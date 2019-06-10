# Copyright: (c) 2019, Jordan Borean (@jborean93) <jborean93@gmail.com>
# MIT License (see LICENSE or https://opensource.org/licenses/MIT)

$ErrorActionPreference = 'Stop'

Function Get-PSGalleryNupkgUri {
    [OutputType([System.String])]
    [CmdletBinding()]
    Param (
        [System.String]
        $Name,

        [System.String]
        $Version
    )

    $search_uri = "https://www.powershellgallery.com/api/v2/Packages?`$filter=Id eq '$Name' and Version eq '$Version'"
    try {
        $gallery_meta = Invoke-RestMethod -Uri $search_uri -ErrorAction Stop
    } catch {
        $msg = "Failed to find PowerShell Gallery release for '$Name' at version '$Version': $($_.Exception.Message)"
        Write-Error -Message $msg
        return
    }

    if ($null -eq $gallery_meta) {
        Write-Error -Message "Failed to find PSGallery package info for $Name with the version $Version"
        return
    }

    return $gallery_meta.Content.src
}

Function Publish-GitHubReleaseNupkg {
    [CmdletBinding()]
    Param (
        [System.String]
        $Name,

        [System.String]
        $Version,

        [System.String]
        $Path
    )
    $nupkg_item = Get-Item -Path $Path

    $root_uri = "https://api.github.com/repos/$Name"
    $headers = @{
        Authorization = "token $env:GITHUB_API_TOKEN"
    }

    try {
        $tag_info = Invoke-RestMethod -Uri "$root_uri/releases/tags/$Version" -Headers $headers -ErrorAction Stop`
    } catch {
        Write-Error -Message "Failed to get tag ID for '$Name' with version tag '$Version': $($_.Exception.Message)"
        return
    }
    
    $publish_uri = "https://uploads.github.com/repos/$Name/releases/$($tag_info.id)/assets?name=$($nupkg_item.Name)"
    $headers.'Content-Type' = 'application/octet-stream'
    try {
        Invoke-RestMethod -Uri $publish_uri -Headers $headers -InFile $nupkg_item.FullName > $null
    } catch {
        Write-Error -Message "Failed to upload nupkg to release: $($_.Exception.Message)"
        return
    }
}

$module_name = (Get-ChildItem -Path ([System.IO.Path]::Combine($DeploymentRoot, 'Build', '*', '*.psd1'))).BaseName
$source_path = [System.IO.Path]::Combine($DeploymentRoot, 'Build', $module_name)

$nupkg_version = $env:APPVEYOR_BUILD_VERSION
if ((Test-Path -Path env:APPVEYOR_REPO_TAG) -and ([System.Boolean]::Parse($env:APPVEYOR_REPO_TAG))) {
    $tag_name = $env:APPVEYOR_REPO_TAG_NAME
    if ($tag_name[0] -eq 'v') {
        $nupkg_version = $tag_name.Substring(1)
    } else {
        $nupkg_version = $tag_name
    }
}

Deploy Module {
    By AppVeyorModule {
        FromSource $source_path
        To AppVeyor
        WithOptions @{
            SourceIsAbsolute = $true
            Version = $nupkg_version
        }
        Tagged AppVeyor
    }

    By PSGalleryModule {
        FromSource $source_path
        To PSGallery
        WithOptions @{
            ApiKey = $env:NugetApiKey
            SourceIsAbsolute = $true
        }
        Tagged Release
    }
}

if ($env:GITHUB_API_TOKEN -and 'Release' -in $Tags) {
    $uri = Get-PSGalleryNupkgUrl -Name $module_name -Version '000'
    $nupkg_file = "$module_name.nupkg"
    Invoke-Webrequest -Uri $uri -OutFile $nupkg_file

    try {
        # TODO: Add this as a PSDeploy option
        Publish-GitHubReleaseNupkg -Name 'jborean93/PSAzurePipelinesCITemplate' -Version 'v0.1.0' -Path $nupkg_file
    }  finally {
        Remove-Item -LiteralPath $nupkg_file -Force
    }
}
