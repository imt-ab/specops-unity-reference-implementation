Set-StrictMode -Version Latest

$script:Utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)

function Get-SpecOpsRepositoryOrdinalSortedStrings {
    param([AllowEmptyCollection()] [string[]] $Values)
    $result = [string[]]@($Values)
    [Array]::Sort($result, [StringComparer]::Ordinal)
    return $result
}

function New-SpecOpsRepositoryException {
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

function Assert-SpecOpsRepositoryRelativePath {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or
        $Path.Contains([char]0) -or
        $Path.Contains('\') -or
        $Path.StartsWith('/') -or
        [System.IO.Path]::IsPathRooted($Path) -or
        $Path -match '^[A-Za-z]:' -or
        $Path -match '(^|/)\.\.(/|$)' -or
        $Path -match '(^|/)\.(/|$)' -or
        $Path.Contains('//')) {
        throw (New-SpecOpsRepositoryException -Message "Invalid repository-relative path: $Path" -RejectionClass 'REPOSITORY_PATH_INVALID')
    }

    return $Path
}

function Invoke-SpecOpsGitProcess {
    param(
        [Parameter(Mandatory)] [string] $RepositoryRoot,
        [Parameter(Mandatory)] [string[]] $Arguments,
        [int[]] $AllowedExitCodes = @(0)
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = 'git'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.Environment['GIT_TERMINAL_PROMPT'] = '0'
    $startInfo.Environment['LC_ALL'] = 'C'
    $startInfo.Environment['LANG'] = 'C'
    $startInfo.ArgumentList.Add('-C')
    $startInfo.ArgumentList.Add($RepositoryRoot)
    foreach ($argument in $Arguments) {
        $startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw [System.InvalidOperationException]::new('Git process did not start.')
        }

        $stdout = [System.IO.MemoryStream]::new()
        $copyTask = $process.StandardOutput.BaseStream.CopyToAsync($stdout)
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $null = $process.WaitForExit()
        $null = $copyTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $bytes = $stdout.ToArray()

        if ($AllowedExitCodes -notcontains $process.ExitCode) {
            $message = $stderr.Trim()
            if ([string]::IsNullOrEmpty($message)) {
                $message = "Git exited with code $($process.ExitCode)."
            }
            throw (New-SpecOpsRepositoryException -Message $message -RejectionClass 'REPOSITORY_ADAPTER_FAILURE' -ExitCode 4)
        }

        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            StdoutBytes = $bytes
            Stderr = $stderr
        }
    }
    finally {
        $process.Dispose()
    }
}

function ConvertFrom-SpecOpsGitUtf8 {
    param([Parameter(Mandatory)] [byte[]] $Bytes)
    return $script:Utf8Strict.GetString($Bytes)
}

function Invoke-SpecOpsGitText {
    param(
        [Parameter(Mandatory)] [string] $RepositoryRoot,
        [Parameter(Mandatory)] [string[]] $Arguments,
        [int[]] $AllowedExitCodes = @(0)
    )

    $result = Invoke-SpecOpsGitProcess -RepositoryRoot $RepositoryRoot -Arguments $Arguments -AllowedExitCodes $AllowedExitCodes
    return [pscustomobject]@{
        ExitCode = $result.ExitCode
        Text = (ConvertFrom-SpecOpsGitUtf8 -Bytes $result.StdoutBytes).TrimEnd("`r", "`n")
        Stderr = $result.Stderr
    }
}

function Assert-SpecOpsGitAdapter {
    param([Parameter(Mandatory)] $Adapter)
    if ($null -eq $Adapter -or
        -not [string]::Equals([string]$Adapter.AdapterKind, 'Git', [System.StringComparison]::Ordinal) -or
        [string]::IsNullOrEmpty([string]$Adapter.RepositoryRoot)) {
        throw (New-SpecOpsRepositoryException -Message 'Unsupported repository adapter.' -RejectionClass 'REPOSITORY_ADAPTER_UNSUPPORTED' -ExitCode 4)
    }
}

function New-SpecOpsGitRepositoryAdapter {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $RepositoryPath)

    $candidate = [System.IO.Path]::GetFullPath($RepositoryPath)
    $rootResult = Invoke-SpecOpsGitText -RepositoryRoot $candidate -Arguments @('rev-parse', '--show-toplevel')
    $root = [System.IO.Path]::GetFullPath($rootResult.Text)
    return [pscustomobject]@{
        AdapterKind = 'Git'
        RepositoryRoot = $root
    }
}

function Get-SpecOpsRepositoryCleanState {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Adapter)

    Assert-SpecOpsGitAdapter -Adapter $Adapter
    $status = Invoke-SpecOpsGitProcess -RepositoryRoot $Adapter.RepositoryRoot -Arguments @(
        'status', '--porcelain=v2', '-z', '--untracked-files=all', '--ignore-submodules=none'
    )
    $entries = [System.Collections.Generic.List[string]]::new()
    if ($status.StdoutBytes.Length -gt 0) {
        $text = ConvertFrom-SpecOpsGitUtf8 -Bytes $status.StdoutBytes
        foreach ($entry in $text.Split([char]0, [System.StringSplitOptions]::RemoveEmptyEntries)) {
            $entries.Add($entry)
        }
    }

    return [pscustomobject]@{
        IsClean = ($entries.Count -eq 0)
        Entries = @($entries)
    }
}

function ConvertFrom-SpecOpsLsTree {
    param([Parameter(Mandatory)] [byte[]] $Bytes)

    $entries = [System.Collections.Generic.List[object]]::new()
    $byPath = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    if ($Bytes.Length -eq 0) {
        return [pscustomobject]@{ Entries = @(); ByPath = $byPath }
    }

    $text = ConvertFrom-SpecOpsGitUtf8 -Bytes $Bytes
    foreach ($record in $text.Split([char]0, [System.StringSplitOptions]::RemoveEmptyEntries)) {
        $tab = $record.IndexOf("`t", [System.StringComparison]::Ordinal)
        if ($tab -lt 1) {
            throw (New-SpecOpsRepositoryException -Message 'Malformed immutable subject inventory.' -RejectionClass 'REPOSITORY_INVENTORY_INVALID' -ExitCode 4)
        }
        $header = $record.Substring(0, $tab).Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)
        if ($header.Count -ne 3) {
            throw (New-SpecOpsRepositoryException -Message 'Malformed immutable subject inventory header.' -RejectionClass 'REPOSITORY_INVENTORY_INVALID' -ExitCode 4)
        }
        $path = Assert-SpecOpsRepositoryRelativePath -Path $record.Substring($tab + 1)
        if ($byPath.ContainsKey($path)) {
            throw (New-SpecOpsRepositoryException -Message "Duplicate immutable subject path: $path" -RejectionClass 'REPOSITORY_INVENTORY_INVALID' -ExitCode 4)
        }
        $entry = [pscustomobject]@{
            Path = $path
            Mode = $header[0]
            ObjectType = $header[1]
            ObjectId = $header[2]
        }
        $entries.Add($entry)
        $byPath.Add($path, $entry)
    }

    return [pscustomobject]@{ Entries = @($entries); ByPath = $byPath }
}

function Get-SpecOpsRepositorySnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Adapter)

    Assert-SpecOpsGitAdapter -Adapter $Adapter
    $root = $Adapter.RepositoryRoot
    $objectFormat = (Invoke-SpecOpsGitText -RepositoryRoot $root -Arguments @('rev-parse', '--show-object-format')).Text
    if ($objectFormat -notmatch '^[a-z0-9]+$') {
        throw (New-SpecOpsRepositoryException -Message 'Unsupported repository object format.' -RejectionClass 'REPOSITORY_OBJECT_FORMAT_INVALID' -ExitCode 4)
    }
    $revision = (Invoke-SpecOpsGitText -RepositoryRoot $root -Arguments @('rev-parse', '--verify', 'HEAD^{commit}')).Text
    $tree = (Invoke-SpecOpsGitText -RepositoryRoot $root -Arguments @('rev-parse', '--verify', 'HEAD^{tree}')).Text
    $cleanState = Get-SpecOpsRepositoryCleanState -Adapter $Adapter
    if (-not $cleanState.IsClean) {
        throw (New-SpecOpsRepositoryException -Message 'Repository subject contains staged, tracked, or nonignored untracked changes.' -RejectionClass 'SUBJECT_NOT_CLEAN')
    }
    $inventoryResult = Invoke-SpecOpsGitProcess -RepositoryRoot $root -Arguments @('ls-tree', '-r', '-z', '--full-tree', $revision)
    $inventory = ConvertFrom-SpecOpsLsTree -Bytes $inventoryResult.StdoutBytes

    return [pscustomobject]@{
        AdapterKind = 'Git'
        RepositoryRoot = $root
        RevisionScheme = "git-commit-$objectFormat"
        ObjectFormat = $objectFormat
        Revision = $revision
        Tree = $tree
        Inventory = $inventory.Entries
        InventoryByPath = $inventory.ByPath
    }
}

function Get-SpecOpsRepositoryPaths {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Snapshot)
    return @($Snapshot.Inventory | ForEach-Object { $_.Path })
}

function Test-SpecOpsRepositoryPathExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Snapshot,
        [Parameter(Mandatory)] [string] $Path
    )

    if ([string]::Equals($Path, '.', [System.StringComparison]::Ordinal)) {
        return $true
    }
    $normalized = Assert-SpecOpsRepositoryRelativePath -Path $Path.TrimEnd('/')
    if ($Snapshot.InventoryByPath.ContainsKey($normalized)) {
        return $true
    }
    $prefix = "$normalized/"
    foreach ($candidate in $Snapshot.InventoryByPath.Keys) {
        if ($candidate.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
            return $true
        }
    }
    return $false
}

function Get-SpecOpsRepositoryBlobBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Snapshot,
        [Parameter(Mandatory)] [string] $Path
    )

    $normalized = Assert-SpecOpsRepositoryRelativePath -Path $Path
    if (-not $Snapshot.InventoryByPath.ContainsKey($normalized)) {
        throw (New-SpecOpsRepositoryException -Message "Subject path does not exist: $normalized" -RejectionClass 'SUBJECT_PATH_NOT_FOUND')
    }
    $entry = $Snapshot.InventoryByPath[$normalized]
    if (-not [string]::Equals([string]$entry.ObjectType, 'blob', [System.StringComparison]::Ordinal)) {
        throw (New-SpecOpsRepositoryException -Message "Subject path is not a blob: $normalized" -RejectionClass 'SUBJECT_PATH_NOT_BLOB')
    }
    return (Invoke-SpecOpsGitProcess -RepositoryRoot $Snapshot.RepositoryRoot -Arguments @('cat-file', 'blob', $entry.ObjectId)).StdoutBytes
}

function Test-SpecOpsProducerImplementationBinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Adapter,
        [Parameter(Mandatory)] $Snapshot,
        [Parameter(Mandatory)] [string[]] $Paths
    )

    Assert-SpecOpsGitAdapter -Adapter $Adapter
    $failures = [System.Collections.Generic.List[string]]::new()
    foreach ($path in $Paths) {
        $normalized = Assert-SpecOpsRepositoryRelativePath -Path $path
        if (-not $Snapshot.InventoryByPath.ContainsKey($normalized)) {
            $failures.Add("missing:$normalized")
            continue
        }
        $entry = $Snapshot.InventoryByPath[$normalized]
        if (-not [string]::Equals([string]$entry.ObjectType, 'blob', [System.StringComparison]::Ordinal)) {
            $failures.Add("not-blob:$normalized")
            continue
        }
        $absolute = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($Adapter.RepositoryRoot, $normalized.Replace('/', [System.IO.Path]::DirectorySeparatorChar)))
        $rootPrefix = $Adapter.RepositoryRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
        if (-not $absolute.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or -not [System.IO.File]::Exists($absolute)) {
            $failures.Add("working-path-missing:$normalized")
            continue
        }
        $actualObject = (Invoke-SpecOpsGitText -RepositoryRoot $Adapter.RepositoryRoot -Arguments @('hash-object', "--path=$normalized", '--', $absolute)).Text
        if (-not [string]::Equals($actualObject, [string]$entry.ObjectId, [System.StringComparison]::Ordinal)) {
            $failures.Add("content-mismatch:$normalized")
        }
    }

    return [pscustomobject]@{
        IsBound = ($failures.Count -eq 0)
        Failures = @(Get-SpecOpsRepositoryOrdinalSortedStrings $failures.ToArray())
    }
}

function Test-SpecOpsRepositorySnapshotCurrent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Adapter,
        [Parameter(Mandatory)] $Snapshot
    )

    Assert-SpecOpsGitAdapter -Adapter $Adapter
    $revision = (Invoke-SpecOpsGitText -RepositoryRoot $Adapter.RepositoryRoot -Arguments @('rev-parse', '--verify', 'HEAD^{commit}')).Text
    $tree = (Invoke-SpecOpsGitText -RepositoryRoot $Adapter.RepositoryRoot -Arguments @('rev-parse', '--verify', 'HEAD^{tree}')).Text
    $clean = Get-SpecOpsRepositoryCleanState -Adapter $Adapter
    return [pscustomobject]@{
        IsCurrent = ($clean.IsClean -and
            [string]::Equals($revision, [string]$Snapshot.Revision, [System.StringComparison]::Ordinal) -and
            [string]::Equals($tree, [string]$Snapshot.Tree, [System.StringComparison]::Ordinal))
        RevisionMatches = [string]::Equals($revision, [string]$Snapshot.Revision, [System.StringComparison]::Ordinal)
        TreeMatches = [string]::Equals($tree, [string]$Snapshot.Tree, [System.StringComparison]::Ordinal)
        IsClean = $clean.IsClean
        DirtyEntries = $clean.Entries
    }
}

Export-ModuleMember -Function @(
    'Assert-SpecOpsRepositoryRelativePath',
    'Get-SpecOpsRepositoryBlobBytes',
    'Get-SpecOpsRepositoryCleanState',
    'Get-SpecOpsRepositoryPaths',
    'Get-SpecOpsRepositorySnapshot',
    'New-SpecOpsGitRepositoryAdapter',
    'Test-SpecOpsProducerImplementationBinding',
    'Test-SpecOpsRepositoryPathExists',
    'Test-SpecOpsRepositorySnapshotCurrent'
)
