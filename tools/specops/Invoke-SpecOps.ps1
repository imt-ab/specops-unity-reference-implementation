<#
.SYNOPSIS
Runs the bounded SpecOps identity, profile-verification, and eval operations.

.DESCRIPTION
Supported commands are identity, verify-profile, and eval. Exit codes are:
0 success; 2 caller/input/profile rejection; 3 conformance failure;
4 unexpected internal/tool failure.

The deterministic CLI contract begins after PowerShell starts this script.
Shell or PowerShell parser failures that prevent script execution are outside
the SpecOps CLI contract.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$rawArguments = @($args)

function ConvertTo-SpecOpsCliJson {
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Value
    )

    $options = [System.Text.Json.JsonSerializerOptions]::new()
    $options.WriteIndented = $false
    return [System.Text.Json.JsonSerializer]::Serialize($Value, $Value.GetType(), $options)
}

function Write-SpecOpsCliError {
    param(
        [Parameter(Mandatory)]
        [int] $Code,

        [Parameter(Mandatory)]
        [string] $ErrorClass,

        [Parameter(Mandatory)]
        [string] $Message
    )

    $errorBody = [System.Collections.Generic.Dictionary[string, object]]::new()
    $errorBody.Add('code', $Code)
    $errorBody.Add('class', $ErrorClass)
    $errorBody.Add('message', $Message)
    $body = [System.Collections.Generic.Dictionary[string, object]]::new()
    $body.Add('error', $errorBody)
    [Console]::Out.WriteLine((ConvertTo-SpecOpsCliJson -Value $body))
}

function Stop-SpecOpsCliInput {
    param(
        [Parameter(Mandatory)]
        [string] $ErrorClass,

        [Parameter(Mandatory)]
        [string] $Message
    )

    Write-SpecOpsCliError -Code 2 -ErrorClass $ErrorClass -Message $Message
    exit 2
}

try {
    if ($rawArguments.Count -eq 0) {
        Stop-SpecOpsCliInput -ErrorClass 'MISSING_COMMAND' -Message 'A command is required.'
    }

    $command = [string] $rawArguments[0]
    $isIdentity = [string]::Equals($command, 'identity', [System.StringComparison]::Ordinal)
    $isVerifyProfile = [string]::Equals($command, 'verify-profile', [System.StringComparison]::Ordinal)
    $isEval = [string]::Equals($command, 'eval', [System.StringComparison]::Ordinal)
    if (-not $isIdentity -and -not $isVerifyProfile -and -not $isEval) {
        Stop-SpecOpsCliInput -ErrorClass 'UNSUPPORTED_COMMAND' -Message 'Supported commands are identity, verify-profile, and eval.'
    }

    if ($isVerifyProfile -and $rawArguments.Count -gt 1) {
        $unexpected = [string] $rawArguments[1]
        if ($unexpected.StartsWith('-', [System.StringComparison]::Ordinal)) {
            Stop-SpecOpsCliInput -ErrorClass 'UNEXPECTED_OPTION' -Message 'verify-profile does not accept options.'
        }
        Stop-SpecOpsCliInput -ErrorClass 'UNEXPECTED_POSITIONAL_ARGUMENT' -Message 'verify-profile does not accept positional arguments.'
    }

    if ($isIdentity) {
        $path = $null
        $mode = $null
        $pathSeen = $false
        $modeSeen = $false
        $argumentIndex = 1

        while ($argumentIndex -lt $rawArguments.Count) {
            $option = [string] $rawArguments[$argumentIndex]
            $isPathOption = [string]::Equals($option, '-Path', [System.StringComparison]::Ordinal)
            $isModeOption = [string]::Equals($option, '-Mode', [System.StringComparison]::Ordinal)

            if (-not $option.StartsWith('-', [System.StringComparison]::Ordinal)) {
                Stop-SpecOpsCliInput -ErrorClass 'UNEXPECTED_POSITIONAL_ARGUMENT' -Message 'identity accepts only -Path and -Mode options.'
            }
            if (-not $isPathOption -and -not $isModeOption) {
                Stop-SpecOpsCliInput -ErrorClass 'UNKNOWN_OPTION' -Message "Unknown identity option: $option"
            }
            if (($isPathOption -and $pathSeen) -or ($isModeOption -and $modeSeen)) {
                Stop-SpecOpsCliInput -ErrorClass 'DUPLICATE_OPTION' -Message "Option supplied more than once: $option"
            }
            if (($argumentIndex + 1) -ge $rawArguments.Count) {
                Stop-SpecOpsCliInput -ErrorClass 'MISSING_OPTION_VALUE' -Message "Option requires a following value: $option"
            }

            $optionValue = [string] $rawArguments[$argumentIndex + 1]
            if ([string]::IsNullOrEmpty($optionValue) -or $optionValue.StartsWith('-', [System.StringComparison]::Ordinal)) {
                Stop-SpecOpsCliInput -ErrorClass 'MISSING_OPTION_VALUE' -Message "Option requires a following value: $option"
            }

            if ($isPathOption) {
                $pathSeen = $true
                $path = $optionValue
            }
            else {
                $modeSeen = $true
                $mode = $optionValue
            }
            $argumentIndex += 2
        }

        if (-not $pathSeen) {
            Stop-SpecOpsCliInput -ErrorClass 'MISSING_PATH' -Message 'identity requires -Path.'
        }
        if (-not $modeSeen) {
            Stop-SpecOpsCliInput -ErrorClass 'MISSING_MODE' -Message 'identity requires -Mode.'
        }
        if (-not [string]::Equals($mode, 'FULL_JSON', [System.StringComparison]::Ordinal) -and
            -not [string]::Equals($mode, 'EVAL_DEFINITION', [System.StringComparison]::Ordinal)) {
            Stop-SpecOpsCliInput -ErrorClass 'UNSUPPORTED_MODE' -Message 'Mode must be FULL_JSON or EVAL_DEFINITION.'
        }
    }

    if ($isEval) {
        $definitionId = $null
        $definitionIdSeen = $false
        $argumentIndex = 1
        while ($argumentIndex -lt $rawArguments.Count) {
            $option = [string] $rawArguments[$argumentIndex]
            if (-not $option.StartsWith('-', [System.StringComparison]::Ordinal)) {
                Stop-SpecOpsCliInput -ErrorClass 'UNEXPECTED_POSITIONAL_ARGUMENT' -Message 'eval accepts only the -DefinitionId option.'
            }
            if (-not [string]::Equals($option, '-DefinitionId', [System.StringComparison]::Ordinal)) {
                Stop-SpecOpsCliInput -ErrorClass 'UNKNOWN_OPTION' -Message "Unknown eval option: $option"
            }
            if ($definitionIdSeen) {
                Stop-SpecOpsCliInput -ErrorClass 'DUPLICATE_OPTION' -Message 'Option supplied more than once: -DefinitionId'
            }
            if (($argumentIndex + 1) -ge $rawArguments.Count) {
                Stop-SpecOpsCliInput -ErrorClass 'MISSING_OPTION_VALUE' -Message 'Option requires a following value: -DefinitionId'
            }
            $optionValue = [string] $rawArguments[$argumentIndex + 1]
            if ([string]::IsNullOrEmpty($optionValue) -or $optionValue.StartsWith('-', [System.StringComparison]::Ordinal)) {
                Stop-SpecOpsCliInput -ErrorClass 'MISSING_OPTION_VALUE' -Message 'Option requires a following value: -DefinitionId'
            }
            $definitionIdSeen = $true
            $definitionId = $optionValue
            $argumentIndex += 2
        }
        if (-not $definitionIdSeen) {
            Stop-SpecOpsCliInput -ErrorClass 'MISSING_DEFINITION_ID' -Message 'eval requires -DefinitionId.'
        }
    }

    $modulePath = [System.IO.Path]::Combine($PSScriptRoot, 'SpecOps.Core.psm1')
    Import-Module -Name $modulePath -Force -ErrorAction Stop

    if ($isIdentity) {
        $identity = Get-SpecOpsJsonContentIdentity -Path $path -Mode $mode
        $body = [System.Collections.Generic.Dictionary[string, object]]::new()
        $body.Add('profileId', $identity.profileId)
        $body.Add('value', $identity.value)
        [Console]::Out.WriteLine((ConvertTo-SpecOpsCliJson -Value $body))
        exit 0
    }

    if ($isEval) {
        $repositoryModulePath = [System.IO.Path]::Combine($PSScriptRoot, 'SpecOps.Repository.psm1')
        $evalModulePath = [System.IO.Path]::Combine($PSScriptRoot, 'SpecOps.Eval.psm1')
        Import-Module -Name $evalModulePath -Force -ErrorAction Stop
        Import-Module -Name $repositoryModulePath -Force -ErrorAction Stop
        Import-Module -Name $modulePath -Force -ErrorAction Stop
        $repositoryRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, '..', '..'))
        $adapter = New-SpecOpsGitRepositoryAdapter -RepositoryPath $repositoryRoot
        $evalArguments = @{
            RepositoryAdapter = $adapter
            DefinitionId = $definitionId
        }
        if ([string]::Equals($definitionId, 'unity-editmode-validation', [System.StringComparison]::Ordinal)) {
            $evalArguments.UnityExecutionAdapter = Get-SpecOpsUnityProductionExecutionAdapter
        }
        $result = Invoke-SpecOpsEvaluation @evalArguments
        [Console]::Out.WriteLine((ConvertTo-SpecOpsCliJson -Value $result))
        if ([string]::Equals([string]$result.overallResult, 'PASS', [System.StringComparison]::Ordinal)) { exit 0 }
        exit 3
    }

    $repositoryRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, '..', '..'))
    $vectorSetPath = [System.IO.Path]::Combine($repositoryRoot, '.specops', 'contracts', 'content-identity-profile-v1.vectors.json')
    $summary = Test-SpecOpsContentIdentityProfile -VectorSetPath $vectorSetPath

    $resultList = [System.Collections.Generic.List[object]]::new()
    foreach ($result in $summary.results) {
        $item = [System.Collections.Generic.Dictionary[string, object]]::new()
        $item.Add('id', $result.id)
        $item.Add('status', $result.status)
        if (-not [string]::IsNullOrEmpty($result.detail)) {
            $item.Add('detail', $result.detail)
        }
        $resultList.Add($item)
    }

    $body = [System.Collections.Generic.Dictionary[string, object]]::new()
    $body.Add('profileId', $summary.profileId)
    $body.Add('total', $summary.total)
    $body.Add('passed', $summary.passed)
    $body.Add('failed', $summary.failed)
    $body.Add('results', $resultList)
    [Console]::Out.WriteLine((ConvertTo-SpecOpsCliJson -Value $body))

    if ($summary.failed -gt 0) { exit 3 }
    exit 0
}
catch {
    try {
        if ($null -ne (Get-Command -Name Get-SpecOpsErrorMetadata -ErrorAction SilentlyContinue)) {
            $metadata = Get-SpecOpsErrorMetadata -ErrorRecord $_
        }
        else {
            $metadata = [pscustomobject]@{ ExitCode = 4; RejectionClass = 'INTERNAL_TOOL_FAILURE' }
        }
        Write-SpecOpsCliError -Code $metadata.ExitCode -ErrorClass $metadata.RejectionClass -Message $_.Exception.Message
        exit $metadata.ExitCode
    }
    catch {
        [Console]::Out.WriteLine('{"error":{"code":4,"class":"INTERNAL_TOOL_FAILURE","message":"The CLI could not serialize the failure."}}')
        exit 4
    }
}
