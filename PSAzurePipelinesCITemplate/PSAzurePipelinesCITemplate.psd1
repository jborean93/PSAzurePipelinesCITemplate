# Copyright: (c) 2019, Jordan Borean (@jborean93) <jborean93@gmail.com>
# MIT License (see LICENSE or https://opensource.org/licenses/MIT)

@{
    RootModule = 'PSAzurePipelinesCITemplate.psm1'
    ModuleVersion = '0.1.1'
    GUID = '1964fa76-d92f-432a-81e8-fb44b341c7a5'
    Author = 'Jordan Borean'
    Copyright = 'Copyright (c) 2019 by Jordan Borean, Red Hat, licensed under MIT.'
    Description = "A template repo for running a PowerShell module CI in Azure Pipelines.`nSee https://github.com/jborean93/PSAzurePipelinesCITemplate for more info"
    PowerShellVersion = '3.0'
    RequiredModules = @()
    FunctionsToExport = @(
        'Get-PSAzurePipelinesCITemplate'
    )
    PrivateData = @{
        PSData = @{
            Tags = @(
                "DevOps",
                "Module",
                "Development"
            )
            LicenseUri = 'https://github.com/jborean93/PSAzurePipelinesCITemplate/blob/master/LICENSE'
            ProjectUri = 'https://github.com/jborean93/PSAzurePipelinesCITemplate'
            ReleaseNotes = 'See https://github.com/jborean93/PSAzurePipelinesCITemplate/blob/master/CHANGELOG.md'
        }
    }
}
