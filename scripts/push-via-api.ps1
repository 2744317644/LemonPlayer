$ErrorActionPreference = 'Stop'
$env:HTTPS_PROXY = 'http://127.0.0.1:7890'
$env:HTTP_PROXY = 'http://127.0.0.1:7890'

$Owner = '2744317644'
$Repo = 'LemonPlayer'
$Branch = 'main'
$Remote = 'origin'

$repoRoot = Split-Path $PSScriptRoot -Parent
Set-Location $repoRoot

function Invoke-Api {
    param([string]$Method, [string]$Endpoint, [string]$Json)
    $tmp = Join-Path $env:TEMP ("ghapi-" + [guid]::NewGuid().ToString('N') + ".json")
    [IO.File]::WriteAllText($tmp, $Json, (New-Object System.Text.UTF8Encoding($false)))
    try {
        return gh api -X $Method $Endpoint --input $tmp
    } finally {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
}

$remoteSha = (git rev-parse "$Remote/$Branch").Trim()
$localSha = (git rev-parse HEAD).Trim()
if ($remoteSha -eq $localSha) { Write-Output "nothing to push"; exit 0 }

$changes = git diff --name-status "$Remote/$Branch" HEAD
if (-not $changes) { Write-Output "no file changes"; exit 0 }

$message = (git log -1 --format=%s).Trim()
$entries = @()

foreach ($line in $changes) {
    if (-not $line.Trim()) { continue }
    $parts = $line -split "`t"
    $status = $parts[0]
    $path = $parts[1]
    if ($status -like 'D*') {
        $entries += [pscustomobject]@{ path = $path; sha = $null }
        continue
    }
    $full = Join-Path $repoRoot $path
    if (-not (Test-Path $full)) { continue }
    $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($full))
    $blobBody = '{"content":"' + $b64 + '","encoding":"base64"}'
    $blob = (Invoke-Api -Method POST -Endpoint "repos/$Owner/$Repo/git/blobs" -Json $blobBody) | ConvertFrom-Json
    $entries += [pscustomobject]@{ path = $path; sha = $blob.sha }
    Write-Output ("blob    " + $path)
}

$baseCommit = (Invoke-Api -Method GET -Endpoint "repos/$Owner/$Repo/git/commits/$remoteSha" -Json '{}') | ConvertFrom-Json
$baseTree = $baseCommit.tree.sha

$treeJson = ($entries | ForEach-Object {
    $shaPart = if ($_.sha) { '"' + $_.sha + '"' } else { 'null' }
    '{"path":' + ($_.path | ConvertTo-Json -Compress) + ',"mode":"100644","type":"blob","sha":' + $shaPart + '}'
}) -join ','
$treeBody = '{"base_tree":"' + $baseTree + '","tree":[' + $treeJson + ']}'
$tree = (Invoke-Api -Method POST -Endpoint "repos/$Owner/$Repo/git/trees" -Json $treeBody) | ConvertFrom-Json
Write-Output ("tree    " + $tree.sha)

$commitBody = '{"message":' + ($message | ConvertTo-Json -Compress) + ',"tree":"' + $tree.sha + '","parents":["' + $remoteSha + '"]}'
$commit = (Invoke-Api -Method POST -Endpoint "repos/$Owner/$Repo/git/commits" -Json $commitBody) | ConvertFrom-Json
Write-Output ("commit  " + $commit.sha)

$refBody = '{"sha":"' + $commit.sha + '","force":false}'
Invoke-Api -Method PATCH -Endpoint "repos/$Owner/$Repo/git/refs/heads/$Branch" -Json $refBody | Out-Null
Write-Output ("pushed  " + $remoteSha + " -> " + $commit.sha)
git fetch $Remote --quiet
