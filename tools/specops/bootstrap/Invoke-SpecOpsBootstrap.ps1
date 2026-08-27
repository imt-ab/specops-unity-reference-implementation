Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$VerbosePreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'
$InformationPreference = 'SilentlyContinue'

$utf8 = [Text.UTF8Encoding]::new($false, $true)
$exitCode = 70
$stdoutBytes = $null
$diagnostic = $null

try {
    $modulePath = [IO.Path]::Combine([IO.Path]::GetDirectoryName($PSCommandPath), 'SpecOps.Bootstrap.psm1')
    Import-Module -Name $modulePath -Force -ErrorAction Stop
    $execution = Invoke-SpecOpsBootstrapExecution -RawArguments ([string[]]$args) -ImplementationScriptPath $PSCommandPath
    $exitCode = [int]$execution.ExitCode
    $stdoutBytes = [byte[]]$execution.StdoutBytes
    $diagnostic = [string]$execution.Diagnostic
}
catch {
    $diagnostic = "Internal bootstrap entry-point failure: $($_.Exception.Message)"
    $stdoutBytes = $utf8.GetBytes('{"exitCode":70,"failureClass":"INTERNAL_INVARIANT","phase":"internal","status":"FAILURE"}' + "`n")
}

if ($diagnostic) { [Console]::Error.WriteLine($diagnostic) }
$stdout = [Console]::OpenStandardOutput()
$stdout.Write($stdoutBytes, 0, $stdoutBytes.Length)
$stdout.Flush()
exit $exitCode
