# Install Rider Live Templates (Prompts) + C# Test Scaffolds (DotSettings)
# Rider 2025.3.x – Windows
# Usage: Right-click this file → Run with PowerShell, then restart Rider.

$ErrorActionPreference = "Stop"

# Script directory = folder where this script lives
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ----------------------------
# 1) Install IntelliJ templateSet XML (Prompts / Other Languages)
# ----------------------------
$xmlSource = Join-Path $scriptDir "RiderLiveTemplates-Enterprise.xml"
if (!(Test-Path $xmlSource)) {
    throw "Template XML not found next to script: $xmlSource"
}

$intellijTargetDir = Join-Path $env:APPDATA "JetBrains\Rider2025.3\templates"
$intellijTarget    = Join-Path $intellijTargetDir "RiderLiveTemplates-Enterprise.xml"

New-Item -ItemType Directory -Force -Path $intellijTargetDir | Out-Null
Copy-Item -Force $xmlSource $intellijTarget

# ----------------------------
# 2) Install ReSharper/Rider C# Live Templates (DotSettings team-shared layer)
# ----------------------------
$dotSource = Join-Path $scriptDir "RiderLiveTemplates-CSharpTests.DotSettings"
if (!(Test-Path $dotSource)) {
    throw "DotSettings file not found next to script: $dotSource"
}

function Find-SolutionFile([string]$startDir) {
    $dir = Get-Item $startDir
    while ($dir -ne $null) {
        $sln = Get-ChildItem -Path $dir.FullName -Filter *.sln -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($sln) { return $sln.FullName }
        $dir = $dir.Parent
    }
    return $null
}

$slnPath = Find-SolutionFile $scriptDir
if (-not $slnPath) {
    throw "Could not find a .sln file by searching parent directories from: $scriptDir"
}

# Team-shared settings layer is the <Solution>.sln.DotSettings file next to the solution.
$teamSharedTarget = "$slnPath.DotSettings"

Copy-Item -Force $dotSource $teamSharedTarget

Write-Host ""
Write-Host "Installed successfully:"
Write-Host "  Prompts (IntelliJ templateSet XML): $intellijTarget"
Write-Host "  C# Test scaffolds (Team-shared DotSettings): $teamSharedTarget"
Write-Host ""
Write-Host "Restart Rider to load the updated templates."
