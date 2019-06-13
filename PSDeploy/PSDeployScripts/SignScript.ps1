<#
    .SYNOPSIS
        Signs PowerShell scripts and modules

    .DESCRIPTION
        Signs PowerShell scripts and modules

        Deployment source should be either:
            The path to a single file to sign, or;
            The path to a folder to sign all the files inside that have the extensions
                .psd1
                .psdm1
                .ps1
                .ps1xml

    .PARAMETER Deployment
        Deployment to run

    .PARAMETER CertificatePath
        The path to the certificate to sign with, this can be either a certificate using the Cert: PSProvider or the path on the filesystem to a .pfx certificate

    .PARAMETER CertificatePassword
        If using a certificate in the file system and not in the certificate store, this is the password used to open the certificate

    .PARAMETER TimestampServer
        Optional timestamp server to timestamp the certificate with

    .PARAMETER HashAlgorithm
        Optionally specify the hash algorithm used to sign the certificate

    .PARAMETER IncludeChain
        Determines which certificates in the cert trust chain are included in the digital signature. Value values are:
            Signer - Includes only the signer's certificate
            NotRoot - Includes all the certificates in the certificate chain, except for the root authority
            All - Includes all the certificates in the certificate chain
#>
[CmdletBinding()]
Param (
    [ValidateScript({ $_.PSObject.TypeNames[0] -eq 'PSDeploy.Deployment' })]
    [PSObject[]]$Deployment,

    [Parameter(Mandatory=$true)]
    [System.String]
    $CertificatePath,

    [SecureString]
    [AllowNull]
    $CertificatePassword,

    [System.String]
    $TimestampServer,

    [System.String]
    $HashAlgorithm,

    [System.String]
    $IncludeChain
)

Write-Verbose -Message "Attempting to get signing certificate at path '$CertificatePath'"
$cert = Get-Item -LiteralPath $CertificatePath -ErrorAction Ignore
if ($null -eq $Cert) {
    Write-Error -Message "Failed to find certificate at '$CertificatePath'"
    return
}

if ($cert.PSProvider -eq 'FileSystem.Name') {
    Write-Verbose -Message "Certificate at path '$CertificatePath' is a file, load the certificate"

    $cert.Dispose()
    $argList = @($CertificatePath)
    if ($null -ne $CertificatePassword) {
        Write-Verbose -Message "Loading the certificate with an explicit password"
        $argList += $CertificatePassword
    }
    $cert = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList $argList
}

try {
    $signParams = @{
        Certificate = $cert
    }

    'TimestampServer', 'HashAlgorithm', 'IncludeChain' | ForEach-Object -Process {
        if ($PSBoundParameters.ContainsKey($_)) {
            Write-Verbose -Message "Adding optional authenticode param $_"
            $signParams.$_ = $PSBoundParameters.$_
        }
    }

    foreach ($Deploy in $Deployment) {
        Write-Verbose -Message "Running SignScript for deployment source '$($Deploy.Source)'"

        $sourcePath = Get-Item -LiteralPath $Deploy.Source -ErrorAction Ignore
        if ($null -eq $sourcePath) {
            Write-Error -Message "The path specified '$($Deploy.Source)' was not found"
            return
        } elseif ($sourcePath.PSIsContainer) {
            Write-Verbose -Message "The source specified '$($Deploy.Source)' is a directory, finding all .psd1, .psm1, .ps1, and .ps1xml files to sign"
            $files = @(Get-ChildItem -Path $sourcePath.FullName -Recurse -Include '*.psd1', '*.psm1', '.ps1', '.ps1xml')
        } else {
            Write-Verbose -Message "The source specified '$($Deploy.Source)' is a file, signing that file only"
            $files = @($sourcePath)
        }

        foreach ($file in $files) {
            Write-Verbose -Message "Signing file '$($file.FullName)'"
            Set-AuthenticodeSignature -LiteralPath $file.FullName @signParams > $null
        }
    }
} finally {
    $cert.Dispose()
}
