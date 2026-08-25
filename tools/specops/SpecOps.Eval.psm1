Set-StrictMode -Version Latest

$script:CorePath = [System.IO.Path]::Combine($PSScriptRoot, 'SpecOps.Core.psm1')
$script:RepositoryPath = [System.IO.Path]::Combine($PSScriptRoot, 'SpecOps.Repository.psm1')
Import-Module -Name $script:CorePath -Force -ErrorAction Stop
Import-Module -Name $script:RepositoryPath -Force -ErrorAction Stop

$script:ProfileId = 'specops-json-jcs-sha256-v1'
$script:DefinitionContractVersion = '1.0.0'
$script:Utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
$script:SupportedDefinitionIdentities = [ordered]@{
    'specops-core-contract-integrity' = 'c9406453833d46e6813186cfbae5ba249a0c8e7c76af460b292073412cd23dd2'
    'specops-derived-state-consistency' = '4702aae1c11777990afab0073fbe35f07e86611d0837b3748998f8801a9c5612'
    'unity-clean-architecture-static' = 'aa07fa7eb27c04755372b981fb330646d1f3b9378f422336c24080368d87d64f'
    'unity-editmode-validation' = 'e1b74181d6229313d9c379d51b095325bdfc924ceea6e98436fd0db3dd233033'
}
$script:ProducerPaths = @(
    'tools/specops/Invoke-SpecOps.ps1',
    'tools/specops/SpecOps.Core.psm1',
    'tools/specops/SpecOps.Repository.psm1',
    'tools/specops/SpecOps.Eval.psm1'
)
$script:UnityCheckIds = @(
    'unity-version-match',
    'unity-compilation-success',
    'editmode-suite-executed',
    'editmode-required-tests-discovered',
    'editmode-zero-failures',
    'unity-exit-success',
    'unity-tracked-state-preserved'
)
$script:E8C3CheckIds = @(
    'contracts-json-parse',
    'contracts-id-unique',
    'contracts-version-consistent',
    'contracts-draft-declared',
    'contracts-references-resolve',
    'contracts-schema-valid',
    'authority-routes-resolve',
    'feature-authority-triplets',
    'feature-state-schema-valid',
    'feature-id-directory-match',
    'acceptance-id-exact-match',
    'state-reference-resolution',
    'state-lifecycle-consistency',
    'runtime-asmdef-set',
    'runtime-assembly-names',
    'engine-independence-flags',
    'runtime-project-reference-graph',
    'domain-application-source-boundary',
    'generated-artifacts-untracked'
)

function Get-SpecOpsEvalOrdinalSortedStrings {
    param([AllowEmptyCollection()] [string[]] $Values)
    $result = [string[]]@($Values)
    [Array]::Sort($result, [StringComparer]::Ordinal)
    return $result
}

function New-SpecOpsEvalException {
    param(
        [Parameter(Mandatory)] [string] $Message,
        [Parameter(Mandatory)] [string] $RejectionClass,
        [int] $ExitCode = 2
    )
    $exception = [System.InvalidOperationException]::new($Message)
    $exception.Data['SpecOpsExitCode'] = $ExitCode
    $exception.Data['SpecOpsRejectionClass'] = $RejectionClass
    return $exception
}

function ConvertTo-SpecOpsHashtable {
    param([Parameter(Mandatory)] [string] $Json)
    return $Json | ConvertFrom-Json -AsHashtable -Depth 100
}

function Test-SpecOpsJsonElementDuplicateNames {
    param([Parameter(Mandatory)] [System.Text.Json.JsonElement] $Element)
    if ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
        $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($property in $Element.EnumerateObject()) {
            if (-not $names.Add($property.Name)) {
                throw (New-SpecOpsEvalException -Message "Duplicate JSON member name: $($property.Name)" -RejectionClass 'DUPLICATE_JSON_MEMBER')
            }
            Test-SpecOpsJsonElementDuplicateNames -Element $property.Value
        }
    }
    elseif ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
        foreach ($item in $Element.EnumerateArray()) {
            Test-SpecOpsJsonElementDuplicateNames -Element $item
        }
    }
}

function Read-SpecOpsStrictJsonBytes {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [byte[]] $Bytes)

    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        throw (New-SpecOpsEvalException -Message 'Leading UTF-8 BOM is not accepted.' -RejectionClass 'LEADING_UTF8_BOM')
    }
    try {
        $text = $script:Utf8Strict.GetString($Bytes)
        $options = [System.Text.Json.JsonDocumentOptions]::new()
        $options.AllowTrailingCommas = $false
        $options.CommentHandling = [System.Text.Json.JsonCommentHandling]::Disallow
        $document = [System.Text.Json.JsonDocument]::Parse($text, $options)
        try {
            Test-SpecOpsJsonElementDuplicateNames -Element $document.RootElement
            $root = $document.RootElement.Clone()
        }
        finally {
            $document.Dispose()
        }
        return [pscustomobject]@{
            Text = $text
            Element = $root
            Value = ConvertTo-SpecOpsHashtable -Json $text
        }
    }
    catch {
        if ($_.Exception.Data.Contains('SpecOpsRejectionClass')) { throw }
        throw (New-SpecOpsEvalException -Message $_.Exception.Message -RejectionClass 'INVALID_JSON')
    }
}

function Read-SpecOpsSubjectJson {
    param($Context, [string] $Path)
    $bytes = Get-SpecOpsRepositoryBlobBytes -Snapshot $Context.Snapshot -Path $Path
    return Read-SpecOpsStrictJsonBytes -Bytes $bytes
}

function Read-SpecOpsSubjectUtf8 {
    param($Context, [string] $Path)
    try {
        return $script:Utf8Strict.GetString((Get-SpecOpsRepositoryBlobBytes -Snapshot $Context.Snapshot -Path $Path))
    }
    catch {
        if ($_.Exception.Data.Contains('SpecOpsRejectionClass')) { throw }
        throw (New-SpecOpsEvalException -Message "Invalid UTF-8 subject text: $Path" -RejectionClass 'INVALID_UTF8')
    }
}

function Get-SpecOpsJsonPointerValue {
    param(
        [Parameter(Mandatory)] [System.Text.Json.JsonElement] $Root,
        [Parameter(Mandatory)] [string] $Pointer
    )
    if ([string]::Equals($Pointer, '', [System.StringComparison]::Ordinal)) {
        return [pscustomobject]@{ Found = $true; Value = $Root }
    }
    if (-not $Pointer.StartsWith('/', [System.StringComparison]::Ordinal)) {
        return [pscustomobject]@{ Found = $false; Value = $null }
    }
    $current = $Root
    foreach ($rawSegment in $Pointer.Substring(1).Split('/')) {
        $segment = $rawSegment.Replace('~1', '/').Replace('~0', '~')
        if ($current.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
            $found = $false
            foreach ($property in $current.EnumerateObject()) {
                if ([string]::Equals($property.Name, $segment, [System.StringComparison]::Ordinal)) {
                    $current = $property.Value
                    $found = $true
                    break
                }
            }
            if (-not $found) { return [pscustomobject]@{ Found = $false; Value = $null } }
        }
        elseif ($current.ValueKind -eq [System.Text.Json.JsonValueKind]::Array -and $segment -match '^(0|[1-9][0-9]*)$') {
            $index = [int]$segment
            if ($index -ge $current.GetArrayLength()) { return [pscustomobject]@{ Found = $false; Value = $null } }
            $current = $current[$index]
        }
        else {
            return [pscustomobject]@{ Found = $false; Value = $null }
        }
    }
    return [pscustomobject]@{ Found = $true; Value = $current }
}

function Get-SpecOpsCanonicalDefinitionDigest {
    param([Parameter(Mandatory)] [byte[]] $Bytes)
    $canonical = ConvertTo-SpecOpsCanonicalJson -Bytes $Bytes -Mode EVAL_DEFINITION
    $canonicalBytes = $script:Utf8Strict.GetBytes($canonical)
    return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($canonicalBytes)).ToLowerInvariant()
}

function Get-SpecOpsSchemaAdapterCapability {
    [CmdletBinding()]
    param()
    $command = Get-Command -Name Test-Json -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        return [pscustomobject]@{ Available = $false; Draft202012 = $false; ExternalReferences = $false; SchemaDocuments = $false; Detail = 'Test-Json unavailable.' }
    }
    try {
        $probeSchema = '{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","properties":{"x":{"const":1}},"required":["x"],"unevaluatedProperties":false}'
        $valid = Test-Json -Json '{"x":1}' -Schema $probeSchema -ErrorAction Stop
        $invalid = Test-Json -Json '{"x":1,"y":2}' -Schema $probeSchema -ErrorAction SilentlyContinue
        $draft = ($valid -and -not $invalid)
        $externalReferences = $false
        $schemaDocuments = $false
        $probeRoot = [IO.Path]::Combine([IO.Path]::GetTempPath(), "specops-schema-capability-$([Guid]::NewGuid().ToString('N'))")
        try {
            $null = [IO.Directory]::CreateDirectory($probeRoot)
            $rootSchemaPath = [IO.Path]::Combine($probeRoot, 'root.schema.json')
            $childSchemaPath = [IO.Path]::Combine($probeRoot, 'child.schema.json')
            [IO.File]::WriteAllText($rootSchemaPath, '{"$schema":"https://json-schema.org/draft/2020-12/schema","$ref":"child.schema.json"}', [Text.UTF8Encoding]::new($false))
            [IO.File]::WriteAllText($childSchemaPath, '{"$schema":"https://json-schema.org/draft/2020-12/schema","const":1}', [Text.UTF8Encoding]::new($false))
            $externalValid = Test-Json -Json '1' -SchemaFile $rootSchemaPath -ErrorAction Stop
            $externalInvalid = Test-Json -Json '2' -SchemaFile $rootSchemaPath -ErrorAction SilentlyContinue
            $externalReferences = ($externalValid -and -not $externalInvalid)
        }
        finally {
            if ([IO.Directory]::Exists($probeRoot)) { [IO.Directory]::Delete($probeRoot, $true) }
        }
        try {
            $validSchema = [Text.Json.Nodes.JsonNode]::Parse('{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object"}')
            $invalidSchema = [Text.Json.Nodes.JsonNode]::Parse('{"$schema":"https://json-schema.org/draft/2020-12/schema","type":7}')
            $metaOptions = [Json.Schema.EvaluationOptions]::new()
            $metaOptions.EvaluateAs = [Json.Schema.SpecVersion]::Draft202012
            $schemaDocuments = ([Json.Schema.MetaSchemas]::Draft202012.Evaluate($validSchema, $metaOptions).IsValid -and
                -not [Json.Schema.MetaSchemas]::Draft202012.Evaluate($invalidSchema, $metaOptions).IsValid)
        }
        catch { $schemaDocuments = $false }
        return [pscustomobject]@{
            Available = ($draft -and $externalReferences)
            Draft202012 = $draft
            ExternalReferences = $externalReferences
            SchemaDocuments = $schemaDocuments
            Detail = "PowerShell $($PSVersionTable.PSVersion); Test-Json; JsonSchema.Net $([Json.Schema.JsonSchema].Assembly.GetName().Version)"
        }
    }
    catch {
        return [pscustomobject]@{ Available = $false; Draft202012 = $false; ExternalReferences = $false; SchemaDocuments = $false; Detail = $_.Exception.Message }
    }
}

function Assert-SpecOpsLocalOnlySchemaUris {
    param(
        [System.Text.Json.JsonElement] $Element,
        [Parameter(Mandatory)] [string] $DocumentPath,
        [string] $Pointer = ''
    )
    if ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
        foreach ($property in $Element.EnumerateObject()) {
            $childPointer = "$Pointer/$($property.Name.Replace('~', '~0').Replace('/', '~1'))"
            if ([string]::Equals($property.Name, '$ref', [System.StringComparison]::Ordinal) -or [string]::Equals($property.Name, '$dynamicRef', [System.StringComparison]::Ordinal)) {
                if ($property.Value.ValueKind -ne [System.Text.Json.JsonValueKind]::String) {
                    throw (New-SpecOpsEvalException -Message "Schema reference keyword is not a string: $childPointer" -RejectionClass 'SCHEMA_REFERENCE_INVALID')
                }
                $reference = $property.Value.GetString()
                if ($reference -match '^[A-Za-z][A-Za-z0-9+.-]*:' -or $reference.StartsWith('//', [StringComparison]::Ordinal) -or $reference.StartsWith('/', [StringComparison]::Ordinal) -or $reference.Contains('\')) {
                    throw (New-SpecOpsEvalException -Message "Network or absolute schema reference prohibited: $reference" -RejectionClass 'NETWORK_SCHEMA_REFERENCE_PROHIBITED')
                }
            }
            elseif ([string]::Equals($property.Name, '$id', [System.StringComparison]::Ordinal)) {
                if ($property.Value.ValueKind -ne [System.Text.Json.JsonValueKind]::String) {
                    throw (New-SpecOpsEvalException -Message "Schema identifier is not a string: $childPointer" -RejectionClass 'SCHEMA_IDENTIFIER_REBASE_PROHIBITED')
                }
                $identifier = $property.Value.GetString()
                if ($identifier -match '^[A-Za-z][A-Za-z0-9+.-]*:' -or $identifier.StartsWith('//', [StringComparison]::Ordinal) -or $identifier.StartsWith('/', [StringComparison]::Ordinal) -or $identifier.Contains('\')) {
                    throw (New-SpecOpsEvalException -Message "Network or absolute schema identifier prohibited: $identifier" -RejectionClass 'NETWORK_SCHEMA_REFERENCE_PROHIBITED')
                }
                $expectedIdentifier = $DocumentPath.Substring($DocumentPath.LastIndexOf('/') + 1)
                if (-not [string]::Equals($Pointer, '', [StringComparison]::Ordinal) -or -not [string]::Equals($identifier, $expectedIdentifier, [StringComparison]::Ordinal)) {
                    throw (New-SpecOpsEvalException -Message "Schema identifier rebasing is outside the local-only adapter profile: $identifier" -RejectionClass 'SCHEMA_IDENTIFIER_REBASE_PROHIBITED')
                }
            }
            Assert-SpecOpsLocalOnlySchemaUris -Element $property.Value -DocumentPath $DocumentPath -Pointer $childPointer
        }
    }
    elseif ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
        $index = 0
        foreach ($item in $Element.EnumerateArray()) { Assert-SpecOpsLocalOnlySchemaUris -Element $item -DocumentPath $DocumentPath -Pointer "$Pointer/$index"; $index++ }
    }
}

function Test-SpecOpsDraft202012SchemaDocument {
    param(
        [Parameter(Mandatory)] [string] $Json,
        [Parameter(Mandatory)] $Capability
    )
    if (-not $Capability.SchemaDocuments) {
        return [pscustomobject]@{ Executable = $false; Valid = $false; Detail = $Capability.Detail }
    }
    try {
        $node = [Text.Json.Nodes.JsonNode]::Parse($Json)
        $options = [Json.Schema.EvaluationOptions]::new()
        $options.EvaluateAs = [Json.Schema.SpecVersion]::Draft202012
        $result = [Json.Schema.MetaSchemas]::Draft202012.Evaluate($node, $options)
        return [pscustomobject]@{ Executable = $true; Valid = [bool]$result.IsValid; Detail = if ($result.IsValid) { '' } else { 'Draft 2020-12 metaschema validation failed.' } }
    }
    catch {
        return [pscustomobject]@{ Executable = $true; Valid = $false; Detail = $_.Exception.Message }
    }
}

function Test-SpecOpsJsonAgainstSubjectSchema {
    param(
        [Parameter(Mandatory)] $Context,
        [Parameter(Mandatory)] [string] $Json,
        [Parameter(Mandatory)] [string] $SchemaReference,
        [Parameter(Mandatory)] $Capability
    )
    if (-not $Capability.Available -or -not $Capability.Draft202012 -or -not $Capability.ExternalReferences) {
        return [pscustomobject]@{ Executable = $false; Valid = $false; Detail = $Capability.Detail }
    }
    $temporaryRoot = [IO.Path]::Combine([IO.Path]::GetTempPath(), "specops-schema-closure-$([Guid]::NewGuid().ToString('N'))")
    try {
        $schemaPath = Assert-SpecOpsRepositoryRelativePath $SchemaReference
        if (-not $schemaPath.StartsWith('.specops/contracts/', [StringComparison]::Ordinal)) { throw (New-SpecOpsEvalException 'Schema is outside the approved contract root.' 'SCHEMA_REFERENCE_INVALID') }
        $null = [IO.Directory]::CreateDirectory($temporaryRoot)
        $queue=[Collections.Generic.Queue[string]]::new();$visited=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$queue.Enqueue($schemaPath)
        while($queue.Count-gt0){
            $contractPath=$queue.Dequeue();if(-not$visited.Add($contractPath)){continue}
            if(-not(Test-SpecOpsRepositoryPathExists $Context.Snapshot $contractPath)){throw(New-SpecOpsEvalException "Schema is absent from subject X: $contractPath" 'SCHEMA_REFERENCE_INVALID')}
            $contractBytes=Get-SpecOpsRepositoryBlobBytes $Context.Snapshot $contractPath
            $contractDocument=Read-SpecOpsStrictJsonBytes $contractBytes;Assert-SpecOpsLocalOnlySchemaUris $contractDocument.Element $contractPath
            $materializedPath=[IO.Path]::Combine($temporaryRoot,$contractPath.Replace('/',[IO.Path]::DirectorySeparatorChar))
            $parent=[IO.Path]::GetDirectoryName($materializedPath);if(-not[IO.Directory]::Exists($parent)){$null=[IO.Directory]::CreateDirectory($parent)}
            [IO.File]::WriteAllBytes($materializedPath,$contractBytes)
            foreach($referenceItem in @(Get-SpecOpsJsonReferences $contractDocument.Element)){
                $reference=[string]$referenceItem.Reference;$hash=$reference.IndexOf('#');$filePart=if($hash-ge0){$reference.Substring(0,$hash)}else{$reference};if([string]::IsNullOrEmpty($filePart)){continue}
                if($filePart.Contains('\')-or$filePart.StartsWith('/')-or$filePart-match'^[A-Za-z][A-Za-z0-9+.-]*:'){throw(New-SpecOpsEvalException "Network or rooted schema reference prohibited: $reference" 'NETWORK_SCHEMA_REFERENCE_PROHIBITED')}
                $target=Resolve-SpecOpsRelativePath $contractPath $filePart '.specops/contracts'
                if($null-eq$target-or-not(Test-SpecOpsRepositoryPathExists $Context.Snapshot $target)){throw(New-SpecOpsEvalException "Schema reference escapes or is absent from subject X: $reference" 'SCHEMA_REFERENCE_INVALID')}
                $queue.Enqueue($target)
            }
        }
        $materializedRootSchema=[IO.Path]::Combine($temporaryRoot,$schemaPath.Replace('/',[IO.Path]::DirectorySeparatorChar))
        $valid = Test-Json -Json $Json -SchemaFile $materializedRootSchema -ErrorAction Stop
        return [pscustomobject]@{ Executable = $true; Valid = [bool]$valid; Detail = '' }
    }
    catch {
        return [pscustomobject]@{ Executable = $true; Valid = $false; Detail = $_.Exception.Message }
    }
    finally {
        if ([IO.Directory]::Exists($temporaryRoot)) { [IO.Directory]::Delete($temporaryRoot, $true) }
    }
}

function Test-SpecOpsStrictUtcTimestamp {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Value)
    if ($Value -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$') { return $false }
    $parsed = [DateTimeOffset]::MinValue
    $valid = [DateTimeOffset]::TryParse(
        $Value,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal,
        [ref]$parsed
    )
    return ($valid -and $parsed.Offset -eq [TimeSpan]::Zero)
}

function New-SpecOpsExecutedCheckResult {
    param([string] $Id, [string] $Result, [string[]] $Observations)
    if ($Result -notin @('PASS', 'FAIL', 'INCONCLUSIVE')) {
        throw (New-SpecOpsEvalException -Message "Invalid executed check result: $Result" -RejectionClass 'INTERNAL_RESULT_INVARIANT' -ExitCode 4)
    }
    if ($Observations.Count -eq 0) { $Observations = @('No additional observation was reported.') }
    return [ordered]@{ id = $Id; executed = $true; result = $Result; observations = @($Observations) }
}

function New-SpecOpsNotExecutedCheckResult {
    param([string] $Id, [string] $Reason)
    return [ordered]@{ id = $Id; executed = $false; result = 'NOT_EXECUTED'; observations = @(); notExecutedReason = $Reason }
}

function New-SpecOpsPassOrFail {
    param([string] $Id, [bool] $Pass, [string[]] $Observations)
    return New-SpecOpsExecutedCheckResult -Id $Id -Result $(if ($Pass) { 'PASS' } else { 'FAIL' }) -Observations $Observations
}

function Get-SpecOpsContractPaths {
    param($Context)
    $values=@($Context.Paths | Where-Object {
        $_ -match '^\.specops/contracts/[^/]+\.schema\.json$'
    })
    return @(Get-SpecOpsEvalOrdinalSortedStrings $values)
}

function Get-SpecOpsFeatureDirectories {
    param($Context)
    $root = 'Assets/Project/Docs/Specifications/'
    $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($path in $Context.Paths) {
        if (-not $path.StartsWith($root, [System.StringComparison]::Ordinal)) { continue }
        $remaining = $path.Substring($root.Length)
        $slash = $remaining.IndexOf('/')
        if ($slash -lt 1) { continue }
        $name = $remaining.Substring(0, $slash)
        if ([string]::Equals($name, '_templates', [System.StringComparison]::Ordinal)) { continue }
        $fileName = $remaining.Substring($slash + 1)
        if ($fileName -in @('SPEC.md', 'CONSTRAINTS.md', 'ACCEPTANCE.md', 'SPECOPS_STATE.json')) { $null = $names.Add($name) }
    }
    return @(Get-SpecOpsEvalOrdinalSortedStrings @($names))
}

function Resolve-SpecOpsRelativePath {
    param([string] $BasePath, [string] $Reference, [string] $AllowedRoot)
    if ([string]::IsNullOrEmpty($Reference) -or $Reference.Contains('\') -or $Reference -match '^[A-Za-z][A-Za-z0-9+.-]*:' -or $Reference.StartsWith('/')) {
        return $null
    }
    $segments = [System.Collections.Generic.List[string]]::new()
    $baseDirectory = if ($BasePath.Contains('/')) { $BasePath.Substring(0, $BasePath.LastIndexOf('/')) } else { '' }
    foreach ($segment in (($baseDirectory + '/' + $Reference).Split('/'))) {
        if ([string]::IsNullOrEmpty($segment) -or $segment -eq '.') { continue }
        if ($segment -eq '..') {
            if ($segments.Count -eq 0) { return $null }
            $segments.RemoveAt($segments.Count - 1)
        }
        else { $segments.Add($segment) }
    }
    $result = [string]::Join('/', $segments)
    $root = $AllowedRoot.TrimEnd('/')
    if (-not [string]::Equals($root, '.', [System.StringComparison]::Ordinal) -and
        -not [string]::Equals($result, $root, [System.StringComparison]::Ordinal) -and
        -not $result.StartsWith("$root/", [System.StringComparison]::Ordinal)) { return $null }
    try { return Assert-SpecOpsRepositoryRelativePath -Path $result } catch { return $null }
}

function Get-SpecOpsJsonReferences {
    param([System.Text.Json.JsonElement] $Element, [string] $Pointer = '')
    $results = [System.Collections.Generic.List[object]]::new()
    if ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
        foreach ($property in $Element.EnumerateObject()) {
            $escaped = $property.Name.Replace('~', '~0').Replace('/', '~1')
            $childPointer = "$Pointer/$escaped"
            if (([string]::Equals($property.Name, '$ref', [System.StringComparison]::Ordinal) -or [string]::Equals($property.Name, '$dynamicRef', [System.StringComparison]::Ordinal)) -and $property.Value.ValueKind -eq [System.Text.Json.JsonValueKind]::String) {
                $results.Add([pscustomobject]@{ Pointer = $childPointer; Keyword = $property.Name; Reference = $property.Value.GetString() })
            }
            foreach ($child in @(Get-SpecOpsJsonReferences -Element $property.Value -Pointer $childPointer)) { $results.Add($child) }
        }
    }
    elseif ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
        $index = 0
        foreach ($item in $Element.EnumerateArray()) {
            foreach ($child in @(Get-SpecOpsJsonReferences -Element $item -Pointer "$Pointer/$index")) { $results.Add($child) }
            $index++
        }
    }
    return @($results)
}

function Test-SpecOpsContractReferences {
    param($Context, [string[]] $ContractPaths)
    $failures = [System.Collections.Generic.List[string]]::new()
    $documents = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($path in $ContractPaths) {
        try { $documents[$path] = Read-SpecOpsSubjectJson -Context $Context -Path $path }
        catch { $failures.Add("${path}:invalid-json"); continue }
    }
    foreach ($path in $ContractPaths) {
        if (-not $documents.ContainsKey($path)) { continue }
        foreach ($item in @(Get-SpecOpsJsonReferences -Element $documents[$path].Element)) {
            $reference = [string]$item.Reference
            $hash = $reference.IndexOf('#')
            $filePart = if ($hash -ge 0) { $reference.Substring(0, $hash) } else { $reference }
            $fragment = if ($hash -ge 0) { $reference.Substring($hash + 1) } else { '' }
            if ($filePart -match '^[A-Za-z][A-Za-z0-9+.-]*:' -or $filePart.Contains('\') -or $filePart.StartsWith('/')) {
                $failures.Add("${path}:${reference}:prohibited")
                continue
            }
            $targetPath = if ([string]::IsNullOrEmpty($filePart)) { $path } else { Resolve-SpecOpsRelativePath -BasePath $path -Reference $filePart -AllowedRoot '.specops/contracts' }
            if ($null -eq $targetPath -or -not $documents.ContainsKey($targetPath)) {
                $failures.Add("${path}:${reference}:missing-target")
                continue
            }
            if (-not [string]::IsNullOrEmpty($fragment)) {
                try { $pointer = [Uri]::UnescapeDataString($fragment) } catch { $failures.Add("${path}:${reference}:invalid-fragment"); continue }
                $resolved = Get-SpecOpsJsonPointerValue -Root $documents[$targetPath].Element -Pointer $pointer
                if (-not $resolved.Found) { $failures.Add("${path}:${reference}:missing-fragment") }
            }
        }
    }
    return @(Get-SpecOpsEvalOrdinalSortedStrings $failures.ToArray())
}

function Get-SpecOpsAsmdefPaths {
    param($Context)
    return @(Get-SpecOpsEvalOrdinalSortedStrings @($Context.Paths | Where-Object { $_ -match '^Assets/Project/Code/Runtime/.+\.asmdef$' }))
}

function Test-SpecOpsGeneratedPattern {
    param([string] $Path, [string] $Pattern)
    $options = [System.Management.Automation.WildcardOptions]::CultureInvariant
    if ($Pattern.EndsWith('/', [System.StringComparison]::Ordinal)) {
        $directoryPattern = $Pattern.TrimEnd('/')
        $matcher = [System.Management.Automation.WildcardPattern]::new($directoryPattern, $options)
        $segments = $Path.Split('/')
        for ($i = 0; $i -lt ($segments.Count - 1); $i++) { if ($matcher.IsMatch($segments[$i])) { return $true } }
        return $false
    }
    $fileMatcher = [System.Management.Automation.WildcardPattern]::new($Pattern, $options)
    return $fileMatcher.IsMatch(($Path.Split('/')[-1]))
}

function Initialize-SpecOpsCSharpScanner {
    if ($null -ne ([System.Management.Automation.PSTypeName]'SpecOps.Local.CSharpLexicalScannerV1').Type) { return }
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace SpecOps.Local {
  public sealed class CSharpScanResult {
    public bool Supported { get; set; }
    public string Error { get; set; }
    public string[] Tokens { get; set; }
  }

  public static class CSharpLexicalScannerV1 {
    private sealed class Scanner {
      private readonly string s;
      private int i;
      private readonly List<string> tokens = new List<string>();
      internal Scanner(string text) { s = text ?? throw new ArgumentNullException(nameof(text)); }
      internal CSharpScanResult Run() {
        try { ReadCode(0, false); if (i != s.Length) throw new FormatException("Unexpected scanner termination."); return new CSharpScanResult { Supported=true, Error="", Tokens=tokens.ToArray() }; }
        catch (Exception e) { return new CSharpScanResult { Supported=false, Error=e.Message, Tokens=tokens.ToArray() }; }
      }
      private void ReadCode(int terminatorBraces, bool interpolationExpression) {
        int braceDepth = 0, parenthesisDepth = 0, bracketDepth = 0;
        while (i < s.Length) {
          char c=s[i];
          if (terminatorBraces>0 && c=='}' && braceDepth==0 && parenthesisDepth==0 && bracketDepth==0) {
            int closingRun=Count(i,'}');
            if(closingRun>=2*terminatorBraces) throw new FormatException("Malformed raw interpolation closing brace run.");
            if(closingRun>=terminatorBraces) { i+=terminatorBraces; return; }
          }
          if (c=='/' && Peek(1)=='/') { i+=2; while(i<s.Length && s[i]!='\n' && s[i]!='\r') i++; continue; }
          if (c=='/' && Peek(1)=='*') { i+=2; bool done=false; while(i+1<s.Length){ if(s[i]=='*'&&s[i+1]=='/'){i+=2;done=true;break;} i++; } if(!done) throw new FormatException("Unterminated block comment."); continue; }
          if (TryStringOrCharacter()) continue;
          if (c=='{') { braceDepth++; tokens.Add("{"); i++; continue; }
          if (c=='}') { if(braceDepth==0) throw new FormatException("Unexpected closing brace."); braceDepth--; tokens.Add("}"); i++; continue; }
          if (c=='(') { parenthesisDepth++; tokens.Add("("); i++; continue; }
          if (c==')') { if(parenthesisDepth==0) throw new FormatException("Unexpected closing parenthesis."); parenthesisDepth--; tokens.Add(")"); i++; continue; }
          if (c=='[') { bracketDepth++; tokens.Add("["); i++; continue; }
          if (c==']') { if(bracketDepth==0) throw new FormatException("Unexpected closing bracket."); bracketDepth--; tokens.Add("]"); i++; continue; }
          if (interpolationExpression && c==':' && braceDepth==0 && parenthesisDepth==0 && bracketDepth==0 && Peek(1)!=':' && (i==0 || s[i-1]!=':')) { i++; SkipInterpolationFormat(terminatorBraces); return; }
          if (IsIdentifierStartAt(i)) { tokens.Add(ReadIdentifier()); continue; }
          if (!char.IsWhiteSpace(c)) tokens.Add(c.ToString());
          i++;
        }
        if (terminatorBraces>0) throw new FormatException("Unterminated interpolation expression.");
        if (braceDepth!=0 || parenthesisDepth!=0 || bracketDepth!=0) throw new FormatException("Unbalanced lexical delimiters.");
      }
      private bool TryStringOrCharacter() {
        if (s[i]=='\'') { SkipCharacter(); return true; }
        if (s[i]=='@' && Peek(1)=='$' && Peek(2)=='"') { i+=3; SkipQuotedString(true,true); return true; }
        int start=i, dollars=0;
        while(start+dollars<s.Length && s[start+dollars]=='$') dollars++;
        int p=start+dollars;
        bool verbatim=false;
        if (p<s.Length && s[p]=='@') { verbatim=true; p++; }
        else if (dollars==0 && p<s.Length && s[p]=='@' && PeekFrom(p,1)=='$') { dollars=1; verbatim=true; p+=2; }
        int quotes=Count(p,'"');
        if (quotes>=3) { i=p+quotes; SkipRawString(dollars, quotes); return true; }
        if (quotes==1 && (dollars>0 || verbatim || p==i)) { i=p+1; SkipQuotedString(dollars>0, verbatim); return true; }
        if (s[i]=='@' && Peek(1)=='"') { i+=2; SkipQuotedString(false,true); return true; }
        return false;
      }
      private void SkipCharacter() {
        i++; int units=0;
        while(i<s.Length){ char c=s[i++]; if(c=='\\'){units+=SkipEscape();continue;} if(c=='\''){if(units!=1)throw new FormatException("Character literal must contain one character.");return;} if(c=='\n'||c=='\r')throw new FormatException("Unterminated character literal."); if(char.IsHighSurrogate(c)){if(i>=s.Length||!char.IsLowSurrogate(s[i]))throw new FormatException("Invalid surrogate in character literal.");i++;units+=2;}else if(char.IsLowSurrogate(c))throw new FormatException("Invalid surrogate in character literal.");else units++; }
        throw new FormatException("Unterminated character literal.");
      }
      private void SkipQuotedString(bool interpolated, bool verbatim) {
        while(i<s.Length){ char c=s[i++];
          if(verbatim && c=='"'){ if(i<s.Length&&s[i]=='"'){i++;continue;} return; }
          if(!verbatim && c=='\\'){ SkipEscape(); continue; }
          if(!verbatim && c=='"') return;
          if(!verbatim && (c=='\n'||c=='\r')) throw new FormatException("Unterminated string literal.");
          if(interpolated && c=='{'){ if(i<s.Length&&s[i]=='{'){i++;continue;} ReadCode(1, true); }
          else if(interpolated && c=='}'){ if(i<s.Length&&s[i]=='}'){i++;continue;} throw new FormatException("Unescaped interpolation brace."); }
        }
        throw new FormatException("Unterminated string literal.");
      }
      private void SkipRawString(int dollars, int quotes) {
        while(i<s.Length){
          if(dollars>0){
            int openingRun=Count(i,'{');
            if(openingRun>=2*dollars) throw new FormatException("Malformed raw interpolation opening brace run.");
            if(openingRun>=dollars){ i+=openingRun-dollars; i+=dollars; ReadCode(dollars, true); continue; }
            int unmatchedClosingRun=Count(i,'}');
            if(unmatchedClosingRun>=dollars) throw new FormatException("Unmatched raw interpolation closing brace run.");
          }
          if(Count(i,'"')>=quotes){ i+=quotes; return; }
          i++;
        }
        throw new FormatException("Unterminated raw string literal.");
      }
      private void SkipInterpolationFormat(int terminatorBraces) {
        while(i<s.Length){ if(Count(i,'}')>=terminatorBraces){i+=terminatorBraces;return;} i++; }
        throw new FormatException("Unterminated interpolation format.");
      }
      private int SkipEscape() {
        if(i>=s.Length)throw new FormatException("Unterminated escape sequence.");
        char kind=s[i++];
        if("'\"\\0abfnrtv".IndexOf(kind)>=0)return 1;
        int min, max;
        if(kind=='u'){min=max=4;}else if(kind=='U'){min=max=8;}else if(kind=='x'){min=1;max=4;}else throw new FormatException("Unsupported escape sequence.");
        int count=0;uint value=0;
        while(count<max&&i<s.Length){int digit=Hex(s[i]);if(digit<0)break;value=(value<<4)|(uint)digit;i++;count++;}
        if(count<min||value>0x10ffff||(kind=='U'&&value>=0xd800&&value<=0xdfff))throw new FormatException("Invalid Unicode escape sequence.");
        return value>0xffff?2:1;
      }
      private int Hex(char c){if(c>='0'&&c<='9')return c-'0';if(c>='a'&&c<='f')return c-'a'+10;if(c>='A'&&c<='F')return c-'A'+10;return -1;}
      private bool IsIdentifierStartAt(int pos) {
        if(pos>=s.Length)return false; char c=s[pos];
        return c=='_' || c=='\\' || char.IsLetter(c) || char.GetUnicodeCategory(c)==UnicodeCategory.LetterNumber;
      }
      private bool IsIdentifierPart(char c) {
        var cat=char.GetUnicodeCategory(c);
        return c=='_' || char.IsLetterOrDigit(c) || cat==UnicodeCategory.ConnectorPunctuation || cat==UnicodeCategory.NonSpacingMark || cat==UnicodeCategory.SpacingCombiningMark || cat==UnicodeCategory.Format;
      }
      private string ReadIdentifier() {
        var b=new StringBuilder();
        while(i<s.Length){
          if(s[i]=='\\' && i+1<s.Length && (s[i+1]=='u'||s[i+1]=='U')) { int digits=s[i+1]=='u'?4:8; if(i+2+digits>s.Length)throw new FormatException("Malformed Unicode identifier escape."); string hex=s.Substring(i+2,digits); int scalar; if(!int.TryParse(hex,NumberStyles.AllowHexSpecifier,CultureInfo.InvariantCulture,out scalar)||scalar>0x10ffff||(scalar>=0xd800&&scalar<=0xdfff))throw new FormatException("Invalid Unicode identifier escape."); b.Append(char.ConvertFromUtf32(scalar)); i+=2+digits; continue; }
          if(!IsIdentifierPart(s[i]))break; b.Append(s[i++]);
        }
        if(b.Length==0)throw new FormatException("Malformed identifier.");
        return b.ToString();
      }
      private int Count(int pos,char value){int n=0;while(pos+n<s.Length&&s[pos+n]==value)n++;return n;}
      private char Peek(int offset){return PeekFrom(i,offset);}
      private char PeekFrom(int pos,int offset){int p=pos+offset;return p>=0&&p<s.Length?s[p]:'\0';}
    }
    public static CSharpScanResult Scan(string text) { return new Scanner(text).Run(); }
  }
}
'@
}

function Test-SpecOpsCSharpLexicalBoundary {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Text)
    Initialize-SpecOpsCSharpScanner
    $scan = [SpecOps.Local.CSharpLexicalScannerV1]::Scan($Text)
    if (-not $scan.Supported) { return [pscustomobject]@{ Supported=$false; Violations=@(); Error=$scan.Error; Tokens=$scan.Tokens } }
    $tokens = @($scan.Tokens)
    $violations = [System.Collections.Generic.List[string]]::new()
    for ($i=0; $i -lt $tokens.Count; $i++) {
        if (($tokens[$i] -eq 'UnityEngine' -or $tokens[$i] -eq 'UnityEditor') -and $i+1 -lt $tokens.Count -and $tokens[$i+1] -eq '.') {
            $violations.Add("qualified-prefix:$($tokens[$i])")
        }
        if ($tokens[$i] -eq 'using') {
            $j=$i+1
            if ($j -lt $tokens.Count -and $tokens[$j] -eq 'static') { $j++ }
            if ($j+1 -lt $tokens.Count -and $tokens[$j+1] -eq '=') { $j+=2 }
            if ($j -lt $tokens.Count -and $tokens[$j] -eq '@') { $j++ }
            if ($j+2 -lt $tokens.Count -and $tokens[$j] -eq 'global' -and $tokens[$j+1] -eq ':' -and $tokens[$j+2] -eq ':') { $j+=3 }
            if ($j -lt $tokens.Count -and $tokens[$j] -eq '@') { $j++ }
            if ($j -lt $tokens.Count -and ($tokens[$j] -eq 'UnityEngine' -or $tokens[$j] -eq 'UnityEditor')) {
                $violations.Add("using-prefix:$($tokens[$j])")
            }
        }
        if ($tokens[$i] -in @('class','record','struct')) {
            $j=$i+1
            while($j -lt $tokens.Count -and $tokens[$j] -ne ':' -and $tokens[$j] -ne '{' -and $tokens[$j] -ne ';'){ $j++ }
            if($j -lt $tokens.Count -and $tokens[$j] -eq ':'){
                $j++
                while($j -lt $tokens.Count -and $tokens[$j] -notin @('{',';')){
                    if($tokens[$j] -eq 'MonoBehaviour'){ $violations.Add('base-type:MonoBehaviour') }
                    $j++
                }
            }
        }
    }
    $unique=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($violation in $violations){$null=$unique.Add($violation)}
    return [pscustomobject]@{ Supported=$true; Violations=@(Get-SpecOpsEvalOrdinalSortedStrings @($unique)); Error=''; Tokens=$tokens }
}

function Invoke-SpecOpsContractsCheck {
    param($Context, $Check)
    $paths = @(Get-SpecOpsContractPaths -Context $Context)
    switch ([string]$Check.id) {
        'contracts-json-parse' {
            $failures = [System.Collections.Generic.List[string]]::new()
            foreach ($path in $paths) { try { $null = Read-SpecOpsSubjectJson -Context $Context -Path $path } catch { $failures.Add($path) } }
            return New-SpecOpsPassOrFail -Id $Check.id -Pass ($failures.Count -eq 0) -Observations @(
                if ($failures.Count -eq 0) { "Strict JSON parsed for $($paths.Count) contract documents." } else { "Invalid contract JSON: $([string]::Join(', ', $failures))" }
            )
        }
        'contracts-id-unique' {
            $ids = [System.Collections.Generic.List[string]]::new(); $failures = [System.Collections.Generic.List[string]]::new()
            foreach ($path in $paths) {
                try {
                    $doc = Read-SpecOpsSubjectJson -Context $Context -Path $path
                    $value = Get-SpecOpsJsonPointerValue -Root $doc.Element -Pointer '/$id'
                    if (-not $value.Found -or $value.Value.ValueKind -ne [System.Text.Json.JsonValueKind]::String -or [string]::IsNullOrEmpty($value.Value.GetString())) { $failures.Add("${path}:missing-root-id") }
                    else { $ids.Add($value.Value.GetString()) }
                } catch { $failures.Add("${path}:invalid-json") }
            }
            $idItems=@($ids|ForEach-Object{[pscustomobject]@{id=$_}});$unique = Test-SpecOpsUniqueIds -Items $idItems -IdProperty 'id'
            foreach ($duplicate in @($unique.DuplicateIds)) { $failures.Add("duplicate:$duplicate") }
            return New-SpecOpsPassOrFail -Id $Check.id -Pass ($failures.Count -eq 0) -Observations @(
                if ($failures.Count -eq 0) { 'Every contract has one ordinal-unique nonempty root $id.' } else { [string]::Join(', ', @(Get-SpecOpsEvalOrdinalSortedStrings $failures.ToArray())) }
            )
        }
        'contracts-version-consistent' {
            $failures = [System.Collections.Generic.List[string]]::new()
            foreach ($path in $paths) {
                try {
                    $doc=Read-SpecOpsSubjectJson $Context $path; $left=Get-SpecOpsJsonPointerValue $doc.Element '/x-contract-version'; $right=Get-SpecOpsJsonPointerValue $doc.Element '/properties/contractVersion/const'
                    if (-not $left.Found -or -not $right.Found -or $left.Value.ValueKind -ne [System.Text.Json.JsonValueKind]::String -or $right.Value.ValueKind -ne [System.Text.Json.JsonValueKind]::String -or -not [string]::Equals($left.Value.GetString(),$right.Value.GetString(),[System.StringComparison]::Ordinal)){ $failures.Add($path) }
                } catch { $failures.Add($path) }
            }
            return New-SpecOpsPassOrFail $Check.id ($failures.Count -eq 0) @(if($failures.Count-eq 0){'Every contract version declaration equals its instance const.'}else{"Version mismatch: $([string]::Join(', ', $failures))"})
        }
        'contracts-draft-declared' {
            $expected='https://json-schema.org/draft/2020-12/schema'; $failures=[System.Collections.Generic.List[string]]::new()
            foreach($path in $paths){ try{$doc=Read-SpecOpsSubjectJson $Context $path;$value=Get-SpecOpsJsonPointerValue $doc.Element '/$schema';if(-not $value.Found -or $value.Value.ValueKind-ne[System.Text.Json.JsonValueKind]::String -or -not [string]::Equals($value.Value.GetString(),$expected,[System.StringComparison]::Ordinal)){$failures.Add($path)}}catch{$failures.Add($path)} }
            return New-SpecOpsPassOrFail $Check.id ($failures.Count-eq 0) @(if($failures.Count-eq 0){'Every contract declares the exact approved Draft 2020-12 URI.'}else{"Draft mismatch: $([string]::Join(', ', $failures))"})
        }
        'contracts-references-resolve' {
            $failures=@(Test-SpecOpsContractReferences -Context $Context -ContractPaths $paths)
            return New-SpecOpsPassOrFail $Check.id ($failures.Count-eq 0) @(if($failures.Count-eq 0){'All repository-local contract references and fragments resolve without network access.'}else{$failures})
        }
        'contracts-schema-valid' {
            if(-not $Context.SchemaCapability.SchemaDocuments){ return New-SpecOpsNotExecutedCheckResult $Check.id 'SCHEMA_ADAPTER_CAPABILITY_UNAVAILABLE' }
            $failures=[System.Collections.Generic.List[string]]::new()
            foreach($path in $paths){
                try{
                    $doc=Read-SpecOpsSubjectJson $Context $path; Assert-SpecOpsLocalOnlySchemaUris $doc.Element $path
                    $validation=Test-SpecOpsDraft202012SchemaDocument $doc.Text $Context.SchemaCapability
                    if(-not$validation.Executable){return New-SpecOpsNotExecutedCheckResult $Check.id 'SCHEMA_ADAPTER_CAPABILITY_UNAVAILABLE'}
                    if(-not$validation.Valid){$failures.Add("${path}:$($validation.Detail)")}
                }catch{$failures.Add("${path}:$($_.Exception.Message)")}
            }
            return New-SpecOpsPassOrFail $Check.id ($failures.Count-eq 0) @(if($failures.Count-eq 0){"The approved schema adapter accepted $($paths.Count) schema documents."}else{@(Get-SpecOpsEvalOrdinalSortedStrings $failures.ToArray())})
        }
    }
}

function Invoke-SpecOpsDerivedStateCheck {
    param($Context,$Check)
    $features=@(Get-SpecOpsFeatureDirectories -Context $Context)
    switch([string]$Check.id){
        'authority-routes-resolve' {
            $source=[string]$Check.passCondition.value.source; $doc=Read-SpecOpsSubjectJson $Context $source; $failures=[System.Collections.Generic.List[string]]::new()
            foreach($pointer in @($Check.passCondition.value.jsonPointers)){
                $resolved=Get-SpecOpsJsonPointerValue $doc.Element ([string]$pointer)
                if(-not $resolved.Found -or $resolved.Value.ValueKind-ne[System.Text.Json.JsonValueKind]::String){$failures.Add("${pointer}:not-string");continue}
                $path=$resolved.Value.GetString(); try{$null=Assert-SpecOpsRepositoryRelativePath $path}catch{$failures.Add("${pointer}:invalid-path");continue}
                if(-not (Test-SpecOpsRepositoryPathExists $Context.Snapshot $path)){$failures.Add("${pointer}:missing:$path")}
            }
            return New-SpecOpsPassOrFail $Check.id ($failures.Count-eq 0) @(if($failures.Count-eq 0){'All configured authority, contract, permission, Skill, ADR, and eval routes resolve inside the subject.'}else{@(Get-SpecOpsEvalOrdinalSortedStrings $failures.ToArray())})
        }
        'feature-authority-triplets' {
            $failures=[System.Collections.Generic.List[string]]::new(); foreach($feature in $features){foreach($file in @('SPEC.md','CONSTRAINTS.md','ACCEPTANCE.md')){$path="Assets/Project/Docs/Specifications/$feature/$file";if(-not (Test-SpecOpsRepositoryPathExists $Context.Snapshot $path)){$failures.Add($path)}}}
            return New-SpecOpsPassOrFail $Check.id ($failures.Count-eq 0) @(if($failures.Count-eq 0){"All $($features.Count) instantiated feature directories contain the exact authority triplet."}else{"Missing: $([string]::Join(', ', $failures))"})
        }
        'feature-state-schema-valid' {
            if(-not $Context.SchemaCapability.Available){return New-SpecOpsNotExecutedCheckResult $Check.id 'SCHEMA_ADAPTER_CAPABILITY_UNAVAILABLE'}
            $schemaReference='.specops/contracts/feature-state.schema.json';$failures=[System.Collections.Generic.List[string]]::new();$count=0
            foreach($feature in $features){$path="Assets/Project/Docs/Specifications/$feature/SPECOPS_STATE.json";if(-not(Test-SpecOpsRepositoryPathExists $Context.Snapshot $path)){continue};$count++;$json=Read-SpecOpsSubjectUtf8 $Context $path;$validation=Test-SpecOpsJsonAgainstSubjectSchema $Context $json $schemaReference $Context.SchemaCapability;if(-not$validation.Executable){return New-SpecOpsNotExecutedCheckResult $Check.id 'SCHEMA_ADAPTER_CAPABILITY_UNAVAILABLE'};if(-not$validation.Valid){$failures.Add($path)}}
            return New-SpecOpsPassOrFail $Check.id ($failures.Count-eq 0) @(if($failures.Count-eq 0){"Validated $count feature-state instances against the installed contract."}else{"Invalid feature state: $([string]::Join(', ', $failures))"})
        }
        'feature-id-directory-match' {
            $failures=[System.Collections.Generic.List[string]]::new();foreach($feature in $features){$path="Assets/Project/Docs/Specifications/$feature/SPECOPS_STATE.json";if(-not(Test-SpecOpsRepositoryPathExists $Context.Snapshot $path)){continue};try{$doc=Read-SpecOpsSubjectJson $Context $path;$id=Get-SpecOpsJsonPointerValue $doc.Element '/featureId';if(-not$id.Found -or $id.Value.ValueKind-ne[System.Text.Json.JsonValueKind]::String -or -not[string]::Equals($id.Value.GetString(),$feature,[System.StringComparison]::Ordinal)){$failures.Add($feature)}}catch{$failures.Add($feature)}}
            return New-SpecOpsPassOrFail $Check.id ($failures.Count-eq 0) @(if($failures.Count-eq 0){'Every featureId exactly equals its containing directory name.'}else{"Feature ID mismatch: $([string]::Join(', ', $failures))"})
        }
        'acceptance-id-exact-match' {
            $failures=[System.Collections.Generic.List[string]]::new();foreach($feature in $features){$acceptance="Assets/Project/Docs/Specifications/$feature/ACCEPTANCE.md";$state="Assets/Project/Docs/Specifications/$feature/SPECOPS_STATE.json";if(-not(Test-SpecOpsRepositoryPathExists $Context.Snapshot $state)){continue};$text=Read-SpecOpsSubjectUtf8 $Context $acceptance;if($text.Contains("`r") -and $text -match "`r(?!`n)"){$failures.Add("${feature}:invalid-line-endings");continue};$ids=[System.Collections.Generic.List[string]]::new();$bad=$false;foreach($line in $text -split "`r?`n"){if($line.StartsWith('### AC-',[System.StringComparison]::Ordinal)){if($line -cnotmatch '^### (AC-[0-9]{3}) — .+$'){$bad=$true;break};$ids.Add($Matches[1])}};if($bad){$failures.Add("${feature}:invalid-heading");continue};$idItems=@($ids|ForEach-Object{[pscustomobject]@{id=$_}});$unique=Test-SpecOpsUniqueIds -Items $idItems -IdProperty 'id';if(-not$unique.IsValid){$failures.Add("${feature}:duplicate-heading");continue};$doc=Read-SpecOpsSubjectJson $Context $state;$pointer=Get-SpecOpsJsonPointerValue $doc.Element '/acceptanceCriteriaIds';if(-not$pointer.Found -or $pointer.Value.ValueKind-ne[System.Text.Json.JsonValueKind]::Array){$failures.Add("${feature}:missing-state-ids");continue};$actual=@($pointer.Value.EnumerateArray()|ForEach-Object{$_.GetString()});$coverage=Compare-SpecOpsIdCoverage -ExpectedIds $ids -ActualIds $actual;if(-not$coverage.IsExact){$failures.Add("${feature}:set-mismatch")}}
            return New-SpecOpsPassOrFail $Check.id ($failures.Count-eq 0) @(if($failures.Count-eq 0){'Acceptance headings and state AC ID sets match exactly using the approved case-sensitive parser.'}else{@(Get-SpecOpsEvalOrdinalSortedStrings $failures.ToArray())})
        }
        'state-reference-resolution' {
            $failures=[System.Collections.Generic.List[string]]::new();$selectors=@($Check.passCondition.value.selectors)
            foreach($feature in $features){$path="Assets/Project/Docs/Specifications/$feature/SPECOPS_STATE.json";if(-not(Test-SpecOpsRepositoryPathExists $Context.Snapshot $path)){continue};$doc=Read-SpecOpsSubjectJson $Context $path;foreach($selector in $selectors){$selected=Get-SpecOpsJsonPointerValue $doc.Element ([string]$selector.jsonPointer);if(-not$selected.Found){$failures.Add("${feature}:$($selector.jsonPointer):missing");continue};$values=@();if($selector.selection-eq'scalar'){$values=@($selected.Value)}elseif($selector.selection-eq'all-array-items' -and $selected.Value.ValueKind-eq[System.Text.Json.JsonValueKind]::Array){$values=@($selected.Value.EnumerateArray())}else{$failures.Add("${feature}:$($selector.jsonPointer):selector-type");continue};foreach($value in $values){if($value.ValueKind-eq[System.Text.Json.JsonValueKind]::Null){continue};if($value.ValueKind-ne[System.Text.Json.JsonValueKind]::String){$failures.Add("${feature}:$($selector.jsonPointer):not-string");continue};$reference=$value.GetString();try{$null=Assert-SpecOpsRepositoryRelativePath $reference}catch{$failures.Add("${feature}:${reference}:invalid");continue};if(-not(Test-SpecOpsRepositoryPathExists $Context.Snapshot $reference)){$failures.Add("${feature}:${reference}:missing")}}}}
            return New-SpecOpsPassOrFail $Check.id ($failures.Count-eq 0) @(if($failures.Count-eq 0){'All non-null scalar and adrReferences array-item paths resolve inside the immutable subject.'}else{@(Get-SpecOpsEvalOrdinalSortedStrings $failures.ToArray())})
        }
        'state-lifecycle-consistency' {
            if(-not$Context.SchemaCapability.Available){return New-SpecOpsNotExecutedCheckResult $Check.id 'SCHEMA_ADAPTER_CAPABILITY_UNAVAILABLE'}
            $schemaReference='.specops/contracts/feature-state.schema.json';$failures=[System.Collections.Generic.List[string]]::new();$count=0;foreach($feature in $features){$path="Assets/Project/Docs/Specifications/$feature/SPECOPS_STATE.json";if(-not(Test-SpecOpsRepositoryPathExists $Context.Snapshot $path)){continue};$count++;$validation=Test-SpecOpsJsonAgainstSubjectSchema $Context (Read-SpecOpsSubjectUtf8 $Context $path) $schemaReference $Context.SchemaCapability;if(-not$validation.Executable){return New-SpecOpsNotExecutedCheckResult $Check.id 'SCHEMA_ADAPTER_CAPABILITY_UNAVAILABLE'};if(-not$validation.Valid){$failures.Add($path)}}
            return New-SpecOpsPassOrFail $Check.id ($failures.Count-eq 0) @(if($failures.Count-eq 0){"Lifecycle conditionals hold for $count feature-state instances; this does not prove evidence authenticity."}else{"Lifecycle mismatch: $([string]::Join(', ', $failures))"})
        }
    }
}

function Invoke-SpecOpsArchitectureCheck {
    param($Context,$Check)
    $asmdefs=@(Get-SpecOpsAsmdefPaths $Context)
    switch([string]$Check.id){
        'runtime-asmdef-set' {
            $expected=@($Check.passCondition.value.expected);$coverage=Compare-SpecOpsIdCoverage $expected $asmdefs
            return New-SpecOpsPassOrFail $Check.id $coverage.isExact @(if($coverage.isExact){'The immutable subject contains exactly the seven declared runtime asmdefs.'}else{"Missing=$([string]::Join(',',@($coverage.missingIds))); Extra=$([string]::Join(',',@($coverage.extraIds)))"})
        }
        'runtime-assembly-names' {
            $failures=[System.Collections.Generic.List[string]]::new();$expected=$Check.passCondition.value.expectedByPath;foreach($path in $expected.Keys){try{$doc=Read-SpecOpsSubjectJson $Context $path;$name=Get-SpecOpsJsonPointerValue $doc.Element '/name';if(-not$name.Found -or $name.Value.ValueKind-ne[System.Text.Json.JsonValueKind]::String -or -not[string]::Equals($name.Value.GetString(),[string]$expected[$path],[StringComparison]::Ordinal)){$failures.Add($path)}}catch{$failures.Add($path)}}
            return New-SpecOpsPassOrFail $Check.id ($failures.Count-eq 0) @(if($failures.Count-eq 0){'Every runtime asmdef declares its exact authoritative assembly name.'}else{"Assembly-name mismatch: $([string]::Join(', ', $failures))"})
        }
        'engine-independence-flags' {
            $failures=[System.Collections.Generic.List[string]]::new();foreach($path in @($Check.passCondition.value.subjects)){try{$doc=Read-SpecOpsSubjectJson $Context $path;$flag=Get-SpecOpsJsonPointerValue $doc.Element '/noEngineReferences';if(-not$flag.Found -or $flag.Value.ValueKind-ne[System.Text.Json.JsonValueKind]::True){$failures.Add($path)}}catch{$failures.Add($path)}}
            return New-SpecOpsPassOrFail $Check.id ($failures.Count-eq 0) @(if($failures.Count-eq 0){'Domain and Application explicitly set noEngineReferences=true.'}else{"Missing engine-independence flag: $([string]::Join(', ', $failures))"})
        }
        'runtime-project-reference-graph' {
            $guidRecords=[System.Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
            $nameRecords=[System.Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
            foreach($path in @($Context.Paths|Where-Object{$_ -cmatch '^Assets/.+\.asmdef$'})){
                $name=$null
                try{
                    $namePointer=Get-SpecOpsJsonPointerValue (Read-SpecOpsSubjectJson $Context $path).Element '/name'
                    if($namePointer.Found -and $namePointer.Value.ValueKind-eq[System.Text.Json.JsonValueKind]::String -and -not[string]::IsNullOrEmpty($namePointer.Value.GetString())){$name=$namePointer.Value.GetString()}
                }catch{}
                if($null-ne$name){if(-not$nameRecords.ContainsKey($name)){$nameRecords[$name]=[System.Collections.Generic.List[object]]::new()};$nameRecords[$name].Add([pscustomobject]@{Path=$path;Name=$name})}
                $meta="$path.meta"
                if(Test-SpecOpsRepositoryPathExists $Context.Snapshot $meta){
                    try{
                        $metaText=Read-SpecOpsSubjectUtf8 $Context $meta
                        $exactMatches=@([regex]::Matches($metaText,'(?m)^guid: ([0-9a-f]+)$'))
                        $candidateMatches=@([regex]::Matches($metaText,'(?m)^guid:\s*([0-9a-f]+).*$'))
                        $candidateGuids=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
                        foreach($candidate in $candidateMatches){
                            $guid=$candidate.Groups[1].Value
                            if(-not$candidateGuids.Add($guid)){continue}
                            if(-not$guidRecords.ContainsKey($guid)){$guidRecords[$guid]=[System.Collections.Generic.List[object]]::new()}
                            $guidRecords[$guid].Add([pscustomobject]@{Path=$path;Name=$name;MetaValid=($exactMatches.Count-eq1 -and [string]::Equals($exactMatches[0].Groups[1].Value,$guid,[StringComparison]::Ordinal))})
                        }
                    }catch{}
                }
            }
            $failures=[System.Collections.Generic.List[string]]::new();$allowed=$Check.passCondition.value.allowedTargetsByAssembly
            foreach($path in $asmdefs){
                try{
                    $doc=Read-SpecOpsSubjectJson $Context $path;$assembly=(Get-SpecOpsJsonPointerValue $doc.Element '/name').Value.GetString();$refs=Get-SpecOpsJsonPointerValue $doc.Element '/references'
                    if(-not$refs.Found -or $refs.Value.ValueKind-ne[System.Text.Json.JsonValueKind]::Array){throw 'references is not an array.'}
                    foreach($r in $refs.Value.EnumerateArray()){
                        if($r.ValueKind-ne[System.Text.Json.JsonValueKind]::String){$failures.Add("${assembly}:non-string-reference");continue}
                        $raw=$r.GetString();$target=$null
                        if($raw.StartsWith('GUID:',[StringComparison]::Ordinal)){
                            $guid=$raw.Substring(5)
                            if($guidRecords.ContainsKey($guid)){
                                $records=@($guidRecords[$guid])
                                if($records.Count-ne1 -or -not$records[0].MetaValid -or [string]::IsNullOrEmpty([string]$records[0].Name)){$failures.Add("$assembly->${raw}:unresolved-project-reference");continue}
                                $target=[string]$records[0].Name
                                if(-not$nameRecords.ContainsKey($target) -or @($nameRecords[$target]).Count-ne1){$failures.Add("$assembly->${raw}:ambiguous-project-assembly-name");continue}
                            }
                        }
                        elseif($nameRecords.ContainsKey($raw)){
                            $records=@($nameRecords[$raw])
                            if($records.Count-ne1){$failures.Add("$assembly->${raw}:unresolved-project-reference");continue}
                            $target=$raw
                        }
                        if($null-ne$target){$allowedTargets=[string[]]@($allowed[$assembly]);if([Array]::IndexOf($allowedTargets,$target)-lt0){$failures.Add("$assembly->$target")}}
                    }
                }catch{$failures.Add("${path}:invalid")}
            }
            return New-SpecOpsPassOrFail $Check.id ($failures.Count-eq 0) @(if($failures.Count-eq 0){'Every resolved project runtime reference is a subset of the authoritative Utility-expanded allowlist.'}else{@(Get-SpecOpsEvalOrdinalSortedStrings $failures.ToArray())})
        }
        'domain-application-source-boundary' {
            $failures=[System.Collections.Generic.List[string]]::new();$inconclusive=[System.Collections.Generic.List[string]]::new();foreach($root in @($Check.passCondition.value.roots)){foreach($path in @(Get-SpecOpsEvalOrdinalSortedStrings @($Context.Paths|Where-Object{$_.StartsWith("$root/",[StringComparison]::Ordinal)-and$_-match'\.cs$'}))){$scan=Test-SpecOpsCSharpLexicalBoundary (Read-SpecOpsSubjectUtf8 $Context $path);if(-not$scan.Supported){$inconclusive.Add("${path}:$($scan.Error)")}elseif($scan.Violations.Count-gt 0){$failures.Add("${path}:$([string]::Join(',', $scan.Violations))")}}}
            if($failures.Count-gt 0){return New-SpecOpsExecutedCheckResult $Check.id 'FAIL' @(Get-SpecOpsEvalOrdinalSortedStrings $failures.ToArray())}
            if($inconclusive.Count-gt 0){return New-SpecOpsExecutedCheckResult $Check.id 'INCONCLUSIVE' @(Get-SpecOpsEvalOrdinalSortedStrings $inconclusive.ToArray())}
            return New-SpecOpsExecutedCheckResult $Check.id 'PASS' @('The dependency-free lexical scanner found no prohibited Unity namespace prefixes or MonoBehaviour base types in Domain/Application source.')
        }
        'generated-artifacts-untracked' {
            $failures=[System.Collections.Generic.List[string]]::new();foreach($path in $Context.Paths){foreach($pattern in @($Check.passCondition.value.prohibitedPatterns)){if(Test-SpecOpsGeneratedPattern $path ([string]$pattern)){$failures.Add("${path}:$pattern");break}}}
            return New-SpecOpsPassOrFail $Check.id ($failures.Count-eq 0) @(if($failures.Count-eq 0){'No prohibited generated artifact occurs in subject X tracked paths; ignored local presence is excluded.'}else{@(Get-SpecOpsEvalOrdinalSortedStrings $failures.ToArray())})
        }
    }
}

function Invoke-SpecOpsDefinitionCheck {
    param($Context,$Check)
    $id=[string]$Check.id
    if($script:UnityCheckIds -ccontains $id){return New-SpecOpsNotExecutedCheckResult $id 'UNITY_ADAPTER_NOT_INSTALLED'}
    if(-not($script:E8C3CheckIds -ccontains $id)){throw(New-SpecOpsEvalException "No allowlisted owner for check: $id" 'INTERNAL_CHECK_OWNER_MISSING' 4)}
    if($id.StartsWith('contracts-',[StringComparison]::Ordinal)){return Invoke-SpecOpsContractsCheck $Context $Check}
    if($id -in @('authority-routes-resolve','feature-authority-triplets','feature-state-schema-valid','feature-id-directory-match','acceptance-id-exact-match','state-reference-resolution','state-lifecycle-consistency')){return Invoke-SpecOpsDerivedStateCheck $Context $Check}
    return Invoke-SpecOpsArchitectureCheck $Context $Check
}

function Get-SpecOpsExpectedDefinitionChecks {
    $map=[System.Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $map['specops-core-contract-integrity']=@('contracts-json-parse','contracts-id-unique','contracts-version-consistent','contracts-draft-declared','contracts-references-resolve','contracts-schema-valid')
    $map['specops-derived-state-consistency']=@('authority-routes-resolve','feature-authority-triplets','feature-state-schema-valid','feature-id-directory-match','acceptance-id-exact-match','state-reference-resolution','state-lifecycle-consistency')
    $map['unity-clean-architecture-static']=@('runtime-asmdef-set','runtime-assembly-names','engine-independence-flags','runtime-project-reference-graph','domain-application-source-boundary','generated-artifacts-untracked')
    $map['unity-editmode-validation']=$script:UnityCheckIds
    return $map
}

function Get-SpecOpsExpectedMethods {
    $map=[System.Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    foreach($id in @('contracts-json-parse','contracts-id-unique','contracts-version-consistent','contracts-draft-declared','feature-id-directory-match','runtime-assembly-names','engine-independence-flags','runtime-project-reference-graph')){$map[$id]='static-json-inspection'}
    foreach($id in @('contracts-references-resolve','authority-routes-resolve','state-reference-resolution')){$map[$id]='reference-resolution'}
    foreach($id in @('contracts-schema-valid','feature-state-schema-valid','state-lifecycle-consistency')){$map[$id]='schema-validation'}
    foreach($id in @('runtime-asmdef-set','acceptance-id-exact-match')){$map[$id]='exact-set-comparison'}
    foreach($id in @('feature-authority-triplets','generated-artifacts-untracked')){$map[$id]='static-repository-inspection'}
    $map['domain-application-source-boundary']='static-source-boundary'
    foreach($id in $script:UnityCheckIds){$map[$id]='unity-editmode-execution'}
    return $map
}

function Test-SpecOpsContainsExecutableField {
    param($Value)
    if($Value-is[Collections.IDictionary]){
        foreach($key in $Value.Keys){
            if([string]$key -in @('command','commands','script','executable','arguments','shell')){return $true}
            if(Test-SpecOpsContainsExecutableField $Value[$key]){return $true}
        }
    }elseif($Value-is[Collections.IEnumerable] -and $Value-isnot[string]){foreach($item in $Value){if(Test-SpecOpsContainsExecutableField $item){return $true}}}
    return $false
}

function Assert-SpecOpsSupportedPassCondition {
    param($Check)
    $types=[System.Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    foreach($id in @('contracts-json-parse','contracts-id-unique','contracts-version-consistent','contracts-draft-declared','contracts-schema-valid','feature-state-schema-valid','feature-id-directory-match','state-lifecycle-consistency','runtime-assembly-names','domain-application-source-boundary')){$types[$id]='all-items-conform'}
    foreach($id in @('contracts-references-resolve','authority-routes-resolve','state-reference-resolution')){$types[$id]='references-resolve'}
    foreach($id in @('runtime-asmdef-set','acceptance-id-exact-match')){$types[$id]='exact-set'}
    $types['feature-authority-triplets']='required-items-present';$types['engine-independence-flags']='equals';$types['runtime-project-reference-graph']='subset-of-allowlist';$types['generated-artifacts-untracked']='tracked-paths-absent'
    $types['unity-version-match']='equals';$types['unity-compilation-success']='zero-count';$types['editmode-suite-executed']='equals';$types['editmode-required-tests-discovered']='required-items-present';$types['editmode-zero-failures']='zero-count';$types['unity-exit-success']='equals';$types['unity-tracked-state-preserved']='zero-count'
    $id=[string]$Check.id
    if(-not$types.ContainsKey($id)-or -not[string]::Equals([string]$Check.passCondition.type,$types[$id],[StringComparison]::Ordinal)-or (Test-SpecOpsContainsExecutableField $Check.passCondition.value)){throw(New-SpecOpsEvalException "Unsupported pass-condition form: $id" 'DEFINITION_PASS_CONDITION_UNSUPPORTED')}
    $value=$Check.passCondition.value
    switch($id){
        'contracts-json-parse'{if($value.rule.operation-cne'strict-json-parse' -or $value.rule.commentsAllowed -or $value.rule.trailingCommasAllowed -or $value.rule.duplicateMemberNamesAllowed){throw(New-SpecOpsEvalException 'Unsupported strict JSON pass condition.' 'DEFINITION_PASS_CONDITION_UNSUPPORTED')}}
        'contracts-id-unique'{if($value.rule.operation-cne'root-property-nonempty-and-unique' -or $value.rule.property-cne'$id' -or $value.rule.equality-cne'ordinal'){throw(New-SpecOpsEvalException 'Unsupported contract ID pass condition.' 'DEFINITION_PASS_CONDITION_UNSUPPORTED')}}
        'contracts-version-consistent'{if($value.rule.operation-cne'root-property-equality' -or $value.rule.leftJsonPointer-cne'/x-contract-version' -or $value.rule.rightJsonPointer-cne'/properties/contractVersion/const'){throw(New-SpecOpsEvalException 'Unsupported contract version pass condition.' 'DEFINITION_PASS_CONDITION_UNSUPPORTED')}}
        'contracts-draft-declared'{if($value.rule.operation-cne'root-property-equals' -or $value.rule.jsonPointer-cne'/$schema' -or $value.rule.expected-cne'https://json-schema.org/draft/2020-12/schema'){throw(New-SpecOpsEvalException 'Unsupported contract dialect pass condition.' 'DEFINITION_PASS_CONDITION_UNSUPPORTED')}}
        'contracts-references-resolve'{if($value.allowedRoot-cne'.specops/contracts' -or $value.networkAllowed -or -not$value.fragmentsMustResolve){throw(New-SpecOpsEvalException 'Unsupported contract reference pass condition.' 'DEFINITION_PASS_CONDITION_UNSUPPORTED')}}
        'contracts-schema-valid'{if($value.rule.operation-cne'schema-document-valid' -or $value.rule.dialect-cne'https://json-schema.org/draft/2020-12/schema' -or $value.rule.networkAllowed){throw(New-SpecOpsEvalException 'Unsupported schema-document pass condition.' 'DEFINITION_PASS_CONDITION_UNSUPPORTED')}}
        'authority-routes-resolve'{if($value.source-cne'.specops/specops.json' -or $value.allowedRoot-cne'.' -or $value.networkAllowed){throw(New-SpecOpsEvalException 'Unsupported authority-route pass condition.' 'DEFINITION_PASS_CONDITION_UNSUPPORTED')}}
        'feature-authority-triplets'{if($value.root-cne'Assets/Project/Docs/Specifications' -or $value.directorySelection.depth-cne1 -or @($value.directorySelection.excludeNames)-cnotcontains'_templates'){throw(New-SpecOpsEvalException 'Unsupported feature selection pass condition.' 'DEFINITION_PASS_CONDITION_UNSUPPORTED')}}
        'feature-state-schema-valid'{if($value.schemaReference-cne'.specops/contracts/feature-state.schema.json' -or $value.networkAllowed){throw(New-SpecOpsEvalException 'Unsupported feature-state schema pass condition.' 'DEFINITION_PASS_CONDITION_UNSUPPORTED')}}
        'feature-id-directory-match'{if($value.rule.operation-cne'json-property-equals-containing-directory' -or $value.rule.jsonPointer-cne'/featureId'){throw(New-SpecOpsEvalException 'Unsupported feature ID pass condition.' 'DEFINITION_PASS_CONDITION_UNSUPPORTED')}}
        'acceptance-id-exact-match'{if($value.lineParsing.encoding-cne'UTF-8' -or $value.lineParsing.headingPattern-cne'^### (AC-[0-9]{3}) — .+$' -or -not$value.lineParsing.caseSensitive -or $value.comparison-cne'ordinal-exact-set'){throw(New-SpecOpsEvalException 'Unsupported acceptance parser pass condition.' 'DEFINITION_PASS_CONDITION_UNSUPPORTED')}}
        'state-reference-resolution'{if($value.networkAllowed -or $value.nullPolicy-cne'allowed-and-skipped'){throw(New-SpecOpsEvalException 'Unsupported state-reference pass condition.' 'DEFINITION_PASS_CONDITION_UNSUPPORTED')};$actual=@($value.selectors|ForEach-Object{"$($_.jsonPointer)|$($_.selection)"});$expected=@('/review/reference|scalar','/implementationPlan/reference|scalar','/validation/reference|scalar','/sync/reference|scalar','/adrReferences|all-array-items');$coverage=Compare-SpecOpsIdCoverage $expected $actual;if(-not$coverage.IsExact){throw(New-SpecOpsEvalException 'Unsupported state-reference selectors.' 'DEFINITION_PASS_CONDITION_UNSUPPORTED')}}
        'state-lifecycle-consistency'{if($value.rule.operation-cne'schema-conditional-lifecycle-conformance' -or $value.rule.schemaReference-cne'.specops/contracts/feature-state.schema.json'){throw(New-SpecOpsEvalException 'Unsupported lifecycle pass condition.' 'DEFINITION_PASS_CONDITION_UNSUPPORTED')}}
        'runtime-asmdef-set'{if($value.inventory.root-cne'Assets/Project/Code/Runtime' -or $value.comparison-cne'repository-relative-path-ordinal'){throw(New-SpecOpsEvalException 'Unsupported runtime inventory pass condition.' 'DEFINITION_PASS_CONDITION_UNSUPPORTED')}}
        'runtime-assembly-names'{if($value.jsonPointer-cne'/name' -or $value.equality-cne'ordinal-string'){throw(New-SpecOpsEvalException 'Unsupported assembly-name pass condition.' 'DEFINITION_PASS_CONDITION_UNSUPPORTED')}}
        'engine-independence-flags'{if($value.jsonPointer-cne'/noEngineReferences' -or $value.expected-cne$true){throw(New-SpecOpsEvalException 'Unsupported engine-independence pass condition.' 'DEFINITION_PASS_CONDITION_UNSUPPORTED')}}
        'runtime-project-reference-graph'{
            $roots=@($value.semanticResolution.projectAsmdefRoots)
            if($value.referenceJsonPointer-cne'/references' -or $value.semanticResolution.guidPrefix-cne'GUID:' -or -not$value.semanticResolution.exactAssemblyName -or $roots.Count-ne1 -or $roots[0]-cne'Assets' -or $value.semanticResolution.guidSource-cne'adjacent-asmdef-meta' -or $value.semanticResolution.comparison-cne'ordinal-assembly-name' -or -not$value.semanticResolution.externalNonProjectReferencesExcluded -or $value.semanticResolution.unresolvedProjectReference-cne'reject' -or $value.unusedAllowedTargetsRequired){throw(New-SpecOpsEvalException 'Unsupported project-graph pass condition.' 'DEFINITION_PASS_CONDITION_UNSUPPORTED')}
        }
        'domain-application-source-boundary'{if($value.analysisModel-cne'csharp-lexical-tokens-v1' -or $value.comparison-cne'ordinal-token'){throw(New-SpecOpsEvalException 'Unsupported C# boundary pass condition.' 'DEFINITION_PASS_CONDITION_UNSUPPORTED')}}
        'generated-artifacts-untracked'{if($value.inventory-cne'tracked-subject-paths' -or $value.pathSemantics-cne'repository-relative-forward-slash' -or -not$value.ignoredLocalPresenceIsNotFailure){throw(New-SpecOpsEvalException 'Unsupported generated-artifact pass condition.' 'DEFINITION_PASS_CONDITION_UNSUPPORTED')}}
    }
}

function Get-SpecOpsInstalledDefinition {
    param($Context,[string]$DefinitionId)
    if([string]::IsNullOrEmpty($DefinitionId)-or $DefinitionId -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$'){
        throw(New-SpecOpsEvalException 'DefinitionId is not a valid installed definition identifier.' 'INVALID_DEFINITION_ID')
    }
    $expected=Get-SpecOpsExpectedDefinitionChecks
    if(-not$expected.ContainsKey($DefinitionId)){throw(New-SpecOpsEvalException "Definition is not installed or supported: $DefinitionId" 'DEFINITION_NOT_INSTALLED')}
    $config=Read-SpecOpsSubjectJson $Context '.specops/specops.json'
    $evalRootPointer=Get-SpecOpsJsonPointerValue $config.Element '/paths/evalRoot'
    if(-not$evalRootPointer.Found -or $evalRootPointer.Value.ValueKind-ne[System.Text.Json.JsonValueKind]::String){throw(New-SpecOpsEvalException 'Configured eval root is missing.' 'EVAL_ROOT_INVALID')}
    $evalRoot=$evalRootPointer.Value.GetString();$null=Assert-SpecOpsRepositoryRelativePath $evalRoot
    $path="$($evalRoot.TrimEnd('/'))/$DefinitionId.eval.json"
    if(-not(Test-SpecOpsRepositoryPathExists $Context.Snapshot $path)){throw(New-SpecOpsEvalException "Installed definition path is absent from subject X: $path" 'DEFINITION_NOT_INSTALLED')}
    $definitionJson=Read-SpecOpsSubjectJson $Context $path
    $schemaValidation=Test-SpecOpsJsonAgainstSubjectSchema $Context $definitionJson.Text '.specops/contracts/eval-definition.schema.json' $Context.SchemaCapability
    if(-not$schemaValidation.Executable){throw(New-SpecOpsEvalException 'Definition schema validation capability is unavailable.' 'DEFINITION_SCHEMA_CAPABILITY_UNAVAILABLE' 2)}
    if(-not$schemaValidation.Valid){throw(New-SpecOpsEvalException "Installed definition fails eval-definition contract: $($schemaValidation.Detail)" 'DEFINITION_SCHEMA_INVALID' 2)}
    $definition=$definitionJson.Value
    if(-not[string]::Equals([string]$definition.definitionId,$DefinitionId,[StringComparison]::Ordinal)){throw(New-SpecOpsEvalException 'Installed definition ID does not match the requested ID.' 'DEFINITION_ID_MISMATCH')}
    if(-not[string]::Equals([string]$definition.contractVersion,$script:DefinitionContractVersion,[StringComparison]::Ordinal)-or -not[string]::Equals([string]$definition.definitionVersion,'1.0.0',[StringComparison]::Ordinal)){throw(New-SpecOpsEvalException 'Installed definition version is unsupported.' 'DEFINITION_VERSION_UNSUPPORTED')}
    if(-not[string]::Equals([string]$definition.contentIdentity.algorithm,$script:ProfileId,[StringComparison]::Ordinal)){throw(New-SpecOpsEvalException 'Installed definition identity profile is unsupported.' 'DEFINITION_IDENTITY_PROFILE_UNSUPPORTED')}
    $digest=Get-SpecOpsCanonicalDefinitionDigest -Bytes (Get-SpecOpsRepositoryBlobBytes $Context.Snapshot $path)
    if(-not[string]::Equals([string]$definition.contentIdentity.value,$digest,[StringComparison]::Ordinal)){throw(New-SpecOpsEvalException 'Installed definition content identity does not match subject X.' 'DEFINITION_IDENTITY_MISMATCH')}
    $ids=@($definition.checks|ForEach-Object{[string]$_.id});$unique=Test-SpecOpsUniqueIds -Items @($definition.checks) -IdProperty 'id'
    if(-not$unique.IsValid){throw(New-SpecOpsEvalException 'Installed definition contains duplicate or missing check IDs.' 'DEFINITION_CHECK_IDS_INVALID')}
    $coverage=Compare-SpecOpsIdCoverage -ExpectedIds $expected[$DefinitionId] -ActualIds $ids
    if(-not$coverage.isExact){throw(New-SpecOpsEvalException 'Installed definition check inventory is not the supported E8C2 inventory.' 'DEFINITION_CHECK_INVENTORY_UNSUPPORTED')}
    $methods=Get-SpecOpsExpectedMethods
    foreach($check in @($definition.checks)){if(-not$methods.ContainsKey([string]$check.id)-or -not[string]::Equals([string]$check.evaluationMethod,$methods[[string]$check.id],[StringComparison]::Ordinal)){throw(New-SpecOpsEvalException "Unsupported evaluation method binding: $($check.id)" 'DEFINITION_METHOD_UNSUPPORTED')};Assert-SpecOpsSupportedPassCondition $check}
    if(-not$script:SupportedDefinitionIdentities.Contains($DefinitionId)-or -not[string]::Equals([string]$script:SupportedDefinitionIdentities[$DefinitionId],$digest,[StringComparison]::Ordinal)){throw(New-SpecOpsEvalException 'Installed definition semantics are not supported by this producer.' 'DEFINITION_SEMANTICS_UNSUPPORTED')}
    return [pscustomobject]@{Path=$path;Value=$definition;Bytes=(Get-SpecOpsRepositoryBlobBytes $Context.Snapshot $path);RecomputedIdentity=$digest}
}

function Get-SpecOpsRepositoryIdentity {
    param($Context)
    $config=Read-SpecOpsSubjectJson $Context '.specops/specops.json';$identity=Get-SpecOpsJsonPointerValue $config.Element '/repository/identity'
    if(-not$identity.Found -or $identity.Value.ValueKind-ne[System.Text.Json.JsonValueKind]::String -or [string]::IsNullOrEmpty($identity.Value.GetString())){throw(New-SpecOpsEvalException 'Subject X does not declare repository.identity.' 'REPOSITORY_IDENTITY_MISSING')}
    return $identity.Value.GetString()
}

function Get-SpecOpsOverallResult {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object[]] $CheckResults)
    if(@($CheckResults|Where-Object{$_.result-eq'FAIL'}).Count-gt 0){return 'FAIL'}
    if(@($CheckResults|Where-Object{$_.result-in@('INCONCLUSIVE','NOT_EXECUTED')}).Count-gt 0){return 'INCONCLUSIVE'}
    return 'PASS'
}

function Assert-SpecOpsEvalResultInvariants {
    param($Result,$Definition)
    $expected=@($Definition.Value.checks|ForEach-Object{[string]$_.id});$actual=@($Result.checkResults|ForEach-Object{[string]$_.id});$coverage=Compare-SpecOpsIdCoverage $expected $actual
    if(-not$coverage.isExact){throw(New-SpecOpsEvalException 'Producer-generated check coverage mismatch.' 'INTERNAL_CHECK_COVERAGE_FAILURE' 4)}
    for($i=0;$i-lt$expected.Count;$i++){if(-not[string]::Equals($expected[$i],$actual[$i],[StringComparison]::Ordinal)){throw(New-SpecOpsEvalException 'Producer-generated check ordering mismatch.' 'INTERNAL_CHECK_ORDER_FAILURE' 4)}}
    $aggregate=Get-SpecOpsOverallResult @($Result.checkResults);if(-not[string]::Equals($aggregate,[string]$Result.overallResult,[StringComparison]::Ordinal)){throw(New-SpecOpsEvalException 'Producer-generated aggregate mismatch.' 'INTERNAL_AGGREGATE_FAILURE' 4)}
    if(-not[string]::Equals([string]$Result.provenance.executedDefinition.id,[string]$Definition.Value.definitionId,[StringComparison]::Ordinal)-or -not[string]::Equals([string]$Result.provenance.executedDefinition.version,[string]$Definition.Value.definitionVersion,[StringComparison]::Ordinal)-or -not[string]::Equals([string]$Result.definitionContentIdentity.value,[string]$Definition.RecomputedIdentity,[StringComparison]::Ordinal)){throw(New-SpecOpsEvalException 'Producer-generated definition binding mismatch.' 'INTERNAL_DEFINITION_BINDING_FAILURE' 4)}
    foreach($check in @($Result.checkResults)){if(-not$check.executed -and (-not[string]::Equals([string]$check.result,'NOT_EXECUTED',[StringComparison]::Ordinal)-or @($check.observations).Count-ne 0 -or [string]::IsNullOrEmpty([string]$check.notExecutedReason))){throw(New-SpecOpsEvalException 'Producer-generated non-execution semantics are invalid.' 'INTERNAL_NONEXECUTION_FAILURE' 4)}}
    if(-not(Test-SpecOpsStrictUtcTimestamp ([string]$Result.provenance.executedAtUtc))){throw(New-SpecOpsEvalException 'Producer-generated executedAtUtc is not strict UTC.' 'INTERNAL_TIMESTAMP_FAILURE' 4)}
    $execution=[string]$Result.provenance.executionId;if($execution -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'){throw(New-SpecOpsEvalException 'Producer-generated executionId is not lowercase canonical UUIDv4.' 'INTERNAL_EXECUTION_ID_FAILURE' 4)}
}

function Invoke-SpecOpsEvaluation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $RepositoryAdapter,
        [Parameter(Mandatory)] [string] $DefinitionId,
        $SchemaCapability
    )
    $snapshot=Get-SpecOpsRepositorySnapshot $RepositoryAdapter
    $binding=Test-SpecOpsProducerImplementationBinding $RepositoryAdapter $snapshot $script:ProducerPaths
    if(-not$binding.IsBound){throw(New-SpecOpsEvalException "Canonical producer implementation is not bound to subject X: $([string]::Join(', ', $binding.Failures))" 'PRODUCER_NOT_BOUND')}
    if($null-eq$SchemaCapability){$SchemaCapability=Get-SpecOpsSchemaAdapterCapability}
    if(-not$SchemaCapability.Available){throw(New-SpecOpsEvalException 'Eval-result schema validation capability is unavailable.' 'RESULT_SCHEMA_CAPABILITY_UNAVAILABLE' 3)}
    $context=[pscustomobject]@{Adapter=$RepositoryAdapter;Snapshot=$snapshot;Paths=@(Get-SpecOpsRepositoryPaths $snapshot);SchemaCapability=$SchemaCapability}
    $repositoryIdentity=Get-SpecOpsRepositoryIdentity $context
    $definition=Get-SpecOpsInstalledDefinition $context $DefinitionId
    $results=[System.Collections.Generic.List[object]]::new()
    foreach($check in @($definition.Value.checks)){$results.Add((Invoke-SpecOpsDefinitionCheck $context $check))}
    $overall=Get-SpecOpsOverallResult @($results)
    $limitations=[System.Collections.Generic.List[string]]::new();$unknowns=[System.Collections.Generic.List[string]]::new()
    if(@($results|Where-Object{$_.Contains('notExecutedReason') -and [string]::Equals([string]$_.notExecutedReason,'UNITY_ADAPTER_NOT_INSTALLED',[StringComparison]::Ordinal)}).Count-gt 0){$limitations.Add('Unity execution is outside E8C3; the E8C4 Unity adapter is not installed.');$unknowns.Add('UNITY_ADAPTER_NOT_INSTALLED')}
    if(@($results|Where-Object{$_.Contains('notExecutedReason') -and [string]::Equals([string]$_.notExecutedReason,'SCHEMA_ADAPTER_CAPABILITY_UNAVAILABLE',[StringComparison]::Ordinal)}).Count-gt 0){$limitations.Add('A check-specific schema capability was unavailable.');$unknowns.Add('SCHEMA_ADAPTER_CAPABILITY_UNAVAILABLE')}
    $timestamp=[DateTimeOffset]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'",[Globalization.CultureInfo]::InvariantCulture)
    if(-not(Test-SpecOpsStrictUtcTimestamp $timestamp)){throw(New-SpecOpsEvalException 'Generated timestamp failed strict UTC validation.' 'INTERNAL_TIMESTAMP_FAILURE' 4)}
    $targetScope=@($definition.Value.targetScope|ForEach-Object{$item=[ordered]@{type=[string]$_.type;id=[string]$_.id};if($_.Contains('reference')){$item.reference=[string]$_.reference};$item})
    $result=[ordered]@{
        contractVersion='1.0.0'
        provenance=[ordered]@{
            contractVersion='1.0.0'
            subject=[ordered]@{type='repository';id=$repositoryIdentity;revision=[ordered]@{scheme=$snapshot.RevisionScheme;identifier=$snapshot.Revision}}
            executionId=[Guid]::NewGuid().ToString('D')
            producer=[ordered]@{id="$repositoryIdentity/eval-producer";version="$($snapshot.RevisionScheme):$($snapshot.Revision)"}
            executedDefinition=[ordered]@{type='eval-definition';id=[string]$definition.Value.definitionId;version=[string]$definition.Value.definitionVersion;reference=$definition.Path}
            governingContracts=@(
                [ordered]@{id='eval-result.schema.json';version='1.0.0';reference='.specops/contracts/eval-result.schema.json'},
                [ordered]@{id='evidence-provenance.schema.json';version='1.0.0';reference='.specops/contracts/evidence-provenance.schema.json'},
                [ordered]@{id='eval-definition.schema.json';version='1.0.0';reference='.specops/contracts/eval-definition.schema.json'}
            )
            targetScope=$targetScope
            executedAtUtc=$timestamp
            limitations=@($limitations)
            unresolvedUnknowns=@($unknowns)
        }
        definitionContentIdentity=[ordered]@{algorithm=$script:ProfileId;value=$definition.RecomputedIdentity}
        overallResult=$overall
        checkResults=@($results)
    }
    Assert-SpecOpsEvalResultInvariants $result $definition
    $current=Test-SpecOpsRepositorySnapshotCurrent $RepositoryAdapter $snapshot
    $bindingAfter=Test-SpecOpsProducerImplementationBinding $RepositoryAdapter $snapshot $script:ProducerPaths
    if(-not$current.IsCurrent -or -not$bindingAfter.IsBound){throw(New-SpecOpsEvalException 'Repository subject or producer basis changed during execution.' 'SUBJECT_CHANGED_DURING_EXECUTION')}
    $json=$result|ConvertTo-Json -Depth 100 -Compress
    $validation=Test-SpecOpsJsonAgainstSubjectSchema $context $json '.specops/contracts/eval-result.schema.json' $SchemaCapability
    if(-not$validation.Executable){throw(New-SpecOpsEvalException 'Eval-result schema validation capability is unavailable.' 'RESULT_SCHEMA_CAPABILITY_UNAVAILABLE' 3)}
    if(-not$validation.Valid){throw(New-SpecOpsEvalException "Generated eval-result does not conform: $($validation.Detail)" 'RESULT_CONFORMANCE_FAILURE' 3)}
    $current=Test-SpecOpsRepositorySnapshotCurrent $RepositoryAdapter $snapshot
    if(-not$current.IsCurrent){throw(New-SpecOpsEvalException 'Repository subject changed during result validation.' 'SUBJECT_CHANGED_DURING_EXECUTION')}
    return $result
}

Export-ModuleMember -Function @(
    'Get-SpecOpsOverallResult',
    'Get-SpecOpsSchemaAdapterCapability',
    'Invoke-SpecOpsEvaluation',
    'Read-SpecOpsStrictJsonBytes',
    'Test-SpecOpsCSharpLexicalBoundary',
    'Test-SpecOpsStrictUtcTimestamp'
)
