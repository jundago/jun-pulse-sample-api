# CLAUDE.md

Guidance for Claude Code in this repository. The Core-Product `CLAUDE.md` (one level up in the local
workspace) applies as well.

## What this is

The Jundago Pulse **sample API**: a small ASP.NET Core app (.NET 10) instrumented with the
OpenTelemetry SDK, used to validate a Pulse installation and to demo it. It is not product code.
Carved out of `rootvyana/contoso-pizza-observability` (the app only, with history) on 2026-09-27;
the ContosoPizza name is kept on purpose because Pulse's pages and the pilot record use these routes.

## Planes and modules (Jundago platform)

Every Jundago screen and route belongs to one **plane**, decided by who calls it: **staff** → `platform-admin`; **a tenant's admins and members** → their org's Command Center (`command-center`, or `devops-center` for deployments); **an agent in the customer's account** → the operator routes; **signed out** → `jun-portal`. The planes share no principal, and on-prem is the tenant plane only. The module map and the canonical table live in one place — [`jun-platform/CLAUDE.md` → "Products, planes and modules — at a glance"](https://github.com/jundago/jun-platform/blob/main/CLAUDE.md#products-planes-and-modules--at-a-glance) (authority: its ADR 0003 and ADR 0002). Do not copy it here.

**This repo:** **not a platform product.** It is a sample app used to demo and validate Pulse.

## Commands

```bash
dotnet build
dotnet run --launch-profile http      # http://localhost:5176
dotnet publish -c Release -o out      # what the install guides deploy
pwsh scripts/generate-traffic.ps1     # drives the four routes
```

## Rules

- **It stays a sample.** No dependency on `jun-collector` or `jun-pulse`; it reaches the agent only
  through the three standard `OTEL_EXPORTER_*` variables. No agent code here, no Pulse code here.
- **Keep the routes and their behaviour.** `weatherforecast`, `api/incidents/{slow,crash,upstream}`
  are what Pulse's pages, tests and the pilot record refer to. Add routes; do not rename or change
  what these do.
- **Keep it installable by a stranger.** Every change to hosting or configuration updates the
  Windows Server (IIS) and Linux (systemd) guides in `README.md`, and the guides are re-run, not
  just re-read.
- **Instrumentation is the OpenTelemetry SDK, standard packages only.** The resource carries
  `service.name` and `service.instance.id = <machine>:<pid>`; that entity-level join is what Pulse
  relies on. Do not add a vendor SDK.
- Work on a named branch; `main` takes PRs. Conventional Commits, no AI trailers.
