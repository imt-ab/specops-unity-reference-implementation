Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:CanonicalTimeoutMilliseconds = 20 * 60 * 1000
$script:TerminationWaitMilliseconds = 30 * 1000
$script:ObservationQuiescenceMilliseconds = 30 * 1000
$script:ObservationStableIntervalMilliseconds = 100
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

function Test-SpecOpsUnityExactBytes {
    param(
        [AllowNull()] [byte[]] $Left,
        [AllowNull()] [byte[]] $Right
    )

    if ($null -eq $Left -or $null -eq $Right -or $Left.LongLength -ne $Right.LongLength) { return $false }
    for ($index = 0L; $index -lt $Left.LongLength; $index++) {
        if ($Left[$index] -ne $Right[$index]) { return $false }
    }
    return $true
}

function Read-SpecOpsUnityStableFileBytes {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $LogicalName,
        [Parameter(Mandatory)] [bool] $RequireNonEmpty,
        [Parameter(Mandatory)] [int] $TimeoutMilliseconds,
        [Parameter(Mandatory)] [int] $StableIntervalMilliseconds,
        [Parameter(Mandatory)] [scriptblock] $ReadFileBytes,
        [scriptblock] $FileExists = { param($candidatePath) [System.IO.File]::Exists($candidatePath) },
        [bool] $AllowAbsentAfterTimeout = $false
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    [byte[]] $previous = $null
    $hasPrevious = $false
    $observedExists = $false
    while ($true) {
        try {
            if (& $FileExists $Path) {
                $observedExists = $true
                [byte[]] $current = @(& $ReadFileBytes $Path)
                if ((-not $RequireNonEmpty -or $current.LongLength -gt 0) -and
                    $hasPrevious -and (Test-SpecOpsUnityExactBytes -Left $previous -Right $current)) {
                    Write-Output -NoEnumerate $current
                    return
                }
                if (-not $RequireNonEmpty -or $current.LongLength -gt 0) {
                    $previous = $current
                    $hasPrevious = $true
                }
                else {
                    $previous = $null
                    $hasPrevious = $false
                }
            }
            else {
                $previous = $null
                $hasPrevious = $false
            }
        }
        catch {
            $previous = $null
            $hasPrevious = $false
        }

        if ($stopwatch.ElapsedMilliseconds -ge $TimeoutMilliseconds) {
            if ($AllowAbsentAfterTimeout -and -not $observedExists) { return $null }
            throw (New-SpecOpsUnityException "Required observation output did not become readable and stable: $LogicalName" 'UNITY_OBSERVATION_OUTPUT_NOT_QUIESCENT')
        }
        $remaining = $TimeoutMilliseconds - [int] $stopwatch.ElapsedMilliseconds
        $delay = [System.Math]::Max(1, [System.Math]::Min($StableIntervalMilliseconds, $remaining))
        Start-Sleep -Milliseconds $delay
    }
}

function Read-SpecOpsUnityCompilationObservation {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [byte[]] $Bytes)

    try { $text = $script:Utf8Strict.GetString($Bytes) }
    catch { throw (New-SpecOpsUnityException 'Unity log is not valid UTF-8.' 'UNITY_LOG_ENCODING_INVALID' $_.Exception) }

    $completed = [System.Text.RegularExpressions.Regex]::IsMatch(
        $text,
        '(?m)^AssetDatabase: script compilation time: [0-9]+(?:\.[0-9]+)?s\r?$'
    )
    $errorEvidence = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($match in [System.Text.RegularExpressions.Regex]::Matches(
        $text,
        '(?m)^[^\r\n]+\([0-9]+,[0-9]+\): error [A-Za-z]+[0-9]+: [^\r\n]+\r?$'
    )) { $null = $errorEvidence.Add($match.Value.TrimEnd("`r")) }
    $hasFailureMarker = [System.Text.RegularExpressions.Regex]::IsMatch(
        $text,
        '(?m)^(?:Scripts have compiler errors\.|## Script Compilation Error for:.*)\r?$'
    )
    $errors = $errorEvidence.Count
    if ($hasFailureMarker -and $errors -eq 0) { $errors = 1 }

    return [pscustomobject]@{
        Completed = $completed
        Errors = $errors
        Warnings = $null
        WarningObservability = 'COMPILATION_WARNING_OBSERVABILITY_UNRESOLVED'
        Source = 'unity.log'
    }
}

function Assert-SpecOpsUnityObservationOutputPath {
    param(
        [Parameter(Mandatory)] $Workspace,
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $LogicalName
    )

    if (-not [System.IO.Path]::IsPathFullyQualified($Path)) {
        throw (New-SpecOpsUnityException "Observation output path must be absolute: $LogicalName" 'UNITY_OBSERVATION_PATH_INVALID')
    }
    $outputRoot = [System.IO.Path]::GetFullPath([string] $Workspace.OutputRoot).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $canonical = [System.IO.Path]::GetFullPath($Path)
    if (-not $canonical.StartsWith($outputRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw (New-SpecOpsUnityException "Observation output path is outside the owned output workspace: $LogicalName" 'UNITY_OBSERVATION_PATH_INVALID')
    }
    return $canonical
}

function Get-SpecOpsUnityPostRunFileInventory {
    param([Parameter(Mandatory)] [string] $ProjectRoot)

    $inventory = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    $pending = [System.Collections.Generic.Stack[string]]::new()
    $pending.Push($ProjectRoot)
    try {
        while ($pending.Count -gt 0) {
            $directory = $pending.Pop()
            $directoryAttributes = [System.IO.File]::GetAttributes($directory)
            if (($directoryAttributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw (New-SpecOpsUnityException 'Post-run subject inventory contains a filesystem reparse point.' 'UNITY_SUBJECT_INVENTORY_REPARSE_POINT')
            }
            foreach ($hostPath in [System.IO.Directory]::EnumerateFileSystemEntries($directory)) {
                $attributes = [System.IO.File]::GetAttributes($hostPath)
                if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw (New-SpecOpsUnityException 'Post-run subject inventory contains a filesystem reparse point.' 'UNITY_SUBJECT_INVENTORY_REPARSE_POINT')
                }
                if (($attributes -band [System.IO.FileAttributes]::Directory) -ne 0) {
                    $pending.Push($hostPath)
                    continue
                }
                $relative = [System.IO.Path]::GetRelativePath($ProjectRoot, $hostPath).Replace([System.IO.Path]::DirectorySeparatorChar, '/')
                $null = Assert-SpecOpsUnitySubjectPath -Path $relative
                if ($inventory.ContainsKey($relative)) {
                    throw (New-SpecOpsUnityException 'Post-run subject inventory contains a duplicate path identity.' 'UNITY_SUBJECT_INVENTORY_INVALID')
                }
                $inventory.Add($relative, $hostPath)
            }
        }
    }
    catch {
        if ($_.Exception.Data.Contains('SpecOpsRejectionClass')) { throw }
        throw (New-SpecOpsUnityException 'Unable to enumerate the post-run subject safely.' 'UNITY_SUBJECT_INVENTORY_READ_FAILED' $_.Exception)
    }
    return $inventory
}

function Invoke-SpecOpsUnityCapabilityGit {
    param(
        [Parameter(Mandatory)] [string] $GitDirectory,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $Arguments
    )

    $environment = Get-SpecOpsUnityPackageAcquisitionGuard
    $environment['LC_ALL'] = 'C'
    $environment['LANG'] = 'C'
    $environment['GIT_NO_REPLACE_OBJECTS'] = '1'
    $environment['GIT_OBJECT_DIRECTORY'] = [System.IO.Path]::Combine($GitDirectory, 'objects')
    $environment['GIT_ALTERNATE_OBJECT_DIRECTORIES'] = ''
    $result = Invoke-SpecOpsControlledProcessCore -FilePath 'git' -ArgumentList ([string[]] @('--no-replace-objects', '--git-dir', $GitDirectory) + $Arguments) -TimeoutMilliseconds 30000 -TerminationWaitMilliseconds $script:TerminationWaitMilliseconds -EnvironmentVariables $environment
    if (-not $result.Started -or $result.TimedOut -or -not $result.TerminationConfirmed -or $null -eq $result.ExitCode -or [int] $result.ExitCode -ne 0) {
        throw (New-SpecOpsUnityException 'The offline package capability Git object chain could not be verified.' 'UNITY_PACKAGE_CAPABILITY_REVISION_INVALID')
    }
    return [string] $result.Stdout
}

function Get-SpecOpsUnityCapabilityTreeEntries {
    param(
        [Parameter(Mandatory)] [string] $GitDirectory,
        [Parameter(Mandatory)] [string] $TreeObjectId
    )

    $output = Invoke-SpecOpsUnityCapabilityGit -GitDirectory $GitDirectory -Arguments @('ls-tree', '-rz', '--full-tree', $TreeObjectId)
    $entries = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($record in $output.Split([char] 0, [System.StringSplitOptions]::RemoveEmptyEntries)) {
        $match = [regex]::Match($record, '^(?<mode>[0-9]{6}) (?<type>[^ ]+) (?<object>[0-9a-f]{40})\t(?<path>.+)$')
        if (-not $match.Success) {
            throw (New-SpecOpsUnityException 'The offline package capability tree contains an invalid entry.' 'UNITY_PACKAGE_CAPABILITY_REVISION_INVALID')
        }
        $path = Assert-SpecOpsUnitySubjectPath -Path $match.Groups['path'].Value
        if ($entries.ContainsKey($path)) {
            throw (New-SpecOpsUnityException 'The offline package capability tree contains duplicate paths.' 'UNITY_PACKAGE_CAPABILITY_REVISION_INVALID')
        }
        $entries.Add($path, [pscustomobject]@{ Path = $path; Mode = $match.Groups['mode'].Value; Type = $match.Groups['type'].Value; ObjectId = $match.Groups['object'].Value })
    }
    return $entries
}

function Read-SpecOpsUnityRegistryPackageArchiveIdentity {
    param(
        [Parameter(Mandatory)] [string] $ArchivePath,
        [Parameter(Mandatory)] [string] $PackageName,
        [Parameter(Mandatory)] [string] $PackageVersion
    )

    $fileStream = $null
    $gzipStream = $null
    $tarReader = $null
    try {
        $fileStream = [System.IO.File]::OpenRead($ArchivePath)
        $gzipStream = [System.IO.Compression.GZipStream]::new($fileStream, [System.IO.Compression.CompressionMode]::Decompress, $false)
        $tarReader = [System.Formats.Tar.TarReader]::new($gzipStream, $false)
        $packageJsonCount = 0
        while ($null -ne ($tarEntry = $tarReader.GetNextEntry())) {
            if (-not [string]::Equals([string] $tarEntry.Name, 'package/package.json', [StringComparison]::Ordinal)) { continue }
            $packageJsonCount++
            if ($packageJsonCount -ne 1 -or $null -eq $tarEntry.DataStream) {
                throw (New-SpecOpsUnityException "The cached package archive has an invalid package.json inventory: $PackageName" 'UNITY_REGISTRY_PACKAGE_CACHE_INVALID')
            }
            $packageJsonBytes = [System.IO.MemoryStream]::new()
            try {
                [byte[]] $buffer = [byte[]]::new(8192)
                while (($read = $tarEntry.DataStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    if ($packageJsonBytes.Length + $read -gt 1048576) {
                        throw (New-SpecOpsUnityException "The cached package metadata is unreasonably large: $PackageName" 'UNITY_REGISTRY_PACKAGE_CACHE_INVALID')
                    }
                    $packageJsonBytes.Write($buffer, 0, $read)
                }
                $packageMetadata = $script:Utf8Strict.GetString($packageJsonBytes.ToArray()) | ConvertFrom-Json -Depth 100
            }
            finally { $packageJsonBytes.Dispose() }
        }
    }
    catch {
        if ($_.Exception.Data.Contains('SpecOpsRejectionClass')) { throw }
        throw (New-SpecOpsUnityException "The cached package archive cannot be read: $PackageName" 'UNITY_REGISTRY_PACKAGE_CACHE_INVALID' $_.Exception)
    }
    finally {
        if ($null -ne $tarReader) { $tarReader.Dispose() }
        if ($null -ne $gzipStream) { $gzipStream.Dispose() }
        if ($null -ne $fileStream) { $fileStream.Dispose() }
    }
    if ($packageJsonCount -ne 1 -or
        -not [string]::Equals([string] $packageMetadata.name, $PackageName, [StringComparison]::Ordinal) -or
        -not [string]::Equals([string] $packageMetadata.version, $PackageVersion, [StringComparison]::Ordinal)) {
        throw (New-SpecOpsUnityException "The cached package archive identity is invalid: $PackageName@$PackageVersion" 'UNITY_REGISTRY_PACKAGE_CACHE_INVALID')
    }
    return [pscustomobject]@{ Name = [string] $packageMetadata.name; Version = [string] $packageMetadata.version }
}

function Get-SpecOpsUnityRegistryPackageCacheCapabilities {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $ProjectRoot,
        [string] $CacheRoot
    )

    $project = [System.IO.Path]::GetFullPath($ProjectRoot)
    if ([string]::IsNullOrEmpty($CacheRoot)) {
        $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
        if ([string]::IsNullOrEmpty($localAppData)) {
            throw (New-SpecOpsUnityException 'The machine-local Unity package cache root cannot be resolved.' 'UNITY_REGISTRY_PACKAGE_CACHE_MISSING')
        }
        $CacheRoot = [System.IO.Path]::Combine($localAppData, 'Unity', 'cache')
    }
    $cache = [System.IO.Path]::GetFullPath($CacheRoot)
    $indexRoot = [System.IO.Path]::Combine($cache, 'upm', 'db', 'index-v5')
    $contentRoot = [System.IO.Path]::Combine($cache, 'upm', 'db', 'content-v2')

    try {
        $lockBytes = [System.IO.File]::ReadAllBytes([System.IO.Path]::Combine($project, 'Packages', 'packages-lock.json'))
        $lock = $script:Utf8Strict.GetString($lockBytes) | ConvertFrom-Json -Depth 100
    }
    catch {
        throw (New-SpecOpsUnityException 'The materialized package lock cannot be read for registry preflight.' 'UNITY_PACKAGE_AUTHORITY_INVALID' $_.Exception)
    }

    $required = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($property in $lock.dependencies.PSObject.Properties) {
        if (-not [string]::Equals([string] $property.Value.source, 'registry', [StringComparison]::Ordinal)) { continue }
        $name = [string] $property.Name
        $version = [string] $property.Value.version
        $url = [string] $property.Value.url
        if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($version) -or
            -not [string]::Equals($url, 'https://packages.unity.com', [StringComparison]::Ordinal) -or $required.ContainsKey($name)) {
            throw (New-SpecOpsUnityException "The locked registry-package authority is invalid: $name" 'UNITY_PACKAGE_AUTHORITY_INVALID')
        }
        $required.Add($name, [pscustomobject]@{ Name = $name; Version = $version; Registry = 'packages.unity.com' })
    }
    if ($required.Count -eq 0) { return @() }
    if (-not [System.IO.Directory]::Exists($indexRoot) -or -not [System.IO.Directory]::Exists($contentRoot)) {
        throw (New-SpecOpsUnityException 'The standard Unity UPM cache database is missing.' 'UNITY_REGISTRY_PACKAGE_CACHE_MISSING')
    }

    $candidates = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($name in $required.Keys) { $candidates.Add($name, [System.Collections.Generic.List[object]]::new()) }
    $indexInventory = Get-SpecOpsUnityPostRunFileInventory -ProjectRoot $indexRoot
    foreach ($relativeIndexPath in (Get-SpecOpsUnityOrdinalSortedStrings @($indexInventory.Keys))) {
        try { $indexText = $script:Utf8Strict.GetString([System.IO.File]::ReadAllBytes($indexInventory[$relativeIndexPath])) }
        catch { throw (New-SpecOpsUnityException 'The standard Unity UPM cache index is unreadable.' 'UNITY_REGISTRY_PACKAGE_CACHE_INVALID' $_.Exception) }
        foreach ($rawLine in $indexText.Split("`n")) {
            $line = $rawLine.TrimEnd("`r")
            if ([string]::IsNullOrEmpty($line) -or -not $line.Contains('"key":"package-tarball|', [StringComparison]::Ordinal)) { continue }
            $tab = $line.IndexOf("`t", [StringComparison]::Ordinal)
            if ($tab -ne 40 -or $line.IndexOf("`t", $tab + 1) -ge 0) { continue }
            $recordHash = $line.Substring(0, $tab)
            $json = $line.Substring($tab + 1)
            try { $record = $json | ConvertFrom-Json -Depth 20 }
            catch { continue }
            $keyParts = ([string] $record.key).Split('|')
            if ($keyParts.Count -ne 4 -or -not [string]::Equals($keyParts[0], 'package-tarball', [StringComparison]::Ordinal) -or -not $required.ContainsKey($keyParts[1])) { continue }
            $requirement = $required[$keyParts[1]]
            if (-not [string]::Equals($keyParts[2], [string] $requirement.Version, [StringComparison]::Ordinal)) { continue }

            $calculatedRecordHash = [System.Convert]::ToHexString([System.Security.Cryptography.SHA1]::HashData([System.Text.Encoding]::UTF8.GetBytes($json))).ToLowerInvariant()
            $calculatedIndexHash = [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes([string] $record.key))).ToLowerInvariant()
            $expectedIndexPath = "$($calculatedIndexHash.Substring(0, 2))/$($calculatedIndexHash.Substring(2, 2))/$($calculatedIndexHash.Substring(4))"
            $integrityMatch = [regex]::Match([string] $record.integrity, '^sha1-(?<digest>[A-Za-z0-9+/]{27}=)$')
            if (-not [string]::Equals($recordHash, $calculatedRecordHash, [StringComparison]::Ordinal) -or
                -not [string]::Equals($relativeIndexPath, $expectedIndexPath, [StringComparison]::Ordinal) -or -not $integrityMatch.Success) {
                throw (New-SpecOpsUnityException "The registry cache index metadata is invalid: $($requirement.Name)@$($requirement.Version)" 'UNITY_REGISTRY_PACKAGE_CACHE_INVALID')
            }
            [byte[]] $digest = [System.Convert]::FromBase64String($integrityMatch.Groups['digest'].Value)
            $digestHex = [System.Convert]::ToHexString($digest).ToLowerInvariant()
            if (-not [string]::Equals($keyParts[3], $digestHex, [StringComparison]::Ordinal)) {
                throw (New-SpecOpsUnityException "The registry cache key and integrity disagree: $($requirement.Name)@$($requirement.Version)" 'UNITY_REGISTRY_PACKAGE_CACHE_INVALID')
            }
            $candidates[$requirement.Name].Add([pscustomobject]@{ Requirement = $requirement; Record = $record; Digest = $digest; DigestHex = $digestHex })
        }
    }

    $observations = [System.Collections.Generic.List[object]]::new()
    foreach ($name in (Get-SpecOpsUnityOrdinalSortedStrings @($required.Keys))) {
        $matches = $candidates[$name]
        if ($matches.Count -eq 0) {
            throw (New-SpecOpsUnityException "The required registry package is absent from the standard Unity UPM cache: $name@$($required[$name].Version)" 'UNITY_REGISTRY_PACKAGE_CACHE_MISSING')
        }
        if ($matches.Count -ne 1) {
            throw (New-SpecOpsUnityException "The required registry package has ambiguous standard cache entries: $name@$($required[$name].Version)" 'UNITY_REGISTRY_PACKAGE_CACHE_INVALID')
        }
        $candidate = $matches[0]
        $contentPath = [System.IO.Path]::Combine($contentRoot, 'sha1', $candidate.DigestHex.Substring(0, 2), $candidate.DigestHex.Substring(2, 2), $candidate.DigestHex.Substring(4))
        if (-not [System.IO.File]::Exists($contentPath)) {
            throw (New-SpecOpsUnityException "The required registry package content is absent: $name@$($candidate.Requirement.Version)" 'UNITY_REGISTRY_PACKAGE_CACHE_MISSING')
        }
        $archiveLength = [System.IO.FileInfo]::new($contentPath).Length
        $archiveStream = [System.IO.File]::OpenRead($contentPath)
        try { [byte[]] $archiveDigest = [System.Security.Cryptography.SHA1]::HashData($archiveStream) }
        finally { $archiveStream.Dispose() }
        $recordedSize = 0L
        if (-not [int64]::TryParse([string] $candidate.Record.size, [System.Globalization.NumberStyles]::None, [System.Globalization.CultureInfo]::InvariantCulture, [ref] $recordedSize) -or
            $recordedSize -ne $archiveLength -or
            -not (Test-SpecOpsUnityExactBytes -Left $candidate.Digest -Right $archiveDigest)) {
            throw (New-SpecOpsUnityException "The required registry package content integrity is invalid: $name@$($candidate.Requirement.Version)" 'UNITY_REGISTRY_PACKAGE_CACHE_INVALID')
        }
        $identity = Read-SpecOpsUnityRegistryPackageArchiveIdentity -ArchivePath $contentPath -PackageName $name -PackageVersion ([string] $candidate.Requirement.Version)
        $observations.Add([pscustomobject]@{ PackageName = $identity.Name; PackageVersion = $identity.Version; Registry = [string] $candidate.Requirement.Registry; Integrity = [string] $candidate.Record.integrity; ByteLength = $recordedSize })
    }
    return @($observations)
}

function Initialize-SpecOpsUnityOfflinePackageCapability {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $ProjectRoot,
        [string] $CapabilityRoot
    )

    $project = [System.IO.Path]::GetFullPath($ProjectRoot)
    if ([string]::IsNullOrEmpty($CapabilityRoot)) {
        $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
        if ([string]::IsNullOrEmpty($localAppData)) {
            throw (New-SpecOpsUnityException 'The machine-local Unity package capability root cannot be resolved.' 'UNITY_PACKAGE_CAPABILITY_MISSING')
        }
        $CapabilityRoot = [System.IO.Path]::Combine($localAppData, 'SpecOps', 'capabilities', 'unity-git-packages')
    }
    $capabilityBase = [System.IO.Path]::GetFullPath($CapabilityRoot)

    try {
        $manifestText = $script:Utf8Strict.GetString([System.IO.File]::ReadAllBytes([System.IO.Path]::Combine($project, 'Packages', 'manifest.json')))
        $lockText = $script:Utf8Strict.GetString([System.IO.File]::ReadAllBytes([System.IO.Path]::Combine($project, 'Packages', 'packages-lock.json')))
        $projectManifest = $manifestText | ConvertFrom-Json -Depth 100
        $projectLock = $lockText | ConvertFrom-Json -Depth 100
    }
    catch {
        throw (New-SpecOpsUnityException 'The materialized Unity package authority cannot be read.' 'UNITY_PACKAGE_AUTHORITY_INVALID' $_.Exception)
    }

    $gitDependencies = @($projectManifest.dependencies.PSObject.Properties | Where-Object { [string] $_.Value -match '\.git(?:\?|#|$)' })
    $observations = [System.Collections.Generic.List[object]]::new()
    foreach ($dependency in $gitDependencies) {
        $packageName = [string] $dependency.Name
        $requestedVersion = [string] $dependency.Value
        $lockProperty = $projectLock.dependencies.PSObject.Properties[$packageName]
        if ($null -eq $lockProperty -or -not [string]::Equals([string] $lockProperty.Value.source, 'git', [StringComparison]::Ordinal) -or
            -not [string]::Equals([string] $lockProperty.Value.version, $requestedVersion, [StringComparison]::Ordinal)) {
            throw (New-SpecOpsUnityException "The locked git-package authority is inconsistent: $packageName" 'UNITY_PACKAGE_AUTHORITY_INVALID')
        }
        $lockedCommit = [string] $lockProperty.Value.hash
        if ($lockedCommit -cnotmatch '^[0-9a-f]{40}$') {
            throw (New-SpecOpsUnityException "The locked git-package commit is invalid: $packageName" 'UNITY_PACKAGE_AUTHORITY_INVALID')
        }
        $match = [regex]::Match($requestedVersion, '^(?<repository>https://[^?#]+\.git)\?path=(?<subpath>[^#]+)#(?<ref>[^#]+)$')
        if (-not $match.Success) {
            throw (New-SpecOpsUnityException "The git-package reference is not supported by the offline capability contract: $packageName" 'UNITY_PACKAGE_AUTHORITY_INVALID')
        }

        $capabilityDirectory = [System.IO.Path]::Combine($capabilityBase, $packageName, $lockedCommit)
        $capabilityManifestPath = [System.IO.Path]::Combine($capabilityDirectory, 'capability-manifest.json')
        $sourceRoot = [System.IO.Path]::Combine($capabilityDirectory, 'source')
        $gitDirectory = [System.IO.Path]::Combine($capabilityDirectory, 'repository.git')
        try {
            $capability = $script:Utf8Strict.GetString([System.IO.File]::ReadAllBytes($capabilityManifestPath)) | ConvertFrom-Json -Depth 100
        }
        catch {
            throw (New-SpecOpsUnityException "The required offline package capability is missing or unreadable: $packageName" 'UNITY_PACKAGE_CAPABILITY_MISSING' $_.Exception)
        }
        $fingerprintInput = $lockedCommit + $match.Groups['subpath'].Value
        $expectedFingerprint = [System.Convert]::ToHexString([System.Security.Cryptography.SHA1]::HashData([System.Text.Encoding]::UTF8.GetBytes($fingerprintInput))).ToLowerInvariant()
        $identityMatches =
            [string]::Equals([string] $capability.capabilityKind, 'unity-git-package-offline-capability', [StringComparison]::Ordinal) -and
            [string]::Equals([string] $capability.capabilityFormatVersion, '1.0.0', [StringComparison]::Ordinal) -and
            [string]::Equals([string] $capability.packageName, $packageName, [StringComparison]::Ordinal) -and
            [string]::Equals([string] $capability.repositoryUrl, $match.Groups['repository'].Value, [StringComparison]::Ordinal) -and
            [string]::Equals([string] $capability.requestedRef, $match.Groups['ref'].Value, [StringComparison]::Ordinal) -and
            [string]::Equals([string] $capability.packageSubpath, $match.Groups['subpath'].Value, [StringComparison]::Ordinal) -and
            [string]::Equals([string] $capability.lockedCommit, $lockedCommit, [StringComparison]::Ordinal) -and
            [string]::Equals([string] $capability.objectFormat, 'sha1', [StringComparison]::Ordinal) -and
            ([string] $capability.packageTreeObjectId -cmatch '^[0-9a-f]{40}$') -and
            [string]::Equals([string] $capability.upmFingerprint, $expectedFingerprint, [StringComparison]::Ordinal)
        if (-not $identityMatches -or $null -eq $capability.entries -or @($capability.entries).Count -eq 0) {
            throw (New-SpecOpsUnityException "The offline package capability identity is invalid: $packageName" 'UNITY_PACKAGE_CAPABILITY_INVALID')
        }

        if ([System.IO.File]::Exists([System.IO.Path]::Combine($gitDirectory, 'objects', 'info', 'alternates'))) {
            throw (New-SpecOpsUnityException "The offline package capability uses an external object store: $packageName" 'UNITY_PACKAGE_CAPABILITY_REVISION_INVALID')
        }
        $null = Invoke-SpecOpsUnityCapabilityGit -GitDirectory $gitDirectory -Arguments @('fsck', '--strict', '--full', '--no-reflogs', '--no-dangling', $lockedCommit)
        $null = Invoke-SpecOpsUnityCapabilityGit -GitDirectory $gitDirectory -Arguments @('cat-file', '-e', "$lockedCommit^{commit}")
        $resolvedTree = (Invoke-SpecOpsUnityCapabilityGit -GitDirectory $gitDirectory -Arguments @('rev-parse', "$lockedCommit`:$($match.Groups['subpath'].Value)")).Trim()
        if ($resolvedTree -cnotmatch '^[0-9a-f]{40}$' -or
            -not [string]::Equals($resolvedTree, [string] $capability.packageTreeObjectId, [StringComparison]::Ordinal) -or
            -not [string]::Equals((Invoke-SpecOpsUnityCapabilityGit -GitDirectory $gitDirectory -Arguments @('cat-file', '-t', $resolvedTree)).Trim(), 'tree', [StringComparison]::Ordinal)) {
            throw (New-SpecOpsUnityException "The locked package subtree does not match the capability: $packageName" 'UNITY_PACKAGE_CAPABILITY_REVISION_INVALID')
        }
        $revisionEntries = Get-SpecOpsUnityCapabilityTreeEntries -GitDirectory $gitDirectory -TreeObjectId $resolvedTree

        $actualSource = Get-SpecOpsUnityPostRunFileInventory -ProjectRoot $sourceRoot
        $expectedPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $validated = [System.Collections.Generic.List[object]]::new()
        foreach ($entry in @($capability.entries)) {
            $path = Assert-SpecOpsUnitySubjectPath -Path ([string] $entry.path)
            if (-not $expectedPaths.Add($path) -or -not $actualSource.ContainsKey($path) -or -not $revisionEntries.ContainsKey($path) -or
                [string] $entry.sha256 -cnotmatch '^[0-9a-f]{64}$') {
                throw (New-SpecOpsUnityException "The offline package capability inventory is invalid: $packageName" 'UNITY_PACKAGE_CAPABILITY_INVALID')
            }
            [byte[]] $bytes = [System.IO.File]::ReadAllBytes($actualSource[$path])
            $sha256 = [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
            [byte[]] $gitHeader = [System.Text.Encoding]::ASCII.GetBytes("blob $($bytes.LongLength)`0")
            [byte[]] $gitObjectBytes = [byte[]]::new($gitHeader.Length + $bytes.Length)
            [System.Buffer]::BlockCopy($gitHeader, 0, $gitObjectBytes, 0, $gitHeader.Length)
            [System.Buffer]::BlockCopy($bytes, 0, $gitObjectBytes, $gitHeader.Length, $bytes.Length)
            $gitObjectId = [System.Convert]::ToHexString([System.Security.Cryptography.SHA1]::HashData($gitObjectBytes)).ToLowerInvariant()
            $revisionEntry = $revisionEntries[$path]
            if ($bytes.LongLength -ne [int64] $entry.byteLength -or
                -not [string]::Equals($sha256, [string] $entry.sha256, [StringComparison]::Ordinal) -or
                -not [string]::Equals([string] $entry.gitObjectType, 'blob', [StringComparison]::Ordinal) -or
                -not [string]::Equals($gitObjectId, [string] $entry.gitObjectId, [StringComparison]::Ordinal) -or
                -not [string]::Equals([string] $entry.gitMode, [string] $revisionEntry.Mode, [StringComparison]::Ordinal) -or
                -not [string]::Equals([string] $entry.gitObjectType, [string] $revisionEntry.Type, [StringComparison]::Ordinal) -or
                -not [string]::Equals([string] $entry.gitObjectId, [string] $revisionEntry.ObjectId, [StringComparison]::Ordinal)) {
                throw (New-SpecOpsUnityException "The offline package capability bytes are invalid: $packageName/$path" 'UNITY_PACKAGE_CAPABILITY_INVALID')
            }
            $validated.Add([pscustomobject]@{ Path = $path; Bytes = $bytes })
        }
        if ($actualSource.Count -ne $expectedPaths.Count -or $revisionEntries.Count -ne $expectedPaths.Count) {
            throw (New-SpecOpsUnityException "The offline package capability has unexpected files: $packageName" 'UNITY_PACKAGE_CAPABILITY_INVALID')
        }

        $packageJsonEntry = @($validated | Where-Object { [string]::Equals($_.Path, 'package.json', [StringComparison]::Ordinal) })
        if ($packageJsonEntry.Count -ne 1) {
            throw (New-SpecOpsUnityException "The offline package capability has no unique package.json: $packageName" 'UNITY_PACKAGE_CAPABILITY_INVALID')
        }
        try { $packageJson = $script:Utf8Strict.GetString([byte[]] $packageJsonEntry[0].Bytes) | ConvertFrom-Json -AsHashtable -Depth 100 }
        catch { throw (New-SpecOpsUnityException "The offline package metadata is invalid: $packageName" 'UNITY_PACKAGE_CAPABILITY_INVALID' $_.Exception) }
        if (-not [string]::Equals([string] $packageJson.name, $packageName, [StringComparison]::Ordinal) -or
            -not [string]::Equals([string] $packageJson.version, [string] $capability.packageVersion, [StringComparison]::Ordinal)) {
            throw (New-SpecOpsUnityException "The offline package metadata identity is invalid: $packageName" 'UNITY_PACKAGE_CAPABILITY_INVALID')
        }

        $sourcePackageMetadata = $packageJson | ConvertTo-Json -Depth 100 -Compress
        $packageJson['_fingerprint'] = $expectedFingerprint
        [byte[]] $generatedPackageJsonBytes = $script:Utf8Strict.GetBytes(($packageJson | ConvertTo-Json -Depth 100) + "`n")
        $seedRoot = [System.IO.Path]::Combine($project, 'Library', 'PackageCache', "$packageName@$($expectedFingerprint.Substring(0, 12))")
        foreach ($entry in $validated) {
            $destination = [System.IO.Path]::Combine($seedRoot, ([string] $entry.Path).Replace('/', [System.IO.Path]::DirectorySeparatorChar))
            $parent = [System.IO.Path]::GetDirectoryName($destination)
            if (-not [System.IO.Directory]::Exists($parent)) { $null = [System.IO.Directory]::CreateDirectory($parent) }
            [byte[]] $seedBytes = if ([string]::Equals([string] $entry.Path, 'package.json', [StringComparison]::Ordinal)) { $generatedPackageJsonBytes } else { [byte[]] $entry.Bytes }
            [System.IO.File]::WriteAllBytes($destination, $seedBytes)
            [byte[]] $writtenBytes = [System.IO.File]::ReadAllBytes($destination)
            if (-not (Test-SpecOpsUnityExactBytes -Left $seedBytes -Right $writtenBytes)) {
                throw (New-SpecOpsUnityException "The offline package seed failed point-of-use validation: $packageName/$($entry.Path)" 'UNITY_PACKAGE_CAPABILITY_INVALID')
            }
            if ([string]::Equals([string] $entry.Path, 'package.json', [StringComparison]::Ordinal)) {
                try { $seedMetadata = $script:Utf8Strict.GetString($writtenBytes) | ConvertFrom-Json -AsHashtable -Depth 100 }
                catch { throw (New-SpecOpsUnityException "The generated package metadata is invalid: $packageName" 'UNITY_PACKAGE_CAPABILITY_INVALID' $_.Exception) }
                if (-not [string]::Equals([string] $seedMetadata['_fingerprint'], $expectedFingerprint, [StringComparison]::Ordinal)) {
                    throw (New-SpecOpsUnityException "The generated package fingerprint is invalid: $packageName" 'UNITY_PACKAGE_CAPABILITY_INVALID')
                }
                $null = $seedMetadata.Remove('_fingerprint')
                if (-not [string]::Equals(($seedMetadata | ConvertTo-Json -Depth 100 -Compress), $sourcePackageMetadata, [StringComparison]::Ordinal)) {
                    throw (New-SpecOpsUnityException "The generated package metadata changed beyond its fingerprint: $packageName" 'UNITY_PACKAGE_CAPABILITY_INVALID')
                }
            }
            elseif (-not (Test-SpecOpsUnityExactBytes -Left ([byte[]] $entry.Bytes) -Right $writtenBytes)) {
                throw (New-SpecOpsUnityException "The offline package seed changed verified source bytes: $packageName/$($entry.Path)" 'UNITY_PACKAGE_CAPABILITY_INVALID')
            }
        }
        $observations.Add([pscustomobject]@{
            PackageName = $packageName
            PackageVersion = [string] $capability.packageVersion
            LockedCommit = $lockedCommit
            UpmFingerprint = $expectedFingerprint
            EntryCount = $validated.Count
            NetworkAcquisitionAllowed = $false
        })
    }
    return @($observations)
}

function Get-SpecOpsUnitySubjectObservation {
    param(
        [Parameter(Mandatory)] $Workspace,
        [Parameter(Mandatory)] $Materialization
    )

    $projectRoot = [System.IO.Path]::GetFullPath([string] $Materialization.ProjectRoot).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    if (-not [string]::Equals($projectRoot, [System.IO.Path]::GetFullPath([string] $Workspace.SubjectRoot).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar), [System.StringComparison]::OrdinalIgnoreCase) -or
        $null -eq $Materialization.PSObject.Properties['Manifest']) {
        throw (New-SpecOpsUnityException 'Subject materialization does not match the owned workspace.' 'UNITY_SUBJECT_INVENTORY_INVALID')
    }

    $baseline = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($entry in @($Materialization.Manifest)) {
        $path = Assert-SpecOpsUnitySubjectPath -Path ([string] $entry.Path)
        if ($baseline.ContainsKey($path) -or $null -eq $entry.PSObject.Properties['ComparisonBytes']) {
            throw (New-SpecOpsUnityException 'Subject materialization manifest is invalid.' 'UNITY_SUBJECT_INVENTORY_INVALID')
        }
        [byte[]] $beforeBytes = @($entry.ComparisonBytes)
        $baseline.Add($path, [pscustomobject]@{ Path = $path; Bytes = $beforeBytes })
    }

    $actual = Get-SpecOpsUnityPostRunFileInventory -ProjectRoot $projectRoot
    $changed = [System.Collections.Generic.List[object]]::new()
    foreach ($path in (Get-SpecOpsUnityOrdinalSortedStrings @($baseline.Keys))) {
        $before = [byte[]] $baseline[$path].Bytes
        if (-not $actual.ContainsKey($path)) {
            $changed.Add([pscustomobject]@{ Path = $path; Change = 'Missing'; BeforeBytes = $before; AfterBytes = $null })
            continue
        }
        [byte[]] $after = [System.IO.File]::ReadAllBytes($actual[$path])
        if (-not (Test-SpecOpsUnityExactBytes -Left $before -Right $after)) {
            $changed.Add([pscustomobject]@{ Path = $path; Change = 'Modified'; BeforeBytes = $before; AfterBytes = $after })
        }
    }

    $generated = [System.Collections.Generic.List[string]]::new()
    foreach ($relative in $actual.Keys) {
        if (-not $baseline.ContainsKey($relative)) { $generated.Add($relative) }
    }
    $generatedPaths = Get-SpecOpsUnityOrdinalSortedStrings @($generated)

    $lockPath = 'Packages/packages-lock.json'
    $lockStatus = 'NotInBaseline'
    $lockPreserved = $false
    if ($baseline.ContainsKey($lockPath)) {
        $lockChange = @($changed | Where-Object { [string]::Equals($_.Path, $lockPath, [System.StringComparison]::Ordinal) })
        if ($lockChange.Count -eq 0) { $lockStatus = 'Preserved'; $lockPreserved = $true }
        else { $lockStatus = [string] $lockChange[0].Change }
    }

    return [pscustomobject]@{
        ChangedEntries = @($changed)
        GeneratedPaths = $generatedPaths
        PackagesLock = [pscustomobject]@{
            Path = $lockPath
            BaselineExists = $baseline.ContainsKey($lockPath)
            ExactBytePreserved = $lockPreserved
            Status = $lockStatus
        }
    }
}

function Get-SpecOpsUnityExternalObservations {
    param(
        [AllowEmptyCollection()] [object[]] $Targets,
        [Parameter(Mandatory)] [int] $TimeoutMilliseconds,
        [Parameter(Mandatory)] [int] $StableIntervalMilliseconds,
        [Parameter(Mandatory)] [scriptblock] $ReadFileBytes
    )

    $byName = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($target in @($Targets)) {
        foreach ($property in @('LogicalName', 'Path', 'Exists')) {
            if ($null -eq $target.PSObject.Properties[$property]) {
                throw (New-SpecOpsUnityException 'External observation target is incomplete.' 'UNITY_EXTERNAL_TARGET_INVALID')
            }
        }
        $logicalName = [string] $target.LogicalName
        $path = [string] $target.Path
        if ([string]::IsNullOrWhiteSpace($logicalName) -or -not [System.IO.Path]::IsPathFullyQualified($path) -or $byName.ContainsKey($logicalName)) {
            throw (New-SpecOpsUnityException 'External observation target is invalid or duplicated.' 'UNITY_EXTERNAL_TARGET_INVALID')
        }
        $beforeExists = [bool] $target.Exists
        $bytesProperty = $target.PSObject.Properties['Bytes']
        if ($beforeExists -and ($null -eq $bytesProperty -or $null -eq $bytesProperty.Value)) {
            throw (New-SpecOpsUnityException 'Present external baseline has no exact bytes.' 'UNITY_EXTERNAL_TARGET_INVALID')
        }
        [byte[]] $beforeBytes = $null
        if ($beforeExists) { $beforeBytes = [byte[]] $bytesProperty.Value }
        $canonical = [System.IO.Path]::GetFullPath($path)
        $afterExists = [System.IO.File]::Exists($canonical)
        [byte[]] $afterBytes = if ($afterExists) {
            Read-SpecOpsUnityStableFileBytes -Path $canonical -LogicalName $logicalName -RequireNonEmpty $false -TimeoutMilliseconds $TimeoutMilliseconds -StableIntervalMilliseconds $StableIntervalMilliseconds -ReadFileBytes $ReadFileBytes
        }
        else { $null }
        $state = if (-not $beforeExists -and -not $afterExists) { 'AbsentBeforeAbsentAfter' }
            elseif (-not $beforeExists) { 'Created' }
            elseif (-not $afterExists) { 'Missing' }
            elseif (Test-SpecOpsUnityExactBytes -Left $beforeBytes -Right $afterBytes) { 'Unchanged' }
            else { 'Modified' }
        $byName.Add($logicalName, [pscustomobject]@{
            LogicalName = $logicalName
            Path = $canonical
            BeforeExists = $beforeExists
            AfterExists = $afterExists
            State = $state
            BeforeBytes = $beforeBytes
            AfterBytes = $afterBytes
        })
    }

    $ordered = [System.Collections.Generic.List[object]]::new()
    foreach ($name in (Get-SpecOpsUnityOrdinalSortedStrings @($byName.Keys))) { $ordered.Add($byName[$name]) }
    return @($ordered)
}

function Invoke-SpecOpsUnityObservationLifecycleCore {
    param(
        [Parameter(Mandatory)] $Workspace,
        [Parameter(Mandatory)] $Materialization,
        [Parameter(Mandatory)] [string] $ResultsPath,
        [Parameter(Mandatory)] [string] $LogPath,
        [string] $TracePath,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $RequiredTestFullNames,
        [AllowEmptyCollection()] [object[]] $ExternalTargets = @(),
        [Parameter(Mandatory)] [int] $QuiescenceTimeoutMilliseconds,
        [Parameter(Mandatory)] [int] $StableIntervalMilliseconds,
        [Parameter(Mandatory)] [scriptblock] $ReadFileBytes,
        [Parameter(Mandatory)] [scriptblock] $CleanupWorkspace,
        [scriptblock] $FileExists = { param($candidatePath) [System.IO.File]::Exists($candidatePath) }
    )

    $null = Assert-SpecOpsUnityOwnedWorkspace -Workspace $Workspace
    $canonicalResults = Assert-SpecOpsUnityObservationOutputPath -Workspace $Workspace -Path $ResultsPath -LogicalName 'results.xml'
    $canonicalLog = Assert-SpecOpsUnityObservationOutputPath -Workspace $Workspace -Path $LogPath -LogicalName 'unity.log'
    [byte[]] $logBytes = Read-SpecOpsUnityStableFileBytes -Path $canonicalLog -LogicalName 'unity.log' -RequireNonEmpty $true -TimeoutMilliseconds $QuiescenceTimeoutMilliseconds -StableIntervalMilliseconds $StableIntervalMilliseconds -ReadFileBytes $ReadFileBytes -FileExists $FileExists
    $compilation = Read-SpecOpsUnityCompilationObservation -Bytes $logBytes
    [byte[]] $resultBytes = $null
    $nunit = $null
    $allowAbsentResults = $compilation.Completed -and $compilation.Errors -gt 0
    $resultBytes = Read-SpecOpsUnityStableFileBytes -Path $canonicalResults -LogicalName 'results.xml' -RequireNonEmpty $true -TimeoutMilliseconds $QuiescenceTimeoutMilliseconds -StableIntervalMilliseconds $StableIntervalMilliseconds -ReadFileBytes $ReadFileBytes -FileExists $FileExists -AllowAbsentAfterTimeout $allowAbsentResults
    $resultsExist = $null -ne $resultBytes
    if ($resultsExist) {
        $nunit = Read-SpecOpsUnityNUnit3Result -Bytes $resultBytes -RequiredTestFullNames $RequiredTestFullNames
    }

    $trace = if ([string]::IsNullOrEmpty($TracePath) -or -not [System.IO.File]::Exists($TracePath)) {
        [pscustomobject]@{ Exists = $false; Path = if ([string]::IsNullOrEmpty($TracePath)) { $null } else { [System.IO.Path]::GetFullPath($TracePath) }; Bytes = $null }
    }
    else {
        $canonicalTrace = [System.IO.Path]::GetFullPath($TracePath)
        [byte[]] $traceBytes = Read-SpecOpsUnityStableFileBytes -Path $canonicalTrace -LogicalName 'trace' -RequireNonEmpty $false -TimeoutMilliseconds $QuiescenceTimeoutMilliseconds -StableIntervalMilliseconds $StableIntervalMilliseconds -ReadFileBytes $ReadFileBytes
        [pscustomobject]@{ Exists = $true; Path = $canonicalTrace; Bytes = $traceBytes }
    }
    $subject = Get-SpecOpsUnitySubjectObservation -Workspace $Workspace -Materialization $Materialization
    $external = Get-SpecOpsUnityExternalObservations -Targets $ExternalTargets -TimeoutMilliseconds $QuiescenceTimeoutMilliseconds -StableIntervalMilliseconds $StableIntervalMilliseconds -ReadFileBytes $ReadFileBytes

    $result = [pscustomobject]@{
        Results = [pscustomobject]@{ Exists = $resultsExist; Path = $canonicalResults; Bytes = $resultBytes; NUnit3 = $nunit }
        Log = [pscustomobject]@{ Path = $canonicalLog; Bytes = $logBytes }
        Compilation = $compilation
        Trace = $trace
        ChangedEntries = $subject.ChangedEntries
        GeneratedPaths = $subject.GeneratedPaths
        PackagesLock = $subject.PackagesLock
        ExternalTargets = $external
        Cleanup = [pscustomobject]@{ Attempted = $false; Succeeded = $false; RejectionClass = $null; Diagnostic = $null }
    }

    $result.Cleanup.Attempted = $true
    try {
        $null = & $CleanupWorkspace $Workspace
        $result.Cleanup.Succeeded = $true
    }
    catch {
        $metadata = Get-SpecOpsUnityErrorMetadata -ErrorRecord $_
        $result.Cleanup.RejectionClass = $metadata.RejectionClass
        $result.Cleanup.Diagnostic = $_.Exception.Message
    }
    return $result
}

function Invoke-SpecOpsUnityObservationLifecycle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Workspace,
        [Parameter(Mandatory)] $Materialization,
        [Parameter(Mandatory)] [string] $ResultsPath,
        [Parameter(Mandatory)] [string] $LogPath,
        [string] $TracePath,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $RequiredTestFullNames,
        [AllowEmptyCollection()] [object[]] $ExternalTargets = @()
    )

    return Invoke-SpecOpsUnityObservationLifecycleCore -Workspace $Workspace -Materialization $Materialization -ResultsPath $ResultsPath -LogPath $LogPath -TracePath $TracePath -RequiredTestFullNames $RequiredTestFullNames -ExternalTargets $ExternalTargets -QuiescenceTimeoutMilliseconds $script:ObservationQuiescenceMilliseconds -StableIntervalMilliseconds $script:ObservationStableIntervalMilliseconds -ReadFileBytes { param($path) [System.IO.File]::ReadAllBytes($path) } -CleanupWorkspace { param($ownedWorkspace) Remove-SpecOpsUnityWorkspace -Workspace $ownedWorkspace }
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
        [Parameter(Mandatory)] [int] $TerminationWaitMilliseconds,
        [System.Collections.IDictionary] $EnvironmentVariables = @{}
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
        foreach ($name in $EnvironmentVariables.Keys) {
            if ([string]::IsNullOrEmpty([string] $name) -or $null -eq $EnvironmentVariables[$name]) {
                throw (New-SpecOpsUnityException 'A controlled-process environment override is invalid.' 'UNITY_PROCESS_ENVIRONMENT_INVALID')
            }
            $startInfo.Environment[[string] $name] = [string] $EnvironmentVariables[$name]
        }
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
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $ArgumentList,
        [System.Collections.IDictionary] $EnvironmentVariables = @{}
    )

    return Invoke-SpecOpsControlledProcessCore -FilePath $FilePath -ArgumentList $ArgumentList -TimeoutMilliseconds $script:CanonicalTimeoutMilliseconds -TerminationWaitMilliseconds $script:TerminationWaitMilliseconds -EnvironmentVariables $EnvironmentVariables
}

function Get-SpecOpsUnityPackageAcquisitionGuard {
    [CmdletBinding()]
    param()

    return [ordered]@{
        GIT_ALLOW_PROTOCOL = ''
        GIT_CONFIG_COUNT = '1'
        GIT_CONFIG_KEY_0 = 'protocol.allow'
        GIT_CONFIG_VALUE_0 = 'never'
        GIT_TERMINAL_PROMPT = '0'
        GCM_INTERACTIVE = 'Never'
    }
}

Export-ModuleMember -Function @(
    'ConvertFrom-SpecOpsUnityProductVersion',
    'Get-SpecOpsUnityErrorMetadata',
    'Get-SpecOpsUnityExecutableMetadata',
    'Get-SpecOpsUnityPackageAcquisitionGuard',
    'Get-SpecOpsUnityRegistryPackageCacheCapabilities',
    'Invoke-SpecOpsControlledProcess',
    'Invoke-SpecOpsUnityObservationLifecycle',
    'Initialize-SpecOpsUnityOfflinePackageCapability',
    'New-SpecOpsUnityArgumentVector',
    'New-SpecOpsUnitySubjectMaterialization',
    'New-SpecOpsUnityWorkspace',
    'Read-SpecOpsUnityNUnit3Result',
    'Read-SpecOpsUnityCompilationObservation',
    'Read-SpecOpsUnityProjectVersionRequirement',
    'Remove-SpecOpsUnityWorkspace',
    'Select-SpecOpsUnityExecutable'
)
