[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', '',
    Justification='Vars defined in Properties are used in other blocks'
)]
Param ()

Function Export-CodeCovIO {
    <#
    .SYNOPSIS
    Generates CodeCov json from Pester results.

    .DESCRIPTION
    Takes in the Pester coverage results and generates a json file in the format the CodeCov.io expects. This can then
    be uploaded to CodeCov using the codecov.exe tool.

    .PARAMETER Coverage
    The pester code coverage results.

    .PARAMETER Path
    The root path of the project, this should be the root directory of the git repo. Defaults to the current path in
    PowerShell.

    .PARAMETER OutPath
    The output path of the formatted coverage json. This defaults to './CodeCov.json'.

    .EXAMPLE Format Pester coverage to CodeCov json format
    $result = Invoke-Pester -Path Tests/* -CodeCoverage script.ps1 -PassThru
    Format-CodeCovIO -Coverage $result.CodeCoverage

    .NOTES
    I should look at adding this as an option for the Pester CodeCoverageOutputFormat
    #>
    [CmdletBinding()]
    Param (
        [System.Object]
        $Coverage,

        [System.String]
        $Path = '.',

        [System.String]
        $OutPath = (Join-Path -Path '.' -ChildPath 'CodeCov.json')
    )

    # Resolve the path to turn relative to absolute paths
    $Path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $OutPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutPath)

    $code_cov_info = @{
        coverage = @{}
    }

    foreach ($file in $Coverage.AnalyzedFiles) {
        $line_info = [System.Collections.Generic.SortedDictionary`2[[System.String], [System.Object]]]@{}

        $missed_lines = @($Coverage.MissedCommands | Where-Object -Property File -EQ $file)
        $hit_lines = @($Coverage.HitCommands | Where-Object -Property File -EQ $file)
        foreach ($entry in $missed_lines + $hit_lines) {
            for ($i = $entry.StartLine; $i -le $entry.EndLine; $i++) {
                $line_info.$i = $entry.HitCount
            }
        }

        $processed_filename = $file.Substring($Path.Length + 1).Replace('\', '/')
        $code_cov_info.coverage.$processed_filename = $line_info
    }

    $code_cov_json = ConvertTo-Json -InputObject $code_cov_info -Compress
    Set-Content -LiteralPath $OutPath -Value $code_cov_json -Force
}

Properties {
    # Find the build folder based on build system
    $ProjectRoot = $env:BHProjectPath
    if (-not $ProjectRoot) {
        $ProjectRoot = $PSScriptRoot
    }

    $nl = [System.Environment]::NewLine
    $lines = '----------------------------------------------------------------------'
    $BuildPath = Join-Path -Path $ProjectRoot -ChildPath 'Build'
    $ManifestFile = Get-Item -Path (Join-Path -Path $env:BHModulePath -ChildPath '*.psd1')
    $ModuleFile = Get-Item -Path (Join-Path -Path $env:BHModulePath -ChildPath '*.psm1')

    $Verbose = @{}
    if ($env:BHCommitMessage -match '!verbose') {
        $Verbose.Verbose = $true
    }
}

Task Default -Depends Build

Task Init {
    $lines
    Set-Location -LiteralPath $ProjectRoot
    'Build System Details:'
    Get-Item -Path env:BH*

    if (Test-Path -LiteralPath $BuildPath) {
        Remove-Item -LiteralPath $BuildPath -Force -Recurse
    }
    New-Item -Path $BuildPath -ItemType Directory > $null

    if ($env:BHBuildSystem -in @('AppVeyor', 'Azure Pipelines')) {
        $nl
        if ((-not (Get-Variable -Name IsWindows -ErrorAction Ignore)) -or $IsWindows) {
            'Installing codecov.exe with chocolatey'
            &choco.exe install codecov --yes --no-progress
        } else {
            'Downloading codecov.sh with wget'
            Invoke-WebRequest -Uri 'https://codecov.io/bash' -OutFile codecov.sh
        }
    }

    $nl
}

Task Sanity -Depends Init {
    $lines
    "$nl`tSTATUS: Sanity tests with PSScriptAnalyzer"

    $pssa_params = @{
        ErrorAction = 'Ignore'
        Path = "$ProjectRoot$([System.IO.Path]::DirectorySeparatorChar)"
        Recurse = $true
    }
    $results = Invoke-ScriptAnalyzer @pssa_params @verbose
    if ($null -ne $results) {
        $results | Out-String
        Write-Error 'Failed PsScriptAnalyzer tests, build failed'
    }
    $nl
}

Task Test -Depends Sanity {
    $ps_version = "{0}.{1}" -f ($PSVersionTable.PSVersion.Major, $PSVersionTable.PSVersion.Minor)

    $lines
    "$nl`tSTATUS: Testing with PowerShell $ps_version"

    # Gather test results. Store them in a variable and file
    $public_path = Join-Path -Path $env:BHModulePath -ChildPath 'Public'
    $private_path = Join-Path -Path $env:BHModulePath -ChildPath 'Private'
    $code_coverage = [System.Collections.Generic.List`1[String]]@()
    if (Test-Path -LiteralPath $public_path) {
        $code_coverage.Add([System.IO.Path]::Combine($public_path, '*.ps1'))
    }
    if (Test-Path -LiteralPath $private_path) {
        $code_coverage.Add([System.IO.Path]::Combine($private_path, '*.ps1'))
    }
    $code_coverage.Add($ModuleFile.FullName)

    $ps_edition = 'Desktop'
    if ($PSVersionTable.ContainsKey('PSEdition')) {
        $ps_edition = $PSVersionTable.PSEdition
    }
    $ps_platform = 'Win32NT'
    if ($PSVersionTable.ContainsKey('Platform')) {
        $ps_platform = $PSVersionTable.Platform
    }
    $arch = switch([System.Environment]::Is64BitProcess) {
        $true { "x64" }
        $false { "x86" }
    }
    $output_id = "PS{0}_{1}_{2}_{3}_{4}" -f ($ps_version, $arch, $ps_edition, $ps_platform, (Get-Date -UFormat "%Y%m%d-%H%M%S"))
    $test_file = Join-Path -Path $BuildPath -ChildPath "TestResults_$($output_id).xml"
    $coverage_file = Join-Path -Path $BuildPath -ChildPath "Coverage_$($output_id).xml"
    $pester_params = @{
        CodeCoverage = $code_coverage.ToArray()
        CodeCoverageOutputFile = $coverage_file
        OutputFile = $test_file
        OutputFormat = 'NUnitXml'
        PassThru = $true
        Path = (Join-Path -Path $ProjectRoot -ChildPath 'Tests')
    }
    $test_results  = Invoke-Pester @pester_params @Verbose

    if ($env:BHBuildSystem -eq 'AppVeyor') {
        $web_client = New-Object -TypeName System.Net.WebClient
        $web_client.UploadFile(
            "https://ci.appveyor.com/api/testresults/nunit/$($env:APPVEYOR_JOB_ID)",
            $test_file
        )
    }

    if ($test_results.FailedCount -gt 0) {
        Write-Error "Failed '$($test_results.FailedCount)' tests, build failed"
    }

    if ($env:BHBuildSystem -in @('AppVeyor', 'Azure Pipelines', 'Travis CI')) {
        $code_cov_file = Join-Path -Path $BuildPath -ChildPath "Coverage_CodeCov_$($output_id).json"
        $code_cov_params = @{
            Coverage = $test_results.CodeCoverage
            Path = $ProjectRoot
            OutPath = $code_cov_file
        }
        Export-CodeCovIO @code_cov_params


        $coverage_id = "PowerShell-$ps_edition-$ps_version-$arch-$ps_platform"

        "$nl`tSTATUS: Uploading code coverage results with the ID: $coverage_id"
        $upload_args = [System.Collections.Generic.List`1[System.String]]@(
            '-f',
            "`"$code_cov_file`"",
            '-n',
            "`"$coverage_id`""
        )

        if (Get-Command -Name codecov.exe -ErrorAction Ignore) {
            $code_cov_exe = 'codecov.exe'
        } else {
            $code_cov_exe = 'bash'
            $upload_args.Insert(0, './codecov.sh')
        }
        &$code_cov_exe $upload_args
    }
    $nl
}

Task Build -Depends Test {
    $module_name = $ManifestFile.BaseName
    $module_build = Join-Path -Path $BuildPath -ChildPath $module_name

    $lines
    "$nl`tSTATUS: Building PowerShell module with documentation to '$module_build'"

    New-Item -Path $module_build -ItemType Directory > $null
    Copy-Item -LiteralPath $ManifestFile.FullName -Destination (Join-Path -Path $module_build -ChildPath $ManifestFile.Name)

    # Read the existing module and split out the template section lines.
    $module_pre_template_lines = [System.Collections.Generic.List`1[String]]@()
    $module_template_lines = [System.Collections.Generic.List`1[String]]@()
    $module_post_template_lines = [System.Collections.Generic.List`1[String]]@()
    $template_section = $false  # $false == pre, $null == template, $true == post
    foreach ($module_file_line in (Get-Content -LiteralPath $ModuleFile.FullName)) {
        if ($module_file_line -eq '### TEMPLATED EXPORT FUNCTIONS ###') {
            $template_section = $null
        } elseif ($module_file_line -eq '### END TEMPLATED EXPORT FUNCTIONS ###') {
            $template_section = $true
        } elseif ($template_section -eq $false) {
            $module_pre_template_lines.Add($module_file_line)
        } elseif ($template_section -eq $true) {
            $module_post_template_lines.Add($module_file_line)
        }
    }

    # Read each public and private function and add it to the manifest template
    $public_module_names = [System.Collections.Generic.List`1[String]]@()
    $public_functions_path = Join-Path -Path $env:BHModulePath -ChildPath 'Public'
    $private_functions_path = Join-Path -Path $env:BHModulePath -ChildPath 'Private'

    $function_predicate = {
        Param ([System.Management.Automation.Language.Ast]$Ast)
        $Ast -is [System.Management.Automation.Language.FunctionDefinitionAst]
    }

    $public_functions_path, $private_functions_path | ForEach-Object -Process {
        if (Test-Path -LiteralPath $_) {
            Get-ChildItem -LiteralPath $_ | ForEach-Object -Process {
                $function_content = Get-Content -LiteralPath $_.FullName -Raw
                $functions = ([ScriptBlock]::Create($function_content)).Ast.FindAll($function_predicate, $false)

                foreach ($function in $functions) {
                    $module_template_lines.Add($function.ToString())
                    $module_template_lines.Add("")  # Add an empty newline so the functions are spaced out.

                    $parent = Split-Path -Path (Split-Path -Path $_.FullName -Parent) -Leaf
                    if ($parent -eq 'Public') {
                        $public_module_names.Add($function.Name)
                    }
                }
            }
        }
    }

    # Make sure we add an array of all the public functions and place it in our template. This is so the
    # Export-ModuleMember line at the end exports the correct functions.
    $module_template_lines.Add(
        "`$public_functions = @({0}    '{1}'{0})" -f ($nl, ($public_module_names -join "',$nl    '"))
    )

    # Now build the new manifest file lines by adding the templated and post templated lines to the 1 list.
    $module_pre_template_lines.AddRange($module_template_lines)
    $module_pre_template_lines.AddRange($module_post_template_lines)
    $module_file_content = $module_pre_template_lines -join $nl

    Set-Content -LiteralPath (Join-Path -Path $module_build -ChildPath $ModuleFile.Name) -Value $module_file_content

    if ($env:BHBuildSystem -eq 'AppVeyor') {
        "$nl`tSTATUS: Publishing PowerShell module nupkg to AppVeyor artifact"
        Invoke-PSDeploy -Path (Join-Path -Path $ProjectRoot -ChildPath 'deploy.psdeploy.ps1') -Recurse $false -Force -Tags AppVeyor
    }

    $nl
}
