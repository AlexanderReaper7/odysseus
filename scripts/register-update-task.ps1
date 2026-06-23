<#
.SYNOPSIS
  Register a Windows Scheduled Task to run the update script automatically.

.DESCRIPTION
  This helper creates or updates a scheduled task that runs
  .\scripts\update-from-upstream.ps1 on a schedule.

.PARAMETER TaskName
  Name of the scheduled task. Defaults to 'Odysseus Update from Upstream'.

.PARAMETER RepoPath
  Path to the Odysseus repository. Defaults to the current directory.

.PARAMETER Schedule
  Schedule frequency: 'Daily', 'Weekly', or 'Hourly'. Defaults to 'Daily'.

.PARAMETER StartTime
  Local time to start the task. Defaults to '03:00'.

.EXAMPLE
  .\scripts\register-update-task.ps1
#>

[CmdletBinding()]
param(
    [string]$TaskName = 'Odysseus Update from Upstream',
    [string]$RepoPath = (Get-Location).Path,
    [ValidateSet('Daily','Weekly','Hourly')]
    [string]$Schedule = 'Daily',
    [string]$StartTime = '03:00'
)

Set-StrictMode -Version Latest

$scriptPath = Join-Path $RepoPath 'scripts\update-from-upstream.ps1'
if (-not (Test-Path $scriptPath)) {
    throw "Cannot find update script at $scriptPath"
}

$action = New-ScheduledTaskAction -Execute 'pwsh.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`" -RepoPath `"$RepoPath`"" -WorkingDirectory $RepoPath
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
$trigger = switch ($Schedule) {
    'Daily' { New-ScheduledTaskTrigger -Daily -At $StartTime }
    'Weekly' { New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At $StartTime }
    'Hourly' { New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration ([TimeSpan]::MaxValue) }
}

try {
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Force -ErrorAction Stop
    Write-Host "Scheduled task '$TaskName' registered. Runs '$scriptPath' $Schedule at $StartTime."
} catch {
    Write-Error "Failed to register scheduled task '$TaskName': $($_.Exception.Message)"
    Write-Error "Run this script in an elevated PowerShell session (Run as Administrator) and try again."
    exit 1
}
