[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PublicRoot,

    [Parameter(Mandatory = $true)]
    [string]$GhPath,

    [string]$Repository = 'LukaDoncicY77/LukaDoncicY77.GitHub.io',

    [string]$Message = ('Site updated: {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')),

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedPublic = (Resolve-Path -LiteralPath $PublicRoot).Path
$deployFilterRoot = Join-Path (Split-Path -Parent $resolvedPublic) '.deploy_git'
if (-not (Test-Path -LiteralPath (Join-Path $deployFilterRoot '.git') -PathType Container)) {
    throw "Hexo deploy cache is missing; cannot reproduce Git text filters: $deployFilterRoot"
}

function Invoke-GitHubJson {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Endpoint,

        [ValidateSet('GET', 'POST', 'PATCH')]
        [string]$Method = 'GET',

        [AllowNull()]
        [object]$Body = $null
    )

    if ($null -eq $Body) {
        $raw = @(& $GhPath api --method $Method $Endpoint)
    }
    else {
        $json = $Body | ConvertTo-Json -Depth 20 -Compress
        $raw = @($json | & $GhPath api --method $Method $Endpoint --input -)
    }

    if ($LASTEXITCODE -ne 0) {
        throw "GitHub API request failed: $Method $Endpoint"
    }

    return (($raw -join [Environment]::NewLine) | ConvertFrom-Json)
}

$ref = Invoke-GitHubJson -Endpoint "repos/$Repository/git/ref/heads/main"
$beforeHash = $ref.object.sha
$commit = Invoke-GitHubJson -Endpoint "repos/$Repository/git/commits/$beforeHash"
$baseTreeHash = $commit.tree.sha
$remoteTree = Invoke-GitHubJson -Endpoint "repos/$Repository/git/trees/$baseTreeHash`?recursive=1"

if ($remoteTree.truncated) {
    throw 'The remote tree response was truncated; refusing a partial API deployment.'
}

$remoteBlobs = @{}
foreach ($item in @($remoteTree.tree | Where-Object { $_.type -eq 'blob' })) {
    $remoteBlobs[$item.path] = $item.sha
}

$localFiles = @(Get-ChildItem -LiteralPath $resolvedPublic -Recurse -File -Force)
$localPaths = @{}
$changedFiles = @()

foreach ($file in $localFiles) {
    $relative = $file.FullName.Substring($resolvedPublic.Length).TrimStart('\', '/').Replace('\', '/')
    $localPaths[$relative] = $true
    $localHash = (& git -C $deployFilterRoot hash-object --path=$relative -- $file.FullName).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($localHash)) {
        throw "Could not calculate Git object hash for $($file.FullName)"
    }

    if (-not $remoteBlobs.ContainsKey($relative) -or $remoteBlobs[$relative] -ne $localHash) {
        $changedFiles += [pscustomobject]@{
            Path = $relative
            File = $file
        }
    }
}

$deletedPaths = @($remoteBlobs.Keys | Where-Object { -not $localPaths.ContainsKey($_) } | Sort-Object)

if ($changedFiles.Count -eq 0 -and $deletedPaths.Count -eq 0) {
    Write-Host 'GitHub Pages main already matches the generated public folder.' -ForegroundColor Green
    Write-Host "Remote main: $beforeHash"
    return
}

$oversizedFallback = @($changedFiles | Where-Object { $_.File.Length -gt 25MB })
if ($oversizedFallback.Count -gt 0) {
    $paths = $oversizedFallback.Path -join [Environment]::NewLine
    throw "API fallback refuses changed files above 25 MiB; use normal Git transport for these files:`n$paths"
}

if ($DryRun) {
    Write-Host 'GitHub API deployment dry run passed.' -ForegroundColor Green
    Write-Host "Remote main: $beforeHash"
    Write-Host "Changed files: $($changedFiles.Count)"
    $changedFiles | ForEach-Object { Write-Host "  change $($_.Path)" }
    Write-Host "Deleted files: $($deletedPaths.Count)"
    $deletedPaths | ForEach-Object { Write-Host "  delete $_" }
    return
}

$treeEntries = [System.Collections.Generic.List[object]]::new()
foreach ($change in $changedFiles) {
    $bytes = [System.IO.File]::ReadAllBytes($change.File.FullName)
    $blob = Invoke-GitHubJson -Endpoint "repos/$Repository/git/blobs" -Method POST -Body @{
        content = [Convert]::ToBase64String($bytes)
        encoding = 'base64'
    }
    $treeEntries.Add([pscustomobject]@{
        path = $change.Path
        mode = '100644'
        type = 'blob'
        sha = $blob.sha
    })
    Write-Host "Prepared changed file: $($change.Path)"
}

foreach ($path in $deletedPaths) {
    $treeEntries.Add([pscustomobject]@{
        path = $path
        mode = '100644'
        type = 'blob'
        sha = $null
    })
    Write-Host "Prepared deletion: $path"
}

$newTree = Invoke-GitHubJson -Endpoint "repos/$Repository/git/trees" -Method POST -Body @{
    base_tree = $baseTreeHash
    tree = @($treeEntries)
}

$newCommit = Invoke-GitHubJson -Endpoint "repos/$Repository/git/commits" -Method POST -Body @{
    message = $Message
    tree = $newTree.sha
    parents = @($beforeHash)
}

$updatedRef = Invoke-GitHubJson -Endpoint "repos/$Repository/git/refs/heads/main" -Method PATCH -Body @{
    sha = $newCommit.sha
    force = $false
}

$afterHash = $updatedRef.object.sha
if ($afterHash -ne $newCommit.sha) {
    throw 'GitHub API returned an unexpected main-branch commit after deployment.'
}

Write-Host ''
Write-Host 'Approved API deployment completed.' -ForegroundColor Green
Write-Host "Changed files: $($changedFiles.Count)"
Write-Host "Deleted files: $($deletedPaths.Count)"
Write-Host "Remote main before: $beforeHash"
Write-Host "Remote main after:  $afterHash"
