# Get version param
param (
    [string]$Version,
    [nullable[bool]]$PostRelease
)

# Configuration
$Username = "Lyall"
$RepoName = "P5StrikersFix"
$ProxyName = "dinput8"
$Arch = "x64"
$ZipFolder = "tmp"
$ScriptsFolder = Join-Path $ZipFolder "scripts"

Write-Host "Building release version: $Version"

if ($null -eq $PostRelease) {
    $PostReleaseInput = Read-Host "Post release build? (true/false)"
    $PostRelease = $PostReleaseInput -match '^(true|1)$'
}

# Build
Write-Host "($Arch) Building with xmake..."
xmake f -p windows -a $Arch -m release
xmake build -v

# Download ultimate ASI loader
Write-Host "($Arch) Downloading Ultimate ASI Loader..."

if ($Arch -eq "x86") {
    $asiUrl = "https://github.com/ThirteenAG/Ultimate-ASI-Loader/releases/download/v9.7.0/Ultimate-ASI-Loader.zip"
    $asiZipFile = "Ultimate-ASI-Loader_x86.zip"
} else {
    $asiUrl = "https://github.com/ThirteenAG/Ultimate-ASI-Loader/releases/download/v9.7.0/Ultimate-ASI-Loader_x64.zip"
    $asiZipFile = "Ultimate-ASI-Loader_x64.zip"
}

Invoke-WebRequest -Uri $asiUrl -OutFile $asiZipFile
Expand-Archive -Force $asiZipFile -DestinationPath "." | Out-Null
Remove-Item $asiZipFile

# Prepare temp directory
Write-Host "Preparing temporary directory..."
Remove-Item -Recurse -Force $ZipFolder -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $ScriptsFolder | Out-Null
Copy-Item -Path "build/windows/$Arch/release/*.asi" -Destination $ScriptsFolder/
Copy-Item -Path "*.ini" -Destination $ScriptsFolder/
Move-Item -Path dinput8.dll -Destination $ZipFolder/$ProxyName.dll # ASI loader in root

# Create Reloaded-II zip
$ReloadedZipName = "${RepoName}_Reloaded-II.zip"
$ReloadedZipPath = Join-Path -Path "build" -ChildPath $ReloadedZipName
$ModConfigPath = Join-Path $ScriptsFolder "ModConfig.json"
Copy-Item -Path ".forgejo/r2-package/ModConfig.json" -Destination $ModConfigPath
(Get-Content $ModConfigPath -Raw) -replace '<REPLACE_VERSION>', $Version | Set-Content $ModConfigPath
Write-Host "Creating Reloaded-II zip: $ReloadedZipPath"
Compress-Archive -Path $ScriptsFolder/* -DestinationPath $ReloadedZipPath -Force
Remove-Item -Path $ModConfigPath -ErrorAction SilentlyContinue

# Add LICENSES.txt
Write-Host "Adding LICENSES.txt..."
 
function Format-LicenseSection {
    param($Title, $Text)
    return "================================================================`n$Title`n================================================================`n$Text"
}
 
function Get-RemoteLicense {
    param($Url, $Label)
    try {
        return (Invoke-WebRequest -Uri $Url -UseBasicParsing).Content
    } catch {
        Write-Warning "Could not fetch license for $Label from $Url."
        return "[Could not fetch license for $Label from $Url]"
    }
}

$fixLicense =  Get-Content "LICENSE" -Raw

$thirdPartyLicenses = @(
    @{ Name = "Ultimate ASI Loader"; Url = "https://raw.githubusercontent.com/ThirteenAG/Ultimate-ASI-Loader/master/license" },
    @{ Name = "mINI";                Url = "https://raw.githubusercontent.com/metayeti/mINI/master/LICENSE" },
    @{ Name = "safetyhook";          Url = "https://raw.githubusercontent.com/cursey/safetyhook/main/LICENSE" }
)
 
$sections = @(Format-LicenseSection -Title $RepoName -Text $fixLicense)
$sections += $thirdPartyLicenses | ForEach-Object {
    Format-LicenseSection -Title $_.Name -Text (Get-RemoteLicense -Url $_.Url -Label $_.Name)
}
 
$sections -join "`n`n" | Out-File -FilePath "$ZipFolder/LICENSES.txt" -Encoding utf8

# Create release zip
$ReleaseZipName = "${RepoName}_${Version}.zip"
$ReleaseZipPath = Join-Path -Path "build" -ChildPath $ReleaseZipName
Write-Host "Creating release zip: $ReleaseZipPath"
Compress-Archive -Path $ZipFolder/* -DestinationPath $ReleaseZipPath -Force

# Get release artifacts
$ZipPaths = @($ReleaseZipPath, $ReloadedZipPath)

# Clean up
Write-Host "Cleaning up temp directory..."
Remove-Item -Recurse -Force $ZipFolder

Write-Host "Build $Version completed."

# ---------------------

if ($PostRelease) {
    # Prepare release body
    $ReleaseBodyPath = "release_body.md"
    $ReleaseBody = ""

    if (Test-Path $ReleaseBodyPath) {
        $ReleaseBody = Get-Content $ReleaseBodyPath -Raw
        $ReleaseBody = $ReleaseBody -replace "<RELEASE_ZIP_NAME>", $ReleaseZipName
    }

    function New-Release {
        param (
            $ApiBaseUrl,
            $Owner,
            $Repo,
            $Tag,
            $Name,
            $Body = "",
            [string[]]$AssetPaths,
            $Token,
            $Draft = $false,
            $Prerelease = $false,
            $Platform = "Unknown"
        )

        $headers = @{
            "Authorization" = "token $Token"
            "Accept" = "application/json"
        }

        $releaseUrl = "$ApiBaseUrl/api/v1/repos/$Owner/$Repo/releases"
        $releaseBody = @{
            tag_name = $Tag
            name = $Name
            body = $Body
            draft = $Draft
            prerelease = $Prerelease
        } | ConvertTo-Json

        Write-Host "[$Platform] Creating release $Tag..."
        try {
            $release = Invoke-RestMethod -Uri $releaseUrl -Method Post -Headers $headers -Body $releaseBody -ContentType "application/json"
        } catch {
            Write-Error "[$Platform] Failed to create release: $_"
            return $false
        }

        $allUploaded = $true
        foreach ($assetPath in $AssetPaths) {
            $uploadUrl = "$ApiBaseUrl/api/v1/repos/$Owner/$Repo/releases/$($release.id)/assets?name=$(Split-Path $assetPath -Leaf)"
            Write-Host "[$Platform] Uploading asset: $(Split-Path $assetPath -Leaf)..."

            try {
                $asset = Invoke-RestMethod -Uri $uploadUrl -Method Post -Headers $headers -InFile $assetPath -ContentType "application/octet-stream"
                Write-Host "[$Platform] Uploaded: $($asset.browser_download_url)"
            } catch {
                Write-Error "[$Platform] Failed to upload asset ${assetPath}: $_"
                $allUploaded = $false
            }
        }

        return $allUploaded
    }

    $platforms = @(
        @{ Name = "Forgejo";  Url = $env:FORGEJO_URL;  Token = $env:FORGEJO_TOKEN },
        @{ Name = "Codeberg"; Url = $env:CODEBERG_URL; Token = $env:CODEBERG_TOKEN }
    )

    $success = $true
    $anyConfigured = $false

    foreach ($platform in $platforms) {
        if ($platform.Url -and $platform.Token) {
            $anyConfigured = $true
            $result = New-Release -ApiBaseUrl $platform.Url `
                                  -Owner $Username `
                                  -Repo $RepoName `
                                  -Tag $Version `
                                  -Name $Version `
                                  -Body $ReleaseBody `
                                  -AssetPaths $ZipPaths `
                                  -Token $platform.Token `
                                  -Draft $false `
                                  -Platform $platform.Name
            $success = $success -and $result
        }
    }

    if (-not $anyConfigured) {
        Write-Warning "No release platforms configured (FORGEJO_URL or CODEBERG_URL not set)"
        exit 0
    }

    if (-not $success) {
        Write-Error "One or more releases failed"
        exit 1
    }
}