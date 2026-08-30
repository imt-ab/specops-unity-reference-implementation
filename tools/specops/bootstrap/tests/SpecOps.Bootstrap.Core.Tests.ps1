[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Tests = 0
$script:Failures = [Collections.Generic.List[string]]::new()
$script:CategoryCounts = [ordered]@{}
$utf8 = [Text.UTF8Encoding]::new($false, $true)
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
Import-Module -Force (Join-Path $repositoryRoot 'tools/specops/bootstrap/SpecOps.Bootstrap.psm1')

function Add-Result {
    param([string]$Category,[string]$Name,[bool]$Pass,[string]$Detail='')
    $script:Tests++
    if(-not$script:CategoryCounts.Contains($Category)){$script:CategoryCounts[$Category]=0};$script:CategoryCounts[$Category]++
    if(-not$Pass){$script:Failures.Add("[$Category] $Name$(if($Detail){': '+$Detail})")}
}
function Assert-True { param([string]$Category,[string]$Name,[bool]$Condition,[string]$Detail='') Add-Result $Category $Name $Condition $Detail }
function Assert-Equal { param([string]$Category,[string]$Name,$Actual,$Expected) Add-Result $Category $Name ($Actual-ceq$Expected) "expected=$Expected actual=$Actual" }
function Assert-BytesEqual {
    param([string]$Category,[string]$Name,[byte[]]$Actual,[byte[]]$Expected)
    $equal=$Actual.Length-eq$Expected.Length
    if($equal){for($i=0;$i-lt$Actual.Length;$i++){if($Actual[$i]-ne$Expected[$i]){$equal=$false;break}}}
    Add-Result $Category $Name $equal
}
function Assert-Throws {
    param([string]$Category,[string]$Name,[scriptblock]$Action,[string]$Code='')
    $threw=$false;$detail=''
    try{&$Action}catch{$threw=$true;$detail=$_.Exception.Message;if($Code-and-not$detail.Contains($Code,[StringComparison]::Ordinal)){$threw=$false}}
    Add-Result $Category $Name $threw $detail
}
function B { param([string]$Text) return $utf8.GetBytes($Text) }
function S { param([byte[]]$Bytes) return $utf8.GetString($Bytes) }
function New-Transform {
    param([string]$Class,[string]$Selector,$Expected,[int]$Count,$Replacement,[string]$Id='fixture-transform')
    $postKind=if($Class-in@('CSHARP_UTF8_TOKEN','TEXT_UTF8_TOKEN','JSON_STRING_VALUE_TOKEN','JSON_MEMBER_NAME_OR_STRING_VALUE_TOKEN')){'TOKEN_ABSENT'}elseif($Class-ceq'JSON_ARRAY_ITEMS_BY_EXACT_VALUE'){'SELECTED_ITEMS_ABSENT'}elseif($Class-ceq'EVAL_DEFINITION_CONTENT_IDENTITY'){'EVAL_DEFINITION_IDENTITY_VALID'}elseif($Class-ceq'JSON_POINTER_MEMBER'-and$Replacement.kind-ceq'REMOVE_SELECTED_SPAN'){'SELECTOR_ABSENT'}else{'SELECTOR_EQUALS_REPLACEMENT'}
    $postSelector=if($Class-ceq'EVAL_DEFINITION_CONTENT_IDENTITY'){'/contentIdentity'}else{$Selector}
    return [pscustomobject]@{id=$Id;selectorClass=$Class;selector=$Selector;expectedSourceValue=$Expected;expectedMatchCount=$Count;replacement=$Replacement;encodingAndEscaping=[pscustomobject]@{sourceEncoding='UTF-8_NO_BOM';replacementEncoding='UTF-8_NO_BOM';escaping='EXACT_UTF8';preserveNonSelectedBytes=$true};postcondition=[pscustomobject]@{kind=$postKind;selector=$postSelector};forbiddenResidualValues=@()}
}

$valid = [ordered]@{DestinationPath='C:\SpecOps\SyntheticChild';ProjectId='synthetic-project';ProductName='Synthetic Product';CompanyName='Synthetic Company';ApplicationIdentifier='com.synthetic.project';CodeNamespaceRoot='Synthetic.Project'}
$inputs = Assert-BootstrapInvocationValues @valid
Assert-Equal Input 'valid canonical values retained' $inputs.ProjectId $valid.ProjectId
foreach($case in @(
    @{Name='ProjectId minimum';Patch=@{ProjectId='a'}},
    @{Name='ProjectId maximum';Patch=@{ProjectId=('a'+('1'*62))}},
    @{Name='Unicode product';Patch=@{ProductName='Ångström 🎮'}},
    @{Name='Unicode company';Patch=@{CompanyName='Équipe Société'}},
    @{Name='non-White_Space zero width space retained';Patch=@{ProductName=([char]0x200B+'Product')}},
    @{Name='namespace segment maximum';Patch=@{CodeNamespaceRoot=('A'+('a'*63))}},
    @{Name='application three segments';Patch=@{ApplicationIdentifier='a.b.c'}},
    @{Name='UNC destination';Patch=@{DestinationPath='\\server\share\child'}}
)){$args=@{};foreach($key in $valid.Keys){$args[$key]=$valid[$key]};foreach($key in $case.Patch.Keys){$args[$key]=$case.Patch[$key]};try{[void](Assert-BootstrapInvocationValues @args);$ok=$true}catch{$ok=$false};Assert-True Input $case.Name $ok}

$invalidCases = @(
    @{Name='ProjectId uppercase';Patch=@{ProjectId='Bad'}},@{Name='ProjectId leading digit';Patch=@{ProjectId='1bad'}},@{Name='ProjectId double hyphen';Patch=@{ProjectId='bad--id'}},
    @{Name='ProjectId too long';Patch=@{ProjectId=('a'*64)}},@{Name='non-ASCII ProjectId';Patch=@{ProjectId='å'}},@{Name='application two segments';Patch=@{ApplicationIdentifier='a.bc'}},
    @{Name='application uppercase';Patch=@{ApplicationIdentifier='com.Example.game'}},@{Name='application hyphen';Patch=@{ApplicationIdentifier='com.example.my-game'}},
    @{Name='namespace lowercase';Patch=@{CodeNamespaceRoot='bad.Root'}},@{Name='namespace underscore';Patch=@{CodeNamespaceRoot='Bad_Root'}},@{Name='namespace segment too long';Patch=@{CodeNamespaceRoot=('A'+('a'*64))}},
    @{Name='leading whitespace';Patch=@{ProductName=' Product'}},@{Name='trailing NBSP';Patch=@{CompanyName=('Company'+[char]0x00A0)}},@{Name='C0';Patch=@{ProductName="Bad`nName"}},@{Name='C1';Patch=@{CompanyName=('Bad'+[char]0x0085+'Name')}},
    @{Name='non-NFC product';Patch=@{ProductName=('e'+[char]0x0301)}},@{Name='unpaired surrogate';Patch=@{CompanyName=[string][char]0xD800}},
    @{Name='relative destination';Patch=@{DestinationPath='child'}},@{Name='lowercase drive';Patch=@{DestinationPath='c:\child'}},@{Name='drive root';Patch=@{DestinationPath='C:\'}},
    @{Name='forward slash';Patch=@{DestinationPath='C:\SpecOps/Child'}},@{Name='dot segment';Patch=@{DestinationPath='C:\SpecOps\.\Child'}},@{Name='full-path parent normalization rejected';Patch=@{DestinationPath='C:\SpecOps\Parent\..\Child'}},@{Name='trailing separator';Patch=@{DestinationPath='C:\SpecOps\Child\'}},
    @{Name='device namespace';Patch=@{DestinationPath='\\?\C:\Child'}},@{Name='reserved CON';Patch=@{DestinationPath='C:\SpecOps\CON'}},@{Name='reserved extension';Patch=@{DestinationPath='C:\SpecOps\Lpt1.txt'}},
    @{Name='reserved CONIN$';Patch=@{DestinationPath='C:\SpecOps\CONIN$'}},@{Name='reserved CONOUT$ extension';Patch=@{DestinationPath='C:\SpecOps\conout$.asset'}},
    @{Name='reserved COM superscript one';Patch=@{DestinationPath='C:\SpecOps\COM¹'}},@{Name='reserved COM superscript two extension';Patch=@{DestinationPath='C:\SpecOps\com².txt'}},@{Name='reserved COM superscript three';Patch=@{DestinationPath='C:\SpecOps\COM³'}},
    @{Name='reserved LPT superscript one';Patch=@{DestinationPath='C:\SpecOps\LPT¹'}},@{Name='reserved LPT superscript two extension';Patch=@{DestinationPath='C:\SpecOps\lpt².meta'}},@{Name='reserved LPT superscript three';Patch=@{DestinationPath='C:\SpecOps\LPT³'}},
    @{Name='trailing period';Patch=@{DestinationPath='C:\SpecOps\Child.'}},@{Name='invalid character';Patch=@{DestinationPath='C:\SpecOps\Bad*Name'}},@{Name='UNC no leaf';Patch=@{DestinationPath='\\server\share'}}
)
foreach($case in $invalidCases){$args=@{};foreach($key in $valid.Keys){$args[$key]=$valid[$key]};foreach($key in $case.Patch.Keys){$args[$key]=$case.Patch[$key]};Assert-Throws Input $case.Name {[void](Assert-BootstrapInvocationValues @args)}}
Assert-Equal Input 'canonical destination retained without repair' $inputs.DestinationPath ([IO.Path]::GetFullPath($valid.DestinationPath))
$module=Get-Module SpecOps.Bootstrap
$whiteSpaceScalars=@(0x0009,0x000A,0x000B,0x000C,0x000D,0x0020,0x0085,0x00A0,0x1680,0x2000,0x2001,0x2002,0x2003,0x2004,0x2005,0x2006,0x2007,0x2008,0x2009,0x200A,0x2028,0x2029,0x202F,0x205F,0x3000)
Assert-True Input 'exact F4 Unicode White_Space set accepted by classifier' (&$module {param($scalars) foreach($scalar in $scalars){if(-not(Test-BootstrapUnicodeWhiteSpace ([char]$scalar))){return $false}};return $true} $whiteSpaceScalars)
Assert-True Input 'U+200B is not F4 Unicode White_Space' (-not(&$module {Test-BootstrapUnicodeWhiteSpace ([char]0x200B)}))

$vectors=Get-Content -Raw -LiteralPath (Join-Path $repositoryRoot '.specops/contracts/content-identity-profile-v1.vectors.json')|ConvertFrom-Json -Depth 100
foreach($vector in $vectors.vectors){
    $bytes=B $vector.inputJsonText
    if($vector.expectedOutcome-ceq'IDENTITY'){$identity=Get-BootstrapJsonIdentity $bytes $vector.mode;Assert-Equal JCS "$($vector.id) canonical" $identity.canonicalJson $vector.expectedCanonicalJson;Assert-Equal JCS "$($vector.id) digest" $identity.value $vector.expectedSha256Hex}
    else{Assert-Throws JCS "$($vector.id) rejected" {[void](Get-BootstrapJsonIdentity $bytes $vector.mode)}}
}
Assert-Throws JCS 'invalid UTF-8 rejected' {[void](Read-BootstrapStrictJson ([byte[]]@(0x7B,0x22,0x78,0x22,0x3A,0x22,0xC3,0x28,0x22,0x7D)))} MALFORMED_UTF8
Assert-Throws JCS 'trailing comma rejected' {[void](Read-BootstrapStrictJson (B '{"a":1,}'))} MALFORMED_JSON
Assert-Throws JCS 'comment rejected' {[void](Read-BootstrapStrictJson (B '{/*x*/"a":1}'))} MALFORMED_JSON
Assert-Equal JCS 'negative zero canonicalizes to zero' (ConvertTo-BootstrapJcs (B '-0')) '0'
Assert-Equal JCS 'escaped string canonicalized deterministically' (ConvertTo-BootstrapJcs (B '{"x":"\u0041\/"}')) '{"x":"A/"}'

$schemaCapability=&$module {Get-BootstrapSchemaAdapterCapability}
Assert-True JCS 'complete Draft 2020-12 capability probes pass' $schemaCapability.Available $schemaCapability.Detail
$fakeInvariant=[pscustomobject]@{staticInvariants=[pscustomobject]@{prohibitedOutputPrefixes=@('Library/','Temp/');prohibitedOutputPaths=@('.git','.specops/evidence')}}
&$module {param($m) Assert-BootstrapOutputPaths @('A/a.txt','B/b.txt') $m} $fakeInvariant
Assert-True Planner 'valid paths accepted' $true
foreach($case in @(
    @{Name='ordinal collision';Paths=@('A/a','A/a')},@{Name='case collision';Paths=@('A/a','a/A')},@{Name='prefix collision';Paths=@('A','A/b')},
    @{Name='transient prefix';Paths=@('Library/x')},@{Name='prohibited exact';Paths=@('.git')},@{Name='prohibited subtree';Paths=@('.specops/evidence/x')},
    @{Name='reserved segment';Paths=@('Assets/CON/file')},@{Name='C0 output segment';Paths=@("Assets/Bad`nName/file")},@{Name='authored generated collision';Paths=@('a.json','a.json')}
)){Assert-Throws Planner $case.Name {&$module {param($paths,$m) Assert-BootstrapOutputPaths $paths $m} $case.Paths $fakeInvariant}}

$contentReplacement=[pscustomobject]@{kind='CONTENT_INPUT';name='CodeNamespaceRoot'}
$constantNew=[pscustomobject]@{kind='APPROVED_CONSTANT';name='FIXTURE';value='new'}
$remove=[pscustomobject]@{kind='REMOVE_SELECTED_SPAN'}
$transformFixtures=[ordered]@{}
$transformFixtures.CSHARP_UTF8_TOKEN=@{Bytes=B 'PRE /* InfiniteMonkey */ MyInfiniteMonkeyService namespace InfiniteMonkey.X InfiniteMonkeyFactory SomeInfiniteMonkey; char c=''I''; POST';Transform=(New-Transform CSHARP_UTF8_TOKEN 'csharp token' 'InfiniteMonkey' 1 $contentReplacement);Contains='namespace Synthetic.Project.X';Prefix='PRE /* InfiniteMonkey */ MyInfiniteMonkeyService ';Suffix=' InfiniteMonkeyFactory SomeInfiniteMonkey; char c=''I''; POST'}
$transformFixtures.TEXT_UTF8_EXACT_SPAN=@{Bytes=B 'PRE old exact POST';Transform=(New-Transform TEXT_UTF8_EXACT_SPAN 'exact span' 'old exact' 1 $constantNew);Contains='PRE new POST';Prefix='PRE ';Suffix=' POST'}
$transformFixtures.TEXT_UTF8_TOKEN=@{Bytes=B 'PRE InfiniteMonkey.X POST';Transform=(New-Transform TEXT_UTF8_TOKEN 'token' 'InfiniteMonkey' 1 $contentReplacement);Contains='PRE Synthetic.Project.X POST';Prefix='PRE ';Suffix='.X POST'}
$transformFixtures.JSON_STRING_VALUE_TOKEN=@{Bytes=B '{ "pre":1, "x":"PRE-\u0049nfiniteMonkey-POST", "post":2 }';Transform=(New-Transform JSON_STRING_VALUE_TOKEN 'strings' 'InfiniteMonkey' 1 $contentReplacement);Contains='"PRE-Synthetic.Project-POST"';Prefix='{ "pre":1, "x":"PRE-';Suffix='-POST", "post":2 }'}
$transformFixtures.JSON_MEMBER_NAME_OR_STRING_VALUE_TOKEN=@{Bytes=B '{"PRE-InfiniteMonkey-POST":"PRE-InfiniteMonkey-POST"}';Transform=(New-Transform JSON_MEMBER_NAME_OR_STRING_VALUE_TOKEN 'names and values' 'InfiniteMonkey' 2 $contentReplacement);Contains='{"PRE-Synthetic.Project-POST":"PRE-Synthetic.Project-POST"}';Prefix='{"PRE-';Suffix='-POST"}'}
$transformFixtures.JSON_POINTER_VALUE=@{Bytes=B '{ "pre":1, "x" : "old", "post":2 }';Transform=(New-Transform JSON_POINTER_VALUE '/x' 'old' 1 $constantNew);Contains='"x" : "new"';Prefix='{ "pre":1, "x" : ';Suffix=', "post":2 }'}
$transformFixtures.JSON_POINTER_MEMBER=@{Bytes=B '{ "pre":1, "x":"old", "post":2 }';Transform=(New-Transform JSON_POINTER_MEMBER '/x' 'old' 1 $remove);Contains='"pre":1,  "post":2';Prefix='{ "pre":1, ';Suffix=' "post":2 }'}
$transformFixtures.JSON_ARRAY_ITEMS_BY_EXACT_VALUE=@{Bytes=B '{"x":["PRE", "old", "POST"]}';Transform=(New-Transform JSON_ARRAY_ITEMS_BY_EXACT_VALUE '/x' 'old' 1 $remove);Contains='["PRE",  "POST"]';Prefix='{"x":["PRE", ';Suffix=' "POST"]}'}
$evalSource='{"pre":"PRE","contentIdentity":{"algorithm":"specops-json-jcs-sha256-v1","value":"'+('a'*64)+'"},"post":"POST"}'
$evalReplacement=[pscustomobject]@{kind='DETERMINISTIC_DERIVATION';name='EVAL_DEFINITION_CONTENT_IDENTITY_V1';inputs=@('TransformedEvalDefinition')}
$transformFixtures.EVAL_DEFINITION_CONTENT_IDENTITY=@{Bytes=B $evalSource;Transform=(New-Transform EVAL_DEFINITION_CONTENT_IDENTITY '/contentIdentity/value' ('a'*64) 1 $evalReplacement);Contains='"value":"';Prefix='{"pre":"PRE","contentIdentity":';Suffix=',"post":"POST"}'}
$transformFixtures.UNITY_YAML_SCALAR=@{Bytes=B "PlayerSettings:`n  productName: old`n  untouched: POST`n";Transform=(New-Transform UNITY_YAML_SCALAR 'PlayerSettings/productName' 'old' 1 $constantNew);Contains="productName: new";Prefix="PlayerSettings:`n  productName: ";Suffix="`n  untouched: POST`n"}

foreach($class in $transformFixtures.Keys){
    $fixture=$transformFixtures[$class];$result=Invoke-BootstrapScopedTransforms $fixture.Bytes @($fixture.Transform) $inputs;$text=S $result
    Assert-True Transform "$class positive" $text.Contains($fixture.Contains,[StringComparison]::Ordinal) $text
    Assert-True Preservation "$class prefix gap preserved" $text.StartsWith($fixture.Prefix,[StringComparison]::Ordinal) $text
    Assert-True Preservation "$class suffix gap preserved" $text.EndsWith($fixture.Suffix,[StringComparison]::Ordinal) $text
    $badCount=$fixture.Transform.PSObject.Copy();$badCount.expectedMatchCount=99
    Assert-Throws Transform "$class count mismatch" {[void](Invoke-BootstrapScopedTransforms $fixture.Bytes @($badCount) $inputs)} MATCH_COUNT
    $badExpected=$fixture.Transform.PSObject.Copy();$badExpected.expectedSourceValue='definitely-absent'
    Assert-Throws Transform "$class expected mismatch" {[void](Invoke-BootstrapScopedTransforms $fixture.Bytes @($badExpected) $inputs)}
}
$unsupported=(New-Transform NOT_A_SELECTOR 'x' 'x' 1 $constantNew)
Assert-Throws Transform 'unsupported selector spelling' {[void](Invoke-BootstrapScopedTransforms (B 'x') @($unsupported) $inputs)} UNSUPPORTED_SELECTOR
$overlapA=New-Transform TEXT_UTF8_EXACT_SPAN a 'aba' 1 $constantNew 'a';$overlapB=New-Transform TEXT_UTF8_EXACT_SPAN b 'bab' 1 $constantNew 'b'
Assert-Throws Transform 'transform overlap or invalidated precondition fails' {[void](Invoke-BootstrapScopedTransforms (B 'ababa') @($overlapA,$overlapB) $inputs)}
$commentFixture=$transformFixtures.CSHARP_UTF8_TOKEN;$commentResult=S (Invoke-BootstrapScopedTransforms $commentFixture.Bytes @($commentFixture.Transform) $inputs)
Assert-True Transform 'C# comment attribution not replaced' $commentResult.Contains('/* InfiniteMonkey */',[StringComparison]::Ordinal)
Assert-True Transform 'C# prefixed identifier is not replaced' $commentResult.Contains('MyInfiniteMonkeyService',[StringComparison]::Ordinal)
Assert-True Transform 'C# suffixed identifier is not replaced' $commentResult.Contains('InfiniteMonkeyFactory',[StringComparison]::Ordinal)
Assert-True Transform 'C# embedded identifier suffix is not replaced' $commentResult.Contains('SomeInfiniteMonkey',[StringComparison]::Ordinal)
$unsupportedCSharp=New-Transform CSHARP_UTF8_TOKEN csharp InfiniteMonkey 1 $contentReplacement
Assert-Throws Transform 'C# target in interpolated literal fails closed' {[void](Invoke-BootstrapScopedTransforms (B '$"InfiniteMonkey"') @($unsupportedCSharp) $inputs)} UNSUPPORTED_CSHARP_LITERAL
$escapedCSharp='PRE "PRE-\u0049nfiniteMonkey-POST" GAP'
$escapedCSharpResult=S (Invoke-BootstrapScopedTransforms (B $escapedCSharp) @($unsupportedCSharp) $inputs)
Assert-Equal Transform 'C# decoded Unicode escape is selected' $escapedCSharpResult 'PRE "PRE-Synthetic.Project-POST" GAP'
Assert-True Preservation 'C# decoded escape prefix gap preserved' $escapedCSharpResult.StartsWith('PRE "PRE-',[StringComparison]::Ordinal)
Assert-True Preservation 'C# decoded escape suffix gap preserved' $escapedCSharpResult.EndsWith('-POST" GAP',[StringComparison]::Ordinal)
$multilineUnsupported='$@"first'+"`n"+'InfiniteMonkey'+"`n"+'last"'
Assert-Throws Transform 'multiline unsupported C# literal fails closed' {[void](Invoke-BootstrapScopedTransforms (B $multilineUnsupported) @($unsupportedCSharp) $inputs)} UNSUPPORTED_CSHARP_LITERAL
$quotedYaml=New-Transform UNITY_YAML_SCALAR 'PlayerSettings/productName' old 1 ([pscustomobject]@{kind='APPROVED_CONSTANT';name='FIXTURE';value='true'})
Assert-True Transform 'YAML unsafe scalar is deterministically quoted' ((S (Invoke-BootstrapScopedTransforms (B "PlayerSettings:`n  productName: old`n") @($quotedYaml) $inputs)).Contains('productName: "true"',[StringComparison]::Ordinal))
foreach($separator in @([char]0x2028,[char]0x2029)){$yamlValue='Before'+$separator+'After';$yamlTransform=New-Transform UNITY_YAML_SCALAR 'PlayerSettings/productName' old 1 ([pscustomobject]@{kind='APPROVED_CONSTANT';name='FIXTURE';value=$yamlValue});$yamlResult=S (Invoke-BootstrapScopedTransforms (B "PlayerSettings:`n  productName: old`n  untouched: GAP`n") @($yamlTransform) $inputs);$escape='\u'+([int]$separator).ToString('x4');Assert-True Transform "YAML line separator $escape escaped" $yamlResult.Contains($escape,[StringComparison]::Ordinal);Assert-True Preservation "YAML line separator $escape gaps preserved" ($yamlResult.StartsWith("PlayerSettings:`n  productName: `"Before",[StringComparison]::Ordinal)-and$yamlResult.EndsWith("After`"`n  untouched: GAP`n",[StringComparison]::Ordinal))}

Assert-Equal Derivation 'productGUID known answer' (Get-BootstrapProductGuid $valid.ProjectId $valid.ApplicationIdentifier) 'd22bb1c8d0dc3f76bf4e806827424ac2'
$nulVariant=Get-BootstrapProductGuid 'synthetic-projectx' 'com.synthetic.project'
Assert-True Derivation 'productGUID input framing changes digest' ($nulVariant-cne'd22bb1c8d0dc3f76bf4e806827424ac2')

$tempRoot=Join-Path ([IO.Path]::GetTempPath()) ('specops-f5-'+[guid]::NewGuid().ToString('N'))
try{
    [void](New-Item -ItemType Directory -Path (Join-Path $tempRoot '.specops/contracts') -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $tempRoot '.specops/bootstrap') -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $tempRoot 'tools/specops/bootstrap') -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $tempRoot 'src') -Force)
    [IO.File]::WriteAllBytes((Join-Path $tempRoot '.specops/contracts/schema.json'),(B '{}'))
    [IO.File]::WriteAllBytes((Join-Path $tempRoot '.specops/bootstrap/manifest.json'),(B 'manifest'))
    [IO.File]::WriteAllBytes((Join-Path $tempRoot 'src/a.txt'),(B 'source'))
    [IO.File]::WriteAllBytes((Join-Path $tempRoot 'tools/specops/bootstrap/support.ps1'),(B 'support'))
    $mini=[pscustomobject]@{bootstrapSourceMetadata=@([pscustomobject]@{path='.specops/bootstrap/manifest.json';role='PROJECTION_MANIFEST'},[pscustomobject]@{path='.specops/contracts/schema.json';role='PROJECTION_MANIFEST_SCHEMA';byteIdentity=[pscustomobject]@{byteLength=2;sha256=(Get-BootstrapSha256Hex (B '{}'))}});authoredSourceInventory=@([pscustomobject]@{sourcePath='src/a.txt';byteIdentity=[pscustomobject]@{byteLength=6;sha256=(Get-BootstrapSha256Hex (B 'source'))};disposition='COPY_EXACT';output=[pscustomobject]@{path='src/a.txt'}});bootstrapImplementationSupport=[pscustomobject]@{root='tools/specops/bootstrap/'}}
    $miniRecord=[pscustomobject]@{Manifest=$mini;Bytes=(B 'manifest');SchemaBytes=(B '{}');SchemaPath=(Join-Path $tempRoot '.specops/contracts/schema.json');SourceIdentity=[pscustomobject]@{digest=('a'*64)}}
    $repoPaths=@('.specops/bootstrap/manifest.json','.specops/contracts/schema.json','src/a.txt','tools/specops/bootstrap/support.ps1')
    $enumeratedMini=Get-VerifiedBootstrapSource $tempRoot $miniRecord
    Assert-Equal Source 'default filesystem enumeration count' $enumeratedMini.RegularLeafCount 4
    Assert-Equal Source 'default source mode is filesystem enumeration' $enumeratedMini.EnumerationMode 'FILESYSTEM'
    [IO.File]::WriteAllBytes((Join-Path $tempRoot 'unexpected.tmp'),(B 'unexpected'));Assert-Throws Source 'unexpected real leaf fails' {[void](Get-VerifiedBootstrapSource $tempRoot $miniRecord)} CLOSED_ACCOUNTING;Remove-Item -LiteralPath (Join-Path $tempRoot 'unexpected.tmp')
    [IO.File]::WriteAllBytes((Join-Path $tempRoot 'tools/specops/bootstrap/future.ps1'),(B 'future'));$futureSupport=Get-VerifiedBootstrapSource $tempRoot $miniRecord;Assert-True Source 'real support leaf under approved root succeeds' ($futureSupport.ImplementationSupportPaths-ccontains'tools/specops/bootstrap/future.ps1');Remove-Item -LiteralPath (Join-Path $tempRoot 'tools/specops/bootstrap/future.ps1')
    [IO.File]::WriteAllBytes((Join-Path $tempRoot 'tools/specops/future.ps1'),(B 'future'));Assert-Throws Source 'same real leaf outside support root fails' {[void](Get-VerifiedBootstrapSource $tempRoot $miniRecord)} CLOSED_ACCOUNTING;Remove-Item -LiteralPath (Join-Path $tempRoot 'tools/specops/future.ps1')
    $verifiedMini=Get-VerifiedBootstrapSource $tempRoot $miniRecord $repoPaths
    Assert-Equal Source 'exact hash and length pass' $verifiedMini.Bytes['src/a.txt'].Length 6
    Assert-True Source 'implementation support recognized' ($verifiedMini.ImplementationSupportPaths-ccontains'tools/specops/bootstrap/support.ps1')
    $mini.authoredSourceInventory[0].byteIdentity.sha256='0'*64;Assert-Throws Source 'hash mismatch fails' {[void](Get-VerifiedBootstrapSource $tempRoot $miniRecord $repoPaths)} BYTE_HASH
    $mini.authoredSourceInventory[0].byteIdentity.sha256=Get-BootstrapSha256Hex (B 'source');$mini.authoredSourceInventory[0].byteIdentity.byteLength=7;Assert-Throws Source 'length mismatch fails' {[void](Get-VerifiedBootstrapSource $tempRoot $miniRecord $repoPaths)} BYTE_LENGTH
    $mini.authoredSourceInventory[0].byteIdentity.byteLength=6;Move-Item -LiteralPath (Join-Path $tempRoot 'src/a.txt') -Destination (Join-Path $tempRoot 'src/missing.txt');Assert-Throws Source 'missing authored source fails' {[void](Get-VerifiedBootstrapSource $tempRoot $miniRecord $repoPaths)} MISSING_SOURCE
}finally{if(Test-Path -LiteralPath $tempRoot){Remove-Item -LiteralPath $tempRoot -Recurse -Force}}

$metadata=@('manifest','schema');$authored=@('a');$support=@('tools/specops/bootstrap/support')
Assert-True Source 'closed three-category accounting pass' (Test-BootstrapClosedSourceAccounting @($metadata+$authored+$support) $metadata $authored $support 'tools/specops/bootstrap/')
Assert-True Source 'unexpected source rejected' (-not(Test-BootstrapClosedSourceAccounting @($metadata+$authored+$support+'transient.tmp') $metadata $authored $support 'tools/specops/bootstrap/'))
Assert-True Source 'hypothetical support accepted' (Test-BootstrapClosedSourceAccounting @($metadata+$authored+$support+'tools/specops/bootstrap/future.ps1') $metadata $authored @($support+'tools/specops/bootstrap/future.ps1') 'tools/specops/bootstrap/')
Assert-True Source 'same support outside root rejected' (-not(Test-BootstrapClosedSourceAccounting @($metadata+$authored+$support+'tools/specops/future.ps1') $metadata $authored @($support+'tools/specops/future.ps1') 'tools/specops/bootstrap/'))
Assert-True Source 'case duplicate rejected' (-not(Test-BootstrapClosedSourceAccounting @('A','a') @('A','a') @() @() 'tools/specops/bootstrap/'))

$manifestPath=Join-Path $repositoryRoot '.specops/bootstrap/bootstrap-v1.projection-manifest.json'
$manifestSchema=Join-Path $repositoryRoot '.specops/contracts/bootstrap-projection-manifest.schema.json'
$provenanceSchema=Join-Path $repositoryRoot '.specops/contracts/bootstrap-provenance.schema.json'
$record=Read-BootstrapProjectionManifest $manifestPath $manifestSchema
$wrongSchema=Join-Path ([IO.Path]::GetTempPath()) ('specops-wrong-schema-'+[guid]::NewGuid().ToString('N')+'.json')
try{[IO.File]::WriteAllBytes($wrongSchema,(B '{}'));Assert-Throws JCS 'unverified arbitrary manifest schema rejected' {[void](Read-BootstrapProjectionManifest $manifestPath $wrongSchema)} SOURCE_METADATA}finally{if(Test-Path -LiteralPath $wrongSchema){Remove-Item -LiteralPath $wrongSchema -Force}}
$integrationRoot=Join-Path ([IO.Path]::GetTempPath()) ('specops-f5-current-source-'+[guid]::NewGuid().ToString('N'))
try{
    [void](New-Item -ItemType Directory -Path $integrationRoot -Force)
    $currentSupport=@(Get-ChildItem -LiteralPath (Join-Path $repositoryRoot 'tools/specops/bootstrap') -File -Recurse -Force|ForEach-Object{[IO.Path]::GetRelativePath($repositoryRoot,$_.FullName).Replace('\','/')})
    $currentSourcePaths=@(@($record.Manifest.bootstrapSourceMetadata.path)+@($record.Manifest.authoredSourceInventory.sourcePath)+$currentSupport|Sort-Object -Unique)
    foreach($path in $currentSourcePaths){$destination=Join-Path $integrationRoot $path;$parent=Split-Path -Parent $destination;[void](New-Item -ItemType Directory -Path $parent -Force);[IO.File]::WriteAllBytes($destination,[IO.File]::ReadAllBytes((Join-Path $repositoryRoot $path)))}
    $source=Get-VerifiedBootstrapSource $integrationRoot $record
    Assert-Equal Integration 'current source uses filesystem enumeration' $source.EnumerationMode 'FILESYSTEM'
    Assert-Equal Integration 'actual enumerated regular-leaf count' $source.RegularLeafCount 402
    $verifiedProvenanceSchema=$source.Bytes['.specops/contracts/bootstrap-provenance.schema.json']
    [IO.File]::WriteAllBytes((Join-Path $integrationRoot '.specops/contracts/bootstrap-provenance.schema.json'),(B '{"tampered":true}'))
    $output=New-BootstrapProspectiveOutputMap $source $inputs '1.0.0'
    Assert-True Provenance 'filesystem schema mutation after materialization is neutral' $output.Bytes.ContainsKey('.specops/bootstrap.json')
$static=Test-BootstrapByteMapStatic $output
Assert-Equal Integration 'Source Identity reproduced' $record.SourceIdentity.digest 'e131f5db9415d8c479cf7472f8e09b1530499cec7f67bd4520f52989e10dc1db'
Assert-Equal Integration 'all authored files verified' $source.Bytes.Count 394
Assert-True Integration 'implementation module recognized as support' ($source.ImplementationSupportPaths-ccontains'tools/specops/bootstrap/SpecOps.Bootstrap.psm1')
Assert-True Integration 'core tests recognized as support' ($source.ImplementationSupportPaths-ccontains'tools/specops/bootstrap/tests/SpecOps.Bootstrap.Core.Tests.ps1')
Assert-True Integration 'execution entry point recognized as support' ($source.ImplementationSupportPaths-ccontains'tools/specops/bootstrap/Invoke-SpecOpsBootstrap.ps1')
Assert-True Integration 'execution tests recognized as support' ($source.ImplementationSupportPaths-ccontains'tools/specops/bootstrap/tests/SpecOps.Bootstrap.Execution.Tests.ps1')
Assert-True Integration 'conformance tests recognized as support' ($source.ImplementationSupportPaths-ccontains'tools/specops/bootstrap/tests/SpecOps.Bootstrap.Conformance.Tests.ps1')
Assert-Equal Integration 'implementation support topology count' $source.ImplementationSupportPaths.Count 6
Assert-Equal Integration 'prospective output count' $output.Count 312
Assert-True Integration 'generated provenance present' $output.Bytes.ContainsKey('.specops/bootstrap.json')
Assert-True Integration 'static byte-map verification' $static.Pass ($static.Findings-join'; ')
$agentsText=S $output.Bytes['AGENTS.md']
$globalConstraintsText=S $output.Bytes['Assets/Project/Docs/Governance/GLOBAL_CONSTRAINTS.md']
$producerGlobalConstraintsText=Get-Content -Raw -LiteralPath (Join-Path $repositoryRoot 'Assets/Project/Docs/Governance/GLOBAL_CONSTRAINTS.md')
Assert-True RMD 'RMD-AC-001 child global constraints omit producer repository identity' (-not$globalConstraintsText.Contains('specops-unity-reference-implementation',[StringComparison]::Ordinal))
Assert-True RMD 'RMD-AC-002 child global constraints omit public-reference classifications' (
    -not$globalConstraintsText.Contains('this public Unity reference repository',[StringComparison]::Ordinal)-and
    -not$globalConstraintsText.Contains('public reference implementation',[StringComparison]::Ordinal)-and
    -not$globalConstraintsText.Contains('Golden Baseline candidate',[StringComparison]::Ordinal)
)
Assert-True RMD 'RMD-AC-003 child global constraints retain generic current authority and applicability' (
    $globalConstraintsText.Contains('Status: Current repository-wide engineering constraint authority for this repository.',[StringComparison]::Ordinal)-and
    $globalConstraintsText.Contains('These constraints apply to work across this governed Unity game project.',[StringComparison]::Ordinal)
)
Assert-True RMD 'RMD-AC-004 producer global constraints remain producer-specific' (
    $producerGlobalConstraintsText.Contains('Status: Current repository-wide engineering constraint authority for `specops-unity-reference-implementation`.',[StringComparison]::Ordinal)-and
    $producerGlobalConstraintsText.Contains('These constraints apply to work across this public Unity reference repository.',[StringComparison]::Ordinal)-and
    $producerGlobalConstraintsText.Contains('public reference implementation and Golden Baseline candidate',[StringComparison]::Ordinal)
)
Assert-True RMD 'RMD-AC-005 child AGENTS omits excluded ONBOARDING route' (-not$agentsText.Contains('ONBOARDING.md',[StringComparison]::Ordinal))
Assert-True RMD 'RMD-AC-006 child AGENTS omits excluded DEPLOYMENT route' (-not$agentsText.Contains('DEPLOYMENT.md',[StringComparison]::Ordinal))
$requiredAgentRoutes=@(
    'Assets/Project/Docs/SpecOps/SPECOPS_V2.md','Assets/Project/Docs/Architecture/ARCHITECTURE.md',
    'Assets/Project/Docs/Governance/GLOBAL_CONSTRAINTS.md','Assets/Project/Docs/SpecOps/WORKFLOW.md',
    'ADRs','plans','reviews','validation results','context exports','.specops/permissions.json',
    'specops-spec','specops-review','specops-plan','specops-implement','specops-validate','specops-sync','specops-audit'
)
$agentsRoutesValid=$agentsText.Contains('explicit authorization',[StringComparison]::Ordinal)-and
    $agentsText.Contains('human-controlled under repository policy',[StringComparison]::Ordinal)
foreach($route in $requiredAgentRoutes){$agentsRoutesValid=$agentsRoutesValid-and$agentsText.Contains($route,[StringComparison]::Ordinal)}
Assert-True RMD 'RMD-AC-007 child AGENTS retains authority workflow decision evidence permission and seven-skill routes' $agentsRoutesValid
Assert-True RMD 'RMD-AC-008 zero-feature child remains intact' (
    -not(@($output.Bytes.Keys|Where-Object{$_-like'Assets/Project/Docs/Specifications/*/SPECOPS_STATE.json'-and$_-notlike'Assets/Project/Docs/Specifications/_templates/*'}).Count)-and
    -not(@($output.Bytes.Keys|Where-Object{$_.Contains('reference-architecture-example',[StringComparison]::OrdinalIgnoreCase)}).Count)
)
$specops=S $output.Bytes['.specops/specops.json']|ConvertFrom-Json -Depth 100
Assert-Equal Derivation 'repository id member derivation' $specops.repository.id $valid.ProjectId
Assert-True Derivation 'legacy repository identity member removed' ($null-eq$specops.repository.PSObject.Properties['identity'])
$specopsEntry=$record.Manifest.authoredSourceInventory|Where-Object sourcePath -CEQ '.specops/specops.json'
$releaseEvidenceReset=@($specopsEntry.transforms|Where-Object id -CEQ 'initialization-release-evidence-present-reset')
$releasedVersionReset=@($specopsEntry.transforms|Where-Object id -CEQ 'repository-released-version-reset')
Assert-Equal Derivation 'releaseEvidencePresent reset transform count' $releaseEvidenceReset.Count 1
Assert-Equal Derivation 'releaseEvidencePresent reset approved constant' $releaseEvidenceReset[0].replacement.name 'RELEASE_EVIDENCE_PRESENT_FALSE'
Assert-Equal Derivation 'releasedVersion reset transform count' $releasedVersionReset.Count 1
Assert-Equal Derivation 'releasedVersion reset approved constant' $releasedVersionReset[0].replacement.name 'RELEASED_VERSION_NULL'
Assert-True Derivation 'fresh releasedVersion null' ($null-eq$specops.repository.releasedVersion)
Assert-True Derivation 'fresh releaseEvidencePresent false' ($specops.initialization.releaseEvidencePresent-eq$false)
foreach($evalPath in @('.specops/evals/unity-clean-architecture-static.eval.json','.specops/evals/unity-editmode-validation.eval.json')){$eval=S $output.Bytes[$evalPath]|ConvertFrom-Json -Depth 100;$identity=Get-BootstrapJsonIdentity $output.Bytes[$evalPath] EVAL_DEFINITION;Assert-Equal Derivation "eval identity $evalPath" $eval.contentIdentity.value $identity.value}

$provenanceA=New-BootstrapProvenance $inputs $record.Manifest '1.0.0' $verifiedProvenanceSchema
$otherArgs=@{};foreach($key in $valid.Keys){$otherArgs[$key]=$valid[$key]};$otherArgs.DestinationPath='D:\Elsewhere\AnotherChild';$otherInputs=Assert-BootstrapInvocationValues @otherArgs
$provenanceB=New-BootstrapProvenance $otherInputs $record.Manifest '1.0.0' $verifiedProvenanceSchema
Assert-BytesEqual Provenance 'DestinationPath neutrality' $provenanceA $provenanceB
Assert-True Provenance 'no BOM' (-not($provenanceA.Length-ge3-and$provenanceA[0]-eq0xEF-and$provenanceA[1]-eq0xBB-and$provenanceA[2]-eq0xBF))
Assert-True Provenance 'no trailing newline' ($provenanceA[-1]-notin@(10,13))
$provenanceText=S $provenanceA
Assert-True Provenance 'schema-valid deterministic bytes' (Test-Json -Json $provenanceText -SchemaFile $provenanceSchema -ErrorAction SilentlyContinue)
foreach($ambient in @('DestinationPath','C:\SpecOps\SyntheticChild','sourcePath','stagingPath','timestamp','gitCommit','validationStatus','releaseStatus','approval')){Assert-True Provenance "ambient value absent: $ambient" (-not$provenanceText.Contains($ambient,[StringComparison]::OrdinalIgnoreCase))}

$sourceKinds=@($record.Manifest.authoredSourceInventory|Where-Object disposition -EQ 'TRANSFORM_SCOPED'|ForEach-Object{$_.transforms.selectorClass}|Sort-Object -Unique)
foreach($class in $transformFixtures.Keys){Assert-True Integration "current manifest uses $class" ($sourceKinds-ccontains$class)}

}finally{if(Test-Path -LiteralPath $integrationRoot){Remove-Item -LiteralPath $integrationRoot -Recurse -Force}}

if($script:Failures.Count-gt0){[pscustomobject]@{Result='FAIL';Tests=$script:Tests;Categories=$script:CategoryCounts;Failures=@($script:Failures);SourceIdentity=$record.SourceIdentity.digest;AuthoredFiles=$source.Bytes.Count;ImplementationSupportFiles=$source.ImplementationSupportPaths.Count;OutputCount=$output.Count;StaticVerification=$static.Pass}|ConvertTo-Json -Depth 20;exit 1}
[pscustomobject]@{Result='PASS';Tests=$script:Tests;Categories=$script:CategoryCounts;Failures=@();SourceIdentity=$record.SourceIdentity.digest;RegularLeafCount=$source.RegularLeafCount;AuthoredFiles=$source.Bytes.Count;ImplementationSupportFiles=$source.ImplementationSupportPaths.Count;OutputCount=$output.Count;SelectorClasses=$transformFixtures.Keys.Count;StaticVerification=$static.Pass;UnityExecuted=$false}|ConvertTo-Json -Depth 20
