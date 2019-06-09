# Copyright: (c) 2019, Jordan Borean (@jborean93) <jborean93@gmail.com>
# MIT License (see LICENSE or https://opensource.org/licenses/MIT)

Function Get-PSAzurePipelinesCITemplate {
    [OutputType([System.String])]
    [CmdletBinding()]
    Param (
        [Parameter(ValueFromPipeline=$true)]
        [System.String]
        $Value = "World"
    )

    $return_string = Get-ReturnString -Value $Value
    return $return_string
}
