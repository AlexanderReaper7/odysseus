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
    [string]$RepoPath = $PSScriptRoot,
    [string]$UpstreamRemote = 'upstream',
    [string]$OriginRemote = 'origin',
    [string]$BaseBranch = 'dev',
    [string]$PersonalBranch = 'personal-changes',
    [switch]$NoPush,
    [switch]$NoDeploy,
    [switch]$NoPrune
)

Set-StrictMode -Version Latest

function Abort-WithMessage {
    param([string]$Message)
    Write-Error $Message
    exit 1
}

Push-Location $RepoPath
try {
    if (-not (Test-Path '.git')) {
        Abort-WithMessage "This directory is not a git repository: $RepoPath"
    }

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
finally {
    Pop-Location
}
