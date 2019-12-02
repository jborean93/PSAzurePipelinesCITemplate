# Copyright: (c) 2019, Jordan Borean (@jborean93) <jborean93@gmail.com>
# MIT License (see LICENSE or https://opensource.org/licenses/MIT)

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification='Just for testing right now'
)]
Param ()

$ErrorActionPreference = 'Stop'

# Define common variables
$module_name = (Get-ChildItem -Path ([System.IO.Path]::Combine($DeploymentRoot, 'Build', '*', '*.psd1'))).BaseName
$source_path = [System.IO.Path]::Combine($DeploymentRoot, 'Build', $module_name)
$module_version = (Get-Module -Name $source_path -ListAvailable).Version.ToString()
$code_cert_path = $null
$code_cert_pass = $null
$repository_name = $null
$repository_tag = $null

# Populate variables based on the build host type we are running on
if (Test-Path -LiteralPath env:APPVEYOR) {
    # TODO: Support code signing certificates

    $repository_name = $env:APPVEYOR_REPO_NAME
    if ((Test-Path -LiteralPath env:APPVEYOR_REPO_TAG) -and ([System.Boolean]::Parse($env:APPVEYOR_REPO_TAG))) {
        $repository_tag = $env:APPVEYOR_REPO_TAG_NAME
    }
} elseif (Test-Path -LiteralPath env:BUILD_SOURCEBRANCHNAME) {
    # Check if we need to sign the module
    if ((Test-Path -LiteralPath env:DOWNLOADSECUREFILE_SECUREFILEPATH) -and (Test-Path -LiteralPath env:CODE_SIGNING_PASS)) {
        if (Test-Path -LiteralPath $env:DOWNLOADSECUREFILE_SECUREFILEPATH) {
            $code_cert_path = $env:DOWNLOADSECUREFILE_SECUREFILEPATH
            $code_cert_pass = ConvertTo-SecureString -String $env:CODE_SIGNING_PASS -AsPlainText -Force
        }
    }

    $repository_name = $env:BUILD_REPOSITORYNAME
    if ($env:BUILD_SOURCEBRANCH.StartsWith('refs/tags/')) {
        $repository_tag = $env:BUILD_SOURCEBRANCHNAME
    }
}
$is_signed = ($null -ne $code_cert_path -and $null -ne $code_cert_pass)
$is_github_release = ($null -ne $repository_name -and $null -ne $repository_tag -and (Test-Path -LiteralPath env:GITHUB_TOKEN))

Deploy Module {
    if (Test-Path -LiteralPath env:APPVEYOR) {
        $nupkg_version = $env:APPVEYOR_BUILD_VERSION
        if ((Test-Path -LiteralPath env:APPVEYOR_REPO_TAG) -and ([System.Boolean]::Parse($env:APPVEYOR_REPO_TAG))) {
            $nupkg_version = $module_version
        }

        By AppVeyorModule {
            FromSource $source_path
            To AppVeyor
            WithOptions @{
                SourceIsAbsolute = $true
                Version = $nupkg_version
            }
            Tagged AppVeyor
        }
    }

    if ($is_signed) {
        By SignScript SignModule {
            FromSource $source_path
            WithOptions {
                CertificatePath = $code_cert_path
                CertificatePassword = $code_cert_pass
                TimestampServer = 'http://timestamp.comodoca.com'
                HashAlgorithm = 'sha256'
                IncludeChain = 'All'
            }
            Tagged Release
        }
    }

    By PSGalleryModule PSGallery {
        FromSource $source_path
        To PSGallery
        WithOptions @{
            ApiKey = $env:PSGALLERY_TOKEN
            SourceIsAbsolute = $true
        }
        if ($is_signed) {
            DependingOn SignModule
        }
        Tagged Release
    }

    if ($is_github_release) {
        $github_token = ConvertTo-SecureString -String $env:GITHUB_TOKEN -AsPlainText -Force

        By GitHubAsset {
            FromSource PSGallery
            To $repository_name
            WithOptions @{
                ApiKey = $github_token
                PackageName = $module_name
                PackageVersion = $module_version
                Tag = $repository_tag
            }
            DependingOn PSGallery
            Tagged Release
        }
    }
}
