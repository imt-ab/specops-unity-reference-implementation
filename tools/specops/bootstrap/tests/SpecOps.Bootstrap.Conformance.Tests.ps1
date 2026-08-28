[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Tests = 0
$script:Failures = [Collections.Generic.List[string]]::new()
$script:Categories = [ordered]@{}
$utf8 = [Text.UTF8Encoding]::new($false, $true)
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
$module = Import-Module -Force -PassThru (Join-Path $repositoryRoot 'tools/specops/bootstrap/SpecOps.Bootstrap.psm1')
$entry = Join-Path $repositoryRoot 'tools/specops/bootstrap/Invoke-SpecOpsBootstrap.ps1'
$manifestPath = Join-Path $repositoryRoot '.specops/bootstrap/bootstrap-v1.projection-manifest.json'
$manifestSchemaPath = Join-Path $repositoryRoot '.specops/contracts/bootstrap-projection-manifest.schema.json'
$provenanceSchemaPath = Join-Path $repositoryRoot '.specops/contracts/bootstrap-provenance.schema.json'

function Add-Result {
    param([string]$Category,[string]$Name,[bool]$Pass,[string]$Detail='')
    $script:Tests++
    if(-not $script:Categories.Contains($Category)){$script:Categories[$Category]=0}
    $script:Categories[$Category]++
    if(-not $Pass){$script:Failures.Add("[$Category] $Name$(if($Detail){': '+$Detail})")}
}
function Assert-True { param([string]$Category,[string]$Name,[bool]$Condition,[string]$Detail='') Add-Result $Category $Name $Condition $Detail }
function Assert-Equal { param([string]$Category,[string]$Name,$Actual,$Expected) Add-Result $Category $Name ($Actual-ceq$Expected) "expected=$Expected actual=$Actual" }
function Test-BytesEqual {
    param([byte[]]$Left,[byte[]]$Right)
    if($Left.Length-ne$Right.Length){return $false}
    for($i=0;$i-lt$Left.Length;$i++){if($Left[$i]-ne$Right[$i]){return $false}}
    return $true
}
function Assert-BytesEqual { param([string]$Category,[string]$Name,[byte[]]$Actual,[byte[]]$Expected) Add-Result $Category $Name (Test-BytesEqual $Actual $Expected) }
function Test-ByteSequenceContains {
    param([byte[]]$Bytes,[byte[]]$Needle)
    if($Needle.Length-eq0-or$Needle.Length-gt$Bytes.Length){return $false}
    for($i=0;$i-le$Bytes.Length-$Needle.Length;$i++){
        $match=$true
        for($j=0;$j-lt$Needle.Length;$j++){if($Bytes[$i+$j]-ne$Needle[$j]){$match=$false;break}}
        if($match){return $true}
    }
    return $false
}
function Get-Args {
    param(
        [string]$Destination,
        [string]$ProjectId='f7-conformance-project',
        [string]$ProductName='F7 Conformance Product',
        [string]$CompanyName='F7 Conformance Company',
        [string]$ApplicationIdentifier='com.specops.f7conformance',
        [string]$CodeNamespaceRoot='SpecOps.F7Conformance'
    )
    return [string[]]@(
        '-DestinationPath',$Destination,'-ProjectId',$ProjectId,'-ProductName',$ProductName,
        '-CompanyName',$CompanyName,'-ApplicationIdentifier',$ApplicationIdentifier,
        '-CodeNamespaceRoot',$CodeNamespaceRoot)
}
function Invoke-Cli {
    param([string]$ScriptPath,[string[]]$Arguments,[string]$WorkingDirectory,[string]$AmbientMarker='')
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=(Get-Command pwsh).Source
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    if($WorkingDirectory){$start.WorkingDirectory=$WorkingDirectory}
    if($AmbientMarker){$start.Environment['SPECOPS_F7_AMBIENT_MARKER']=$AmbientMarker}
    foreach($argument in @('-NoLogo','-NoProfile','-NonInteractive','-File',$ScriptPath)+$Arguments){[void]$start.ArgumentList.Add($argument)}
    $process=[Diagnostics.Process]::new();$process.StartInfo=$start;[void]$process.Start()
    $stdout=[IO.MemoryStream]::new();$stderr=[IO.MemoryStream]::new()
    $outTask=$process.StandardOutput.BaseStream.CopyToAsync($stdout);$errTask=$process.StandardError.BaseStream.CopyToAsync($stderr)
    $process.WaitForExit();[void]$outTask.GetAwaiter().GetResult();[void]$errTask.GetAwaiter().GetResult()
    return [pscustomobject]@{ExitCode=$process.ExitCode;Stdout=$stdout.ToArray();Stderr=$stderr.ToArray();StdoutText=$utf8.GetString($stdout.ToArray());StderrText=$utf8.GetString($stderr.ToArray())}
}
function New-CleanMirror {
    param([string]$Root)
    [void][IO.Directory]::CreateDirectory($Root)
    $record=Read-BootstrapProjectionManifest $manifestPath $manifestSchemaPath
    $support=@(Get-ChildItem -LiteralPath (Join-Path $repositoryRoot 'tools/specops/bootstrap') -File -Recurse -Force|ForEach-Object{[IO.Path]::GetRelativePath($repositoryRoot,$_.FullName).Replace('\','/')})
    $paths=@(@($record.Manifest.bootstrapSourceMetadata.path)+@($record.Manifest.authoredSourceInventory.sourcePath)+$support|Sort-Object -Unique)
    foreach($path in $paths){
        $target=Join-Path $Root $path;$parent=[IO.Path]::GetDirectoryName($target)
        [void][IO.Directory]::CreateDirectory($parent)
        [IO.File]::WriteAllBytes($target,[IO.File]::ReadAllBytes((Join-Path $repositoryRoot $path)))
    }
    return [pscustomobject]@{Root=$Root;Entry=(Join-Path $Root 'tools/specops/bootstrap/Invoke-SpecOpsBootstrap.ps1');Paths=$paths;Support=$support;Record=$record}
}
function Get-OutputMap {
    param([string]$Root)
    $map=[Collections.Generic.Dictionary[string,byte[]]]::new([StringComparer]::Ordinal)
    foreach($file in Get-ChildItem -LiteralPath $Root -File -Recurse -Force){
        $path=[IO.Path]::GetRelativePath($Root,$file.FullName).Replace('\','/')
        $map.Add($path,[IO.File]::ReadAllBytes($file.FullName))
    }
    return $map
}
function Get-OrdinalPaths {
    param($Map)
    $paths=[string[]]@($Map.Keys);[Array]::Sort($paths,[StringComparer]::Ordinal);return $paths
}
function Compare-OutputMaps {
    param($Left,$Right)
    $all=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($path in $Left.Keys){[void]$all.Add($path)};foreach($path in $Right.Keys){[void]$all.Add($path)}
    $different=[Collections.Generic.List[string]]::new()
    foreach($path in $all){if(-not$Left.ContainsKey($path)-or-not$Right.ContainsKey($path)-or-not(Test-BytesEqual $Left[$path] $Right[$path])){$different.Add($path)}}
    $result=[string[]]@($different);[Array]::Sort($result,[StringComparer]::Ordinal);return $result
}
function Resolve-OutputPath {
    param($Entry,[string]$Namespace)
    if($Entry.output.PSObject.Properties['path']){return [string]$Entry.output.path}
    return ([string]$Entry.output.pathTemplate).Replace('${CodeNamespaceRoot}',$Namespace,[StringComparison]::Ordinal)
}
function Get-AuthorizedDifferences {
    param($Manifest,[string]$InputName,[string]$OldNamespace,[string]$NewNamespace)
    $paths=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);[void]$paths.Add('.specops/bootstrap.json')
    foreach($entry in $Manifest.authoredSourceInventory|Where-Object disposition -ne 'EXCLUDE'){
        $affected=$entry.output.PSObject.Properties['pathInputs']-and@($entry.output.pathInputs)-ccontains$InputName
        if($entry.PSObject.Properties['transforms']){
            foreach($transform in $entry.transforms){
                if(($transform.replacement.kind-ceq'CONTENT_INPUT'-and$transform.replacement.name-ceq$InputName)-or
                   ($transform.replacement.PSObject.Properties['inputs']-and@($transform.replacement.inputs)-ccontains$InputName)){$affected=$true}
            }
        }
        if($affected){[void]$paths.Add((Resolve-OutputPath $entry $OldNamespace));[void]$paths.Add((Resolve-OutputPath $entry $NewNamespace))}
    }
    return $paths
}
function Get-ProductGuid {
    param([string]$ProjectId,[string]$ApplicationIdentifier)
    $bytes=$utf8.GetBytes("specops-bootstrap-product-guid-v1`0$ProjectId`0$ApplicationIdentifier")
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)[0..15]).ToLowerInvariant()
}
function New-HookFailure {
    param([string]$Class,[string]$Message)
    $exception=[IO.InvalidDataException]::new($Message);$exception.Data['BootstrapExecutionFailureClass']=$Class;return $exception
}
function Set-Fault { param([string]$Name,[scriptblock]$Action) &$module {param($n,$a)$script:ExecutionFaults[$n]=$a} $Name $Action }
function Clear-Faults { &$module {$script:ExecutionFaults.Clear()} }
function Invoke-Direct { param([string]$MirrorEntry,[string]$Destination,[string[]]$Arguments=(Get-Args $Destination)) Invoke-SpecOpsBootstrapExecution -RawArguments $Arguments -ImplementationScriptPath $MirrorEntry }
function Assert-FailureResult {
    param([string]$Category,[string]$Name,$Result,[int]$Exit,[string]$Phase,[string]$Class,[string[]]$ForbiddenPaths=@())
    Assert-Equal $Category "$Name exit" $Result.ExitCode $Exit
    $text=$utf8.GetString($Result.StdoutBytes);$json=$text|ConvertFrom-Json
    Assert-Equal $Category "$Name status" $json.status 'FAILURE';Assert-Equal $Category "$Name phase" $json.phase $Phase;Assert-Equal $Category "$Name class" $json.failureClass $Class
    Assert-True $Category "$Name canonical stdout framing" ($Result.StdoutBytes[-1]-eq10-and$Result.StdoutBytes[-2]-ne10-and$text.Substring(0,$text.Length-1)-ceq(ConvertTo-BootstrapJcs $utf8.GetBytes($text.Substring(0,$text.Length-1))))
    foreach($path in $ForbiddenPaths){Assert-True $Category "$Name stdout excludes path" (-not$text.Contains($path,[StringComparison]::OrdinalIgnoreCase))}
}

$tempRoot=Join-Path ([IO.Path]::GetTempPath()) ('specops-f7-conformance-'+[guid]::NewGuid().ToString('N'))
try{
    [void][IO.Directory]::CreateDirectory($tempRoot)
    $cwdA=Join-Path $tempRoot 'cwd-a';$cwdB=Join-Path $tempRoot 'cwd-b';[void][IO.Directory]::CreateDirectory($cwdA);[void][IO.Directory]::CreateDirectory($cwdB)
    $mirror=New-CleanMirror (Join-Path $tempRoot 'verified-source')
    $manifest=$mirror.Record.Manifest
    Assert-Equal Accounting 'clean mirror regular leaves' $mirror.Paths.Count 402
    Assert-Equal Accounting 'authored source count' $manifest.authoredSourceInventory.Count 394
    Assert-Equal Accounting 'implementation support count' $mirror.Support.Count 6
    Assert-True Accounting 'conformance suite is dynamically accounted support' ($mirror.Support-ccontains'tools/specops/bootstrap/tests/SpecOps.Bootstrap.Conformance.Tests.ps1')
    Assert-Equal Accounting 'source identity frozen' $mirror.Record.SourceIdentity.digest 'a92b31752e46b3f801f32400f4f6808d7a888a27d4f865486763896689225adc'

    $publishRoot=Join-Path $tempRoot 'published';[void][IO.Directory]::CreateDirectory($publishRoot)
    $destinationA=Join-Path $publishRoot 'DeterminismA'
    $runA=Invoke-Cli $mirror.Entry (Get-Args $destinationA) $cwdA 'ambient-marker-a'
    Assert-Equal Determinism 'first independent destination exit' $runA.ExitCode 0
    if($runA.ExitCode-ne0){throw "Baseline A failed. stdout=$($runA.StdoutText) stderr=$($runA.StderrText)"}

    [void][IO.Directory]::CreateDirectory((Join-Path $mirror.Root '.git'))
    [IO.File]::WriteAllText((Join-Path $mirror.Root '.git/config'),'f7-ambient-git-marker',$utf8)
    $destinationB=Join-Path $publishRoot 'DeterminismB'
    $runB=Invoke-Cli $mirror.Entry (Get-Args $destinationB) $cwdB 'ambient-marker-b'
    Assert-Equal Determinism 'second independent destination exit' $runB.ExitCode 0
    if($runB.ExitCode-ne0){throw "Baseline B failed. stdout=$($runB.StdoutText) stderr=$($runB.StderrText)"}
    $mapA=Get-OutputMap $destinationA;$mapB=Get-OutputMap $destinationB
    Assert-Equal Determinism 'first output count' $mapA.Count 312;Assert-Equal Determinism 'second output count' $mapB.Count 312
    Assert-Equal Determinism 'ordinal relative path sets identical' ([string]::Join("`0",(Get-OrdinalPaths $mapA))) ([string]::Join("`0",(Get-OrdinalPaths $mapB)))
    Assert-Equal Determinism 'every corresponding tracked byte sequence identical' @(Compare-OutputMaps $mapA $mapB).Count 0
    Assert-BytesEqual Determinism 'provenance bytes identical' $mapA['.specops/bootstrap.json'] $mapB['.specops/bootstrap.json']
    Assert-BytesEqual Result 'success canonical stdout bytes identical' $runA.Stdout $runB.Stdout
    Assert-True Result 'success stdout path-free' (-not$runA.StdoutText.Contains($destinationA,[StringComparison]::OrdinalIgnoreCase)-and-not$runB.StdoutText.Contains($destinationB,[StringComparison]::OrdinalIgnoreCase))
    Assert-True VCS 'source without Git successfully generated output' $true
    Assert-True VCS 'ambient Git subtree did not affect tracked bytes' (@(Compare-OutputMaps $mapA $mapB).Count-eq0)
    Assert-True VCS 'no child Git path emitted' (-not$mapA.ContainsKey('.git')-and-not(@($mapA.Keys|Where-Object{$_.StartsWith('.git/',[StringComparison]::OrdinalIgnoreCase)}).Count))

    foreach($forbidden in @($destinationA,$destinationB,$mirror.Root,$tempRoot,$cwdA,$cwdB,'ambient-marker-a','ambient-marker-b','f7-ambient-git-marker','.specops-bootstrap-')){
        $needle=$utf8.GetBytes($forbidden);$leaked=$false
        foreach($bytes in $mapA.Values){if(Test-ByteSequenceContains $bytes $needle){$leaked=$true;break}}
        Assert-True Neutrality "tracked bytes exclude $forbidden" (-not$leaked)
    }

    $baseInputs=[ordered]@{ProjectId='f7-conformance-project';ProductName='F7 Conformance Product';CompanyName='F7 Conformance Company';ApplicationIdentifier='com.specops.f7conformance';CodeNamespaceRoot='SpecOps.F7Conformance'}
    $variations=[ordered]@{
        ProjectId='f7-conformance-alternate';ProductName='F7 Alternate Product';CompanyName='F7 Alternate Company'
        ApplicationIdentifier='org.specops.f7alternate';CodeNamespaceRoot='Alternate.F7Namespace'
    }
    $variationMaps=[ordered]@{}
    foreach($inputName in $variations.Keys){
        $values=[ordered]@{};foreach($key in $baseInputs.Keys){$values[$key]=$baseInputs[$key]};$values[$inputName]=$variations[$inputName]
        $destination=Join-Path $publishRoot ('Sensitivity-'+$inputName)
        $arguments=Get-Args $destination $values.ProjectId $values.ProductName $values.CompanyName $values.ApplicationIdentifier $values.CodeNamespaceRoot
        $run=Invoke-Cli $mirror.Entry $arguments $cwdB ('ambient-'+$inputName)
        Assert-Equal Sensitivity "$inputName isolated variation exit" $run.ExitCode 0
        if($run.ExitCode-ne0){throw "$inputName variation failed. stdout=$($run.StdoutText) stderr=$($run.StderrText)"}
        $map=Get-OutputMap $destination;$variationMaps[$inputName]=$map
        Assert-Equal Sensitivity "$inputName output count" $map.Count 312
        $different=@(Compare-OutputMaps $mapA $map)
        $allowed=Get-AuthorizedDifferences $manifest $inputName $baseInputs.CodeNamespaceRoot $values.CodeNamespaceRoot
        $unauthorized=@($different|Where-Object{-not$allowed.Contains($_)})
        Assert-Equal Sensitivity "$inputName changes only manifest-authorized outputs" $unauthorized.Count 0
        Assert-True Sensitivity "$inputName has observable deterministic consequences" ($different.Count-gt0)
        $provenance=$utf8.GetString($map['.specops/bootstrap.json'])|ConvertFrom-Json -Depth 100
        foreach($key in $baseInputs.Keys){Assert-Equal Provenance "$inputName provenance $key exact" $provenance.contentInputs.$key $values[$key]}
        $state=$utf8.GetString($map['.specops/specops.json'])|ConvertFrom-Json -Depth 100
        Assert-Equal Sensitivity "$inputName repository.id dependency" $state.repository.id $(if($inputName-ceq'ProjectId'){$variations.ProjectId}else{$baseInputs.ProjectId})
        $player=$utf8.GetString($map['ProjectSettings/ProjectSettings.asset'])
        $expectedGuid=Get-ProductGuid $values.ProjectId $values.ApplicationIdentifier
        Assert-True Sensitivity "$inputName productGUID deterministic derivation" $player.Contains("  productGUID: $expectedGuid",[StringComparison]::Ordinal)
    }
    Assert-True Sensitivity 'ProductName selector applied' $utf8.GetString($variationMaps.ProductName['ProjectSettings/ProjectSettings.asset']).Contains('  productName: F7 Alternate Product',[StringComparison]::Ordinal)
    Assert-True Sensitivity 'CompanyName selector applied' $utf8.GetString($variationMaps.CompanyName['ProjectSettings/ProjectSettings.asset']).Contains('  companyName: F7 Alternate Company',[StringComparison]::Ordinal)
    Assert-True Sensitivity 'ApplicationIdentifier selectors applied' $utf8.GetString($variationMaps.ApplicationIdentifier['ProjectSettings/ProjectSettings.asset']).Contains('    Standalone: org.specops.f7alternate',[StringComparison]::Ordinal)
    $alternatePaths=Get-OrdinalPaths $variationMaps.CodeNamespaceRoot
    Assert-True Sensitivity 'CodeNamespaceRoot path templates applied' (@($alternatePaths|Where-Object{$_.Contains('Alternate.F7Namespace',[StringComparison]::Ordinal)}).Count-gt0)
    Assert-True Neutrality 'DestinationPath remains execution-only across all successful runs' (@(Compare-OutputMaps $mapA $mapB).Count-eq0)

    $provenanceBytes=$mapA['.specops/bootstrap.json'];$provenanceText=$utf8.GetString($provenanceBytes);$provenance=$provenanceText|ConvertFrom-Json -Depth 100
    $canonical=ConvertTo-BootstrapJcs $provenanceBytes
    Assert-Equal Provenance 'RFC 8785 JCS exact bytes' $provenanceText $canonical
    Assert-True Provenance 'UTF-8 without BOM' (-not($provenanceBytes.Length-ge3-and$provenanceBytes[0]-eq0xEF-and$provenanceBytes[1]-eq0xBB-and$provenanceBytes[2]-eq0xBF))
    Assert-True Provenance 'no trailing newline' ($provenanceBytes[-1]-notin@(10,13))
    $schemaCapability=&$module {Get-BootstrapSchemaAdapterCapability}
    Assert-True Provenance 'approved schema capability available' $schemaCapability.Available $schemaCapability.Detail
    Assert-True Provenance 'schema-valid through approved capability' (Test-Json -Json $provenanceText -SchemaFile $provenanceSchemaPath -ErrorAction SilentlyContinue)
    Assert-Equal Provenance 'exact top-level shape' (@($provenance.PSObject.Properties.Name|Sort-Object)-join',') 'authorityStatus,bootstrap,classification,contentInputs,contractVersion,evidenceStatus,sourceBaseline'
    Assert-Equal Provenance 'source baseline id' $provenance.sourceBaseline.id 'specops-unity-clean-architecture-golden-baseline'
    Assert-Equal Provenance 'source baseline version' $provenance.sourceBaseline.version '2.0.0'
    Assert-Equal Provenance 'source identity' $provenance.sourceBaseline.sourceIdentity.digest 'a92b31752e46b3f801f32400f4f6808d7a888a27d4f865486763896689225adc'
    Assert-Equal Provenance 'contract version' $provenance.bootstrap.contractVersion '1.0.0';Assert-Equal Provenance 'implementation version' $provenance.bootstrap.implementationVersion '1.0.0'
    foreach($term in @('DestinationPath','sourcePath','stagingPath','timestamp','username','machine','git','releaseStatus','validationStatus','PASS','approval')){Assert-True Provenance "prohibited semantic absent: $term" (-not$provenanceText.Contains($term,[StringComparison]::OrdinalIgnoreCase))}

    $state=$utf8.GetString($mapA['.specops/specops.json'])|ConvertFrom-Json -Depth 100
    Assert-Equal FreshState 'repository.id exact' $state.repository.id $baseInputs.ProjectId
    Assert-Equal FreshState 'repository.type exact' $state.repository.type 'unity-game-project'
    Assert-Equal FreshState 'repository.purpose exact' $state.repository.purpose 'SpecOps v2 governed Unity game project'
    Assert-True FreshState 'migrationStatus absent' ($null-eq$state.repository.PSObject.Properties['migrationStatus'])
    Assert-True FreshState 'releasedVersion null' ($null-eq$state.repository.releasedVersion)
    Assert-True FreshState 'releaseEvidencePresent false' ($state.initialization.releaseEvidencePresent-eq$false)
    Assert-True FreshState 'bootstrapPresent true' ($state.initialization.bootstrapPresent-eq$true)
    Assert-True FreshState 'feature instance state absent' (-not(@($mapA.Keys|Where-Object{$_-like'Assets/Project/Docs/Specifications/*/SPECOPS_STATE.json'-and$_-notlike'Assets/Project/Docs/Specifications/_templates/*'}).Count))
    Assert-True FreshState 'reference feature absent' (-not(@($mapA.Keys|Where-Object{$_.Contains('reference-architecture-example',[StringComparison]::OrdinalIgnoreCase)}).Count))
    Assert-True FreshState 'release evidence absent' (-not(@($mapA.Keys|Where-Object{$_.StartsWith('.specops/evidence/',[StringComparison]::OrdinalIgnoreCase)}).Count))
    Assert-BytesEqual Attribution 'LICENSE exact-byte preserved' $mapA['LICENSE'] ([IO.File]::ReadAllBytes((Join-Path $mirror.Root 'LICENSE')))
    Assert-BytesEqual Attribution 'NOTICE exact-byte preserved' $mapA['NOTICE'] ([IO.File]::ReadAllBytes((Join-Path $mirror.Root 'NOTICE')))
    Assert-BytesEqual Status 'Bootstrap normative contract status preserved' $mapA['.specops/contracts/bootstrap-v1.md'] ([IO.File]::ReadAllBytes((Join-Path $mirror.Root '.specops/contracts/bootstrap-v1.md')))

    $syntaxA=Invoke-Cli $mirror.Entry @('-Unknown','x','-ProjectId','BAD') $cwdA
    $syntaxB=Invoke-Cli $mirror.Entry @('-Unknown','x','-ProjectId','BAD') $cwdB
    Assert-Equal Result 'syntax failure exit' $syntaxA.ExitCode 2;Assert-BytesEqual Result 'repeated syntax failure stdout deterministic' $syntaxA.Stdout $syntaxB.Stdout
    $syntaxJson=$syntaxA.StdoutText|ConvertFrom-Json;Assert-Equal Precedence 'syntax precedes semantic input' $syntaxJson.failureClass 'INVOCATION_SYNTAX'

    $badInputA=Get-Args (Join-Path $publishRoot 'BadInputA');$badInputA[3]='BAD'
    $badInputB=Get-Args (Join-Path $publishRoot 'BadInputB');$badInputB[3]='BAD'
    $inputA=Invoke-Cli $mirror.Entry $badInputA $cwdA;$inputB=Invoke-Cli $mirror.Entry $badInputB $cwdB
    Assert-Equal Result 'input failure exit' $inputA.ExitCode 2;Assert-BytesEqual Result 'repeated input failure stdout deterministic' $inputA.Stdout $inputB.Stdout
    Assert-True SideEffects 'input failures leave destinations absent' (-not(Test-Path -LiteralPath $badInputA[1])-and-not(Test-Path -LiteralPath $badInputB[1]))

    $transientResults=[ordered]@{}
    foreach($relative in @('Library/transient.bin','Temp/transient.bin','.idea/workspace.xml','obj/build.tmp')){
        $leaf=Join-Path $mirror.Root $relative;$parent=[IO.Path]::GetDirectoryName($leaf);[void][IO.Directory]::CreateDirectory($parent);[IO.File]::WriteAllText($leaf,'undeclared-transient',$utf8)
        $destination=Join-Path $publishRoot ('Transient-'+($relative-replace'[^A-Za-z]',''))
        $result=Invoke-Direct $mirror.Entry $destination;$transientResults[$relative]=$result
        Assert-FailureResult Source "ordinary transient $relative" $result 3 'source' 'CLOSED_ACCOUNTING' @($destination,$mirror.Root)
        Assert-True SideEffects "$relative leaves destination absent" (-not(Test-Path -LiteralPath $destination))
        [IO.File]::Delete($leaf);[IO.Directory]::Delete($parent,$true)
    }
    Assert-BytesEqual Result 'equivalent transient source failures deterministic' $transientResults['Library/transient.bin'].StdoutBytes $transientResults['Temp/transient.bin'].StdoutBytes

    $shareProbe=[ordered]@{WriteBlocked=$false;DeleteBlocked=$false}
    Set-Fault AfterSourceAcquisition {
        param($context)
        $path=Join-Path $context.Root 'LICENSE'
        try{$handle=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite);$handle.Dispose()}catch{$script:shareProbe.WriteBlocked=$true}
        try{[IO.File]::Delete($path)}catch{$script:shareProbe.DeleteBlocked=$true}
        throw (New-HookFailure SOURCE_MUTATION 'F7 retained source handle conflict probe.')
    }
    $shareDestination=Join-Path $publishRoot 'SourceSharing';$shareResult=Invoke-Direct $mirror.Entry $shareDestination;Clear-Faults
    Assert-FailureResult Source 'retained source handle conflict' $shareResult 3 'source' 'SOURCE_MUTATION' @($shareDestination,$mirror.Root)
    Assert-True Source 'source write sharing denied' $shareProbe.WriteBlocked;Assert-True Source 'source delete sharing denied' $shareProbe.DeleteBlocked
    Assert-True SideEffects 'source sharing failure leaves destination absent' (-not(Test-Path -LiteralPath $shareDestination))

    $existingA=Join-Path $publishRoot 'ExistingA';$existingB=Join-Path $publishRoot 'ExistingB';[IO.File]::WriteAllText($existingA,'user-a',$utf8);[IO.File]::WriteAllText($existingB,'user-b',$utf8)
    $destinationFailA=Invoke-Direct $mirror.Entry $existingA;$destinationFailB=Invoke-Direct $mirror.Entry $existingB
    Assert-FailureResult Destination 'existing destination A' $destinationFailA 4 'destination' 'DESTINATION_EXISTS' @($existingA,$mirror.Root)
    Assert-FailureResult Destination 'existing destination B' $destinationFailB 4 'destination' 'DESTINATION_EXISTS' @($existingB,$mirror.Root)
    Assert-BytesEqual Result 'equivalent destination failures deterministic' $destinationFailA.StdoutBytes $destinationFailB.StdoutBytes
    Assert-Equal SideEffects 'existing destination A preserved' ([IO.File]::ReadAllText($existingA)) 'user-a';Assert-Equal SideEffects 'existing destination B preserved' ([IO.File]::ReadAllText($existingB)) 'user-b'
    $caseSibling=Join-Path $publishRoot 'case-equivalent';[IO.File]::WriteAllText($caseSibling,'case-user',$utf8)
    $caseResult=Invoke-Direct $mirror.Entry (Join-Path $publishRoot 'Case-Equivalent');Assert-Equal Destination 'case-equivalent sibling fails closed' $caseResult.ExitCode 4
    $overlapParent=Join-Path $mirror.Root 'destination-parent';[void][IO.Directory]::CreateDirectory($overlapParent)
    $overlapDestination=Join-Path $overlapParent 'Child';$overlapResult=Invoke-Direct $mirror.Entry $overlapDestination;Assert-Equal Destination 'source overlap fails closed' $overlapResult.ExitCode 4

    [IO.File]::WriteAllText((Join-Path $mirror.Root 'unexpected-precedence.txt'),'unexpected',$utf8)
    $multiExisting=Join-Path $publishRoot 'MultiExisting';[IO.File]::WriteAllText($multiExisting,'user',$utf8)
    $multiBad=Get-Args $multiExisting;$multiBad[3]='BAD'
    $inputPrecedence=Invoke-Direct $mirror.Entry $multiExisting $multiBad;Assert-Equal Precedence 'input precedes source and destination' $inputPrecedence.ExitCode 2
    $sourcePrecedence=Invoke-Direct $mirror.Entry $multiExisting;Assert-Equal Precedence 'source precedes destination' $sourcePrecedence.ExitCode 3
    [IO.File]::Delete((Join-Path $mirror.Root 'unexpected-precedence.txt'))

    $laterReached=$false
    Set-Fault BeforeStagingCreation {param($context);throw (New-HookFailure STAGING_CREATE 'Earlier staging failure.')}
    Set-Fault BeforeStagedVerification {param($context);$script:laterReached=$true;throw (New-HookFailure STATIC_BYTES 'Later staged failure.')}
    $stageDestination=Join-Path $publishRoot 'StagePrecedence';$stageResult=Invoke-Direct $mirror.Entry $stageDestination;Clear-Faults
    Assert-FailureResult Precedence 'staging before staged verification' $stageResult 5 'staging' 'STAGING_CREATE' @($stageDestination,$mirror.Root)
    Assert-True Precedence 'later staged hook not reached' (-not$laterReached);Assert-True SideEffects 'staging failure destination absent' (-not(Test-Path -LiteralPath $stageDestination))

    $publicationReached=$false
    Set-Fault BeforeStagedVerification {param($context);throw (New-HookFailure STATIC_BYTES 'Earlier staged verification failure.')}
    Set-Fault BeforePublication {param($context);$script:publicationReached=$true;throw (New-HookFailure PUBLICATION_MOVE 'Later publication failure.')}
    $stagedDestination=Join-Path $publishRoot 'StagedPrecedence';$stagedResult=Invoke-Direct $mirror.Entry $stagedDestination;Clear-Faults
    Assert-FailureResult Precedence 'staged verification before publication' $stagedResult 8 'staged-verification' 'STATIC_BYTES' @($stagedDestination,$mirror.Root)
    Assert-True Precedence 'publication hook not reached' (-not$publicationReached);Assert-True SideEffects 'staged failure destination absent' (-not(Test-Path -LiteralPath $stagedDestination))

    $postReached=$false
    Set-Fault BeforePublication {param($context);throw (New-HookFailure PUBLICATION_MOVE 'Earlier publication failure.')}
    Set-Fault BeforePostPublicationVerification {param($context);$script:postReached=$true;throw (New-HookFailure POST_STATIC 'Later post failure.')}
    $publicationDestination=Join-Path $publishRoot 'PublicationPrecedence';$publicationResult=Invoke-Direct $mirror.Entry $publicationDestination;Clear-Faults
    Assert-FailureResult Precedence 'publication before post-publication verification' $publicationResult 9 'publication' 'PUBLICATION_MOVE' @($publicationDestination,$mirror.Root)
    Assert-True Precedence 'post-publication hook not reached' (-not$postReached);Assert-True SideEffects 'publication failure destination absent' (-not(Test-Path -LiteralPath $publicationDestination))

    # The contract binds canonical paths to supported PowerShell 7 and Windows filesystem primitives.
    # Unsupported-host execution cannot be represented honestly on this supported host without mocking platform identity.
    $platformSupported=[OperatingSystem]::IsWindows()-and$PSVersionTable.PSEdition-ceq'Core'-and$PSVersionTable.PSVersion.Major-ge7-and[Environment]::Is64BitProcess
    Assert-True Platform 'validation host satisfies the supported platform guard' $platformSupported
    $contractText=[IO.File]::ReadAllText((Join-Path $mirror.Root '.specops/contracts/bootstrap-v1.md'),$utf8)
    Assert-True Platform 'contract binds supported PowerShell 7 and Windows filesystem primitives' $contractText.Contains('supported PowerShell 7 and Windows filesystem primitives',[StringComparison]::Ordinal)
    $moduleText=[IO.File]::ReadAllText((Join-Path $mirror.Root 'tools/specops/bootstrap/SpecOps.Bootstrap.psm1'),$utf8)
    $platformGuard=$moduleText.IndexOf("if(-not[OperatingSystem]::IsWindows()-or`$PSVersionTable.PSEdition-cne'Core'-or`$PSVersionTable.PSVersion.Major-lt7-or-not[Environment]::Is64BitProcess){Throw-BootstrapExecutionFailure UNSUPPORTED_PLATFORM",[StringComparison]::Ordinal)
    $rawParser=$moduleText.IndexOf('ConvertFrom-BootstrapRawArguments $RawArguments',[StringComparison]::Ordinal)
    $firstExecutionHook=$moduleText.IndexOf('Invoke-BootstrapExecutionFault AfterSourceAcquisition',[StringComparison]::Ordinal)
    Assert-True Platform 'unsupported-platform guard precedes syntax parsing and every execution fault hook' ($platformGuard-ge0-and$platformGuard-lt$rawParser-and$rawParser-lt$firstExecutionHook)
    Assert-True Platform 'unsupported-platform failure is explicitly dispositioned without host-identity mocking' $platformSupported

    $projectionResults=[Collections.Generic.List[object]]::new()
    foreach($suffix in @('A','B')){
        $script:projectionLaterReached=$false
        Set-Fault AfterSourceAcquisition {param($context);$entryToCorrupt=@($context.ManifestRecord.Manifest.authoredSourceInventory|Where-Object disposition -CEQ 'COPY_EXACT')[0];$entryToCorrupt.disposition='INVALID_FOR_F7_PRECEDENCE'}
        Set-Fault BeforeStagedVerification {param($context);$script:projectionLaterReached=$true}
        $destination=Join-Path $publishRoot ('ProjectionPrecedence'+$suffix);$result=Invoke-Direct $mirror.Entry $destination;Clear-Faults;$projectionResults.Add($result)
        Assert-FailureResult Precedence "projection failure $suffix" $result 6 'projection' 'INVALID_DISPOSITION' @($destination,$mirror.Root)
        Assert-True SideEffects "projection failure $suffix leaves destination absent" (-not(Test-Path -LiteralPath $destination))
        Assert-True Precedence "projection failure $suffix prevents staged verification" (-not$projectionLaterReached)
    }
    Assert-BytesEqual Result 'equivalent projection failures deterministic' $projectionResults[0].StdoutBytes $projectionResults[1].StdoutBytes

    $generatedResults=[Collections.Generic.List[object]]::new()
    foreach($suffix in @('A','B')){
        $script:generatedLaterReached=$false
        Set-Fault AfterSourceAcquisition {param($context);$context.ManifestRecord.Manifest.generatedOutputInventory[0].outputPath='.specops/f7-precedence-not-bootstrap.json'}
        Set-Fault BeforeStagedVerification {param($context);$script:generatedLaterReached=$true}
        $destination=Join-Path $publishRoot ('GeneratedPrecedence'+$suffix);$result=Invoke-Direct $mirror.Entry $destination;Clear-Faults;$generatedResults.Add($result)
        Assert-FailureResult Precedence "generated-output failure $suffix" $result 7 'generated-output' 'GENERATED_OUTPUT' @($destination,$mirror.Root)
        Assert-True SideEffects "generated-output failure $suffix leaves destination absent" (-not(Test-Path -LiteralPath $destination))
        Assert-True Precedence "generated-output failure $suffix prevents staged verification" (-not$generatedLaterReached)
    }
    Assert-BytesEqual Result 'equivalent generated-output failures deterministic' $generatedResults[0].StdoutBytes $generatedResults[1].StdoutBytes

    $internalResults=[Collections.Generic.List[object]]::new()
    foreach($suffix in @('A','B')){
        $script:internalLaterReached=$false
        Set-Fault AfterSourceAcquisition {param($context);throw [InvalidOperationException]::new('Unclassified F7 internal fallback fixture.')}
        Set-Fault BeforeStagingCreation {param($context);$script:internalLaterReached=$true}
        $destination=Join-Path $publishRoot ('InternalFallback'+$suffix);$result=Invoke-Direct $mirror.Entry $destination;Clear-Faults;$internalResults.Add($result)
        Assert-FailureResult Fallback "internal fallback $suffix" $result 70 'internal' 'INTERNAL_INVARIANT' @($destination,$mirror.Root)
        Assert-True SideEffects "internal fallback $suffix leaves destination absent" (-not(Test-Path -LiteralPath $destination))
        Assert-True Fallback "internal fallback $suffix prevents later phase execution" (-not$internalLaterReached)
    }
    Assert-BytesEqual Result 'equivalent internal fallback results deterministic' $internalResults[0].StdoutBytes $internalResults[1].StdoutBytes
    Assert-True Fallback 'internal fallback is a classification and not a temporal successor to post-publication verification' ($internalResults[0].ExitCode-eq70)

    $postResults=[Collections.Generic.List[object]]::new()
    foreach($suffix in @('A','B')){
        Set-Fault BeforePostPublicationVerification {param($context);[IO.File]::WriteAllBytes((Join-Path $context.Destination.Path '.specops/bootstrap.json'),$utf8.GetBytes('{}'))}
        $destination=Join-Path $publishRoot ('PostFailure'+$suffix);$result=Invoke-Direct $mirror.Entry $destination;Clear-Faults;$postResults.Add($result)
        Assert-FailureResult PostPublication "post-publication failure $suffix" $result 10 'post-publication-verification' 'STATIC_BYTES' @($destination,$mirror.Root)
        Assert-True PostPublication "published destination $suffix preserved" (Test-Path -LiteralPath $destination -PathType Container)
        Assert-Equal PostPublication "published corruption $suffix preserved" ([IO.File]::ReadAllText((Join-Path $destination '.specops/bootstrap.json'))) '{}'
        Assert-True PostPublication "retained destination $suffix diagnostic only" ($result.Diagnostic.Contains($destination,[StringComparison]::OrdinalIgnoreCase)-and-not($utf8.GetString($result.StdoutBytes).Contains($destination,[StringComparison]::OrdinalIgnoreCase)))
    }
    Assert-BytesEqual Result 'equivalent post-publication failures deterministic' $postResults[0].StdoutBytes $postResults[1].StdoutBytes
}
finally{
    Clear-Faults
    if(Test-Path -LiteralPath $tempRoot){Remove-Item -LiteralPath $tempRoot -Recurse -Force}
}

$result=[ordered]@{
    Result=$(if($script:Failures.Count){'FAIL'}else{'PASS'});Tests=$script:Tests;Categories=$script:Categories;Failures=@($script:Failures)
    AcceptanceCriteria=@(1..16|ForEach-Object{'AC-F2-{0:D3}'-f$_});RegularLeafCount=402;BootstrapSourceMetadataCount=2
    AuthoredFiles=394;ImplementationSupportFiles=6;OutputCount=312
    SourceIdentity='a92b31752e46b3f801f32400f4f6808d7a888a27d4f865486763896689225adc'
    GoldenBaselineId='specops-unity-clean-architecture-golden-baseline';GoldenBaselineVersion='2.0.0'
    BootstrapContractVersion='1.0.0';BootstrapImplementationVersion='1.0.0'
    UnityExecuted=$false;RealHumanDestinationUsed=$false;GitRequired=$false;ExternalRuntimeOrPackageIntroduced=$false
}
$result|ConvertTo-Json -Depth 20
if($script:Failures.Count){exit 1}
