# Zokai Station — Host URL Watcher (Windows)
# Polls the shared .open-url-queue file and opens URLs in the system browser.
#
# The vs-code container's url-relay.py writes to scripts/.open-url-queue
# via the bind-mounted scripts/ volume. This script detects changes and
# opens the URL in the Windows host browser using Start-Process.
#
# Started automatically by install-free.ps1 as a background job.
# Stays running as long as the terminal/session is alive.

param(
    [string]$InstallDir = ""
)

# Resolve the queue file path
if ($InstallDir -eq "") {
    $InstallDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$QueueFile = Join-Path $InstallDir "scripts\.open-url-queue"

Write-Host "[url-watcher] Watching for OAuth URLs..."
Write-Host "[url-watcher] Queue file: $QueueFile"

while ($true) {
    try {
        if (Test-Path $QueueFile) {
            $url = (Get-Content $QueueFile -Raw -ErrorAction SilentlyContinue).Trim()
            if ($url -and $url.StartsWith("https://")) {
                Write-Host "[url-watcher] Opening: $($url.Substring(0, [Math]::Min(80, $url.Length)))..."
                Start-Process $url
                # Clear the queue file immediately after opening
                "" | Set-Content $QueueFile -Encoding UTF8
            }
        }
    } catch {
        # Silently ignore file access errors (container may be writing)
    }
    Start-Sleep -Milliseconds 300
}
