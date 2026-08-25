Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Tests = 0
$script:Failures = [System.Collections.Generic.List[string]]::new()
$modulePath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, '..', 'SpecOps.Unity.psm1'))
$repositoryRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, '..', '..', '..'))
Import-Module -Name $modulePath -Force -ErrorAction Stop
$module = Get-Module -Name SpecOps.Unity
$utf8 = [System.Text.UTF8Encoding]::new($false)
$successCompilationLog = "AssetDatabase: script compilation time: 1.250000s`n"

function Test-Case {
    param([string] $Name, [scriptblock] $Body)
    $script:Tests++
    try { & $Body; [Console]::Out.WriteLine("PASS $Name") }
    catch { $script:Failures.Add("${Name}: $($_.Exception.Message)"); [Console]::Out.WriteLine("FAIL $Name -- $($_.Exception.Message)") }
}
function Assert-True { param([bool] $Value, [string] $Message) if (-not $Value) { throw $Message } }
function Assert-False { param([bool] $Value, [string] $Message) if ($Value) { throw $Message } }
function Assert-Equal { param($Expected, $Actual, [string] $Message) if (-not [string]::Equals([string] $Expected, [string] $Actual, [System.StringComparison]::Ordinal)) { throw "$Message Expected=[$Expected] Actual=[$Actual]" } }
function Assert-Bytes { param([byte[]] $Expected, [byte[]] $Actual, [string] $Message) if (-not [string]::Equals([System.Convert]::ToHexString($Expected), [System.Convert]::ToHexString($Actual), [System.StringComparison]::Ordinal)) { throw $Message } }
function Assert-Rejected {
    param([scriptblock] $Body, [string] $Class)
    try { & $Body; throw 'Expected rejection did not occur.' }
    catch {
        if ($_.Exception.Message -eq 'Expected rejection did not occur.') { throw }
        Assert-Equal $Class ([string] $_.Exception.Data['SpecOpsRejectionClass']) 'Unexpected rejection class.'
    }
}
function Get-VersionBytes {
    param([string] $Version = '6000.5.8f1', [string] $Combined = '6000.5.8f1 (5cb7df797b7d)', [string[]] $Extra = @())
    return $utf8.GetBytes(([string]::Join("`n", @("m_EditorVersion: $Version", "m_EditorVersionWithRevision: $Combined") + $Extra) + "`n"))
}
function New-TestHubCandidate {
    param([string] $Root, [string] $DirectoryName)
    $path = [System.IO.Path]::Combine($Root, $DirectoryName, 'Editor', 'Unity.exe')
    $null = [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($path))
    [System.IO.File]::WriteAllBytes($path, [byte[]] @(0))
    return [System.IO.Path]::GetFullPath($path)
}
function Invoke-SelectionCore {
    param($Requirement, [string] $Explicit, [string[]] $Roots, [scriptblock] $Inspector)
    return & $module { param($r, $e, $h, $i) Select-SpecOpsUnityExecutableCore -Requirement $r -ExplicitExecutablePath $e -HubRoots $h -MetadataInspector $i } $Requirement $Explicit $Roots $Inspector
}
function New-TestSnapshot {
    param([object[]] $Entries)
    return [pscustomobject]@{ Inventory = @($Entries) }
}
function New-TestEntry {
    param([string] $Path, [string] $Type = 'blob', [string] $Mode = '100644')
    return [pscustomobject]@{ Path = $Path; ObjectType = $Type; Mode = $Mode }
}
function Invoke-ProcessCore {
    param([string] $File, [string[]] $Arguments, [int] $Timeout = 5000, [int] $TerminationWait = 30000, [System.Collections.IDictionary] $EnvironmentVariables = @{})
    return & $module { param($f, $a, $t, $w, $environment) Invoke-SpecOpsControlledProcessCore -FilePath $f -ArgumentList $a -TimeoutMilliseconds $t -TerminationWaitMilliseconds $w -EnvironmentVariables $environment } $File $Arguments $Timeout $TerminationWait $EnvironmentVariables
}
function Escape-XmlAttribute { param([string] $Value) return [System.Security.SecurityElement]::Escape($Value) }
function New-NUnit3Xml {
    param(
        [string[]] $TestNames = $requiredTests,
        [hashtable] $ResultOverrides = @{},
        [string] $AssemblyName = 'InfiniteMonkey.EditModeTests.dll',
        [string] $AssemblyFullName = 'C:\machine-specific\Library\ScriptAssemblies\InfiniteMonkey.EditModeTests.dll',
        [int] $MissingFullNameIndex = -1,
        [switch] $DuplicateAssembly,
        [hashtable] $RootCountOverrides = @{}
    )
    $testCases = [System.Collections.Generic.List[string]]::new()
    $counts = [ordered]@{ Passed = 0; Failed = 0; Inconclusive = 0; Skipped = 0 }
    for ($index = 0; $index -lt $TestNames.Count; $index++) {
        $name = $TestNames[$index]
        $state = if ($ResultOverrides.ContainsKey($name)) { $ResultOverrides[$name] } else { [pscustomobject]@{ Result = 'Passed' } }
        if ($counts.Contains($state.Result)) { $counts[$state.Result]++ }
        $identity = if ($index -eq $MissingFullNameIndex) { '' } else { ' fullname="{0}"' -f (Escape-XmlAttribute $name) }
        $label = if ($null -ne $state.PSObject.Properties['Label']) { ' label="{0}"' -f (Escape-XmlAttribute ([string] $state.Label)) } else { '' }
        $runState = if ($null -ne $state.PSObject.Properties['RunState']) { ' runstate="{0}"' -f (Escape-XmlAttribute ([string] $state.RunState)) } else { '' }
        $testCases.Add(('<test-case name="display-{0}"{1} result="{2}"{3}{4} />' -f $index, $identity, (Escape-XmlAttribute ([string] $state.Result)), $label, $runState))
    }
    $total = $TestNames.Count
    $suiteResult = if ($counts.Failed -gt 0) { 'Failed' } elseif ($counts.Inconclusive -gt 0) { 'Inconclusive' } elseif ($counts.Skipped -eq $total -and $total -gt 0) { 'Skipped' } else { 'Passed' }
    $suite = '<test-suite type="Assembly" name="{0}" fullname="{1}" result="{2}" testcasecount="{3}" total="{3}" passed="{4}" failed="{5}" inconclusive="{6}" skipped="{7}"><test-suite type="TestFixture" name="fixture">{8}</test-suite></test-suite>' -f (Escape-XmlAttribute $AssemblyName), (Escape-XmlAttribute $AssemblyFullName), $suiteResult, $total, $counts.Passed, $counts.Failed, $counts.Inconclusive, $counts.Skipped, ([string]::Join('', $testCases))
    $rootValues = [ordered]@{ testcasecount = $total; total = $total; passed = $counts.Passed; failed = $counts.Failed; inconclusive = $counts.Inconclusive; skipped = $counts.Skipped }
    foreach ($key in $RootCountOverrides.Keys) { $rootValues[$key] = $RootCountOverrides[$key] }
    $rootResult = if ($counts.Failed -gt 0) { 'Failed' } elseif ($counts.Inconclusive -gt 0) { 'Inconclusive' } elseif ($counts.Skipped -eq $total -and $total -gt 0) { 'Skipped' } else { 'Passed' }
    $assemblies = if ($DuplicateAssembly) { $suite + $suite } else { $suite }
    return '<?xml version="1.0" encoding="utf-8"?><test-run result="{0}" testcasecount="{1}" total="{2}" passed="{3}" failed="{4}" inconclusive="{5}" skipped="{6}">{7}</test-run>' -f $rootResult, $rootValues.testcasecount, $rootValues.total, $rootValues.passed, $rootValues.failed, $rootValues.inconclusive, $rootValues.skipped, $assemblies
}
function Read-TestNUnit3 { param([string] $Xml) return Read-SpecOpsUnityNUnit3Result -Bytes $utf8.GetBytes($Xml) -RequiredTestFullNames $requiredTests }
function Remove-TestDirectory {
    param([string] $Path)
    $resolved = [System.IO.Path]::GetFullPath($Path)
    $temp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if (-not $resolved.StartsWith($temp, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe test cleanup path: $resolved" }
    if ([System.IO.Directory]::Exists($resolved)) { Remove-Item -LiteralPath ("\\?\" + $resolved) -Recurse -Force }
}
function Write-TestFileBytes {
    param([string] $Path, [byte[]] $Bytes)
    $parent = [System.IO.Path]::GetDirectoryName($Path)
    if (-not [System.IO.Directory]::Exists($parent)) { $null = [System.IO.Directory]::CreateDirectory($parent) }
    [System.IO.File]::WriteAllBytes($Path, $Bytes)
}
function Invoke-TestGit {
    param([string] $Root, [string[]] $Arguments)
    $output = & git -C $Root @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Fixture Git failed: $output" }
    return @($output)
}
function New-OfflineCapabilityFixture {
    param([switch] $CorruptSource, [switch] $WrongFingerprint, [switch] $FakeTree)
    $root = [System.IO.Path]::Combine($fixtureRoot, "o-$([guid]::NewGuid().ToString('N').Substring(0, 8))")
    $project = [System.IO.Path]::Combine($root, 'project')
    $capabilityRoot = [System.IO.Path]::Combine($root, 'capabilities')
    $repository = [System.IO.Path]::Combine($root, 'repository')
    $name = 'jp.hadashikick.vcontainer'; $version = '1.18.0'; $subpath = 'VContainer/Assets/VContainer'
    $reference = 'https://github.com/hadashiA/VContainer.git?path=VContainer/Assets/VContainer#1.18.0'
    $files = [ordered]@{ 'package.json' = $utf8.GetBytes('{"name":"jp.hadashikick.vcontainer","version":"1.18.0"}'); 'Runtime/VContainer.cs' = $utf8.GetBytes('namespace VContainer {}') }
    $null = [System.IO.Directory]::CreateDirectory($repository)
    $null = Invoke-TestGit $repository @('init', '--quiet')
    $null = Invoke-TestGit $repository @('config', 'user.email', 'specops-tests@example.invalid'); $null = Invoke-TestGit $repository @('config', 'user.name', 'SpecOps Tests'); $null = Invoke-TestGit $repository @('config', 'core.autocrlf', 'false')
    foreach ($path in $files.Keys) { Write-TestFileBytes ([System.IO.Path]::Combine($repository, $subpath.Replace('/', [System.IO.Path]::DirectorySeparatorChar), $path.Replace('/', [System.IO.Path]::DirectorySeparatorChar))) ([byte[]] $files[$path]) }
    $null = Invoke-TestGit $repository @('add', '--all'); $null = Invoke-TestGit $repository @('commit', '--quiet', '-m', 'offline package fixture', '--date=2000-01-01T00:00:00Z')
    $commit = [string] @(Invoke-TestGit $repository @('rev-parse', 'HEAD'))[0]
    $tree = [string] @(Invoke-TestGit $repository @('rev-parse', "HEAD:$subpath"))[0]
    $fingerprint = [System.Convert]::ToHexString([System.Security.Cryptography.SHA1]::HashData($utf8.GetBytes($commit + $subpath))).ToLowerInvariant()
    Write-TestFileBytes ([System.IO.Path]::Combine($project, 'Packages', 'manifest.json')) $utf8.GetBytes((@{ dependencies = @{ $name = $reference } } | ConvertTo-Json -Depth 10))
    Write-TestFileBytes ([System.IO.Path]::Combine($project, 'Packages', 'packages-lock.json')) $utf8.GetBytes((@{ dependencies = @{ $name = @{ version = $reference; depth = 0; source = 'git'; hash = $commit } } } | ConvertTo-Json -Depth 10))
    $capability = [System.IO.Path]::Combine($capabilityRoot, $name, $commit)
    $source = [System.IO.Path]::Combine($capability, 'source')
    $null = [System.IO.Directory]::CreateDirectory($capability)
    $null = Invoke-TestGit $root @('clone', '--quiet', '--bare', $repository, ([System.IO.Path]::Combine($capability, 'repository.git')))
    foreach ($path in $files.Keys) { Write-TestFileBytes ([System.IO.Path]::Combine($source, $path.Replace('/', [System.IO.Path]::DirectorySeparatorChar))) ([byte[]] $files[$path]) }
    $treeRecords = @(Invoke-TestGit $repository @('ls-tree', '-r', "HEAD:$subpath"))
    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($record in $treeRecords) {
        $match = [regex]::Match([string] $record, '^(?<mode>[0-9]{6}) (?<type>[^ ]+) (?<object>[0-9a-f]{40})\t(?<path>.+)$')
        if (-not $match.Success) { throw "Invalid fixture tree record: $record" }
        $path = $match.Groups['path'].Value; $bytes = [byte[]] $files[$path]
        $entries.Add([ordered]@{ path = $path; gitMode = $match.Groups['mode'].Value; gitObjectType = $match.Groups['type'].Value; gitObjectId = $match.Groups['object'].Value; byteLength = $bytes.LongLength; sha256 = [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant() })
    }
    $manifest = [ordered]@{ capabilityKind = 'unity-git-package-offline-capability'; capabilityFormatVersion = '1.0.0'; packageName = $name; packageVersion = $version; repositoryUrl = 'https://github.com/hadashiA/VContainer.git'; requestedRef = '1.18.0'; objectFormat = 'sha1'; lockedCommit = $commit; packageSubpath = $subpath; packageTreeObjectId = $(if ($FakeTree) { '2' * 40 } else { $tree }); upmFingerprint = $(if ($WrongFingerprint) { '3' * 40 } else { $fingerprint }); entries = @($entries) }
    Write-TestFileBytes ([System.IO.Path]::Combine($capability, 'capability-manifest.json')) $utf8.GetBytes(($manifest | ConvertTo-Json -Depth 20))
    if ($CorruptSource) { Write-TestFileBytes ([System.IO.Path]::Combine($source, 'Runtime', 'VContainer.cs')) $utf8.GetBytes('corrupt') }
    return [pscustomobject]@{ ProjectRoot = $project; CapabilityRoot = $capabilityRoot; PackageName = $name; Version = $version; Commit = $commit; Subpath = $subpath; Tree = $tree; Fingerprint = $fingerprint; SourceBytes = $files }
}
function New-TestRegistryPackageArchive {
    param([string] $Name, [string] $Version)
    $archive = [System.IO.MemoryStream]::new()
    $gzip = [System.IO.Compression.GZipStream]::new($archive, [System.IO.Compression.CompressionLevel]::Optimal, $true)
    $writer = [System.Formats.Tar.TarWriter]::new($gzip, [System.Formats.Tar.TarEntryFormat]::Pax, $true)
    try {
        foreach ($file in ([ordered]@{ 'package/package.json' = $utf8.GetBytes((@{ name = $Name; version = $Version } | ConvertTo-Json -Compress)); 'package/Runtime/content.bin' = [byte[]] @(0, 1, 2, 255) }).GetEnumerator()) {
            $entry = [System.Formats.Tar.PaxTarEntry]::new([System.Formats.Tar.TarEntryType]::RegularFile, [string] $file.Key)
            $data = [System.IO.MemoryStream]::new([byte[]] $file.Value, $false)
            try { $entry.DataStream = $data; $writer.WriteEntry($entry) }
            finally { $data.Dispose() }
        }
    }
    finally { $writer.Dispose(); $gzip.Dispose() }
    try { return $archive.ToArray() }
    finally { $archive.Dispose() }
}
function New-RegistryCacheFixture {
    param([switch] $MissingEntry, [switch] $WrongVersion, [switch] $MissingContent, [switch] $TamperContent, [switch] $WrongIdentity)
    $root = [System.IO.Path]::Combine($fixtureRoot, "r-$([guid]::NewGuid().ToString('N').Substring(0, 8))")
    $project = [System.IO.Path]::Combine($root, 'project'); $cache = [System.IO.Path]::Combine($root, 'cache')
    $name = 'com.unity.fixture'; $version = '1.2.3'; $cachedVersion = if ($WrongVersion) { '9.9.9' } else { $version }
    $lock = @{ dependencies = @{ $name = @{ version = $version; depth = 0; source = 'registry'; url = 'https://packages.unity.com' }; 'com.unity.modules.ui' = @{ version = '1.0.0'; depth = 0; source = 'builtin' } } }
    Write-TestFileBytes ([System.IO.Path]::Combine($project, 'Packages', 'packages-lock.json')) $utf8.GetBytes(($lock | ConvertTo-Json -Depth 20))
    $indexRoot = [System.IO.Path]::Combine($cache, 'upm', 'db', 'index-v5'); $contentRoot = [System.IO.Path]::Combine($cache, 'upm', 'db', 'content-v2')
    $null = [System.IO.Directory]::CreateDirectory($indexRoot); $null = [System.IO.Directory]::CreateDirectory($contentRoot)
    if (-not $MissingEntry) {
        [byte[]] $archive = New-TestRegistryPackageArchive -Name $(if ($WrongIdentity) { 'com.unity.wrong' } else { $name }) -Version $cachedVersion
        [byte[]] $digest = [System.Security.Cryptography.SHA1]::HashData($archive); $digestHex = [System.Convert]::ToHexString($digest).ToLowerInvariant()
        $key = "package-tarball|$name|$cachedVersion|$digestHex"
        $record = [ordered]@{ key = $key; integrity = "sha1-$([System.Convert]::ToBase64String($digest))"; time = 1; size = $archive.LongLength }
        $json = $record | ConvertTo-Json -Compress; $recordHash = [System.Convert]::ToHexString([System.Security.Cryptography.SHA1]::HashData($utf8.GetBytes($json))).ToLowerInvariant()
        $indexHash = [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($utf8.GetBytes($key))).ToLowerInvariant()
        $indexPath = [System.IO.Path]::Combine($indexRoot, $indexHash.Substring(0, 2), $indexHash.Substring(2, 2), $indexHash.Substring(4))
        Write-TestFileBytes $indexPath $utf8.GetBytes("`n$recordHash`t$json`n")
        $contentPath = [System.IO.Path]::Combine($contentRoot, 'sha1', $digestHex.Substring(0, 2), $digestHex.Substring(2, 2), $digestHex.Substring(4))
        if (-not $MissingContent) { Write-TestFileBytes $contentPath $(if ($TamperContent) { [byte[]] @($archive + 7) } else { $archive }) }
    }
    return [pscustomobject]@{ ProjectRoot = $project; CacheRoot = $cache; Name = $name; Version = $version }
}
function New-ObservationFixture {
    param([hashtable] $Baseline = @{ 'Assets/a.bin' = [byte[]] @(1, 2, 3); 'Packages/packages-lock.json' = [byte[]] @(4, 5, 6) })
    $workspace = New-SpecOpsUnityWorkspace
    $ownedWorkspaces.Add($workspace)
    $entries = [System.Collections.Generic.List[object]]::new()
    $blobs = [System.Collections.Generic.Dictionary[string, byte[]]]::new([System.StringComparer]::Ordinal)
    foreach ($path in $Baseline.Keys) { $entries.Add((New-TestEntry $path)); $blobs.Add($path, [byte[]] $Baseline[$path]) }
    $reader = { param($ignored, $path) return $blobs[$path] }.GetNewClosure()
    $materialization = New-SpecOpsUnitySubjectMaterialization (New-TestSnapshot @($entries)) $reader $workspace
    $resultsPath = [System.IO.Path]::Combine($workspace.OutputRoot, 'results.xml')
    $logPath = [System.IO.Path]::Combine($workspace.OutputRoot, 'unity.log')
    Write-TestFileBytes $resultsPath $utf8.GetBytes((New-NUnit3Xml))
    Write-TestFileBytes $logPath $utf8.GetBytes($successCompilationLog)
    return [pscustomobject]@{ Workspace = $workspace; Materialization = $materialization; ResultsPath = $resultsPath; LogPath = $logPath }
}
function Invoke-ObservationCore {
    param(
        $Fixture,
        [string] $TracePath = '',
        [object[]] $ExternalTargets = @(),
        [scriptblock] $FileReader,
        [scriptblock] $Cleanup,
        [scriptblock] $FileExists,
        [int] $Timeout = 1000,
        [int] $StableInterval = 1
    )
    if ($null -eq $FileReader) { $FileReader = { param($path) [System.IO.File]::ReadAllBytes($path) } }
    if ($null -eq $Cleanup) { $Cleanup = { param($workspace) [pscustomobject]@{ Removed = $true; Root = $workspace.Root } } }
    if ($null -eq $FileExists) { $FileExists = { param($path) [System.IO.File]::Exists($path) } }
    return & $module {
        param($f, $required, $trace, $external, $timeout, $interval, $read, $cleanup, $exists)
        Invoke-SpecOpsUnityObservationLifecycleCore -Workspace $f.Workspace -Materialization $f.Materialization -ResultsPath $f.ResultsPath -LogPath $f.LogPath -TracePath $trace -RequiredTestFullNames $required -ExternalTargets $external -QuiescenceTimeoutMilliseconds $timeout -StableIntervalMilliseconds $interval -ReadFileBytes $read -CleanupWorkspace $cleanup -FileExists $exists
    } $Fixture $requiredTests $TracePath $ExternalTargets $Timeout $StableInterval $FileReader $Cleanup $FileExists
}

$fixtureRoot = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "sot-$([guid]::NewGuid().ToString('N').Substring(0, 8))")
$null = [System.IO.Directory]::CreateDirectory($fixtureRoot)
$ownedWorkspaces = [System.Collections.Generic.List[object]]::new()
$evalPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, '..', '..', '..', '.specops', 'evals', 'unity-editmode-validation.eval.json'))
$evalDefinition = Get-Content -Raw -LiteralPath $evalPath | ConvertFrom-Json
$requiredTests = [string[]] @(($evalDefinition.checks | Where-Object { $_.id -ceq 'editmode-required-tests-discovered' }).passCondition.value.requiredItems)
try {
    Test-Case 'NUnit3 valid exact 14 of 14 Passed result parsed' {
        $result = Read-TestNUnit3 (New-NUnit3Xml)
        Assert-Equal 14 $result.Counts.Total 'Observed total mismatch.'
        Assert-Equal 14 $result.Counts.Passed 'Passed count mismatch.'
        Assert-Equal 0 $result.Counts.Failed 'Failed count mismatch.'
        Assert-Equal 0 $result.Counts.Inconclusive 'Inconclusive count mismatch.'
        Assert-Equal 0 $result.Counts.NotExecuted 'Not-executed count mismatch.'
        Assert-Equal 14 @($result.TestCases).Count 'Test observation count mismatch.'
        $expectedNames = [string[]] @($requiredTests)
        [System.Array]::Sort($expectedNames, [System.StringComparer]::Ordinal)
        Assert-Equal ([string]::Join([char] 0, $expectedNames)) ([string]::Join([char] 0, $result.FullyQualifiedTestNames)) 'Exact fullname inventory or ordinal order changed.'
    }
    Test-Case 'NUnit3 one failed test retained without eval decision' {
        $failedName = $requiredTests[0]
        $result = Read-TestNUnit3 (New-NUnit3Xml -ResultOverrides @{ $failedName = [pscustomobject]@{ Result = 'Failed'; Label = 'Error'; RunState = 'Runnable' } })
        Assert-Equal 1 $result.Counts.Failed 'Failed count mismatch.'
        $test = $result.TestCases | Where-Object { $_.FullName -ceq $failedName }
        Assert-Equal 'Failed' $test.Result 'Failed result was normalized incorrectly.'
        Assert-Equal 'Error' $test.Label 'Failure label was not retained.'
        Assert-True $test.Executed 'Failed test was not marked executed.'
    }
    Test-Case 'NUnit3 one inconclusive test retained' {
        $name = $requiredTests[1]
        $result = Read-TestNUnit3 (New-NUnit3Xml -ResultOverrides @{ $name = [pscustomobject]@{ Result = 'Inconclusive'; Label = 'Inconclusive' } })
        Assert-Equal 1 $result.Counts.Inconclusive 'Inconclusive count mismatch.'
        Assert-Equal 'Inconclusive' (($result.TestCases | Where-Object { $_.FullName -ceq $name }).Result) 'Inconclusive state changed.'
    }
    Test-Case 'NUnit3 skipped not-executed representation retained' {
        $name = $requiredTests[2]
        $result = Read-TestNUnit3 (New-NUnit3Xml -ResultOverrides @{ $name = [pscustomobject]@{ Result = 'Skipped'; Label = 'Ignored'; RunState = 'Ignored' } })
        $test = $result.TestCases | Where-Object { $_.FullName -ceq $name }
        Assert-Equal 1 $result.Counts.Skipped 'Skipped count mismatch.'
        Assert-Equal 1 $result.Counts.NotExecuted 'Not-executed count mismatch.'
        Assert-Equal 'Ignored' $test.RunState 'Run state was not retained.'
        Assert-False $test.Executed 'Skipped test was marked executed.'
    }
    Test-Case 'NUnit3 missing required test rejected' { Assert-Rejected { Read-TestNUnit3 (New-NUnit3Xml -TestNames $requiredTests[0..12]) } 'UNITY_NUNIT_REQUIRED_TEST_MISSING' }
    Test-Case 'NUnit3 unexpected extra test rejected' { Assert-Rejected { Read-TestNUnit3 (New-NUnit3Xml -TestNames @($requiredTests + 'InfiniteMonkey.EditModeTests.Unexpected.Extra')) } 'UNITY_NUNIT_TEST_UNEXPECTED' }
    Test-Case 'NUnit3 empty required inventory rejected' { Assert-Rejected { Read-SpecOpsUnityNUnit3Result -Bytes $utf8.GetBytes((New-NUnit3Xml)) -RequiredTestFullNames ([string[]] @()) } 'UNITY_NUNIT_REQUIRED_TESTS_INVALID' }
    Test-Case 'NUnit3 whitespace-only required identity rejected' { Assert-Rejected { Read-SpecOpsUnityNUnit3Result -Bytes $utf8.GetBytes((New-NUnit3Xml)) -RequiredTestFullNames ([string[]] @(' ')) } 'UNITY_NUNIT_REQUIRED_TESTS_INVALID' }
    Test-Case 'NUnit3 duplicate fullname rejected' { Assert-Rejected { Read-TestNUnit3 (New-NUnit3Xml -TestNames @($requiredTests + $requiredTests[0])) } 'UNITY_NUNIT_TEST_IDENTITY_DUPLICATE' }
    Test-Case 'NUnit3 missing fullname rejected' { Assert-Rejected { Read-TestNUnit3 (New-NUnit3Xml -MissingFullNameIndex 0) } 'UNITY_NUNIT_TEST_IDENTITY_INVALID' }
    Test-Case 'NUnit3 wrong assembly rejected' { Assert-Rejected { Read-TestNUnit3 (New-NUnit3Xml -AssemblyName 'Wrong.EditModeTests.dll') } 'UNITY_NUNIT_ASSEMBLY_NOT_FOUND' }
    Test-Case 'NUnit3 duplicate matching assembly rejected' { Assert-Rejected { Read-TestNUnit3 (New-NUnit3Xml -DuplicateAssembly) } 'UNITY_NUNIT_ASSEMBLY_AMBIGUOUS' }
    Test-Case 'NUnit3 wrong root rejected' { Assert-Rejected { Read-TestNUnit3 ((New-NUnit3Xml).Replace('<test-run ', '<wrong-root ').Replace('</test-run>', '</wrong-root>')) } 'UNITY_NUNIT_ROOT_INVALID' }
    Test-Case 'NUnit3 malformed XML rejected deterministically' { Assert-Rejected { Read-TestNUnit3 '<test-run><broken></test-run>' } 'UNITY_NUNIT_XML_INVALID' }
    Test-Case 'NUnit3 empty and non-XML input rejected deterministically' { Assert-Rejected { Read-SpecOpsUnityNUnit3Result -Bytes ([byte[]] @()) -RequiredTestFullNames $requiredTests } 'UNITY_NUNIT_XML_INVALID'; Assert-Rejected { Read-TestNUnit3 'not xml' } 'UNITY_NUNIT_XML_INVALID' }
    Test-Case 'NUnit3 DTD entity attempt rejected without resolution' {
        $xml = '<!DOCTYPE test-run [<!ENTITY external SYSTEM "https://invalid.example/specops">]><test-run><test-suite type="Assembly" name="InfiniteMonkey.EditModeTests.dll">&external;</test-suite></test-run>'
        Assert-Rejected { Read-TestNUnit3 $xml } 'UNITY_NUNIT_XML_INVALID'
    }
    Test-Case 'NUnit3 declared count mismatch rejected' { Assert-Rejected { Read-TestNUnit3 (New-NUnit3Xml -RootCountOverrides @{ total = 15 }) } 'UNITY_NUNIT_COUNT_MISMATCH' }
    Test-Case 'NUnit3 unknown result state rejected' { $name = $requiredTests[0]; Assert-Rejected { Read-TestNUnit3 (New-NUnit3Xml -ResultOverrides @{ $name = [pscustomobject]@{ Result = 'UnknownState' } }) } 'UNITY_NUNIT_RESULT_UNSUPPORTED' }
    Test-Case 'NUnit3 absolute assembly fullname does not affect identity' {
        $absolute = 'D:\agents\different-machine\Library\ScriptAssemblies\InfiniteMonkey.EditModeTests.dll'
        $result = Read-TestNUnit3 (New-NUnit3Xml -AssemblyFullName $absolute)
        Assert-Equal 'InfiniteMonkey.EditModeTests.dll' $result.AssemblyFileName 'Assembly filename identity mismatch.'
        Assert-Equal $absolute $result.AssemblyFullName 'Assembly diagnostic fullname was not retained.'
    }

    Test-Case 'ProjectVersion valid current form' {
        $requirement = Read-SpecOpsUnityProjectVersionRequirement -Bytes (Get-VersionBytes)
        Assert-Equal '6000.5.8f1' $requirement.EditorVersion 'Version mismatch.'
        Assert-Equal '5cb7df797b7d' $requirement.EditorRevision 'Revision mismatch.'
        Assert-Equal 'parenthesized-revision-suffix' $requirement.ExtractionOperation 'Extraction operation mismatch.'
        Assert-Equal 'substring-before-space-open-parenthesis' $requirement.VersionResult 'Version extraction mismatch.'
        Assert-Equal 'content-inside-parentheses' $requirement.RevisionResult 'Revision extraction mismatch.'
    }
    Test-Case 'ProjectVersion missing version rejected' { Assert-Rejected { Read-SpecOpsUnityProjectVersionRequirement -Bytes $utf8.GetBytes("m_EditorVersionWithRevision: 6000.5.8f1 (5cb7df797b7d)`n") } 'UNITY_PROJECT_VERSION_MISSING_FIELD' }
    Test-Case 'ProjectVersion missing revision field rejected' { Assert-Rejected { Read-SpecOpsUnityProjectVersionRequirement -Bytes $utf8.GetBytes("m_EditorVersion: 6000.5.8f1`n") } 'UNITY_PROJECT_VERSION_MISSING_FIELD' }
    Test-Case 'ProjectVersion field disagreement rejected' { Assert-Rejected { Read-SpecOpsUnityProjectVersionRequirement -Bytes (Get-VersionBytes -Combined '6000.5.7f1 (5cb7df797b7d)') } 'UNITY_PROJECT_VERSION_INCONSISTENT' }
    Test-Case 'ProjectVersion malformed parentheses rejected' { Assert-Rejected { Read-SpecOpsUnityProjectVersionRequirement -Bytes (Get-VersionBytes -Combined '6000.5.8f1 5cb7df797b7d') } 'UNITY_PROJECT_VERSION_INVALID' }
    Test-Case 'ProjectVersion duplicate version rejected' { Assert-Rejected { Read-SpecOpsUnityProjectVersionRequirement -Bytes (Get-VersionBytes -Extra @('m_EditorVersion: 6000.5.8f1')) } 'UNITY_PROJECT_VERSION_DUPLICATE_FIELD' }
    Test-Case 'ProjectVersion duplicate combined field rejected' { Assert-Rejected { Read-SpecOpsUnityProjectVersionRequirement -Bytes (Get-VersionBytes -Extra @('m_EditorVersionWithRevision: 6000.5.8f1 (5cb7df797b7d)')) } 'UNITY_PROJECT_VERSION_DUPLICATE_FIELD' }
    Test-Case 'ProjectVersion BOM rejected' { Assert-Rejected { Read-SpecOpsUnityProjectVersionRequirement -Bytes ([byte[]] @(0xEF, 0xBB, 0xBF) + (Get-VersionBytes)) } 'UNITY_PROJECT_VERSION_INVALID' }

    Test-Case 'ProductVersion matching metadata parsed' {
        $metadata = ConvertFrom-SpecOpsUnityProductVersion '6000.5.8f1_5cb7df797b7d'
        Assert-Equal '6000.5.8f1' $metadata.EditorVersion 'Product version component mismatch.'
        Assert-Equal '5cb7df797b7d' $metadata.EditorRevision 'Product revision component mismatch.'
    }
    Test-Case 'ProductVersion malformed rejected' { Assert-Rejected { ConvertFrom-SpecOpsUnityProductVersion '6000.5.8f1 (5cb7df797b7d)' } 'UNITY_EXECUTABLE_METADATA_INVALID' }
    Test-Case 'ProductVersion extra separator rejected' { Assert-Rejected { ConvertFrom-SpecOpsUnityProductVersion '6000.5.8f1_5cb7df797b7d_extra' } 'UNITY_EXECUTABLE_METADATA_INVALID' }
    Test-Case 'Executable metadata relative path rejected' { Assert-Rejected { Get-SpecOpsUnityExecutableMetadata 'Unity.exe' } 'UNITY_EXECUTABLE_PATH_INVALID' }
    Test-Case 'Executable metadata missing path rejected' { Assert-Rejected { Get-SpecOpsUnityExecutableMetadata ([System.IO.Path]::Combine($fixtureRoot, 'missing.exe')) } 'UNITY_EXECUTABLE_NOT_FOUND' }

    $requirement = Read-SpecOpsUnityProjectVersionRequirement -Bytes (Get-VersionBytes)
    $hubOne = [System.IO.Path]::Combine($fixtureRoot, 'hub-one')
    $hubTwo = [System.IO.Path]::Combine($fixtureRoot, 'hub-two')
    $matchOne = New-TestHubCandidate $hubOne '6000.5.8f1'
    $matchTwo = New-TestHubCandidate $hubTwo 'also-6000.5.8f1'
    $mismatch = New-TestHubCandidate $hubOne '6000.4.0f1'
    $metadataMap = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $metadataMap[$matchOne] = [pscustomobject]@{ Path = $matchOne; EditorVersion = '6000.5.8f1'; EditorRevision = '5cb7df797b7d'; ProductVersion = '6000.5.8f1_5cb7df797b7d' }
    $metadataMap[$matchTwo] = [pscustomobject]@{ Path = $matchTwo; EditorVersion = '6000.5.8f1'; EditorRevision = '5cb7df797b7d'; ProductVersion = '6000.5.8f1_5cb7df797b7d' }
    $metadataMap[$mismatch] = [pscustomobject]@{ Path = $mismatch; EditorVersion = '6000.4.0f1'; EditorRevision = 'different'; ProductVersion = '6000.4.0f1_different' }
    $inspector = { param($path) if (-not $metadataMap.ContainsKey($path)) { throw 'Unknown test candidate.' }; return $metadataMap[$path] }.GetNewClosure()

    Test-Case 'Explicit candidate exact match selected alone' { $selected = Invoke-SelectionCore $requirement $matchOne @($hubTwo) $inspector; Assert-Equal 'explicit' $selected.SelectionMode 'Selection mode mismatch.'; Assert-Equal $matchOne $selected.Candidate.Path 'Explicit candidate mismatch.' }
    Test-Case 'Explicit candidate version mismatch rejected' { Assert-Rejected { Invoke-SelectionCore -Requirement $requirement -Explicit $mismatch -Roots ([string[]] @()) -Inspector $inspector } 'UNITY_EXECUTABLE_VERSION_MISMATCH' }
    Test-Case 'Explicit candidate revision mismatch rejected' {
        $revisionMap = { param($path) [pscustomobject]@{ Path = $path; EditorVersion = '6000.5.8f1'; EditorRevision = 'wrong' } }
        Assert-Rejected { Invoke-SelectionCore -Requirement $requirement -Explicit $matchOne -Roots ([string[]] @()) -Inspector $revisionMap } 'UNITY_EXECUTABLE_VERSION_MISMATCH'
    }
    Test-Case 'Automatic zero exact match rejected' { Assert-Rejected { Invoke-SelectionCore $requirement '' @([System.IO.Path]::Combine($fixtureRoot, 'absent-hub')) $inspector } 'UNITY_EXECUTABLE_CAPABILITY_UNAVAILABLE' }
    Test-Case 'Automatic one exact match selected' { $selected = Invoke-SelectionCore $requirement '' @($hubOne) $inspector; Assert-Equal 'automatic' $selected.SelectionMode 'Selection mode mismatch.'; Assert-Equal $matchOne $selected.Candidate.Path 'Automatic candidate mismatch.' }
    Test-Case 'Automatic multiple exact matches rejected' { Assert-Rejected { Invoke-SelectionCore $requirement '' @($hubOne, $hubTwo) $inspector } 'UNITY_EXECUTABLE_SELECTION_AMBIGUOUS' }
    Test-Case 'Automatic duplicate canonical root deduplicated' { $selected = Invoke-SelectionCore $requirement '' @($hubOne, [System.IO.Path]::Combine($hubOne, '.')) $inspector; Assert-Equal $matchOne $selected.Candidate.Path 'Canonical duplicate changed selection.' }
    Test-Case 'Automatic mismatched candidates ignored' { $selected = Invoke-SelectionCore $requirement '' @($hubOne) $inspector; Assert-Equal $matchOne $selected.Candidate.Path 'Mismatched candidate was selected.' }

    Test-Case 'Workspace roots are unique and OS-temporary' {
        $one = New-SpecOpsUnityWorkspace; $two = New-SpecOpsUnityWorkspace
        $ownedWorkspaces.Add($one); $ownedWorkspaces.Add($two)
        Assert-False ([string]::Equals($one.Root, $two.Root, [System.StringComparison]::OrdinalIgnoreCase)) 'Workspace roots were reused.'
        Assert-True ($one.Root.StartsWith([System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()), [System.StringComparison]::OrdinalIgnoreCase)) 'Workspace is outside OS temp.'
    }
    Test-Case 'Workspace guarded cleanup succeeds' {
        $workspace = New-SpecOpsUnityWorkspace
        $result = Remove-SpecOpsUnityWorkspace $workspace
        Assert-True $result.Removed 'Workspace was not reported removed.'
        Assert-False ([System.IO.Directory]::Exists($workspace.Root)) 'Workspace still exists.'
    }
    Test-Case 'Workspace arbitrary cleanup rejected' {
        $fake = [pscustomobject]@{ OwnerId = 'not-owned'; Root = (Get-Location).Path; SubjectRoot = (Get-Location).Path; OutputRoot = (Get-Location).Path; OwnershipMarker = [System.IO.Path]::Combine((Get-Location).Path, '.not-present') }
        Assert-Rejected { Remove-SpecOpsUnityWorkspace $fake } 'UNITY_WORKSPACE_NOT_OWNED'
    }
    Test-Case 'Workspace tampered ownership marker rejected' {
        $workspace = New-SpecOpsUnityWorkspace
        [System.IO.File]::WriteAllText($workspace.OwnershipMarker, 'wrong-owner', $utf8)
        Assert-Rejected { Remove-SpecOpsUnityWorkspace $workspace } 'UNITY_WORKSPACE_NOT_OWNED'
        [System.IO.File]::WriteAllText($workspace.OwnershipMarker, $workspace.OwnerId, $utf8)
        $null = Remove-SpecOpsUnityWorkspace $workspace
    }

    Test-Case 'Materialization preserves binary and Unicode paths in ordinal order' {
        $workspace = New-SpecOpsUnityWorkspace; $ownedWorkspaces.Add($workspace)
        $blobMap = [System.Collections.Generic.Dictionary[string, byte[]]]::new([System.StringComparer]::Ordinal)
        $blobMap['z.bin'] = [byte[]] @(0, 1, 2, 10, 13, 255)
        $blobMap['Assets/space and-é.txt'] = $utf8.GetBytes('héllo')
        $snapshot = New-TestSnapshot @((New-TestEntry 'z.bin' -Mode '100755'), (New-TestEntry 'Assets/space and-é.txt'))
        $reader = { param($ignored, $path) return $blobMap[$path] }.GetNewClosure()
        $materialized = New-SpecOpsUnitySubjectMaterialization $snapshot $reader $workspace
        Assert-Equal 2 $materialized.EntryCount 'Entry count mismatch.'
        Assert-Equal 'Assets/space and-é.txt' $materialized.Manifest[0].Path 'Manifest order is not ordinal.'
        Assert-Equal 'z.bin' $materialized.Manifest[1].Path 'Manifest order is not ordinal.'
        Assert-Bytes $blobMap['z.bin'] ([System.IO.File]::ReadAllBytes([System.IO.Path]::Combine($materialized.ProjectRoot, 'z.bin'))) 'Binary bytes changed.'
        Assert-Bytes $blobMap['Assets/space and-é.txt'] $materialized.Manifest[0].ComparisonBytes 'Comparison basis changed.'
        Assert-Equal $blobMap['z.bin'].Length $materialized.Manifest[1].ByteLength 'Byte length mismatch.'
        Assert-False ($materialized.ProjectRoot.StartsWith((Get-Location).Path, [System.StringComparison]::OrdinalIgnoreCase)) 'Materialization occurred under repository root.'
    }
    Test-Case 'Materialization traversal rejected' { $workspace = New-SpecOpsUnityWorkspace; $ownedWorkspaces.Add($workspace); Assert-Rejected { New-SpecOpsUnitySubjectMaterialization (New-TestSnapshot @((New-TestEntry '../escape'))) { [byte[]] @(1) } $workspace } 'UNITY_SUBJECT_PATH_INVALID' }
    Test-Case 'Materialization rooted path rejected' { $workspace = New-SpecOpsUnityWorkspace; $ownedWorkspaces.Add($workspace); Assert-Rejected { New-SpecOpsUnitySubjectMaterialization (New-TestSnapshot @((New-TestEntry 'C:/escape'))) { [byte[]] @(1) } $workspace } 'UNITY_SUBJECT_PATH_INVALID' }
    Test-Case 'Materialization unsupported entry type rejected' { $workspace = New-SpecOpsUnityWorkspace; $ownedWorkspaces.Add($workspace); Assert-Rejected { New-SpecOpsUnitySubjectMaterialization (New-TestSnapshot @((New-TestEntry 'submodule' -Type 'commit' -Mode '160000'))) { [byte[]] @(1) } $workspace } 'UNITY_SUBJECT_ENTRY_UNSUPPORTED' }
    Test-Case 'Materialization unsupported entry mode rejected' { $workspace = New-SpecOpsUnityWorkspace; $ownedWorkspaces.Add($workspace); Assert-Rejected { New-SpecOpsUnitySubjectMaterialization (New-TestSnapshot @((New-TestEntry 'link' -Mode '120000'))) { [byte[]] @(1) } $workspace } 'UNITY_SUBJECT_ENTRY_UNSUPPORTED' }
    Test-Case 'Materialization case collision rejected' { $workspace = New-SpecOpsUnityWorkspace; $ownedWorkspaces.Add($workspace); Assert-Rejected { New-SpecOpsUnitySubjectMaterialization (New-TestSnapshot @((New-TestEntry 'A.txt'), (New-TestEntry 'a.txt'))) { [byte[]] @(1) } $workspace } 'UNITY_SUBJECT_PATH_COLLISION' }
    Test-Case 'Materialization file-directory collision rejected' { $workspace = New-SpecOpsUnityWorkspace; $ownedWorkspaces.Add($workspace); Assert-Rejected { New-SpecOpsUnitySubjectMaterialization (New-TestSnapshot @((New-TestEntry 'node'), (New-TestEntry 'node/child.txt'))) { [byte[]] @(1) } $workspace } 'UNITY_SUBJECT_PATH_COLLISION' }
    foreach ($reservedPath in @('NUL', 'nul.txt', 'CON', 'COM1.cs', 'LPT9.meta', 'nested/CLOCK$.txt', 'CONIN$', 'CONOUT$.log')) {
        Test-Case "Materialization rejects reserved Windows path $reservedPath" {
            $workspace = New-SpecOpsUnityWorkspace; $ownedWorkspaces.Add($workspace)
            Assert-Rejected { New-SpecOpsUnitySubjectMaterialization (New-TestSnapshot @((New-TestEntry $reservedPath))) { [byte[]] @(1) } $workspace } 'UNITY_SUBJECT_PATH_UNREPRESENTABLE'
        }
    }
    Test-Case 'Materialization rejects host-invalid filename character' {
        $workspace = New-SpecOpsUnityWorkspace; $ownedWorkspaces.Add($workspace)
        Assert-Rejected { New-SpecOpsUnitySubjectMaterialization (New-TestSnapshot @((New-TestEntry 'Assets/bad?name.txt'))) { [byte[]] @(1) } $workspace } 'UNITY_SUBJECT_PATH_UNREPRESENTABLE'
    }
    Test-Case 'Materialization rejects control character in path segment' {
        $workspace = New-SpecOpsUnityWorkspace; $ownedWorkspaces.Add($workspace)
        $unsafePath = 'Assets/bad' + [char] 1 + 'name.txt'
        Assert-Rejected { New-SpecOpsUnitySubjectMaterialization (New-TestSnapshot @((New-TestEntry $unsafePath))) { [byte[]] @(1) } $workspace } 'UNITY_SUBJECT_PATH_UNREPRESENTABLE'
    }
    Test-Case 'Materialization accepts nearby ordinary Windows filename' {
        $workspace = New-SpecOpsUnityWorkspace; $ownedWorkspaces.Add($workspace)
        $materialized = New-SpecOpsUnitySubjectMaterialization (New-TestSnapshot @((New-TestEntry 'Assets/NULish.txt'))) { [byte[]] @(7, 8, 9) } $workspace
        Assert-Equal 'Assets/NULish.txt' $materialized.Manifest[0].Path 'Ordinary filename identity changed.'
        Assert-Bytes ([byte[]] @(7, 8, 9)) ([System.IO.File]::ReadAllBytes([System.IO.Path]::Combine($materialized.ProjectRoot, 'Assets', 'NULish.txt'))) 'Ordinary filename bytes changed.'
    }

    Test-Case 'Compilation success is derived from standard Unity log completion evidence' {
        $result = Read-SpecOpsUnityCompilationObservation -Bytes $utf8.GetBytes("warning CS0219: diagnostic only`n$successCompilationLog")
        Assert-True $result.Completed 'Compilation completion evidence was not recognized.'
        Assert-Equal 0 $result.Errors 'Warning was treated as a compilation error.'
        Assert-True ($null -eq $result.Warnings) 'Unresolved warning count was fabricated.'
        Assert-Equal 'unity.log' $result.Source 'Compilation fact source changed.'
    }
    Test-Case 'Compilation failure is derived from standard Unity log error evidence' {
        $log = "Assets\Project\Bad.cs(12,7): error CS1002: ; expected`nScripts have compiler errors.`n$successCompilationLog"
        $result = Read-SpecOpsUnityCompilationObservation -Bytes $utf8.GetBytes($log)
        Assert-True $result.Completed 'Failed compilation completion was not established.'
        Assert-Equal 1 $result.Errors 'Compiler error evidence was not retained.'
    }
    Test-Case 'Compilation without positive completion evidence remains incomplete' {
        $result = Read-SpecOpsUnityCompilationObservation -Bytes $utf8.GetBytes('Test run completed.')
        Assert-False $result.Completed 'Compilation completion was fabricated.'
        Assert-Equal 0 $result.Errors 'Compiler errors were fabricated.'
    }
    Test-Case 'Exact offline git-package capability is validated and seeded without acquisition' {
        $fixture = New-OfflineCapabilityFixture
        $result = @(Initialize-SpecOpsUnityOfflinePackageCapability -ProjectRoot $fixture.ProjectRoot -CapabilityRoot $fixture.CapabilityRoot)
        Assert-Equal 1 $result.Count 'Capability observation count mismatch.'
        Assert-Equal $fixture.PackageName $result[0].PackageName 'Package identity changed.'
        Assert-Equal $fixture.Commit $result[0].LockedCommit 'Locked commit changed.'
        $independentFingerprint = [System.Convert]::ToHexString([System.Security.Cryptography.SHA1]::HashData($utf8.GetBytes($fixture.Commit + $fixture.Subpath))).ToLowerInvariant()
        Assert-Equal $independentFingerprint $result[0].UpmFingerprint 'UPM fingerprint was not independently derived from subject authority.'
        Assert-False $result[0].NetworkAcquisitionAllowed 'Network acquisition was enabled.'
        $seedRoot = [System.IO.Path]::Combine($fixture.ProjectRoot, 'Library', 'PackageCache', "$($fixture.PackageName)@$($fixture.Fingerprint.Substring(0, 12))")
        $seed = [System.IO.Path]::Combine($seedRoot, 'Runtime', 'VContainer.cs')
        Assert-True ([System.IO.File]::Exists($seed)) 'Validated package was not seeded at Unity point of use.'
        Assert-Bytes ([byte[]] $fixture.SourceBytes['Runtime/VContainer.cs']) ([System.IO.File]::ReadAllBytes($seed)) 'Non-package.json seed bytes changed.'
        $sourceMetadata = $utf8.GetString([byte[]] $fixture.SourceBytes['package.json']) | ConvertFrom-Json -AsHashtable
        $seedPackagePath = [System.IO.Path]::Combine($seedRoot, 'package.json'); $seedMetadata = Get-Content -Raw -LiteralPath $seedPackagePath | ConvertFrom-Json -AsHashtable
        Assert-Equal $fixture.Fingerprint $seedMetadata['_fingerprint'] 'Generated package fingerprint mismatch.'
        $null = $seedMetadata.Remove('_fingerprint')
        Assert-Equal ($sourceMetadata | ConvertTo-Json -Compress) ($seedMetadata | ConvertTo-Json -Compress) 'Generated package metadata changed beyond fingerprint augmentation.'
    }
    Test-Case 'Wrong capability-manifest UPM fingerprint rejects' { $fixture = New-OfflineCapabilityFixture -WrongFingerprint; Assert-Rejected { Initialize-SpecOpsUnityOfflinePackageCapability -ProjectRoot $fixture.ProjectRoot -CapabilityRoot $fixture.CapabilityRoot } 'UNITY_PACKAGE_CAPABILITY_INVALID' }
    Test-Case 'Fabricated package subtree object rejects against real commit chain' { $fixture = New-OfflineCapabilityFixture -FakeTree; Assert-Rejected { Initialize-SpecOpsUnityOfflinePackageCapability -ProjectRoot $fixture.ProjectRoot -CapabilityRoot $fixture.CapabilityRoot } 'UNITY_PACKAGE_CAPABILITY_REVISION_INVALID' }
    Test-Case 'Missing offline git-package capability fails closed' {
        $fixture = New-OfflineCapabilityFixture
        Assert-Rejected { Initialize-SpecOpsUnityOfflinePackageCapability -ProjectRoot $fixture.ProjectRoot -CapabilityRoot ([System.IO.Path]::Combine($fixtureRoot, 'missing-capabilities')) } 'UNITY_PACKAGE_CAPABILITY_MISSING'
        Assert-False ([System.IO.Directory]::Exists([System.IO.Path]::Combine($fixture.ProjectRoot, 'Library'))) 'Invalid execution acquired or seeded package state.'
    }
    Test-Case 'Invalid offline git-package bytes fail point-of-use validation' {
        $fixture = New-OfflineCapabilityFixture -CorruptSource
        Assert-Rejected { Initialize-SpecOpsUnityOfflinePackageCapability -ProjectRoot $fixture.ProjectRoot -CapabilityRoot $fixture.CapabilityRoot } 'UNITY_PACKAGE_CAPABILITY_INVALID'
        Assert-False ([System.IO.Directory]::Exists([System.IO.Path]::Combine($fixture.ProjectRoot, 'Library'))) 'Invalid capability reached package seeding.'
    }
    Test-Case 'Exact valid registry package standard-cache capability passes' {
        $fixture = New-RegistryCacheFixture
        $result = @(Get-SpecOpsUnityRegistryPackageCacheCapabilities -ProjectRoot $fixture.ProjectRoot -CacheRoot $fixture.CacheRoot)
        Assert-Equal 1 $result.Count 'Registry capability count mismatch.'; Assert-Equal $fixture.Name $result[0].PackageName 'Registry package name changed.'; Assert-Equal $fixture.Version $result[0].PackageVersion 'Registry package version changed.'
        Assert-True ([string] $result[0].Integrity -cmatch '^sha1-') 'Registry integrity observation missing.'
    }
    Test-Case 'Missing required registry cache entry rejects' { $fixture = New-RegistryCacheFixture -MissingEntry; Assert-Rejected { Get-SpecOpsUnityRegistryPackageCacheCapabilities -ProjectRoot $fixture.ProjectRoot -CacheRoot $fixture.CacheRoot } 'UNITY_REGISTRY_PACKAGE_CACHE_MISSING' }
    Test-Case 'Wrong registry cache version rejects' { $fixture = New-RegistryCacheFixture -WrongVersion; Assert-Rejected { Get-SpecOpsUnityRegistryPackageCacheCapabilities -ProjectRoot $fixture.ProjectRoot -CacheRoot $fixture.CacheRoot } 'UNITY_REGISTRY_PACKAGE_CACHE_MISSING' }
    Test-Case 'Missing registry cache content rejects' { $fixture = New-RegistryCacheFixture -MissingContent; Assert-Rejected { Get-SpecOpsUnityRegistryPackageCacheCapabilities -ProjectRoot $fixture.ProjectRoot -CacheRoot $fixture.CacheRoot } 'UNITY_REGISTRY_PACKAGE_CACHE_MISSING' }
    Test-Case 'Tampered registry archive integrity rejects' { $fixture = New-RegistryCacheFixture -TamperContent; Assert-Rejected { Get-SpecOpsUnityRegistryPackageCacheCapabilities -ProjectRoot $fixture.ProjectRoot -CacheRoot $fixture.CacheRoot } 'UNITY_REGISTRY_PACKAGE_CACHE_INVALID' }
    Test-Case 'Wrong embedded registry package identity rejects' { $fixture = New-RegistryCacheFixture -WrongIdentity; Assert-Rejected { Get-SpecOpsUnityRegistryPackageCacheCapabilities -ProjectRoot $fixture.ProjectRoot -CacheRoot $fixture.CacheRoot } 'UNITY_REGISTRY_PACKAGE_CACHE_INVALID' }

    Test-Case 'Observation capture completes before cleanup' {
        $fixture = New-ObservationFixture
        $state = [pscustomobject]@{ ResultReads = 0; LogReads = 0; CleanupCalls = 0 }
        $read = { param($path) if ($path -ceq $fixture.ResultsPath) { $state.ResultReads++ } elseif ($path -ceq $fixture.LogPath) { $state.LogReads++ }; [System.IO.File]::ReadAllBytes($path) }.GetNewClosure()
        $cleanup = { param($workspace) $state.CleanupCalls++; if ($state.ResultReads -lt 2 -or $state.LogReads -lt 2) { throw 'Cleanup preceded stable capture.' } }.GetNewClosure()
        $result = Invoke-ObservationCore $fixture -FileReader $read -Cleanup $cleanup
        Assert-Equal 1 $state.CleanupCalls 'Cleanup call count mismatch.'
        Assert-True $result.Cleanup.Succeeded 'Cleanup did not follow complete capture.'
        Assert-Equal 14 $result.Results.NUnit3.Counts.Total 'Normalized result was not retained.'
        Assert-True $result.Compilation.Completed 'Compilation completion was not retained from unity.log.'
        Assert-Equal 0 $result.Compilation.Errors 'Compilation error count mismatch.'
    }
    Test-Case 'Contracted results appearing after initial absence are retained and parsed' {
        $fixture = New-ObservationFixture; [byte[]] $expectedResults = [System.IO.File]::ReadAllBytes($fixture.ResultsPath); [System.IO.File]::Delete($fixture.ResultsPath)
        $state = [pscustomobject]@{ ResultExistenceChecks = 0 }
        $exists = {
            param($path)
            if ($path -ceq $fixture.ResultsPath) {
                $state.ResultExistenceChecks++
                if ($state.ResultExistenceChecks -eq 1) { return $false }
                if (-not [System.IO.File]::Exists($path)) { Write-TestFileBytes $path $expectedResults }
            }
            return [System.IO.File]::Exists($path)
        }.GetNewClosure()
        $result = Invoke-ObservationCore $fixture -FileExists $exists
        Assert-True ($state.ResultExistenceChecks -ge 3) 'Results did not traverse absent then stable observations.'
        Assert-True $result.Results.Exists 'Late contracted results remained absent.'
        Assert-Bytes $expectedResults $result.Results.Bytes 'Late contracted results bytes were discarded.'
        Assert-Equal 14 $result.Results.NUnit3.Counts.Total 'Late contracted results were not parsed.'
    }
    Test-Case 'Established compilation failure survives absent results and reaches cleanup' {
        $fixture = New-ObservationFixture; [System.IO.File]::Delete($fixture.ResultsPath)
        Write-TestFileBytes $fixture.LogPath $utf8.GetBytes("## Script Compilation Error for: Csc`nScripts have compiler errors.`n$successCompilationLog")
        $state = [pscustomobject]@{ CleanupCalls = 0 }
        $cleanup = { param($workspace) $state.CleanupCalls++ }.GetNewClosure()
        $result = Invoke-ObservationCore $fixture -Cleanup $cleanup
        Assert-True $result.Compilation.Completed 'Compilation completion was lost.'
        Assert-Equal 1 $result.Compilation.Errors 'Compilation failure was not retained.'
        Assert-False $result.Results.Exists 'Absent results were fabricated.'
        Assert-True ($null -eq $result.Results.NUnit3) 'NUnit facts were fabricated after compilation failure.'
        Assert-Equal 1 $state.CleanupCalls 'Observed compilation failure did not reach cleanup.'
    }
    Test-Case 'Missing contracted results rejects without cleanup and preserves workspace' {
        $fixture = New-ObservationFixture; [System.IO.File]::Delete($fixture.ResultsPath); $state = [pscustomobject]@{ CleanupCalls = 0 }
        $cleanup = { param($workspace) $state.CleanupCalls++ }.GetNewClosure()
        Assert-Rejected { Invoke-ObservationCore $fixture -Cleanup $cleanup -Timeout 10 } 'UNITY_OBSERVATION_OUTPUT_NOT_QUIESCENT'
        Assert-Equal 0 $state.CleanupCalls 'Cleanup ran after results capture failure.'
        Assert-True ([System.IO.Directory]::Exists($fixture.Workspace.Root)) 'Workspace was removed after capture failure.'
    }
    Test-Case 'Missing unity log rejects without cleanup' {
        $fixture = New-ObservationFixture; [System.IO.File]::Delete($fixture.LogPath); $state = [pscustomobject]@{ CleanupCalls = 0 }
        $cleanup = { param($workspace) $state.CleanupCalls++ }.GetNewClosure()
        Assert-Rejected { Invoke-ObservationCore $fixture -Cleanup $cleanup -Timeout 10 } 'UNITY_OBSERVATION_OUTPUT_NOT_QUIESCENT'
        Assert-Equal 0 $state.CleanupCalls 'Cleanup ran after log capture failure.'
    }
    Test-Case 'Unreadable unity log rejects without cleanup' {
        $fixture = New-ObservationFixture; $state = [pscustomobject]@{ CleanupCalls = 0 }
        $read = { param($path) if ($path -ceq $fixture.LogPath) { throw 'sharing violation' }; [System.IO.File]::ReadAllBytes($path) }.GetNewClosure()
        $cleanup = { param($workspace) $state.CleanupCalls++ }.GetNewClosure()
        Assert-Rejected { Invoke-ObservationCore $fixture -FileReader $read -Cleanup $cleanup -Timeout 10 } 'UNITY_OBSERVATION_OUTPUT_NOT_QUIESCENT'
        Assert-Equal 0 $state.CleanupCalls 'Cleanup ran after unreadable log capture failure.'
    }
    Test-Case 'Temporarily unavailable and unstable output becomes stable before cleanup' {
        $fixture = New-ObservationFixture; $state = [pscustomobject]@{ LogReads = 0; CleanupCalls = 0 }
        $responses = [System.Collections.Generic.Queue[object]]::new()
        $responses.Enqueue([System.IO.IOException]::new('held')); $responses.Enqueue($utf8.GetBytes('partial')); $responses.Enqueue($utf8.GetBytes($successCompilationLog)); $responses.Enqueue($utf8.GetBytes($successCompilationLog))
        $read = { param($path) if ($path -ceq $fixture.LogPath) { $state.LogReads++; $response = if ($responses.Count -gt 0) { $responses.Dequeue() } else { $utf8.GetBytes($successCompilationLog) }; if ($response -is [System.Exception]) { throw $response }; return [byte[]] $response }; [System.IO.File]::ReadAllBytes($path) }.GetNewClosure()
        $cleanup = { param($workspace) $state.CleanupCalls++; if ($responses.Count -ne 0) { throw 'Cleanup preceded stable log.' } }.GetNewClosure()
        $result = Invoke-ObservationCore $fixture -FileReader $read -Cleanup $cleanup -Timeout 2000
        Assert-Bytes $utf8.GetBytes($successCompilationLog) $result.Log.Bytes 'Stable log bytes mismatch.'
        Assert-Equal 1 $state.CleanupCalls 'Cleanup did not run exactly once.'
        Assert-True $result.Cleanup.Succeeded 'Cleanup failed after eventual quiescence.'
    }
    Test-Case 'Malformed contracted XML preserves parser rejection and prevents cleanup' {
        $fixture = New-ObservationFixture; Write-TestFileBytes $fixture.ResultsPath $utf8.GetBytes('<test-run><broken></test-run>'); $state = [pscustomobject]@{ CleanupCalls = 0 }
        $cleanup = { param($workspace) $state.CleanupCalls++ }.GetNewClosure()
        Assert-Rejected { Invoke-ObservationCore $fixture -Cleanup $cleanup } 'UNITY_NUNIT_XML_INVALID'
        Assert-Equal 0 $state.CleanupCalls 'Cleanup ran after NUnit parser rejection.'
    }
    Test-Case 'Present trace exact bytes captured' {
        $fixture = New-ObservationFixture; $tracePath = [System.IO.Path]::Combine($fixture.Workspace.OutputRoot, 'trace.log'); $traceBytes = [byte[]] @(0, 10, 13, 255); Write-TestFileBytes $tracePath $traceBytes
        $result = Invoke-ObservationCore $fixture -TracePath $tracePath
        Assert-True $result.Trace.Exists 'Present trace reported absent.'
        Assert-Bytes $traceBytes $result.Trace.Bytes 'Trace bytes changed.'
    }
    Test-Case 'Absent trace remains explicit and is not fabricated' {
        $fixture = New-ObservationFixture; $tracePath = [System.IO.Path]::Combine($fixture.Workspace.OutputRoot, 'absent.trace')
        $result = Invoke-ObservationCore $fixture -TracePath $tracePath
        Assert-False $result.Trace.Exists 'Absent trace reported present.'
        Assert-True ($null -eq $result.Trace.Bytes) 'Absent trace was converted to empty content.'
        Assert-False ([System.IO.File]::Exists($tracePath)) 'Absent trace file was fabricated.'
    }
    Test-Case 'Timestamp-only subject touches produce zero changes' {
        $fixture = New-ObservationFixture
        foreach ($entry in $fixture.Materialization.Manifest) { [System.IO.File]::SetLastWriteTimeUtc([System.IO.Path]::Combine($fixture.Materialization.ProjectRoot, $entry.Path.Replace('/', [System.IO.Path]::DirectorySeparatorChar)), [datetime]::UtcNow.AddHours(1)) }
        $result = Invoke-ObservationCore $fixture
        Assert-Equal 0 @($result.ChangedEntries).Count 'Timestamp-only touch was treated as byte change.'
    }
    Test-Case 'Byte-modified subject entry retains exact before and after bytes' {
        $fixture = New-ObservationFixture; $path = [System.IO.Path]::Combine($fixture.Materialization.ProjectRoot, 'Assets', 'a.bin'); Write-TestFileBytes $path ([byte[]] @(9, 8))
        $result = Invoke-ObservationCore $fixture; $change = @($result.ChangedEntries)[0]
        Assert-Equal 'Assets/a.bin' $change.Path 'Modified path mismatch.'; Assert-Equal 'Modified' $change.Change 'Modified state mismatch.'
        Assert-Bytes ([byte[]] @(1, 2, 3)) $change.BeforeBytes 'Before bytes changed.'; Assert-Bytes ([byte[]] @(9, 8)) $change.AfterBytes 'After bytes changed.'
    }
    Test-Case 'Missing original subject entry is returned exactly' {
        $fixture = New-ObservationFixture; [System.IO.File]::Delete([System.IO.Path]::Combine($fixture.Materialization.ProjectRoot, 'Assets', 'a.bin'))
        $result = Invoke-ObservationCore $fixture; $change = @($result.ChangedEntries)[0]
        Assert-Equal 'Assets/a.bin' $change.Path 'Missing path mismatch.'; Assert-Equal 'Missing' $change.Change 'Missing state mismatch.'; Assert-True ($null -eq $change.AfterBytes) 'Missing entry has after bytes.'
    }
    Test-Case 'Case-only subject path change is missing plus generated' {
        $fixture = New-ObservationFixture -Baseline @{ 'Assets/Foo.bin' = [byte[]] @(1, 2, 3) }
        $original = [System.IO.Path]::Combine($fixture.Materialization.ProjectRoot, 'Assets', 'Foo.bin')
        $intermediate = [System.IO.Path]::Combine($fixture.Materialization.ProjectRoot, 'Assets', 'rename-intermediate.bin')
        $renamed = [System.IO.Path]::Combine($fixture.Materialization.ProjectRoot, 'Assets', 'foo.bin')
        [System.IO.File]::Move($original, $intermediate); [System.IO.File]::Move($intermediate, $renamed)
        $result = Invoke-ObservationCore $fixture
        Assert-Equal 1 @($result.ChangedEntries).Count 'Case-only rename changed-entry count mismatch.'
        Assert-Equal 'Assets/Foo.bin' $result.ChangedEntries[0].Path 'Baseline case identity was not preserved.'
        Assert-Equal 'Missing' $result.ChangedEntries[0].Change 'Case-only rename was not reported missing.'
        Assert-Equal 'Assets/foo.bin' @($result.GeneratedPaths)[0] 'Actual case identity was not reported generated.'
    }
    Test-Case 'Generated new path is inventory only' {
        $fixture = New-ObservationFixture; Write-TestFileBytes ([System.IO.Path]::Combine($fixture.Materialization.ProjectRoot, 'Library', 'seed.bin')) ([byte[]] @(7))
        $result = Invoke-ObservationCore $fixture
        Assert-Equal 'Library/seed.bin' @($result.GeneratedPaths)[0] 'Generated path mismatch.'; Assert-Equal 0 @($result.ChangedEntries).Count 'Generated path became subject mutation.'
    }
    Test-Case 'Generated reparse-point escape is rejected where supported' {
        $fixture = New-ObservationFixture
        $outside = [System.IO.Path]::Combine($fixtureRoot, "reparse-target-$([guid]::NewGuid().ToString('N'))")
        $link = [System.IO.Path]::Combine($fixture.Materialization.ProjectRoot, 'Library', 'escape')
        $null = [System.IO.Directory]::CreateDirectory($outside); Write-TestFileBytes ([System.IO.Path]::Combine($outside, 'escaped.bin')) ([byte[]] @(9))
        try {
            try {
                $null = if ($IsWindows) { New-Item -ItemType Junction -Path $link -Target $outside -ErrorAction Stop } else { New-Item -ItemType SymbolicLink -Path $link -Target $outside -ErrorAction Stop }
            }
            catch {
                [Console]::Out.WriteLine("INFO Reparse-point fixture unsupported: $($_.Exception.Message)")
                return
            }
            $state = [pscustomobject]@{ CleanupCalls = 0 }
            $cleanup = { param($workspace) $state.CleanupCalls++ }.GetNewClosure()
            Assert-Rejected { Invoke-ObservationCore $fixture -Cleanup $cleanup } 'UNITY_SUBJECT_INVENTORY_REPARSE_POINT'
            Assert-Equal 0 $state.CleanupCalls 'Cleanup ran after reparse-point inventory rejection.'
        }
        finally {
            if ([System.IO.Directory]::Exists($link)) { [System.IO.Directory]::Delete($link) }
        }
    }
    Test-Case 'Changed and generated paths are ordinally sorted' {
        $fixture = New-ObservationFixture -Baseline @{ 'z.bin' = [byte[]] @(1); 'A.bin' = [byte[]] @(2); 'Packages/packages-lock.json' = [byte[]] @(3) }
        Write-TestFileBytes ([System.IO.Path]::Combine($fixture.Materialization.ProjectRoot, 'z.bin')) ([byte[]] @(9)); Write-TestFileBytes ([System.IO.Path]::Combine($fixture.Materialization.ProjectRoot, 'A.bin')) ([byte[]] @(8))
        Write-TestFileBytes ([System.IO.Path]::Combine($fixture.Materialization.ProjectRoot, 'zeta', 'z.bin')) ([byte[]] @(1)); Write-TestFileBytes ([System.IO.Path]::Combine($fixture.Materialization.ProjectRoot, 'Alpha', 'A.bin')) ([byte[]] @(1))
        $result = Invoke-ObservationCore $fixture
        Assert-Equal ([string]::Join('|', @('A.bin', 'z.bin'))) ([string]::Join('|', @($result.ChangedEntries.Path))) 'Changed entries are not ordinal.'
        Assert-Equal ([string]::Join('|', @('Alpha/A.bin', 'zeta/z.bin'))) ([string]::Join('|', @($result.GeneratedPaths))) 'Generated paths are not ordinal.'
    }
    Test-Case 'Packages lock exact preservation is explicit' {
        $result = Invoke-ObservationCore (New-ObservationFixture)
        Assert-True $result.PackagesLock.ExactBytePreserved 'Exact packages lock was not preserved.'; Assert-Equal 'Preserved' $result.PackagesLock.Status 'Packages lock status mismatch.'
    }
    Test-Case 'Modified packages lock uses generic delta and preservation fact' {
        $fixture = New-ObservationFixture; Write-TestFileBytes ([System.IO.Path]::Combine($fixture.Materialization.ProjectRoot, 'Packages', 'packages-lock.json')) ([byte[]] @(0))
        $result = Invoke-ObservationCore $fixture; $lockChange = @($result.ChangedEntries | Where-Object { $_.Path -ceq 'Packages/packages-lock.json' })
        Assert-False $result.PackagesLock.ExactBytePreserved 'Modified packages lock reported preserved.'; Assert-Equal 'Modified' $result.PackagesLock.Status 'Modified lock status mismatch.'; Assert-Equal 1 $lockChange.Count 'Generic delta omitted packages lock.'
    }
    Test-Case 'External target unchanged is exact-byte observed' {
        $fixture = New-ObservationFixture; $path = [System.IO.Path]::Combine($fixtureRoot, 'external-unchanged.xml'); $bytes = [byte[]] @(1, 0, 2); Write-TestFileBytes $path $bytes
        $result = Invoke-ObservationCore $fixture -ExternalTargets @([pscustomobject]@{ LogicalName = 'runner'; Path = $path; Exists = $true; Bytes = $bytes })
        Assert-Equal 'Unchanged' $result.ExternalTargets[0].State 'External unchanged state mismatch.'; Assert-Bytes $bytes $result.ExternalTargets[0].AfterBytes 'External after bytes changed.'
    }
    Test-Case 'Present external null baseline rejected while explicit empty bytes remain valid' {
        $path = [System.IO.Path]::Combine($fixtureRoot, 'external-empty.xml'); Write-TestFileBytes $path ([byte[]]::new(0))
        $rejectedFixture = New-ObservationFixture; $state = [pscustomobject]@{ CleanupCalls = 0 }
        $cleanup = { param($workspace) $state.CleanupCalls++ }.GetNewClosure()
        Assert-Rejected { Invoke-ObservationCore $rejectedFixture -ExternalTargets @([pscustomobject]@{ LogicalName = 'runner'; Path = $path; Exists = $true; Bytes = $null }) -Cleanup $cleanup } 'UNITY_EXTERNAL_TARGET_INVALID'
        Assert-Equal 0 $state.CleanupCalls 'Cleanup ran after null external baseline rejection.'
        $accepted = Invoke-ObservationCore (New-ObservationFixture) -ExternalTargets @([pscustomobject]@{ LogicalName = 'runner'; Path = $path; Exists = $true; Bytes = [byte[]]::new(0) })
        Assert-Equal 'Unchanged' $accepted.ExternalTargets[0].State 'Explicit empty external baseline was rejected or changed.'
        Assert-Equal 0 $accepted.ExternalTargets[0].BeforeBytes.Length 'Explicit empty baseline did not remain zero length.'
    }
    Test-Case 'External target creation is observed' {
        $fixture = New-ObservationFixture; $path = [System.IO.Path]::Combine($fixtureRoot, 'external-created.xml'); $bytes = [byte[]] @(3, 4); Write-TestFileBytes $path $bytes
        $result = Invoke-ObservationCore $fixture -ExternalTargets @([pscustomobject]@{ LogicalName = 'runner'; Path = $path; Exists = $false })
        Assert-Equal 'Created' $result.ExternalTargets[0].State 'External created state mismatch.'; Assert-Bytes $bytes $result.ExternalTargets[0].AfterBytes 'Created bytes changed.'
    }
    Test-Case 'External target modification is observed' {
        $fixture = New-ObservationFixture; $path = [System.IO.Path]::Combine($fixtureRoot, 'external-modified.xml'); Write-TestFileBytes $path ([byte[]] @(8))
        $result = Invoke-ObservationCore $fixture -ExternalTargets @([pscustomobject]@{ LogicalName = 'runner'; Path = $path; Exists = $true; Bytes = [byte[]] @(7) })
        Assert-Equal 'Modified' $result.ExternalTargets[0].State 'External modified state mismatch.'; Assert-Bytes ([byte[]] @(7)) $result.ExternalTargets[0].BeforeBytes 'External before bytes changed.'; Assert-Bytes ([byte[]] @(8)) $result.ExternalTargets[0].AfterBytes 'External after bytes changed.'
    }
    Test-Case 'External target removal is observed' {
        $fixture = New-ObservationFixture; $path = [System.IO.Path]::Combine($fixtureRoot, 'external-removed.xml')
        $result = Invoke-ObservationCore $fixture -ExternalTargets @([pscustomobject]@{ LogicalName = 'runner'; Path = $path; Exists = $true; Bytes = [byte[]] @(7) })
        Assert-Equal 'Missing' $result.ExternalTargets[0].State 'External missing state mismatch.'; Assert-False $result.ExternalTargets[0].AfterExists 'Removed external target reported present.'
    }
    Test-Case 'External target absent before and after is explicit' {
        $fixture = New-ObservationFixture; $path = [System.IO.Path]::Combine($fixtureRoot, 'external-absent.xml')
        $result = Invoke-ObservationCore $fixture -ExternalTargets @([pscustomobject]@{ LogicalName = 'runner'; Path = $path; Exists = $false })
        Assert-Equal 'AbsentBeforeAbsentAfter' $result.ExternalTargets[0].State 'External absent state mismatch.'
    }
    Test-Case 'Cleanup failure remains separate from captured observation' {
        $fixture = New-ObservationFixture
        $cleanup = { param($workspace) throw 'simulated cleanup rejection' }
        $result = Invoke-ObservationCore $fixture -Cleanup $cleanup
        Assert-True $result.Cleanup.Attempted 'Cleanup attempt was not reported.'; Assert-False $result.Cleanup.Succeeded 'Cleanup failure reported success.'; Assert-Equal 'UNITY_ADAPTER_FAILURE' $result.Cleanup.RejectionClass 'Cleanup rejection class mismatch.'
        Assert-Equal 14 $result.Results.NUnit3.Counts.Total 'Captured parser facts were lost.'; Assert-Bytes $utf8.GetBytes($successCompilationLog) $result.Log.Bytes 'Captured log was lost.'; Assert-True ([System.IO.Directory]::Exists($fixture.Workspace.Root)) 'Simulated cleanup unexpectedly removed workspace.'
    }
    Test-Case 'Public observation lifecycle fixes quiescence and exposes no override' {
        $command = Get-Command Invoke-SpecOpsUnityObservationLifecycle
        Assert-False $command.Parameters.ContainsKey('QuiescenceTimeoutMilliseconds') 'Public lifecycle exposes quiescence override.'
        Assert-Equal 30000 (& $module { $script:ObservationQuiescenceMilliseconds }) 'Canonical observation quiescence is not 30 seconds.'
    }

    Test-Case 'Unity argument vector is exact and discrete' {
        $workspace = New-SpecOpsUnityWorkspace; $ownedWorkspaces.Add($workspace)
        $contract = New-SpecOpsUnityArgumentVector $workspace.SubjectRoot $workspace.OutputRoot
        $expected = @('-batchmode', '-projectPath', $workspace.SubjectRoot, '-runTests', '-testPlatform', 'EditMode', '-assemblyNames', 'InfiniteMonkey.EditModeTests', '-testResults', ([System.IO.Path]::Combine($workspace.OutputRoot, 'results.xml')), '-logFile', ([System.IO.Path]::Combine($workspace.OutputRoot, 'unity.log')))
        Assert-Equal ([string]::Join([char]0, $expected)) ([string]::Join([char]0, $contract.Arguments)) 'Argument vector mismatch.'
        Assert-False ($contract.Arguments -ccontains '-quit') 'Forbidden -quit present.'
        Assert-False ($contract.Arguments -ccontains '-nographics') 'Unproven -nographics present.'
        Assert-False ($contract.Arguments -ccontains '-testFilter') 'Narrow test filter present.'
        Assert-False ($contract.Arguments -ccontains '-testCategory') 'Category filter present.'
        Assert-True ([System.IO.Path]::IsPathFullyQualified($contract.ResultsPath)) 'Results path is not absolute.'
        Assert-True ([System.IO.Path]::IsPathFullyQualified($contract.LogPath)) 'Log path is not absolute.'
        Assert-False ($contract.ResultsPath.StartsWith($workspace.SubjectRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) 'Results path is inside materialized subject.'
    }
    Test-Case 'Unity argument output inside project rejected' { $workspace = New-SpecOpsUnityWorkspace; $ownedWorkspaces.Add($workspace); Assert-Rejected { New-SpecOpsUnityArgumentVector $workspace.SubjectRoot ([System.IO.Path]::Combine($workspace.SubjectRoot, 'output')) } 'UNITY_ARGUMENT_PATH_INVALID' }

    $pwshPath = [System.Environment]::ProcessPath
    Test-Case 'Controlled process captures successful stdout' {
        $observation = Invoke-ProcessCore $pwshPath @('-NoProfile', '-Command', '[Console]::Out.Write("foundation-ok")')
        Assert-True $observation.Started 'Process did not start.'; Assert-False $observation.TimedOut 'Process timed out.'; Assert-True $observation.TerminationConfirmed 'Termination not confirmed.'; Assert-Equal 0 $observation.ExitCode 'Exit code mismatch.'; Assert-Equal 'foundation-ok' $observation.Stdout 'stdout mismatch.'; Assert-Equal '' $observation.Stderr 'stderr was not empty.'
    }
    Test-Case 'Controlled process captures stderr and nonzero exit' {
        $observation = Invoke-ProcessCore $pwshPath @('-NoProfile', '-Command', '[Console]::Error.Write("foundation-error"); exit 7')
        Assert-Equal 7 $observation.ExitCode 'Nonzero exit mismatch.'; Assert-Equal 'foundation-error' $observation.Stderr 'stderr mismatch.'; Assert-False $observation.TimedOut 'Nonzero process timed out.'
    }
    Test-Case 'Controlled process timeout kills process' {
        $observation = Invoke-ProcessCore $pwshPath @('-NoProfile', '-Command', 'Start-Sleep -Seconds 30') 250 30000
        Assert-True $observation.Started 'Timeout fixture did not start.'; Assert-True $observation.TimedOut 'Timeout was not observed.'; Assert-True $observation.TerminationConfirmed 'Timed-out process termination was not confirmed.'; Assert-True ($observation.DurationMilliseconds -lt 30000) 'Timeout fixture exceeded termination bound.'
    }
    Test-Case 'Controlled process kills complete process tree' {
        $childCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes('Start-Sleep -Seconds 30'))
        $escapedPwsh = $pwshPath.Replace("'", "''")
        $parentSource = "`$psi=[Diagnostics.ProcessStartInfo]::new();`$psi.FileName='$escapedPwsh';`$psi.UseShellExecute=`$false;`$psi.CreateNoWindow=`$true;`$null=`$psi.ArgumentList.Add('-NoProfile');`$null=`$psi.ArgumentList.Add('-EncodedCommand');`$null=`$psi.ArgumentList.Add('$childCommand');`$child=[Diagnostics.Process]::new();`$child.StartInfo=`$psi;if(-not `$child.Start()){throw 'Child process did not start.'};[Console]::Out.WriteLine(`$child.Id);[Console]::Out.Flush();`$child.WaitForExit()"
        $parentCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($parentSource))
        $observation = Invoke-ProcessCore $pwshPath @('-NoProfile', '-EncodedCommand', $parentCommand) 1500 30000
        Assert-True $observation.TimedOut 'Process-tree fixture did not time out.'; Assert-True $observation.TerminationConfirmed 'Process-tree termination was not confirmed.'
        $childId = 0
        Assert-True ([int]::TryParse($observation.Stdout.Trim(), [ref] $childId)) 'Child PID was not captured.'
        Assert-True ($null -eq (Get-Process -Id $childId -ErrorAction SilentlyContinue)) 'Child process survived tree termination.'
    }
    Test-Case 'Controlled process reports start failure structurally' {
        $observation = Invoke-ProcessCore ([System.IO.Path]::Combine($fixtureRoot, 'does-not-exist.exe')) @() 1000 1000
        Assert-False $observation.Started 'Missing process unexpectedly started.'; Assert-Equal 'PROCESS_START_FAILED' $observation.StartFailure 'Start failure class mismatch.'; Assert-True ($null -eq $observation.ExitCode) 'Start failure has an exit code.'
    }
    Test-Case 'Controlled process observation has all required fields' {
        $observation = Invoke-ProcessCore $pwshPath @('-NoProfile', '-Command', 'exit 0')
        foreach ($name in @('Started', 'TimedOut', 'TerminationConfirmed', 'ExitCode', 'Stdout', 'Stderr', 'DurationMilliseconds', 'StartFailure')) { Assert-True ($null -ne $observation.PSObject.Properties[$name]) "Missing process observation field: $name" }
    }
    Test-Case 'Process-local package guard mechanically denies Git transport fallback' {
        $guard = Get-SpecOpsUnityPackageAcquisitionGuard
        $repositoryUri = ([System.Uri]::new($repositoryRoot)).AbsoluteUri
        $observation = Invoke-ProcessCore 'git' @('ls-remote', $repositoryUri) 5000 30000 $guard
        Assert-True $observation.Started 'Guard verification Git process did not start.'
        Assert-True ($observation.ExitCode -ne 0) 'Process-local guard allowed a Git transport.'
        Assert-True ($observation.Stderr.Contains('transport', [System.StringComparison]::OrdinalIgnoreCase) -and $observation.Stderr.Contains('not allowed', [System.StringComparison]::OrdinalIgnoreCase)) 'Git transport denial was not observed.'
    }

    Test-Case 'Unity module contains package-object verification but no subject repository state semantics' { $source = [System.IO.File]::ReadAllText($modulePath); Assert-True ($source.Contains('Invoke-SpecOpsUnityCapabilityGit', [System.StringComparison]::Ordinal)) 'Package Git-object verifier absent.'; Assert-False ([regex]::IsMatch($source, "(?i)SpecOpsRepository|--show-current|'(?:HEAD|status|branch|checkout|worktree)'")) 'Subject repository state semantics found in Unity module.' }
    Test-Case 'Unity module contains no Eval business logic' { $source = [System.IO.File]::ReadAllText($modulePath); Assert-False ([regex]::IsMatch($source, '(?i)definitionContentIdentity|overallResult|checkResults|eval-result|provenance|\.specops/evidence')) 'Eval/evidence business logic found in Unity module.' }
    Test-Case 'Process-tree fixture uses direct ProcessStartInfo' { $source = [System.IO.File]::ReadAllText($PSCommandPath); Assert-False $source.Contains(('Start-' + 'Process'), [System.StringComparison]::OrdinalIgnoreCase) 'Test suite contains forbidden descendant process creation.'; Assert-True $source.Contains('[Diagnostics.ProcessStartInfo]::new()', [System.StringComparison]::Ordinal) 'Direct child ProcessStartInfo fixture is absent.' }
    Test-Case 'Unity test suite never invokes Unity' { $source = [System.IO.File]::ReadAllText($PSCommandPath); Assert-False ([regex]::IsMatch($source, '(?i)Invoke-SpecOpsControlledProcess(?:Core)?[^\r\n]*Unity\.exe')) 'Test suite contains a Unity process invocation.' }
    Test-Case 'Canonical process timeout is fixed and not public' {
        $command = Get-Command Invoke-SpecOpsControlledProcess
        Assert-False $command.Parameters.ContainsKey('TimeoutMilliseconds') 'Canonical process exposes timeout override.'
        $timeout = & $module { $script:CanonicalTimeoutMilliseconds }
        $termination = & $module { $script:TerminationWaitMilliseconds }
        Assert-Equal 1200000 $timeout 'Canonical timeout is not 20 minutes.'; Assert-Equal 30000 $termination 'Termination wait is not 30 seconds.'
    }
}
finally {
    foreach ($workspace in $ownedWorkspaces) {
        if ([System.IO.Directory]::Exists([string] $workspace.Root)) {
            try { $null = Remove-SpecOpsUnityWorkspace $workspace } catch { }
        }
    }
    Remove-TestDirectory $fixtureRoot
}

[Console]::Out.WriteLine("Unity foundation tests: $($script:Tests); failures: $($script:Failures.Count)")
if ($script:Failures.Count -gt 0) { $script:Failures | ForEach-Object { [Console]::Out.WriteLine($_) }; exit 1 }
exit 0
