Set-StrictMode -Version Latest

$script:SpecOpsProfileId = 'specops-json-jcs-sha256-v1'
$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false, $true)
$script:InvariantCulture = [System.Globalization.CultureInfo]::InvariantCulture

function Throw-SpecOpsInputRejection {
    param(
        [Parameter(Mandatory)]
        [string] $RejectionClass,

        [Parameter(Mandatory)]
        [string] $Message
    )

    $exception = [System.IO.InvalidDataException]::new($Message)
    $exception.Data['SpecOpsExitCode'] = 2
    $exception.Data['SpecOpsRejectionClass'] = $RejectionClass
    throw $exception
}

function Get-SpecOpsErrorMetadata {
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord] $ErrorRecord
    )

    $exception = $ErrorRecord.Exception
    while ($null -ne $exception) {
        if ($exception.Data.Contains('SpecOpsExitCode')) {
            return [pscustomobject][ordered]@{
                ExitCode       = [int] $exception.Data['SpecOpsExitCode']
                RejectionClass = [string] $exception.Data['SpecOpsRejectionClass']
            }
        }

        $exception = $exception.InnerException
    }

    return [pscustomobject][ordered]@{
        ExitCode       = 4
        RejectionClass = 'INTERNAL_TOOL_FAILURE'
    }
}

function Assert-SpecOpsValidUnicodeString {
    param(
        [AllowEmptyString()]
        [Parameter(Mandatory)]
        [string] $Value
    )

    for ($index = 0; $index -lt $Value.Length; $index++) {
        $codeUnit = [int] $Value[$index]
        if ($codeUnit -ge 0xD800 -and $codeUnit -le 0xDBFF) {
            if (($index + 1) -ge $Value.Length) {
                Throw-SpecOpsInputRejection -RejectionClass 'INVALID_UNICODE_DATA' -Message 'A high surrogate is not followed by a low surrogate.'
            }

            $nextCodeUnit = [int] $Value[$index + 1]
            if ($nextCodeUnit -lt 0xDC00 -or $nextCodeUnit -gt 0xDFFF) {
                Throw-SpecOpsInputRejection -RejectionClass 'INVALID_UNICODE_DATA' -Message 'A high surrogate is not followed by a low surrogate.'
            }

            $index++
            continue
        }

        if ($codeUnit -ge 0xDC00 -and $codeUnit -le 0xDFFF) {
            Throw-SpecOpsInputRejection -RejectionClass 'INVALID_UNICODE_DATA' -Message 'A low surrogate is not preceded by a high surrogate.'
        }
    }
}

function Get-SpecOpsHexCodeUnit {
    param(
        [Parameter(Mandatory)]
        [string] $Source,

        [Parameter(Mandatory)]
        [int] $StartIndex
    )

    if ($StartIndex -lt 0 -or ($StartIndex + 4) -gt $Source.Length) {
        return -1
    }

    $value = 0
    for ($offset = 0; $offset -lt 4; $offset++) {
        $character = [int] $Source[$StartIndex + $offset]
        if ($character -ge 0x30 -and $character -le 0x39) {
            $digit = $character - 0x30
        }
        elseif ($character -ge 0x41 -and $character -le 0x46) {
            $digit = $character - 0x41 + 10
        }
        elseif ($character -ge 0x61 -and $character -le 0x66) {
            $digit = $character - 0x61 + 10
        }
        else {
            return -1
        }
        $value = ($value * 16) + $digit
    }

    return $value
}

function Assert-SpecOpsRawJsonUnicodeEscapes {
    param(
        [Parameter(Mandatory)]
        [string] $SourceText
    )

    Assert-SpecOpsValidUnicodeString -Value $SourceText
    for ($index = 0; $index -lt $SourceText.Length; $index++) {
        if ($SourceText[$index] -ne '"') {
            continue
        }

        $index++
        while ($index -lt $SourceText.Length) {
            $character = $SourceText[$index]
            if ($character -eq '"') {
                break
            }

            if ($character -ne '\') {
                $index++
                continue
            }

            if (($index + 1) -ge $SourceText.Length) {
                break
            }

            if ($SourceText[$index + 1] -ne 'u') {
                $index += 2
                continue
            }

            $codeUnit = Get-SpecOpsHexCodeUnit -Source $SourceText -StartIndex ($index + 2)
            if ($codeUnit -lt 0) {
                break
            }

            if ($codeUnit -ge 0xD800 -and $codeUnit -le 0xDBFF) {
                if (($index + 11) -ge $SourceText.Length -or
                    $SourceText[$index + 6] -ne '\' -or
                    $SourceText[$index + 7] -ne 'u') {
                    Throw-SpecOpsInputRejection -RejectionClass 'INVALID_UNICODE_DATA' -Message 'An escaped high surrogate is not followed by an escaped low surrogate.'
                }

                $lowCodeUnit = Get-SpecOpsHexCodeUnit -Source $SourceText -StartIndex ($index + 8)
                if ($lowCodeUnit -lt 0xDC00 -or $lowCodeUnit -gt 0xDFFF) {
                    Throw-SpecOpsInputRejection -RejectionClass 'INVALID_UNICODE_DATA' -Message 'An escaped high surrogate is not followed by an escaped low surrogate.'
                }

                $index += 12
                continue
            }

            if ($codeUnit -ge 0xDC00 -and $codeUnit -le 0xDFFF) {
                Throw-SpecOpsInputRejection -RejectionClass 'INVALID_UNICODE_DATA' -Message 'An escaped low surrogate is not preceded by an escaped high surrogate.'
            }

            $index += 6
        }
    }
}

function Assert-SpecOpsJsonElement {
    param(
        [Parameter(Mandatory)]
        [System.Text.Json.JsonElement] $Element
    )

    switch ($Element.ValueKind) {
        ([System.Text.Json.JsonValueKind]::Object) {
            $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            foreach ($property in $Element.EnumerateObject()) {
                try {
                    $name = $property.Name
                    Assert-SpecOpsValidUnicodeString -Value $name
                }
                catch {
                    if ((Get-SpecOpsErrorMetadata -ErrorRecord $_).ExitCode -eq 2) {
                        throw
                    }

                    Throw-SpecOpsInputRejection -RejectionClass 'INVALID_UNICODE_DATA' -Message 'An object member name contains invalid Unicode data.'
                }

                if (-not $names.Add($name)) {
                    Throw-SpecOpsInputRejection -RejectionClass 'DUPLICATE_OBJECT_MEMBER_NAME' -Message "The object member name '$name' occurs more than once."
                }

                Assert-SpecOpsJsonElement -Element $property.Value
            }
            break
        }

        ([System.Text.Json.JsonValueKind]::Array) {
            foreach ($item in $Element.EnumerateArray()) {
                Assert-SpecOpsJsonElement -Element $item
            }
            break
        }

        ([System.Text.Json.JsonValueKind]::String) {
            try {
                $value = $Element.GetString()
                Assert-SpecOpsValidUnicodeString -Value $value
            }
            catch {
                if ((Get-SpecOpsErrorMetadata -ErrorRecord $_).ExitCode -eq 2) {
                    throw
                }

                Throw-SpecOpsInputRejection -RejectionClass 'INVALID_UNICODE_DATA' -Message 'A string contains invalid Unicode data.'
            }
            break
        }

        ([System.Text.Json.JsonValueKind]::Number) {
            try {
                $number = $Element.GetDouble()
            }
            catch {
                Throw-SpecOpsInputRejection -RejectionClass 'UNSUPPORTED_NUMBER' -Message 'A JSON number cannot be represented as an IEEE 754 binary64 value.'
            }

            if (-not [double]::IsFinite($number)) {
                Throw-SpecOpsInputRejection -RejectionClass 'UNSUPPORTED_NUMBER' -Message 'A JSON number is outside the finite IEEE 754 binary64 domain.'
            }
            break
        }

        ([System.Text.Json.JsonValueKind]::True) { break }
        ([System.Text.Json.JsonValueKind]::False) { break }
        ([System.Text.Json.JsonValueKind]::Null) { break }
        default {
            Throw-SpecOpsInputRejection -RejectionClass 'MALFORMED_JSON' -Message 'The parsed input contains an unsupported JSON token.'
        }
    }
}

function Read-SpecOpsStrictJsonBytes {
    param(
        [Parameter(Mandatory)]
        [byte[]] $Bytes
    )

    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        Throw-SpecOpsInputRejection -RejectionClass 'LEADING_UTF8_BOM' -Message 'Source JSON beginning with a UTF-8 BOM is rejected by the content identity profile.'
    }

    try {
        $sourceText = $script:Utf8NoBom.GetString($Bytes)
    }
    catch [System.Text.DecoderFallbackException] {
        Throw-SpecOpsInputRejection -RejectionClass 'MALFORMED_UTF8' -Message 'Source JSON is not valid UTF-8.'
    }
    Assert-SpecOpsRawJsonUnicodeEscapes -SourceText $sourceText

    $options = [System.Text.Json.JsonDocumentOptions]::new()
    $options.AllowTrailingCommas = $false
    $options.CommentHandling = [System.Text.Json.JsonCommentHandling]::Disallow
    $options.MaxDepth = 0

    try {
        $document = [System.Text.Json.JsonDocument]::Parse([System.ReadOnlyMemory[byte]]::new($Bytes), $options)
    }
    catch [System.Text.Json.JsonException] {
        Throw-SpecOpsInputRejection -RejectionClass 'MALFORMED_JSON' -Message 'Source input is not strict JSON.'
    }

    try {
        Assert-SpecOpsJsonElement -Element $document.RootElement
        return $document.RootElement.Clone()
    }
    finally {
        $document.Dispose()
    }
}

function ConvertTo-SpecOpsJcsString {
    param(
        [AllowEmptyString()]
        [Parameter(Mandatory)]
        [string] $Value
    )

    Assert-SpecOpsValidUnicodeString -Value $Value
    $builder = [System.Text.StringBuilder]::new($Value.Length + 2)
    [void] $builder.Append('"')

    :characterLoop for ($index = 0; $index -lt $Value.Length; $index++) {
        $character = $Value[$index]
        $codeUnit = [int] $character
        switch ($codeUnit) {
            0x08 { [void] $builder.Append('\b'); continue characterLoop }
            0x09 { [void] $builder.Append('\t'); continue characterLoop }
            0x0A { [void] $builder.Append('\n'); continue characterLoop }
            0x0C { [void] $builder.Append('\f'); continue characterLoop }
            0x0D { [void] $builder.Append('\r'); continue characterLoop }
            0x22 { [void] $builder.Append('\"'); continue characterLoop }
            0x5C { [void] $builder.Append('\\'); continue characterLoop }
        }

        if ($codeUnit -ge 0 -and $codeUnit -le 0x1F) {
            [void] $builder.Append('\u')
            [void] $builder.Append($codeUnit.ToString('x4', $script:InvariantCulture))
            continue
        }

        [void] $builder.Append($character)
    }

    [void] $builder.Append('"')
    return $builder.ToString()
}

function ConvertTo-SpecOpsJcsNumber {
    param(
        [Parameter(Mandatory)]
        [double] $Value
    )

    if (-not [double]::IsFinite($Value)) {
        Throw-SpecOpsInputRejection -RejectionClass 'UNSUPPORTED_NUMBER' -Message 'JCS cannot serialize a non-finite number.'
    }

    if ($Value -eq 0.0) {
        return '0'
    }

    $negative = $Value -lt 0.0
    $absoluteValue = [Math]::Abs($Value)
    $roundTrip = $absoluteValue.ToString('R', $script:InvariantCulture)
    $exponentIndex = $roundTrip.IndexOfAny([char[]] @('E', 'e'))

    if ($exponentIndex -ge 0) {
        $mantissa = $roundTrip.Substring(0, $exponentIndex)
        $parsedExponent = [int]::Parse(
            $roundTrip.Substring($exponentIndex + 1),
            [System.Globalization.NumberStyles]::Integer,
            $script:InvariantCulture
        )
        $digits = $mantissa.Replace('.', '')
        $decimalPosition = $parsedExponent + 1
    }
    else {
        $decimalPoint = $roundTrip.IndexOf('.')
        if ($decimalPoint -lt 0) {
            $decimalPoint = $roundTrip.Length
        }

        $digitsWithLeadingZeros = $roundTrip.Replace('.', '')
        $leadingZeroCount = 0
        while ($leadingZeroCount -lt $digitsWithLeadingZeros.Length -and $digitsWithLeadingZeros[$leadingZeroCount] -eq '0') {
            $leadingZeroCount++
        }

        $digits = $digitsWithLeadingZeros.Substring($leadingZeroCount)
        $decimalPosition = $decimalPoint - $leadingZeroCount
    }

    if ([string]::IsNullOrEmpty($digits)) {
        return '0'
    }

    $digitCount = $digits.Length
    if ($digitCount -le $decimalPosition -and $decimalPosition -le 21) {
        $serialized = $digits + ('0' * ($decimalPosition - $digitCount))
    }
    elseif ($decimalPosition -gt 0 -and $decimalPosition -le 21) {
        $serialized = $digits.Substring(0, $decimalPosition) + '.' + $digits.Substring($decimalPosition)
    }
    elseif ($decimalPosition -gt -6 -and $decimalPosition -le 0) {
        $serialized = '0.' + ('0' * (-$decimalPosition)) + $digits
    }
    else {
        if ($digitCount -eq 1) {
            $serialized = $digits
        }
        else {
            $serialized = $digits.Substring(0, 1) + '.' + $digits.Substring(1)
        }

        $scientificExponent = $decimalPosition - 1
        if ($scientificExponent -ge 0) {
            $serialized += 'e+' + $scientificExponent.ToString($script:InvariantCulture)
        }
        else {
            $serialized += 'e' + $scientificExponent.ToString($script:InvariantCulture)
        }
    }

    if ($negative) {
        return '-' + $serialized
    }

    return $serialized
}

function ConvertTo-SpecOpsJcsElement {
    param(
        [Parameter(Mandatory)]
        [System.Text.Json.JsonElement] $Element,

        [switch] $ExcludeRootContentIdentity
    )

    switch ($Element.ValueKind) {
        ([System.Text.Json.JsonValueKind]::Object) {
            $properties = [System.Collections.Generic.SortedDictionary[string, System.Text.Json.JsonElement]]::new([System.StringComparer]::Ordinal)
            foreach ($property in $Element.EnumerateObject()) {
                if ($ExcludeRootContentIdentity -and [string]::Equals($property.Name, 'contentIdentity', [System.StringComparison]::Ordinal)) {
                    continue
                }

                $properties.Add($property.Name, $property.Value)
            }

            $builder = [System.Text.StringBuilder]::new()
            [void] $builder.Append('{')
            $first = $true
            foreach ($entry in $properties.GetEnumerator()) {
                if (-not $first) {
                    [void] $builder.Append(',')
                }
                $first = $false
                [void] $builder.Append((ConvertTo-SpecOpsJcsString -Value $entry.Key))
                [void] $builder.Append(':')
                [void] $builder.Append((ConvertTo-SpecOpsJcsElement -Element $entry.Value))
            }
            [void] $builder.Append('}')
            return $builder.ToString()
        }

        ([System.Text.Json.JsonValueKind]::Array) {
            $builder = [System.Text.StringBuilder]::new()
            [void] $builder.Append('[')
            $first = $true
            foreach ($item in $Element.EnumerateArray()) {
                if (-not $first) {
                    [void] $builder.Append(',')
                }
                $first = $false
                [void] $builder.Append((ConvertTo-SpecOpsJcsElement -Element $item))
            }
            [void] $builder.Append(']')
            return $builder.ToString()
        }

        ([System.Text.Json.JsonValueKind]::String) {
            return ConvertTo-SpecOpsJcsString -Value $Element.GetString()
        }

        ([System.Text.Json.JsonValueKind]::Number) {
            return ConvertTo-SpecOpsJcsNumber -Value $Element.GetDouble()
        }

        ([System.Text.Json.JsonValueKind]::True) { return 'true' }
        ([System.Text.Json.JsonValueKind]::False) { return 'false' }
        ([System.Text.Json.JsonValueKind]::Null) { return 'null' }
        default {
            Throw-SpecOpsInputRejection -RejectionClass 'MALFORMED_JSON' -Message 'The parsed input contains an unsupported JSON token.'
        }
    }
}

function Assert-SpecOpsEvalDefinitionIdentityMember {
    param(
        [Parameter(Mandatory)]
        [System.Text.Json.JsonElement] $Root
    )

    if ($Root.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) {
        Throw-SpecOpsInputRejection -RejectionClass 'INVALID_EVAL_DEFINITION_ROOT' -Message 'EVAL_DEFINITION mode requires a root JSON object.'
    }

    $found = $false
    foreach ($property in $Root.EnumerateObject()) {
        if (-not [string]::Equals($property.Name, 'contentIdentity', [System.StringComparison]::Ordinal)) {
            continue
        }

        $found = $true
        if ($property.Value.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) {
            Throw-SpecOpsInputRejection -RejectionClass 'INVALID_EVAL_CONTENT_IDENTITY' -Message 'The root contentIdentity member must be an object.'
        }

        $memberNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($member in $property.Value.EnumerateObject()) {
            [void] $memberNames.Add($member.Name)
        }

        if ($memberNames.Count -ne 2 -or -not $memberNames.Contains('algorithm') -or -not $memberNames.Contains('value')) {
            Throw-SpecOpsInputRejection -RejectionClass 'INVALID_EVAL_CONTENT_IDENTITY' -Message 'The root contentIdentity member must contain only algorithm and value.'
        }

        $algorithm = $property.Value.GetProperty('algorithm')
        $identityValue = $property.Value.GetProperty('value')
        if ($algorithm.ValueKind -ne [System.Text.Json.JsonValueKind]::String -or [string]::IsNullOrEmpty($algorithm.GetString())) {
            Throw-SpecOpsInputRejection -RejectionClass 'INVALID_EVAL_CONTENT_IDENTITY' -Message 'The root contentIdentity.algorithm member must be a non-empty string.'
        }
        if ($identityValue.ValueKind -ne [System.Text.Json.JsonValueKind]::String -or [string]::IsNullOrEmpty($identityValue.GetString())) {
            Throw-SpecOpsInputRejection -RejectionClass 'INVALID_EVAL_CONTENT_IDENTITY' -Message 'The root contentIdentity.value member must be a non-empty string.'
        }
    }

    if (-not $found) {
        Throw-SpecOpsInputRejection -RejectionClass 'MISSING_EVAL_CONTENT_IDENTITY' -Message 'EVAL_DEFINITION mode requires one root contentIdentity member.'
    }
}

function Get-SpecOpsCanonicalResultFromBytes {
    param(
        [Parameter(Mandatory)]
        [byte[]] $Bytes,

        [Parameter(Mandatory)]
        [ValidateSet('FULL_JSON', 'EVAL_DEFINITION')]
        [string] $Mode
    )

    $root = Read-SpecOpsStrictJsonBytes -Bytes $Bytes
    $excludeRootIdentity = $false
    if ($Mode -eq 'EVAL_DEFINITION') {
        Assert-SpecOpsEvalDefinitionIdentityMember -Root $root
        $excludeRootIdentity = $true
    }

    $canonicalJson = ConvertTo-SpecOpsJcsElement -Element $root -ExcludeRootContentIdentity:$excludeRootIdentity
    $canonicalBytes = $script:Utf8NoBom.GetBytes($canonicalJson)
    $digest = [System.Security.Cryptography.SHA256]::HashData($canonicalBytes)
    $hex = [Convert]::ToHexString($digest).ToLowerInvariant()

    return [pscustomobject][ordered]@{
        ProfileId     = $script:SpecOpsProfileId
        Value         = $hex
        CanonicalJson = $canonicalJson
    }
}

function ConvertTo-SpecOpsCanonicalJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [byte[]] $Bytes,

        [Parameter(Mandatory)]
        [ValidateSet('FULL_JSON', 'EVAL_DEFINITION')]
        [string] $Mode
    )

    return (Get-SpecOpsCanonicalResultFromBytes -Bytes $Bytes -Mode $Mode).CanonicalJson
}

function Get-SpecOpsJsonContentIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [ValidateSet('FULL_JSON', 'EVAL_DEFINITION')]
        [string] $Mode
    )

    if (-not [System.IO.File]::Exists($Path)) {
        Throw-SpecOpsInputRejection -RejectionClass 'INPUT_FILE_NOT_FOUND' -Message "Input file does not exist: $Path"
    }

    try {
        $bytes = [System.IO.File]::ReadAllBytes([System.IO.Path]::GetFullPath($Path))
    }
    catch {
        Throw-SpecOpsInputRejection -RejectionClass 'INPUT_FILE_UNREADABLE' -Message "Input file could not be read: $Path"
    }

    $result = Get-SpecOpsCanonicalResultFromBytes -Bytes $bytes -Mode $Mode
    return [pscustomobject][ordered]@{
        profileId = $result.ProfileId
        value     = $result.Value
    }
}

function Test-SpecOpsContentIdentityProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $VectorSetPath
    )

    if (-not [System.IO.File]::Exists($VectorSetPath)) {
        Throw-SpecOpsInputRejection -RejectionClass 'VECTOR_SET_NOT_FOUND' -Message "Profile vector set does not exist: $VectorSetPath"
    }

    $vectorRoot = Read-SpecOpsStrictJsonBytes -Bytes ([System.IO.File]::ReadAllBytes([System.IO.Path]::GetFullPath($VectorSetPath)))
    if ($vectorRoot.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) {
        Throw-SpecOpsInputRejection -RejectionClass 'INVALID_VECTOR_SET' -Message 'The profile vector set root must be an object.'
    }

    $profileId = $vectorRoot.GetProperty('profileId').GetString()
    if (-not [string]::Equals($profileId, $script:SpecOpsProfileId, [System.StringComparison]::Ordinal)) {
        Throw-SpecOpsInputRejection -RejectionClass 'PROFILE_ID_MISMATCH' -Message 'The vector-set profileId does not match the implemented profile.'
    }

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($vector in $vectorRoot.GetProperty('vectors').EnumerateArray()) {
        $id = $vector.GetProperty('id').GetString()
        $mode = $vector.GetProperty('mode').GetString()
        $expectedOutcome = $vector.GetProperty('expectedOutcome').GetString()
        $inputText = $vector.GetProperty('inputJsonText').GetString()
        $inputBytes = $script:Utf8NoBom.GetBytes($inputText)
        $passed = $false
        $detail = ''

        if ($expectedOutcome -eq 'IDENTITY') {
            try {
                $actual = Get-SpecOpsCanonicalResultFromBytes -Bytes $inputBytes -Mode $mode
                $expectedCanonical = $vector.GetProperty('expectedCanonicalJson').GetString()
                $expectedDigest = $vector.GetProperty('expectedSha256Hex').GetString()
                $canonicalMatches = [string]::Equals($actual.CanonicalJson, $expectedCanonical, [System.StringComparison]::Ordinal)
                $digestMatches = [string]::Equals($actual.Value, $expectedDigest, [System.StringComparison]::Ordinal)
                $passed = $canonicalMatches -and $digestMatches
                if (-not $canonicalMatches) { $detail = 'CANONICAL_JSON_MISMATCH' }
                elseif (-not $digestMatches) { $detail = 'DIGEST_MISMATCH' }
            }
            catch {
                $passed = $false
                $detail = (Get-SpecOpsErrorMetadata -ErrorRecord $_).RejectionClass
            }
        }
        elseif ($expectedOutcome -eq 'REJECT') {
            try {
                [void] (Get-SpecOpsCanonicalResultFromBytes -Bytes $inputBytes -Mode $mode)
                $passed = $false
                $detail = 'EXPECTED_REJECTION_NOT_OBSERVED'
            }
            catch {
                $actualClass = (Get-SpecOpsErrorMetadata -ErrorRecord $_).RejectionClass
                $expectedClass = $vector.GetProperty('rejectionClass').GetString()
                $passed = [string]::Equals($actualClass, $expectedClass, [System.StringComparison]::Ordinal)
                if (-not $passed) { $detail = 'EXPECTED_{0}_ACTUAL_{1}' -f $expectedClass, $actualClass }
            }
        }
        else {
            $detail = 'UNSUPPORTED_EXPECTED_OUTCOME'
        }

        $results.Add([pscustomobject][ordered]@{
            id     = $id
            status = $(if ($passed) { 'PASS' } else { 'FAIL' })
            detail = $detail
        })
    }

    $failed = @($results | Where-Object status -eq 'FAIL').Count
    return [pscustomobject][ordered]@{
        profileId = $script:SpecOpsProfileId
        total     = $results.Count
        passed    = $results.Count - $failed
        failed    = $failed
        results   = $results.ToArray()
    }
}

function Get-SpecOpsOrdinalSortedStrings {
    param(
        [AllowEmptyCollection()]
        [Parameter(Mandatory)]
        [string[]] $Values
    )

    $copy = [string[]] $Values.Clone()
    [Array]::Sort($copy, [System.StringComparer]::Ordinal)
    return ,$copy
}

function Test-SpecOpsUniqueIds {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [Parameter(Mandatory)]
        [object[]] $Items,

        [Parameter(Mandatory)]
        [string] $IdProperty
    )

    if ([string]::IsNullOrEmpty($IdProperty)) {
        Throw-SpecOpsInputRejection -RejectionClass 'INVALID_ID_PROPERTY' -Message 'IdProperty must be a non-empty string.'
    }

    $counts = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::Ordinal)
    $missingIndexes = [System.Collections.Generic.List[int]]::new()
    for ($index = 0; $index -lt $Items.Count; $index++) {
        $item = $Items[$index]
        $propertyFound = $false
        $id = $null

        if ($item -is [System.Collections.IDictionary]) {
            if ($item.Contains($IdProperty)) {
                $propertyFound = $true
                $id = $item[$IdProperty]
            }
        }
        elseif ($null -ne $item) {
            $property = $item.PSObject.Properties[$IdProperty]
            if ($null -ne $property) {
                $propertyFound = $true
                $id = $property.Value
            }
        }

        if (-not $propertyFound -or $id -isnot [string] -or [string]::IsNullOrEmpty([string] $id)) {
            $missingIndexes.Add($index)
            continue
        }

        $idText = [string] $id
        if ($counts.ContainsKey($idText)) {
            $counts[$idText]++
        }
        else {
            $counts.Add($idText, 1)
        }
    }

    $duplicates = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $counts.GetEnumerator()) {
        if ($entry.Value -gt 1) {
            $duplicates.Add($entry.Key)
        }
    }
    $duplicateIds = Get-SpecOpsOrdinalSortedStrings -Values $duplicates.ToArray()

    return [pscustomobject][ordered]@{
        IsValid          = ($duplicateIds.Count -eq 0 -and $missingIndexes.Count -eq 0)
        DuplicateIds     = $duplicateIds
        MissingIdIndexes = $missingIndexes.ToArray()
    }
}

function Get-SpecOpsIdCounts {
    param(
        [AllowEmptyCollection()]
        [Parameter(Mandatory)]
        [string[]] $Ids,

        [Parameter(Mandatory)]
        [string] $Side
    )

    $counts = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::Ordinal)
    foreach ($id in $Ids) {
        if ([string]::IsNullOrEmpty($id)) {
            Throw-SpecOpsInputRejection -RejectionClass 'INVALID_ID' -Message "$Side IDs must all be non-empty strings."
        }

        if ($counts.ContainsKey($id)) { $counts[$id]++ }
        else { $counts.Add($id, 1) }
    }
    return $counts
}

function Compare-SpecOpsIdCoverage {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [Parameter(Mandatory)]
        [string[]] $ExpectedIds,

        [AllowEmptyCollection()]
        [Parameter(Mandatory)]
        [string[]] $ActualIds
    )

    $expectedCounts = Get-SpecOpsIdCounts -Ids $ExpectedIds -Side 'Expected'
    $actualCounts = Get-SpecOpsIdCounts -Ids $ActualIds -Side 'Actual'
    $duplicateExpected = [System.Collections.Generic.List[string]]::new()
    $duplicateActual = [System.Collections.Generic.List[string]]::new()
    $missing = [System.Collections.Generic.List[string]]::new()
    $extra = [System.Collections.Generic.List[string]]::new()

    foreach ($entry in $expectedCounts.GetEnumerator()) {
        if ($entry.Value -gt 1) { $duplicateExpected.Add($entry.Key) }
        if (-not $actualCounts.ContainsKey($entry.Key)) { $missing.Add($entry.Key) }
    }
    foreach ($entry in $actualCounts.GetEnumerator()) {
        if ($entry.Value -gt 1) { $duplicateActual.Add($entry.Key) }
        if (-not $expectedCounts.ContainsKey($entry.Key)) { $extra.Add($entry.Key) }
    }

    $missingIds = Get-SpecOpsOrdinalSortedStrings -Values $missing.ToArray()
    $extraIds = Get-SpecOpsOrdinalSortedStrings -Values $extra.ToArray()
    $duplicateExpectedIds = Get-SpecOpsOrdinalSortedStrings -Values $duplicateExpected.ToArray()
    $duplicateActualIds = Get-SpecOpsOrdinalSortedStrings -Values $duplicateActual.ToArray()

    return [pscustomobject][ordered]@{
        IsExact              = ($missingIds.Count -eq 0 -and $extraIds.Count -eq 0 -and $duplicateExpectedIds.Count -eq 0 -and $duplicateActualIds.Count -eq 0)
        MissingIds           = $missingIds
        ExtraIds             = $extraIds
        DuplicateExpectedIds = $duplicateExpectedIds
        DuplicateActualIds   = $duplicateActualIds
    }
}

function Test-SpecOpsOrdinalEqual {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string] $Left,

        [AllowNull()]
        [string] $Right
    )

    return [string]::Equals($Left, $Right, [System.StringComparison]::Ordinal)
}

Export-ModuleMember -Function @(
    'Compare-SpecOpsIdCoverage',
    'ConvertTo-SpecOpsCanonicalJson',
    'Get-SpecOpsErrorMetadata',
    'Get-SpecOpsJsonContentIdentity',
    'Test-SpecOpsContentIdentityProfile',
    'Test-SpecOpsOrdinalEqual',
    'Test-SpecOpsUniqueIds'
)
