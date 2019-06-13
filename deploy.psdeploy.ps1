# Copyright: (c) 2019, Jordan Borean (@jborean93) <jborean93@gmail.com>
# MIT License (see LICENSE or https://opensource.org/licenses/MIT)

#Requires -Module BuildHelpers

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

Function Publish-GitHubReleaseAsset {
    [CmdletBinding()]
    Param (
        [System.String]
        $Name,

        [System.String]
        $Repository,

        [System.String]
        $Tag,

        [System.String]
        $Path
    )
    $nupkg_item = Get-Item -Path $Path

    $root_uri = "https://api.github.com/repos/$Repository"
    $headers = @{
        Authorization = "token $env:GITHUB_TOKEN"
    }

    try {
        $tag_info = Invoke-RestMethod -Uri "$root_uri/releases/tags/$Tag" -Headers $headers -ErrorAction Stop`
    } catch {
        Write-Error -Message "Failed to get tag ID for '$Repository' with version tag '$Tag': $($_.Exception.Message)"
        return
    }

    $publish_uri = "https://uploads.github.com/repos/$Repository/releases/$($tag_info.id)/assets?name=$Name"
    $headers.'Content-Type' = 'application/octet-stream'
    try {
        Invoke-RestMethod -Uri $publish_uri -Headers $headers -InFile $nupkg_item.FullName > $null
    } catch {
        Write-Error -Message "Failed to upload asset to release: $($_.Exception.Message)"
        return
    }
}

$is_appveyor = Test-Path -LiteralPath env:APPVEYOR
$is_azure_pipelines = Test-Path -LiteralPath env:BUILD_SOURCEBRANCHNAME

$module_name = (Get-ChildItem -Path ([System.IO.Path]::Combine($DeploymentRoot, 'Build', '*', '*.psd1'))).BaseName
$source_path = [System.IO.Path]::Combine($DeploymentRoot, 'Build', $module_name)
$module_version = (Get-Module -Name $source_path -ListAvailable).Version.ToString()

# Deploy module to the AppVeyor build artifacts if running in AppVeyor
if ($is_appveyor) {
    $repository = $env:APPVEYOR_REPO_NAME
    $tag = $env:APPVEYOR_REPO_TAG_NAME
    $code_cert_path = $null

    $nupkg_version = $env:APPVEYOR_BUILD_VERSION
    if ((Test-Path -LiteralPath env:APPVEYOR_REPO_TAG) -and ([System.Boolean]::Parse($env:APPVEYOR_REPO_TAG))) {
        $nupkg_version = $module_version
    }

    Deploy AppVeyorNuget {
        By AppVeyorModule {
            FromSource $source_path
            To AppVeyor
            WithOptions @{
                SourceIsAbsolute = $true
                Version = $nupkg_version
            }
        }
    }
} elseif ($is_azure_pipelines) {
    $repository = $env:BUILD_REPOSITORYNAME
    $tag = $env:BUILD_SOURCEBRANCHNAME

    if (Test-Path -LiteralPath $env:DOWNLOADSECUREFILE_SECUREFILEPATH) {
        $code_cert_path = $env:DOWNLOADSECUREFILE_SECUREFILEPATH
    } else {
        $code_cert_path = $null
    }
}

# Sign the module and all the files within.
if ($null -ne $code_cert_path -and Test-Path -LiteralPath env:CODE_SIGNING_PASS -and 'Release' -in $Tags) {
    $cert = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList @(
        $code_cert_path,
        $env:CODE_SIGNING_PASS
    )
    try {
        $sign_params = @{
            Certificate = $cert
            TimestampServer = 'http://timestamp.comodoca.com'
            HashAlgorithm = 'sha256'
            IncludeChain = 'All'
        }
        Get-ChildItem -Path $source_path -Recurse -Include '*.psd1', '*.psm1' | ForEach-Object -Process {
            Set-AuthenticodeSignature -LiteralPath $_.FullName @sign_params > $null
        }
    } finally {
        $cert.Dispose()
    }
}


# Deploy module to PSGallery when tagged with Release
Deploy Module {
    By PSGalleryModule {
        FromSource $source_path
        To PSGallery
        WithOptions @{
            ApiKey = $env:PSGALLERY_TOKEN
            SourceIsAbsolute = $true
        }
        Tagged Release
    }
}

# Deploy the published module nupkg to the GitHub release asset
if (Test-Path -LiteralPath env:GITHUB_TOKEN -and 'Release' -in $Tags) {
    $uri = Get-PSGalleryNupkgUrl -Name $module_name -Version $module_version
    $nupkg_file = "$module_name.nupkg"
    Invoke-Webrequest -Uri $uri -OutFile $nupkg_file

    try {
        # TODO: Add this as a PSDeploy option
        $publish_params = @{
            Name = "$module_name.$module_version.nupkg"
            Repository = $repository
            Tag = $tag
            Path = $nupkg_file
        }
        Publish-GitHubReleaseAsset @publish_params
    }  finally {
        Remove-Item -LiteralPath $nupkg_file -Force
    }
}
