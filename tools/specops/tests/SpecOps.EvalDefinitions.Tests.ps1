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
        $script:Failures.Add($(if ([string]::IsNullOrEmpty($Detail)) { $Name } else { "$Name`: $Detail" }))
    }
}

function Test-Equal {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [AllowNull()] $Expected,
        [AllowNull()] $Actual
    )

    if ($Expected -is [string] -and $Actual -is [string]) {
        $equal = [string]::Equals($Expected, $Actual, [System.StringComparison]::Ordinal)
    }
    else {
        $equal = $Expected -eq $Actual
    }
    Test-Assertion -Name $Name -Condition $equal -Detail "expected=[$Expected] actual=[$Actual]"
}

function Test-HasProperty {
    param(
        [Parameter(Mandatory)] $Object,
        [Parameter(Mandatory)] [string] $Name
    )

    return $null -ne $Object.PSObject.Properties[$Name]
}

function Write-TemporaryJson {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] $Value
    )

    $json = $Value | ConvertTo-Json -Depth 100
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false, $true))
}

function Test-RepositoryReference {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Reference,
        [Parameter(Mandatory)] [string] $RepositoryRoot
    )

    $isRelative = -not [System.IO.Path]::IsPathRooted($Reference)
    $usesForwardSlash = -not $Reference.Contains('\')
    $hasTraversal = @($Reference.Split('/') | Where-Object { $_ -eq '..' }).Count -gt 0
    Test-Assertion -Name ($Name + ' is repository-relative') -Condition ($isRelative -and $usesForwardSlash -and -not $hasTraversal)
    if ($isRelative -and -not $hasTraversal) {
        $resolved = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($RepositoryRoot, $Reference.Replace('/', [System.IO.Path]::DirectorySeparatorChar)))
        $rootPrefix = $RepositoryRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
        $inside = [string]::Equals($resolved, $RepositoryRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
            $resolved.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)
        Test-Assertion -Name ($Name + ' stays inside repository') -Condition $inside
        Test-Assertion -Name ($Name + ' resolves') -Condition ($inside -and ([System.IO.File]::Exists($resolved) -or [System.IO.Directory]::Exists($resolved))) -Detail $Reference
    }
}

function Test-PassConditionShape {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] $PassCondition
    )

    $value = $PassCondition.value
    Test-Assertion -Name ($Name + ' value is object') -Condition ($value -is [pscustomobject])
    if ($value -isnot [pscustomobject]) { return }

    switch ($PassCondition.type) {
        'all-items-conform' {
            $hasSelector = (Test-HasProperty $value 'inventory') -or
                (Test-HasProperty $value 'inventoryReference') -or
                (Test-HasProperty $value 'selectionReference') -or
                (Test-HasProperty $value 'roots')
            Test-Assertion -Name ($Name + ' has deterministic item selection') -Condition $hasSelector
        }
        'exact-set' {
            Test-Assertion -Name ($Name + ' has comparison') -Condition (Test-HasProperty $value 'comparison')
            $hasExpected = (Test-HasProperty $value 'expected') -or (Test-HasProperty $value 'stateJsonPointer')
            Test-Assertion -Name ($Name + ' has expected-set source') -Condition $hasExpected
        }
        'equals' {
            Test-Assertion -Name ($Name + ' has expected') -Condition (Test-HasProperty $value 'expected')
            Test-Assertion -Name ($Name + ' has comparison') -Condition (Test-HasProperty $value 'comparison')
        }
        'references-resolve' {
            Test-Assertion -Name ($Name + ' has allowedRoot') -Condition (Test-HasProperty $value 'allowedRoot')
            Test-Assertion -Name ($Name + ' prohibits network') -Condition ((Test-HasProperty $value 'networkAllowed') -and $value.networkAllowed -eq $false)
        }
        'subset-of-allowlist' {
            Test-Assertion -Name ($Name + ' has semanticResolution') -Condition (Test-HasProperty $value 'semanticResolution')
            Test-Assertion -Name ($Name + ' has allowedTargetsByAssembly') -Condition (Test-HasProperty $value 'allowedTargetsByAssembly')
        }
        'zero-count' {
            Test-Assertion -Name ($Name + ' has source') -Condition (Test-HasProperty $value 'source')
            Test-Assertion -Name ($Name + ' has count field') -Condition ((Test-HasProperty $value 'field') -or (Test-HasProperty $value 'fields'))
        }
        'required-items-present' {
            Test-Assertion -Name ($Name + ' has requiredItems') -Condition (Test-HasProperty $value 'requiredItems')
        }
        'tracked-paths-absent' {
            Test-Assertion -Name ($Name + ' has tracked inventory') -Condition ((Test-HasProperty $value 'inventory') -and $value.inventory -ceq 'tracked-subject-paths')
            Test-Assertion -Name ($Name + ' has prohibitedPatterns') -Condition (Test-HasProperty $value 'prohibitedPatterns')
        }
        default {
            Test-Assertion -Name ($Name + ' uses known pass condition') -Condition $false -Detail $PassCondition.type
        }
    }
}

$repositoryRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, '..', '..', '..'))
$modulePath = [System.IO.Path]::Combine($repositoryRoot, 'tools', 'specops', 'SpecOps.Core.psm1')
$evalRoot = [System.IO.Path]::Combine($repositoryRoot, '.specops', 'evals')
$schemaPath = [System.IO.Path]::Combine($repositoryRoot, '.specops', 'contracts', 'eval-definition.schema.json')
$configPath = [System.IO.Path]::Combine($repositoryRoot, '.specops', 'specops.json')
$temporaryRoot = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'specops-e8c2-' + [guid]::NewGuid().ToString('N'))
$evidencePath = [System.IO.Path]::Combine($repositoryRoot, '.specops', 'evidence')
$evidenceExistedBefore = [System.IO.Directory]::Exists($evidencePath)

$expectedChecks = [ordered]@{
    'specops-core-contract-integrity' = @(
        'contracts-json-parse',
        'contracts-id-unique',
        'contracts-version-consistent',
        'contracts-draft-declared',
        'contracts-references-resolve',
        'contracts-schema-valid'
    )
    'specops-derived-state-consistency' = @(
        'authority-routes-resolve',
        'feature-authority-triplets',
        'feature-state-schema-valid',
        'feature-id-directory-match',
        'acceptance-id-exact-match',
        'state-reference-resolution',
        'state-lifecycle-consistency'
    )
    'unity-clean-architecture-static' = @(
        'runtime-asmdef-set',
        'runtime-assembly-names',
        'engine-independence-flags',
        'runtime-project-reference-graph',
        'domain-application-source-boundary',
        'generated-artifacts-untracked'
    )
    'unity-editmode-validation' = @(
        'unity-version-match',
        'unity-compilation-success',
        'editmode-suite-executed',
        'editmode-required-tests-discovered',
        'editmode-zero-failures',
        'unity-exit-success',
        'unity-tracked-state-preserved'
    )
}

$allowedMethods = @(
    'exact-set-comparison',
    'reference-resolution',
    'schema-validation',
    'static-json-inspection',
    'static-repository-inspection',
    'static-source-boundary',
    'unity-editmode-execution'
)
$allowedPassConditionTypes = @(
    'all-items-conform',
    'equals',
    'exact-set',
    'references-resolve',
    'required-items-present',
    'subset-of-allowlist',
    'tracked-paths-absent',
    'zero-count'
)

try {
    [void] [System.IO.Directory]::CreateDirectory($temporaryRoot)
    Import-Module -Name $modulePath -Force -ErrorAction Stop

    $definitionFiles = @(Get-ChildItem -LiteralPath $evalRoot -Filter '*.eval.json' -File | Sort-Object Name)
    Test-Equal -Name 'definition inventory count' -Expected 4 -Actual $definitionFiles.Count
    $expectedFiles = @($expectedChecks.Keys | ForEach-Object { $_ + '.eval.json' } | Sort-Object)
    $actualFiles = @($definitionFiles.Name | Sort-Object)
    $fileCoverage = Compare-SpecOpsIdCoverage -ExpectedIds $expectedFiles -ActualIds $actualFiles
    Test-Assertion -Name 'definition filename exact set' -Condition $fileCoverage.IsExact

    $definitions = [System.Collections.Generic.List[object]]::new()
    foreach ($file in $definitionFiles) {
        $raw = [System.IO.File]::ReadAllText($file.FullName, [System.Text.UTF8Encoding]::new($false, $true))
        $schemaValid = $false
        try { $schemaValid = Test-Json -Json $raw -SchemaFile $schemaPath -ErrorAction Stop }
        catch { $schemaValid = $false }
        Test-Assertion -Name ('schema valid ' + $file.Name) -Condition $schemaValid

        $definition = $raw | ConvertFrom-Json -Depth 100
        $definitions.Add([pscustomobject]@{ File = $file; Raw = $raw; Value = $definition })
    }

    $definitionIdResult = Test-SpecOpsUniqueIds -Items @($definitions | ForEach-Object { $_.Value }) -IdProperty definitionId
    Test-Assertion -Name 'definition IDs unique' -Condition $definitionIdResult.IsValid
    $definitionCoverage = Compare-SpecOpsIdCoverage -ExpectedIds @($expectedChecks.Keys) -ActualIds @($definitions | ForEach-Object { $_.Value.definitionId })
    Test-Assertion -Name 'definition IDs exact set' -Condition $definitionCoverage.IsExact

    foreach ($entry in $definitions) {
        $definition = $entry.Value
        $id = $definition.definitionId
        Test-Equal -Name ("$id contractVersion") -Expected '1.0.0' -Actual $definition.contractVersion
        Test-Equal -Name ("$id definitionVersion") -Expected '1.0.0' -Actual $definition.definitionVersion
        Test-Equal -Name ("$id identity algorithm") -Expected 'specops-json-jcs-sha256-v1' -Actual $definition.contentIdentity.algorithm
        Test-Assertion -Name ("$id identity shape") -Condition ($definition.contentIdentity.value -cmatch '^[0-9a-f]{64}$')
        $identity = Get-SpecOpsJsonContentIdentity -Path $entry.File.FullName -Mode EVAL_DEFINITION
        Test-Equal -Name ("$id stored identity") -Expected $definition.contentIdentity.value -Actual $identity.value

        $checkIds = @($definition.checks | ForEach-Object { $_.id })
        $uniqueChecks = Test-SpecOpsUniqueIds -Items @($definition.checks) -IdProperty id
        Test-Assertion -Name ("$id check IDs unique") -Condition $uniqueChecks.IsValid
        $checkCoverage = Compare-SpecOpsIdCoverage -ExpectedIds $expectedChecks[$id] -ActualIds $checkIds
        Test-Assertion -Name ("$id check IDs exact set") -Condition $checkCoverage.IsExact

        foreach ($check in $definition.checks) {
            Test-Assertion -Name ("$id/$($check.id) evaluationMethod allowlisted") -Condition ($allowedMethods -ccontains $check.evaluationMethod)
            Test-Assertion -Name ("$id/$($check.id) passCondition allowlisted") -Condition ($allowedPassConditionTypes -ccontains $check.passCondition.type)
            Test-PassConditionShape -Name ("$id/$($check.id)") -PassCondition $check.passCondition
        }

        foreach ($scope in $definition.targetScope) {
            if (Test-HasProperty $scope 'reference') {
                Test-RepositoryReference -Name ("$id targetScope/$($scope.id)") -Reference $scope.reference -RepositoryRoot $repositoryRoot
            }
        }
        foreach ($reference in $definition.governingReferences) {
            if (Test-HasProperty $reference 'reference') {
                Test-RepositoryReference -Name ("$id governingReference/$($reference.id)") -Reference $reference.reference -RepositoryRoot $repositoryRoot
            }
        }

        $asHashtable = $entry.Raw | ConvertFrom-Json -AsHashtable -Depth 100
        $reordered = [ordered]@{}
        $keys = @($asHashtable.Keys)
        [array]::Reverse($keys)
        foreach ($key in $keys) { $reordered[$key] = $asHashtable[$key] }
        $reorderedPath = [System.IO.Path]::Combine($temporaryRoot, $id + '-reordered.json')
        Write-TemporaryJson -Path $reorderedPath -Value $reordered
        $reorderedIdentity = Get-SpecOpsJsonContentIdentity -Path $reorderedPath -Mode EVAL_DEFINITION
        Test-Equal -Name ("$id property reorder invariant") -Expected $identity.value -Actual $reorderedIdentity.value

        $rootChanged = $entry.Raw | ConvertFrom-Json -AsHashtable -Depth 100
        $rootChanged.contentIdentity.value = 'temporary-root-identity-change'
        $rootChangedPath = [System.IO.Path]::Combine($temporaryRoot, $id + '-root-identity.json')
        Write-TemporaryJson -Path $rootChangedPath -Value $rootChanged
        $rootChangedIdentity = Get-SpecOpsJsonContentIdentity -Path $rootChangedPath -Mode EVAL_DEFINITION
        Test-Equal -Name ("$id root identity excluded") -Expected $identity.value -Actual $rootChangedIdentity.value

        $semanticChanged = $entry.Raw | ConvertFrom-Json -AsHashtable -Depth 100
        $semanticChanged.checks[0].passCondition.value['e8c2IdentityProbe'] = 'included-change'
        $semanticChangedPath = [System.IO.Path]::Combine($temporaryRoot, $id + '-semantic-change.json')
        Write-TemporaryJson -Path $semanticChangedPath -Value $semanticChanged
        $semanticChangedIdentity = Get-SpecOpsJsonContentIdentity -Path $semanticChangedPath -Mode EVAL_DEFINITION
        Test-Assertion -Name ("$id included passCondition changes identity") -Condition (-not [string]::Equals($identity.value, $semanticChangedIdentity.value, [System.StringComparison]::Ordinal))
    }

    $architectureDefinition = ($definitions | Where-Object { $_.Value.definitionId -eq 'unity-clean-architecture-static' }).Value
    $graphCheck = $architectureDefinition.checks | Where-Object { $_.id -eq 'runtime-project-reference-graph' }
    $actualGraph = $graphCheck.passCondition.value.allowedTargetsByAssembly
    $expectedGraph = [ordered]@{
        'InfiniteMonkey.Domain' = @()
        'InfiniteMonkey.Application' = @('InfiniteMonkey.Domain', 'InfiniteMonkey.Utility')
        'InfiniteMonkey.AI' = @('InfiniteMonkey.Application', 'InfiniteMonkey.Domain', 'InfiniteMonkey.Utility')
        'InfiniteMonkey.Infrastructure' = @('InfiniteMonkey.Application', 'InfiniteMonkey.Domain', 'InfiniteMonkey.Utility')
        'InfiniteMonkey.Presentation' = @('InfiniteMonkey.Application', 'InfiniteMonkey.Utility')
        'InfiniteMonkey.Composition' = @('InfiniteMonkey.Application', 'InfiniteMonkey.Domain', 'InfiniteMonkey.Infrastructure', 'InfiniteMonkey.Presentation', 'InfiniteMonkey.Utility')
        'InfiniteMonkey.Utility' = @()
    }
    $graphAssemblyCoverage = Compare-SpecOpsIdCoverage -ExpectedIds @($expectedGraph.Keys) -ActualIds @($actualGraph.PSObject.Properties.Name)
    Test-Assertion -Name 'architecture allowlist assembly set exact' -Condition $graphAssemblyCoverage.IsExact
    foreach ($assemblyName in $expectedGraph.Keys) {
        $actualTargets = @($actualGraph.PSObject.Properties[$assemblyName].Value)
        $targetCoverage = Compare-SpecOpsIdCoverage -ExpectedIds $expectedGraph[$assemblyName] -ActualIds $actualTargets
        Test-Assertion -Name ("architecture allowlist exact $assemblyName") -Condition $targetCoverage.IsExact
    }
    Test-Assertion -Name 'architecture Domain deliberately excludes Utility' -Condition (-not (@($actualGraph.'InfiniteMonkey.Domain') -ccontains 'InfiniteMonkey.Utility'))
    Test-Assertion -Name 'architecture Utility is a runtime-layer leaf' -Condition (@($actualGraph.'InfiniteMonkey.Utility').Count -eq 0)
    $expectedUtilityReferrers = @('InfiniteMonkey.Application', 'InfiniteMonkey.AI', 'InfiniteMonkey.Infrastructure', 'InfiniteMonkey.Presentation', 'InfiniteMonkey.Composition')
    $actualUtilityReferrers = @($actualGraph.PSObject.Properties | Where-Object { @($_.Value) -ccontains 'InfiniteMonkey.Utility' } | ForEach-Object { $_.Name })
    $utilityReferrerCoverage = Compare-SpecOpsIdCoverage -ExpectedIds $expectedUtilityReferrers -ActualIds $actualUtilityReferrers
    Test-Assertion -Name 'architecture Utility edges are incoming only from approved layers' -Condition $utilityReferrerCoverage.IsExact
    Test-Assertion -Name 'architecture no runtime-layer edge beyond literal allowlists' -Condition ($graphAssemblyCoverage.IsExact -and (@($expectedGraph.Keys | Where-Object {
        $targets = @($actualGraph.PSObject.Properties[$_].Value)
        -not (Compare-SpecOpsIdCoverage -ExpectedIds $expectedGraph[$_] -ActualIds $targets).IsExact
    }).Count -eq 0))

    $stateDefinition = ($definitions | Where-Object { $_.Value.definitionId -eq 'specops-derived-state-consistency' }).Value
    $stateReferenceCheck = $stateDefinition.checks | Where-Object { $_.id -eq 'state-reference-resolution' }
    $selectorValue = $stateReferenceCheck.passCondition.value
    Test-Assertion -Name 'state reference resolver has no jsonPointers pseudo-selector' -Condition (-not (Test-HasProperty $selectorValue 'jsonPointers'))
    Test-Assertion -Name 'state reference resolver has selectors' -Condition (Test-HasProperty $selectorValue 'selectors')
    $expectedSelectors = @(
        '/review/reference|scalar',
        '/implementationPlan/reference|scalar',
        '/validation/reference|scalar',
        '/sync/reference|scalar',
        '/adrReferences|all-array-items'
    )
    $actualSelectors = @($selectorValue.selectors | ForEach-Object { $_.jsonPointer + '|' + $_.selection })
    $selectorCoverage = Compare-SpecOpsIdCoverage -ExpectedIds $expectedSelectors -ActualIds $actualSelectors
    Test-Assertion -Name 'state reference selectors exact' -Condition $selectorCoverage.IsExact
    foreach ($selector in $selectorValue.selectors) {
        Test-Assertion -Name ("state selector has normal JSON Pointer $($selector.jsonPointer)") -Condition ($selector.jsonPointer.StartsWith('/', [System.StringComparison]::Ordinal) -and -not $selector.jsonPointer.Contains('*'))
        Test-Assertion -Name ("state selector vocabulary $($selector.jsonPointer)") -Condition (@('scalar', 'all-array-items') -ccontains $selector.selection)
    }

    $editModeDefinition = ($definitions | Where-Object { $_.Value.definitionId -eq 'unity-editmode-validation' }).Value
    $zeroFailuresCheck = $editModeDefinition.checks | Where-Object { $_.id -eq 'editmode-zero-failures' }
    $zeroFailuresValue = $zeroFailuresCheck.passCondition.value
    Test-Assertion -Name 'EditMode zero-failures has complete assembly scope' -Condition (Test-HasProperty $zeroFailuresValue 'scope')
    Test-Equal -Name 'EditMode zero-failures scope type' -Expected 'executed-test-assembly' -Actual $zeroFailuresValue.scope.type
    Test-Equal -Name 'EditMode zero-failures scope assembly' -Expected 'InfiniteMonkey.EditModeTests' -Actual $zeroFailuresValue.scope.assembly
    Test-Assertion -Name 'EditMode zero-failures is not required-subset scoped' -Condition (-not (Test-HasProperty $zeroFailuresValue 'scopeReference'))
    Test-Assertion -Name 'EditMode zero-failures requires all terminal results' -Condition ((Test-HasProperty $zeroFailuresValue 'allDiscoveredAndExecutedTestsMustHaveTerminalResult') -and $zeroFailuresValue.allDiscoveredAndExecutedTestsMustHaveTerminalResult -eq $true)
    $zeroFailureFields = Compare-SpecOpsIdCoverage -ExpectedIds @('failed', 'inconclusive', 'notExecuted') -ActualIds @($zeroFailuresValue.fields)
    Test-Assertion -Name 'EditMode zero-failures result fields exact' -Condition $zeroFailureFields.IsExact

    $trackedStateCheck = $editModeDefinition.checks | Where-Object { $_.id -eq 'unity-tracked-state-preserved' }
    $trackedStateValue = $trackedStateCheck.passCondition.value
    $trackedStateJson = $trackedStateCheck | ConvertTo-Json -Depth 20 -Compress
    Test-Equal -Name 'tracked-state pass condition is zero-count' -Expected 'zero-count' -Actual $trackedStateCheck.passCondition.type
    Test-Equal -Name 'tracked-state delta source' -Expected 'tracked-subject-state-delta' -Actual $trackedStateValue.source
    Test-Equal -Name 'tracked-state changed entry field' -Expected 'changedEntries' -Actual $trackedStateValue.field
    Test-Assertion -Name 'tracked-state contains no contentIdentitySet' -Condition (-not $trackedStateJson.Contains('contentIdentitySet'))
    Test-Assertion -Name 'tracked-state names no JSON identity profile' -Condition (-not $trackedStateJson.Contains('specops-json-jcs-sha256-v1'))
    Test-Equal -Name 'tracked-state path identity exact' -Expected 'repository-relative-ordinal' -Actual $trackedStateValue.changeSemantics.pathIdentity
    Test-Equal -Name 'tracked-state byte comparison exact' -Expected 'exact-byte-equivalence' -Actual $trackedStateValue.changeSemantics.contentComparison
    Test-Equal -Name 'tracked-state addition is change' -Expected 'change' -Actual $trackedStateValue.changeSemantics.addedEntry
    Test-Equal -Name 'tracked-state removal is change' -Expected 'change' -Actual $trackedStateValue.changeSemantics.removedEntry
    Test-Equal -Name 'tracked-state modified bytes are change' -Expected 'change' -Actual $trackedStateValue.changeSemantics.modifiedEntryBytes
    Test-Equal -Name 'tracked-state ignored caches excluded' -Expected $true -Actual $trackedStateValue.ignoredGeneratedPathsExcluded
    Test-Equal -Name 'tracked-state ProjectSettings changes prohibited' -Expected $false -Actual $trackedStateValue.trackedProjectSettingsChangesAllowed

    $versionCheck = $editModeDefinition.checks | Where-Object { $_.id -eq 'unity-version-match' }
    $versionValue = $versionCheck.passCondition.value
    Test-Equal -Name 'Unity version actual source' -Expected 'unity-execution-context' -Actual $versionValue.actual.source
    Test-Equal -Name 'Unity version actual field' -Expected 'editorVersion' -Actual $versionValue.actual.versionField
    Test-Equal -Name 'Unity revision actual field' -Expected 'editorRevision' -Actual $versionValue.actual.revisionField
    Test-Equal -Name 'Unity version expected source' -Expected 'repository-file' -Actual $versionValue.expected.source
    Test-Equal -Name 'Unity version expected reference' -Expected 'ProjectSettings/ProjectVersion.txt' -Actual $versionValue.expected.reference
    Test-Equal -Name 'Unity version expected field' -Expected 'm_EditorVersion' -Actual $versionValue.expected.versionField
    Test-Equal -Name 'Unity combined version/revision field' -Expected 'm_EditorVersionWithRevision' -Actual $versionValue.expected.combinedVersionRevisionField
    Test-Equal -Name 'Unity revision extraction operation' -Expected 'parenthesized-revision-suffix' -Actual $versionValue.expected.extraction.operation
    Test-Equal -Name 'Unity combined field format' -Expected 'version-space-parenthesized-revision' -Actual $versionValue.expected.extraction.combinedFormat
    Test-Equal -Name 'Unity extraction version result' -Expected 'substring-before-space-open-parenthesis' -Actual $versionValue.expected.extraction.versionResult
    Test-Equal -Name 'Unity extraction revision result' -Expected 'content-inside-parentheses' -Actual $versionValue.expected.extraction.revisionResult
    Test-Equal -Name 'Unity combined version prefix consistency field' -Expected 'm_EditorVersion' -Actual $versionValue.expected.extraction.versionPrefixMustEqualField
    Test-Equal -Name 'Unity editor version comparison' -Expected 'ordinal-string' -Actual $versionValue.comparison.editorVersionToDeclaredVersion
    Test-Equal -Name 'Unity editor revision comparison' -Expected 'ordinal-string' -Actual $versionValue.comparison.editorRevisionToExtractedRevision

    $projectVersionPath = [System.IO.Path]::Combine($repositoryRoot, 'ProjectSettings', 'ProjectVersion.txt')
    $projectVersionText = [System.IO.File]::ReadAllText($projectVersionPath)
    $declaredVersionMatch = [System.Text.RegularExpressions.Regex]::Match($projectVersionText, '^m_EditorVersion: ([^\r\n]+)\r?$', [System.Text.RegularExpressions.RegexOptions]::Multiline)
    $combinedVersionMatch = [System.Text.RegularExpressions.Regex]::Match($projectVersionText, '^m_EditorVersionWithRevision: ([^ ()\r\n]+) \(([^()\s]+)\)\r?$', [System.Text.RegularExpressions.RegexOptions]::Multiline)
    Test-Assertion -Name 'ProjectVersion m_EditorVersion format applicable' -Condition $declaredVersionMatch.Success
    Test-Assertion -Name 'ProjectVersion parenthesized revision format applicable' -Condition $combinedVersionMatch.Success
    if ($declaredVersionMatch.Success -and $combinedVersionMatch.Success) {
        $extractedVersion = $combinedVersionMatch.Groups[1].Value
        $extractedRevision = $combinedVersionMatch.Groups[2].Value
        Test-Equal -Name 'ProjectVersion combined prefix equals declared version' -Expected $declaredVersionMatch.Groups[1].Value -Actual $extractedVersion
        Test-Assertion -Name 'ProjectVersion extracted version excludes space/open-parenthesis delimiter' -Condition (-not $extractedVersion.Contains(' ('))
        Test-Assertion -Name 'ProjectVersion extracted revision non-empty' -Condition ($extractedRevision.Length -gt 0)
        Test-Assertion -Name 'ProjectVersion extracted revision excludes open parenthesis' -Condition (-not $extractedRevision.Contains('('))
        Test-Assertion -Name 'ProjectVersion extracted revision excludes close parenthesis' -Condition (-not $extractedRevision.Contains(')'))
    }

    $multiCheck = $definitions | Where-Object { $_.Value.definitionId -eq 'specops-core-contract-integrity' }
    $checkReordered = $multiCheck.Raw | ConvertFrom-Json -AsHashtable -Depth 100
    $first = $checkReordered.checks[0]
    $checkReordered.checks[0] = $checkReordered.checks[1]
    $checkReordered.checks[1] = $first
    $checkReorderedPath = [System.IO.Path]::Combine($temporaryRoot, 'check-reordered.json')
    Write-TemporaryJson -Path $checkReorderedPath -Value $checkReordered
    $canonicalIdentity = Get-SpecOpsJsonContentIdentity -Path $multiCheck.File.FullName -Mode EVAL_DEFINITION
    $checkReorderedIdentity = Get-SpecOpsJsonContentIdentity -Path $checkReorderedPath -Mode EVAL_DEFINITION
    Test-Assertion -Name 'check ordering is identity-significant' -Condition (-not [string]::Equals($canonicalIdentity.value, $checkReorderedIdentity.value, [System.StringComparison]::Ordinal))

    $configRaw = [System.IO.File]::ReadAllText($configPath)
    $config = $configRaw | ConvertFrom-Json -AsHashtable -Depth 100
    Test-Equal -Name 'config evalRoot' -Expected '.specops/evals' -Actual $config.paths.evalRoot
    Test-Equal -Name 'config evalDefinitionsPresent' -Expected $true -Actual $config.initialization.evalDefinitionsPresent
    Test-Equal -Name 'config evalPathStatus' -Expected 'installed' -Actual $config.initialization.evalPathStatus

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

[Console]::Out.WriteLine('PASS definition-validation tests=' + $script:TestCount + ' failures=0')
exit 0
