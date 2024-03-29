# PSAzurePipelinesCITemplate

[![Build Status](https://dev.azure.com/jborean93/jborean93/_apis/build/status/jborean93.PSAzurePipelinesCITemplate?branchName=master)](https://dev.azure.com/jborean93/jborean93/_build/latest?definitionId=1&branchName=master)
[![PowerShell Gallery](https://img.shields.io/powershellgallery/dt/PSAzurePipelinesCITemplate.svg)](https://www.powershellgallery.com/packages/PSAzurePipelinesCITemplate)
[![codecov](https://codecov.io/gh/jborean93/PSAzurePipelinesCITemplate/branch/master/graph/badge.svg)](https://codecov.io/gh/jborean93/PSAzurePipelinesCITemplate)


## Info

A template repo for running CI of a PowerShell module with
[Azure Pipelines](https://azure.microsoft.com/en-us/services/devops/pipelines/).

When setting up an Azure Pipeline you will first need to define the following
secret variables;

* `psgallery_token`: The API token used to publish the module to the [PowerShell Gallery](https://www.powershellgallery.com).
* `github_token`: The API token used to publish a GitHub assert on a tagged release, this requires the `public_repo` access scope
* `code_signing_pass`: The password used to decrypt the code signing `.pfx` certificate. Can be omitted if no code signing is required
* `codecov_token`: The token used to upload coverage results to [codecov.io](https://codecov.io). This is unique per repo and should be set directly as a secret build variable

The `psgallery_token`, `github_token`, and `code_singing_pass` can be set as a
secret in a common variable group allowing it to be defined one and used in
multiple builds. It is recommended you explicitly link the build instead of
allowing all pipeline access.

The final step is to upload a secure file called `ps_signing_cert.pfx` that is
used for signing the PowerShell module. This step can be skipped if no signing
is required but requires some changed to the `azure-pipelines.yml`.

_Note: Pull requests runs won't have access to secure variables, be careful to review changes to the CI process in case it exposes one of these vars._


## Requirements

* PowerShell v3.0 or newer (PSCore included)


## Installing

The easiest way to install this module is through
[PowerShellGet](https://docs.microsoft.com/en-us/powershell/gallery/overview).
This is installed by default with PowerShell 5 but can be added on PowerShell
3 or 4 by installing the MSI [here](https://www.microsoft.com/en-us/download/details.aspx?id=51451).

Once installed, you can install this module by running;

```powershell
# Install for all users
Install-Module -Name PSAzurePipelinesCITemplate

# Install for only the current user
Install-Module -Name PSAzurePipelinesCITemplate -Scope CurrentUser
```

If you wish to remove the module, just run
`Uninstall-Module -Name PSAzurePipelinesCITemplate`.

If you cannot use PowerShellGet, you can still install the module manually,
by using the script cmdlets in the script [Install-ModuleNupkg.ps1](https://gist.github.com/jborean93/e0cb0e3aabeaa1701e41f2304b023366).

```powershell
# Enable TLS1.1/TLS1.2 if they're available but disabled (eg. .NET 4.5)
$security_protocols = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::SystemDefault
if ([Net.SecurityProtocolType].GetMember("Tls11").Count -gt 0) {
    $security_protocols = $security_protocols -bor [Net.SecurityProtocolType]::Tls11
}
if ([Net.SecurityProtocolType].GetMember("Tls12").Count -gt 0) {
    $security_protocols = $security_protocols -bor [Net.SecurityProtocolType]::Tls12
}
[Net.ServicePointManager]::SecurityProtocol = $security_protocols

# Run the script to load the cmdlets and get the URI of the nupkg
$invoke_wr_params = @{
    Uri = 'https://gist.github.com/jborean93/e0cb0e3aabeaa1701e41f2304b023366/raw/Install-ModuleNupkg.ps1'
    UseBasicParsing = $true
}
$install_script = (Invoke-WebRequest @invoke_wr_params).Content

################################################################################################
# Make sure you check the script at the URI first and are happy with the script before running #
################################################################################################
Invoke-Expression -Command $install_script

# Get the URI to the nupkg on the gallery
$gallery_uri = Get-PSGalleryNupkgUri -Name PSAzurePipelinesCITemplate

# Install the nupkg for the current user, add '-Scope AllUsers' to install
# for all users (requires admin privileges)
Install-PowerShellNupkg -Uri $gallery_uri
```

_Note: I can't stress this enough, make sure you review the script specified by Uri` before running the above_

If you wish to remove a module installed with the above method you can run;

```powershell
$module_path = (Get-Module -Name PSAzurePipelinesCITemplate -ListAvailable).ModuleBase
Remove-Item -LiteralPath $module_path -Force -Recurse
```


## Contributing

Contributing is quite easy, fork this repo and submit a pull request with the
changes. To test out your changes locally you can just run `.\build.ps1` in
PowerShell. This script will ensure all dependencies are installed before
running the test suite.

_Note: this requires PowerShellGet or WMF 5+ to be installed_
