Set-StrictMode -Version Latest

$script:Utf8 = [Text.UTF8Encoding]::new($false, $true)
$script:Invariant = [Globalization.CultureInfo]::InvariantCulture
$script:SourceIdentityProfile = 'specops-bootstrap-source-jcs-sha256-v1'
$script:JsonIdentityProfile = 'specops-json-jcs-sha256-v1'
$script:SchemaAdapterCapability = $null
$script:ExecutionFaults = @{}
$script:SelectorClasses = @(
    'CSHARP_UTF8_TOKEN',
    'EVAL_DEFINITION_CONTENT_IDENTITY',
    'JSON_ARRAY_ITEMS_BY_EXACT_VALUE',
    'JSON_POINTER_MEMBER',
    'JSON_POINTER_VALUE',
    'JSON_MEMBER_NAME_OR_STRING_VALUE_TOKEN',
    'JSON_STRING_VALUE_TOKEN',
    'TEXT_UTF8_EXACT_SPAN',
    'TEXT_UTF8_TOKEN',
    'UNITY_YAML_SCALAR'
)
$script:ReservedWindowsBasenames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($reservedName in @(
    'CON','PRN','AUX','NUL','CLOCK$','CONIN$','CONOUT$',
    'COM1','COM2','COM3','COM4','COM5','COM6','COM7','COM8','COM9',
    'LPT1','LPT2','LPT3','LPT4','LPT5','LPT6','LPT7','LPT8','LPT9',
    'COM¹','COM²','COM³','LPT¹','LPT²','LPT³'
)){[void]$script:ReservedWindowsBasenames.Add($reservedName)}

function Throw-BootstrapFailure {
    param([Parameter(Mandatory)][string] $Code, [Parameter(Mandatory)][string] $Message)
    $exception = [IO.InvalidDataException]::new("$Code`: $Message")
    $exception.Data['BootstrapFailureCode'] = $Code
    throw $exception
}

function Get-BootstrapScalarCount {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Value)
    $count = 0
    for ($index = 0; $index -lt $Value.Length; $index++) {
        $unit = [int]$Value[$index]
        if ($unit -ge 0xD800 -and $unit -le 0xDBFF) {
            if ($index + 1 -ge $Value.Length -or [int]$Value[$index + 1] -lt 0xDC00 -or [int]$Value[$index + 1] -gt 0xDFFF) {
                Throw-BootstrapFailure INVALID_UNICODE 'A high surrogate is not followed by a low surrogate.'
            }
            $index++
        }
        elseif ($unit -ge 0xDC00 -and $unit -le 0xDFFF) {
            Throw-BootstrapFailure INVALID_UNICODE 'A low surrogate is not preceded by a high surrogate.'
        }
        $count++
    }
    return $count
}

function Test-BootstrapUnicodeWhiteSpace {
    param([char] $Character)
    $scalar = [int]$Character
    return (
        ($scalar -ge 0x0009 -and $scalar -le 0x000D) -or
        $scalar -eq 0x0020 -or
        $scalar -eq 0x0085 -or
        $scalar -eq 0x00A0 -or
        $scalar -eq 0x1680 -or
        ($scalar -ge 0x2000 -and $scalar -le 0x200A) -or
        ($scalar -ge 0x2028 -and $scalar -le 0x2029) -or
        $scalar -eq 0x202F -or
        $scalar -eq 0x205F -or
        $scalar -eq 0x3000
    )
}

function Assert-BootstrapCommonValue {
    param([Parameter(Mandatory)][string] $Name, [AllowNull()][AllowEmptyString()][string] $Value)
    if ($null -eq $Value -or $Value.Length -eq 0) { Throw-BootstrapFailure INVALID_INPUT "$Name must be non-empty." }
    [void](Get-BootstrapScalarCount $Value)
    :characterLoop for ($index = 0; $index -lt $Value.Length; $index++) {
        $character = $Value[$index]
        $code = [int]$character
        if (($code -ge 0 -and $code -le 0x1F) -or ($code -ge 0x7F -and $code -le 0x9F)) {
            Throw-BootstrapFailure INVALID_INPUT "$Name contains a C0 or C1 control character."
        }
    }
    if ((Test-BootstrapUnicodeWhiteSpace $Value[0]) -or (Test-BootstrapUnicodeWhiteSpace $Value[$Value.Length - 1])) {
        Throw-BootstrapFailure INVALID_INPUT "$Name has leading or trailing Unicode White_Space."
    }
}

function Test-BootstrapAscii {
    param([string] $Value)
    foreach ($character in $Value.ToCharArray()) { if ([int]$character -gt 0x7F) { return $false } }
    return $true
}

function Test-BootstrapReservedWindowsSegment {
    param([Parameter(Mandatory)][string] $Segment)
    $stem = $Segment.Split('.')[0]
    return $script:ReservedWindowsBasenames.Contains($stem)
}

function Assert-BootstrapWindowsSegment {
    param([Parameter(Mandatory)][string] $Segment)
    if ($Segment.Length -eq 0 -or $Segment -in @('.', '..')) { Throw-BootstrapFailure INVALID_PATH 'Empty, dot, and dot-dot path segments are prohibited.' }
    foreach ($character in $Segment.ToCharArray()) {
        if ([int]$character -le 0x1F) { Throw-BootstrapFailure INVALID_PATH "A path segment contains a C0 control character: $Segment" }
    }
    if ($Segment.IndexOfAny([char[]]'<>:"/\|?*') -ge 0) { Throw-BootstrapFailure INVALID_PATH "Windows-invalid path segment: $Segment" }
    if ($Segment.EndsWith(' ', [StringComparison]::Ordinal) -or $Segment.EndsWith('.', [StringComparison]::Ordinal)) {
        Throw-BootstrapFailure INVALID_PATH "A path segment ends in a space or period: $Segment"
    }
    if (Test-BootstrapReservedWindowsSegment $Segment) { Throw-BootstrapFailure INVALID_PATH "Reserved Windows device segment: $Segment" }
}

function Assert-BootstrapDestinationPath {
    param([Parameter(Mandatory)][string] $Value)
    Assert-BootstrapCommonValue DestinationPath $Value
    if ($Value.Contains('/')) { Throw-BootstrapFailure INVALID_PATH 'DestinationPath must use backslash separators.' }
    if ($Value.StartsWith('\\?\', [StringComparison]::Ordinal) -or $Value.StartsWith('\\.\', [StringComparison]::Ordinal)) {
        Throw-BootstrapFailure INVALID_PATH 'Device namespace paths are prohibited.'
    }
    $segments = @()
    if ($Value -cmatch '^[A-Z]:\\') {
        if ($Value -cmatch '^[A-Z]:\\$') { Throw-BootstrapFailure INVALID_PATH 'A filesystem root is prohibited.' }
        $segments = @($Value.Substring(3).Split('\'))
    }
    elseif ($Value.StartsWith('\\', [StringComparison]::Ordinal)) {
        $parts = @($Value.Substring(2).Split('\'))
        if ($parts.Count -lt 3 -or $parts[0].Length -eq 0 -or $parts[1].Length -eq 0 -or $parts[2].Length -eq 0) {
            Throw-BootstrapFailure INVALID_PATH 'A UNC path requires server, share, and leaf components.'
        }
        $segments = $parts
    }
    else { Throw-BootstrapFailure INVALID_PATH 'DestinationPath is not a canonical absolute Windows path.' }
    if ($Value.EndsWith('\', [StringComparison]::Ordinal)) { Throw-BootstrapFailure INVALID_PATH 'A trailing separator is prohibited.' }
    foreach ($segment in $segments) { Assert-BootstrapWindowsSegment $segment }
    try { $fullPath = [IO.Path]::GetFullPath($Value) }
    catch { Throw-BootstrapFailure INVALID_PATH 'DestinationPath cannot be interpreted as an absolute canonical path.' }
    if ($fullPath -cne $Value) { Throw-BootstrapFailure INVALID_PATH 'DestinationPath differs from Path.GetFullPath(DestinationPath).' }
}

function Assert-BootstrapInvocationValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $DestinationPath,
        [Parameter(Mandatory)][string] $ProjectId,
        [Parameter(Mandatory)][string] $ProductName,
        [Parameter(Mandatory)][string] $CompanyName,
        [Parameter(Mandatory)][string] $ApplicationIdentifier,
        [Parameter(Mandatory)][string] $CodeNamespaceRoot
    )
    Assert-BootstrapDestinationPath $DestinationPath
    foreach ($pair in @(@('ProjectId',$ProjectId), @('ProductName',$ProductName), @('CompanyName',$CompanyName), @('ApplicationIdentifier',$ApplicationIdentifier), @('CodeNamespaceRoot',$CodeNamespaceRoot))) {
        Assert-BootstrapCommonValue $pair[0] $pair[1]
    }
    if ($ProjectId.Length -gt 63 -or -not (Test-BootstrapAscii $ProjectId) -or $ProjectId -cnotmatch '^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$') {
        Throw-BootstrapFailure INVALID_PROJECT_ID 'ProjectId does not satisfy the canonical grammar.'
    }
    foreach ($pair in @(@('ProductName',$ProductName), @('CompanyName',$CompanyName))) {
        $count = Get-BootstrapScalarCount $pair[1]
        if ($count -lt 1 -or $count -gt 128) { Throw-BootstrapFailure INVALID_INPUT "$($pair[0]) must contain 1 through 128 Unicode scalars." }
        if (-not $pair[1].IsNormalized([Text.NormalizationForm]::FormC)) { Throw-BootstrapFailure NON_NFC "$($pair[0]) must already be NFC." }
    }
    if ($ApplicationIdentifier.Length -lt 5 -or $ApplicationIdentifier.Length -gt 255 -or -not (Test-BootstrapAscii $ApplicationIdentifier) -or
        $ApplicationIdentifier -cnotmatch '^[a-z][a-z0-9]*(?:\.[a-z][a-z0-9]*){2,}$') {
        Throw-BootstrapFailure INVALID_APPLICATION_IDENTIFIER 'ApplicationIdentifier does not satisfy the canonical grammar.'
    }
    if ($CodeNamespaceRoot.Length -gt 255 -or -not (Test-BootstrapAscii $CodeNamespaceRoot) -or
        $CodeNamespaceRoot -cnotmatch '^[A-Z][A-Za-z0-9]*(?:\.[A-Z][A-Za-z0-9]*)*$') {
        Throw-BootstrapFailure INVALID_NAMESPACE 'CodeNamespaceRoot does not satisfy the canonical grammar.'
    }
    foreach ($segment in $CodeNamespaceRoot.Split('.')) {
        if ($segment.Length -gt 64) { Throw-BootstrapFailure INVALID_NAMESPACE 'A CodeNamespaceRoot segment exceeds 64 characters.' }
        Assert-BootstrapWindowsSegment $segment
    }
    return [pscustomobject][ordered]@{
        DestinationPath=$DestinationPath; ProjectId=$ProjectId; ProductName=$ProductName; CompanyName=$CompanyName
        ApplicationIdentifier=$ApplicationIdentifier; CodeNamespaceRoot=$CodeNamespaceRoot
    }
}

function Assert-BootstrapUnicodeString {
    param([AllowEmptyString()][string] $Value)
    [void](Get-BootstrapScalarCount $Value)
}

function Assert-BootstrapRawJsonEscapes {
    param([string] $Text)
    for ($index = 0; $index -lt $Text.Length; $index++) {
        if ($Text[$index] -ne '"') { continue }
        $index++
        while ($index -lt $Text.Length -and $Text[$index] -ne '"') {
            if ($Text[$index] -ne '\') { $index++; continue }
            if ($index + 1 -ge $Text.Length) { break }
            if ($Text[$index + 1] -ne 'u') { $index += 2; continue }
            if ($index + 5 -ge $Text.Length) { break }
            $hex = $Text.Substring($index + 2, 4)
            if ($hex -cnotmatch '^[0-9A-Fa-f]{4}$') { break }
            $unit = [Convert]::ToInt32($hex, 16)
            if ($unit -ge 0xD800 -and $unit -le 0xDBFF) {
                if ($index + 11 -ge $Text.Length -or $Text.Substring($index + 6, 2) -cne '\u') { Throw-BootstrapFailure INVALID_UNICODE 'Escaped high surrogate is unpaired.' }
                $lowHex = $Text.Substring($index + 8, 4)
                if ($lowHex -cnotmatch '^[0-9A-Fa-f]{4}$') { Throw-BootstrapFailure INVALID_UNICODE 'Escaped high surrogate is unpaired.' }
                $low = [Convert]::ToInt32($lowHex, 16)
                if ($low -lt 0xDC00 -or $low -gt 0xDFFF) { Throw-BootstrapFailure INVALID_UNICODE 'Escaped high surrogate is unpaired.' }
                $index += 12; continue
            }
            if ($unit -ge 0xDC00 -and $unit -le 0xDFFF) { Throw-BootstrapFailure INVALID_UNICODE 'Escaped low surrogate is unpaired.' }
            $index += 6
        }
    }
}

function Assert-BootstrapJsonElement {
    param([Parameter(Mandatory)][Text.Json.JsonElement] $Element)
    switch ($Element.ValueKind) {
        ([Text.Json.JsonValueKind]::Object) {
            $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach ($property in $Element.EnumerateObject()) {
                Assert-BootstrapUnicodeString $property.Name
                if (-not $names.Add($property.Name)) { Throw-BootstrapFailure DUPLICATE_JSON_MEMBER "Duplicate JSON member '$($property.Name)'." }
                Assert-BootstrapJsonElement $property.Value
            }
        }
        ([Text.Json.JsonValueKind]::Array) { foreach ($item in $Element.EnumerateArray()) { Assert-BootstrapJsonElement $item } }
        ([Text.Json.JsonValueKind]::String) { Assert-BootstrapUnicodeString $Element.GetString() }
        ([Text.Json.JsonValueKind]::Number) {
            try { $number = $Element.GetDouble() } catch { Throw-BootstrapFailure UNSUPPORTED_NUMBER 'JSON number is outside binary64.' }
            if (-not [double]::IsFinite($number)) { Throw-BootstrapFailure UNSUPPORTED_NUMBER 'JSON number is outside finite binary64.' }
        }
        ([Text.Json.JsonValueKind]::True) {}
        ([Text.Json.JsonValueKind]::False) {}
        ([Text.Json.JsonValueKind]::Null) {}
        default { Throw-BootstrapFailure MALFORMED_JSON 'Unsupported JSON token.' }
    }
}

function Read-BootstrapStrictJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)][byte[]] $Bytes, [switch] $AllowBom)
    if (-not $AllowBom -and $Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        Throw-BootstrapFailure JSON_BOM 'A UTF-8 BOM is prohibited.'
    }
    try { $text = $script:Utf8.GetString($Bytes) } catch { Throw-BootstrapFailure MALFORMED_UTF8 'Input is not strict UTF-8.' }
    Assert-BootstrapRawJsonEscapes $text
    $options = [Text.Json.JsonDocumentOptions]::new()
    $options.AllowTrailingCommas = $false
    $options.CommentHandling = [Text.Json.JsonCommentHandling]::Disallow
    $options.MaxDepth = 0
    try { $document = [Text.Json.JsonDocument]::Parse([ReadOnlyMemory[byte]]::new($Bytes), $options) }
    catch { Throw-BootstrapFailure MALFORMED_JSON 'Input is not strict RFC 8259 JSON.' }
    try {
        Assert-BootstrapJsonElement $document.RootElement
        return $document.RootElement.Clone()
    }
    finally { $document.Dispose() }
}

function ConvertTo-BootstrapJcsString {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Value)
    Assert-BootstrapUnicodeString $Value
    $builder = [Text.StringBuilder]::new()
    [void]$builder.Append('"')
    for ($index = 0; $index -lt $Value.Length; $index++) {
        $character = $Value[$index]
        $code = [int]$character
        $handled = $true
        switch ($code) {
            8 { [void]$builder.Append('\b') }
            9 { [void]$builder.Append('\t') }
            10 { [void]$builder.Append('\n') }
            12 { [void]$builder.Append('\f') }
            13 { [void]$builder.Append('\r') }
            34 { [void]$builder.Append('\"') }
            92 { [void]$builder.Append('\\') }
            default { $handled = $false }
        }
        if ($handled) { continue }
        if ($code -le 0x1F) { [void]$builder.Append('\u'); [void]$builder.Append($code.ToString('x4', $script:Invariant)) }
        else { [void]$builder.Append($character) }
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function ConvertTo-BootstrapJcsNumber {
    param([double] $Value)
    if (-not [double]::IsFinite($Value)) { Throw-BootstrapFailure UNSUPPORTED_NUMBER 'JCS requires finite binary64.' }
    if ($Value -eq 0.0) { return '0' }
    $negative = $Value -lt 0
    $roundTrip = [Math]::Abs($Value).ToString('R', $script:Invariant)
    $exponentIndex = $roundTrip.IndexOfAny([char[]]@('E','e'))
    if ($exponentIndex -ge 0) {
        $mantissa = $roundTrip.Substring(0,$exponentIndex)
        $parsedExponent = [int]::Parse($roundTrip.Substring($exponentIndex + 1), [Globalization.NumberStyles]::Integer, $script:Invariant)
        $digits = $mantissa.Replace('.','')
        $decimalPosition = $parsedExponent + 1
    }
    else {
        $decimalPoint = $roundTrip.IndexOf('.')
        if ($decimalPoint -lt 0) { $decimalPoint = $roundTrip.Length }
        $withZeros = $roundTrip.Replace('.','')
        $leading = 0
        while ($leading -lt $withZeros.Length -and $withZeros[$leading] -eq '0') { $leading++ }
        $digits = $withZeros.Substring($leading)
        $decimalPosition = $decimalPoint - $leading
    }
    $digitCount = $digits.Length
    if ($digitCount -le $decimalPosition -and $decimalPosition -le 21) { $serialized = $digits + ('0' * ($decimalPosition - $digitCount)) }
    elseif ($decimalPosition -gt 0 -and $decimalPosition -le 21) { $serialized = $digits.Substring(0,$decimalPosition)+'.'+$digits.Substring($decimalPosition) }
    elseif ($decimalPosition -gt -6 -and $decimalPosition -le 0) { $serialized = '0.'+('0' * (-$decimalPosition))+$digits }
    else {
        $serialized = if ($digitCount -eq 1) { $digits } else { $digits.Substring(0,1)+'.'+$digits.Substring(1) }
        $scientificExponent = $decimalPosition - 1
        $serialized += if ($scientificExponent -ge 0) { 'e+'+$scientificExponent.ToString($script:Invariant) } else { 'e'+$scientificExponent.ToString($script:Invariant) }
    }
    return $(if ($negative) { '-'+$serialized } else { $serialized })
}

function ConvertTo-BootstrapJcsElement {
    param([Parameter(Mandatory)][Text.Json.JsonElement] $Element, [switch] $ExcludeRootContentIdentity)
    switch ($Element.ValueKind) {
        ([Text.Json.JsonValueKind]::Object) {
            $properties = [Collections.Generic.SortedDictionary[string,Text.Json.JsonElement]]::new([StringComparer]::Ordinal)
            foreach ($property in $Element.EnumerateObject()) {
                if ($ExcludeRootContentIdentity -and $property.Name -ceq 'contentIdentity') { continue }
                $properties.Add($property.Name,$property.Value)
            }
            $parts = [Collections.Generic.List[string]]::new()
            foreach ($entry in $properties.GetEnumerator()) { $parts.Add((ConvertTo-BootstrapJcsString $entry.Key)+':'+(ConvertTo-BootstrapJcsElement $entry.Value)) }
            return '{'+[string]::Join(',',$parts)+'}'
        }
        ([Text.Json.JsonValueKind]::Array) {
            $parts = [Collections.Generic.List[string]]::new()
            foreach ($item in $Element.EnumerateArray()) { $parts.Add((ConvertTo-BootstrapJcsElement $item)) }
            return '['+[string]::Join(',',$parts)+']'
        }
        ([Text.Json.JsonValueKind]::String) { return (ConvertTo-BootstrapJcsString $Element.GetString()) }
        ([Text.Json.JsonValueKind]::Number) { return (ConvertTo-BootstrapJcsNumber $Element.GetDouble()) }
        ([Text.Json.JsonValueKind]::True) { return 'true' }
        ([Text.Json.JsonValueKind]::False) { return 'false' }
        ([Text.Json.JsonValueKind]::Null) { return 'null' }
        default { Throw-BootstrapFailure MALFORMED_JSON 'Unsupported JSON token.' }
    }
}

function ConvertTo-BootstrapJcs {
    [CmdletBinding()]
    param([Parameter(Mandatory)][byte[]] $Bytes, [ValidateSet('FULL_JSON','EVAL_DEFINITION')][string] $Mode = 'FULL_JSON')
    $root = Read-BootstrapStrictJson $Bytes
    if ($Mode -eq 'EVAL_DEFINITION') {
        if ($root.ValueKind -ne [Text.Json.JsonValueKind]::Object) { Throw-BootstrapFailure INVALID_EVAL 'Eval definition root must be an object.' }
        $found = $false
        foreach ($property in $root.EnumerateObject()) {
            if ($property.Name -cne 'contentIdentity') { continue }
            $found = $true
            if ($property.Value.ValueKind -ne [Text.Json.JsonValueKind]::Object) { Throw-BootstrapFailure INVALID_EVAL 'contentIdentity must be an object.' }
            $names = @($property.Value.EnumerateObject() | ForEach-Object Name)
            if ($names.Count -ne 2 -or $names -cnotcontains 'algorithm' -or $names -cnotcontains 'value') { Throw-BootstrapFailure INVALID_EVAL 'contentIdentity must contain only algorithm and value.' }
        }
        if (-not $found) { Throw-BootstrapFailure INVALID_EVAL 'Eval definition contentIdentity is missing.' }
    }
    return (ConvertTo-BootstrapJcsElement $root -ExcludeRootContentIdentity:($Mode -eq 'EVAL_DEFINITION'))
}

function Get-BootstrapSha256Hex {
    param([Parameter(Mandatory)][byte[]] $Bytes)
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function Get-BootstrapJsonIdentity {
    [CmdletBinding()]
    param([Parameter(Mandatory)][byte[]] $Bytes, [ValidateSet('FULL_JSON','EVAL_DEFINITION')][string] $Mode = 'FULL_JSON')
    $canonical = ConvertTo-BootstrapJcs -Bytes $Bytes -Mode $Mode
    return [pscustomobject][ordered]@{ profileId=$script:JsonIdentityProfile; value=(Get-BootstrapSha256Hex $script:Utf8.GetBytes($canonical)); canonicalJson=$canonical }
}

function ConvertTo-BootstrapJsonBytes {
    param($Value)
    return $script:Utf8.GetBytes(($Value | ConvertTo-Json -Compress -Depth 100))
}

function New-BootstrapJsonStringToken {
    param([hashtable] $State, [ValidateSet('MemberName','StringValue')][string] $Kind)
    $text=$State.Text; $start=$State.Index; $index=$start+1
    $decoded=[Text.StringBuilder]::new(); $mapStart=[Collections.Generic.List[int]]::new(); $mapEnd=[Collections.Generic.List[int]]::new()
    while ($index -lt $text.Length) {
        if ($text[$index] -eq '"') { break }
        $rawStart=$index
        if ($text[$index] -eq '\') {
            if ($index+1 -ge $text.Length) { Throw-BootstrapFailure MALFORMED_JSON 'Unterminated JSON escape.' }
            $escape=$text[$index+1]
            if ($escape -eq 'u') {
                $raw=$text.Substring($index,6); $decodedPart=(('"'+$raw+'"') | ConvertFrom-Json); $index+=6
                if ($decodedPart.Length -eq 1 -and [int]$decodedPart[0] -ge 0xD800 -and [int]$decodedPart[0] -le 0xDBFF) {
                    $raw2=$text.Substring($index,6); $decodedPart=(('"'+$raw+$raw2+'"') | ConvertFrom-Json); $index+=6
                }
            }
            else { $raw=$text.Substring($index,2); $decodedPart=(('"'+$raw+'"') | ConvertFrom-Json); $index+=2 }
        }
        else { $decodedPart=[string]$text[$index]; $index++ }
        [void]$decoded.Append($decodedPart)
        foreach ($unit in $decodedPart.ToCharArray()) { $mapStart.Add($rawStart); $mapEnd.Add($index) }
    }
    if ($index -ge $text.Length) { Throw-BootstrapFailure MALFORMED_JSON 'Unterminated JSON string.' }
    $State.Index=$index+1
    return [pscustomobject]@{Kind=$Kind;Start=$start;End=$index+1;ContentStart=$start+1;ContentEnd=$index;Decoded=$decoded.ToString();MapStart=$mapStart.ToArray();MapEnd=$mapEnd.ToArray()}
}

function Skip-BootstrapJsonWhitespace { param([hashtable]$State) while($State.Index-lt$State.Text.Length -and $State.Text[$State.Index]-in @(' ',"`t","`r","`n")){$State.Index++} }

function Read-BootstrapJsonSpanNode {
    param([hashtable] $State, [Collections.Generic.List[object]] $Tokens)
    Skip-BootstrapJsonWhitespace $State
    $text=$State.Text; $start=$State.Index
    if ($text[$State.Index] -eq '{') {
        $State.Index++; $members=[Collections.Generic.List[object]]::new(); Skip-BootstrapJsonWhitespace $State
        if ($text[$State.Index] -ne '}') {
            while ($true) {
                $name=New-BootstrapJsonStringToken $State MemberName; $Tokens.Add($name); Skip-BootstrapJsonWhitespace $State
                if ($text[$State.Index] -ne ':') { Throw-BootstrapFailure MALFORMED_JSON 'Expected object colon.' }; $State.Index++
                $value=Read-BootstrapJsonSpanNode $State $Tokens
                $members.Add([pscustomobject]@{Name=$name.Decoded;NameToken=$name;Value=$value;Start=$name.Start;End=$value.End})
                Skip-BootstrapJsonWhitespace $State
                if ($text[$State.Index] -eq '}') { break }
                if ($text[$State.Index] -ne ',') { Throw-BootstrapFailure MALFORMED_JSON 'Expected object comma.' }; $State.Index++; Skip-BootstrapJsonWhitespace $State
            }
        }
        $State.Index++
        return [pscustomobject]@{Kind='Object';Start=$start;End=$State.Index;Members=$members;Items=$null;Token=$null}
    }
    if ($text[$State.Index] -eq '[') {
        $State.Index++; $items=[Collections.Generic.List[object]]::new(); Skip-BootstrapJsonWhitespace $State
        if ($text[$State.Index] -ne ']') {
            while ($true) {
                $items.Add((Read-BootstrapJsonSpanNode $State $Tokens)); Skip-BootstrapJsonWhitespace $State
                if ($text[$State.Index] -eq ']') { break }
                if ($text[$State.Index] -ne ',') { Throw-BootstrapFailure MALFORMED_JSON 'Expected array comma.' }; $State.Index++; Skip-BootstrapJsonWhitespace $State
            }
        }
        $State.Index++
        return [pscustomobject]@{Kind='Array';Start=$start;End=$State.Index;Members=$null;Items=$items;Token=$null}
    }
    if ($text[$State.Index] -eq '"') {
        $token=New-BootstrapJsonStringToken $State StringValue; $Tokens.Add($token)
        return [pscustomobject]@{Kind='String';Start=$token.Start;End=$token.End;Members=$null;Items=$null;Token=$token}
    }
    while ($State.Index -lt $text.Length -and $text[$State.Index] -notin @(',',']','}',' ',"`t","`r","`n")) { $State.Index++ }
    return [pscustomobject]@{Kind='Primitive';Start=$start;End=$State.Index;Members=$null;Items=$null;Token=$null}
}

function Get-BootstrapJsonSpanTree {
    param([byte[]] $Bytes)
    [void](Read-BootstrapStrictJson $Bytes)
    $text=$script:Utf8.GetString($Bytes); $state=@{Text=$text;Index=0}; $tokens=[Collections.Generic.List[object]]::new()
    $root=Read-BootstrapJsonSpanNode $state $tokens; Skip-BootstrapJsonWhitespace $state
    if($state.Index-ne$text.Length){Throw-BootstrapFailure MALFORMED_JSON 'Trailing JSON content.'}
    return [pscustomobject]@{Text=$text;Root=$root;Tokens=$tokens}
}

function ConvertFrom-BootstrapJsonPointerPart { param([string]$Part) return $Part.Replace('~1','/').Replace('~0','~') }

function Resolve-BootstrapJsonPointer {
    param($Root,[string]$Pointer)
    if($Pointer-ceq''){return [pscustomobject]@{Node=$Root;Parent=$null;Member=$null;Index=-1}}
    if(-not$Pointer.StartsWith('/',[StringComparison]::Ordinal)){Throw-BootstrapFailure INVALID_SELECTOR 'JSON pointer must be RFC 6901.'}
    $current=$Root;$parent=$null;$member=$null;$itemIndex=-1
    foreach($raw in $Pointer.Substring(1).Split('/')){
        $part=ConvertFrom-BootstrapJsonPointerPart $raw;$parent=$current;$member=$null;$itemIndex=-1
        if($current.Kind-ceq'Object'){
            $matches=@($current.Members|Where-Object Name -CEQ $part);if($matches.Count-ne1){Throw-BootstrapFailure SELECTOR_MISMATCH "JSON pointer member '$part' is absent or ambiguous."}
            $member=$matches[0];$current=$member.Value
        }elseif($current.Kind-ceq'Array'){
            if($part-cnotmatch '^(?:0|[1-9][0-9]*)$'){Throw-BootstrapFailure INVALID_SELECTOR 'Invalid JSON array index.'};$itemIndex=[int]$part
            if($itemIndex-ge$current.Items.Count){Throw-BootstrapFailure SELECTOR_MISMATCH 'JSON array index is absent.'};$current=$current.Items[$itemIndex]
        }else{Throw-BootstrapFailure SELECTOR_MISMATCH 'JSON pointer traverses a primitive.'}
    }
    return [pscustomobject]@{Node=$current;Parent=$parent;Member=$member;Index=$itemIndex}
}

function Convert-BootstrapCharSpanToByteSpan {
    param([string]$Text,[int]$Start,[int]$End,[byte[]]$Replacement,[string]$TransformId)
    return [pscustomobject]@{Start=$script:Utf8.GetByteCount($Text.Substring(0,$Start));End=$script:Utf8.GetByteCount($Text.Substring(0,$End));Replacement=$Replacement;TransformId=$TransformId}
}

function Invoke-BootstrapByteSpanEdits {
    param([byte[]]$Bytes,[object[]]$Edits)
    $ordered=@($Edits|Sort-Object Start,End)
    for($i=0;$i-lt$ordered.Count;$i++){
        if($ordered[$i].Start-lt0-or$ordered[$i].End-lt$ordered[$i].Start-or$ordered[$i].End-gt$Bytes.Length){Throw-BootstrapFailure INVALID_SPAN 'A transform span is outside the source.'}
        if($i-gt0-and$ordered[$i].Start-lt$ordered[$i-1].End){Throw-BootstrapFailure TRANSFORM_OVERLAP 'Transform spans overlap.'}
    }
    $stream=[IO.MemoryStream]::new()
    try{
        $cursor=0
        foreach($edit in $ordered){$stream.Write($Bytes,$cursor,$edit.Start-$cursor);$stream.Write($edit.Replacement,0,$edit.Replacement.Length);$cursor=$edit.End}
        $stream.Write($Bytes,$cursor,$Bytes.Length-$cursor);return $stream.ToArray()
    }finally{$stream.Dispose()}
}

function Get-BootstrapReplacementValue {
    param($Replacement,$Inputs,[byte[]]$CurrentBytes)
    switch($Replacement.kind){
        'CONTENT_INPUT'{return $Inputs.($Replacement.name)}
        'APPROVED_CONSTANT'{return $Replacement.value}
        'DETERMINISTIC_DERIVATION'{
            switch($Replacement.name){
                'PLAYERSETTINGS_PRODUCT_GUID_V1'{return (Get-BootstrapProductGuid -ProjectId $Inputs.ProjectId -ApplicationIdentifier $Inputs.ApplicationIdentifier)}
                'REPOSITORY_ID_MEMBER_V1'{return $Inputs.ProjectId}
                'EVAL_DEFINITION_CONTENT_IDENTITY_V1'{return (Get-BootstrapJsonIdentity -Bytes $CurrentBytes -Mode EVAL_DEFINITION).value}
                default{Throw-BootstrapFailure UNSUPPORTED_DERIVATION "Unsupported derivation $($Replacement.name)."}
            }
        }
        'REMOVE_SELECTED_SPAN'{return $null}
        default{Throw-BootstrapFailure UNSUPPORTED_REPLACEMENT "Unsupported replacement kind $($Replacement.kind)."}
    }
}

function Test-BootstrapJsonNodeEquals {
    param($Tree,$Node,$Expected)
    $nodeBytes=$script:Utf8.GetBytes($Tree.Text.Substring($Node.Start,$Node.End-$Node.Start))
    $expectedBytes=ConvertTo-BootstrapJsonBytes $Expected
    return (ConvertTo-BootstrapJcs $nodeBytes)-ceq(ConvertTo-BootstrapJcs $expectedBytes)
}

function Get-BootstrapRemovalSpan {
    param($Tree,$Parent,[int]$Index,[switch]$Member)
    $list=if($Member){$Parent.Members}else{$Parent.Items};$target=$list[$Index]
    if($list.Count-eq1){return [pscustomobject]@{Start=$target.Start;End=$target.End}}
    if($Index-lt$list.Count-1){
        $between=$Tree.Text.Substring($target.End,$list[$Index+1].Start-$target.End);$comma=$between.IndexOf(',')
        if($comma-lt0){Throw-BootstrapFailure MALFORMED_JSON 'Removal delimiter not found.'};return [pscustomobject]@{Start=$target.Start;End=$target.End+$comma+1}
    }
    $between=$Tree.Text.Substring($list[$Index-1].End,$target.Start-$list[$Index-1].End);$comma=$between.LastIndexOf(',')
    if($comma-lt0){Throw-BootstrapFailure MALFORMED_JSON 'Removal delimiter not found.'};return [pscustomobject]@{Start=$list[$Index-1].End+$comma;End=$target.End}
}

function Invoke-BootstrapJsonTransform {
    param([byte[]]$Bytes,$Transform,$Inputs)
    $tree=Get-BootstrapJsonSpanTree $Bytes;$edits=[Collections.Generic.List[object]]::new();$replacement=Get-BootstrapReplacementValue $Transform.replacement $Inputs $Bytes
    if($Transform.selectorClass-in@('JSON_POINTER_VALUE','JSON_POINTER_MEMBER','EVAL_DEFINITION_CONTENT_IDENTITY')-and$Transform.expectedMatchCount-ne1){Throw-BootstrapFailure MATCH_COUNT "$($Transform.id) pointer selectors require expectedMatchCount 1."}
    switch($Transform.selectorClass){
        {$_ -in @('JSON_STRING_VALUE_TOKEN','JSON_MEMBER_NAME_OR_STRING_VALUE_TOKEN')}{
            $matches=[Collections.Generic.List[object]]::new()
            foreach($token in $tree.Tokens){
                if($token.Kind-ceq'MemberName'-and$Transform.selectorClass-cne'JSON_MEMBER_NAME_OR_STRING_VALUE_TOKEN'){continue}
                $offset=0
                while($offset-le$token.Decoded.Length-([string]$Transform.expectedSourceValue).Length){
                    $found=$token.Decoded.IndexOf([string]$Transform.expectedSourceValue,$offset,[StringComparison]::Ordinal);if($found-lt0){break}
                    $matches.Add([pscustomobject]@{Token=$token;Index=$found});$offset=$found+([string]$Transform.expectedSourceValue).Length
                }
            }
            if($matches.Count-ne$Transform.expectedMatchCount){Throw-BootstrapFailure MATCH_COUNT "$($Transform.id) expected $($Transform.expectedMatchCount), found $($matches.Count)."}
            $escaped=(ConvertTo-BootstrapJcsString ([string]$replacement));$segment=$escaped.Substring(1,$escaped.Length-2)
            foreach($match in $matches){$start=$match.Token.MapStart[$match.Index];$end=$match.Token.MapEnd[$match.Index+([string]$Transform.expectedSourceValue).Length-1];$edits.Add((Convert-BootstrapCharSpanToByteSpan $tree.Text $start $end $script:Utf8.GetBytes($segment) $Transform.id))}
        }
        'JSON_POINTER_VALUE'{
            $resolved=Resolve-BootstrapJsonPointer $tree.Root $Transform.selector
            if(-not(Test-BootstrapJsonNodeEquals $tree $resolved.Node $Transform.expectedSourceValue)){Throw-BootstrapFailure EXPECTED_VALUE "$($Transform.id) expected value mismatch."}
            $edits.Add((Convert-BootstrapCharSpanToByteSpan $tree.Text $resolved.Node.Start $resolved.Node.End (ConvertTo-BootstrapJsonBytes $replacement) $Transform.id))
        }
        'JSON_POINTER_MEMBER'{
            $resolved=Resolve-BootstrapJsonPointer $tree.Root $Transform.selector
            if($null-eq$resolved.Member-or-not(Test-BootstrapJsonNodeEquals $tree $resolved.Node $Transform.expectedSourceValue)){Throw-BootstrapFailure EXPECTED_VALUE "$($Transform.id) expected member mismatch."}
            if($Transform.replacement.kind-ceq'REMOVE_SELECTED_SPAN'){
                $index=$resolved.Parent.Members.IndexOf($resolved.Member);$span=Get-BootstrapRemovalSpan $tree $resolved.Parent $index -Member
                $edits.Add((Convert-BootstrapCharSpanToByteSpan $tree.Text $span.Start $span.End ([byte[]]@()) $Transform.id))
            }elseif($Transform.replacement.name-ceq'REPOSITORY_ID_MEMBER_V1'){
                $edits.Add((Convert-BootstrapCharSpanToByteSpan $tree.Text $resolved.Member.NameToken.ContentStart $resolved.Member.NameToken.ContentEnd $script:Utf8.GetBytes('id') $Transform.id))
                $edits.Add((Convert-BootstrapCharSpanToByteSpan $tree.Text $resolved.Node.Start $resolved.Node.End (ConvertTo-BootstrapJsonBytes $replacement) $Transform.id))
            }else{Throw-BootstrapFailure UNSUPPORTED_REPLACEMENT 'JSON_POINTER_MEMBER supports removal or REPOSITORY_ID_MEMBER_V1.'}
        }
        'JSON_ARRAY_ITEMS_BY_EXACT_VALUE'{
            $resolved=Resolve-BootstrapJsonPointer $tree.Root $Transform.selector
            if($resolved.Node.Kind-cne'Array'){Throw-BootstrapFailure SELECTOR_MISMATCH 'Array selector did not resolve to an array.'}
            $expectedItems=if($Transform.expectedSourceValue-is[Array]){@($Transform.expectedSourceValue)}else{@($Transform.expectedSourceValue)}
            $indices=[Collections.Generic.List[int]]::new()
            for($i=0;$i-lt$resolved.Node.Items.Count;$i++){foreach($expected in $expectedItems){if(Test-BootstrapJsonNodeEquals $tree $resolved.Node.Items[$i] $expected){$indices.Add($i);break}}}
            if($indices.Count-ne$Transform.expectedMatchCount){Throw-BootstrapFailure MATCH_COUNT "$($Transform.id) expected $($Transform.expectedMatchCount), found $($indices.Count)."}
            # Merge selected item/removal-delimiter spans before byte editing so adjacent removals cannot overlap.
            $spans=@($indices|ForEach-Object{Get-BootstrapRemovalSpan $tree $resolved.Node $_})|Sort-Object Start
            $merged=[Collections.Generic.List[object]]::new()
            foreach($span in $spans){if($merged.Count-gt0-and$span.Start-le$merged[$merged.Count-1].End){$merged[$merged.Count-1].End=[Math]::Max($merged[$merged.Count-1].End,$span.End)}else{$merged.Add([pscustomobject]@{Start=$span.Start;End=$span.End})}}
            foreach($span in $merged){$edits.Add((Convert-BootstrapCharSpanToByteSpan $tree.Text $span.Start $span.End ([byte[]]@()) $Transform.id))}
        }
        'EVAL_DEFINITION_CONTENT_IDENTITY'{
            $resolved=Resolve-BootstrapJsonPointer $tree.Root $Transform.selector
            if(-not(Test-BootstrapJsonNodeEquals $tree $resolved.Node $Transform.expectedSourceValue)){Throw-BootstrapFailure EXPECTED_VALUE 'Eval source identity mismatch.'}
            $edits.Add((Convert-BootstrapCharSpanToByteSpan $tree.Text $resolved.Node.Start $resolved.Node.End (ConvertTo-BootstrapJsonBytes $replacement) $Transform.id))
        }
        default{Throw-BootstrapFailure UNSUPPORTED_SELECTOR "Unsupported JSON selector $($Transform.selectorClass)."}
    }
    $result=Invoke-BootstrapByteSpanEdits $Bytes $edits.ToArray();[void](Read-BootstrapStrictJson $result);return $result
}

function Get-BootstrapLiteralSpans {
    param([string]$Text,[string]$Token,[switch]$TokenBoundary)
    $result=[Collections.Generic.List[object]]::new();$offset=0
    while($offset-le$Text.Length-$Token.Length){$index=$Text.IndexOf($Token,$offset,[StringComparison]::Ordinal);if($index-lt0){break};$valid=$true
        if($TokenBoundary){if($index-gt0-and($Text[$index-1]-cmatch'[A-Za-z0-9_]')){$valid=$false};$after=$index+$Token.Length;if($after-lt$Text.Length-and($Text[$after]-cmatch'[A-Za-z0-9_]')){$valid=$false}}
        if($valid){$result.Add([pscustomobject]@{Start=$index;End=$index+$Token.Length})};$offset=$index+$Token.Length}
    return $result
}

function Read-BootstrapCSharpNormalString {
    param([string]$Text,[int]$Start)
    $decoded=[Text.StringBuilder]::new();$mapStart=[Collections.Generic.List[int]]::new();$mapEnd=[Collections.Generic.List[int]]::new();$index=$Start+1
    while($index-lt$Text.Length){
        if($Text[$index]-eq'"'){return [pscustomobject]@{Decoded=$decoded.ToString();MapStart=$mapStart.ToArray();MapEnd=$mapEnd.ToArray();End=$index+1}}
        if($Text[$index]-in@("`r","`n")){Throw-BootstrapFailure INVALID_CSHARP 'A normal C# string literal crosses a physical line.'}
        $rawStart=$index
        if($Text[$index]-ne'\'){$part=[string]$Text[$index];$index++}
        else{
            if($index+1-ge$Text.Length){Throw-BootstrapFailure INVALID_CSHARP 'Unterminated C# escape.'};$kind=$Text[$index+1]
            $simple=@{"'"="'";'"'='"';'\'='\';'0'=[string][char]0;'a'=[string][char]7;'b'=[string][char]8;'f'=[string][char]12;'n'="`n";'r'="`r";'t'="`t";'v'=[string][char]11}
            if($simple.ContainsKey([string]$kind)){$part=[string]$simple[[string]$kind];$index+=2}
            elseif($kind-in@('u','U')){$digits=if($kind-eq'u'){4}else{8};if($index+2+$digits-gt$Text.Length){Throw-BootstrapFailure INVALID_CSHARP 'Incomplete C# Unicode escape.'};$hex=$Text.Substring($index+2,$digits);if($hex-cnotmatch'^[0-9A-Fa-f]+$'){Throw-BootstrapFailure INVALID_CSHARP 'Invalid C# Unicode escape.'};$scalar=[Convert]::ToInt32($hex,16);try{$part=[char]::ConvertFromUtf32($scalar)}catch{Throw-BootstrapFailure INVALID_CSHARP 'Invalid C# Unicode scalar escape.'};$index+=2+$digits}
            elseif($kind-eq'x'){$hexStart=$index+2;$hexLength=0;while($hexLength-lt4-and$hexStart+$hexLength-lt$Text.Length-and$Text[$hexStart+$hexLength]-cmatch'[0-9A-Fa-f]'){$hexLength++};if($hexLength-eq0){Throw-BootstrapFailure INVALID_CSHARP 'C# hexadecimal escape has no digits.'};$part=[string][char][Convert]::ToInt32($Text.Substring($hexStart,$hexLength),16);$index=$hexStart+$hexLength}
            else{Throw-BootstrapFailure INVALID_CSHARP "Unsupported C# escape '\$kind'."}
        }
        [void]$decoded.Append($part);foreach($unit in $part.ToCharArray()){$mapStart.Add($rawStart);$mapEnd.Add($index)}
    }
    Throw-BootstrapFailure INVALID_CSHARP 'Unterminated normal C# string literal.'
}

function Get-BootstrapUnsupportedCSharpLiteral {
    param([string]$Text,[int]$Start,[string]$Target)
    $quote=$Text.IndexOf('"',$Start);if($quote-lt0-or$quote-$Start-gt3){return $null}
    $prefix=$Text.Substring($Start,$quote-$Start);$quoteCount=0;while($quote+$quoteCount-lt$Text.Length-and$Text[$quote+$quoteCount]-eq'"'){$quoteCount++}
    $isRaw=$quoteCount-ge3;$isVerbatim=$prefix.Contains('@',[StringComparison]::Ordinal);$isInterpolated=$prefix.Contains('$',[StringComparison]::Ordinal)
    if(-not$isRaw-and-not$isVerbatim-and-not$isInterpolated){return $null}
    if($isRaw){$delimiter='"'*$quoteCount;$end=$Text.IndexOf($delimiter,$quote+$quoteCount,[StringComparison]::Ordinal);if($end-lt0){Throw-BootstrapFailure INVALID_CSHARP 'Unterminated raw C# string literal.'};$end+=$quoteCount}
    elseif($isVerbatim){$index=$quote+1;while($index-lt$Text.Length){if($Text[$index]-eq'"'){if($index+1-lt$Text.Length-and$Text[$index+1]-eq'"'){$index+=2;continue};break};$index++};if($index-ge$Text.Length){Throw-BootstrapFailure INVALID_CSHARP 'Unterminated verbatim C# string literal.'};$end=$index+1}
    else{$index=$quote+1;$escaped=$false;while($index-lt$Text.Length){if(-not$escaped-and$Text[$index]-eq'"'){break};if(-not$escaped-and$Text[$index]-eq'\'){$escaped=$true}else{$escaped=$false};$index++};if($index-ge$Text.Length){Throw-BootstrapFailure INVALID_CSHARP 'Unterminated interpolated C# string literal.'};$end=$index+1}
    $raw=$Text.Substring($Start,$end-$Start)
    if($raw.Contains($Target,[StringComparison]::Ordinal)-or$raw.Contains('\',[StringComparison]::Ordinal)){Throw-BootstrapFailure UNSUPPORTED_CSHARP_LITERAL 'An unsupported C# literal contains or may encode the target.'}
    return [pscustomobject]@{End=$end}
}

function Get-BootstrapCSharpTokenSpans {
    param([string]$Text,[string]$Token)
    $result=[Collections.Generic.List[object]]::new();$i=0
    while($i-lt$Text.Length){
        if($i+1-lt$Text.Length-and$Text[$i]-eq'/'-and$Text[$i+1]-eq'/'){$end=$Text.IndexOf("`n",$i+2);$i=if($end-lt0){$Text.Length}else{$end+1};continue}
        if($i+1-lt$Text.Length-and$Text[$i]-eq'/'-and$Text[$i+1]-eq'*'){$end=$Text.IndexOf('*/',$i+2,[StringComparison]::Ordinal);if($end-lt0){Throw-BootstrapFailure INVALID_CSHARP 'Unterminated block comment.'};$i=$end+2;continue}
        if($Text[$i]-eq"'"){$i++;$escaped=$false;while($i-lt$Text.Length){if(-not$escaped-and$Text[$i]-eq"'"){$i++;break};if(-not$escaped-and$Text[$i]-eq'\'){$escaped=$true}else{$escaped=$false};$i++};continue}
        $unsupported=Get-BootstrapUnsupportedCSharpLiteral $Text $i $Token;if($null-ne$unsupported){$i=$unsupported.End;continue}
        if($Text[$i]-eq'"'){$literal=Read-BootstrapCSharpNormalString $Text $i;$offset=0;while($offset-le$literal.Decoded.Length-$Token.Length){$found=$literal.Decoded.IndexOf($Token,$offset,[StringComparison]::Ordinal);if($found-lt0){break};$result.Add([pscustomobject]@{Start=$literal.MapStart[$found];End=$literal.MapEnd[$found+$Token.Length-1]});$offset=$found+$Token.Length};$i=$literal.End;continue}
        if($Text[$i]-cmatch'[A-Za-z_]'){$start=$i;$i++;while($i-lt$Text.Length-and$Text[$i]-cmatch'[A-Za-z0-9_]'){$i++};$identifier=$Text.Substring($start,$i-$start);if($identifier-ceq$Token){$result.Add([pscustomobject]@{Start=$start;End=$i})};continue}
        $i++
    }
    return $result
}

function Get-BootstrapYamlScalar {
    param([string]$Text,[string]$Selector)
    $lines=[regex]::Matches($Text,'[^\r\n]*(?:\r\n|\n|\r|$)');$stack=@{};$matches=[Collections.Generic.List[object]]::new()
    foreach($lineMatch in $lines){$line=$lineMatch.Value.TrimEnd("`r","`n");if($line.Length-eq0-or$line.TrimStart().StartsWith('#')){continue};$match=[regex]::Match($line,'^( *)([^:#][^:]*?):(?: ?(.*))?$');if(-not$match.Success){continue}
        $indent=$match.Groups[1].Length;$key=$match.Groups[2].Value
        foreach($depth in @($stack.Keys|Where-Object{[int]$_-ge$indent})){$stack.Remove($depth)}
        $ancestors=@($stack.GetEnumerator()|Sort-Object{[int]$_.Key}|ForEach-Object Value);$path=(@($ancestors)+$key)-join'/'
        $value=$match.Groups[3].Value;$hasValue=$match.Groups[3].Success
        if($path-ceq$Selector-and$hasValue){$start=$lineMatch.Index+$match.Groups[3].Index;$matches.Add([pscustomobject]@{Start=$start;End=$start+$match.Groups[3].Length;Raw=$value})}
        if(-not$hasValue-or$value.Length-eq0){$stack[$indent]=$key}
    }
    if($matches.Count-ne1){Throw-BootstrapFailure SELECTOR_MISMATCH "Unity YAML selector '$Selector' is absent or ambiguous."};return $matches[0]
}

function ConvertFrom-BootstrapYamlScalar { param([string]$Raw) if($Raw.Length-eq0){return ''};if($Raw.StartsWith('"')-and$Raw.EndsWith('"')){return ($Raw|ConvertFrom-Json)};return $Raw }
function ConvertTo-BootstrapYamlScalar {
    param([AllowEmptyString()][string]$Value)
    if($Value.Length-eq0){return ''}
    $unsafe=$Value-cmatch '^(?:[-?:,\[\]{}#&*!|>''"%@`])' -or $Value.Contains(': ') -or $Value.Contains(' #') -or $Value.IndexOf([char]0x2028)-ge0 -or $Value.IndexOf([char]0x2029)-ge0 -or $Value -cmatch '^(?i:null|~|true|false|yes|no|on|off|[-+]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+))$'
    if(-not$unsafe){return $Value}
    $quoted=ConvertTo-BootstrapJcsString $Value
    return $quoted.Replace([string][char]0x2028,'\u2028',[StringComparison]::Ordinal).Replace([string][char]0x2029,'\u2029',[StringComparison]::Ordinal)
}

function Invoke-BootstrapNonJsonTransform {
    param([byte[]]$Bytes,$Transform,$Inputs)
    try{$text=$script:Utf8.GetString($Bytes)}catch{Throw-BootstrapFailure MALFORMED_UTF8 'Transform input is not UTF-8.'}
    $replacement=[string](Get-BootstrapReplacementValue $Transform.replacement $Inputs $Bytes);$semanticReplacement=$replacement;$spans=@()
    switch($Transform.selectorClass){
        'TEXT_UTF8_EXACT_SPAN'{$spans=@(Get-BootstrapLiteralSpans $text ([string]$Transform.expectedSourceValue))}
        'TEXT_UTF8_TOKEN'{$spans=@(Get-BootstrapLiteralSpans $text ([string]$Transform.expectedSourceValue) -TokenBoundary)}
        'CSHARP_UTF8_TOKEN'{$spans=@(Get-BootstrapCSharpTokenSpans $text ([string]$Transform.expectedSourceValue))}
        'UNITY_YAML_SCALAR'{
            $scalar=Get-BootstrapYamlScalar $text $Transform.selector
            if((ConvertFrom-BootstrapYamlScalar $scalar.Raw)-cne[string]$Transform.expectedSourceValue){Throw-BootstrapFailure EXPECTED_VALUE "$($Transform.id) expected YAML value mismatch."}
            $spans=@([pscustomobject]@{Start=$scalar.Start;End=$scalar.End});$replacement=ConvertTo-BootstrapYamlScalar $replacement
        }
        default{Throw-BootstrapFailure UNSUPPORTED_SELECTOR "Unsupported selector $($Transform.selectorClass)."}
    }
    if($spans.Count-ne$Transform.expectedMatchCount){Throw-BootstrapFailure MATCH_COUNT "$($Transform.id) expected $($Transform.expectedMatchCount), found $($spans.Count)."}
    $edits=@($spans|ForEach-Object{Convert-BootstrapCharSpanToByteSpan $text $_.Start $_.End $script:Utf8.GetBytes($replacement) $Transform.id})
    $result=Invoke-BootstrapByteSpanEdits $Bytes $edits
    if($Transform.selectorClass-ceq'UNITY_YAML_SCALAR'){$post=Get-BootstrapYamlScalar ($script:Utf8.GetString($result)) $Transform.selector;if((ConvertFrom-BootstrapYamlScalar $post.Raw)-cne$semanticReplacement){Throw-BootstrapFailure POSTCONDITION 'Unity YAML postcondition failed.'}}
    return $result
}

function Assert-BootstrapTransformPostconditions {
    param([byte[]]$Bytes,[object[]]$Transforms,$Inputs)
    $text=$script:Utf8.GetString($Bytes)
    $jsonTree=$null
    if(@($Transforms|Where-Object{$_.selectorClass.StartsWith('JSON_',[StringComparison]::Ordinal)-or$_.selectorClass-ceq'EVAL_DEFINITION_CONTENT_IDENTITY'}).Count-gt0){$jsonTree=Get-BootstrapJsonSpanTree $Bytes}
    foreach($transform in $Transforms){
        $kind=[string]$transform.postcondition.kind
        switch($kind){
            'TOKEN_ABSENT'{
                if($transform.selectorClass-in@('JSON_STRING_VALUE_TOKEN','JSON_MEMBER_NAME_OR_STRING_VALUE_TOKEN')){
                    foreach($token in $jsonTree.Tokens){if($token.Kind-ceq'MemberName'-and$transform.selectorClass-cne'JSON_MEMBER_NAME_OR_STRING_VALUE_TOKEN'){continue};if($token.Decoded.Contains([string]$transform.expectedSourceValue,[StringComparison]::Ordinal)){Throw-BootstrapFailure POSTCONDITION "$($transform.id) token remains."}}
                }elseif($transform.selectorClass-ceq'CSHARP_UTF8_TOKEN'){
                    if(@(Get-BootstrapCSharpTokenSpans $text ([string]$transform.expectedSourceValue)).Count-ne0){Throw-BootstrapFailure POSTCONDITION "$($transform.id) C# token remains."}
                }elseif(@(Get-BootstrapLiteralSpans $text ([string]$transform.expectedSourceValue) -TokenBoundary).Count-ne0){Throw-BootstrapFailure POSTCONDITION "$($transform.id) text token remains."}
            }
            'SELECTOR_EQUALS_REPLACEMENT'{
                $expected=Get-BootstrapReplacementValue $transform.replacement $Inputs $Bytes
                if($transform.selectorClass-ceq'UNITY_YAML_SCALAR'){$scalar=Get-BootstrapYamlScalar $text $transform.postcondition.selector;if((ConvertFrom-BootstrapYamlScalar $scalar.Raw)-cne[string]$expected){Throw-BootstrapFailure POSTCONDITION "$($transform.id) YAML selector differs."}}
                elseif($transform.selectorClass-in@('JSON_POINTER_VALUE','JSON_POINTER_MEMBER')){$resolved=Resolve-BootstrapJsonPointer $jsonTree.Root $transform.postcondition.selector;if(-not(Test-BootstrapJsonNodeEquals $jsonTree $resolved.Node $expected)){Throw-BootstrapFailure POSTCONDITION "$($transform.id) JSON selector differs."}}
                elseif(-not$text.Contains([string]$expected,[StringComparison]::Ordinal)){Throw-BootstrapFailure POSTCONDITION "$($transform.id) replacement span is absent."}
            }
            'SELECTOR_ABSENT'{
                $absent=$false;try{[void](Resolve-BootstrapJsonPointer $jsonTree.Root $transform.postcondition.selector)}catch{$absent=$true};if(-not$absent){Throw-BootstrapFailure POSTCONDITION "$($transform.id) selector remains."}
            }
            'SELECTED_ITEMS_ABSENT'{
                $resolved=Resolve-BootstrapJsonPointer $jsonTree.Root $transform.postcondition.selector
                foreach($item in $resolved.Node.Items){$expectedItems=if($transform.expectedSourceValue-is[Array]){@($transform.expectedSourceValue)}else{@($transform.expectedSourceValue)};foreach($expected in $expectedItems){if(Test-BootstrapJsonNodeEquals $jsonTree $item $expected){Throw-BootstrapFailure POSTCONDITION "$($transform.id) selected array item remains."}}}
            }
            'EVAL_DEFINITION_IDENTITY_VALID'{
                $resolved=Resolve-BootstrapJsonPointer $jsonTree.Root ($transform.postcondition.selector+'/value');$identity=Get-BootstrapJsonIdentity $Bytes EVAL_DEFINITION
                if(-not(Test-BootstrapJsonNodeEquals $jsonTree $resolved.Node $identity.value)){Throw-BootstrapFailure POSTCONDITION "$($transform.id) eval identity is invalid."}
            }
            default{Throw-BootstrapFailure UNSUPPORTED_POSTCONDITION "Unsupported postcondition '$kind'."}
        }
    }
}

function Invoke-BootstrapScopedTransforms {
    [CmdletBinding()]
    param([Parameter(Mandatory)][byte[]]$Bytes,[Parameter(Mandatory)][object[]]$Transforms,[Parameter(Mandatory)]$Inputs)
    foreach($transform in $Transforms){if($script:SelectorClasses-cnotcontains[string]$transform.selectorClass){Throw-BootstrapFailure UNSUPPORTED_SELECTOR "Unsupported selector class $($transform.selectorClass)."}}
    $ordered=@($Transforms|Sort-Object @{Expression={if($_.selectorClass-ceq'JSON_ARRAY_ITEMS_BY_EXACT_VALUE'){0}elseif($_.selectorClass-ceq'EVAL_DEFINITION_CONTENT_IDENTITY'){2}else{1}}},id)
    $result=$Bytes
    foreach($transform in $ordered){
        $result=if($transform.selectorClass.StartsWith('JSON_',[StringComparison]::Ordinal)-or$transform.selectorClass-ceq'EVAL_DEFINITION_CONTENT_IDENTITY'){Invoke-BootstrapJsonTransform $result $transform $Inputs}else{Invoke-BootstrapNonJsonTransform $result $transform $Inputs}
    }
    $finalText=$script:Utf8.GetString($result)
    foreach($transform in $Transforms){foreach($residual in @($transform.forbiddenResidualValues)){if($residual.Length-gt0-and$finalText.Contains($residual,[StringComparison]::Ordinal)){Throw-BootstrapFailure FORBIDDEN_RESIDUAL "$($transform.id) left forbidden residual '$residual'."}}}
    Assert-BootstrapTransformPostconditions $result $Transforms $Inputs
    return $result
}

function Get-BootstrapProductGuid {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$ProjectId,[Parameter(Mandatory)][string]$ApplicationIdentifier)
    $bytes=$script:Utf8.GetBytes("specops-bootstrap-product-guid-v1`0$ProjectId`0$ApplicationIdentifier")
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)[0..15]).ToLowerInvariant()
}

function Get-BootstrapSchemaAdapterCapability {
    if($null-ne$script:SchemaAdapterCapability){return $script:SchemaAdapterCapability}
    $available=$false;$detail='Test-Json with required Draft 2020-12 behavior is unavailable.'
    try{
        $command=Get-Command Test-Json -CommandType Cmdlet -ErrorAction Stop
        if(-not$command.Parameters.ContainsKey('Schema')){throw 'Test-Json has no in-memory Schema parameter.'}
        $draft='"$schema":"https://json-schema.org/draft/2020-12/schema",'
        $probes=@(
            [pscustomobject]@{Name='type object';Body='"type":"object"';Valid=@('{}');Invalid=@('[]')},
            [pscustomobject]@{Name='type string';Body='"type":"string"';Valid=@('"x"');Invalid=@('1')},
            [pscustomobject]@{Name='type array';Body='"type":"array"';Valid=@('[]');Invalid=@('{}')},
            [pscustomobject]@{Name='type integer';Body='"type":"integer"';Valid=@('1');Invalid=@('1.5')},
            [pscustomobject]@{Name='properties';Body='"type":"object","properties":{"x":{"const":1}}';Valid=@('{"x":1}');Invalid=@('{"x":2}')},
            [pscustomobject]@{Name='required';Body='"type":"object","required":["x"]';Valid=@('{"x":1}');Invalid=@('{}')},
            [pscustomobject]@{Name='additionalProperties';Body='"type":"object","properties":{"x":true},"additionalProperties":false';Valid=@('{"x":1}');Invalid=@('{"x":1,"y":2}')},
            [pscustomobject]@{Name='const';Body='"const":"x"';Valid=@('"x"');Invalid=@('"y"')},
            [pscustomobject]@{Name='enum';Body='"enum":["x","y"]';Valid=@('"x"');Invalid=@('"z"')},
            [pscustomobject]@{Name='pattern';Body='"type":"string","pattern":"^[a-z]+$"';Valid=@('"abc"');Invalid=@('"ABC"')},
            [pscustomobject]@{Name='minLength';Body='"type":"string","minLength":2';Valid=@('"ab"');Invalid=@('"a"')},
            [pscustomobject]@{Name='maxLength';Body='"type":"string","maxLength":2';Valid=@('"ab"');Invalid=@('"abc"')},
            [pscustomobject]@{Name='minimum';Body='"type":"integer","minimum":1';Valid=@('1');Invalid=@('0')},
            [pscustomobject]@{Name='items';Body='"type":"array","items":{"type":"string"}';Valid=@('["x"]');Invalid=@('[1]')},
            [pscustomobject]@{Name='minItems';Body='"type":"array","minItems":1';Valid=@('[1]');Invalid=@('[]')},
            [pscustomobject]@{Name='uniqueItems';Body='"type":"array","uniqueItems":true';Valid=@('[1,2]');Invalid=@('[1,1]')},
            [pscustomobject]@{Name='$defs/$ref';Body='"$defs":{"value":{"const":"x"}},"$ref":"#/$defs/value"';Valid=@('"x"');Invalid=@('"y"')},
            [pscustomobject]@{Name='oneOf';Body='"oneOf":[{"const":"x"},{"type":"string"}]';Valid=@('"y"');Invalid=@('"x"','true')},
            [pscustomobject]@{Name='allOf';Body='"allOf":[{"type":"integer"},{"minimum":1}]';Valid=@('1');Invalid=@('0')},
            [pscustomobject]@{Name='anyOf';Body='"anyOf":[{"const":"x"},{"const":"y"}]';Valid=@('"x"');Invalid=@('"z"')},
            [pscustomobject]@{Name='if/then';Body='"type":"object","if":{"required":["strict"]},"then":{"required":["value"]}';Valid=@('{}','{"strict":true,"value":1}');Invalid=@('{"strict":true}')},
            [pscustomobject]@{Name='not';Body='"not":{"const":"x"}';Valid=@('"y"');Invalid=@('"x"')}
        )
        foreach($probe in $probes){
            $probeSchema='{'+$draft+$probe.Body+'}'
            foreach($instance in $probe.Valid){if(-not(Test-Json -Json $instance -Schema $probeSchema -ErrorAction SilentlyContinue)){throw "Test-Json rejected the '$($probe.Name)' valid known-answer probe."}}
            foreach($instance in $probe.Invalid){if(Test-Json -Json $instance -Schema $probeSchema -ErrorAction SilentlyContinue){throw "Test-Json accepted the '$($probe.Name)' invalid known-answer probe."}}
        }
        $available=$true;$detail='All required Draft 2020-12 schema features passed isolated deterministic acceptance and rejection probes.'
    }catch{$detail=$_.Exception.Message}
    $script:SchemaAdapterCapability=[pscustomobject][ordered]@{Available=$available;Detail=$detail}
    return $script:SchemaAdapterCapability
}

function Test-BootstrapJsonSchemaBytes {
    param([Parameter(Mandatory)][byte[]]$InstanceBytes,[Parameter(Mandatory)][byte[]]$SchemaBytes,[string]$Subject='JSON instance')
    $capability=Get-BootstrapSchemaAdapterCapability
    if(-not$capability.Available){Throw-BootstrapFailure SCHEMA_ADAPTER_UNAVAILABLE $capability.Detail}
    $schemaRoot=Read-BootstrapStrictJson $SchemaBytes
    if($schemaRoot.ValueKind-ne[Text.Json.JsonValueKind]::Object){Throw-BootstrapFailure INVALID_SCHEMA 'Schema root must be an object.'}
    $draft=$null;foreach($property in $schemaRoot.EnumerateObject()){if($property.Name-ceq'$schema'){$draft=$property.Value.GetString();break}}
    if($draft-cne'https://json-schema.org/draft/2020-12/schema'){Throw-BootstrapFailure INVALID_SCHEMA 'Bootstrap schemas must declare Draft 2020-12 exactly.'}
    [void](Read-BootstrapStrictJson $InstanceBytes)
    $instanceText=$script:Utf8.GetString($InstanceBytes);$schemaText=$script:Utf8.GetString($SchemaBytes)
    if(-not(Test-Json -Json $instanceText -Schema $schemaText -ErrorAction SilentlyContinue)){Throw-BootstrapFailure SCHEMA_VALIDATION "$Subject does not conform to the verified schema bytes."}
    return $true
}

function Get-BootstrapSourceIdentity {
    [CmdletBinding()]param([Parameter(Mandatory)][byte[]]$ManifestBytes)
    $root=Read-BootstrapStrictJson $ManifestBytes
    $object=$script:Utf8.GetString($ManifestBytes)|ConvertFrom-Json -Depth 100
    if($null-ne$object.sourceIdentity.PSObject.Properties['digest']){$object.sourceIdentity.PSObject.Properties.Remove('digest')}
    $canonical=ConvertTo-BootstrapJcs (ConvertTo-BootstrapJsonBytes $object)
    return [pscustomobject][ordered]@{profile=$script:SourceIdentityProfile;digest=(Get-BootstrapSha256Hex $script:Utf8.GetBytes($canonical));canonicalJson=$canonical}
}

function Read-BootstrapProjectionManifest {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$ManifestPath,[Parameter(Mandatory)][string]$SchemaPath)
    $manifestBytes=[IO.File]::ReadAllBytes([IO.Path]::GetFullPath($ManifestPath));[void](Read-BootstrapStrictJson $manifestBytes)
    $manifestText=$script:Utf8.GetString($manifestBytes)
    $manifest=$manifestText|ConvertFrom-Json -Depth 100
    $schemaBytes=[IO.File]::ReadAllBytes([IO.Path]::GetFullPath($SchemaPath))
    $schemaEntries=@($manifest.bootstrapSourceMetadata|Where-Object role -CEQ 'PROJECTION_MANIFEST_SCHEMA')
    if($schemaEntries.Count-ne1){Throw-BootstrapFailure SOURCE_METADATA 'Projection manifest must bind exactly one schema metadata entry.'}
    $schemaEntry=$schemaEntries[0]
    if($schemaBytes.Length-ne$schemaEntry.byteIdentity.byteLength-or(Get-BootstrapSha256Hex $schemaBytes)-cne$schemaEntry.byteIdentity.sha256){Throw-BootstrapFailure SOURCE_METADATA 'Projection schema byte identity mismatch.'}
    [void](Test-BootstrapJsonSchemaBytes $manifestBytes $schemaBytes 'Projection manifest')
    $identity=Get-BootstrapSourceIdentity $manifestBytes
    if($manifest.sourceIdentity.profile-cne$identity.profile-or$manifest.sourceIdentity.digest-cne$identity.digest){Throw-BootstrapFailure SOURCE_IDENTITY 'Projection manifest Source Identity mismatch.'}
    return [pscustomobject][ordered]@{Manifest=$manifest;Bytes=$manifestBytes;SchemaBytes=$schemaBytes;SourceIdentity=$identity;ManifestPath=[IO.Path]::GetFullPath($ManifestPath);SchemaPath=[IO.Path]::GetFullPath($SchemaPath)}
}

function Test-BootstrapClosedSourceAccounting {
    [CmdletBinding()]param([string[]]$RepositoryPaths,[string[]]$MetadataPaths,[string[]]$AuthoredPaths,[string[]]$ImplementationSupportPaths,[string]$ImplementationSupportRoot)
    $sets=@();foreach($values in @($RepositoryPaths,$MetadataPaths,$AuthoredPaths,$ImplementationSupportPaths)){$set=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$caseSet=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase);foreach($value in $values){if(-not$set.Add($value)-or-not$caseSet.Add($value)){return $false}};$sets+=,$set}
    foreach($path in $ImplementationSupportPaths){if(-not$path.StartsWith($ImplementationSupportRoot,[StringComparison]::Ordinal)){return $false}}
    $union=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($path in @($MetadataPaths)+@($AuthoredPaths)+@($ImplementationSupportPaths)){if(-not$union.Add($path)){return $false}}
    if($union.Count-ne$sets[0].Count){return $false};foreach($path in $sets[0]){if(-not$union.Contains($path)){return $false}};return $true
}

function Assert-BootstrapRelativePath {
    param([string]$Path)
    if($Path.Length-eq0-or$Path.Contains('\')-or$Path.StartsWith('/')-or$Path-cmatch'^[A-Za-z]:'-or$Path.Contains('//')){Throw-BootstrapFailure INVALID_OUTPUT_PATH "Invalid relative path '$Path'."}
    foreach($segment in $Path.Split('/')){Assert-BootstrapWindowsSegment $segment}
}

function Get-BootstrapRegularLeafPaths {
    param([Parameter(Mandatory)][string]$SourceRoot)
    $root=[IO.Path]::GetFullPath($SourceRoot)
    if(-not[IO.Directory]::Exists($root)){Throw-BootstrapFailure SOURCE_ROOT 'Bootstrap SourceRoot is not a directory.'}
    $pending=[Collections.Generic.Stack[string]]::new();$pending.Push($root);$leaves=[Collections.Generic.List[string]]::new()
    while($pending.Count-gt0){
        $directory=$pending.Pop()
        try{$entries=[string[]][IO.Directory]::EnumerateFileSystemEntries($directory)}catch{Throw-BootstrapFailure SOURCE_ENUMERATION "Cannot enumerate '$directory'."}
        [Array]::Sort($entries,[StringComparer]::Ordinal)
        for($index=$entries.Length-1;$index-ge0;$index--){
            $full=$entries[$index];$relative=[IO.Path]::GetRelativePath($root,$full).Replace('\','/')
            try{$attributes=[IO.File]::GetAttributes($full)}catch{Throw-BootstrapFailure SOURCE_ENUMERATION "Cannot inspect '$relative'."}
            $isDirectory=($attributes-band[IO.FileAttributes]::Directory)-ne0
            if($isDirectory-and$relative-ceq'.git'){continue}
            if(($attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){Throw-BootstrapFailure UNSUPPORTED_SOURCE "Reparse source entry '$relative' is prohibited."}
            if($isDirectory){$pending.Push($full)}else{$leaves.Add($relative)}
        }
    }
    $result=[string[]]$leaves.ToArray();[Array]::Sort($result,[StringComparer]::Ordinal);return $result
}

function Assert-BootstrapRegularLeaf {
    param([string]$Root,[string]$Path)
    $full=Join-Path $Root $Path
    if(-not[IO.File]::Exists($full)){Throw-BootstrapFailure MISSING_SOURCE "Missing source leaf '$Path'."}
    $attributes=[IO.File]::GetAttributes($full)
    if(($attributes-band[IO.FileAttributes]::Directory)-ne0-or($attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){Throw-BootstrapFailure UNSUPPORTED_SOURCE "Source '$Path' is not a strict regular leaf."}
    return $full
}

function Get-VerifiedBootstrapSource {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$SourceRoot,[Parameter(Mandatory)]$ManifestRecord,[string[]]$RepositoryPaths)
    $root=[IO.Path]::GetFullPath($SourceRoot);$manifest=$ManifestRecord.Manifest;$bytes=[Collections.Generic.Dictionary[string,byte[]]]::new([StringComparer]::Ordinal);$metadataBytes=[Collections.Generic.Dictionary[string,byte[]]]::new([StringComparer]::Ordinal)
    $metadata=@($manifest.bootstrapSourceMetadata.path);$authored=@($manifest.authoredSourceInventory.sourcePath);$supportRoot=[string]$manifest.bootstrapImplementationSupport.root
    $enumerated=$null
    if($null-eq$RepositoryPaths){$enumerated=Get-BootstrapRegularLeafPaths $root;$RepositoryPaths=$enumerated}
    $support=@($RepositoryPaths|Where-Object{$_.StartsWith($supportRoot,[StringComparison]::Ordinal)})
    if(-not(Test-BootstrapClosedSourceAccounting $RepositoryPaths $metadata $authored $support $supportRoot)){Throw-BootstrapFailure CLOSED_ACCOUNTING 'Repository regular leaves do not equal the three approved categories.'}
    $caseSet=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase);foreach($path in $RepositoryPaths){if(-not$caseSet.Add($path)){Throw-BootstrapFailure CASE_DUPLICATE "Case-equivalent source path '$path'."}}
    foreach($path in $support){[void](Assert-BootstrapRegularLeaf $root $path)}
    foreach($entry in $manifest.authoredSourceInventory){
        $path=[string]$entry.sourcePath;$full=Assert-BootstrapRegularLeaf $root $path
        $fileBytes=[IO.File]::ReadAllBytes($full);if($fileBytes.Length-ne$entry.byteIdentity.byteLength){Throw-BootstrapFailure BYTE_LENGTH "Byte length mismatch for '$path'."};if((Get-BootstrapSha256Hex $fileBytes)-cne$entry.byteIdentity.sha256){Throw-BootstrapFailure BYTE_HASH "SHA-256 mismatch for '$path'."};$bytes.Add($path,$fileBytes)
    }
    $manifestMetadataPath=[string](($manifest.bootstrapSourceMetadata|Where-Object role -EQ 'PROJECTION_MANIFEST').path);$manifestSourceBytes=[IO.File]::ReadAllBytes((Assert-BootstrapRegularLeaf $root $manifestMetadataPath))
    if(-not(Test-BootstrapBytesEqual $manifestSourceBytes $ManifestRecord.Bytes)){Throw-BootstrapFailure SOURCE_METADATA 'SourceRoot projection manifest bytes differ from the verified manifest record.'};$metadataBytes.Add($manifestMetadataPath,$manifestSourceBytes)
    $schemaEntry=$manifest.bootstrapSourceMetadata|Where-Object role -EQ 'PROJECTION_MANIFEST_SCHEMA';$schemaPath=[string]$schemaEntry.path;$schemaBytes=[IO.File]::ReadAllBytes((Assert-BootstrapRegularLeaf $root $schemaPath))
    if($schemaBytes.Length-ne$schemaEntry.byteIdentity.byteLength-or(Get-BootstrapSha256Hex $schemaBytes)-cne$schemaEntry.byteIdentity.sha256-or-not(Test-BootstrapBytesEqual $schemaBytes $ManifestRecord.SchemaBytes)){Throw-BootstrapFailure SOURCE_METADATA 'Projection schema byte identity mismatch.'};$metadataBytes.Add($schemaPath,$schemaBytes)
    return [pscustomobject][ordered]@{Root=$root;ManifestRecord=$ManifestRecord;Bytes=$bytes;MetadataBytes=$metadataBytes;MetadataPaths=$metadata;AuthoredPaths=$authored;ImplementationSupportPaths=$support;RepositoryPaths=$RepositoryPaths;RegularLeafCount=$RepositoryPaths.Count;EnumerationMode=$(if($null-ne$enumerated){'FILESYSTEM'}else{'INJECTED'});SourceIdentity=$ManifestRecord.SourceIdentity.digest}
}

function Resolve-BootstrapOutputPath {
    param($Entry,$Inputs)
    if($null-ne$Entry.output.PSObject.Properties['path']){$path=[string]$Entry.output.path}else{$path=[string]$Entry.output.pathTemplate;foreach($input in $Entry.output.pathInputs){$path=$path.Replace('${'+$input+'}',[string]$Inputs.$input,[StringComparison]::Ordinal)}}
    Assert-BootstrapRelativePath $path;return $path
}

function Assert-BootstrapOutputPaths {
    param([string[]]$Paths,$Manifest)
    $ordinal=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$windows=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($path in $Paths){Assert-BootstrapRelativePath $path;if(-not$ordinal.Add($path)){Throw-BootstrapFailure OUTPUT_COLLISION "Duplicate output '$path'."};if(-not$windows.Add($path)){Throw-BootstrapFailure OUTPUT_CASE_COLLISION "Case-equivalent output '$path'."}
        foreach($prefix in $Manifest.staticInvariants.prohibitedOutputPrefixes){if($path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){Throw-BootstrapFailure PROHIBITED_OUTPUT "Prohibited output '$path'."}}
        foreach($prohibited in $Manifest.staticInvariants.prohibitedOutputPaths){if($path.Equals($prohibited,[StringComparison]::OrdinalIgnoreCase)-or$path.StartsWith($prohibited+'/',[StringComparison]::OrdinalIgnoreCase)){Throw-BootstrapFailure PROHIBITED_OUTPUT "Prohibited output '$path'."}}
    }
    foreach($left in $Paths){foreach($right in $Paths){if($left-cne$right-and$right.StartsWith($left+'/',[StringComparison]::OrdinalIgnoreCase)){Throw-BootstrapFailure OUTPUT_PREFIX_COLLISION "File/directory prefix collision '$left' and '$right'."}}}
}

function New-BootstrapProvenance {
    [CmdletBinding()]param([Parameter(Mandatory)]$Inputs,[Parameter(Mandatory)]$Manifest,[Parameter(Mandatory)][string]$ImplementationVersion,[Parameter(Mandatory)][byte[]]$ProvenanceSchemaBytes)
    $value=[ordered]@{contractVersion='1.0.0';classification='DERIVED_BOOTSTRAP_PROVENANCE';authorityStatus='NON_AUTHORITATIVE';evidenceStatus='NON_RELEASE_EVIDENCE';sourceBaseline=[ordered]@{id=[string]$Manifest.goldenBaseline.id;version=[string]$Manifest.goldenBaseline.version;sourceIdentity=[ordered]@{profile=[string]$Manifest.sourceIdentity.profile;digest=[string]$Manifest.sourceIdentity.digest}};bootstrap=[ordered]@{contractVersion=[string]$Manifest.bootstrapContractVersion;implementationVersion=$ImplementationVersion};contentInputs=[ordered]@{ProjectId=$Inputs.ProjectId;ProductName=$Inputs.ProductName;CompanyName=$Inputs.CompanyName;ApplicationIdentifier=$Inputs.ApplicationIdentifier;CodeNamespaceRoot=$Inputs.CodeNamespaceRoot}}
    $bytes=$script:Utf8.GetBytes((ConvertTo-BootstrapJcs (ConvertTo-BootstrapJsonBytes $value)))
    [void](Test-BootstrapJsonSchemaBytes $bytes $ProvenanceSchemaBytes 'Generated Bootstrap provenance');return $bytes
}

function New-BootstrapProspectiveOutputMap {
    [CmdletBinding()]param([Parameter(Mandatory)]$VerifiedSource,[Parameter(Mandatory)]$Inputs,[Parameter(Mandatory)][string]$ImplementationVersion)
    $manifest=$VerifiedSource.ManifestRecord.Manifest;$plans=[Collections.Generic.List[object]]::new()
    $provenanceSchemaPath='.specops/contracts/bootstrap-provenance.schema.json'
    if(-not$VerifiedSource.Bytes.ContainsKey($provenanceSchemaPath)){Throw-BootstrapFailure PROVENANCE_SCHEMA 'VerifiedSource does not contain the authored provenance schema bytes.'}
    $provenanceSchemaBytes=$VerifiedSource.Bytes[$provenanceSchemaPath]
    foreach($entry in $manifest.authoredSourceInventory){if($entry.disposition-ceq'EXCLUDE'){continue};$path=Resolve-BootstrapOutputPath $entry $Inputs;$plans.Add([pscustomobject]@{Path=$path;Disposition=$entry.disposition;SourcePath=$entry.sourcePath;Entry=$entry})}
    foreach($entry in $manifest.generatedOutputInventory){Assert-BootstrapRelativePath $entry.outputPath;$plans.Add([pscustomobject]@{Path=$entry.outputPath;Disposition=$entry.disposition;SourcePath=$null;Entry=$entry})}
    Assert-BootstrapOutputPaths @($plans.Path) $manifest
    $map=[Collections.Generic.Dictionary[string,byte[]]]::new([StringComparer]::Ordinal)
    foreach($plan in $plans|Sort-Object Path){switch($plan.Disposition){'COPY_EXACT'{$map.Add($plan.Path,$VerifiedSource.Bytes[$plan.SourcePath])};'TRANSFORM_SCOPED'{$map.Add($plan.Path,(Invoke-BootstrapScopedTransforms $VerifiedSource.Bytes[$plan.SourcePath] @($plan.Entry.transforms) $Inputs))};'GENERATE_DETERMINISTIC'{$map.Add($plan.Path,(New-BootstrapProvenance $Inputs $manifest $ImplementationVersion $provenanceSchemaBytes))};default{Throw-BootstrapFailure INVALID_DISPOSITION "Unsupported disposition $($plan.Disposition)."}}}
    return [pscustomobject][ordered]@{Bytes=$map;Plans=$plans;Count=$map.Count;Inputs=$Inputs;VerifiedSource=$VerifiedSource;ImplementationVersion=$ImplementationVersion;ProvenanceSchemaBytes=$provenanceSchemaBytes}
}

function Test-BootstrapBytesEqual {
    param([byte[]]$Left,[byte[]]$Right)
    if($null-eq$Left-or$null-eq$Right-or$Left.Length-ne$Right.Length){return $false}
    for($index=0;$index-lt$Left.Length;$index++){if($Left[$index]-ne$Right[$index]){return $false}}
    return $true
}

function Test-BootstrapByteMapStatic {
    [CmdletBinding()]param([Parameter(Mandatory)]$ProspectiveOutput)
    $findings=[Collections.Generic.List[string]]::new();$verified=$ProspectiveOutput.VerifiedSource;$manifest=$verified.ManifestRecord.Manifest
    try{$reproduced=New-BootstrapProspectiveOutputMap $verified $ProspectiveOutput.Inputs $ProspectiveOutput.ImplementationVersion}catch{$findings.Add($_.Exception.Message);return [pscustomobject]@{Pass=$false;Findings=$findings}}
    if($reproduced.Count-ne$ProspectiveOutput.Count){$findings.Add('Output path count differs from deterministic reproduction.')}
    foreach($path in $reproduced.Bytes.Keys){if(-not$ProspectiveOutput.Bytes.ContainsKey($path)-or-not(Test-BootstrapBytesEqual $reproduced.Bytes[$path] $ProspectiveOutput.Bytes[$path])){$findings.Add("Output bytes differ: $path")}}
    foreach($plan in $ProspectiveOutput.Plans|Where-Object Disposition -EQ 'COPY_EXACT'){if(-not(Test-BootstrapBytesEqual $ProspectiveOutput.Bytes[$plan.Path] $verified.Bytes[$plan.SourcePath])){$findings.Add("COPY_EXACT differs: $($plan.Path)")}}
    $plansBySource=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal);foreach($plan in $ProspectiveOutput.Plans){if($plan.SourcePath){$plansBySource[$plan.SourcePath]=$plan}}
    $metaGuids=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($plan in $ProspectiveOutput.Plans|Where-Object{$_.SourcePath-and$_.SourcePath.EndsWith('.meta')}){
        if($plan.Disposition-cne'COPY_EXACT'){$findings.Add("Retained meta is not COPY_EXACT: $($plan.Path)")}
        $metaText=$script:Utf8.GetString($ProspectiveOutput.Bytes[$plan.Path]);$guidMatches=[regex]::Matches($metaText,'(?m)^guid: ([0-9a-f]{32})\r?$')
        if($guidMatches.Count-ne1-or-not$metaGuids.Add($guidMatches[0].Groups[1].Value)){$findings.Add("Meta GUID invariant failed: $($plan.Path)")}
        $assetSource=$plan.SourcePath.Substring(0,$plan.SourcePath.Length-5);$assetOutput=$plan.Path.Substring(0,$plan.Path.Length-5)
        if($verified.Bytes.ContainsKey($assetSource)){if(-not$plansBySource.ContainsKey($assetSource)-or$plansBySource[$assetSource].Path-cne$assetOutput){$findings.Add("Asset/meta adjacency invariant failed: $($plan.Path)")}}
        elseif(@($ProspectiveOutput.Bytes.Keys|Where-Object{$_.StartsWith($assetOutput+'/',[StringComparison]::Ordinal)}).Count-eq0){$findings.Add("Directory meta has no retained descendants: $($plan.Path)")}
    }
    foreach($plan in $ProspectiveOutput.Plans|Where-Object{$_.SourcePath-and$_.SourcePath.StartsWith('Assets/',[StringComparison]::Ordinal)-and-not$_.SourcePath.EndsWith('.meta')}){if(-not$plansBySource.ContainsKey($plan.SourcePath+'.meta')){$findings.Add("Retained Unity asset lacks meta: $($plan.Path)")}}
    $projectVersion=$script:Utf8.GetString($ProspectiveOutput.Bytes['ProjectSettings/ProjectVersion.txt']);if($projectVersion-cne"m_EditorVersion: $($manifest.staticInvariants.projectVersion)`nm_EditorVersionWithRevision: $($manifest.staticInvariants.projectVersion) ($($manifest.staticInvariants.projectRevision))`n"){$findings.Add('ProjectVersion invariant failed.')}
    $player=$script:Utf8.GetString($ProspectiveOutput.Bytes['ProjectSettings/ProjectSettings.asset']);if([regex]::Matches($player,'(?m)^  runInBackground: 1\r?$').Count-ne1){$findings.Add('runInBackground invariant failed.')}
    try{$package=$script:Utf8.GetString($ProspectiveOutput.Bytes['Packages/manifest.json'])|ConvertFrom-Json -Depth 100;$lock=$script:Utf8.GetString($ProspectiveOutput.Bytes['Packages/packages-lock.json'])|ConvertFrom-Json -Depth 100;$direct=@($package.dependencies.PSObject.Properties.Name|Sort-Object);$zero=@($lock.dependencies.PSObject.Properties|Where-Object{$_.Value.depth-eq0}|ForEach-Object Name|Sort-Object);if(($direct-join"`0")-cne($zero-join"`0")){$findings.Add('Package direct/depth-zero set invariant failed.')}else{foreach($name in $direct){if([string]$package.dependencies.$name-cne[string]$lock.dependencies.$name.version){$findings.Add("Package version invariant failed: $name")}}}}catch{$findings.Add('Package static validation failed.')}
    return [pscustomobject][ordered]@{Pass=($findings.Count-eq0);Findings=@($findings);OutputCount=$ProspectiveOutput.Count;UnityExecuted=$false}
}

function Initialize-BootstrapWindowsNative {
    if ('SpecOpsBootstrapNative.NativeMethods' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
using System.Text;

namespace SpecOpsBootstrapNative {
    [StructLayout(LayoutKind.Sequential)]
    public struct BY_HANDLE_FILE_INFORMATION {
        public uint FileAttributes;
        public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastAccessTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWriteTime;
        public uint VolumeSerialNumber;
        public uint FileSizeHigh;
        public uint FileSizeLow;
        public uint NumberOfLinks;
        public uint FileIndexHigh;
        public uint FileIndexLow;
    }

    public static class NativeMethods {
        public const uint FILE_SHARE_READ = 0x00000001;
        public const uint FILE_SHARE_WRITE = 0x00000002;
        public const uint FILE_SHARE_DELETE = 0x00000004;
        public const uint DELETE = 0x00010000;
        public const uint OPEN_EXISTING = 3;
        public const uint FILE_FLAG_BACKUP_SEMANTICS = 0x02000000;
        public const uint FILE_FLAG_OPEN_REPARSE_POINT = 0x00200000;
        public const uint FILE_TYPE_DISK = 0x0001;

        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        public static extern SafeFileHandle CreateFileW(
            string name, uint access, uint share, IntPtr security,
            uint creation, uint flags, IntPtr template);

        [DllImport("kernel32.dll", SetLastError=true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GetFileInformationByHandle(
            SafeFileHandle handle, out BY_HANDLE_FILE_INFORMATION information);

        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        public static extern uint GetFinalPathNameByHandleW(
            SafeFileHandle handle, StringBuilder path, uint length, uint flags);

        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool CreateDirectoryW(string path, IntPtr security);

        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GetVolumeInformationByHandleW(
            SafeFileHandle handle, StringBuilder volumeName, uint volumeNameSize,
            out uint volumeSerialNumber, out uint maximumComponentLength,
            out uint fileSystemFlags, StringBuilder fileSystemName, uint fileSystemNameSize);

        [DllImport("kernel32.dll", SetLastError=true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetFileInformationByHandle(
            SafeFileHandle handle, int informationClass, IntPtr information, uint bufferSize);

        public static bool RenameAbsoluteNoReplace(
            SafeFileHandle source, string destinationPath, out int errorCode) {
            byte[] nameBytes = Encoding.Unicode.GetBytes(destinationPath);
            int rootOffset = IntPtr.Size == 8 ? 8 : 4;
            int lengthOffset = rootOffset + IntPtr.Size;
            int nameOffset = lengthOffset + 4;
            int bufferSize = nameOffset + nameBytes.Length + 2;
            IntPtr buffer = Marshal.AllocHGlobal(bufferSize);
            try {
                for (int index = 0; index < bufferSize; index++) { Marshal.WriteByte(buffer, index, 0); }
                Marshal.WriteByte(buffer, 0, 0);
                Marshal.WriteIntPtr(buffer, rootOffset, IntPtr.Zero);
                Marshal.WriteInt32(buffer, lengthOffset, nameBytes.Length);
                Marshal.Copy(nameBytes, 0, IntPtr.Add(buffer, nameOffset), nameBytes.Length);
                bool result = SetFileInformationByHandle(source, 3, buffer, (uint)bufferSize);
                errorCode = result ? 0 : Marshal.GetLastWin32Error();
                return result;
            }
            finally { Marshal.FreeHGlobal(buffer); }
        }

        [DllImport("kernel32.dll", SetLastError=true)]
        public static extern uint GetFileType(SafeFileHandle handle);
    }
}
'@
}

function Throw-BootstrapExecutionFailure {
    param([Parameter(Mandatory)][string]$Class,[Parameter(Mandatory)][string]$Message)
    $exception=[IO.InvalidDataException]::new("$Class`: $Message")
    $exception.Data['BootstrapExecutionFailureClass']=$Class
    throw $exception
}

function Invoke-BootstrapExecutionFault {
    param([Parameter(Mandatory)][string]$Name,$Context)
    if($script:ExecutionFaults.ContainsKey($Name)) { & $script:ExecutionFaults[$Name] $Context }
}

function Get-BootstrapWin32Message {
    param([int]$ErrorCode)
    return [ComponentModel.Win32Exception]::new($ErrorCode).Message
}

function Get-BootstrapHandleIdentity {
    param([Parameter(Mandatory)]$Handle)
    Initialize-BootstrapWindowsNative
    $information=[SpecOpsBootstrapNative.BY_HANDLE_FILE_INFORMATION]::new()
    if(-not[SpecOpsBootstrapNative.NativeMethods]::GetFileInformationByHandle($Handle,[ref]$information)) {
        $errorCode=[Runtime.InteropServices.Marshal]::GetLastWin32Error()
        Throw-BootstrapExecutionFailure FILE_IDENTITY "GetFileInformationByHandle failed: $(Get-BootstrapWin32Message $errorCode)"
    }
    $index=([uint64]$information.FileIndexHigh-shl32)-bor[uint64]$information.FileIndexLow
    return [pscustomobject][ordered]@{
        VolumeSerial=[uint32]$information.VolumeSerialNumber
        FileIndex=$index
        Length=(([uint64]$information.FileSizeHigh-shl32)-bor[uint64]$information.FileSizeLow)
        Attributes=[IO.FileAttributes]$information.FileAttributes
        Key=('{0:x8}:{1:x16}' -f $information.VolumeSerialNumber,$index)
    }
}

function Test-BootstrapIdentityEqual {
    param($Left,$Right)
    return $null-ne$Left-and$null-ne$Right-and$Left.VolumeSerial-eq$Right.VolumeSerial-and$Left.FileIndex-eq$Right.FileIndex
}

function Open-BootstrapDirectoryHandle {
    param([Parameter(Mandatory)][string]$Path,[switch]$AllowDeleteShare,[switch]$DeleteAccess)
    Initialize-BootstrapWindowsNative
    $share=[SpecOpsBootstrapNative.NativeMethods]::FILE_SHARE_READ-bor[SpecOpsBootstrapNative.NativeMethods]::FILE_SHARE_WRITE
    if($AllowDeleteShare){$share=$share-bor[SpecOpsBootstrapNative.NativeMethods]::FILE_SHARE_DELETE}
    $flags=[SpecOpsBootstrapNative.NativeMethods]::FILE_FLAG_BACKUP_SEMANTICS-bor[SpecOpsBootstrapNative.NativeMethods]::FILE_FLAG_OPEN_REPARSE_POINT
    $access=if($DeleteAccess){[SpecOpsBootstrapNative.NativeMethods]::DELETE}else{0}
    $handle=[SpecOpsBootstrapNative.NativeMethods]::CreateFileW($Path,$access,$share,[IntPtr]::Zero,[SpecOpsBootstrapNative.NativeMethods]::OPEN_EXISTING,$flags,[IntPtr]::Zero)
    if($handle.IsInvalid){
        $errorCode=[Runtime.InteropServices.Marshal]::GetLastWin32Error();$handle.Dispose()
        Throw-BootstrapExecutionFailure DIRECTORY_HANDLE "Cannot open directory '$Path': $(Get-BootstrapWin32Message $errorCode)"
    }
    try {
        $identity=Get-BootstrapHandleIdentity $handle
        if(($identity.Attributes-band[IO.FileAttributes]::Directory)-eq0-or($identity.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){
            Throw-BootstrapExecutionFailure UNSAFE_DIRECTORY "Path is not a real non-reparse directory: $Path"
        }
        return [pscustomobject][ordered]@{Handle=$handle;Identity=$identity;Path=[IO.Path]::GetFullPath($Path)}
    } catch { $handle.Dispose();throw }
}

function Get-BootstrapFinalHandlePath {
    param([Parameter(Mandatory)]$Handle)
    Initialize-BootstrapWindowsNative
    $capacity=512
    while($true){
        $builder=[Text.StringBuilder]::new($capacity)
        $length=[SpecOpsBootstrapNative.NativeMethods]::GetFinalPathNameByHandleW($Handle,$builder,$capacity,0)
        if($length-eq0){$errorCode=[Runtime.InteropServices.Marshal]::GetLastWin32Error();Throw-BootstrapExecutionFailure PHYSICAL_PATH "GetFinalPathNameByHandle failed: $(Get-BootstrapWin32Message $errorCode)"}
        if($length-lt$capacity){$path=$builder.ToString();break}
        $capacity=[int]$length+1
    }
    if($path.StartsWith('\\?\UNC\',[StringComparison]::OrdinalIgnoreCase)){return '\\'+$path.Substring(8)}
    if($path.StartsWith('\\?\',[StringComparison]::OrdinalIgnoreCase)){return $path.Substring(4)}
    return $path
}

function Get-BootstrapHandleVolumeInformation {
    param([Parameter(Mandatory)]$Handle)
    Initialize-BootstrapWindowsNative
    $volumeName=[Text.StringBuilder]::new(261);$fileSystemName=[Text.StringBuilder]::new(261)
    [uint32]$serial=0;[uint32]$maximumComponentLength=0;[uint32]$flags=0
    if(-not[SpecOpsBootstrapNative.NativeMethods]::GetVolumeInformationByHandleW($Handle,$volumeName,$volumeName.Capacity,[ref]$serial,[ref]$maximumComponentLength,[ref]$flags,$fileSystemName,$fileSystemName.Capacity)){
        $errorCode=[Runtime.InteropServices.Marshal]::GetLastWin32Error();Throw-BootstrapExecutionFailure VOLUME_INFORMATION "GetVolumeInformationByHandleW failed: $(Get-BootstrapWin32Message $errorCode)"
    }
    if($maximumComponentLength-lt1){Throw-BootstrapExecutionFailure VOLUME_INFORMATION 'The destination volume reported no usable maximum component length.'}
    return [pscustomobject][ordered]@{VolumeSerial=$serial;MaximumComponentLength=$maximumComponentLength;FileSystemName=$fileSystemName.ToString();Flags=$flags}
}

function Assert-BootstrapVolumeComponentRepresentable {
    param([Parameter(Mandatory)][string]$Component,[Parameter(Mandatory)][uint32]$MaximumComponentLength)
    if($MaximumComponentLength-lt1-or$Component.Length-gt$MaximumComponentLength){Throw-BootstrapExecutionFailure DESTINATION_REPRESENTATION "A destination component exceeds the verified volume limit of $MaximumComponentLength UTF-16 code units."}
}

function Assert-BootstrapPathChainNoReparse {
    param([Parameter(Mandatory)][string]$Path,[switch]$IncludeLeaf)
    $full=[IO.Path]::GetFullPath($Path)
    $root=[IO.Path]::GetPathRoot($full)
    if([string]::IsNullOrEmpty($root)){Throw-BootstrapExecutionFailure UNSAFE_PATH 'Path has no filesystem root.'}
    $remainder=$full.Substring($root.Length).TrimEnd('\')
    $current=$root.TrimEnd('\')
    if($current.Length-eq2){$current+='\'}
    $parts=if($remainder.Length){@($remainder.Split('\'))}else{@()}
    $limit=if($IncludeLeaf){$parts.Count}else{[Math]::Max(0,$parts.Count-1)}
    for($index=0;$index-lt$limit;$index++){
        $current=[IO.Path]::Combine($current,$parts[$index])
        try{$attributes=[IO.File]::GetAttributes($current)}catch{Throw-BootstrapExecutionFailure UNSAFE_PATH "Cannot inspect path component '$current'."}
        if(($attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){Throw-BootstrapExecutionFailure REPARSE_TRAVERSAL "Reparse traversal is prohibited: $current"}
    }
}

function Resolve-BootstrapImplementationSource {
    param([Parameter(Mandatory)][string]$ImplementationScriptPath)
    if(-not[OperatingSystem]::IsWindows()-or$PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7-or-not[Environment]::Is64BitProcess){
        Throw-BootstrapExecutionFailure UNSUPPORTED_PLATFORM 'Bootstrap requires 64-bit PowerShell 7 or later on Windows.'
    }
    $scriptPath=[IO.Path]::GetFullPath($ImplementationScriptPath)
    Assert-BootstrapPathChainNoReparse $scriptPath -IncludeLeaf
    try{$stream=[IO.FileStream]::new($scriptPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)}catch{Throw-BootstrapExecutionFailure SOURCE_LOCATOR "Cannot retain the implementation entry point: $($_.Exception.Message)"}
    try{$physical=Get-BootstrapFinalHandlePath $stream.SafeFileHandle}finally{$stream.Dispose()}
    if(-not$physical.Equals($scriptPath,[StringComparison]::OrdinalIgnoreCase)){Throw-BootstrapExecutionFailure SOURCE_LOCATOR 'Implementation path does not resolve to its own physical spelling.'}
    $implementationRoot=[IO.DirectoryInfo]::new([IO.Path]::GetDirectoryName($physical))
    $source=$implementationRoot
    for($index=0;$index-lt3;$index++){if($null-eq$source.Parent){Throw-BootstrapExecutionFailure SOURCE_LOCATOR 'Implementation root does not have three physical parents.'};$source=$source.Parent}
    $sourceRoot=$source.FullName
    Assert-BootstrapPathChainNoReparse $sourceRoot -IncludeLeaf
    return [pscustomobject][ordered]@{
        ImplementationRoot=$implementationRoot.FullName
        SourceRoot=$sourceRoot
        ManifestPath=[IO.Path]::Combine($sourceRoot,'.specops','bootstrap','bootstrap-v1.projection-manifest.json')
        SchemaPath=[IO.Path]::Combine($sourceRoot,'.specops','contracts','bootstrap-projection-manifest.schema.json')
        ImplementationDescriptorPath=[IO.Path]::Combine($sourceRoot,'tools','specops','bootstrap','bootstrap-implementation.json')
    }
}

function Read-BootstrapRetainedBytes {
    param([Parameter(Mandatory)][IO.FileStream]$Stream)
    $Stream.Position=0
    if($Stream.Length-gt[int]::MaxValue){Throw-BootstrapExecutionFailure SOURCE_LENGTH 'A source leaf exceeds the supported in-memory size.'}
    $bytes=[byte[]]::new([int]$Stream.Length)
    $offset=0
    while($offset-lt$bytes.Length){$read=$Stream.Read($bytes,$offset,$bytes.Length-$offset);if($read-eq0){Throw-BootstrapExecutionFailure SOURCE_READ 'Unexpected end of retained source handle.'};$offset+=$read}
    return ,$bytes
}

function New-BootstrapManifestRecordFromBytes {
    param([byte[]]$ManifestBytes,[byte[]]$SchemaBytes,[string]$ManifestPath,[string]$SchemaPath)
    [void](Read-BootstrapStrictJson $ManifestBytes)
    $manifest=$script:Utf8.GetString($ManifestBytes)|ConvertFrom-Json -Depth 100
    $schemaEntries=@($manifest.bootstrapSourceMetadata|Where-Object role -CEQ 'PROJECTION_MANIFEST_SCHEMA')
    if($schemaEntries.Count-ne1){Throw-BootstrapFailure SOURCE_METADATA 'Projection manifest must bind exactly one schema metadata entry.'}
    $schemaEntry=$schemaEntries[0]
    if($SchemaBytes.Length-ne$schemaEntry.byteIdentity.byteLength-or(Get-BootstrapSha256Hex $SchemaBytes)-cne$schemaEntry.byteIdentity.sha256){Throw-BootstrapFailure SOURCE_METADATA 'Projection schema byte identity mismatch.'}
    [void](Test-BootstrapJsonSchemaBytes $ManifestBytes $SchemaBytes 'Projection manifest')
    $identity=Get-BootstrapSourceIdentity $ManifestBytes
    if($manifest.sourceIdentity.profile-cne$identity.profile-or$manifest.sourceIdentity.digest-cne$identity.digest){Throw-BootstrapFailure SOURCE_IDENTITY 'Projection manifest Source Identity mismatch.'}
    return [pscustomobject][ordered]@{Manifest=$manifest;Bytes=$ManifestBytes;SchemaBytes=$SchemaBytes;SourceIdentity=$identity;ManifestPath=$ManifestPath;SchemaPath=$SchemaPath}
}

function Open-BootstrapImmutableSource {
    param([Parameter(Mandatory)]$Locator)
    $root=$Locator.SourceRoot
    $rootRecord=Open-BootstrapDirectoryHandle $root
    try{$physicalRoot=Get-BootstrapFinalHandlePath $rootRecord.Handle;if(-not$physicalRoot.Equals([IO.Path]::GetFullPath($root),[StringComparison]::OrdinalIgnoreCase)){Throw-BootstrapExecutionFailure SOURCE_ALIAS 'SourceRoot physical path is ambiguous or aliased.'}}catch{$rootRecord.Handle.Dispose();throw}
    try{$paths=Get-BootstrapRegularLeafPaths $root}catch{$rootRecord.Handle.Dispose();throw}
    $handles=[Collections.Generic.Dictionary[string,IO.FileStream]]::new([StringComparer]::Ordinal)
    $allBytes=[Collections.Generic.Dictionary[string,byte[]]]::new([StringComparer]::Ordinal)
    $identities=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    try {
        foreach($path in $paths){
            $full=Assert-BootstrapRegularLeaf $root $path
            try{$stream=[IO.FileStream]::new($full,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)}catch{Throw-BootstrapExecutionFailure SOURCE_SHARING "Cannot retain source '$path' with write/delete sharing denied: $($_.Exception.Message)"}
            try{
                $before=Get-BootstrapHandleIdentity $stream.SafeFileHandle
                if(($before.Attributes-band[IO.FileAttributes]::Directory)-ne0-or($before.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){Throw-BootstrapExecutionFailure UNSUPPORTED_SOURCE "Source '$path' is not a regular non-reparse file."}
                if([SpecOpsBootstrapNative.NativeMethods]::GetFileType($stream.SafeFileHandle)-ne[SpecOpsBootstrapNative.NativeMethods]::FILE_TYPE_DISK){Throw-BootstrapExecutionFailure UNSUPPORTED_SOURCE "Source '$path' is not a disk file."}
                $bytes=Read-BootstrapRetainedBytes $stream
                $after=Get-BootstrapHandleIdentity $stream.SafeFileHandle
                if(-not(Test-BootstrapIdentityEqual $before $after)-or$after.Length-ne[uint64]$bytes.Length){Throw-BootstrapExecutionFailure SOURCE_MUTATION "Source identity or length changed while reading '$path'."}
                $handles.Add($path,$stream);$stream=$null;$allBytes.Add($path,$bytes);$identities.Add($path,$after)
            }finally{if($null-ne$stream){$stream.Dispose()}}
        }
        $manifestRelative='.specops/bootstrap/bootstrap-v1.projection-manifest.json'
        $schemaRelative='.specops/contracts/bootstrap-projection-manifest.schema.json'
        if(-not$allBytes.ContainsKey($manifestRelative)-or-not$allBytes.ContainsKey($schemaRelative)){Throw-BootstrapExecutionFailure SOURCE_METADATA 'Fixed Bootstrap metadata paths are absent.'}
        $record=New-BootstrapManifestRecordFromBytes $allBytes[$manifestRelative] $allBytes[$schemaRelative] $Locator.ManifestPath $Locator.SchemaPath
        $manifest=$record.Manifest;$metadata=@($manifest.bootstrapSourceMetadata.path);$authored=@($manifest.authoredSourceInventory.sourcePath);$supportRoot=[string]$manifest.bootstrapImplementationSupport.root
        $support=@($paths|Where-Object{$_.StartsWith($supportRoot,[StringComparison]::Ordinal)})
        if(-not(Test-BootstrapClosedSourceAccounting $paths $metadata $authored $support $supportRoot)){Throw-BootstrapFailure CLOSED_ACCOUNTING 'Repository regular leaves do not equal the three approved categories.'}
        $caseSet=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase);foreach($path in $paths){if(-not$caseSet.Add($path)){Throw-BootstrapFailure CASE_DUPLICATE "Case-equivalent source path '$path'."}}
        $authoredBytes=[Collections.Generic.Dictionary[string,byte[]]]::new([StringComparer]::Ordinal)
        foreach($entry in $manifest.authoredSourceInventory){$path=[string]$entry.sourcePath;if(-not$allBytes.ContainsKey($path)){Throw-BootstrapFailure MISSING_SOURCE "Missing source leaf '$path'."};$bytes=$allBytes[$path];if($bytes.Length-ne$entry.byteIdentity.byteLength){Throw-BootstrapFailure BYTE_LENGTH "Byte length mismatch for '$path'."};if((Get-BootstrapSha256Hex $bytes)-cne$entry.byteIdentity.sha256){Throw-BootstrapFailure BYTE_HASH "SHA-256 mismatch for '$path'."};$authoredBytes.Add($path,$bytes)}
        $metadataBytes=[Collections.Generic.Dictionary[string,byte[]]]::new([StringComparer]::Ordinal);foreach($path in $metadata){$metadataBytes.Add($path,$allBytes[$path])}
        $descriptorRelative='tools/specops/bootstrap/bootstrap-implementation.json'
        if(-not$allBytes.ContainsKey($descriptorRelative)){Throw-BootstrapExecutionFailure IMPLEMENTATION_DESCRIPTOR 'Bootstrap implementation descriptor is absent.'}
        $descriptor=Read-BootstrapStrictJson $allBytes[$descriptorRelative]
        $implementationVersion=$null;foreach($property in $descriptor.EnumerateObject()){if($property.Name-ceq'implementationVersion'){$implementationVersion=$property.Value.GetString()}}
        if($implementationVersion-cne'1.0.0'){Throw-BootstrapExecutionFailure IMPLEMENTATION_VERSION 'Bootstrap Implementation Version must remain 1.0.0.'}
        return [pscustomobject][ordered]@{Root=$root;PhysicalRootPath=$physicalRoot;RootHandle=$rootRecord.Handle;RootIdentity=$rootRecord.Identity;ManifestRecord=$record;Bytes=$authoredBytes;MetadataBytes=$metadataBytes;MetadataPaths=$metadata;AuthoredPaths=$authored;ImplementationSupportPaths=$support;RepositoryPaths=$paths;RegularLeafCount=$paths.Count;EnumerationMode='FILESYSTEM';SourceIdentity=$record.SourceIdentity.digest;Handles=$handles;AllIdentities=$identities;ImplementationVersion=$implementationVersion}
    }catch{foreach($stream in $handles.Values){$stream.Dispose()};$rootRecord.Handle.Dispose();throw}
}

function Close-BootstrapImmutableSource {
    param($VerifiedSource)
    if($null-ne$VerifiedSource-and$null-ne$VerifiedSource.Handles){foreach($stream in $VerifiedSource.Handles.Values){$stream.Dispose()}}
    if($null-ne$VerifiedSource-and$null-ne$VerifiedSource.RootHandle-and-not$VerifiedSource.RootHandle.IsClosed){$VerifiedSource.RootHandle.Dispose()}
}

function Assert-BootstrapSourceConsistency {
    param([Parameter(Mandatory)]$VerifiedSource)
    $current=Get-BootstrapRegularLeafPaths $VerifiedSource.Root
    if($current.Count-ne$VerifiedSource.RepositoryPaths.Count){Throw-BootstrapExecutionFailure SOURCE_MUTATION 'The closed source leaf count changed during invocation.'}
    for($index=0;$index-lt$current.Count;$index++){if($current[$index]-cne$VerifiedSource.RepositoryPaths[$index]){Throw-BootstrapExecutionFailure SOURCE_MUTATION 'The closed source path set changed during invocation.'}}
    foreach($path in $current){
        $full=[IO.Path]::Combine($VerifiedSource.Root,$path.Replace('/',[IO.Path]::DirectorySeparatorChar))
        try{$stream=[IO.FileStream]::new($full,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)}catch{Throw-BootstrapExecutionFailure SOURCE_MUTATION "Cannot reopen retained source '$path' consistently."}
        try{$identity=Get-BootstrapHandleIdentity $stream.SafeFileHandle;if(-not(Test-BootstrapIdentityEqual $identity $VerifiedSource.AllIdentities[$path])-or$identity.Length-ne$VerifiedSource.AllIdentities[$path].Length){Throw-BootstrapExecutionFailure SOURCE_MUTATION "Source identity changed: $path"}}finally{$stream.Dispose()}
    }
}

function Test-BootstrapPathOverlap {
    param([string]$Left,[string]$Right)
    $leftFull=[IO.Path]::GetFullPath($Left).TrimEnd('\');$rightFull=[IO.Path]::GetFullPath($Right).TrimEnd('\')
    return $leftFull.Equals($rightFull,[StringComparison]::OrdinalIgnoreCase)-or$leftFull.StartsWith($rightFull+'\',[StringComparison]::OrdinalIgnoreCase)-or$rightFull.StartsWith($leftFull+'\',[StringComparison]::OrdinalIgnoreCase)
}

function Assert-BootstrapDestinationAbsent {
    param([Parameter(Mandatory)][string]$ParentPath,[Parameter(Mandatory)][string]$Leaf)
    try{$entries=[string[]][IO.Directory]::EnumerateFileSystemEntries($ParentPath)}catch{Throw-BootstrapExecutionFailure DESTINATION_ENUMERATION "Cannot enumerate destination parent '$ParentPath'."}
    foreach($entry in $entries){if([IO.Path]::GetFileName($entry).Equals($Leaf,[StringComparison]::OrdinalIgnoreCase)){Throw-BootstrapExecutionFailure DESTINATION_EXISTS "A case-equivalent destination entry already exists: $entry"}}
}

function Get-BootstrapDestinationSafety {
    param([Parameter(Mandatory)][string]$DestinationPath,[Parameter(Mandatory)]$VerifiedSource)
    $destination=[IO.Path]::GetFullPath($DestinationPath);$parent=[IO.Path]::GetDirectoryName($destination);$leaf=[IO.Path]::GetFileName($destination)
    if([string]::IsNullOrEmpty($parent)-or-not[IO.Directory]::Exists($parent)){Throw-BootstrapExecutionFailure DESTINATION_PARENT 'The immediate destination parent must already exist.'}
    Assert-BootstrapPathChainNoReparse $parent -IncludeLeaf
    $parentRecord=Open-BootstrapDirectoryHandle $parent
    try{
        $physicalParent=Get-BootstrapFinalHandlePath $parentRecord.Handle
        $volume=Get-BootstrapHandleVolumeInformation $parentRecord.Handle
        if($volume.VolumeSerial-ne$parentRecord.Identity.VolumeSerial){Throw-BootstrapExecutionFailure DESTINATION_ALIAS 'Destination-parent volume identity is inconsistent.'}
        Assert-BootstrapVolumeComponentRepresentable $leaf $volume.MaximumComponentLength
        $physicalDestination=[IO.Path]::Combine($physicalParent,$leaf)
        Assert-BootstrapDestinationAbsent $parent $leaf
        if(-not(Test-BootstrapIdentityEqual (Get-BootstrapHandleIdentity $VerifiedSource.RootHandle) $VerifiedSource.RootIdentity)){Throw-BootstrapExecutionFailure SOURCE_ALIAS 'Retained SourceRoot identity is no longer stable.'}
        if(Test-BootstrapIdentityEqual $VerifiedSource.RootIdentity $parentRecord.Identity){Throw-BootstrapExecutionFailure DESTINATION_OVERLAP 'Destination parent is the physical SourceRoot.'}
        if(Test-BootstrapPathOverlap $VerifiedSource.PhysicalRootPath $physicalDestination){Throw-BootstrapExecutionFailure DESTINATION_OVERLAP 'Physical source and destination path sets overlap.'}
        return [pscustomobject][ordered]@{Path=$destination;PhysicalPath=$physicalDestination;ParentPath=$parent;PhysicalParentPath=$physicalParent;Leaf=$leaf;ParentHandle=$parentRecord.Handle;ParentIdentity=$parentRecord.Identity;MaximumComponentLength=$volume.MaximumComponentLength;VolumeFileSystem=$volume.FileSystemName}
    }catch{$parentRecord.Handle.Dispose();throw}
}

function Assert-BootstrapParentIdentity {
    param([Parameter(Mandatory)]$DestinationSafety)
    $retained=Get-BootstrapHandleIdentity $DestinationSafety.ParentHandle
    if(-not(Test-BootstrapIdentityEqual $retained $DestinationSafety.ParentIdentity)){Throw-BootstrapExecutionFailure PARENT_IDENTITY 'Retained parent identity changed.'}
    $check=Open-BootstrapDirectoryHandle $DestinationSafety.ParentPath -AllowDeleteShare
    try{if(-not(Test-BootstrapIdentityEqual $check.Identity $DestinationSafety.ParentIdentity)){Throw-BootstrapExecutionFailure PARENT_IDENTITY 'Destination parent path now denotes a different directory.'};if(-not(Get-BootstrapFinalHandlePath $check.Handle).Equals($DestinationSafety.PhysicalParentPath,[StringComparison]::OrdinalIgnoreCase)){Throw-BootstrapExecutionFailure PARENT_IDENTITY 'Destination parent physical path changed.'}}finally{$check.Handle.Dispose()}
}

function New-BootstrapOwnedStaging {
    param([Parameter(Mandatory)]$DestinationSafety,[Parameter(Mandatory)]$VerifiedSource)
    Initialize-BootstrapWindowsNative
    $name='.specops-staging-'+[guid]::NewGuid().ToString('N')
    $path=[IO.Path]::Combine($DestinationSafety.ParentPath,$name)
    Assert-BootstrapVolumeComponentRepresentable $name $DestinationSafety.MaximumComponentLength
    if(Test-BootstrapPathOverlap $VerifiedSource.PhysicalRootPath ([IO.Path]::Combine($DestinationSafety.PhysicalParentPath,$name))-or(Test-BootstrapPathOverlap $DestinationSafety.PhysicalPath ([IO.Path]::Combine($DestinationSafety.PhysicalParentPath,$name)))){Throw-BootstrapExecutionFailure STAGING_OVERLAP 'Staging overlaps source or destination.'}
    if(-not[SpecOpsBootstrapNative.NativeMethods]::CreateDirectoryW($path,[IntPtr]::Zero)){$errorCode=[Runtime.InteropServices.Marshal]::GetLastWin32Error();Throw-BootstrapExecutionFailure STAGING_CREATE "Atomic staging creation failed: $(Get-BootstrapWin32Message $errorCode)"}
    $opened=$null
    try{
        Invoke-BootstrapExecutionFault AfterAtomicStagingCreation ([pscustomobject]@{Path=$path;Name=$name;Destination=$DestinationSafety})
        $opened=Open-BootstrapDirectoryHandle $path -DeleteAccess
        $physicalPath=Get-BootstrapFinalHandlePath $opened.Handle
        if($opened.Identity.VolumeSerial-ne$DestinationSafety.ParentIdentity.VolumeSerial){Throw-BootstrapExecutionFailure STAGING_VOLUME 'Staging and parent are not on the same volume.'}
        if(-not[IO.Path]::GetDirectoryName($physicalPath).Equals($DestinationSafety.PhysicalParentPath,[StringComparison]::OrdinalIgnoreCase)){Throw-BootstrapExecutionFailure STAGING_OWNERSHIP 'Staging is not a physical direct child of the verified parent.'}
        return [pscustomobject][ordered]@{Path=$path;PhysicalPath=$physicalPath;Name=$name;CreatedByInvocation=$true;ParentPath=$DestinationSafety.ParentPath;ParentIdentity=$DestinationSafety.ParentIdentity;Handle=$opened.Handle;Identity=$opened.Identity;Published=$false}
    }catch{
        if($null-ne$opened-and$null-ne$opened.Handle-and-not$opened.Handle.IsClosed){$opened.Handle.Dispose()}
        $_.Exception.Data['UncertainStagingPath']=$path
        throw
    }
}

function Assert-BootstrapStagingOwnership {
    param([Parameter(Mandatory)]$Staging,[Parameter(Mandatory)]$DestinationSafety)
    if(-not$Staging.CreatedByInvocation-or$null-eq$Staging.Handle-or$Staging.Handle.IsClosed-or$Staging.Handle.IsInvalid){Throw-BootstrapExecutionFailure STAGING_OWNERSHIP 'No live current-invocation staging creation record exists.'}
    Assert-BootstrapParentIdentity $DestinationSafety
    if(-not(Test-BootstrapIdentityEqual (Get-BootstrapHandleIdentity $Staging.Handle) $Staging.Identity)){Throw-BootstrapExecutionFailure STAGING_OWNERSHIP 'Live staging identity changed.'}
    if([IO.Path]::GetDirectoryName($Staging.Path)-cne$DestinationSafety.ParentPath){Throw-BootstrapExecutionFailure STAGING_OWNERSHIP 'Staging is not a direct child of the recorded parent.'}
    $check=Open-BootstrapDirectoryHandle $Staging.Path -AllowDeleteShare
    try{if(-not(Test-BootstrapIdentityEqual $check.Identity $Staging.Identity)){Throw-BootstrapExecutionFailure STAGING_OWNERSHIP 'Staging path no longer denotes the created identity.'};if(-not(Get-BootstrapFinalHandlePath $check.Handle).Equals($Staging.PhysicalPath,[StringComparison]::OrdinalIgnoreCase)){Throw-BootstrapExecutionFailure STAGING_OWNERSHIP 'Staging physical path no longer denotes the created object.'}}finally{$check.Handle.Dispose()}
}

function Get-BootstrapOutputDirectories {
    param([string[]]$Paths)
    $set=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($path in $Paths){$directory=[IO.Path]::GetDirectoryName($path.Replace('/',[IO.Path]::DirectorySeparatorChar));while(-not[string]::IsNullOrEmpty($directory)){[void]$set.Add($directory.Replace('\','/'));$directory=[IO.Path]::GetDirectoryName($directory)}}
    return @($set|Sort-Object @{Expression={$_.Split('/').Count}},@{Expression={$_}})
}

function Write-BootstrapOwnedStaging {
    param([Parameter(Mandatory)]$Staging,[Parameter(Mandatory)]$DestinationSafety,[Parameter(Mandatory)]$ProspectiveOutput)
    Assert-BootstrapStagingOwnership $Staging $DestinationSafety
    foreach($directory in Get-BootstrapOutputDirectories @($ProspectiveOutput.Bytes.Keys)){
        $full=[IO.Path]::Combine($Staging.Path,$directory.Replace('/',[IO.Path]::DirectorySeparatorChar))
        if(-not[SpecOpsBootstrapNative.NativeMethods]::CreateDirectoryW($full,[IntPtr]::Zero)){$errorCode=[Runtime.InteropServices.Marshal]::GetLastWin32Error();Throw-BootstrapExecutionFailure OUTPUT_DIRECTORY "Create-new output directory failed for '$directory': $(Get-BootstrapWin32Message $errorCode)"}
    }
    foreach($path in @($ProspectiveOutput.Bytes.Keys|Sort-Object)){
        $full=[IO.Path]::Combine($Staging.Path,$path.Replace('/',[IO.Path]::DirectorySeparatorChar));$bytes=$ProspectiveOutput.Bytes[$path]
        try{$stream=[IO.FileStream]::new($full,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}}catch{Throw-BootstrapExecutionFailure OUTPUT_WRITE "Create-new output write failed for '$path': $($_.Exception.Message)"}
    }
}

function Get-BootstrapCandidateInventory {
    param([Parameter(Mandatory)][string]$Root)
    $pending=[Collections.Generic.Stack[string]]::new();$pending.Push($Root);$files=[Collections.Generic.List[string]]::new();$directories=[Collections.Generic.List[string]]::new()
    while($pending.Count-gt0){$directory=$pending.Pop();try{$entries=[string[]][IO.Directory]::EnumerateFileSystemEntries($directory)}catch{Throw-BootstrapExecutionFailure CANDIDATE_ENUMERATION "Cannot enumerate candidate directory '$directory'."};[Array]::Sort($entries,[StringComparer]::Ordinal)
        for($index=$entries.Length-1;$index-ge0;$index--){$entry=$entries[$index];$relative=[IO.Path]::GetRelativePath($Root,$entry).Replace('\','/');try{$attributes=[IO.File]::GetAttributes($entry)}catch{Throw-BootstrapExecutionFailure CANDIDATE_ENTRY "Cannot inspect candidate entry '$relative'."};if(($attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){Throw-BootstrapExecutionFailure CANDIDATE_REPARSE "Candidate contains a reparse entry: $relative"};if(($attributes-band[IO.FileAttributes]::Directory)-ne0){$directories.Add($relative);$pending.Push($entry)}else{$stream=$null;try{$stream=[IO.FileStream]::new($entry,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read);if([SpecOpsBootstrapNative.NativeMethods]::GetFileType($stream.SafeFileHandle)-ne[SpecOpsBootstrapNative.NativeMethods]::FILE_TYPE_DISK){Throw-BootstrapExecutionFailure CANDIDATE_SPECIAL "Candidate contains a special entry: $relative"}}finally{if($null-ne$stream){$stream.Dispose()}};$files.Add($relative)}}}
    $result=[string[]]$files.ToArray();[Array]::Sort($result,[StringComparer]::Ordinal);return [pscustomobject]@{Files=$result;Directories=@($directories)}
}

function Test-BootstrapCandidateStatic {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)]$ProspectiveOutput)
    $static=Test-BootstrapByteMapStatic $ProspectiveOutput
    if(-not$static.Pass){Throw-BootstrapExecutionFailure STATIC_EXPECTATION ($static.Findings-join'; ')}
    $inventory=Get-BootstrapCandidateInventory $Root;$expected=[string[]]@($ProspectiveOutput.Bytes.Keys);[Array]::Sort($expected,[StringComparer]::Ordinal)
    if($inventory.Files.Count-ne$expected.Count){Throw-BootstrapExecutionFailure STATIC_FILE_SET 'Candidate relative file count differs from the expected Output Inventory.'}
    for($index=0;$index-lt$expected.Count;$index++){if($inventory.Files[$index]-cne$expected[$index]){Throw-BootstrapExecutionFailure STATIC_FILE_SET "Candidate file set differs at '$($expected[$index])'."}}
    foreach($path in $expected){$full=[IO.Path]::Combine($Root,$path.Replace('/',[IO.Path]::DirectorySeparatorChar));$actual=[IO.File]::ReadAllBytes($full);if(-not(Test-BootstrapBytesEqual $actual $ProspectiveOutput.Bytes[$path])){Throw-BootstrapExecutionFailure STATIC_BYTES "Candidate bytes differ: $path"}}
    foreach($path in $inventory.Files){if($path.Equals('.git',[StringComparison]::OrdinalIgnoreCase)-or$path.StartsWith('.git/',[StringComparison]::OrdinalIgnoreCase)-or$path.StartsWith('.specops/evidence/',[StringComparison]::OrdinalIgnoreCase)){Throw-BootstrapExecutionFailure STATIC_PROHIBITED "Prohibited candidate path: $path"}}
    $featureStates=@($inventory.Files|Where-Object{$_.EndsWith('/SPECOPS_STATE.json',[StringComparison]::OrdinalIgnoreCase)-and-not$_.StartsWith('Assets/Project/Docs/Specifications/_templates/',[StringComparison]::Ordinal)})
    if($featureStates.Count-ne0){Throw-BootstrapExecutionFailure STATIC_FEATURE_STATE 'Candidate contains an instantiated feature state.'}
    $specops=$script:Utf8.GetString($ProspectiveOutput.Bytes['.specops/specops.json'])|ConvertFrom-Json -Depth 100
    if($specops.repository.id-cne$ProspectiveOutput.Inputs.ProjectId-or$specops.repository.type-cne'unity-game-project'-or$specops.repository.purpose-cne'SpecOps v2 governed Unity game project'-or$null-ne$specops.repository.PSObject.Properties['migrationStatus']-or$null-ne$specops.repository.releasedVersion-or$specops.initialization.releaseEvidencePresent-ne$false-or$specops.initialization.bootstrapPresent-ne$true){Throw-BootstrapExecutionFailure STATIC_FRESH_STATE 'Candidate fresh repository state invariant failed.'}
    $required=@('.specops/specops.json','.specops/permissions.json','.specops/bootstrap.json','.specops/contracts/bootstrap-v1.md','Assets/Project/Docs/Architecture/ARCHITECTURE.md','Assets/Project/Docs/Specifications/_templates/feature/SPECOPS_STATE.json')
    foreach($path in $required){if(-not$ProspectiveOutput.Bytes.ContainsKey($path)){Throw-BootstrapExecutionFailure STATIC_TOPOLOGY "Required output is absent: $path"}}
    return [pscustomobject][ordered]@{Pass=$true;OutputCount=$expected.Count;Files=$expected;UnityExecuted=$false}
}

function Test-BootstrapCleanupTreeSafety {
    param([Parameter(Mandatory)][string]$Root)
    try{[void](Get-BootstrapCandidateInventory $Root);return $true}catch{return $false}
}

function Remove-BootstrapOwnedStaging {
    param([Parameter(Mandatory)]$Staging,[Parameter(Mandatory)]$DestinationSafety)
    Invoke-BootstrapExecutionFault BeforeCleanup $Staging
    Assert-BootstrapStagingOwnership $Staging $DestinationSafety
    if(-not(Test-BootstrapCleanupTreeSafety $Staging.Path)){Throw-BootstrapExecutionFailure CLEANUP_REFUSED 'Staging cleanup refused because reparse/special safety was not established.'}
    Throw-BootstrapExecutionFailure CLEANUP_RETAINED 'Automatic recursive cleanup is refused because object-bound ownership is not recorded for every descendant; owned staging is retained.'
}

function Publish-BootstrapOwnedStaging {
    param([Parameter(Mandatory)]$Staging,[Parameter(Mandatory)]$DestinationSafety)
    Assert-BootstrapStagingOwnership $Staging $DestinationSafety
    Assert-BootstrapDestinationAbsent $DestinationSafety.ParentPath $DestinationSafety.Leaf
    Invoke-BootstrapExecutionFault BeforeOwnedHandlePublication ([pscustomobject]@{Staging=$Staging;Destination=$DestinationSafety})
    Assert-BootstrapStagingOwnership $Staging $DestinationSafety
    Assert-BootstrapDestinationAbsent $DestinationSafety.ParentPath $DestinationSafety.Leaf
    [int]$errorCode=0
    if(-not[SpecOpsBootstrapNative.NativeMethods]::RenameAbsoluteNoReplace($Staging.Handle,$DestinationSafety.PhysicalPath,[ref]$errorCode)){Throw-BootstrapExecutionFailure PUBLICATION_MOVE "Non-replacing same-parent by-handle publication failed: $(Get-BootstrapWin32Message $errorCode)"}
    $Staging.Published=$true
    $published=Open-BootstrapDirectoryHandle $DestinationSafety.Path -AllowDeleteShare
    if(-not(Test-BootstrapIdentityEqual $published.Identity $Staging.Identity)){$published.Handle.Dispose();Throw-BootstrapExecutionFailure PUBLICATION_IDENTITY 'Published destination does not have the recorded staging identity.'}
    return $published
}

function ConvertTo-BootstrapExecutionResultBytes {
    param([Parameter(Mandatory)]$Value)
    $json=ConvertTo-BootstrapJcs (ConvertTo-BootstrapJsonBytes $Value)
    return $script:Utf8.GetBytes($json+"`n")
}

function ConvertFrom-BootstrapRawArguments {
    param([AllowEmptyCollection()][string[]]$RawArguments)
    $names=@('DestinationPath','ProjectId','ProductName','CompanyName','ApplicationIdentifier','CodeNamespaceRoot')
    $lookup=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase);foreach($name in $names){$lookup.Add('-'+$name,$name)}
    $values=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
    $index=0
    while($index-lt$RawArguments.Count){$token=$RawArguments[$index];if(-not$lookup.ContainsKey($token)){Throw-BootstrapExecutionFailure INVOCATION_SYNTAX "Unknown or noncanonical argument name '$token'."};$name=$lookup[$token];if($values.ContainsKey($name)){Throw-BootstrapExecutionFailure INVOCATION_SYNTAX "Argument '$token' occurs more than once."};if($index+1-ge$RawArguments.Count){Throw-BootstrapExecutionFailure INVOCATION_SYNTAX "Argument '$token' must have exactly one value."};$values.Add($name,$RawArguments[$index+1]);$index+=2}
    $missing=@($names|Where-Object{-not$values.ContainsKey($_)});if($missing.Count-ne0){Throw-BootstrapExecutionFailure MISSING_INPUTS ('Missing required inputs in canonical order: '+($missing-join', '))}
    $ordered=[ordered]@{};foreach($name in $names){$ordered[$name]=$values[$name]};return $ordered
}

function Get-BootstrapFailureClass {
    param($Exception)
    if($null-ne$Exception.Data['BootstrapExecutionFailureClass']){return [string]$Exception.Data['BootstrapExecutionFailureClass']}
    if($null-ne$Exception.Data['BootstrapFailureCode']){return [string]$Exception.Data['BootstrapFailureCode']}
    return 'INTERNAL_INVARIANT'
}

function Invoke-SpecOpsBootstrapExecution {
    [CmdletBinding()]param([AllowEmptyCollection()][string[]]$RawArguments,[Parameter(Mandatory)][string]$ImplementationScriptPath)
    $phase='invocation';$exitCode=2;$verifiedSource=$null;$destinationSafety=$null;$staging=$null;$published=$null;$publishedSuccessfully=$false;$diagnostic=$null
    try {
        if(-not[OperatingSystem]::IsWindows()-or$PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7-or-not[Environment]::Is64BitProcess){Throw-BootstrapExecutionFailure UNSUPPORTED_PLATFORM 'Bootstrap requires 64-bit PowerShell 7 or later on Windows.'}
        $raw=ConvertFrom-BootstrapRawArguments $RawArguments
        $phase='input';$exitCode=2
        $inputs=Assert-BootstrapInvocationValues @raw
        $phase='source';$exitCode=3
        $locator=Resolve-BootstrapImplementationSource $ImplementationScriptPath
        $verifiedSource=Open-BootstrapImmutableSource $locator
        if($verifiedSource.SourceIdentity-cne'84d90b31522b96876b3ed8afe01ede1f5273e138cffb94adfdd25b32387cde80'){Throw-BootstrapExecutionFailure SOURCE_IDENTITY 'The currently approved Source Identity is not present.'}
        Invoke-BootstrapExecutionFault AfterSourceAcquisition $verifiedSource
        Assert-BootstrapSourceConsistency $verifiedSource
        $phase='destination';$exitCode=4
        $destinationSafety=Get-BootstrapDestinationSafety $inputs.DestinationPath $verifiedSource
        $phase='staging';$exitCode=5
        Invoke-BootstrapExecutionFault BeforeStagingCreation $destinationSafety
        $staging=New-BootstrapOwnedStaging $destinationSafety $verifiedSource
        Invoke-BootstrapExecutionFault AfterStagingCreated $staging
        $phase='projection';$exitCode=6
        $prospective=New-BootstrapProspectiveOutputMap $verifiedSource $inputs $verifiedSource.ImplementationVersion
        if($prospective.Count-ne312){Throw-BootstrapExecutionFailure OUTPUT_COUNT 'Prospective output count must remain 312.'}
        $phase='generated-output';$exitCode=7
        if(-not$prospective.Bytes.ContainsKey('.specops/bootstrap.json')){Throw-BootstrapExecutionFailure GENERATED_OUTPUT 'Final generated Bootstrap provenance is absent.'}
        Write-BootstrapOwnedStaging $staging $destinationSafety $prospective
        $phase='staged-verification';$exitCode=8
        Invoke-BootstrapExecutionFault BeforeStagedVerification $staging
        $stagedVerification=Test-BootstrapCandidateStatic $staging.Path $prospective
        Assert-BootstrapSourceConsistency $verifiedSource
        $phase='publication';$exitCode=9
        Assert-BootstrapParentIdentity $destinationSafety
        Assert-BootstrapDestinationAbsent $destinationSafety.ParentPath $destinationSafety.Leaf
        Invoke-BootstrapExecutionFault BeforePublication ([pscustomobject]@{Staging=$staging;Destination=$destinationSafety})
        Assert-BootstrapParentIdentity $destinationSafety
        Assert-BootstrapDestinationAbsent $destinationSafety.ParentPath $destinationSafety.Leaf
        Assert-BootstrapSourceConsistency $verifiedSource
        $published=Publish-BootstrapOwnedStaging $staging $destinationSafety
        $publishedSuccessfully=$true
        Invoke-BootstrapExecutionFault AfterPublication ([pscustomobject]@{Published=$published;Destination=$destinationSafety})
        $phase='post-publication-verification';$exitCode=10
        Invoke-BootstrapExecutionFault BeforePostPublicationVerification ([pscustomobject]@{Published=$published;Destination=$destinationSafety})
        $publishedVerification=Test-BootstrapCandidateStatic $destinationSafety.Path $prospective
        Assert-BootstrapSourceConsistency $verifiedSource
        $success=[ordered]@{bootstrapContractVersion=[string]$verifiedSource.ManifestRecord.Manifest.bootstrapContractVersion;bootstrapImplementationVersion=$verifiedSource.ImplementationVersion;exitCode=0;goldenBaseline=[ordered]@{id=[string]$verifiedSource.ManifestRecord.Manifest.goldenBaseline.id;version=[string]$verifiedSource.ManifestRecord.Manifest.goldenBaseline.version};sourceIdentity=[ordered]@{digest=$verifiedSource.SourceIdentity;profile=[string]$verifiedSource.ManifestRecord.Manifest.sourceIdentity.profile};status='SUCCESS'}
        return [pscustomobject][ordered]@{ExitCode=0;StdoutBytes=(ConvertTo-BootstrapExecutionResultBytes $success);Diagnostic='';StagedVerification=$stagedVerification;PublishedVerification=$publishedVerification;RegularLeafCount=$verifiedSource.RegularLeafCount;AuthoredCount=$verifiedSource.Bytes.Count;ImplementationSupportCount=$verifiedSource.ImplementationSupportPaths.Count;OutputCount=$prospective.Count}
    }
    catch {
        $primary=$_;$failureClass=Get-BootstrapFailureClass $primary.Exception
        if($failureClass-ceq'INTERNAL_INVARIANT'){$phase='internal';$exitCode=70}
        $diagnostic=$primary.Exception.Message
        if($null-ne$staging-and-not$publishedSuccessfully-and-not$staging.Published){
            if($null-ne$staging.Handle-and-not$staging.Handle.IsClosed){try{Remove-BootstrapOwnedStaging $staging $destinationSafety}catch{$diagnostic+="`nRetained staging path: $($staging.Path)`nCleanup refusal/failure: $($_.Exception.Message)"}}
            else{$diagnostic+="`nRetained staging path without current ownership proof: $($staging.Path)"}
        }
        elseif($null-ne$primary.Exception.Data['UncertainStagingPath']){$diagnostic+="`nUncertain staging path retained without cleanup: $($primary.Exception.Data['UncertainStagingPath'])"}
        elseif($publishedSuccessfully-or($null-ne$staging-and$staging.Published)){$diagnostic+="`nPublished destination retained for Human inspection: $($destinationSafety.Path)"}
        $failure=[ordered]@{exitCode=$exitCode;failureClass=$failureClass;phase=$phase;status='FAILURE'}
        return [pscustomobject][ordered]@{ExitCode=$exitCode;StdoutBytes=(ConvertTo-BootstrapExecutionResultBytes $failure);Diagnostic=$diagnostic}
    }
    finally {
        if($null-ne$published-and$null-ne$published.Handle-and-not$published.Handle.IsClosed){$published.Handle.Dispose()}
        if($null-ne$staging-and$null-ne$staging.Handle-and-not$staging.Handle.IsClosed){$staging.Handle.Dispose()}
        if($null-ne$destinationSafety-and$null-ne$destinationSafety.ParentHandle-and-not$destinationSafety.ParentHandle.IsClosed){$destinationSafety.ParentHandle.Dispose()}
        Close-BootstrapImmutableSource $verifiedSource
    }
}

Export-ModuleMember -Function @(
    'Assert-BootstrapInvocationValues','Read-BootstrapStrictJson','ConvertTo-BootstrapJcs','Get-BootstrapJsonIdentity','Get-BootstrapSha256Hex',
    'Get-BootstrapProductGuid','Get-BootstrapSourceIdentity','Read-BootstrapProjectionManifest','Test-BootstrapClosedSourceAccounting',
    'Get-VerifiedBootstrapSource','Invoke-BootstrapScopedTransforms','New-BootstrapProvenance','New-BootstrapProspectiveOutputMap','Test-BootstrapByteMapStatic',
    'Invoke-SpecOpsBootstrapExecution'
)
