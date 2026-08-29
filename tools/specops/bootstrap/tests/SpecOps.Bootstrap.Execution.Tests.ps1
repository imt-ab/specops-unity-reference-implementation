[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:Tests=0
$script:Failures=[Collections.Generic.List[string]]::new()
$script:Categories=[ordered]@{}
$utf8=[Text.UTF8Encoding]::new($false,$true)
$repositoryRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
$module=Import-Module -Force -PassThru (Join-Path $repositoryRoot 'tools/specops/bootstrap/SpecOps.Bootstrap.psm1')
$entry=Join-Path $repositoryRoot 'tools/specops/bootstrap/Invoke-SpecOpsBootstrap.ps1'
if(-not('SpecOpsBootstrapExecutionTestNative.NativeMethods'-as[type])){Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace SpecOpsBootstrapExecutionTestNative {
    public static class NativeMethods {
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool MoveFileExW(string existingPath, string newPath, uint flags);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool RemoveDirectoryW(string path);
    }
}
'@}

function Add-Result { param([string]$Category,[string]$Name,[bool]$Pass,[string]$Detail='');$script:Tests++;if(-not$script:Categories.Contains($Category)){$script:Categories[$Category]=0};$script:Categories[$Category]++;if(-not$Pass){$script:Failures.Add("[$Category] $Name$(if($Detail){': '+$Detail})")} }
function Assert-True { param([string]$Category,[string]$Name,[bool]$Condition,[string]$Detail='');Add-Result $Category $Name $Condition $Detail }
function Assert-Equal { param([string]$Category,[string]$Name,$Actual,$Expected);Add-Result $Category $Name ($Actual-ceq$Expected) "expected=$Expected actual=$Actual" }
function New-HookFailure { param([string]$Class,[string]$Message);$exception=[IO.InvalidDataException]::new($Message);$exception.Data['BootstrapExecutionFailureClass']=$Class;return $exception }
function Set-Fault { param([string]$Name,[scriptblock]$Action);&$module {param($n,$a)$script:ExecutionFaults[$n]=$a} $Name $Action }
function Clear-Faults { &$module {$script:ExecutionFaults.Clear()} }
function Get-DirectoryIdentity {
    param([Parameter(Mandatory)][string]$Path)
    return &$module {param($p)$opened=Open-BootstrapDirectoryHandle $p -AllowDeleteShare;try{return $opened.Identity}finally{$opened.Handle.Dispose()}} $Path
}
function Get-Args {
    param([string]$Destination,[switch]$Reverse,[string]$ProductName='F6 Test Product',[string]$CompanyName='F6 Test Company')
    $pairs=@(
        @('-DestinationPath',$Destination),@('-ProjectId','f6-test-project'),@('-ProductName',$ProductName),
        @('-CompanyName',$CompanyName),@('-ApplicationIdentifier','com.specops.f6test'),@('-CodeNamespaceRoot','SpecOps.F6Test'))
    if($Reverse){[Array]::Reverse($pairs)}
    return [string[]]@($pairs|ForEach-Object{$_[0];$_[1]})
}
function Invoke-Direct { param([string]$MirrorEntry,[string]$Destination);return Invoke-SpecOpsBootstrapExecution -RawArguments (Get-Args $Destination) -ImplementationScriptPath $MirrorEntry }
function Invoke-Cli {
    param([string]$ScriptPath,[string[]]$Arguments)
    $start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=(Get-Command pwsh).Source;$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    foreach($argument in @('-NoLogo','-NoProfile','-NonInteractive','-File',$ScriptPath)+$Arguments){[void]$start.ArgumentList.Add($argument)}
    $process=[Diagnostics.Process]::new();$process.StartInfo=$start;[void]$process.Start();$stdout=[IO.MemoryStream]::new();$stderr=[IO.MemoryStream]::new();$outTask=$process.StandardOutput.BaseStream.CopyToAsync($stdout);$errTask=$process.StandardError.BaseStream.CopyToAsync($stderr);$process.WaitForExit();[void]$outTask.GetAwaiter().GetResult();[void]$errTask.GetAwaiter().GetResult()
    return [pscustomobject]@{ExitCode=$process.ExitCode;Stdout=$stdout.ToArray();Stderr=$stderr.ToArray();StdoutText=$utf8.GetString($stdout.ToArray());StderrText=$utf8.GetString($stderr.ToArray())}
}
function New-CleanMirror {
    param([string]$Root)
    [void][IO.Directory]::CreateDirectory($Root)
    $record=Read-BootstrapProjectionManifest (Join-Path $repositoryRoot '.specops/bootstrap/bootstrap-v1.projection-manifest.json') (Join-Path $repositoryRoot '.specops/contracts/bootstrap-projection-manifest.schema.json')
    $support=@(Get-ChildItem -LiteralPath (Join-Path $repositoryRoot 'tools/specops/bootstrap') -File -Recurse -Force|ForEach-Object{[IO.Path]::GetRelativePath($repositoryRoot,$_.FullName).Replace('\','/')})
    $paths=@(@($record.Manifest.bootstrapSourceMetadata.path)+@($record.Manifest.authoredSourceInventory.sourcePath)+$support|Sort-Object -Unique)
    foreach($path in $paths){$target=Join-Path $Root $path;$parent=[IO.Path]::GetDirectoryName($target);[void][IO.Directory]::CreateDirectory($parent);[IO.File]::WriteAllBytes($target,[IO.File]::ReadAllBytes((Join-Path $repositoryRoot $path)))}
    return [pscustomobject]@{Root=$Root;Entry=(Join-Path $Root 'tools/specops/bootstrap/Invoke-SpecOpsBootstrap.ps1');Paths=$paths;Support=$support}
}
function Get-OutputLeaves { param([string]$Root);return @(Get-ChildItem -LiteralPath $Root -File -Recurse -Force|ForEach-Object{[IO.Path]::GetRelativePath($Root,$_.FullName).Replace('\','/')}|Sort-Object) }

$tempRoot=Join-Path ([IO.Path]::GetTempPath()) ('specops-f6-execution-'+[guid]::NewGuid().ToString('N'))
try {
    [void][IO.Directory]::CreateDirectory($tempRoot)

    # Syntax is checked before any source or destination work and uses the real raw CLI.
    $syntaxCases=@(
        @{Name='unknown argument';Args=@('-Unknown','x');Class='INVOCATION_SYNTAX'},
        @{Name='abbreviated argument';Args=@('-Dest','x');Class='INVOCATION_SYNTAX'},
        @{Name='alias-like argument';Args=@('-d','x');Class='INVOCATION_SYNTAX'},
        @{Name='duplicate argument';Args=@('-ProjectId','a','-ProjectId','b');Class='INVOCATION_SYNTAX'},
        @{Name='missing value';Args=@('-ProjectId');Class='INVOCATION_SYNTAX'},
        @{Name='missing required input';Args=@('-ProjectId','a');Class='MISSING_INPUTS'}
    )
    foreach($case in $syntaxCases){$result=Invoke-Cli $entry ([string[]]$case.Args);Assert-Equal CLI "$($case.Name) exit" $result.ExitCode 2;$json=$result.StdoutText|ConvertFrom-Json;Assert-Equal CLI "$($case.Name) class" $json.failureClass $case.Class;Assert-True CLI "$($case.Name) single LF framing" ($result.Stdout.Length-gt1-and$result.Stdout[-1]-eq10-and$result.Stdout[-2]-ne10);Assert-True CLI "$($case.Name) stderr separated" (-not[string]::IsNullOrWhiteSpace($result.StderrText));Assert-True CLI "$($case.Name) stdout path-free" (-not$result.StdoutText.Contains($repositoryRoot,[StringComparison]::OrdinalIgnoreCase))}
    $precedence=Invoke-Cli $entry @('-Unknown','x','-ProjectId','BAD')
    Assert-Equal CLI 'syntax precedes semantic input validation' (($precedence.StdoutText|ConvertFrom-Json).failureClass) 'INVOCATION_SYNTAX'

    $mirror=New-CleanMirror (Join-Path $tempRoot 'clean-source')
    Assert-Equal Source 'clean mirror governed leaves' $mirror.Paths.Count 402
    Assert-Equal Source 'implementation support files' $mirror.Support.Count 6
    Assert-True Source 'entry classified as implementation support' ($mirror.Support-ccontains'tools/specops/bootstrap/Invoke-SpecOpsBootstrap.ps1')
    Assert-True Source 'execution tests classified as implementation support' ($mirror.Support-ccontains'tools/specops/bootstrap/tests/SpecOps.Bootstrap.Execution.Tests.ps1')
    Assert-True Source 'conformance tests classified as implementation support' ($mirror.Support-ccontains'tools/specops/bootstrap/tests/SpecOps.Bootstrap.Conformance.Tests.ps1')
    [void][IO.Directory]::CreateDirectory((Join-Path $mirror.Root '.git'));[IO.File]::WriteAllText((Join-Path $mirror.Root '.git/config'),'ambient git data',$utf8)

    # Successful production CLI path, including order/case variation and exact framing.
    $parent=Join-Path $tempRoot 'published';[void][IO.Directory]::CreateDirectory($parent)
    $destination=Join-Path $parent 'ChildA';$success=Invoke-Cli $mirror.Entry (Get-Args $destination)
    Assert-Equal CLI 'valid raw six-input invocation exit' $success.ExitCode 0
    if($success.ExitCode-ne0){throw "Valid CLI fixture failed. stdout=$($success.StdoutText) stderr=$($success.StderrText)"}
    $successJson=$success.StdoutText|ConvertFrom-Json
    Assert-Equal CLI 'success exact top-level result shape' (@($successJson.PSObject.Properties.Name|Sort-Object)-join',') 'bootstrapContractVersion,bootstrapImplementationVersion,exitCode,goldenBaseline,sourceIdentity,status'
    Assert-Equal CLI 'success status' $successJson.status 'SUCCESS'
    Assert-Equal CLI 'success result exitCode' $successJson.exitCode 0
    Assert-Equal CLI 'success Bootstrap Contract Version' $successJson.bootstrapContractVersion '1.0.0'
    Assert-Equal CLI 'success Golden Baseline id' $successJson.goldenBaseline.id 'specops-unity-clean-architecture-golden-baseline'
    Assert-Equal CLI 'success Golden Baseline version' $successJson.goldenBaseline.version '2.0.0'
    Assert-Equal CLI 'success Source Identity profile' $successJson.sourceIdentity.profile 'specops-bootstrap-source-jcs-sha256-v1'
    Assert-Equal CLI 'success Source Identity' $successJson.sourceIdentity.digest '93fd1d378c47b24265eafe35130ddb1879aa4c3470ac77aba41ffda4313603ed'
    Assert-Equal CLI 'success implementation version' $successJson.bootstrapImplementationVersion '1.0.0'
    Assert-True CLI 'success stderr empty' ([string]::IsNullOrEmpty($success.StderrText))
    Assert-True CLI 'success exact one LF' ($success.Stdout[-1]-eq10-and$success.Stdout[-2]-ne10)
    Assert-True CLI 'success stdout destination path absent' (-not$success.StdoutText.Contains($destination,[StringComparison]::OrdinalIgnoreCase))
    Assert-Equal Publication 'published exact relative file count' (Get-OutputLeaves $destination).Count 312
    Assert-True Publication 'no Git output' (-not(Test-Path -LiteralPath (Join-Path $destination '.git')))
    Assert-True Publication 'bootstrap provenance published' (Test-Path -LiteralPath (Join-Path $destination '.specops/bootstrap.json'))
    $state=Get-Content -Raw -LiteralPath (Join-Path $destination '.specops/specops.json')|ConvertFrom-Json
    Assert-True Publication 'published bootstrapPresent true' ($state.initialization.bootstrapPresent-eq$true)
    Assert-True Publication 'published releasedVersion null' ($null-eq$state.repository.releasedVersion)
    Assert-True Publication 'published releaseEvidencePresent false' ($state.initialization.releaseEvidencePresent-eq$false)

    $destinationB=Join-Path $parent 'ChildB';$ordered=Get-Args $destinationB -Reverse;$ordered[0]=$ordered[0].ToLowerInvariant();$successB=Invoke-Cli $mirror.Entry $ordered
    Assert-Equal CLI 'argument order and name case variation' $successB.ExitCode 0
    Assert-Equal Publication 'second publication output count' (Get-OutputLeaves $destinationB).Count 312

    $hyphenDestination=Join-Path $parent 'HyphenValues';$hyphenSuccess=Invoke-Cli $mirror.Entry (Get-Args $hyphenDestination -ProductName '-Hyphen Product' -CompanyName '-Hyphen Company')
    Assert-Equal CLI 'hyphen-leading ProductName and CompanyName complete successfully' $hyphenSuccess.ExitCode 0
    if($hyphenSuccess.ExitCode-ne0){throw "Hyphen-leading CLI fixture failed. stdout=$($hyphenSuccess.StdoutText) stderr=$($hyphenSuccess.StderrText)"}
    $hyphenProvenance=Get-Content -Raw -LiteralPath (Join-Path $hyphenDestination '.specops/bootstrap.json')|ConvertFrom-Json
    Assert-Equal CLI 'hyphen-leading ProductName preserved exactly' $hyphenProvenance.contentInputs.ProductName '-Hyphen Product'
    Assert-Equal CLI 'hyphen-leading CompanyName preserved exactly' $hyphenProvenance.contentInputs.CompanyName '-Hyphen Company'

    $parameterTokenDestination=Join-Path $parent 'ParameterTokenValues';$parameterTokenSuccess=Invoke-Cli $mirror.Entry (Get-Args $parameterTokenDestination -ProductName '-ProjectId' -CompanyName '-DestinationPath')
    Assert-Equal CLI 'canonical parameter tokens in value position complete successfully' $parameterTokenSuccess.ExitCode 0
    if($parameterTokenSuccess.ExitCode-ne0){throw "Canonical-parameter-token value fixture failed. stdout=$($parameterTokenSuccess.StdoutText) stderr=$($parameterTokenSuccess.StderrText)"}
    $parameterTokenProvenance=Get-Content -Raw -LiteralPath (Join-Path $parameterTokenDestination '.specops/bootstrap.json')|ConvertFrom-Json
    Assert-Equal CLI 'ProductName canonical parameter token preserved exactly' $parameterTokenProvenance.contentInputs.ProductName '-ProjectId'
    Assert-Equal CLI 'CompanyName canonical parameter token preserved exactly' $parameterTokenProvenance.contentInputs.CompanyName '-DestinationPath'

    # Source contract failures use the production enumerator.
    $unexpected=Join-Path $mirror.Root 'unexpected-source-leaf.txt';[IO.File]::WriteAllText($unexpected,'unexpected',$utf8)
    $sourceFailDestination=Join-Path $parent 'SourceFail';$sourceFail=Invoke-Direct $mirror.Entry $sourceFailDestination
    Assert-Equal Source 'unexpected source leaf exit' $sourceFail.ExitCode 3
    Assert-Equal Source 'unexpected source leaf class' (($utf8.GetString($sourceFail.StdoutBytes)|ConvertFrom-Json).failureClass) 'CLOSED_ACCOUNTING'
    Assert-True Source 'source failure leaves destination absent' (-not(Test-Path -LiteralPath $sourceFailDestination))
    [IO.File]::Delete($unexpected)
    $zeroLeafDirectory=Join-Path $mirror.Root 'Library';[void][IO.Directory]::CreateDirectory($zeroLeafDirectory)
    $zeroLeaf=Join-Path $zeroLeafDirectory 'zero-length-source-leaf.bin';[IO.File]::WriteAllBytes($zeroLeaf,[byte[]]::new(0))
    $zeroLeafDestinationA=Join-Path $parent 'ZeroLengthSourceFailA';$zeroLeafFailA=Invoke-Direct $mirror.Entry $zeroLeafDestinationA;$zeroLeafJsonA=$utf8.GetString($zeroLeafFailA.StdoutBytes)|ConvertFrom-Json
    $zeroLeafDestinationB=Join-Path $parent 'ZeroLengthSourceFailB';$zeroLeafFailB=Invoke-Direct $mirror.Entry $zeroLeafDestinationB;$zeroLeafJsonB=$utf8.GetString($zeroLeafFailB.StdoutBytes)|ConvertFrom-Json
    Assert-True Source 'zero-length source leaf is not an internal invariant' ($zeroLeafJsonA.failureClass-cne'INTERNAL_INVARIANT')
    Assert-Equal Source 'zero-length source leaf exit' $zeroLeafFailA.ExitCode 3
    Assert-Equal Source 'zero-length source leaf phase' $zeroLeafJsonA.phase 'source'
    Assert-Equal Source 'zero-length source leaf class' $zeroLeafJsonA.failureClass 'CLOSED_ACCOUNTING'
    Assert-True Source 'zero-length source failure leaves destinations absent' (-not(Test-Path -LiteralPath $zeroLeafDestinationA)-and-not(Test-Path -LiteralPath $zeroLeafDestinationB))
    Assert-Equal Source 'zero-length source failure leaves no owned staging residue' @(Get-ChildItem -LiteralPath $parent -Directory -Force -Filter '.specops-staging-*').Count 0
    Assert-Equal Source 'zero-length source failure result is deterministic' ([Convert]::ToBase64String($zeroLeafFailA.StdoutBytes)) ([Convert]::ToBase64String($zeroLeafFailB.StdoutBytes))
    Assert-Equal Source 'repeated zero-length source leaf exit' $zeroLeafFailB.ExitCode 3
    Assert-Equal Source 'repeated zero-length source leaf phase' $zeroLeafJsonB.phase 'source'
    Assert-Equal Source 'repeated zero-length source leaf class' $zeroLeafJsonB.failureClass 'CLOSED_ACCOUNTING'
    [IO.File]::Delete($zeroLeaf);[IO.Directory]::Delete($zeroLeafDirectory,$false)
    Set-Fault AfterSourceAcquisition {param($context);throw (New-HookFailure SOURCE_MUTATION 'Injected retained-handle sharing conflict.')}
    $sourceMutationDestination=Join-Path $parent 'SourceMutation';$sourceMutation=Invoke-Direct $mirror.Entry $sourceMutationDestination;Clear-Faults
    Assert-Equal Source 'source mutation exit' $sourceMutation.ExitCode 3
    Assert-Equal Source 'source mutation class' (($utf8.GetString($sourceMutation.StdoutBytes)|ConvertFrom-Json).failureClass) 'SOURCE_MUTATION'
    Assert-True Source 'source mutation leaves destination absent' (-not(Test-Path -LiteralPath $sourceMutationDestination))

    # Destination physical safety.
    $existingFile=Join-Path $parent 'ExistingFile';[IO.File]::WriteAllText($existingFile,'user',$utf8);$r=Invoke-Direct $mirror.Entry $existingFile;Assert-Equal Destination 'existing file rejected' $r.ExitCode 4;Assert-Equal Destination 'existing file preserved' ([IO.File]::ReadAllText($existingFile)) 'user'
    $existingDirectory=Join-Path $parent 'ExistingDirectory';[void][IO.Directory]::CreateDirectory($existingDirectory);$r=Invoke-Direct $mirror.Entry $existingDirectory;Assert-Equal Destination 'existing directory rejected' $r.ExitCode 4;Assert-True Destination 'existing directory preserved' (Test-Path -LiteralPath $existingDirectory -PathType Container)
    $caseSibling=Join-Path $parent 'casechild';[IO.File]::WriteAllText($caseSibling,'case',$utf8);$r=Invoke-Direct $mirror.Entry (Join-Path $parent 'CaseChild');Assert-Equal Destination 'case-equivalent sibling rejected' $r.ExitCode 4
    $insideSourceParent=Join-Path $mirror.Root 'empty-destination-parent';[void][IO.Directory]::CreateDirectory($insideSourceParent);$insideDestination=Join-Path $insideSourceParent 'Child';$r=Invoke-Direct $mirror.Entry $insideDestination;Assert-Equal Destination 'source destination containment rejected' $r.ExitCode 4
    $linkTarget=Join-Path $tempRoot 'link-target';[void][IO.Directory]::CreateDirectory($linkTarget);$linkParent=Join-Path $tempRoot 'link-parent';$linkSupported=$true;try{[void][IO.Directory]::CreateSymbolicLink($linkParent,$linkTarget)}catch{$linkSupported=$false};if($linkSupported){$r=Invoke-Direct $mirror.Entry (Join-Path $linkParent 'Child');Assert-Equal Destination 'parent reparse rejected' $r.ExitCode 4}else{Assert-True Destination 'parent reparse case unsupported by host policy' $true}
    $limitRejected=$false;try{&$module {Assert-BootstrapVolumeComponentRepresentable 'four' 3}}catch{$limitRejected=$_.Exception.Data['BootstrapExecutionFailureClass']-ceq'DESTINATION_REPRESENTATION'};Assert-True Destination 'verified volume component decision fails closed' $limitRejected

    # Staging creation and bounded cleanup.
    Set-Fault BeforeStagingCreation {param($context);throw (New-HookFailure STAGING_CREATE 'Injected staging creation failure.')}
    $stagingFailDestination=Join-Path $parent 'StagingFail';$r=Invoke-Direct $mirror.Entry $stagingFailDestination;Clear-Faults
    Assert-Equal Staging 'staging create failure exit' $r.ExitCode 5
    Assert-True Staging 'staging create failure destination absent' (-not(Test-Path -LiteralPath $stagingFailDestination))

    $uncertainStaging=$null
    Set-Fault AfterAtomicStagingCreation {param($context);$script:uncertainStaging=$context.Path;[IO.Directory]::Delete($context.Path,$false);[void][IO.Directory]::CreateDirectory($context.Path);[IO.File]::WriteAllText((Join-Path $context.Path 'replacement.txt'),'unowned replacement',$utf8);throw (New-HookFailure STAGING_OWNERSHIP 'Injected pre-ownership substitution.')}
    $preOwnershipDestination=Join-Path $parent 'PreOwnershipLoss';$r=Invoke-Direct $mirror.Entry $preOwnershipDestination;Clear-Faults
    Assert-Equal Staging 'pre-ownership substitution fails staging phase' $r.ExitCode 5
    Assert-True Staging 'unproven replacement is not deleted' (Test-Path -LiteralPath (Join-Path $uncertainStaging 'replacement.txt') -PathType Leaf)
    Assert-True Staging 'pre-ownership destination remains absent' (-not(Test-Path -LiteralPath $preOwnershipDestination))
    Assert-True Staging 'uncertain residual path excluded from stdout' (-not$utf8.GetString($r.StdoutBytes).Contains($uncertainStaging,[StringComparison]::OrdinalIgnoreCase))
    Assert-True Staging 'uncertain residual reported diagnostically' $r.Diagnostic.Contains('Uncertain staging path retained without cleanup:',[StringComparison]::Ordinal)

    $shareProbe=[ordered]@{Path=$null;RenameError=$null;DeleteError=$null;RenameBlocked=$false;DeleteBlocked=$false}
    Set-Fault AfterStagingCreated {
        param($context)
        $script:shareProbe.Path=$context.Path
        if(-not[SpecOpsBootstrapExecutionTestNative.NativeMethods]::MoveFileExW($context.Path,$context.Path+'-rename-attempt',0)){$script:shareProbe.RenameError=[Runtime.InteropServices.Marshal]::GetLastWin32Error();$script:shareProbe.RenameBlocked=$script:shareProbe.RenameError-eq32}
        if(-not[SpecOpsBootstrapExecutionTestNative.NativeMethods]::RemoveDirectoryW($context.Path)){$script:shareProbe.DeleteError=[Runtime.InteropServices.Marshal]::GetLastWin32Error();$script:shareProbe.DeleteBlocked=$script:shareProbe.DeleteError-eq32}
        throw (New-HookFailure STAGING_CREATE 'Injected failure after authoritative-handle sharing probes.')
    }
    $shareDestination=Join-Path $parent 'AuthoritativeHandleSharing';$r=Invoke-Direct $mirror.Entry $shareDestination;Clear-Faults
    Assert-Equal Staging 'authoritative-handle sharing probe preserves staging exit' $r.ExitCode 5
    Assert-True Staging 'authoritative staging handle blocks independent rename with sharing violation' $shareProbe.RenameBlocked "Win32=$($shareProbe.RenameError)"
    Assert-True Staging 'authoritative staging handle blocks independent delete with sharing violation' $shareProbe.DeleteBlocked "Win32=$($shareProbe.DeleteError)"
    Assert-True Staging 'authoritative staging object retained after blocked namespace mutation' (Test-Path -LiteralPath $shareProbe.Path -PathType Container)
    Assert-True Staging 'authoritative-handle sharing probe destination absent' (-not(Test-Path -LiteralPath $shareDestination))
    Assert-True Staging 'authoritative-handle retained path is diagnostic only' (-not$utf8.GetString($r.StdoutBytes).Contains($shareProbe.Path,[StringComparison]::OrdinalIgnoreCase)-and$r.Diagnostic.Contains($shareProbe.Path,[StringComparison]::OrdinalIgnoreCase))

    $ownedIdentity=$null;$stageComplete=$false;$stageBootstrap=$false;$sequence=[Collections.Generic.List[string]]::new();$physicalSourceSeen=$false;$physicalParentSeen=$false;$volumeLimit=0
    Set-Fault AfterSourceAcquisition {param($context);$script:physicalSourceSeen=(-not[string]::IsNullOrEmpty($context.PhysicalRootPath)-and$null-ne$context.RootIdentity)}
    Set-Fault BeforeStagingCreation {param($context);$script:physicalParentSeen=(-not[string]::IsNullOrEmpty($context.PhysicalParentPath)-and$null-ne$context.ParentIdentity);$script:volumeLimit=$context.MaximumComponentLength}
    Set-Fault BeforeStagedVerification {param($context);$script:sequence.Add('staged-verification');$script:stageComplete=((Get-ChildItem -LiteralPath $context.Path -File -Recurse -Force).Count-eq312);$script:stageBootstrap=Test-Path -LiteralPath (Join-Path $context.Path '.specops/bootstrap.json')}
    Set-Fault BeforePublication {param($context);$script:sequence.Add('publication');$script:ownedIdentity=$context.Staging.Identity.Key}
    Set-Fault AfterPublication {param($context);$script:sequence.Add('post-publication');if($context.Published.Identity.Key-cne$script:ownedIdentity){throw (New-HookFailure PUBLICATION_IDENTITY 'Identity transfer mismatch.')}}
    $instrumentedDestination=Join-Path $parent 'Instrumented';$r=Invoke-Direct $mirror.Entry $instrumentedDestination;Clear-Faults
    Assert-Equal Staging 'instrumented publication succeeds' $r.ExitCode 0
    Assert-True Staging 'complete staging before verification' $stageComplete
    Assert-True Staging 'final bootstrap provenance present in staging' $stageBootstrap
    Assert-True Destination 'physical SourceRoot handle identity observed' $physicalSourceSeen
    Assert-True Destination 'physical destination-parent identity observed' $physicalParentSeen
    Assert-True Destination 'actual volume component limit observed' ($volumeLimit-gt0)
    Assert-Equal Publication 'staged verification precedes publication' $sequence[0] 'staged-verification'
    Assert-Equal Publication 'publication precedes post verification' $sequence[1] 'publication'
    Assert-Equal Publication 'identity transfer confirmed before post verification' $sequence[2] 'post-publication'

    $publicationOriginal=$null;$publicationReplacement=$null
    Set-Fault BeforeOwnedHandlePublication {param($context);$script:publicationOriginal=$context.Staging.Path+'-owned';$script:publicationReplacement=$context.Staging.Path;[int]$renameError=0;if(-not[SpecOpsBootstrapNative.NativeMethods]::RenameAbsoluteNoReplace($context.Staging.Handle,$script:publicationOriginal,[ref]$renameError)){throw (New-HookFailure FIXTURE_SETUP "By-handle publication-substitution rename failed with Win32 error $renameError.")};[void][IO.Directory]::CreateDirectory($script:publicationReplacement);[IO.File]::WriteAllText((Join-Path $script:publicationReplacement 'replacement.txt'),'unowned replacement',$utf8)}
    $publicationLossDestination=Join-Path $parent 'PublicationOwnershipLoss';$r=Invoke-Direct $mirror.Entry $publicationLossDestination;Clear-Faults
    Assert-Equal Publication 'publication ownership loss exits publication phase' $r.ExitCode 9
    Assert-True Publication 'publication ownership loss leaves destination absent' (-not(Test-Path -LiteralPath $publicationLossDestination))
    Assert-True Publication 'publication does not move unowned replacement' (Test-Path -LiteralPath (Join-Path $publicationReplacement 'replacement.txt') -PathType Leaf)
    Assert-True Publication 'owned original retained after live-path substitution' (Test-Path -LiteralPath $publicationOriginal -PathType Container)

    Set-Fault BeforePublication {param($context);[void][IO.Directory]::CreateDirectory($context.Destination.Path)}
    $raceDestination=Join-Path $parent 'RaceDestination';$r=Invoke-Direct $mirror.Entry $raceDestination;Clear-Faults
    Assert-Equal Publication 'destination race exit' $r.ExitCode 9
    Assert-True Publication 'racer destination preserved' (Test-Path -LiteralPath $raceDestination -PathType Container)
    Assert-Equal Publication 'racer destination remains empty' @(Get-ChildItem -LiteralPath $raceDestination -Force).Count 0

    # Even with positive root ownership, recursive cleanup is retained because descendant object ownership is not recorded.
    $ownedCleanup=[ordered]@{Path=$null;Identity=$null;LiveHandle=$false}
    Set-Fault BeforeStagedVerification {param($context);throw (New-HookFailure STATIC_BYTES 'Injected owned-staging cleanup boundary failure.')}
    Set-Fault BeforeCleanup {param($context);$script:ownedCleanup.Path=$context.Path;$script:ownedCleanup.Identity=$context.Identity;$script:ownedCleanup.LiveHandle=(-not$context.Handle.IsClosed)}
    $ownedCleanupDestination=Join-Path $parent 'OwnedCleanupRetention';$r=Invoke-Direct $mirror.Entry $ownedCleanupDestination;Clear-Faults
    $ownedCleanupFinalIdentity=Get-DirectoryIdentity $ownedCleanup.Path
    Assert-Equal Cleanup 'owned cleanup retention preserves primary staged verification exit' $r.ExitCode 8
    Assert-True Cleanup 'owned cleanup reaches boundary with live authoritative handle' $ownedCleanup.LiveHandle
    Assert-True Cleanup 'owned cleanup requested destination absent' (-not(Test-Path -LiteralPath $ownedCleanupDestination))
    Assert-Equal Cleanup 'owned cleanup retained object identity' $ownedCleanupFinalIdentity.Key $ownedCleanup.Identity.Key
    Assert-True Cleanup 'owned cleanup retained path excluded from stdout' (-not$utf8.GetString($r.StdoutBytes).Contains($ownedCleanup.Path,[StringComparison]::OrdinalIgnoreCase))
    Assert-True Cleanup 'owned cleanup retention reported diagnostically' ($r.Diagnostic.Contains('CLEANUP_RETAINED:',[StringComparison]::Ordinal)-and$r.Diagnostic.Contains($ownedCleanup.Path,[StringComparison]::OrdinalIgnoreCase))

    # Cleanup authority loss refuses deletion and reports retained staging only on stderr/diagnostic.
    $cleanupFixture=[ordered]@{SetupSucceeded=$false;OriginalPath=$null;RetainedPath=$null;OwnedIdentity=$null;RetainedIdentity=$null;ReplacementIdentity=$null;RenameAttempts=0;RenameErrors=[Collections.Generic.List[int]]::new()}
    Set-Fault BeforeStagedVerification {param($context);throw (New-HookFailure STATIC_BYTES 'Injected pre-publication failure.')}
    Set-Fault BeforeCleanup {
        param($context)
        $script:cleanupFixture.OriginalPath=$context.Path
        $script:cleanupFixture.RetainedPath=$context.Path+'-owned'
        $script:cleanupFixture.OwnedIdentity=$context.Identity
        $renamed=$false
        foreach($attempt in 1..8){
            $script:cleanupFixture.RenameAttempts=$attempt
            [int]$renameError=0
            if([SpecOpsBootstrapNative.NativeMethods]::RenameAbsoluteNoReplace($context.Handle,$script:cleanupFixture.RetainedPath,[ref]$renameError)){$renamed=$true;break}
            $script:cleanupFixture.RenameErrors.Add($renameError)
            if(Test-Path -LiteralPath $script:cleanupFixture.RetainedPath -PathType Container){
                $resolved=Get-DirectoryIdentity $script:cleanupFixture.RetainedPath
                if($resolved.Key-ceq$script:cleanupFixture.OwnedIdentity.Key){$renamed=$true;break}
                throw (New-HookFailure FIXTURE_SETUP 'Failed rename left the retained path bound to an unexpected identity.')
            }
            $original=Get-DirectoryIdentity $script:cleanupFixture.OriginalPath
            if($original.Key-cne$script:cleanupFixture.OwnedIdentity.Key){throw (New-HookFailure FIXTURE_SETUP 'Failed rename no longer leaves the original path bound to the owned identity.')}
        }
        if(-not$renamed){throw (New-HookFailure FIXTURE_SETUP "By-handle adversarial rename did not complete after $($script:cleanupFixture.RenameAttempts) identity-proven attempts; Win32 errors: $($script:cleanupFixture.RenameErrors -join ',').")}
        $script:cleanupFixture.RetainedIdentity=Get-DirectoryIdentity $script:cleanupFixture.RetainedPath
        if($script:cleanupFixture.RetainedIdentity.Key-cne$script:cleanupFixture.OwnedIdentity.Key){throw (New-HookFailure FIXTURE_SETUP 'Retained path does not denote the invocation-owned staging identity.')}
        [void][IO.Directory]::CreateDirectory($script:cleanupFixture.OriginalPath)
        $script:cleanupFixture.ReplacementIdentity=Get-DirectoryIdentity $script:cleanupFixture.OriginalPath
        if($script:cleanupFixture.ReplacementIdentity.Key-ceq$script:cleanupFixture.OwnedIdentity.Key){throw (New-HookFailure FIXTURE_SETUP 'Replacement unexpectedly has the invocation-owned staging identity.')}
        $script:cleanupFixture.SetupSucceeded=$true
    }
    $ownershipDestination=Join-Path $parent 'OwnershipLoss';$r=Invoke-Direct $mirror.Entry $ownershipDestination;Clear-Faults
    $retainedOriginal=$cleanupFixture.RetainedPath
    Assert-True Cleanup 'ownership-loss adversarial setup succeeded' $cleanupFixture.SetupSucceeded
    if($cleanupFixture.SetupSucceeded){
        $finalRetainedIdentity=Get-DirectoryIdentity $retainedOriginal
        $finalReplacementIdentity=Get-DirectoryIdentity $cleanupFixture.OriginalPath
        Assert-Equal Cleanup 'ownership-loss retained identity proven before cleanup' $cleanupFixture.RetainedIdentity.Key $cleanupFixture.OwnedIdentity.Key
        Assert-True Cleanup 'ownership-loss replacement identity differs before cleanup' ($cleanupFixture.ReplacementIdentity.Key-cne$cleanupFixture.OwnedIdentity.Key)
        Assert-Equal Cleanup 'ownership-loss preserves primary staged verification exit' $r.ExitCode 8
        Assert-True Cleanup 'ownership-loss requested destination absent' (-not(Test-Path -LiteralPath $ownershipDestination))
        Assert-True Cleanup 'ownership-loss original staging retained' (Test-Path -LiteralPath $retainedOriginal -PathType Container)
        Assert-Equal Cleanup 'ownership-loss retained identity preserved after cleanup refusal' $finalRetainedIdentity.Key $cleanupFixture.OwnedIdentity.Key
        Assert-Equal Cleanup 'ownership-loss replacement preserved after cleanup refusal' $finalReplacementIdentity.Key $cleanupFixture.ReplacementIdentity.Key
        Assert-True Cleanup 'retained staging path excluded from stdout' (-not$utf8.GetString($r.StdoutBytes).Contains($retainedOriginal,[StringComparison]::OrdinalIgnoreCase))
        Assert-True Cleanup 'retained staging reported diagnostically' ($r.Diagnostic.Contains('Retained staging path:',[StringComparison]::Ordinal)-and$r.Diagnostic.Contains('Cleanup refusal/failure:',[StringComparison]::Ordinal))
    }

    if($linkSupported){
        $cleanupTarget=Join-Path $tempRoot 'cleanup-link-target';[void][IO.Directory]::CreateDirectory($cleanupTarget)
        Set-Fault AfterStagingCreated {param($context);[void][IO.Directory]::CreateSymbolicLink((Join-Path $context.Path 'unsafe-link'),$script:cleanupTarget);throw (New-HookFailure STAGING_CREATE 'Injected unsafe cleanup tree.')}
        $cleanupDestination=Join-Path $parent 'CleanupReparse';$r=Invoke-Direct $mirror.Entry $cleanupDestination;Clear-Faults
        Assert-Equal Cleanup 'reparse cleanup refusal preserves primary exit' $r.ExitCode 5
        Assert-True Cleanup 'reparse cleanup refusal reported' $r.Diagnostic.Contains('Cleanup refusal/failure:',[StringComparison]::Ordinal)
        Assert-True Cleanup 'reparse cleanup destination absent' (-not(Test-Path -LiteralPath $cleanupDestination))
    }else{Assert-True Cleanup 'reparse cleanup case unsupported by host policy' $true}

    # Post-publication failure preserves the published destination and returns only a path-free failure result.
    Set-Fault BeforePostPublicationVerification {param($context);[IO.File]::WriteAllBytes((Join-Path $context.Destination.Path '.specops/bootstrap.json'),$utf8.GetBytes('{}'))}
    $postFailDestination=Join-Path $parent 'PostFailure';$postFail=Invoke-Direct $mirror.Entry $postFailDestination;Clear-Faults
    $postJson=$utf8.GetString($postFail.StdoutBytes)|ConvertFrom-Json
    Assert-Equal PostPublication 'post-publication corruption exit' $postFail.ExitCode 10
    if($postFail.ExitCode-ne10){throw "Post-publication fixture failed before post verification. stdout=$($utf8.GetString($postFail.StdoutBytes)) diagnostic=$($postFail.Diagnostic)"}
    Assert-Equal PostPublication 'post-publication failure phase' $postJson.phase 'post-publication-verification'
    Assert-Equal PostPublication 'post-publication failure status' $postJson.status 'FAILURE'
    Assert-True PostPublication 'published destination preserved' (Test-Path -LiteralPath $postFailDestination -PathType Container)
    Assert-Equal PostPublication 'published corruption preserved' ([IO.File]::ReadAllText((Join-Path $postFailDestination '.specops/bootstrap.json'))) '{}'
    Assert-True PostPublication 'published path absent from stdout' (-not$utf8.GetString($postFail.StdoutBytes).Contains($postFailDestination,[StringComparison]::OrdinalIgnoreCase))
    Assert-True PostPublication 'published path appears only diagnostically' $postFail.Diagnostic.Contains($postFailDestination,[StringComparison]::OrdinalIgnoreCase)

    Assert-True VCS 'successful mirror required no Git repository' (-not(Test-Path -LiteralPath (Join-Path $mirror.Root '.git/HEAD')))
    Assert-True VCS 'ambient Git data not projected' (-not(Test-Path -LiteralPath (Join-Path $destination '.git')))
    Assert-True VCS 'no child Git initialization' (-not(Test-Path -LiteralPath (Join-Path $destinationB '.git')))
}
finally {
    Clear-Faults
    if(Test-Path -LiteralPath $tempRoot){Remove-Item -LiteralPath $tempRoot -Recurse -Force}
}

$result=[ordered]@{Result=$(if($script:Failures.Count){'FAIL'}else{'PASS'});Tests=$script:Tests;Categories=$script:Categories;Failures=@($script:Failures);RegularLeafCount=402;AuthoredFiles=394;ImplementationSupportFiles=6;OutputCount=312;SourceIdentity='93fd1d378c47b24265eafe35130ddb1879aa4c3470ac77aba41ffda4313603ed';ImplementationVersion='1.0.0';UnityExecuted=$false;RealHumanDestinationUsed=$false;GitRequired=$false}
$result|ConvertTo-Json -Depth 20
if($script:Failures.Count){exit 1}
