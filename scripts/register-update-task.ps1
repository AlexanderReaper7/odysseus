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
$trigger = switch ($Schedule) {
    'Daily' { New-ScheduledTaskTrigger -Daily -At $StartTime }
    'Weekly' { New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At $StartTime }
    'Hourly' { New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration ([TimeSpan]::MaxValue) }
}

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -User $env:USERNAME -RunLevel Highest -Force
Write-Host "Scheduled task '$TaskName' registered. Runs '$scriptPath' $Schedule at $StartTime."
