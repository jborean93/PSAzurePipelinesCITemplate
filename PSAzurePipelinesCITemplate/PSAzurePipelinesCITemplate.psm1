# Copyright: (c) 2019, Jordan Borean (@jborean93) <jborean93@gmail.com>
# MIT License (see LICENSE or https://opensource.org/licenses/MIT)

# Place anything here that needs to be loaded before the module cmdlets are
# imported.

### TEMPLATED EXPORT FUNCTIONS ###
# The below is replaced by the CI system during the build cycle to contain all
# the Public and Private functions into the 1 psm1 file for faster module
# loading.

if (Test-Path -LiteralPath $PSScriptRoot\Public) {
    $public = @( Get-ChildItem -Path $PSScriptRoot\Public\*.ps1 -ErrorAction SilentlyContinue )
} else {
    $public = @()
}
if (Test-Path -LiteralPath $PSScriptRoot\Private) {
    $private = @( Get-ChildItem -Path $PSScriptRoot\Private\*.ps1 -ErrorAction SilentlyContinue )
} else {
    $private = @()
}

# dot source the files
foreach ($import in @($public + $private)) {
    try {
        . $import.FullName
    } catch {
        Write-Error -Message "Failed to import function $($import.FullName): $_"
    }
}

$public_functions = $public.Basename

### END TEMPLATED EXPORT FUNCTIONS ###

# Place anything here that needs to be run after the module cmdlets are
# imported.

Export-ModuleMember -Function $public_functions
