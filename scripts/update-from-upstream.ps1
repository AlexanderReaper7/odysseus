<#
.SYNOPSIS
  Update the repository from the official upstream and merge upstream changes into your personal branch.

.DESCRIPTION
  This script uses a merge-based workflow for stability and easier conflict recovery.
  It fetches from the upstream remote, merges upstream/dev into dev, then merges dev into your personal branch.

.PARAMETER RepoPath
  Path to the repository root. Defaults to the current directory.

.PARAMETER UpstreamRemote
  Name of the official upstream remote. Defaults to 'upstream'.

.PARAMETER OriginRemote
  Name of your fork remote. Defaults to 'origin'.

.PARAMETER BaseBranch
  Branch to sync from upstream. Defaults to 'dev'.

.PARAMETER PersonalBranch
  Your personal branch. Defaults to 'personal-changes'.

# .PARAMETER NoPush
#  If present, skips pushing updated branches to the origin remote.
# .PARAMETER NoDeploy
#  If present, skips Docker deployment after repository update.
# .PARAMETER NoPrune
#  If present, skips Docker image pruning after deployment.

#.EXAMPLE
#  .\scripts\update-from-upstream.ps1
#  .\scripts\update-from-upstream.ps1 -NoPush
#  .\scripts\update-from-upstream.ps1 -NoDeploy
#>

[CmdletBinding()]
param(
    [string]$RepoPath = (Split-Path $PSScriptRoot -Parent),
    [string]$UpstreamRemote = 'upstream',
    [string]$OriginRemote = 'origin',
    [string]$BaseBranch = 'dev',
    [string]$PersonalBranch = 'personal-changes',
    [switch]$NoPush,
    [switch]$NoDeploy,
    [switch]$NoPrune
)

Set-StrictMode -Version Latest

function Show-ErrorDialog {
    param([string]$Message)
    try {
        Add-Type -AssemblyName PresentationFramework | Out-Null
        [System.Windows.MessageBox]::Show($Message, 'Odysseus Update Failed', 'OK', 'Error') | Out-Null
    } catch {
        try {
            $wshell = New-Object -ComObject WScript.Shell
            $wshell.Popup($Message, 0, 'Odysseus Update Failed', 0x10) | Out-Null
        } catch {
            # ignore if UI cannot be shown
        }
    }
}

function Abort-WithMessage {
    param([string]$Message)
    Write-Error "ERROR: $Message"
    Show-ErrorDialog $Message
    exit 1
}

$RepoPath = Resolve-Path -Path $RepoPath -ErrorAction Stop | Select-Object -ExpandProperty Path
Write-Host "Resolved repository path: $RepoPath"

Push-Location $RepoPath
try {
    if (-not (Test-Path '.git')) {
        Abort-WithMessage "This directory is not a git repository: $RepoPath"
    }

    $gitTop = git rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0) {
        Abort-WithMessage "Failed to determine git repository top level. Is this a git repo?"
    }
    $gitTop = (Resolve-Path -Path $gitTop -ErrorAction Stop).Path
    if ($gitTop -ne $RepoPath) {
        Abort-WithMessage "The script resolved to '$RepoPath', but git repo root is '$gitTop'. Run the script from the repository root or set -RepoPath explicitly."
    }

    Write-Host "Confirmed repository root: $RepoPath"
    Write-Host "Checking repository status..."
    $status = git status --porcelain
    if ($status) {
        Abort-WithMessage "Working directory is not clean. Commit or stash your changes before running this script.\n$status"
    }

    Write-Host "Fetching upstream and origin..."
    git remote get-url $UpstreamRemote > $null 2>&1 || Abort-WithMessage "Remote '$UpstreamRemote' does not exist. Add it with 'git remote add $UpstreamRemote <url>'."
    git remote get-url $OriginRemote > $null 2>&1 || Abort-WithMessage "Remote '$OriginRemote' does not exist. Add it with 'git remote add $OriginRemote <url>'."

    git fetch $UpstreamRemote || Abort-WithMessage "Failed to fetch from '$UpstreamRemote'."
    git fetch $OriginRemote || Abort-WithMessage "Failed to fetch from '$OriginRemote'."

    Write-Host "Updating '$BaseBranch' from '$UpstreamRemote/$BaseBranch'..."
    git checkout $BaseBranch || Abort-WithMessage "Failed to checkout branch '$BaseBranch'."
    git merge --no-ff "$UpstreamRemote/$BaseBranch" -m "Merge $UpstreamRemote/$BaseBranch into $BaseBranch" || Abort-WithMessage "Merge failed on branch '$BaseBranch'. Resolve conflicts manually and rerun."

    if (-not $NoPush) {
        Write-Host "Pushing updated '$BaseBranch' to '$OriginRemote'..."
        git push $OriginRemote $BaseBranch || Abort-WithMessage "Failed to push '$BaseBranch' to '$OriginRemote'."
    }

    Write-Host "Updating personal branch '$PersonalBranch' from '$BaseBranch'..."
    git checkout $PersonalBranch || Abort-WithMessage "Failed to checkout branch '$PersonalBranch'."
    git merge --no-ff $BaseBranch -m "Merge $BaseBranch into $PersonalBranch" || Abort-WithMessage "Merge failed on branch '$PersonalBranch'. Resolve conflicts manually and rerun."

    if (-not $NoPush) {
        Write-Host "Pushing updated '$PersonalBranch' to '$OriginRemote'..."
        git push $OriginRemote $PersonalBranch || Abort-WithMessage "Failed to push '$PersonalBranch' to '$OriginRemote'."
    }

    if (-not $NoDeploy) {
        Write-Host "Deploying Docker containers..."
        Push-Location $RepoPath
        try {
            docker compose up -d --build || Abort-WithMessage "Docker compose deploy failed."
            if (-not $NoPrune) {
                Write-Host "Pruning dangling Docker images..."
                docker image prune -f || Abort-WithMessage "Docker image prune failed."
            }
        }
        finally {
            Pop-Location
        }
    }

    Write-Host "Update complete. Current branch: $(git branch --show-current)"
}
catch {
    Write-Error "Fatal error: $($_.Exception.Message)"
    exit 1
}
finally {
    Pop-Location
}
