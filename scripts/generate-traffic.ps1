# Drives the sample API so every Pulse page has something to show. Not elevated.
# Each round hits the four routes: a healthy one, a slow one, one that throws, and
# one whose upstream is unreachable. Failures on crash/upstream are the point.
param([int]$Rounds = 25, [string]$BaseUrl = 'http://127.0.0.1:5176')

$routes = @('/weatherforecast', '/api/incidents/slow', '/api/incidents/crash', '/api/incidents/upstream')
$counts = @{}
foreach ($r in $routes) { $counts[$r] = @{ ok = 0; failed = 0 } }

1..$Rounds | ForEach-Object {
    foreach ($r in $routes) {
        try {
            Invoke-WebRequest "$BaseUrl$r" -UseBasicParsing -TimeoutSec 10 | Out-Null
            $counts[$r].ok++
        } catch {
            $counts[$r].failed++
        }
        Start-Sleep -Milliseconds 120
    }
}

foreach ($r in $routes) {
    $c = $counts[$r]
    Write-Host ("{0,-28} {1,4} ok  {2,4} failed" -f $r, $c.ok, $c.failed)
}
Write-Host "Expected: weatherforecast and slow succeed; crash and upstream fail. Now check Pulse." -ForegroundColor Green
