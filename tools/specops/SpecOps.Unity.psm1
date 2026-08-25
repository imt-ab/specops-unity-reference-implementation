Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:CanonicalTimeoutMilliseconds = 20 * 60 * 1000
$script:TerminationWaitMilliseconds = 30 * 1000
$script:WorkspacePrefix = 'specops-unity-'
$script:OwnerMarkerName = '.specops-unity-owner'
$script:Utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
$script:OwnedWorkspaces = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
$script:WindowsReservedDeviceNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($deviceName in @(
    'CON', 'PRN', 'AUX', 'NUL', 'CLOCK$', 'CONIN$', 'CONOUT$',
    'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
    'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
    "COM¹", "COM²", "COM³", "LPT¹", "LPT²", "LPT³"
)) {
    $null = $script:WindowsReservedDeviceNames.Add($deviceName)
}

function New-SpecOpsUnityException {
    param(
        [Parameter(Mandatory)] [string] $Message,
        [Parameter(Mandatory)] [string] $RejectionClass,
        [System.Exception] $InnerException
    )

    $exception = if ($null -eq $InnerException) {
        [System.InvalidOperationException]::new($Message)
    }
    else {
        [System.InvalidOperationException]::new($Message, $InnerException)
    }
    $exception.Data['SpecOpsRejectionClass'] = $RejectionClass
    return $exception
}

function Get-SpecOpsUnityErrorMetadata {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [System.Management.Automation.ErrorRecord] $ErrorRecord)

    $class = 'UNITY_ADAPTER_FAILURE'
    if ($ErrorRecord.Exception.Data.Contains('SpecOpsRejectionClass')) {
        $class = [string] $ErrorRecord.Exception.Data['SpecOpsRejectionClass']
    }
    return [pscustomobject]@{ RejectionClass = $class }
}

function Get-SpecOpsUnityOrdinalSortedStrings {
    param([string[]] $Values)

    $copy = [string[]] @($Values)
    [System.Array]::Sort($copy, [System.StringComparer]::Ordinal)
    return $copy
}

function Get-SpecOpsUnityNUnit3ResultValue {
    param([Parameter(Mandatory)] [System.Xml.XmlElement] $Element)

    $result = $Element.GetAttribute('result')
    if ([string]::IsNullOrEmpty($result) -or
        -not ($result -cin @('Passed', 'Failed', 'Inconclusive', 'Skipped'))) {
        throw (New-SpecOpsUnityException 'NUnit3 result contains a missing or unsupported result state.' 'UNITY_NUNIT_RESULT_UNSUPPORTED')
    }
    return $result
}

function Get-SpecOpsUnityNUnit3ObservedCounts {
    param([Parameter(Mandatory)] [System.Xml.XmlNodeList] $TestCaseNodes)

    $passed = 0L
    $failed = 0L
    $inconclusive = 0L
    $skipped = 0L
    foreach ($node in $TestCaseNodes) {
        $result = Get-SpecOpsUnityNUnit3ResultValue -Element ([System.Xml.XmlElement] $node)
        switch -CaseSensitive ($result) {
            'Passed' { $passed++ }
            'Failed' { $failed++ }
            'Inconclusive' { $inconclusive++ }
            'Skipped' { $skipped++ }
        }
    }
    return [pscustomobject]@{
        Total = [int64] $TestCaseNodes.Count
        Passed = $passed
        Failed = $failed
        Inconclusive = $inconclusive
        Skipped = $skipped
        NotExecuted = $skipped
    }
}

function Get-SpecOpsUnityNUnit3DeclaredCounts {
    param(
        [Parameter(Mandatory)] [System.Xml.XmlElement] $Element,
        [Parameter(Mandatory)] $ObservedCounts
    )

    $declared = [ordered]@{
        TestCaseCount = $null
        Total = $null
        Passed = $null
        Failed = $null
        Inconclusive = $null
        Skipped = $null
    }
    $mapping = [ordered]@{
        testcasecount = 'Total'
        total = 'Total'
        passed = 'Passed'
        failed = 'Failed'
        inconclusive = 'Inconclusive'
        skipped = 'Skipped'
    }
    foreach ($attributeName in $mapping.Keys) {
        if (-not $Element.HasAttribute($attributeName)) { continue }
        $value = 0L
        if (-not [int64]::TryParse($Element.GetAttribute($attributeName), [System.Globalization.NumberStyles]::None, [System.Globalization.CultureInfo]::InvariantCulture, [ref] $value)) {
            throw (New-SpecOpsUnityException 'NUnit3 summary contains an invalid declared count.' 'UNITY_NUNIT_COUNT_INVALID')
        }
        $propertyName = if ([string]::Equals($attributeName, 'testcasecount', [System.StringComparison]::Ordinal)) { 'TestCaseCount' } else { $attributeName.Substring(0, 1).ToUpperInvariant() + $attributeName.Substring(1) }
        $declared[$propertyName] = $value
        $observedProperty = $mapping[$attributeName]
        if ($value -ne [int64] $ObservedCounts.$observedProperty) {
            throw (New-SpecOpsUnityException 'NUnit3 declared and observed counts are inconsistent.' 'UNITY_NUNIT_COUNT_MISMATCH')
        }
    }
    return [pscustomobject] $declared
}

function Assert-SpecOpsUnityNUnit3AggregateResult {
    param(
        [Parameter(Mandatory)] [System.Xml.XmlElement] $Element,
        [Parameter(Mandatory)] $ObservedCounts
    )

    if (-not $Element.HasAttribute('result')) { return $null }
    $result = Get-SpecOpsUnityNUnit3ResultValue -Element $Element
    $inconsistent = switch -CaseSensitive ($result) {
        'Passed' { $ObservedCounts.Failed -ne 0 -or $ObservedCounts.Inconclusive -ne 0 }
        'Failed' { $ObservedCounts.Failed -eq 0 }
        'Inconclusive' { $ObservedCounts.Failed -ne 0 -or $ObservedCounts.Inconclusive -eq 0 }
        'Skipped' { ($ObservedCounts.Total - $ObservedCounts.Skipped) -ne 0 }
    }
    if ($inconsistent) {
        throw (New-SpecOpsUnityException 'NUnit3 aggregate result is inconsistent with observed test cases.' 'UNITY_NUNIT_RESULT_INCONSISTENT')
    }
    return $result
}

function Read-SpecOpsUnityNUnit3Result {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [byte[]] $Bytes,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $RequiredTestFullNames
    )

    if ($Bytes.Length -eq 0) {
        throw (New-SpecOpsUnityException 'NUnit3 results are empty or not valid XML.' 'UNITY_NUNIT_XML_INVALID')
    }

    $document = [System.Xml.XmlDocument]::new()
    $document.XmlResolver = $null
    $settings = [System.Xml.XmlReaderSettings]::new()
    $settings.ConformanceLevel = [System.Xml.ConformanceLevel]::Document
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $settings.IgnoreComments = $true
    $settings.IgnoreProcessingInstructions = $true
    $stream = [System.IO.MemoryStream]::new($Bytes, $false)
    try {
        $reader = [System.Xml.XmlReader]::Create($stream, $settings)
        try { $document.Load($reader) }
        finally { $reader.Dispose() }
    }
    catch {
        throw (New-SpecOpsUnityException 'NUnit3 results are empty, malformed, or contain prohibited XML constructs.' 'UNITY_NUNIT_XML_INVALID' $_.Exception)
    }
    finally {
        $stream.Dispose()
    }

    $root = $document.DocumentElement
    if ($null -eq $root -or -not [string]::Equals($root.Name, 'test-run', [System.StringComparison]::Ordinal)) {
        throw (New-SpecOpsUnityException 'NUnit3 results must have exactly one test-run document root.' 'UNITY_NUNIT_ROOT_INVALID')
    }

    $required = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    if ($RequiredTestFullNames.Count -eq 0) {
        throw (New-SpecOpsUnityException 'Required NUnit3 test identities must be non-empty and unique.' 'UNITY_NUNIT_REQUIRED_TESTS_INVALID')
    }
    foreach ($requiredName in $RequiredTestFullNames) {
        if ([string]::IsNullOrWhiteSpace($requiredName) -or -not $required.Add($requiredName)) {
            throw (New-SpecOpsUnityException 'Required NUnit3 test identities must be non-empty and unique.' 'UNITY_NUNIT_REQUIRED_TESTS_INVALID')
        }
    }

    $matchingAssemblies = [System.Collections.Generic.List[System.Xml.XmlElement]]::new()
    foreach ($suiteNode in $root.SelectNodes('.//test-suite')) {
        $suite = [System.Xml.XmlElement] $suiteNode
        if ([string]::Equals($suite.GetAttribute('type'), 'Assembly', [System.StringComparison]::Ordinal) -and
            [string]::Equals($suite.GetAttribute('name'), 'InfiniteMonkey.EditModeTests.dll', [System.StringComparison]::Ordinal)) {
            $matchingAssemblies.Add($suite)
        }
    }
    if ($matchingAssemblies.Count -eq 0) {
        throw (New-SpecOpsUnityException 'The required NUnit3 Assembly suite was not found.' 'UNITY_NUNIT_ASSEMBLY_NOT_FOUND')
    }
    if ($matchingAssemblies.Count -gt 1) {
        throw (New-SpecOpsUnityException 'Multiple matching NUnit3 Assembly suites were found.' 'UNITY_NUNIT_ASSEMBLY_AMBIGUOUS')
    }

    $assembly = $matchingAssemblies[0]
    $allTestCaseNodes = $root.SelectNodes('.//test-case')
    $assemblyTestCaseNodes = $assembly.SelectNodes('.//test-case')
    $allCounts = Get-SpecOpsUnityNUnit3ObservedCounts -TestCaseNodes $allTestCaseNodes
    $assemblyCounts = Get-SpecOpsUnityNUnit3ObservedCounts -TestCaseNodes $assemblyTestCaseNodes
    $rootDeclaredCounts = Get-SpecOpsUnityNUnit3DeclaredCounts -Element $root -ObservedCounts $allCounts
    $assemblyDeclaredCounts = Get-SpecOpsUnityNUnit3DeclaredCounts -Element $assembly -ObservedCounts $assemblyCounts
    $rootResult = Assert-SpecOpsUnityNUnit3AggregateResult -Element $root -ObservedCounts $allCounts
    $assemblyResult = Assert-SpecOpsUnityNUnit3AggregateResult -Element $assembly -ObservedCounts $assemblyCounts

    $observationsByName = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($testCaseNode in $assemblyTestCaseNodes) {
        $testCase = [System.Xml.XmlElement] $testCaseNode
        if (-not $testCase.HasAttribute('fullname') -or [string]::IsNullOrEmpty($testCase.GetAttribute('fullname'))) {
            throw (New-SpecOpsUnityException 'A selected NUnit3 test case has no canonical fullname.' 'UNITY_NUNIT_TEST_IDENTITY_INVALID')
        }
        $fullName = $testCase.GetAttribute('fullname')
        if ($observationsByName.ContainsKey($fullName)) {
            throw (New-SpecOpsUnityException 'The selected NUnit3 Assembly suite contains a duplicate fullname.' 'UNITY_NUNIT_TEST_IDENTITY_DUPLICATE')
        }
        $result = Get-SpecOpsUnityNUnit3ResultValue -Element $testCase
        $label = if ($testCase.HasAttribute('label')) { $testCase.GetAttribute('label') } else { $null }
        $runState = if ($testCase.HasAttribute('runstate')) { $testCase.GetAttribute('runstate') } else { $null }
        $observationsByName.Add($fullName, [pscustomobject]@{
            FullName = $fullName
            Result = $result
            Label = $label
            RunState = $runState
            Executed = -not [string]::Equals($result, 'Skipped', [System.StringComparison]::Ordinal)
        })
    }

    $missing = [System.Collections.Generic.List[string]]::new()
    foreach ($requiredName in $required) {
        if (-not $observationsByName.ContainsKey($requiredName)) { $missing.Add($requiredName) }
    }
    if ($missing.Count -gt 0) {
        throw (New-SpecOpsUnityException 'The selected NUnit3 Assembly suite is missing required test identities.' 'UNITY_NUNIT_REQUIRED_TEST_MISSING')
    }
    $unexpected = [System.Collections.Generic.List[string]]::new()
    foreach ($actualName in $observationsByName.Keys) {
        if (-not $required.Contains($actualName)) { $unexpected.Add($actualName) }
    }
    if ($unexpected.Count -gt 0) {
        throw (New-SpecOpsUnityException 'The selected NUnit3 Assembly suite contains unexpected test identities.' 'UNITY_NUNIT_TEST_UNEXPECTED')
    }

    $orderedNames = Get-SpecOpsUnityOrdinalSortedStrings @($observationsByName.Keys)
    $orderedObservations = [System.Collections.Generic.List[object]]::new()
    foreach ($name in $orderedNames) { $orderedObservations.Add($observationsByName[$name]) }
    return [pscustomobject]@{
        RootName = $root.Name
        RootResult = $rootResult
        RootDeclaredCounts = $rootDeclaredCounts
        AssemblyName = 'InfiniteMonkey.EditModeTests'
        AssemblyFileName = $assembly.GetAttribute('name')
        AssemblyFullName = if ($assembly.HasAttribute('fullname')) { $assembly.GetAttribute('fullname') } else { $null }
        AssemblyResult = $assemblyResult
        AssemblyDeclaredCounts = $assemblyDeclaredCounts
        Counts = $assemblyCounts
        FullyQualifiedTestNames = $orderedNames
        TestCases = @($orderedObservations)
    }
}

function Assert-SpecOpsUnitySubjectPath {
    param([Parameter(Mandatory)] [string] $Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or
        $Path.Contains('\') -or
        $Path.StartsWith('/', [System.StringComparison]::Ordinal) -or
        [System.IO.Path]::IsPathFullyQualified($Path) -or
        $Path.Contains(':')) {
        throw (New-SpecOpsUnityException "Unsafe repository-relative path: $Path" 'UNITY_SUBJECT_PATH_INVALID')
    }

    $segments = $Path.Split('/')
    $invalidFileNameCharacters = [System.Collections.Generic.HashSet[char]]::new([System.IO.Path]::GetInvalidFileNameChars())
    foreach ($segment in $segments) {
        if ([string]::IsNullOrEmpty($segment) -or
            [string]::Equals($segment, '.', [System.StringComparison]::Ordinal) -or
            [string]::Equals($segment, '..', [System.StringComparison]::Ordinal) -or
            $segment.EndsWith(' ', [System.StringComparison]::Ordinal) -or
            $segment.EndsWith('.', [System.StringComparison]::Ordinal)) {
            throw (New-SpecOpsUnityException "Unsafe repository-relative path segment: $Path" 'UNITY_SUBJECT_PATH_INVALID')
        }

        foreach ($character in $segment.ToCharArray()) {
            if ([char]::IsControl($character) -or $invalidFileNameCharacters.Contains($character)) {
                throw (New-SpecOpsUnityException "Repository path cannot be represented safely on the Windows host: $Path" 'UNITY_SUBJECT_PATH_UNREPRESENTABLE')
            }
        }

        $deviceStem = $segment.Split('.', 2)[0]
        if ($script:WindowsReservedDeviceNames.Contains($deviceStem)) {
            throw (New-SpecOpsUnityException "Repository path uses a reserved Windows device name: $Path" 'UNITY_SUBJECT_PATH_UNREPRESENTABLE')
        }
    }
    return $Path
}

function Read-SpecOpsUnityProjectVersionRequirement {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [byte[]] $Bytes)

    try {
        $text = $script:Utf8Strict.GetString($Bytes)
    }
    catch {
        throw (New-SpecOpsUnityException 'ProjectVersion.txt is not valid UTF-8.' 'UNITY_PROJECT_VERSION_INVALID')
    }
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        throw (New-SpecOpsUnityException 'ProjectVersion.txt must not begin with a UTF-8 BOM.' 'UNITY_PROJECT_VERSION_INVALID')
    }
    if ($text.Contains("`r") -and [regex]::IsMatch($text, "`r(?!`n)")) {
        throw (New-SpecOpsUnityException 'ProjectVersion.txt contains unsupported line endings.' 'UNITY_PROJECT_VERSION_INVALID')
    }

    $fields = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    foreach ($line in $text -split "`r?`n") {
        $match = [regex]::Match($line, '^(m_EditorVersion|m_EditorVersionWithRevision): (.+)$', [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
        if (-not $match.Success) { continue }
        $name = $match.Groups[1].Value
        if ($fields.ContainsKey($name)) {
            throw (New-SpecOpsUnityException "Duplicate ProjectVersion.txt field: $name" 'UNITY_PROJECT_VERSION_DUPLICATE_FIELD')
        }
        $fields.Add($name, $match.Groups[2].Value)
    }

    foreach ($required in @('m_EditorVersion', 'm_EditorVersionWithRevision')) {
        if (-not $fields.ContainsKey($required)) {
            throw (New-SpecOpsUnityException "Missing ProjectVersion.txt field: $required" 'UNITY_PROJECT_VERSION_MISSING_FIELD')
        }
    }

    $version = $fields['m_EditorVersion']
    $combined = $fields['m_EditorVersionWithRevision']
    if ($version -notmatch '^\S+$') {
        throw (New-SpecOpsUnityException 'm_EditorVersion is malformed.' 'UNITY_PROJECT_VERSION_INVALID')
    }
    $combinedMatch = [regex]::Match($combined, '^([^ ]+) \(([^()]+)\)$', [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
    if (-not $combinedMatch.Success) {
        throw (New-SpecOpsUnityException 'm_EditorVersionWithRevision is malformed.' 'UNITY_PROJECT_VERSION_INVALID')
    }
    $combinedVersion = $combinedMatch.Groups[1].Value
    $revision = $combinedMatch.Groups[2].Value
    if (-not [string]::Equals($version, $combinedVersion, [System.StringComparison]::Ordinal)) {
        throw (New-SpecOpsUnityException 'ProjectVersion.txt version fields disagree.' 'UNITY_PROJECT_VERSION_INCONSISTENT')
    }

    return [pscustomobject]@{
        EditorVersion = $version
        EditorRevision = $revision
        CombinedVersionRevision = $combined
        ExtractionOperation = 'parenthesized-revision-suffix'
        CombinedFormat = 'version-space-parenthesized-revision'
        VersionResult = 'substring-before-space-open-parenthesis'
        RevisionResult = 'content-inside-parentheses'
    }
}

function ConvertFrom-SpecOpsUnityProductVersion {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $ProductVersion)

    $match = [regex]::Match($ProductVersion, '^([^_\s]+)_([^_\s]+)$', [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
    if (-not $match.Success) {
        throw (New-SpecOpsUnityException "Malformed Unity ProductVersion: $ProductVersion" 'UNITY_EXECUTABLE_METADATA_INVALID')
    }
    return [pscustomobject]@{
        ProductVersion = $ProductVersion
        EditorVersion = $match.Groups[1].Value
        EditorRevision = $match.Groups[2].Value
    }
}

function Get-SpecOpsUnityExecutableMetadata {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    if (-not [System.IO.Path]::IsPathFullyQualified($Path)) {
        throw (New-SpecOpsUnityException 'Unity executable path must be absolute.' 'UNITY_EXECUTABLE_PATH_INVALID')
    }
    $canonical = [System.IO.Path]::GetFullPath($Path)
    if (-not [System.IO.File]::Exists($canonical)) {
        throw (New-SpecOpsUnityException "Unity executable does not exist: $canonical" 'UNITY_EXECUTABLE_NOT_FOUND')
    }
    $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($canonical)
    $parsed = ConvertFrom-SpecOpsUnityProductVersion -ProductVersion ([string] $versionInfo.ProductVersion)
    return [pscustomobject]@{
        Path = $canonical
        ProductVersion = $parsed.ProductVersion
        EditorVersion = $parsed.EditorVersion
        EditorRevision = $parsed.EditorRevision
        FileVersion = [string] $versionInfo.FileVersion
    }
}

function Get-SpecOpsUnityHubEditorRoots {
    $roots = [System.Collections.Generic.List[string]]::new()
    $programFiles = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::ProgramFiles)
    if (-not [string]::IsNullOrEmpty($programFiles)) {
        $roots.Add([System.IO.Path]::Combine($programFiles, 'Unity', 'Hub', 'Editor'))
    }

    $applicationData = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::ApplicationData)
    if (-not [string]::IsNullOrEmpty($applicationData)) {
        $secondaryFile = [System.IO.Path]::Combine($applicationData, 'UnityHub', 'secondaryInstallPath.json')
        if ([System.IO.File]::Exists($secondaryFile)) {
            try {
                $secondary = [System.Text.Json.JsonSerializer]::Deserialize([System.IO.File]::ReadAllText($secondaryFile), [string])
                if (-not [string]::IsNullOrWhiteSpace($secondary)) { $roots.Add($secondary) }
            }
            catch {
                throw (New-SpecOpsUnityException 'Unity Hub secondary installation path is malformed.' 'UNITY_HUB_CONFIGURATION_INVALID')
            }
        }
    }

    $deduplicated = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($root in $roots) {
        $canonical = [System.IO.Path]::GetFullPath($root)
        if (-not $deduplicated.ContainsKey($canonical)) { $deduplicated.Add($canonical, $canonical) }
    }
    return @(Get-SpecOpsUnityOrdinalSortedStrings @($deduplicated.Values))
}

function Select-SpecOpsUnityExecutableCore {
    param(
        [Parameter(Mandatory)] $Requirement,
        [string] $ExplicitExecutablePath,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $HubRoots,
        [Parameter(Mandatory)] [scriptblock] $MetadataInspector
    )

    if (-not [string]::IsNullOrEmpty($ExplicitExecutablePath)) {
        if (-not [System.IO.Path]::IsPathFullyQualified($ExplicitExecutablePath)) {
            throw (New-SpecOpsUnityException 'Explicit Unity executable path must be absolute.' 'UNITY_EXECUTABLE_PATH_INVALID')
        }
        $canonical = [System.IO.Path]::GetFullPath($ExplicitExecutablePath)
        if (-not [System.IO.File]::Exists($canonical)) {
            throw (New-SpecOpsUnityException "Explicit Unity executable does not exist: $canonical" 'UNITY_EXECUTABLE_NOT_FOUND')
        }
        $metadata = & $MetadataInspector $canonical
        if (-not [string]::Equals([string] $metadata.EditorVersion, [string] $Requirement.EditorVersion, [System.StringComparison]::Ordinal) -or
            -not [string]::Equals([string] $metadata.EditorRevision, [string] $Requirement.EditorRevision, [System.StringComparison]::Ordinal)) {
            throw (New-SpecOpsUnityException 'Explicit Unity executable does not match the project version and revision.' 'UNITY_EXECUTABLE_VERSION_MISMATCH')
        }
        return [pscustomobject]@{ SelectionMode = 'explicit'; Candidate = $metadata }
    }

    $candidatePaths = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($rootValue in $HubRoots) {
        if ([string]::IsNullOrWhiteSpace($rootValue)) { continue }
        $root = [System.IO.Path]::GetFullPath($rootValue)
        if (-not [System.IO.Directory]::Exists($root)) { continue }
        foreach ($versionDirectory in [System.IO.Directory]::EnumerateDirectories($root)) {
            $candidate = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($versionDirectory, 'Editor', 'Unity.exe'))
            if ([System.IO.File]::Exists($candidate) -and -not $candidatePaths.ContainsKey($candidate)) {
                $candidatePaths.Add($candidate, $candidate)
            }
        }
    }

    $matches = [System.Collections.Generic.List[object]]::new()
    foreach ($candidatePath in (Get-SpecOpsUnityOrdinalSortedStrings @($candidatePaths.Values))) {
        try {
            $metadata = & $MetadataInspector $candidatePath
            if ([string]::Equals([string] $metadata.EditorVersion, [string] $Requirement.EditorVersion, [System.StringComparison]::Ordinal) -and
                [string]::Equals([string] $metadata.EditorRevision, [string] $Requirement.EditorRevision, [System.StringComparison]::Ordinal)) {
                $matches.Add($metadata)
            }
        }
        catch {
            # A malformed automatic candidate is not an exact match. Explicit mode fails directly.
        }
    }
    if ($matches.Count -eq 0) {
        throw (New-SpecOpsUnityException 'No exact Unity editor version and revision match is installed.' 'UNITY_EXECUTABLE_CAPABILITY_UNAVAILABLE')
    }
    if ($matches.Count -gt 1) {
        throw (New-SpecOpsUnityException 'Multiple exact Unity editor candidates are installed.' 'UNITY_EXECUTABLE_SELECTION_AMBIGUOUS')
    }
    return [pscustomobject]@{ SelectionMode = 'automatic'; Candidate = $matches[0] }
}

function Select-SpecOpsUnityExecutable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Requirement,
        [string] $ExplicitExecutablePath
    )

    return Select-SpecOpsUnityExecutableCore -Requirement $Requirement -ExplicitExecutablePath $ExplicitExecutablePath -HubRoots @(Get-SpecOpsUnityHubEditorRoots) -MetadataInspector { param($path) Get-SpecOpsUnityExecutableMetadata -Path $path }
}

function New-SpecOpsUnityWorkspace {
    [CmdletBinding()]
    param()

    $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    $ownerId = [guid]::NewGuid().ToString('D').ToLowerInvariant()
    $root = [System.IO.Path]::Combine($tempRoot, "$($script:WorkspacePrefix)$ownerId")
    $null = [System.IO.Directory]::CreateDirectory($root)
    $subjectRoot = [System.IO.Path]::Combine($root, 'subject')
    $outputRoot = [System.IO.Path]::Combine($root, 'output')
    $null = [System.IO.Directory]::CreateDirectory($subjectRoot)
    $null = [System.IO.Directory]::CreateDirectory($outputRoot)
    $marker = [System.IO.Path]::Combine($root, $script:OwnerMarkerName)
    [System.IO.File]::WriteAllText($marker, $ownerId, [System.Text.UTF8Encoding]::new($false))
    $script:OwnedWorkspaces.Add($ownerId, $root)
    return [pscustomobject]@{
        OwnerId = $ownerId
        Root = $root
        SubjectRoot = $subjectRoot
        OutputRoot = $outputRoot
        OwnershipMarker = $marker
    }
}

function Assert-SpecOpsUnityOwnedWorkspace {
    param([Parameter(Mandatory)] $Workspace)

    foreach ($property in @('OwnerId', 'Root', 'SubjectRoot', 'OutputRoot', 'OwnershipMarker')) {
        if ($null -eq $Workspace.PSObject.Properties[$property] -or [string]::IsNullOrWhiteSpace([string] $Workspace.$property)) {
            throw (New-SpecOpsUnityException 'Workspace ownership data is incomplete.' 'UNITY_WORKSPACE_NOT_OWNED')
        }
    }
    $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $root = [System.IO.Path]::GetFullPath([string] $Workspace.Root).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $requiredPrefix = $tempRoot + [System.IO.Path]::DirectorySeparatorChar
    if (-not $root.StartsWith($requiredPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
        -not [System.IO.Path]::GetFileName($root).StartsWith($script:WorkspacePrefix, [System.StringComparison]::Ordinal)) {
        throw (New-SpecOpsUnityException 'Workspace is outside the owned OS-temporary namespace.' 'UNITY_WORKSPACE_NOT_OWNED')
    }
    if (-not $script:OwnedWorkspaces.ContainsKey([string] $Workspace.OwnerId) -or
        -not [string]::Equals($script:OwnedWorkspaces[[string] $Workspace.OwnerId], $root, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw (New-SpecOpsUnityException 'Workspace was not created by this adapter invocation.' 'UNITY_WORKSPACE_NOT_OWNED')
    }
    $expectedSubject = [System.IO.Path]::Combine($root, 'subject')
    $expectedOutput = [System.IO.Path]::Combine($root, 'output')
    if (-not [string]::Equals([System.IO.Path]::GetFullPath([string] $Workspace.SubjectRoot), $expectedSubject, [System.StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals([System.IO.Path]::GetFullPath([string] $Workspace.OutputRoot), $expectedOutput, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw (New-SpecOpsUnityException 'Workspace child paths do not match the owned layout.' 'UNITY_WORKSPACE_NOT_OWNED')
    }
    $expectedMarker = [System.IO.Path]::Combine($root, $script:OwnerMarkerName)
    if (-not [string]::Equals([System.IO.Path]::GetFullPath([string] $Workspace.OwnershipMarker), $expectedMarker, [System.StringComparison]::OrdinalIgnoreCase) -or
        -not [System.IO.File]::Exists($expectedMarker) -or
        -not [string]::Equals([System.IO.File]::ReadAllText($expectedMarker), [string] $Workspace.OwnerId, [System.StringComparison]::Ordinal)) {
        throw (New-SpecOpsUnityException 'Workspace ownership marker is invalid.' 'UNITY_WORKSPACE_NOT_OWNED')
    }
    return $root
}

function Remove-SpecOpsUnityWorkspace {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Workspace)

    $root = Assert-SpecOpsUnityOwnedWorkspace -Workspace $Workspace
    [System.IO.Directory]::Delete($root, $true)
    $null = $script:OwnedWorkspaces.Remove([string] $Workspace.OwnerId)
    return [pscustomobject]@{ Removed = $true; Root = $root }
}

function New-SpecOpsUnitySubjectMaterialization {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Snapshot,
        [Parameter(Mandatory)] [scriptblock] $ReadBlobBytes,
        [Parameter(Mandatory)] $Workspace
    )

    $workspaceRoot = Assert-SpecOpsUnityOwnedWorkspace -Workspace $Workspace
    $subjectRoot = [System.IO.Path]::GetFullPath([string] $Workspace.SubjectRoot)
    if (-not $subjectRoot.StartsWith($workspaceRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw (New-SpecOpsUnityException 'Materialization root is outside the owned workspace.' 'UNITY_WORKSPACE_NOT_OWNED')
    }
    if ($null -eq $Snapshot.PSObject.Properties['Inventory']) {
        throw (New-SpecOpsUnityException 'Repository snapshot inventory is missing.' 'UNITY_SUBJECT_INVENTORY_INVALID')
    }

    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in @($Snapshot.Inventory)) {
        $path = Assert-SpecOpsUnitySubjectPath -Path ([string] $entry.Path)
        $type = if ($null -ne $entry.PSObject.Properties['ObjectType']) { [string] $entry.ObjectType } else { '' }
        $mode = if ($null -ne $entry.PSObject.Properties['Mode']) { [string] $entry.Mode } else { '' }
        if (-not [string]::Equals($type, 'blob', [System.StringComparison]::Ordinal)) {
            throw (New-SpecOpsUnityException "Unsupported repository entry type for ${path}: $type" 'UNITY_SUBJECT_ENTRY_UNSUPPORTED')
        }
        if (-not [string]::IsNullOrEmpty($mode) -and
            -not [string]::Equals($mode, '100644', [System.StringComparison]::Ordinal) -and
            -not [string]::Equals($mode, '100755', [System.StringComparison]::Ordinal)) {
            throw (New-SpecOpsUnityException "Unsupported repository entry mode for ${path}: $mode" 'UNITY_SUBJECT_ENTRY_UNSUPPORTED')
        }
        $records.Add([pscustomobject]@{ Path = $path; EntryType = $type; Mode = $mode })
    }
    $paths = Get-SpecOpsUnityOrdinalSortedStrings @($records | ForEach-Object { $_.Path })
    $byPath = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($record in $records) {
        if ($byPath.ContainsKey($record.Path)) {
            throw (New-SpecOpsUnityException "Duplicate subject path: $($record.Path)" 'UNITY_SUBJECT_PATH_COLLISION')
        }
        $byPath.Add($record.Path, $record)
    }

    $hostPaths = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $hostRelativePaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($path in $paths) {
        $hostRelative = $path.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        $destination = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($subjectRoot, $hostRelative))
        if (-not $destination.StartsWith($subjectRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw (New-SpecOpsUnityException "Materialized path escapes workspace: $path" 'UNITY_SUBJECT_PATH_INVALID')
        }
        if ($hostPaths.ContainsKey($destination) -or -not $hostRelativePaths.Add($hostRelative)) {
            throw (New-SpecOpsUnityException "Host filesystem path collision: $path" 'UNITY_SUBJECT_PATH_COLLISION')
        }
        $hostPaths.Add($destination, $path)
    }
    foreach ($hostRelative in $hostRelativePaths) {
        $parent = [System.IO.Path]::GetDirectoryName($hostRelative)
        while (-not [string]::IsNullOrEmpty($parent)) {
            if ($hostRelativePaths.Contains($parent)) {
                throw (New-SpecOpsUnityException "File/directory host collision: $hostRelative" 'UNITY_SUBJECT_PATH_COLLISION')
            }
            $parent = [System.IO.Path]::GetDirectoryName($parent)
        }
    }

    $manifest = [System.Collections.Generic.List[object]]::new()
    foreach ($path in $paths) {
        $record = $byPath[$path]
        try {
            [byte[]] $bytes = @(& $ReadBlobBytes $Snapshot $path)
        }
        catch {
            throw (New-SpecOpsUnityException "Unable to read immutable subject blob: $path" 'UNITY_SUBJECT_BLOB_READ_FAILED')
        }
        $destination = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($subjectRoot, $path.Replace('/', [System.IO.Path]::DirectorySeparatorChar)))
        $parent = [System.IO.Path]::GetDirectoryName($destination)
        if (-not [System.IO.Directory]::Exists($parent)) { $null = [System.IO.Directory]::CreateDirectory($parent) }
        [System.IO.File]::WriteAllBytes($destination, $bytes)
        $manifest.Add([pscustomobject]@{
            Path = $path
            EntryType = $record.EntryType
            Mode = $record.Mode
            ByteLength = [int64] $bytes.LongLength
            ComparisonBytes = $bytes
        })
    }

    return [pscustomobject]@{
        ProjectRoot = $subjectRoot
        Manifest = @($manifest)
        EntryCount = $manifest.Count
    }
}

function New-SpecOpsUnityArgumentVector {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $ProjectRoot,
        [Parameter(Mandatory)] [string] $OutputRoot
    )

    if (-not [System.IO.Path]::IsPathFullyQualified($ProjectRoot) -or -not [System.IO.Path]::IsPathFullyQualified($OutputRoot)) {
        throw (New-SpecOpsUnityException 'Unity project and output roots must be absolute.' 'UNITY_ARGUMENT_PATH_INVALID')
    }
    $project = [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $output = [System.IO.Path]::GetFullPath($OutputRoot).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    if ([string]::Equals($project, $output, [System.StringComparison]::OrdinalIgnoreCase) -or
        $output.StartsWith($project + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw (New-SpecOpsUnityException 'Unity output paths must be outside the materialized subject.' 'UNITY_ARGUMENT_PATH_INVALID')
    }
    $results = [System.IO.Path]::Combine($output, 'results.xml')
    $log = [System.IO.Path]::Combine($output, 'unity.log')
    $arguments = [string[]] @(
        '-batchmode',
        '-projectPath', $project,
        '-runTests',
        '-testPlatform', 'EditMode',
        '-assemblyNames', 'InfiniteMonkey.EditModeTests',
        '-testResults', $results,
        '-logFile', $log
    )
    return [pscustomobject]@{ Arguments = $arguments; ResultsPath = $results; LogPath = $log }
}

function Invoke-SpecOpsControlledProcessCore {
    param(
        [Parameter(Mandatory)] [string] $FilePath,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $ArgumentList,
        [Parameter(Mandatory)] [int] $TimeoutMilliseconds,
        [Parameter(Mandatory)] [int] $TerminationWaitMilliseconds
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $process = [System.Diagnostics.Process]::new()
    $started = $false
    $timedOut = $false
    $terminationConfirmed = $false
    $exitCode = $null
    $stdout = ''
    $stderr = ''
    $startFailure = $null
    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $FilePath
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        foreach ($argument in $ArgumentList) { $null = $startInfo.ArgumentList.Add($argument) }
        $process.StartInfo = $startInfo
        try {
            $started = $process.Start()
        }
        catch {
            $startFailure = 'PROCESS_START_FAILED'
            $stderr = $_.Exception.Message
        }
        if ($started) {
            $stdoutTask = $process.StandardOutput.ReadToEndAsync()
            $stderrTask = $process.StandardError.ReadToEndAsync()
            $waitTask = $process.WaitForExitAsync()
            $delayTask = [System.Threading.Tasks.Task]::Delay($TimeoutMilliseconds)
            $winner = [System.Threading.Tasks.Task]::WhenAny($waitTask, $delayTask).GetAwaiter().GetResult()
            if ([object]::ReferenceEquals($winner, $waitTask)) {
                $null = $waitTask.GetAwaiter().GetResult()
                $terminationConfirmed = $true
            }
            else {
                $timedOut = $true
                try { $process.Kill($true) } catch { }
                $terminationConfirmed = $process.WaitForExit($TerminationWaitMilliseconds)
            }
            if ($terminationConfirmed) {
                $stdout = $stdoutTask.GetAwaiter().GetResult()
                $stderr = $stderrTask.GetAwaiter().GetResult()
                $exitCode = $process.ExitCode
            }
        }
    }
    finally {
        $stopwatch.Stop()
        $process.Dispose()
    }
    return [pscustomobject]@{
        Started = $started
        TimedOut = $timedOut
        TerminationConfirmed = $terminationConfirmed
        ExitCode = $exitCode
        Stdout = $stdout
        Stderr = $stderr
        DurationMilliseconds = [int64] $stopwatch.ElapsedMilliseconds
        StartFailure = $startFailure
    }
}

function Invoke-SpecOpsControlledProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $FilePath,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $ArgumentList
    )

    return Invoke-SpecOpsControlledProcessCore -FilePath $FilePath -ArgumentList $ArgumentList -TimeoutMilliseconds $script:CanonicalTimeoutMilliseconds -TerminationWaitMilliseconds $script:TerminationWaitMilliseconds
}

Export-ModuleMember -Function @(
    'ConvertFrom-SpecOpsUnityProductVersion',
    'Get-SpecOpsUnityErrorMetadata',
    'Get-SpecOpsUnityExecutableMetadata',
    'Invoke-SpecOpsControlledProcess',
    'New-SpecOpsUnityArgumentVector',
    'New-SpecOpsUnitySubjectMaterialization',
    'New-SpecOpsUnityWorkspace',
    'Read-SpecOpsUnityNUnit3Result',
    'Read-SpecOpsUnityProjectVersionRequirement',
    'Remove-SpecOpsUnityWorkspace',
    'Select-SpecOpsUnityExecutable'
)
