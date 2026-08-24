[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:TestCount = 0
$script:Failures = [System.Collections.Generic.List[string]]::new()

function Test-Assertion {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [bool] $Condition,
        [string] $Detail = ''
    )

    $script:TestCount++
    if (-not $Condition) {
        $script:Failures.Add($(if ([string]::IsNullOrEmpty($Detail)) { $Name } else { '{0}: {1}' -f $Name, $Detail }))
    }
}

function Test-Equal {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [AllowNull()] $Expected,
        [AllowNull()] $Actual
    )

    $detail = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, 'expected=[{0}] actual=[{1}]', $Expected, $Actual)
    if ($Expected -is [string] -and $Actual -is [string]) {
        $equal = [string]::Equals($Expected, $Actual, [System.StringComparison]::Ordinal)
    }
    else {
        $equal = $Expected -eq $Actual
    }
    Test-Assertion -Name $Name -Condition $equal -Detail $detail
}

function Write-TestUtf8 {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [AllowEmptyString()] [Parameter(Mandatory)] [string] $Text
    )

    $encoding = [System.Text.UTF8Encoding]::new($false, $true)
    [System.IO.File]::WriteAllBytes($Path, $encoding.GetBytes($Text))
}

function Invoke-SpecOpsCliProcess {
    param(
        [Parameter(Mandatory)] [string] $PowerShellPath,
        [Parameter(Mandatory)] [string] $CliPath,
        [AllowEmptyCollection()] [Parameter(Mandatory)] [string[]] $Arguments
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $PowerShellPath
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    [void] $startInfo.ArgumentList.Add('-NoProfile')
    [void] $startInfo.ArgumentList.Add('-File')
    [void] $startInfo.ArgumentList.Add($CliPath)
    foreach ($argument in $Arguments) {
        [void] $startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::Start($startInfo)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Stdout = $stdout
        Stderr = $stderr
    }
}

function Test-SpecOpsCliRejection {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $PowerShellPath,
        [Parameter(Mandatory)] [string] $CliPath,
        [AllowEmptyCollection()] [Parameter(Mandatory)] [string[]] $Arguments,
        [Parameter(Mandatory)] [string] $ExpectedClass
    )

    $result = Invoke-SpecOpsCliProcess -PowerShellPath $PowerShellPath -CliPath $CliPath -Arguments $Arguments
    $trimmedStdout = $result.Stdout.Trim()
    $nonEmptyLines = @($trimmedStdout -split '\r?\n' | Where-Object { $_.Length -gt 0 })
    $parsed = $null
    $parsedSuccessfully = $false
    try {
        $parsed = $trimmedStdout | ConvertFrom-Json -ErrorAction Stop
        $parsedSuccessfully = $null -ne $parsed
    }
    catch {
        $parsedSuccessfully = $false
    }

    Test-Equal -Name ($Name + ' exit') -Expected 2 -Actual $result.ExitCode
    Test-Equal -Name ($Name + ' stdout object count') -Expected 1 -Actual $nonEmptyLines.Count
    Test-Assertion -Name ($Name + ' stdout parses as JSON') -Condition $parsedSuccessfully
    if ($parsedSuccessfully) {
        Test-Equal -Name ($Name + ' error code') -Expected 2 -Actual $parsed.error.code
        Test-Equal -Name ($Name + ' rejection class') -Expected $ExpectedClass -Actual $parsed.error.class
    }
    Test-Equal -Name ($Name + ' stderr empty') -Expected '' -Actual $result.Stderr
}

$modulePath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, '..', 'SpecOps.Core.psm1'))
$cliPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, '..', 'Invoke-SpecOps.ps1'))
$repositoryRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, '..', '..', '..'))
$vectorPath = [System.IO.Path]::Combine($repositoryRoot, '.specops', 'contracts', 'content-identity-profile-v1.vectors.json')
$temporaryRoot = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'specops-e8c1b-' + [guid]::NewGuid().ToString('N'))
$evidencePath = [System.IO.Path]::Combine($repositoryRoot, '.specops', 'evidence')
$evidenceExistedBefore = [System.IO.Directory]::Exists($evidencePath)

try {
    [void] [System.IO.Directory]::CreateDirectory($temporaryRoot)
    Import-Module -Name $modulePath -Force

    $profile = Test-SpecOpsContentIdentityProfile -VectorSetPath $vectorPath
    $vectorData = Get-Content -LiteralPath $vectorPath -Raw | ConvertFrom-Json
    Test-Equal -Name 'profile total' -Expected 18 -Actual $profile.total
    Test-Equal -Name 'profile failures' -Expected 0 -Actual $profile.failed
    foreach ($result in $profile.results) {
        Test-Equal -Name ('profile vector {0}' -f $result.id) -Expected 'PASS' -Actual $result.status
    }

    $repeatText = '{"z":[3,2,1],"a":"repeat"}'
    $repeatBytes = [System.Text.UTF8Encoding]::new($false, $true).GetBytes($repeatText)
    $repeatOne = ConvertTo-SpecOpsCanonicalJson -Bytes $repeatBytes -Mode FULL_JSON
    $repeatTwo = ConvertTo-SpecOpsCanonicalJson -Bytes $repeatBytes -Mode FULL_JSON
    Test-Equal -Name 'canonical repeatability' -Expected $repeatOne -Actual $repeatTwo

    $repeatPath = [System.IO.Path]::Combine($temporaryRoot, 'repeat.json')
    Write-TestUtf8 -Path $repeatPath -Text $repeatText
    $identityOne = Get-SpecOpsJsonContentIdentity -Path $repeatPath -Mode FULL_JSON
    $identityTwo = Get-SpecOpsJsonContentIdentity -Path $repeatPath -Mode FULL_JSON
    Test-Equal -Name 'digest repeatability' -Expected $identityOne.value -Actual $identityTwo.value

    $originalCulture = [System.Globalization.CultureInfo]::CurrentCulture
    $originalUiCulture = [System.Globalization.CultureInfo]::CurrentUICulture
    try {
        [System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('en-US')
        [System.Globalization.CultureInfo]::CurrentUICulture = [System.Globalization.CultureInfo]::GetCultureInfo('en-US')
        $sortingText = ($vectorData.vectors | Where-Object id -eq 'rfc8785-non-ascii-property-order').inputJsonText
        $numberText = ($vectorData.vectors | Where-Object id -eq 'rfc8785-canonical-sample').inputJsonText
        $sortingBytes = [System.Text.UTF8Encoding]::new($false, $true).GetBytes($sortingText)
        $numberBytes = [System.Text.UTF8Encoding]::new($false, $true).GetBytes($numberText)
        $cultureOne = ConvertTo-SpecOpsCanonicalJson -Bytes $repeatBytes -Mode FULL_JSON
        $sortingCultureOne = ConvertTo-SpecOpsCanonicalJson -Bytes $sortingBytes -Mode FULL_JSON
        $numberCultureOne = ConvertTo-SpecOpsCanonicalJson -Bytes $numberBytes -Mode FULL_JSON
        [System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('tr-TR')
        [System.Globalization.CultureInfo]::CurrentUICulture = [System.Globalization.CultureInfo]::GetCultureInfo('tr-TR')
        $cultureTwo = ConvertTo-SpecOpsCanonicalJson -Bytes $repeatBytes -Mode FULL_JSON
        $sortingCultureTwo = ConvertTo-SpecOpsCanonicalJson -Bytes $sortingBytes -Mode FULL_JSON
        $numberCultureTwo = ConvertTo-SpecOpsCanonicalJson -Bytes $numberBytes -Mode FULL_JSON
        Test-Equal -Name 'culture independence' -Expected $cultureOne -Actual $cultureTwo
        Test-Equal -Name 'non-ASCII sorting culture independence' -Expected $sortingCultureOne -Actual $sortingCultureTwo
        Test-Equal -Name 'number culture independence' -Expected $numberCultureOne -Actual $numberCultureTwo
    }
    finally {
        [System.Globalization.CultureInfo]::CurrentCulture = $originalCulture
        [System.Globalization.CultureInfo]::CurrentUICulture = $originalUiCulture
    }

    $evalOnePath = [System.IO.Path]::Combine($temporaryRoot, 'eval-one.json')
    $evalTwoPath = [System.IO.Path]::Combine($temporaryRoot, 'eval-two.json')
    $evalNestedPath = [System.IO.Path]::Combine($temporaryRoot, 'eval-nested.json')
    Write-TestUtf8 -Path $evalOnePath -Text '{"contentIdentity":{"algorithm":"one","value":"one"},"nested":{"contentIdentity":{"value":"included-a"}}}'
    Write-TestUtf8 -Path $evalTwoPath -Text '{"contentIdentity":{"algorithm":"two","value":"two"},"nested":{"contentIdentity":{"value":"included-a"}}}'
    Write-TestUtf8 -Path $evalNestedPath -Text '{"contentIdentity":{"algorithm":"two","value":"two"},"nested":{"contentIdentity":{"value":"included-b"}}}'
    $evalOne = Get-SpecOpsJsonContentIdentity -Path $evalOnePath -Mode EVAL_DEFINITION
    $evalTwo = Get-SpecOpsJsonContentIdentity -Path $evalTwoPath -Mode EVAL_DEFINITION
    $evalNested = Get-SpecOpsJsonContentIdentity -Path $evalNestedPath -Mode EVAL_DEFINITION
    Test-Equal -Name 'root contentIdentity exclusion' -Expected $evalOne.value -Actual $evalTwo.value
    Test-Assertion -Name 'nested contentIdentity included' -Condition (-not [string]::Equals($evalTwo.value, $evalNested.value, [System.StringComparison]::Ordinal))

    $sameIds = Test-SpecOpsUniqueIds -Items @([pscustomobject]@{ id = 'a' }, [pscustomobject]@{ id = 'a' }) -IdProperty id
    $caseIds = Test-SpecOpsUniqueIds -Items @([pscustomobject]@{ id = 'A' }, [pscustomobject]@{ id = 'a' }) -IdProperty id
    $missingId = Test-SpecOpsUniqueIds -Items @([pscustomobject]@{ id = '' }) -IdProperty id
    $absentId = Test-SpecOpsUniqueIds -Items @([pscustomobject]@{ name = 'missing' }) -IdProperty id
    Test-Assertion -Name 'duplicate ID detected' -Condition (-not $sameIds.IsValid -and $sameIds.DuplicateIds.Count -eq 1 -and $sameIds.DuplicateIds[0] -ceq 'a')
    Test-Assertion -Name 'ID comparison is case-sensitive' -Condition $caseIds.IsValid
    Test-Assertion -Name 'empty ID rejected' -Condition (-not $missingId.IsValid -and $missingId.MissingIdIndexes[0] -eq 0)
    Test-Assertion -Name 'missing ID rejected' -Condition (-not $absentId.IsValid -and $absentId.MissingIdIndexes[0] -eq 0)

    $coverageExact = Compare-SpecOpsIdCoverage -ExpectedIds @('a', 'b') -ActualIds @('a', 'b')
    $coverageReordered = Compare-SpecOpsIdCoverage -ExpectedIds @('a', 'b') -ActualIds @('b', 'a')
    $coverageMissing = Compare-SpecOpsIdCoverage -ExpectedIds @('a', 'b') -ActualIds @('a')
    $coverageExtra = Compare-SpecOpsIdCoverage -ExpectedIds @('a') -ActualIds @('a', 'b')
    $coverageDuplicateExpected = Compare-SpecOpsIdCoverage -ExpectedIds @('a', 'a') -ActualIds @('a')
    $coverageDuplicateActual = Compare-SpecOpsIdCoverage -ExpectedIds @('a') -ActualIds @('a', 'a')
    Test-Assertion -Name 'exact coverage' -Condition $coverageExact.IsExact
    Test-Assertion -Name 'coverage ignores ordering' -Condition $coverageReordered.IsExact
    Test-Assertion -Name 'coverage missing diagnostic' -Condition (-not $coverageMissing.IsExact -and $coverageMissing.MissingIds[0] -ceq 'b')
    Test-Assertion -Name 'coverage extra diagnostic' -Condition (-not $coverageExtra.IsExact -and $coverageExtra.ExtraIds[0] -ceq 'b')
    Test-Assertion -Name 'coverage duplicate expected diagnostic' -Condition (-not $coverageDuplicateExpected.IsExact -and $coverageDuplicateExpected.DuplicateExpectedIds[0] -ceq 'a')
    Test-Assertion -Name 'coverage duplicate actual diagnostic' -Condition (-not $coverageDuplicateActual.IsExact -and $coverageDuplicateActual.DuplicateActualIds[0] -ceq 'a')
    Test-Assertion -Name 'ordinal equality exact' -Condition (Test-SpecOpsOrdinalEqual -Left 'a' -Right 'a')
    Test-Assertion -Name 'ordinal equality case-sensitive' -Condition (-not (Test-SpecOpsOrdinalEqual -Left 'A' -Right 'a'))

    $precomposedDigest = ($vectorData.vectors | Where-Object id -eq 'full-unicode-precomposed').expectedSha256Hex
    $decomposedDigest = ($vectorData.vectors | Where-Object id -eq 'full-unicode-decomposed').expectedSha256Hex
    Test-Assertion -Name 'Unicode normalization is not applied' -Condition (-not [string]::Equals($precomposedDigest, $decomposedDigest, [System.StringComparison]::Ordinal))

    $numberCases = @(
        @('0000000000000000', '0'),
        @('8000000000000000', '0'),
        @('0000000000000001', '5e-324'),
        @('8000000000000001', '-5e-324'),
        @('7fefffffffffffff', '1.7976931348623157e+308'),
        @('ffefffffffffffff', '-1.7976931348623157e+308'),
        @('4340000000000000', '9007199254740992'),
        @('c340000000000000', '-9007199254740992'),
        @('4430000000000000', '295147905179352830000'),
        @('44b52d02c7e14af5', '9.999999999999997e+22'),
        @('44b52d02c7e14af6', '1e+23'),
        @('44b52d02c7e14af7', '1.0000000000000001e+23'),
        @('444b1ae4d6e2ef4e', '999999999999999700000'),
        @('444b1ae4d6e2ef4f', '999999999999999900000'),
        @('444b1ae4d6e2ef50', '1e+21'),
        @('3eb0c6f7a0b5ed8c', '9.999999999999997e-7'),
        @('3eb0c6f7a0b5ed8d', '0.000001'),
        @('41b3de4355555553', '333333333.3333332'),
        @('41b3de4355555554', '333333333.33333325'),
        @('41b3de4355555555', '333333333.3333333'),
        @('41b3de4355555556', '333333333.3333334'),
        @('41b3de4355555557', '333333333.33333343'),
        @('becbf647612f3696', '-0.0000033333333333333333'),
        @('43143ff3c1cb0959', '1424953923781206.2')
    )
    $coreModule = Get-Module -Name SpecOps.Core
    foreach ($case in $numberCases) {
        $bits = [Convert]::ToUInt64($case[0], 16)
        $bytes = [BitConverter]::GetBytes($bits)
        $value = [BitConverter]::ToDouble($bytes, 0)
        $actualNumber = & $coreModule { param([double] $number) ConvertTo-SpecOpsJcsNumber -Value $number } $value
        Test-Equal -Name ('RFC Appendix B number {0}' -f $case[0]) -Expected $case[1] -Actual $actualNumber
    }
    foreach ($unsupported in @([double]::NaN, [double]::PositiveInfinity, [double]::NegativeInfinity)) {
        $rejected = $false
        try { [void] (& $coreModule { param([double] $number) ConvertTo-SpecOpsJcsNumber -Value $number } $unsupported) }
        catch { $rejected = $true }
        Test-Assertion -Name ('non-finite number rejected {0}' -f $unsupported) -Condition $rejected
    }

    $duplicatePath = [System.IO.Path]::Combine($temporaryRoot, 'duplicate.json')
    Write-TestUtf8 -Path $duplicatePath -Text '{"a":1,"a":2}'
    $escapedDuplicatePath = [System.IO.Path]::Combine($temporaryRoot, 'escaped-duplicate.json')
    Write-TestUtf8 -Path $escapedDuplicatePath -Text '{"a":1,"\u0061":2}'
    $caseDistinctPath = [System.IO.Path]::Combine($temporaryRoot, 'case-distinct.json')
    Write-TestUtf8 -Path $caseDistinctPath -Text '{"a":2,"A":1}'
    $caseDistinctCanonical = ConvertTo-SpecOpsCanonicalJson -Bytes ([IO.File]::ReadAllBytes($caseDistinctPath)) -Mode FULL_JSON
    Test-Equal -Name 'JSON member identity is ordinal and case-sensitive' -Expected '{"A":1,"a":2}' -Actual $caseDistinctCanonical
    $malformedPath = [System.IO.Path]::Combine($temporaryRoot, 'malformed.json')
    Write-TestUtf8 -Path $malformedPath -Text '{"a":'
    $commentPath = [System.IO.Path]::Combine($temporaryRoot, 'comment.json')
    Write-TestUtf8 -Path $commentPath -Text '{"a":1/*comment*/}'
    $trailingCommaPath = [System.IO.Path]::Combine($temporaryRoot, 'trailing-comma.json')
    Write-TestUtf8 -Path $trailingCommaPath -Text '{"a":1,}'
    $unsupportedNumberPath = [System.IO.Path]::Combine($temporaryRoot, 'unsupported-number.json')
    Write-TestUtf8 -Path $unsupportedNumberPath -Text '{"n":1e9999}'
    $malformedUtf8Path = [System.IO.Path]::Combine($temporaryRoot, 'malformed-utf8.json')
    [System.IO.File]::WriteAllBytes($malformedUtf8Path, [byte[]] @(0x7B, 0x22, 0x78, 0x22, 0x3A, 0x22, 0xC3, 0x28, 0x22, 0x7D))
    $bomPath = [System.IO.Path]::Combine($temporaryRoot, 'bom.json')
    [System.IO.File]::WriteAllBytes($bomPath, [byte[]] @(0xEF, 0xBB, 0xBF, 0x7B, 0x7D))
    $loneSurrogatePath = [System.IO.Path]::Combine($temporaryRoot, 'lone-surrogate.json')
    Write-TestUtf8 -Path $loneSurrogatePath -Text '{"x":"\ud800"}'
    $loneLowSurrogatePath = [System.IO.Path]::Combine($temporaryRoot, 'lone-low-surrogate.json')
    Write-TestUtf8 -Path $loneLowSurrogatePath -Text '{"x":"\udc00"}'
    $loneSurrogateNamePath = [System.IO.Path]::Combine($temporaryRoot, 'lone-surrogate-name.json')
    Write-TestUtf8 -Path $loneSurrogateNamePath -Text '{"\ud800":1}'
    $invalidEvalPath = [System.IO.Path]::Combine($temporaryRoot, 'invalid-eval.json')
    Write-TestUtf8 -Path $invalidEvalPath -Text '[]'

    foreach ($rejection in @(
        @($duplicatePath, 'FULL_JSON', 'DUPLICATE_OBJECT_MEMBER_NAME'),
        @($escapedDuplicatePath, 'FULL_JSON', 'DUPLICATE_OBJECT_MEMBER_NAME'),
        @($malformedPath, 'FULL_JSON', 'MALFORMED_JSON'),
        @($commentPath, 'FULL_JSON', 'MALFORMED_JSON'),
        @($trailingCommaPath, 'FULL_JSON', 'MALFORMED_JSON'),
        @($unsupportedNumberPath, 'FULL_JSON', 'UNSUPPORTED_NUMBER'),
        @($malformedUtf8Path, 'FULL_JSON', 'MALFORMED_UTF8'),
        @($bomPath, 'FULL_JSON', 'LEADING_UTF8_BOM'),
        @($loneSurrogatePath, 'FULL_JSON', 'INVALID_UNICODE_DATA'),
        @($loneLowSurrogatePath, 'FULL_JSON', 'INVALID_UNICODE_DATA'),
        @($loneSurrogateNamePath, 'FULL_JSON', 'INVALID_UNICODE_DATA'),
        @($invalidEvalPath, 'EVAL_DEFINITION', 'INVALID_EVAL_DEFINITION_ROOT')
    )) {
        $actualClass = 'NO_REJECTION'
        try { [void] (Get-SpecOpsJsonContentIdentity -Path $rejection[0] -Mode $rejection[1]) }
        catch { $actualClass = (Get-SpecOpsErrorMetadata -ErrorRecord $_).RejectionClass }
        Test-Equal -Name ('rejection class {0}' -f [System.IO.Path]::GetFileName($rejection[0])) -Expected $rejection[2] -Actual $actualClass
    }

    $pwshPath = (Get-Command -Name pwsh -ErrorAction Stop).Source
    $cliSuccess = Invoke-SpecOpsCliProcess -PowerShellPath $pwshPath -CliPath $cliPath -Arguments @('identity', '-Path', $repeatPath, '-Mode', 'FULL_JSON')
    $cliSuccessObject = $cliSuccess.Stdout | ConvertFrom-Json
    Test-Equal -Name 'CLI identity success exit' -Expected 0 -Actual $cliSuccess.ExitCode
    Test-Equal -Name 'CLI identity profile' -Expected 'specops-json-jcs-sha256-v1' -Actual $cliSuccessObject.profileId
    Test-Equal -Name 'CLI identity digest' -Expected $identityOne.value -Actual $cliSuccessObject.value
    Test-Equal -Name 'CLI identity stderr empty' -Expected '' -Actual $cliSuccess.Stderr

    $cliEval = Invoke-SpecOpsCliProcess -PowerShellPath $pwshPath -CliPath $cliPath -Arguments @('identity', '-Path', $evalOnePath, '-Mode', 'EVAL_DEFINITION')
    $cliEvalObject = $cliEval.Stdout | ConvertFrom-Json
    Test-Equal -Name 'CLI eval identity success exit' -Expected 0 -Actual $cliEval.ExitCode
    Test-Equal -Name 'CLI eval identity digest' -Expected $evalOne.value -Actual $cliEvalObject.value
    Test-Equal -Name 'CLI eval identity stderr empty' -Expected '' -Actual $cliEval.Stderr

    $cliReject = Invoke-SpecOpsCliProcess -PowerShellPath $pwshPath -CliPath $cliPath -Arguments @('identity', '-Path', $duplicatePath, '-Mode', 'FULL_JSON')
    $cliRejectObject = $cliReject.Stdout | ConvertFrom-Json
    Test-Equal -Name 'CLI rejected identity exit' -Expected 2 -Actual $cliReject.ExitCode
    Test-Equal -Name 'CLI rejected identity class' -Expected 'DUPLICATE_OBJECT_MEMBER_NAME' -Actual $cliRejectObject.error.class
    Test-Equal -Name 'CLI rejected identity stderr empty' -Expected '' -Actual $cliReject.Stderr

    Test-SpecOpsCliRejection -Name 'CLI no command' -PowerShellPath $pwshPath -CliPath $cliPath -Arguments @() -ExpectedClass 'MISSING_COMMAND'
    Test-SpecOpsCliRejection -Name 'CLI unknown command' -PowerShellPath $pwshPath -CliPath $cliPath -Arguments @('unknown') -ExpectedClass 'UNSUPPORTED_COMMAND'
    Test-SpecOpsCliRejection -Name 'CLI unknown option' -PowerShellPath $pwshPath -CliPath $cliPath -Arguments @('identity', '-Unknown', 'value') -ExpectedClass 'UNKNOWN_OPTION'
    Test-SpecOpsCliRejection -Name 'CLI missing Path' -PowerShellPath $pwshPath -CliPath $cliPath -Arguments @('identity', '-Mode', 'FULL_JSON') -ExpectedClass 'MISSING_PATH'
    Test-SpecOpsCliRejection -Name 'CLI missing Mode' -PowerShellPath $pwshPath -CliPath $cliPath -Arguments @('identity', '-Path', $repeatPath) -ExpectedClass 'MISSING_MODE'
    Test-SpecOpsCliRejection -Name 'CLI Path missing value' -PowerShellPath $pwshPath -CliPath $cliPath -Arguments @('identity', '-Path') -ExpectedClass 'MISSING_OPTION_VALUE'
    Test-SpecOpsCliRejection -Name 'CLI Mode missing value' -PowerShellPath $pwshPath -CliPath $cliPath -Arguments @('identity', '-Mode') -ExpectedClass 'MISSING_OPTION_VALUE'
    Test-SpecOpsCliRejection -Name 'CLI unsupported Mode' -PowerShellPath $pwshPath -CliPath $cliPath -Arguments @('identity', '-Path', $repeatPath, '-Mode', 'INVALID') -ExpectedClass 'UNSUPPORTED_MODE'
    Test-SpecOpsCliRejection -Name 'CLI extra positional' -PowerShellPath $pwshPath -CliPath $cliPath -Arguments @('identity', 'extra', '-Path', $repeatPath, '-Mode', 'FULL_JSON') -ExpectedClass 'UNEXPECTED_POSITIONAL_ARGUMENT'
    Test-SpecOpsCliRejection -Name 'CLI duplicate option' -PowerShellPath $pwshPath -CliPath $cliPath -Arguments @('identity', '-Path', $repeatPath, '-Path', $repeatPath, '-Mode', 'FULL_JSON') -ExpectedClass 'DUPLICATE_OPTION'
    Test-SpecOpsCliRejection -Name 'CLI verify option' -PowerShellPath $pwshPath -CliPath $cliPath -Arguments @('verify-profile', '-Path', $repeatPath) -ExpectedClass 'UNEXPECTED_OPTION'

    $cliVerify = Invoke-SpecOpsCliProcess -PowerShellPath $pwshPath -CliPath $cliPath -Arguments @('verify-profile')
    $cliVerifyObject = $cliVerify.Stdout | ConvertFrom-Json
    Test-Equal -Name 'CLI profile verification exit' -Expected 0 -Actual $cliVerify.ExitCode
    Test-Equal -Name 'CLI profile verification failures' -Expected 0 -Actual $cliVerifyObject.failed
    Test-Equal -Name 'CLI profile verification stderr empty' -Expected '' -Actual $cliVerify.Stderr

    $productionSource = [System.IO.File]::ReadAllText($modulePath) + [System.IO.File]::ReadAllText($cliPath)
    foreach ($vector in $vectorData.vectors) {
        Test-Assertion -Name ('production excludes vector ID {0}' -f $vector.id) -Condition (-not $productionSource.Contains($vector.id))
        if ($vector.expectedOutcome -eq 'IDENTITY') {
            Test-Assertion -Name ('production excludes vector digest {0}' -f $vector.id) -Condition (-not $productionSource.Contains($vector.expectedSha256Hex))
        }
    }
    Test-Assertion -Name 'no ConvertTo-Json in production' -Condition (-not $productionSource.Contains('ConvertTo-Json'))
    Test-Assertion -Name 'no network API in production' -Condition (-not $productionSource.Contains('Invoke-WebRequest') -and -not $productionSource.Contains('HttpClient'))
    Test-Assertion -Name 'no hidden external runtime in production' -Condition (-not $productionSource.Contains('node') -and -not $productionSource.Contains('python'))
    Test-Assertion -Name 'ordinal comparer present' -Condition $productionSource.Contains('StringComparer]::Ordinal')
    Test-Equal -Name 'evidence directory existence unchanged' -Expected $evidenceExistedBefore -Actual ([System.IO.Directory]::Exists($evidencePath))
}
catch {
    $script:Failures.Add('UNHANDLED: ' + $_.Exception.Message + [Environment]::NewLine + $_.ScriptStackTrace)
}
finally {
    if ([System.IO.Directory]::Exists($temporaryRoot)) {
        $resolvedTemporaryRoot = [System.IO.Path]::GetFullPath($temporaryRoot)
        $resolvedSystemTemporary = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        if ($resolvedTemporaryRoot.StartsWith($resolvedSystemTemporary, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedTemporaryRoot -Recurse -Force
        }
    }
}

if ($script:Failures.Count -gt 0) {
    [Console]::Out.WriteLine('FAIL tests=' + $script:TestCount + ' failures=' + $script:Failures.Count)
    foreach ($failure in $script:Failures) { [Console]::Out.WriteLine('- ' + $failure) }
    exit 1
}

[Console]::Out.WriteLine('PASS tests=' + $script:TestCount + ' failures=0')
exit 0
