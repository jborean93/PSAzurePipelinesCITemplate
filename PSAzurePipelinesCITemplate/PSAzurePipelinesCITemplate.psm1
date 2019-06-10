# Copyright: (c) 2019, Jordan Borean (@jborean93) <jborean93@gmail.com>
# MIT License (see LICENSE or https://opensource.org/licenses/MIT)

# Place anything here that needs to be loaded before the module cmdlets are
# imported.

### TEMPLATED EXPORT FUNCTIONS ###
# The below is replaced by the CI system during the build cycle to contain all
# the Public and Private functions into the 1 psm1 file for faster module
# loading.

$public_functions = [System.Collections.Generic.List`1[System.String]]@()
foreach ($folder in @('Public', 'Private')) {
    $folder_path = Join-Path $PSScriptRoot -ChildPath $folder

    if (Test-Path -LiteralPath $folder_path) {
        $search_path = Join-Path -Path $folder_path -ChildPath '*.ps1'

        foreach ($script_path in Get-ChildItem -Path $search_path -ErrorAction Ignore) {
            . $script_path.FullName

            if ($folder -eq 'Public') {
                $public_functions.Add($script_path.BaseName)
            }
        }
    }
}

### END TEMPLATED EXPORT FUNCTIONS ###

# Place anything here that needs to be run after the module cmdlets are
# imported.

Export-ModuleMember -Function $public_functions
