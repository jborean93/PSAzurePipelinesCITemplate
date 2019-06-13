<#
    .SYNOPSIS
        Publishes an artifact to a GitHub release.

    .DESCRIPTION
        Publishes an artifact to a GitHub release.

        Deployment source should be either:
            The URI to the artifact to publish, or;
            The name of the PowerShellGet PSRepository to search (Get-PSRepository)

    .PARAMETER Deployment
        Deployment to run

    .PARAMETER ApiKey
        The API token of a GitHub account that has public_repo (repo for private repos) rights on the target repository

    .PARAMETER PackageName
        The name of the package to publish as a release asset. This is required when the deployment source is a PowerShellGet repository name

    .PARAMETER PackageVersion
        The version of the module to publish as a release asset

    .PARAMETER Tag
        The GitHub release tag to publish the assert for

    .PARAMETER Name
        The name to publish the asset as, defaults to the filename of the asset that is published
#>
[CmdletBinding()]
Param (
    [ValidateScript({ $_.PSObject.TypeNames[0] -eq 'PSDeploy.Deployment' })]
    [PSObject[]]$Deployment,

    [Parameter(Mandatory=$true)]
    [SecureString]
    $ApiKey,

    [System.String]
    $PackageName,

    [System.String]
    $PackageVersion,

    [System.String]
    $Tag,

    [System.String]
    $Name
)

# Older .NET versions don't automatically use TLSv1.2, we enable it if available to ensure we cna talk to GitHub
$secProtocols = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::SystemDefault
if ([Net.SecurityProtocolType].GetMember("Tls11").Count -gt 0) {
    $secProtocols = $secProtocols -bor [Net.SecurityProtocolType]::Tls11
}
if ([Net.SecurityProtocolType].GetMember("Tls12").Count -gt 0) {
    $secProtocols = $secProtocols -bor [Net.SecurityProtocolType]::Tls12
}
[Net.ServicePointManager]::SecurityProtocol = $secProtocols

$psRepositories = Get-PSRepository
foreach ($Deploy in $Deployment) {
    Write-Verbose -Message "Starting deployment '$($Deploy.DeploymentName)' to GitHub release asset"

    $psRepository = $psRepositories | Where-Object { $_.Name -eq $Deploy.Source }
    $foundPackage = $null
    if ($null -ne $psRepository) {
        Write-Verbose -Message "Source '$($Deploy.Source)' is a valid PowerShellGet repository source, using it's SourceLocation to find asset"
        $sourceUri = [System.Uri]$psRepository.SourceLocation

        if ($null -eq $PackageName) {
            Write-Error -Message "The option PackageName must be set when source is a PowerShell repository"
            return
        }

        Write-Verbose -Message "Source URI '$($sourceUri.AbsolutePath)' is a path to a nuget location, attempting to search for package '$PackageName'"
        $findParams = @{
            Name = $PackageName
            Source = $psRepository.Name
            ErrorAction = 'Ignore'
        }
        if ($PSBoundParameters.ContainsKey('PackageVersion')) {
            $findParams.RequiredVersion = $PackageVersion
        }
        $foundPackage = Find-Package @findParams
        if ($null -eq $foundPackage) {
            Write-Error -Message "Failed to find package '$PackageName' in repository '$($psRepository.Name)'"
        }
    } else {
        Write-Verbose -Message "Source '$($Deploy.Source)' is not a valid PowerShellGet repository source, try to parse it as a URI explicitly"
        try {
            $sourceUri = [System.Uri]$Deploy.Source
        } catch [System.FormatException] {
            Write-Error -Message "Invalid URI source specified '$($Deploy.Source)': $($_.Exception.Message)"
            return
        }
    }

    $supportedSchemes = @('file', 'http', 'https')
    if ($sourceUri.Scheme -notin $supportedSchemes) {
        Write-Error -Message "Source URI '$sourceUri' scheme is not supported. Supported schemes are $($supportedSchemes -join ", ")"
        return
    }

    $tempDir = $null
    try {
        if ($sourceUri.Scheme -eq 'file') {
            if (Test-Path -LiteralPath $sourceUri.AbsolutePath -PathType Leaf) {
                Write-Verbose -Message "Source URI '$($sourceUri.AbsolutePath)' is a path to an explicit file to upload"
                $sourcePath = $sourceUri.AbsolutePath
            } elseif (Test-Path -LiteralPath $sourceUri.AbsolutePath -PathType Container) {
                # Dirs are only supported if the Deployment source was a PSGet identifier
                if ($null -eq $psRepository) {
                    Write-Error -Messsage "Source specified '$($sourceUri.AbsolutePath)' is a directory and not a file or valid PSRepository source name"
                    return
                }

                $sourcePath = Join-Path -Path $sourceUri.AbsolutePath -ChildPath "$($foundPackage.PackageFilename).$($foundPackage.Version).nupkg"
                if (-not (Test-Path -LiteralPath $sourcePath)) {
                    Write-Error -Message "Found package through nuget feed but failed to find nupkg location through the expected path '$sourcePath'"
                }
                Write-Verbose -Message "Source URI '$($sourceUri.AbsolutePath)' was a PowerShellGet repository and found package to upload at '$sourcePath'"
            } else {
                Write-Error -Message "Source specified '$($sourceUri.AbsolutePath)' does not exist"
                return
            }
        } else {
            Write-Verbose -Message "Source URI '$($sourceUri.AbsolutePath)' is a nuget feed, download nupkg from feed"
            $nupkgUri = "$($sourceUri.AbsoluteUri)/package/$($foundPackage.Name)/$($foundPackage.Version)"

            $tempDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([System.IO.Path]::GetRandomFileName())
            Write-Verbose -Message "Creating temp directory to store nupkg at '$tempDir'"
            New-Item -Path $tempDir -ItemType Directory > $null

            $sourcePath = Join-Path -Path $tempDir -ChildPath "$($foundPackage.Name).$($foundPackage.Version).nupkg"
            Write-Verbose -Message "Attempting to download nupkg from '$nupkgUri' to '$sourcePath'"
            $wc = New-Object -TypeName System.Net.WebClient

            try {
                $wc.DownloadFile($nupkgUri, $sourcePath)
            } catch {
                Write-Error -Message "Failed to download nupkg from '$nupkgUri' to '$sourcePath': $($_.Exception.Message)"
                return
            }
        }

        if ([System.String]::IsNullOrEmpty($Name)) {
            $Name = (Get-Item -LiteralPath $sourcePath).Name
        }

        # We've found the file to publish, now actually publish it to the target
        foreach ($Target in $Deploy.Targets) {
            $ghRootUri = "https://api.github.com/repos/$Target"

            # While this duplicates effort we convert from the SecureString as late as possible to avoid the GH token
            # being left as plaintext in the process' memory.
            $tokenPtr = [System.Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($ApiKey)
            try {
                # Only do this right at the end to ensure the secret isn't stored in memory for a long time
                $ghToken = "token $([System.Runtime.InteropServices.Marshal]::PtrToStringUni($tokenPtr))"
                $headers = @{
                    Authorization = $ghToken
                }

                if ([System.String]::IsNullOrEmpty($Tag)) {
                    $tagInfoUri = "$ghRootUri/releases/latest"
                } else {
                    $tagInfoUri = "$ghRootUri/releases/tags/$Tag"
                }
                Write-Verbose -Message "Getting GitHub tag ID with '$tagInfoUri'"
                try {
                    $tagInfo = Invoke-RestMethod -Uri $tagInfoUri -Headers $headers -ErrorAction Stop
                } catch {
                    Write-Error -Message "Failed to get tag ID for '$Target' with version tag '$Tag': $($_.Exception.Message)"
                    return
                }

                $publishUri = "https://uploads.github.com/repos/$Target/releases/$($tagInfo.id)/assets?name=$Name"
                Write-Verbose -Message "Publishing assert from '$sourcePath' to '$publishUri'"
                try {
                    Invoke-RestMethod -Uri $publishUri -Headers $headers -InFile $sourcePath > $null
                } catch {
                    Write-Error -Message "Failed to upload assert to release '$Target' '$Tag': $($_.Exception.Message)"
                    return
                }
            } finally {
                [System.Runtime.InteropServices.Marshal]::ZeroFreeGlobalAllocUnicode($tokenPtr)
                $tokenPtr = [System.IntPtr]::Zero
                $ghToken = $null
                $headers = $null
                [System.GC]::Collect()  # Best effort to tell GC to remove the in memory string reference
            }
        }
    } finally {
        if ($null -ne $tempDir -and (Test-Path -LiteralPath $tempDir)) {
            Write-Verbose -Message "Removing temporary directory '$tempDir' created by deploy task"
            Remove-Item -LiteralPath $tempDir -Force -Recurse
        }
    }
}

