param(
    [Parameter(Mandatory = $true)]
    [string]$Token,

    [string]$Owner = '',
    [string]$Repo = 'video-rotate-portable',
    [string]$ReleaseTag = 'v1.0.0',
    [string]$ReleaseName = 'Video Rotate Portable v1.0.0',
    [string]$AssetPath = 'C:\Users\home\Documents\Codex\2026-06-20\new-chat\outputs\VideoRotatePortable.zip'
)

$ErrorActionPreference = 'Stop'

function Invoke-GitHubJson {
    param(
        [string]$Method,
        [string]$Uri,
        [object]$Body = $null
    )

    $headers = @{
        Authorization = "Bearer $Token"
        Accept = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
        'User-Agent' = 'VideoRotatePortablePublisher'
    }

    if ($null -eq $Body) {
        return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers
    }

    return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers -Body ($Body | ConvertTo-Json -Depth 10) -ContentType 'application/json'
}

if (-not (Test-Path -LiteralPath $AssetPath)) {
    throw "Release asset not found: $AssetPath"
}

$user = Invoke-GitHubJson -Method GET -Uri 'https://api.github.com/user'
if ([string]::IsNullOrWhiteSpace($Owner)) {
    $Owner = $user.login
}

$repoFullName = "$Owner/$Repo"

try {
    $repoInfo = Invoke-GitHubJson -Method GET -Uri "https://api.github.com/repos/$repoFullName"
    Write-Host "Repository exists: $repoFullName"
} catch {
    Write-Host "Creating repository: $Repo"
    $repoInfo = Invoke-GitHubJson -Method POST -Uri 'https://api.github.com/user/repos' -Body @{
        name = $Repo
        description = 'Portable Windows GUI for adding video rotation metadata without re-encoding.'
        private = $false
        has_issues = $true
        has_projects = $false
        has_wiki = $false
    }
}

git branch -M main
if ((git remote) -contains 'origin') {
    git remote remove origin
}
git remote add origin "https://$Token@github.com/$repoFullName.git"
git push -u origin main

$releaseBody = @"
Initial public release of Video Rotate Portable.

- Portable Windows GUI
- Includes FFmpeg in the release ZIP
- Batch queue
- Per-file rotation assignment
- English/Korean UI
- Stream-copy metadata rotation without re-encoding
"@

try {
    $release = Invoke-GitHubJson -Method GET -Uri "https://api.github.com/repos/$repoFullName/releases/tags/$ReleaseTag"
    Write-Host "Release exists: $ReleaseTag"
} catch {
    $release = Invoke-GitHubJson -Method POST -Uri "https://api.github.com/repos/$repoFullName/releases" -Body @{
        tag_name = $ReleaseTag
        target_commitish = 'main'
        name = $ReleaseName
        body = $releaseBody
        draft = $false
        prerelease = $false
    }
}

$assetName = [System.IO.Path]::GetFileName($AssetPath)
$uploadUrl = ($release.upload_url -replace '\{\?name,label\}', '') + "?name=$([uri]::EscapeDataString($assetName))"

$headers = @{
    Authorization = "Bearer $Token"
    Accept = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
    'User-Agent' = 'VideoRotatePortablePublisher'
}

$existingAssets = Invoke-GitHubJson -Method GET -Uri "https://api.github.com/repos/$repoFullName/releases/$($release.id)/assets"
foreach ($asset in $existingAssets) {
    if ($asset.name -eq $assetName) {
        Invoke-GitHubJson -Method DELETE -Uri "https://api.github.com/repos/$repoFullName/releases/assets/$($asset.id)" | Out-Null
    }
}

Invoke-RestMethod -Method POST -Uri $uploadUrl -Headers $headers -ContentType 'application/zip' -InFile $AssetPath | Out-Null

git remote set-url origin "https://github.com/$repoFullName.git"

Write-Host "Published repository: https://github.com/$repoFullName"
Write-Host "Published release: https://github.com/$repoFullName/releases/tag/$ReleaseTag"
