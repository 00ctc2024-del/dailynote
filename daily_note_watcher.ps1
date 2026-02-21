param(
    [string]$BasePath = $PSScriptRoot,
    [int]$IntervalSeconds = 60
)

$ErrorActionPreference = 'SilentlyContinue'

if ($IntervalSeconds -lt 10) {
    $IntervalSeconds = 10
}

$managerScript = Join-Path -Path $BasePath -ChildPath 'manage_today.ps1'
if (-not (Test-Path -Path $managerScript)) {
    exit 1
}

while ($true) {
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $managerScript -BasePath $BasePath | Out-Null
    }
    catch {
    }

    Start-Sleep -Seconds $IntervalSeconds
}
