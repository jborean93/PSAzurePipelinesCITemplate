[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', '',
    Justification='Vars defined in Properties are used in other blocks'
)]
Param ()

#Requires -Module PSCodeCovIo

Properties {
    # Find the build folder based on build system
    $ProjectRoot = $env:BHProjectPath
    if (-not $ProjectRoot) {
        $ProjectRoot = $PSScriptRoot
    }

    $nl = [System.Environment]::NewLine
    $lines = '----------------------------------------------------------------------'
    $BuildPath = Join-Path -Path $ProjectRoot -ChildPath 'Build'

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

    $test_date = Get-Date -UFormat "%Y%m%d-%H%M%S"
    $test_file = Join-Path -Path $BuildPath -ChildPath "TestResults_PS$($ps_version)_$($test_date).xml"
    $pester_params = @{
        CodeCoverage = $code_coverage.ToArray()
        OutputFile = $test_file
        OutputFormat = 'NUnitXml'
        PassThru = $true
        Path = (Join-Path -Path $ProjectRoot -ChildPath 'Tests')
    }
    $test_results  = Invoke-Pester @pester_params @Verbose

    # The file that is uploaded to CodeCov.io needs to be converted first. This can only be done if the repo has been
    # initialised as a git repo and git is available. TODO: Support Linux
    $coverage_file = $null
    $git_folder = Join-Path -Path $ProjectRoot -ChildPath '.git'
    if ((Get-Command -Name git.exe -ErrorAction Ignore) -and (Test-Path -LiteralPath $git_folder)) {
        $coverage_file = Join-Path -Path $BuildPath -ChildPath "CodeCoverage_PS$($ps_version)_$($test_date).json"
        $code_cov_params = @{
            CodeCoverage = $test_results.CodeCoverage
            RepoRoot = $ProjectRoot
            Path = $coverage_file
        }
        Export-CodeCovIoJson @code_cov_params

        # A warning in git may cause LASTEXITCODE to not be 0, we reset it here
        # so the pipeline doesn't fail
        $global:LASTEXITCODE = 0
    }

    if ($env:BHBuildSystem -eq 'AppVeyor') {
        $web_client = New-Object -TypeName System.Net.WebClient
        $web_client.UploadFile(
            "https://ci.appveyor.com/api/testresults/nunit/$($env:APPVEYOR_JOB_ID)",
            [System.IO.Path]::Combine($ProjectRoot, $test_file)
        )
    }

    if ($test_results.FailedCount -gt 0) {
        Write-Error "Failed '$($test_results.FailedCount)' tests, build failed"
    }

    # TODO: Support Linux
    if ((Get-Command -Name codecov.exe -ErrorAction Ignore) -and $env:BHBuildSystem -in @('AppVeyor', 'Azure Pipelines', 'Travis CI') -and $null -ne $coverage_file) {
        $ps_edition = 'Desktop'
        if ($PSVersionTable.ContainsKey('PSEdition')) {
            $ps_edition = $PSVersionTable.PSEdition
        }
        $ps_platform = 'Win32NT'
        if ($PSVersionTable.ContainsKey('Platform')) {
            $ps_platform = $PSVersionTable.Platform
        }
        $coverage_id = "PowerShell-$ps_edition-$ps_version-$ps_platform"

        "$nl`tSTATUS: Uploading code coverage results with the ID: $coverage_id"
        $upload_args = [System.Collections.Generic.List`1[System.String]]@(
            '-f',
            "`"$coverage_file`"",
            '-n',
            "`"$coverage_id`""
        )

        if (Test-Path -LiteralPath env:CODECOV_TOKEN) {
            $upload_args.Add('-t')
            $upload_args.Add($env:CODECOV_TOKEN)
        }

        &codecov.exe $upload_args
    }
    $nl
}

Task Build -Depends Test {
    $manifest_file = Get-Item -Path (Join-Path -Path $env:BHModulePath -ChildPath '*.psd1')
    $module_file = Get-Item -Path (Join-Path -Path $env:BHModulePath -ChildPath '*.psm1')
    $module_name = $manifest_file.BaseName
    $module_build = Join-Path -Path $BuildPath -ChildPath $module_name

    $lines
    "$nl`tSTATUS: Building PowerShell module with documentation to '$module_build'"

    New-Item -Path $module_build -ItemType Directory > $null
    Copy-Item -LiteralPath $manifest_file.FullName -Destination (Join-Path -Path $module_build -ChildPath $manifest_file.Name)

    # Read the existing module and split out the template section lines.
    $module_pre_template_lines = [System.Collections.Generic.List`1[String]]@()
    $module_template_lines = [System.Collections.Generic.List`1[String]]@()
    $module_post_template_lines = [System.Collections.Generic.List`1[String]]@()
    $template_section = $false  # $false == pre, $null == template, $true == post
    foreach ($module_file_line in (Get-Content -LiteralPath $module_file.FullName)) {
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
                $function_content = Get-Content -LiteralPath $_ -Raw
                $functions = ([ScriptBlock]::Create($function_content)).Ast.FindAll($function_predicate, $false)

                foreach ($function in $functions) {
                    $module_template_lines.Add($function.ToString())
                    $module_template_lines.Add("")  # Add an empty newline so the functions are spaced out.

                    $parent = Split-Path -Path (Split-Path -Path $_ -Parent) -Leaf
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

    Set-Content -LiteralPath (Join-Path -Path $module_build -ChildPath $module_file.Name) -Value $module_file_content

    $nl
}
