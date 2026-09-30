# ContosoPizza: the Jundago Pulse sample API

A small ASP.NET Core API, instrumented with the OpenTelemetry SDK, that exists to **validate a Pulse
installation and to demo it**. Install it next to a Pulse agent, point it at the agent with three
environment variables, drive some traffic, and every Pulse page has something to show. It has no
knowledge of the agent and the agent has none of it.

Carved out of `contoso-pizza-observability` (the app only, with history) on 2026-09-27.
The name stays: Pulse's pages and the Plan A pilot record already speak about these routes.

## Routes

| Route | What it does | What Pulse shows |
|---|---|---|
| `GET /weatherforecast` | a normal, fast answer | a healthy route |
| `GET /api/incidents/slow` | answers after a delay | a slow route; p95/p99 rise |
| `GET /api/incidents/crash` | throws inside the process | 500s; an error trace with the exception |
| `GET /api/incidents/upstream` | calls an unreachable upstream | 502-class errors; a client span to the dead peer; a network flow to `127.0.0.1:9` |

Telemetry: traces (ASP.NET Core and HttpClient instrumentation, exceptions recorded), logs and
runtime metrics, all exported over OTLP/HTTP. The service appears in Pulse as `ContosoPizza`, with
`service.instance.id = <machine>:<pid>`, which is the entity-level join Pulse uses.

## Point it at the agent

**On the agent's own machine (agent 0.5.0 or newer): nothing to set.** The agent's installer sets
`OTEL_EXPORTER_OTLP_ENDPOINT` and `OTEL_EXPORTER_OTLP_PROTOCOL` machine-wide, and the agent takes
telemetry from processes on its own machine without the probe key. Start the app from a **new**
shell or session (a shell that was open before the agent was installed keeps its old environment;
under IIS, recycle the application pool). Measured on the pilot server 2026-09-30: a new
PowerShell window saw the variables at once, no sign-out or reboot.

**On another machine, or when the agent was installed with `TRUSTLOOPBACK=0`, or with agent 0.4.0:**
three standard variables, no code change. `<agent>` is the machine running the Pulse agent; the
port is the one the agent listens on (`5202` in Pulse's Add-collector script; the agent's built-in
default is `5200`); the probe key is the one Pulse's Add-collector dialog generated for the site.

```
OTEL_EXPORTER_OTLP_ENDPOINT=http://<agent>:5202
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
OTEL_EXPORTER_OTLP_HEADERS=X-Probe-Key=<probe key>
```

An app that sets only its own endpoint still inherits the machine-level protocol; set all three
when you set any.

## Install on Windows Server

Prerequisites: Windows Server 2019 or later; the .NET 10 SDK to build (or build elsewhere and copy
the published folder); for IIS, the **.NET Hosting Bundle** (installs the ASP.NET Core Module).

### A. Under IIS (the production shape)

```powershell
# 1. Publish (from a clone of this repository)
dotnet publish -c Release -o C:\inetpub\ContosoPizza

# 2. Site and application pool (or do the same in IIS Manager)
Import-Module WebAdministration
New-WebAppPool -Name ContosoPizza
Set-ItemProperty IIS:\AppPools\ContosoPizza -Name managedRuntimeVersion -Value ""   # "No Managed Code"
New-Website -Name ContosoPizza -Port 5176 -PhysicalPath C:\inetpub\ContosoPizza -ApplicationPool ContosoPizza
```

3. Give the site the three variables. The ASP.NET Core Module reads them from `web.config`, so
   with agent 0.5.0 or newer on this machine, nothing: the machine-level defaults apply to the
   application pool after a recycle. Otherwise (another machine, `TRUSTLOOPBACK=0`, or agent
   0.4.0) edit `C:\inetpub\ContosoPizza\web.config` and add inside `<aspNetCore …>`:

```xml
<environmentVariables>
  <environmentVariable name="OTEL_EXPORTER_OTLP_ENDPOINT" value="http://127.0.0.1:5202" />
  <environmentVariable name="OTEL_EXPORTER_OTLP_PROTOCOL" value="http/protobuf" />
  <environmentVariable name="OTEL_EXPORTER_OTLP_HEADERS"  value="X-Probe-Key=<probe key>" />
</environmentVariables>
```

4. Recycle: `Restart-WebAppPool ContosoPizza`. Check `http://localhost:5176/weatherforecast`.

### B. From a console (a quick test, what the pilot did)

On the agent's machine with agent 0.5.0 or newer, from a shell opened after the agent was installed:

```powershell
dotnet run --launch-profile http      # listens on http://localhost:5176; the machine defaults do the rest
```

Anywhere else (or with `TRUSTLOOPBACK=0`, or agent 0.4.0):

```powershell
$env:OTEL_EXPORTER_OTLP_ENDPOINT = "http://127.0.0.1:5202"
$env:OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf"
$env:OTEL_EXPORTER_OTLP_HEADERS  = "X-Probe-Key=<probe key>"
dotnet run --launch-profile http
```

Running it as a Windows service needs `UseWindowsService()` in `Program.cs`, which the sample does
not have yet; use IIS for anything that must survive a reboot.

## Install on Linux

```bash
dotnet publish -c Release -o /opt/contosopizza
sudo tee /etc/systemd/system/contosopizza.service >/dev/null <<'EOF'
[Unit]
Description=ContosoPizza (Jundago Pulse sample API)
After=network.target

[Service]
WorkingDirectory=/opt/contosopizza
ExecStart=/usr/bin/dotnet /opt/contosopizza/ContosoPizza.dll
Environment=ASPNETCORE_URLS=http://0.0.0.0:5176
Environment=OTEL_EXPORTER_OTLP_ENDPOINT=http://<agent>:5202
Environment=OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
Environment=OTEL_EXPORTER_OTLP_HEADERS=X-Probe-Key=<probe key>
# The three variables stay on Linux: the agent's Linux package (Phase 2) is not out yet, so the
# agent is on another machine and the key is required.
Restart=always
User=www-data

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload && sudo systemctl enable --now contosopizza
curl -s http://localhost:5176/weatherforecast
```

## Drive traffic

The script lives in this repo under `scripts/`; a published copy of the app on a server does not
carry it, so clone the repo there or run the four routes inline (`/weatherforecast`,
`/api/incidents/slow`, `/api/incidents/crash`, `/api/incidents/upstream`, 25 rounds).

```powershell
scripts\generate-traffic.ps1                       # 25 rounds against http://127.0.0.1:5176
scripts\generate-traffic.ps1 -Rounds 100 -BaseUrl http://server-01:5176
```

Each round hits the four routes, so the healthy, slow, crashing and upstream-failure shapes all show.

## What you should see in Pulse

- **Collectors:** the agent Online, `records delivered` rising within seconds of the first round.
- **API Monitoring:** service `ContosoPizza`; routes `WeatherForecast`, `api/incidents/slow`,
  `api/incidents/crash`, `api/incidents/upstream`; error rate on `crash` and `upstream`; `slow` at
  the top of latency.
- **Route detail → `crash`:** 500s, recent traces with the exception, the logs from those requests.
- **Traces:** a trace per request; `upstream` carries a client span to the dead peer.
- **Network** (with a probe on the server): connections from the app to `127.0.0.1:9` for
  `upstream`.

If Collectors shows nothing: the agent's `/status` (`spans_received`) says whether the app reached
it, and its `intake` object says whether local senders are trusted (`trust_loopback`) and whether
an allow-list is set (`loopback_processes`). In the agent's log, a wrong probe key is a 401
`invalid probe key`; a local process that is not on the pushed allow-list is a 401 `local sender not
allowed`; 429 and 403 are the per-service rate limit and the services-per-day cap.

## Development

```bash
dotnet run --launch-profile http     # http://localhost:5176, OTLP to whatever the variables say
```

`ContosoPizza.http` has requests for every route. There are no tests; the sample is verified by
installing it and comparing Pulse's pages to the agent's counters.
