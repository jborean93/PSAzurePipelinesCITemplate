# PSAzurePipelinesCITemplate

[![Build Status](https://dev.azure.com/jborean93/jborean93/_apis/build/status/jborean93.PSAzurePipelinesCITemplate?branchName=master)](https://dev.azure.com/jborean93/jborean93/_build/latest?definitionId=1&branchName=master)
[![PowerShell Gallery](https://img.shields.io/powershellgallery/dt/PSAzurePipelinesCITemplate.svg)](https://www.powershellgallery.com/packages/PSAzurePipelinesCITemplate)
[![codecov](https://codecov.io/gh/jborean93/PSAzurePipelinesCITemplate/branch/master/graph/badge.svg)](https://codecov.io/gh/jborean93/PSAzurePipelinesCITemplate)


## Info

A template repo for running CI of a PowerShell module with
[Azure Pipelines](https://azure.microsoft.com/en-us/services/devops/pipelines/).

To setup an Azure Pipeline with a new repo you will need to do the following
manual step:

* Setup the CodeCov token for uploading coverage results
    * Go to [codecov.io](https://codecov.io) and get the `CODECOV_TOKEN` for the new repository
    * Go to Azure DevOps and edit the pipeline for the new repo
    * Go to the variables section for the new pipeline
    * Add a new variable with the name `codecov_token` and the value as the token from Code Cov
    * Set the padlock icon to set the variable as a secure variable
    * Save the variable
* Setup the PowerShell Gallery API token for pushing the module on release
    * Go to the [PowerShell Gallery](https://www.powershellgallery.com) and sign in
    * Click on your account and go to `API Keys`
    * Generate an API key if one has not already been generated
    * Go to Azure DevOps and add a secure variable called `nuget_api_key` with that token


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
