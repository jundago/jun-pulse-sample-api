# Quick setup

Two windows. The app blocks in the first, so traffic and checks go in the second.

Full install guides (IIS, systemd) are in [README.md](README.md); this is the
run-it-on-your-desk path.

---

## Before you start

**Open a new shell.** If the Pulse agent was installed after your terminal was opened,
that terminal still has the old environment and the app will export to nowhere — with
no error, because an OTLP exporter with no endpoint fails quietly.

Check the shell can see the agent:

```powershell
$env:OTEL_EXPORTER_OTLP_ENDPOINT     # expect http://127.0.0.1:5202
$env:OTEL_EXPORTER_OTLP_PROTOCOL     # expect http/protobuf
```

Blank means the shell is stale, not that the agent is broken. Open another one.

On the agent's own machine (0.5.0+) that is all — no probe key, because the agent
trusts local senders. Confirm with `trust_loopback`:

```powershell
(Invoke-RestMethod http://127.0.0.1:5202/status).intake
```

Elsewhere, or with `TRUSTLOOPBACK=0`, set the three variables from README.md instead.

---

## 1. Window one — the app

```powershell
cd <path-to>\jun-pulse-sample-api
dotnet run --launch-profile http
```

Leave it running. It listens on <http://localhost:5176>.

---

## 2. Window two — note the counters, drive traffic, compare

```powershell
cd <path-to>\jun-pulse-sample-api

# Before, so the delta is unambiguous.
(Invoke-RestMethod http://127.0.0.1:5202/status).health |
    Select-Object spans_received, logs_received

# 10 rounds x 4 routes = 40 requests, about 20 seconds.
# The default is 25 rounds (~50s); pass -Rounds to change it.
.\scripts\generate-traffic.ps1 -Rounds 10

# The agent batches, so give it a moment before reading again.
Start-Sleep 45

(Invoke-RestMethod http://127.0.0.1:5202/status).health |
    Select-Object spans_received, logs_received, otlp_rejected, otlp_throttled,
                  otlp_services_rejected, otlp_services_today,
                  delivery_failures, spool_segments_pending
```

`pwsh` is not installed on every machine; Windows PowerShell runs the script fine.

### Expected

```
/weatherforecast               10 ok     0 failed
/api/incidents/slow            10 ok     0 failed
/api/incidents/crash            0 ok    10 failed     <- 500, on purpose
/api/incidents/upstream         0 ok    10 failed     <- 502, on purpose
```

`crash` and `upstream` failing **is the test**. A run where all four succeed means the
failure routes are not doing their job.

Roughly 50 spans from 40 requests, because each `upstream` call carries a child span
for the unreachable peer. Every rejection counter stays at 0, and
`spool_segments_pending` returns to 0 within a few seconds of each flush.

---

## 3. Read the result

| Counter | What a non-zero value means |
|---|---|
| `spans_received` | the app reached the agent — **this is the hop most setups get wrong** |
| `logs_received` | the logging provider is exporting too |
| `otlp_rejected` | the agent refused a payload: usually a wrong probe key (401) |
| `otlp_throttled` | per-service rate limit (429) |
| `otlp_services_rejected` | services-per-day cap (403) |
| `otlp_services_today` | distinct services seen today; the sample is 1 |
| `delivery_failures` | the agent could not reach Pulse |
| `spool_segments_pending` | undelivered batches on disk; should return to 0 |

**`spans_received` rising is the whole point of this file.** It separates "my app is
not reaching the agent" from "the agent is not reaching Pulse" — two problems that look
identical on a Pulse page that has nothing on it.

---

## 4. Then check Pulse

- **Collectors** — the agent Online, records delivered rising
- **API Monitoring** — service `ContosoPizza`; `crash` and `upstream` at a 100% error
  rate; `slow` at the top of latency
- **Route detail → `crash`** — 500s, recent traces, and the log lines from those requests
- **Traces** — one per request; `upstream` carries a client span to the dead peer

### If a page looks empty

Check these three before suspecting anything, in order. Each of them produced an empty
Traces page during this sample's own setup:

1. **Is the app running?** Stopping it to rebuild is easy to forget, and a page with no
   recent traffic behind it is correctly empty.
2. **Is the traffic recent enough for the time range?** The Traces page defaults to a
   window (1h / 6h / 24h / 7d). Traffic driven before it is not missing, it is outside
   the range.
3. **Refresh.** The agent batches and the page does not stream; a run that finished
   seconds ago may not be on a view loaded before it.

Only once `spans_received` has risen *and* fresh traffic is inside the window is the
gap downstream of this machine. That distinction matters: "no error in the agent's log"
is not evidence that Pulse received anything, only that the agent did not complain.

---

## Reset

```powershell
# stop the app: Ctrl-C in window one, or
Get-Process ContosoPizza -ErrorAction SilentlyContinue | Stop-Process -Force
```

Counters on `/status` are since the agent last started; restart the service to zero
them:

```powershell
Restart-Service JundagoCollector    # elevated
```
