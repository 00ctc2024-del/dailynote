param(
    [string]$TaskName = 'DailyNote_Rollover',
    [string]$BasePath = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path -Path $BasePath -ChildPath 'manage_today.ps1'
if (-not (Test-Path -Path $scriptPath)) {
    throw ('manage_today.ps1 was not found: ' + $scriptPath)
}

function Register-WithSchtasks {
    param(
        [string]$BaseTaskName,
        [string]$Script,
        [string]$RootPath
    )

    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $taskRun = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$Script`" -BasePath `"$RootPath`""

    $taskNameLogon = $BaseTaskName + '_Logon'
    $taskNameDaily = $BaseTaskName + '_Daily'

    $argsLogon = @('/Create', '/TN', $taskNameLogon, '/SC', 'ONLOGON', '/TR', $taskRun, '/F', '/RL', 'LIMITED')
    $argsDaily = @('/Create', '/TN', $taskNameDaily, '/SC', 'DAILY', '/ST', '00:01', '/TR', $taskRun, '/F', '/RL', 'LIMITED')

    if ($currentUser) {
        $argsLogon += @('/RU', $currentUser)
        $argsDaily += @('/RU', $currentUser)
    }

    & schtasks.exe @argsLogon 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to create ONLOGON task via schtasks.exe.'
    }

    & schtasks.exe @argsDaily 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to create DAILY task via schtasks.exe.'
    }

    Write-Output ("Tasks '" + $taskNameLogon + "' and '" + $taskNameDaily + "' have been registered.")
}

function Register-WithStartupFolder {
    param(
        [string]$Script,
        [string]$RootPath
    )

    $watcherScript = Join-Path -Path $RootPath -ChildPath 'daily_note_watcher.ps1'
    if (-not (Test-Path -Path $watcherScript)) {
        throw ('Watcher script was not found: ' + $watcherScript)
    }

    $startupDir = [Environment]::GetFolderPath('Startup')
    if (-not $startupDir) {
        throw 'Startup folder path could not be resolved.'
    }

    $launcherPath = Join-Path -Path $startupDir -ChildPath 'DailyNoteWatcher.vbs'
    $escapedWatcher = $watcherScript.Replace('"', '""')
    $escapedRoot = $RootPath.Replace('"', '""')

    $launcherContent = @(
        'Set shell = CreateObject("WScript.Shell")',
        'shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""' + $escapedWatcher + '"" -BasePath ""' + $escapedRoot + '""", 0, False'
    )

    Set-Content -Path $launcherPath -Value $launcherContent -Encoding ASCII
    Write-Output ("Startup launcher has been created: " + $launcherPath)
}

$escapedScript = $scriptPath.Replace("'", "''")
$command = "& '$escapedScript' -BasePath '$BasePath'"

try {
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -Command $command"
    $triggerAtLogon = New-ScheduledTaskTrigger -AtLogOn
    $triggerDaily = New-ScheduledTaskTrigger -Daily -At '00:01'
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    $principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($triggerAtLogon, $triggerDaily) -Settings $settings -Principal $principal -Force -ErrorAction Stop | Out-Null
    Write-Output ("Task '" + $TaskName + "' has been registered.")
}
catch {
    try {
        Register-WithSchtasks -BaseTaskName $TaskName -Script $scriptPath -RootPath $BasePath
    }
    catch {
        Register-WithStartupFolder -Script $scriptPath -RootPath $BasePath
    }
}
