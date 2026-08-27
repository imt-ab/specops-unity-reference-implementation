[CmdletBinding()]
param(
    [switch] $CalculateIdentityOnly
)

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
        $script:Failures.Add($(if ($Detail) { "$Name`: $Detail" } else { $Name }))
    }
}

function Get-OrdinalSortedStrings {
    param([AllowEmptyCollection()] [string[]] $Values)

    $result = [string[]] @($Values)
    [Array]::Sort($result, [StringComparer]::Ordinal)
    return $result
}

function Test-OrdinalOrder {
    param([AllowEmptyCollection()] [string[]] $Values)

    $actual = [string[]] @($Values)
    if ($actual.Count -le 1) {
        return $true
    }
    $expected = Get-OrdinalSortedStrings $actual
    return [string]::Join("`0", $actual) -ceq [string]::Join("`0", $expected)
}

function Test-UniqueOrdinalStrings {
    param([AllowEmptyCollection()] [string[]] $Values)

    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($value in $Values) {
        if (-not $seen.Add($value)) { return $false }
    }
    return $true
}

function Test-OrdinalPathSetsDisjoint {
    param(
        [AllowEmptyCollection()] [string[]] $Left,
        [AllowEmptyCollection()] [string[]] $Right
    )

    $leftSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($path in $Left) { [void] $leftSet.Add($path) }
    foreach ($path in $Right) {
        if ($leftSet.Contains($path)) { return $false }
    }
    return $true
}

function Test-ClosedBootstrapRepositoryAccounting {
    param(
        [AllowEmptyCollection()] [string[]] $RepositoryPaths,
        [AllowEmptyCollection()] [string[]] $MetadataPaths,
        [AllowEmptyCollection()] [string[]] $AuthoredPaths,
        [AllowEmptyCollection()] [string[]] $ImplementationSupportPaths,
        [Parameter(Mandatory)] [string] $ImplementationSupportRoot
    )

    if (-not (Test-UniqueOrdinalStrings $RepositoryPaths) -or
        -not (Test-UniqueOrdinalStrings $MetadataPaths) -or
        -not (Test-UniqueOrdinalStrings $AuthoredPaths) -or
        -not (Test-UniqueOrdinalStrings $ImplementationSupportPaths)) { return $false }
    foreach ($path in $ImplementationSupportPaths) {
        if (-not $path.StartsWith($ImplementationSupportRoot, [StringComparison]::Ordinal)) { return $false }
    }

    $union = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($path in @($MetadataPaths) + @($AuthoredPaths) + @($ImplementationSupportPaths)) {
        if (-not $union.Add($path)) { return $false }
    }
    $repository = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($path in $RepositoryPaths) { [void] $repository.Add($path) }
    if ($repository.Count -ne $union.Count) { return $false }
    foreach ($path in $repository) {
        if (-not $union.Contains($path)) { return $false }
    }
    return $true
}

function Test-PathOrPrefixOverlap {
    param(
        [Parameter(Mandatory)] [string] $Left,
        [Parameter(Mandatory)] [string] $Right
    )

    $leftPath = $Left.TrimEnd('/')
    $rightPath = $Right.TrimEnd('/')
    return $leftPath.Equals($rightPath, [StringComparison]::Ordinal) -or
        $leftPath.StartsWith($rightPath + '/', [StringComparison]::Ordinal) -or
        $rightPath.StartsWith($leftPath + '/', [StringComparison]::Ordinal)
}

function Test-BootstrapImplementationDescriptor {
    param(
        [Parameter(Mandatory)] [byte[]] $Bytes,
        [Parameter(Mandatory)] [string] $ExpectedVersion
    )

    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        return $false
    }
    try {
        $text = [Text.UTF8Encoding]::new($false, $true).GetString($Bytes)
        $descriptor = $text | ConvertFrom-Json -Depth 10
    }
    catch {
        return $false
    }
    $properties = @($descriptor.PSObject.Properties)
    $expectedText = "{`n  `"implementationVersion`": `"$ExpectedVersion`"`n}`n"
    return $properties.Count -eq 1 -and
        $properties[0].Name -ceq 'implementationVersion' -and
        [string] $properties[0].Value -ceq $ExpectedVersion -and
        $ExpectedVersion -cmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$' -and
        $text -ceq $expectedText
}

function Get-OutputPath {
    param([Parameter(Mandatory)] $Entry)

    if ($Entry.output.PSObject.Properties['path']) {
        return [string] $Entry.output.path
    }
    return [string] $Entry.output.pathTemplate
}

function Test-JsonValueEqual {
    param($Left, $Right)

    return ($Left | ConvertTo-Json -Depth 100 -Compress) -ceq
        ($Right | ConvertTo-Json -Depth 100 -Compress)
}

function Get-JsonPointerValue {
    param(
        [Parameter(Mandatory)] $Root,
        [Parameter(Mandatory)] [string] $Pointer
    )

    $current = $Root
    foreach ($rawPart in $Pointer.TrimStart('/').Split('/')) {
        $part = $rawPart.Replace('~1', '/').Replace('~0', '~')
        if ($current -is [Array]) {
            $current = $current[[int] $part]
        }
        else {
            $current = $current.PSObject.Properties[$part].Value
        }
    }
    return $current
}

function Get-JsonStringTokenCount {
    param($Value, [Parameter(Mandatory)] [string] $Token)

    if ($Value -is [string]) {
        $count = 0
        $offset = 0
        while ($offset -le $Value.Length - $Token.Length) {
            $match = $Value.IndexOf($Token, $offset, [StringComparison]::Ordinal)
            if ($match -lt 0) { break }
            $count++
            $offset = $match + $Token.Length
        }
        return $count
    }
    if ($Value -is [Array]) {
        $count = 0
        foreach ($item in $Value) {
            $count += Get-JsonStringTokenCount -Value $item -Token $Token
        }
        return $count
    }
    if ($Value -is [pscustomobject]) {
        $count = 0
        foreach ($property in $Value.PSObject.Properties) {
            $count += Get-JsonStringTokenCount -Value $property.Value -Token $Token
        }
        return $count
    }
    return 0
}

function Get-JsonMemberNameOrStringTokenCount {
    param($Value, [Parameter(Mandatory)] [string] $Token)

    if ($Value -is [pscustomobject]) {
        $count = 0
        foreach ($property in $Value.PSObject.Properties) {
            $count += Get-JsonStringTokenCount -Value ([string] $property.Name) -Token $Token
            $count += Get-JsonMemberNameOrStringTokenCount -Value $property.Value -Token $Token
        }
        return $count
    }
    if ($Value -is [Array]) {
        $count = 0
        foreach ($item in $Value) {
            $count += Get-JsonMemberNameOrStringTokenCount -Value $item -Token $Token
        }
        return $count
    }
    return Get-JsonStringTokenCount -Value $Value -Token $Token
}

function ConvertTo-IndependentJcsString {
    param([AllowEmptyString()] [Parameter(Mandatory)] [string] $Value)

    $builder = [Text.StringBuilder]::new()
    [void] $builder.Append('"')
    foreach ($character in $Value.ToCharArray()) {
        $code = [int] $character
        switch ($code) {
            0x08 { [void] $builder.Append('\b'); continue }
            0x09 { [void] $builder.Append('\t'); continue }
            0x0A { [void] $builder.Append('\n'); continue }
            0x0C { [void] $builder.Append('\f'); continue }
            0x0D { [void] $builder.Append('\r'); continue }
            0x22 { [void] $builder.Append('\"'); continue }
            0x5C { [void] $builder.Append('\\'); continue }
        }
        if ($code -le 0x1F) {
            [void] $builder.Append('\u')
            [void] $builder.Append($code.ToString('x4', [Globalization.CultureInfo]::InvariantCulture))
        }
        else {
            [void] $builder.Append($character)
        }
    }
    [void] $builder.Append('"')
    return $builder.ToString()
}

function ConvertTo-IndependentJcsElement {
    param([Parameter(Mandatory)] [Text.Json.JsonElement] $Element)

    switch ($Element.ValueKind) {
        ([Text.Json.JsonValueKind]::Object) {
            $properties = [Collections.Generic.SortedDictionary[string, Text.Json.JsonElement]]::new([StringComparer]::Ordinal)
            foreach ($property in $Element.EnumerateObject()) {
                $properties.Add($property.Name, $property.Value)
            }
            $parts = [Collections.Generic.List[string]]::new()
            foreach ($entry in $properties.GetEnumerator()) {
                $parts.Add((ConvertTo-IndependentJcsString $entry.Key) + ':' + (ConvertTo-IndependentJcsElement $entry.Value))
            }
            return '{' + [string]::Join(',', $parts) + '}'
        }
        ([Text.Json.JsonValueKind]::Array) {
            $parts = [Collections.Generic.List[string]]::new()
            foreach ($item in $Element.EnumerateArray()) {
                $parts.Add((ConvertTo-IndependentJcsElement $item))
            }
            return '[' + [string]::Join(',', $parts) + ']'
        }
        ([Text.Json.JsonValueKind]::String) {
            return ConvertTo-IndependentJcsString $Element.GetString()
        }
        ([Text.Json.JsonValueKind]::Number) {
            $raw = $Element.GetRawText()
            if ($raw -notmatch '^-?(?:0|[1-9][0-9]*)$') {
                throw "The F3 manifest uses an unsupported non-integer number: $raw"
            }
            return $raw
        }
        ([Text.Json.JsonValueKind]::True) { return 'true' }
        ([Text.Json.JsonValueKind]::False) { return 'false' }
        ([Text.Json.JsonValueKind]::Null) { return 'null' }
        default { throw 'Unsupported JSON token in F3 manifest.' }
    }
}

function Get-SourceIdentityDigests {
    param(
        [string] $ManifestPath,
        [string] $ManifestJson,
        [Parameter(Mandatory)] [string] $RepositoryRoot
    )

    if ([string]::IsNullOrEmpty($ManifestJson)) {
        if ([string]::IsNullOrEmpty($ManifestPath)) { throw 'ManifestPath or ManifestJson is required.' }
        $ManifestJson = Get-Content -LiteralPath $ManifestPath -Raw
    }
    $manifestObject = $ManifestJson | ConvertFrom-Json -Depth 100
    if ($null -ne $manifestObject.sourceIdentity.PSObject.Properties['digest']) {
        $manifestObject.sourceIdentity.PSObject.Properties.Remove('digest')
    }
    $calculationJson = $manifestObject | ConvertTo-Json -Depth 100 -Compress
    $calculationBytes = [Text.UTF8Encoding]::new($false, $true).GetBytes($calculationJson)

    Import-Module (Join-Path $RepositoryRoot 'tools/specops/SpecOps.Core.psm1') -Force
    $primaryCanonical = ConvertTo-SpecOpsCanonicalJson -Bytes $calculationBytes -Mode FULL_JSON
    $primaryDigest = [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData([Text.UTF8Encoding]::new($false, $true).GetBytes($primaryCanonical))
    ).ToLowerInvariant()

    $document = [Text.Json.JsonDocument]::Parse($calculationJson)
    try {
        $independentCanonical = ConvertTo-IndependentJcsElement $document.RootElement
    }
    finally {
        $document.Dispose()
    }
    $independentDigest = [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData([Text.UTF8Encoding]::new($false, $true).GetBytes($independentCanonical))
    ).ToLowerInvariant()

    return [pscustomobject]@{
        Primary = $primaryDigest
        Independent = $independentDigest
        CanonicalBytesEqual = $primaryCanonical -ceq $independentCanonical
    }
}

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$manifestPath = Join-Path $repositoryRoot '.specops/bootstrap/bootstrap-v1.projection-manifest.json'
$manifestSchemaPath = Join-Path $repositoryRoot '.specops/contracts/bootstrap-projection-manifest.schema.json'
$provenanceSchemaPath = Join-Path $repositoryRoot '.specops/contracts/bootstrap-provenance.schema.json'
$implementationDescriptorPath = Join-Path $repositoryRoot 'tools/specops/bootstrap/bootstrap-implementation.json'
$manifestJson = Get-Content -LiteralPath $manifestPath -Raw
$manifest = $manifestJson | ConvertFrom-Json -Depth 100
$manifestSchemaValid = Test-Json -Json $manifestJson -SchemaFile $manifestSchemaPath -ErrorAction Stop
$storedDigestValid = $null -ne $manifest.sourceIdentity.PSObject.Properties['digest'] -and
    [string] $manifest.sourceIdentity.digest -cmatch '^[0-9a-f]{64}$'

Test-Assertion 'manifest schema conformance' $manifestSchemaValid
Test-Assertion 'stored manifest has one final Source Identity digest' $storedDigestValid

Import-Module (Join-Path $repositoryRoot 'tools/specops/SpecOps.Eval.psm1') -Force
$schemaCapability = Get-SpecOpsSchemaAdapterCapability
$schemaDocumentsValid = $schemaCapability.Available -and $schemaCapability.Draft202012 -and $schemaCapability.SchemaDocuments
foreach ($schemaPath in @($manifestSchemaPath, $provenanceSchemaPath)) {
    $validation = & (Get-Module SpecOps.Eval) {
        param($Json, $Capability)
        Test-SpecOpsDraft202012SchemaDocument $Json $Capability
    } (Get-Content -LiteralPath $schemaPath -Raw) $schemaCapability
    $schemaDocumentsValid = $schemaDocumentsValid -and $validation.Executable -and $validation.Valid
}
Test-Assertion 'new schemas validate as Draft 2020-12 documents' $schemaDocumentsValid $schemaCapability.Detail

$workspacePaths = [string[]] @(
    git -C $repositoryRoot ls-files --cached --others --exclude-standard |
        Where-Object { Test-Path -LiteralPath (Join-Path $repositoryRoot $_) -PathType Leaf }
)
$workspacePaths = Get-OrdinalSortedStrings $workspacePaths
$metadataPaths = [string[]] @($manifest.bootstrapSourceMetadata.path)
$authoredPaths = [string[]] @($manifest.authoredSourceInventory.sourcePath)
$implementationSupportRoot = [string] $manifest.bootstrapImplementationSupport.root
$implementationSupportPaths = [string[]] @($workspacePaths | Where-Object {
    $_.StartsWith($implementationSupportRoot, [StringComparison]::Ordinal)
})
$closedAccountingArguments = @{
    RepositoryPaths = $workspacePaths
    MetadataPaths = $metadataPaths
    AuthoredPaths = $authoredPaths
    ImplementationSupportPaths = $implementationSupportPaths
    ImplementationSupportRoot = $implementationSupportRoot
}
$closedAccountingValid = Test-ClosedBootstrapRepositoryAccounting @closedAccountingArguments
Test-Assertion 'three-way closed source accounting' $closedAccountingValid
Test-Assertion 'source accounting categories are mutually exclusive' (
    (Test-OrdinalPathSetsDisjoint $metadataPaths $authoredPaths) -and
    (Test-OrdinalPathSetsDisjoint $metadataPaths $implementationSupportPaths) -and
    (Test-OrdinalPathSetsDisjoint $authoredPaths $implementationSupportPaths)
)

$futureSupportPath = 'tools/specops/bootstrap/FutureImplementationSupportFixture.ps1'
$futureSupportWorkspacePaths = [string[]] @($workspacePaths + $futureSupportPath)
$futureSupportPaths = [string[]] @($implementationSupportPaths + $futureSupportPath)
$identityBeforeFutureSupport = Get-SourceIdentityDigests -ManifestJson $manifestJson -RepositoryRoot $repositoryRoot
$identityAfterFutureSupport = Get-SourceIdentityDigests -ManifestJson $manifestJson -RepositoryRoot $repositoryRoot
$futureSupportArguments = @{
    RepositoryPaths = $futureSupportWorkspacePaths
    MetadataPaths = $metadataPaths
    AuthoredPaths = $authoredPaths
    ImplementationSupportPaths = $futureSupportPaths
    ImplementationSupportRoot = $implementationSupportRoot
}
Test-Assertion 'future implementation-support file is accepted without changing logical Source Identity' (
    (Test-ClosedBootstrapRepositoryAccounting @futureSupportArguments) -and
    $identityBeforeFutureSupport.Primary -ceq $identityAfterFutureSupport.Primary -and
    $identityBeforeFutureSupport.Independent -ceq $identityAfterFutureSupport.Independent
)

foreach ($unexpectedPath in @('unexpected-file.txt', 'tools/specops/SomeOtherUndeclaredTool.ps1')) {
    $unexpectedSourceArguments = @{
        RepositoryPaths = [string[]] @($workspacePaths + $unexpectedPath)
        MetadataPaths = $metadataPaths
        AuthoredPaths = $authoredPaths
        ImplementationSupportPaths = $implementationSupportPaths
        ImplementationSupportRoot = $implementationSupportRoot
    }
    Test-Assertion "undeclared source is rejected: $unexpectedPath" (-not (
        Test-ClosedBootstrapRepositoryAccounting @unexpectedSourceArguments
    ))
}
$outsideSupportArguments = @{
    RepositoryPaths = [string[]] @($workspacePaths + 'tools/specops/SomeOtherUndeclaredTool.ps1')
    MetadataPaths = $metadataPaths
    AuthoredPaths = $authoredPaths
    ImplementationSupportPaths = [string[]] @(
        $implementationSupportPaths + 'tools/specops/SomeOtherUndeclaredTool.ps1'
    )
    ImplementationSupportRoot = $implementationSupportRoot
}
Test-Assertion 'implementation support outside approved root is rejected' (-not (
    Test-ClosedBootstrapRepositoryAccounting @outsideSupportArguments
))

$declaredProjectionPaths = [string[]] @(
    $metadataPaths +
    $authoredPaths +
    @($manifest.authoredSourceInventory | Where-Object disposition -ne 'EXCLUDE' | ForEach-Object { Get-OutputPath $_ }) +
    @($manifest.generatedOutputInventory.outputPath)
)
$supportBoundaryDisjoint = $true
foreach ($path in $declaredProjectionPaths) {
    if (Test-PathOrPrefixOverlap $implementationSupportRoot $path) { $supportBoundaryDisjoint = $false }
}
Test-Assertion 'implementation-support root cannot overlap source or output declarations' (
    $supportBoundaryDisjoint -and
    (Test-PathOrPrefixOverlap $implementationSupportRoot ($implementationSupportRoot + 'synthetic-output.json'))
)

$descriptorBytes = [IO.File]::ReadAllBytes($implementationDescriptorPath)
Test-Assertion 'implementation descriptor is deterministic UTF-8 and version 1.0.0' (
    (Test-BootstrapImplementationDescriptor -Bytes $descriptorBytes -ExpectedVersion '1.0.0') -and
    $implementationSupportPaths -ccontains 'tools/specops/bootstrap/bootstrap-implementation.json'
)
$ambientDescriptorBytes = [Text.UTF8Encoding]::new($false, $true).GetBytes(
    "{`n  `"implementationVersion`": `"1.0.0`",`n  `"gitCommit`": `"ambient`"`n}`n"
)
Test-Assertion 'implementation descriptor rejects ambient-state fields' (-not (
    Test-BootstrapImplementationDescriptor -Bytes $ambientDescriptorBytes -ExpectedVersion '1.0.0'
))

$dispositionGroups = @{}
$manifest.authoredSourceInventory | Group-Object disposition | ForEach-Object { $dispositionGroups[$_.Name] = $_.Count }
Test-Assertion 'one disposition per authored source' (
    $manifest.authoredSourceInventory.Count -eq 394 -and
    $dispositionGroups.COPY_EXACT -eq 276 -and
    $dispositionGroups.TRANSFORM_SCOPED -eq 35 -and
    $dispositionGroups.EXCLUDE -eq 83
)

$inventoryByPath = @{}
foreach ($entry in $manifest.authoredSourceInventory) { $inventoryByPath[$entry.sourcePath] = $entry }
$vcsBoundTools = @(
    'tools/specops/Invoke-SpecOps.ps1',
    'tools/specops/SpecOps.Eval.psm1',
    'tools/specops/SpecOps.Repository.psm1',
    'tools/specops/SpecOps.Unity.psm1'
)
$vcsNeutralToolsValid = $true
foreach ($path in $vcsBoundTools) {
    $entry = $inventoryByPath[$path]
    $vcsNeutralToolsValid = $vcsNeutralToolsValid -and
        $entry.disposition -ceq 'EXCLUDE' -and
        $entry.projectionRole -ceq 'VCS_HOSTING_SPECIFIC' -and
        $null -eq $entry.PSObject.Properties['output'] -and
        $null -eq $entry.PSObject.Properties['transforms']
}
$coreEntry = $inventoryByPath['tools/specops/SpecOps.Core.psm1']
$coreText = Get-Content -LiteralPath (Join-Path $repositoryRoot $coreEntry.sourcePath) -Raw
$vcsNeutralToolsValid = $vcsNeutralToolsValid -and
    $coreEntry.disposition -ceq 'COPY_EXACT' -and
    $coreEntry.projectionRole -ceq 'REUSABLE_CHILD_CONTENT' -and
    $coreText -notmatch '(?i)SpecOps\.(?:Repository|Eval|Unity)\.psm1|New-SpecOpsGitRepositoryAdapter|\bgit\b'
$dependencyEvidence =
    (Get-Content -LiteralPath (Join-Path $repositoryRoot 'tools/specops/Invoke-SpecOps.ps1') -Raw) -cmatch 'New-SpecOpsGitRepositoryAdapter' -and
    (Get-Content -LiteralPath (Join-Path $repositoryRoot 'tools/specops/SpecOps.Eval.psm1') -Raw) -cmatch 'Import-Module -Name \$script:RepositoryPath' -and
    (Get-Content -LiteralPath (Join-Path $repositoryRoot 'tools/specops/SpecOps.Repository.psm1') -Raw) -cmatch "FileName = 'git'" -and
    (Get-Content -LiteralPath (Join-Path $repositoryRoot 'tools/specops/SpecOps.Unity.psm1') -Raw) -cmatch "-FilePath 'git'" -and
    ([string] ((Get-Content -LiteralPath (Join-Path $repositoryRoot 'Packages/manifest.json') -Raw |
        ConvertFrom-Json -Depth 100).dependencies.'jp.hadashikick.vcontainer') -match '\.git(?:\?|#|$)')
$retainedInstructionPaths = @($manifest.authoredSourceInventory | Where-Object {
    $_.disposition -ne 'EXCLUDE' -and
    ($_.sourcePath -ceq 'AGENTS.md' -or $_.sourcePath.StartsWith('.agents/skills/', [StringComparison]::Ordinal))
})
foreach ($entry in $retainedInstructionPaths) {
    $instructionText = Get-Content -LiteralPath (Join-Path $repositoryRoot $entry.sourcePath) -Raw
    $vcsNeutralToolsValid = $vcsNeutralToolsValid -and
        $instructionText -notmatch 'Invoke-SpecOps\.ps1|SpecOps\.(?:Repository|Eval|Unity)\.psm1|New-SpecOpsGitRepositoryAdapter'
}
Test-Assertion 'VCS-neutral retained tooling has no Git-bound command or unsatisfied module dependency' (
    $vcsNeutralToolsValid -and $dependencyEvidence
)
Test-Assertion 'generated output inventory is complete' (
    $manifest.generatedOutputInventory.Count -eq 1 -and
    $manifest.generatedOutputInventory[0].outputPath -ceq '.specops/bootstrap.json' -and
    $manifest.generatedOutputInventory[0].disposition -ceq 'GENERATE_DETERMINISTIC'
)

$orderingValid = (Test-OrdinalOrder $manifest.bootstrapSourceMetadata.path) -and
    (Test-OrdinalOrder $manifest.authoredSourceInventory.sourcePath) -and
    (Test-OrdinalOrder $manifest.generatedOutputInventory.outputPath)
foreach ($entry in $manifest.authoredSourceInventory | Where-Object disposition -eq 'TRANSFORM_SCOPED') {
    $orderingValid = $orderingValid -and (Test-OrdinalOrder $entry.transforms.id)
    foreach ($transform in $entry.transforms) {
        $orderingValid = $orderingValid -and (Test-OrdinalOrder $transform.forbiddenResidualValues)
        if ($transform.replacement.PSObject.Properties['inputs']) {
            $orderingValid = $orderingValid -and (Test-OrdinalOrder $transform.replacement.inputs)
        }
    }
}
$generated = $manifest.generatedOutputInventory[0]
$orderingValid = $orderingValid -and
    (Test-OrdinalOrder $generated.allowedSemanticInputs) -and
    (Test-OrdinalOrder $generated.approvedConstants) -and
    (Test-OrdinalOrder $generated.postconditions.id) -and
    (Test-OrdinalOrder $generated.verificationRequirements) -and
    (Test-OrdinalOrder $manifest.staticInvariants.prohibitedOutputPrefixes) -and
    (Test-OrdinalOrder $manifest.staticInvariants.prohibitedOutputPaths)
Test-Assertion 'canonical manifest array order' $orderingValid

$hashesValid = $true
$sourcePaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($entry in $manifest.authoredSourceInventory) {
    $hashesValid = $hashesValid -and $sourcePaths.Add($entry.sourcePath)
    $bytes = [IO.File]::ReadAllBytes((Join-Path $repositoryRoot $entry.sourcePath))
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    $hashesValid = $hashesValid -and
        $entry.byteIdentity.byteLength -eq $bytes.Length -and
        $entry.byteIdentity.sha256 -ceq $hash
}
Test-Assertion 'exact authored source hashes' $hashesValid

$schemaMetadata = $manifest.bootstrapSourceMetadata | Where-Object role -eq 'PROJECTION_MANIFEST_SCHEMA'
$schemaBytes = [IO.File]::ReadAllBytes($manifestSchemaPath)
$schemaHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($schemaBytes)).ToLowerInvariant()
Test-Assertion 'non-recursive source metadata boundary' (
    $manifest.bootstrapSourceMetadata.Count -eq 2 -and
    -not ($manifest.authoredSourceInventory.sourcePath -contains '.specops/bootstrap/bootstrap-v1.projection-manifest.json') -and
    -not ($manifest.authoredSourceInventory.sourcePath -contains '.specops/contracts/bootstrap-projection-manifest.schema.json') -and
    $schemaMetadata.byteIdentity.byteLength -eq $schemaBytes.Length -and
    $schemaMetadata.byteIdentity.sha256 -ceq $schemaHash
)

$outputs = [Collections.Generic.List[string]]::new()
foreach ($entry in $manifest.authoredSourceInventory | Where-Object disposition -ne 'EXCLUDE') {
    $outputs.Add((Get-OutputPath $entry))
}
foreach ($output in $manifest.generatedOutputInventory) { $outputs.Add($output.outputPath) }
$ordinalOutputs = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$windowsOutputs = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$collisionsAbsent = $true
foreach ($output in $outputs) {
    $collisionsAbsent = $collisionsAbsent -and $ordinalOutputs.Add($output) -and $windowsOutputs.Add($output)
}
foreach ($left in $outputs) {
    foreach ($right in $outputs) {
        if ($left -cne $right -and $right.StartsWith($left + '/', [StringComparison]::OrdinalIgnoreCase)) {
            $collisionsAbsent = $false
        }
    }
}
Test-Assertion 'output collisions and file-prefix conflicts absent' $collisionsAbsent

$prohibitedOutputsAbsent = $true
foreach ($output in $outputs) {
    foreach ($prefix in $manifest.staticInvariants.prohibitedOutputPrefixes) {
        if ($output.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { $prohibitedOutputsAbsent = $false }
    }
    foreach ($path in $manifest.staticInvariants.prohibitedOutputPaths) {
        if ($output -ceq $path) { $prohibitedOutputsAbsent = $false }
    }
}
Test-Assertion 'prohibited and transient outputs absent' $prohibitedOutputsAbsent

$emittedBySource = @{}
foreach ($entry in $manifest.authoredSourceInventory | Where-Object disposition -ne 'EXCLUDE') {
    $emittedBySource[$entry.sourcePath] = $entry
}
$retainedMetas = @($manifest.authoredSourceInventory | Where-Object {
    $_.sourcePath.EndsWith('.meta', [StringComparison]::Ordinal) -and $_.disposition -ne 'EXCLUDE'
})
$guids = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$metaValid = $retainedMetas.Count -eq 153
foreach ($meta in $retainedMetas) {
    $match = @(Select-String -LiteralPath (Join-Path $repositoryRoot $meta.sourcePath) -Pattern '^guid: ([0-9a-f]{32})$' -CaseSensitive)
    $metaValid = $metaValid -and $meta.disposition -ceq 'COPY_EXACT' -and $match.Count -eq 1
    if ($match.Count -eq 1) { $metaValid = $metaValid -and $guids.Add($match.Matches[0].Groups[1].Value) }
    $assetSource = $meta.sourcePath.Substring(0, $meta.sourcePath.Length - 5)
    if (Test-Path -LiteralPath (Join-Path $repositoryRoot $assetSource) -PathType Leaf) {
        $metaValid = $metaValid -and $emittedBySource.ContainsKey($assetSource)
        if ($emittedBySource.ContainsKey($assetSource)) {
            $metaValid = $metaValid -and
                (Get-OutputPath $meta) -ceq ((Get-OutputPath $emittedBySource[$assetSource]) + '.meta')
        }
    }
    else {
        $metaValid = $metaValid -and @($outputs | Where-Object {
            $_.StartsWith($assetSource + '/', [StringComparison]::Ordinal)
        }).Count -gt 0
    }
}
foreach ($asset in $manifest.authoredSourceInventory | Where-Object {
    $_.sourcePath.StartsWith('Assets/', [StringComparison]::Ordinal) -and
    -not $_.sourcePath.EndsWith('.meta', [StringComparison]::Ordinal) -and
    $_.disposition -ne 'EXCLUDE'
}) {
    $metaValid = $metaValid -and $emittedBySource.ContainsKey($asset.sourcePath + '.meta')
}
$renamedEntries = @($manifest.authoredSourceInventory | Where-Object {
    $_.disposition -ne 'EXCLUDE' -and $_.output.PSObject.Properties['pathTemplate']
})
Test-Assertion 'Unity metadata pairing, GUIDs, and exact rename pairs' ($metaValid -and $renamedEntries.Count -eq 20)

$projectVersion = Get-Content -LiteralPath (Join-Path $repositoryRoot 'ProjectSettings/ProjectVersion.txt') -Raw
$playerSettings = Get-Content -LiteralPath (Join-Path $repositoryRoot 'ProjectSettings/ProjectSettings.asset') -Raw
Test-Assertion 'Unity project baseline is exact' (
    $projectVersion -ceq "m_EditorVersion: 6000.5.8f1`nm_EditorVersionWithRevision: 6000.5.8f1 (5cb7df797b7d)`n" -and
    [regex]::Matches($playerSettings, '(?m)^  runInBackground: 1\r?$').Count -eq 1
)

$packageManifest = Get-Content -LiteralPath (Join-Path $repositoryRoot 'Packages/manifest.json') -Raw | ConvertFrom-Json -Depth 100
$packageLock = Get-Content -LiteralPath (Join-Path $repositoryRoot 'Packages/packages-lock.json') -Raw | ConvertFrom-Json -Depth 100
$direct = Get-OrdinalSortedStrings ([string[]] $packageManifest.dependencies.PSObject.Properties.Name)
$depthZero = Get-OrdinalSortedStrings ([string[]] @(
    $packageLock.dependencies.PSObject.Properties | Where-Object { $_.Value.depth -eq 0 } | ForEach-Object Name
))
$packagesValid = [string]::Join("`0", $direct) -ceq [string]::Join("`0", $depthZero)
foreach ($name in $direct) {
    $packagesValid = $packagesValid -and
        [string] $packageManifest.dependencies.$name -ceq [string] $packageLock.dependencies.$name.version
}
Test-Assertion 'package manifest and depth-zero lock are consistent' $packagesValid

$sampleProvenance = [ordered]@{
    contractVersion = '1.0.0'
    classification = 'DERIVED_BOOTSTRAP_PROVENANCE'
    authorityStatus = 'NON_AUTHORITATIVE'
    evidenceStatus = 'NON_RELEASE_EVIDENCE'
    sourceBaseline = [ordered]@{
        id = 'specops-unity-clean-architecture-golden-baseline'
        version = '2.0.0'
        sourceIdentity = [ordered]@{ profile = 'specops-bootstrap-source-jcs-sha256-v1'; digest = ('a' * 64) }
    }
    bootstrap = [ordered]@{ contractVersion = '1.0.0'; implementationVersion = '1.0.0' }
    contentInputs = [ordered]@{
        ProjectId = 'sample-project'
        ProductName = 'Sample Product'
        CompanyName = 'Sample Company'
        ApplicationIdentifier = 'com.sample.project'
        CodeNamespaceRoot = 'Sample.Project'
    }
} | ConvertTo-Json -Depth 20 -Compress
$provenanceValid = Test-Json -Json $sampleProvenance -SchemaFile $provenanceSchemaPath -ErrorAction Stop
$invalidProvenance = $sampleProvenance | ConvertFrom-Json -Depth 20
$invalidProvenance | Add-Member DestinationPath 'C:\Temp\Child'
$provenanceValid = $provenanceValid -and -not (
    Test-Json -Json ($invalidProvenance | ConvertTo-Json -Depth 20 -Compress) -SchemaFile $provenanceSchemaPath -ErrorAction SilentlyContinue
)
Test-Assertion 'provenance schema accepts only deterministic lineage fields' $provenanceValid

$jsonSegmentTransforms = @(
    $manifest.authoredSourceInventory | Where-Object disposition -eq 'TRANSFORM_SCOPED' | ForEach-Object {
        $_.transforms | Where-Object {
            $_.expectedSourceValue -ceq 'InfiniteMonkey' -and
            $_.selectorClass -in @('JSON_STRING_VALUE_TOKEN', 'JSON_MEMBER_NAME_OR_STRING_VALUE_TOKEN')
        }
    }
)
$selectorPrecisionValid = $jsonSegmentTransforms.Count -gt 0
foreach ($transform in $jsonSegmentTransforms) {
    $selectorPrecisionValid = $selectorPrecisionValid -and
        $transform.selector.Contains('exact ordinal substring segment InfiniteMonkey inside parsed JSON', [StringComparison]::Ordinal) -and
        -not $transform.selector.Contains('spans equal to InfiniteMonkey', [StringComparison]::Ordinal) -and
        $transform.postcondition.selector.Contains('exact ordinal substring segment InfiniteMonkey', [StringComparison]::Ordinal)
    if ($transform.selectorClass -ceq 'JSON_MEMBER_NAME_OR_STRING_VALUE_TOKEN') {
        $selectorPrecisionValid = $selectorPrecisionValid -and
            $transform.selector.Contains('including both member names and string values', [StringComparison]::Ordinal) -and
            $transform.postcondition.selector.Contains('member-name or string-value token', [StringComparison]::Ordinal)
    }
    else {
        $selectorPrecisionValid = $selectorPrecisionValid -and
            $transform.selector.Contains('string-value tokens', [StringComparison]::Ordinal)
    }
}
$projectionSchemaText = Get-Content -LiteralPath $manifestSchemaPath -Raw
$selectorPrecisionValid = $selectorPrecisionValid -and
    $projectionSchemaText.Contains('inside already parsed JSON member-name or string-value tokens', [StringComparison]::Ordinal) -and
    $projectionSchemaText.Contains('never authorize regex or raw-file replacement', [StringComparison]::Ordinal)
Test-Assertion 'JSON namespace selectors are exact parsed-token substring segments' $selectorPrecisionValid

$transformPreconditionsValid = $true
$transformFailures = [Collections.Generic.List[string]]::new()
foreach ($entry in $manifest.authoredSourceInventory | Where-Object disposition -eq 'TRANSFORM_SCOPED') {
    $bytes = [IO.File]::ReadAllBytes((Join-Path $repositoryRoot $entry.sourcePath))
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $transformPreconditionsValid = $false
        $transformFailures.Add("BOM: $($entry.sourcePath)")
    }
    $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
    $json = $null
    if ($entry.sourcePath.EndsWith('.json') -or $entry.sourcePath.EndsWith('.asmdef')) {
        $json = $text | ConvertFrom-Json -Depth 100
    }
    foreach ($transform in $entry.transforms) {
        $actual = -1
        switch ($transform.selectorClass) {
            'TEXT_UTF8_EXACT_SPAN' { $actual = [regex]::Matches($text, [regex]::Escape([string] $transform.expectedSourceValue)).Count }
            'TEXT_UTF8_TOKEN' { $actual = [regex]::Matches($text, [regex]::Escape([string] $transform.expectedSourceValue)).Count }
            'CSHARP_UTF8_TOKEN' { $actual = [regex]::Matches($text, [regex]::Escape([string] $transform.expectedSourceValue)).Count }
            'JSON_STRING_VALUE_TOKEN' {
                $actual = Get-JsonStringTokenCount -Value $json -Token ([string] $transform.expectedSourceValue)
                if ($transform.selector.Contains('ten string values removed', [StringComparison]::Ordinal)) { $actual -= 10 }
            }
            'JSON_MEMBER_NAME_OR_STRING_VALUE_TOKEN' {
                $actual = Get-JsonMemberNameOrStringTokenCount -Value $json -Token ([string] $transform.expectedSourceValue)
            }
            'JSON_POINTER_VALUE' { $actual = if (Test-JsonValueEqual (Get-JsonPointerValue $json $transform.selector) $transform.expectedSourceValue) { 1 } else { 0 } }
            'JSON_POINTER_MEMBER' { $actual = if (Test-JsonValueEqual (Get-JsonPointerValue $json $transform.selector) $transform.expectedSourceValue) { 1 } else { 0 } }
            'EVAL_DEFINITION_CONTENT_IDENTITY' { $actual = if ((Get-JsonPointerValue $json $transform.selector) -ceq [string] $transform.expectedSourceValue) { 1 } else { 0 } }
            'JSON_ARRAY_ITEMS_BY_EXACT_VALUE' {
                $array = Get-JsonPointerValue $json $transform.selector
                $actual = 0
                if ($transform.expectedSourceValue -is [Array]) {
                    foreach ($expected in $transform.expectedSourceValue) {
                        $actual += @($array | Where-Object { Test-JsonValueEqual $_ $expected }).Count
                    }
                }
                else { $actual = @($array | Where-Object { Test-JsonValueEqual $_ $transform.expectedSourceValue }).Count }
            }
            'UNITY_YAML_SCALAR' {
                $key = $transform.selector.Split('/')[-1]
                $matches = [regex]::Matches($text, '(?m)^\s+' + [regex]::Escape($key) + ': ?(.*)\r?$')
                $actual = @($matches | Where-Object { $_.Groups[1].Value -ceq [string] $transform.expectedSourceValue }).Count
            }
        }
        if ($actual -ne $transform.expectedMatchCount) {
            $transformPreconditionsValid = $false
            $transformFailures.Add("$($entry.sourcePath)/$($transform.id): expected $($transform.expectedMatchCount), actual $actual")
        }
    }
}
Test-Assertion 'transform source preconditions and exact counts' $transformPreconditionsValid ($transformFailures -join '; ')

$inventoryByPath = @{}
foreach ($entry in $manifest.authoredSourceInventory) { $inventoryByPath[$entry.sourcePath] = $entry }
$referenceCouplingAccounted = $true
foreach ($term in @('reference-architecture-example', 'ReferenceMessage', 'ReferenceLifetimeScope', 'FixedReferenceTextSource', 'ReferenceCompositionTests')) {
    foreach ($rawPath in @(rg -l --hidden --glob '!.git/**' --fixed-strings -- $term $repositoryRoot)) {
        $path = [IO.Path]::GetRelativePath($repositoryRoot, $rawPath).Replace('\', '/')
        if ($path -in @(
            '.specops/bootstrap/bootstrap-v1.projection-manifest.json',
            '.specops/contracts/bootstrap-projection-manifest.schema.json',
            'tools/specops/tests/SpecOps.BootstrapProjection.Tests.ps1'
        )) { continue }
        $entry = $inventoryByPath[$path]
        if ($null -eq $entry) { $referenceCouplingAccounted = $false }
        elseif ($entry.disposition -eq 'EXCLUDE') { }
        elseif ($path -ceq '.specops/contracts/bootstrap-v1.md') { }
        elseif ($entry.disposition -eq 'TRANSFORM_SCOPED') { }
        else { $referenceCouplingAccounted = $false }
    }
}
Test-Assertion 'reference feature coupling is excluded or explicitly transformed' $referenceCouplingAccounted

Import-Module (Join-Path $repositoryRoot 'tools/specops/SpecOps.Core.psm1') -Force
$evalIdentitiesValid = $true
foreach ($evalPath in @(git -C $repositoryRoot ls-files '.specops/evals/*.eval.json')) {
    $definition = Get-Content -LiteralPath (Join-Path $repositoryRoot $evalPath) -Raw | ConvertFrom-Json -Depth 100
    $identity = Get-SpecOpsJsonContentIdentity -Path (Join-Path $repositoryRoot $evalPath) -Mode EVAL_DEFINITION
    $evalIdentitiesValid = $evalIdentitiesValid -and $identity.value -ceq $definition.contentIdentity.value
}
Test-Assertion 'unchanged source eval definition identities remain valid' $evalIdentitiesValid

if ($script:Failures.Count -gt 0) {
    [pscustomobject]@{
        Result = 'FAIL'
        Tests = $script:TestCount
        Failures = @($script:Failures)
        SourceIdentity = $null
    } | ConvertTo-Json -Depth 10
    exit 1
}

$candidateManifest = $manifestJson | ConvertFrom-Json -Depth 100
$candidateManifest.sourceIdentity.PSObject.Properties.Remove('digest')
$candidateJson = $candidateManifest | ConvertTo-Json -Depth 100 -Compress
$candidateSchemaValid = Test-Json -Json $candidateJson -SchemaFile $manifestSchemaPath -ErrorAction Stop
$candidateDigests = Get-SourceIdentityDigests -ManifestJson $candidateJson -RepositoryRoot $repositoryRoot
$identityDigests = Get-SourceIdentityDigests -ManifestJson $manifestJson -RepositoryRoot $repositoryRoot
Test-Assertion 'initial Source Identity construction requires no placeholder or iterative self-hash' (
    $candidateSchemaValid -and
    $null -eq $candidateManifest.sourceIdentity.PSObject.Properties['digest'] -and
    $candidateDigests.CanonicalBytesEqual -and
    $candidateDigests.Primary -ceq $candidateDigests.Independent -and
    $candidateDigests.Primary -ceq $identityDigests.Primary -and
    $candidateDigests.Independent -ceq $identityDigests.Independent
)
Test-Assertion 'Source Identity profile is exact' ($manifest.sourceIdentity.profile -ceq 'specops-bootstrap-source-jcs-sha256-v1')
Test-Assertion 'independent Source Identity canonicalization agrees' (
    $identityDigests.CanonicalBytesEqual -and $identityDigests.Primary -ceq $identityDigests.Independent
)
Test-Assertion 'stored Source Identity digest is reproducible' (
    $manifest.sourceIdentity.digest -ceq $identityDigests.Primary
) "stored=$($manifest.sourceIdentity.digest) calculated=$($identityDigests.Primary)"

if ($script:Failures.Count -gt 0) {
    [pscustomobject]@{
        Result = 'FAIL'
        Tests = $script:TestCount
        Failures = @($script:Failures)
        SourceIdentity = $identityDigests.Primary
    } | ConvertTo-Json -Depth 10
    exit 1
}

if ($CalculateIdentityOnly) {
    $identityDigests | ConvertTo-Json
    exit 0
}

[pscustomobject]@{
    Result = 'PASS'
    Tests = $script:TestCount
    Failures = @()
    SourceIdentity = $identityDigests.Primary
    BootstrapSourceMetadataCount = $metadataPaths.Count
    AuthoredSourceCount = $manifest.authoredSourceInventory.Count
    BootstrapImplementationSupportCount = $implementationSupportPaths.Count
    RepositoryRegularLeafCount = $workspacePaths.Count
    CopyExactCount = $dispositionGroups.COPY_EXACT
    TransformScopedCount = $dispositionGroups.TRANSFORM_SCOPED
    ExcludeCount = $dispositionGroups.EXCLUDE
    GeneratedOutputCount = $manifest.generatedOutputInventory.Count
    OutputCount = $outputs.Count
    RetainedMetaCount = $retainedMetas.Count
    RenamedAssetMetaPairs = $renamedEntries.Count / 2
} | ConvertTo-Json -Depth 10
