# Copyright: (c) 2019, Jordan Borean (@jborean93) <jborean93@gmail.com>
# MIT License (see LICENSE or https://opensource.org/licenses/MIT)

$ps_version = "{0}.{1}" -f ($PSVersionTable.PSVersion.Major, $PSVersionTable.PSVersion.Minor)
$cmdlet_name = $MyInvocation.MyCommand.Name.Replace('.Tests.ps1', '')
$module_name = (Get-ChildItem -Path $PSScriptRoot\.. -Directory -Exclude @('Build', 'Docs', 'PSDeploy', 'Tests')).Name
Import-Module -Name $PSScriptRoot\..\$module_name -Force

Describe "$cmdlet_name PS$ps_version tests" {
    Context 'Strict mode' {
        Set-StrictMode -Version latest

        It 'Should call public cmdlet with defaults' {
            $expected = 'Hello World'
            $actual = Get-PSAzurePipelinesCITemplate
            $actual | Should -Be $expected
        }

        It 'Should call public cmdlet with custom value' {
            $expected = 'Hello Module'
            $actual = Get-PSAzurePipelinesCITemplate -Value 'Module'
            $actual | Should -Be $expected
        }
    }
}
