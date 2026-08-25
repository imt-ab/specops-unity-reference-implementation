Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Tests = 0
$script:Failures = [System.Collections.Generic.List[string]]::new()
$modulePath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, '..', 'SpecOps.Repository.psm1'))
Import-Module -Name $modulePath -Force -ErrorAction Stop

function Test-Case {
    param([string]$Name,[scriptblock]$Body)
    $script:Tests++
    try { & $Body; [Console]::Out.WriteLine("PASS $Name") }
    catch { $script:Failures.Add("${Name}: $($_.Exception.Message)"); [Console]::Out.WriteLine("FAIL $Name -- $($_.Exception.Message)") }
}

function Assert-True { param([bool]$Value,[string]$Message) if(-not$Value){throw $Message} }
function Assert-Equal { param($Expected,$Actual,[string]$Message) if(-not[string]::Equals([string]$Expected,[string]$Actual,[StringComparison]::Ordinal)){throw "$Message Expected=[$Expected] Actual=[$Actual]"} }
function Invoke-TestGit {
    param([string]$Root,[string[]]$Arguments)
    $output=& git -C $Root @Arguments 2>&1
    if($LASTEXITCODE-ne 0){throw "git $($Arguments -join ' ') failed: $output"}
    return @($output)
}
function Write-TestBytes { param([string]$Path,[byte[]]$Bytes) $parent=[IO.Path]::GetDirectoryName($Path);if(-not[IO.Directory]::Exists($parent)){$null=[IO.Directory]::CreateDirectory($parent)};[IO.File]::WriteAllBytes($Path,$Bytes) }
function Commit-TestRepo { param([string]$Root,[string]$Message) $null=Invoke-TestGit $Root @('add','--all');$null=Invoke-TestGit $Root @('commit','--quiet','-m',$Message) }
function New-TestRepo {
    param([string]$Root)
    $null=[IO.Directory]::CreateDirectory($Root)
    $null=Invoke-TestGit $Root @('init','--quiet')
    $null=Invoke-TestGit $Root @('config','user.email','specops-tests@example.invalid')
    $null=Invoke-TestGit $Root @('config','user.name','SpecOps Tests')
    Write-TestBytes (Join-Path $Root '.gitignore') ([Text.UTF8Encoding]::new($false).GetBytes("ignored/`n"))
    Write-TestBytes (Join-Path $Root '.gitattributes') ([Text.UTF8Encoding]::new($false).GetBytes("*.ps1 text eol=lf`n*.psm1 text eol=lf`n"))
    foreach($path in @('tools/specops/Invoke-SpecOps.ps1','tools/specops/SpecOps.Core.psm1','tools/specops/SpecOps.Repository.psm1','tools/specops/SpecOps.Eval.psm1')){Write-TestBytes (Join-Path $Root $path) ([Text.UTF8Encoding]::new($false).GetBytes("# $path`n"))}
    Write-TestBytes (Join-Path $Root 'data/space and-é.txt') ([byte[]](0,1,2,10,13,255))
    Commit-TestRepo $Root 'initial subject'
}
function Assert-Rejected { param([scriptblock]$Body,[string]$Class) try{&$Body;throw 'Expected rejection did not occur.'}catch{if($_.Exception.Message-eq'Expected rejection did not occur.'){throw};Assert-Equal $Class ([string]$_.Exception.Data['SpecOpsRejectionClass']) 'Unexpected rejection class.'} }

$tempRoot=[IO.Path]::GetFullPath([IO.Path]::Combine([IO.Path]::GetTempPath(),"specops-repository-tests-$([Guid]::NewGuid().ToString('N'))"))
try {
    New-TestRepo $tempRoot
    $adapter=New-SpecOpsGitRepositoryAdapter $tempRoot
    $snapshot=Get-SpecOpsRepositorySnapshot $adapter

    Test-Case 'clean repository accepted' { Assert-True ((Get-SpecOpsRepositoryCleanState $adapter).IsClean) 'Clean subject was rejected.' }
    Test-Case 'exact full revision captured' { Assert-Equal ([string](Invoke-TestGit $tempRoot @('rev-parse','--verify','HEAD^{commit}'))) $snapshot.Revision 'Revision mismatch.';Assert-True ($snapshot.Revision.Length-ge 40) 'Revision is not full length.' }
    Test-Case 'object format captured' { Assert-Equal ([string](Invoke-TestGit $tempRoot @('rev-parse','--show-object-format'))) $snapshot.ObjectFormat 'Object format mismatch.';Assert-Equal "git-commit-$($snapshot.ObjectFormat)" $snapshot.RevisionScheme 'Revision scheme mismatch.' }
    Test-Case 'committed tree captured' { Assert-Equal ([string](Invoke-TestGit $tempRoot @('rev-parse','--verify','HEAD^{tree}'))) $snapshot.Tree 'Tree mismatch.' }
    Test-Case 'NUL inventory preserves complex path' { Assert-True ($snapshot.InventoryByPath.ContainsKey('data/space and-é.txt')) 'Complex path absent.' }
    Test-Case 'repository path identity is ordinal' { Assert-True (-not$snapshot.InventoryByPath.ContainsKey('DATA/space and-é.txt')) 'Path identity was case folded.' }
    Test-Case 'committed blob bytes are exact' { $bytes=Get-SpecOpsRepositoryBlobBytes $snapshot 'data/space and-é.txt';Assert-True ([Convert]::ToHexString($bytes)-ceq'0001020A0DFF') 'Blob bytes changed.' }
    Test-Case 'path traversal rejected' { Assert-Rejected { Assert-SpecOpsRepositoryRelativePath '../escape' } 'REPOSITORY_PATH_INVALID' }
    Test-Case 'rooted path rejected' { Assert-Rejected { Assert-SpecOpsRepositoryRelativePath 'C:/escape' } 'REPOSITORY_PATH_INVALID' }
    Test-Case 'producer implementation bound' { $binding=Test-SpecOpsProducerImplementationBinding $adapter $snapshot @('tools/specops/Invoke-SpecOps.ps1','tools/specops/SpecOps.Core.psm1','tools/specops/SpecOps.Repository.psm1','tools/specops/SpecOps.Eval.psm1');Assert-True $binding.IsBound ($binding.Failures -join ',') }
    Test-Case 'no remote is allowed' { $remotes=@(Invoke-TestGit $tempRoot @('remote'));Assert-Equal 0 $remotes.Count 'Fixture unexpectedly has a remote.';Assert-True ($null-ne(Get-SpecOpsRepositorySnapshot $adapter)) 'No-remote subject rejected.' }
    Test-Case 'detached HEAD is allowed' { $null=Invoke-TestGit $tempRoot @('checkout','--quiet','--detach');Assert-True ($null-ne(Get-SpecOpsRepositorySnapshot $adapter)) 'Detached subject rejected.' }
    Test-Case 'branch name is not subject identity' { $revision=(Get-SpecOpsRepositorySnapshot $adapter).Revision;$null=Invoke-TestGit $tempRoot @('switch','--quiet','-c','renamed-local');Assert-Equal $revision (Get-SpecOpsRepositorySnapshot $adapter).Revision 'Branch name changed subject identity.' }

    Write-TestBytes (Join-Path $tempRoot 'tracked.txt') ([Text.UTF8Encoding]::new($false).GetBytes("base`n"));Commit-TestRepo $tempRoot 'tracked fixture';$baseline=Get-SpecOpsRepositorySnapshot $adapter
    Test-Case 'unstaged tracked modification rejected' { Write-TestBytes (Join-Path $tempRoot 'tracked.txt') ([Text.UTF8Encoding]::new($false).GetBytes("changed`n"));Assert-Rejected { Get-SpecOpsRepositorySnapshot $adapter } 'SUBJECT_NOT_CLEAN';$null=Invoke-TestGit $tempRoot @('restore','tracked.txt') }
    Test-Case 'staged modification rejected' { Write-TestBytes (Join-Path $tempRoot 'tracked.txt') ([Text.UTF8Encoding]::new($false).GetBytes("staged`n"));$null=Invoke-TestGit $tempRoot @('add','tracked.txt');Assert-Rejected { Get-SpecOpsRepositorySnapshot $adapter } 'SUBJECT_NOT_CLEAN';$null=Invoke-TestGit $tempRoot @('restore','--staged','tracked.txt');$null=Invoke-TestGit $tempRoot @('restore','tracked.txt') }
    Test-Case 'tracked deletion rejected' { [IO.File]::Delete((Join-Path $tempRoot 'tracked.txt'));Assert-Rejected { Get-SpecOpsRepositorySnapshot $adapter } 'SUBJECT_NOT_CLEAN';$null=Invoke-TestGit $tempRoot @('restore','tracked.txt') }
    Test-Case 'nonignored untracked rejected' { Write-TestBytes (Join-Path $tempRoot 'new.txt') ([byte[]](1));Assert-Rejected { Get-SpecOpsRepositorySnapshot $adapter } 'SUBJECT_NOT_CLEAN';[IO.File]::Delete((Join-Path $tempRoot 'new.txt')) }
    Test-Case 'ignored-only file allowed' { Write-TestBytes (Join-Path $tempRoot 'ignored/cache.bin') ([byte[]](1,2,3));Assert-True ($null-ne(Get-SpecOpsRepositorySnapshot $adapter)) 'Ignored-only state rejected.' }
    Test-Case 'revision movement detected' { $before=Get-SpecOpsRepositorySnapshot $adapter;Write-TestBytes (Join-Path $tempRoot 'movement.txt') ([byte[]](9));Commit-TestRepo $tempRoot 'move subject';Assert-True (-not(Test-SpecOpsRepositorySnapshotCurrent $adapter $before).IsCurrent) 'Revision movement was not detected.' }
    Test-Case 'producer path missing rejected' { $now=Get-SpecOpsRepositorySnapshot $adapter;$binding=Test-SpecOpsProducerImplementationBinding $adapter $now @('tools/specops/missing.psm1');Assert-True (-not$binding.IsBound) 'Missing producer path was accepted.' }
    Test-Case 'producer canonical-content mismatch rejected' { $now=Get-SpecOpsRepositorySnapshot $adapter;Write-TestBytes (Join-Path $tempRoot 'tools/specops/SpecOps.Eval.psm1') ([Text.UTF8Encoding]::new($false).GetBytes("# changed`n"));$binding=Test-SpecOpsProducerImplementationBinding $adapter $now @('tools/specops/SpecOps.Eval.psm1');Assert-True (-not$binding.IsBound) 'Producer mismatch accepted.';$null=Invoke-TestGit $tempRoot @('restore','tools/specops/SpecOps.Eval.psm1') }
    Test-Case 'checkout line endings use Git canonical equivalence' { $now=Get-SpecOpsRepositorySnapshot $adapter;$path=Join-Path $tempRoot 'tools/specops/Invoke-SpecOps.ps1';$text=[IO.File]::ReadAllText($path).Replace("`r`n","`n").Replace("`n","`r`n");[IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($false));$binding=Test-SpecOpsProducerImplementationBinding $adapter $now @('tools/specops/Invoke-SpecOps.ps1');Assert-True $binding.IsBound ($binding.Failures -join ',');$null=Invoke-TestGit $tempRoot @('restore','tools/specops/Invoke-SpecOps.ps1') }
    Test-Case 'read-only adapter does not move revision or index' { $beforeHead=[string](Invoke-TestGit $tempRoot @('rev-parse','HEAD'));$beforeIndex=(Get-FileHash (Join-Path $tempRoot '.git/index') -Algorithm SHA256).Hash;$null=Get-SpecOpsRepositorySnapshot $adapter;$afterHead=[string](Invoke-TestGit $tempRoot @('rev-parse','HEAD'));$afterIndex=(Get-FileHash (Join-Path $tempRoot '.git/index') -Algorithm SHA256).Hash;Assert-Equal $beforeHead $afterHead 'Adapter moved revision.';Assert-Equal $beforeIndex $afterIndex 'Adapter changed index.' }
}
finally {
    $resolved=[IO.Path]::GetFullPath($tempRoot);$tempPrefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if($resolved.StartsWith($tempPrefix,[StringComparison]::OrdinalIgnoreCase)-and[IO.Directory]::Exists($resolved)){Remove-Item -LiteralPath $resolved -Recurse -Force}
}

[Console]::Out.WriteLine("Repository tests: $($script:Tests); failures: $($script:Failures.Count)")
if($script:Failures.Count-gt 0){$script:Failures|ForEach-Object{[Console]::Out.WriteLine($_)};exit 1}
exit 0
