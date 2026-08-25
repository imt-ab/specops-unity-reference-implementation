Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Tests = 0
$script:Failures = [System.Collections.Generic.List[string]]::new()
$modulePath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, '..', 'SpecOps.Unity.psm1'))
Import-Module -Name $modulePath -Force -ErrorAction Stop
$module = Get-Module -Name SpecOps.Unity
$utf8 = [System.Text.UTF8Encoding]::new($false)

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
    param([string] $File, [string[]] $Arguments, [int] $Timeout = 5000, [int] $TerminationWait = 30000)
    return & $module { param($f, $a, $t, $w) Invoke-SpecOpsControlledProcessCore -FilePath $f -ArgumentList $a -TimeoutMilliseconds $t -TerminationWaitMilliseconds $w } $File $Arguments $Timeout $TerminationWait
}
function Remove-TestDirectory {
    param([string] $Path)
    $resolved = [System.IO.Path]::GetFullPath($Path)
    $temp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if (-not $resolved.StartsWith($temp, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe test cleanup path: $resolved" }
    if ([System.IO.Directory]::Exists($resolved)) { [System.IO.Directory]::Delete($resolved, $true) }
}

$fixtureRoot = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "specops-unity-tests-$([guid]::NewGuid().ToString('N'))")
$null = [System.IO.Directory]::CreateDirectory($fixtureRoot)
$ownedWorkspaces = [System.Collections.Generic.List[object]]::new()
try {
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

    Test-Case 'Unity module contains no Git semantics' { $source = [System.IO.File]::ReadAllText($modulePath); Assert-False ([regex]::IsMatch($source, '(?i)\bgit\b|rev-parse|ls-tree|cat-file|checkout|worktree')) 'Git semantics found in Unity module.' }
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
