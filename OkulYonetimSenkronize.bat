@echo off
setlocal EnableExtensions
chcp 65001 >nul
title ElpiOkulYonetim - Guvenli GitHub Senkronizasyon V21
rem SYNC_VERSION: 21
rem V21: AL cakismasiz fast-forward; YAZ sadece onizlenen uygun dosyalari gonderir.
rem Ana OkulYonetimSenkronize.bat dosyasi da acik YAZ onayiyla guncellenebilir.
rem Otomatik reset, stash, rebase, force-push veya remote degisikligi YAPMAZ.
set "SYNC_BAT=%~f0"
set "SYNC_PS=%TEMP%\ElpiOkulYonetim_Sync_V21_%RANDOM%_%RANDOM%.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $s=[IO.File]::ReadAllText($env:SYNC_BAT); $m=[regex]::Match($s,'(?m)^#===POWERSHELL_BASLANGIC===\r?$'); if(!$m.Success){throw 'Gomulu betik bulunamadi'}; [IO.File]::WriteAllText($env:SYNC_PS,$s.Substring($m.Index+$m.Length),[Text.UTF8Encoding]::new($true))"
if errorlevel 1 goto FAIL
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SYNC_PS%"
set "SYNC_EXIT=%ERRORLEVEL%"
del /q "%SYNC_PS%" >nul 2>&1
echo.
pause
exit /b %SYNC_EXIT%
:FAIL
if exist "%SYNC_PS%" del /q "%SYNC_PS%" >nul 2>&1
echo [HATA] Betik hazirlanamadi.
pause
exit /b 1
#===POWERSHELL_BASLANGIC===
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$repo = [IO.Path]::GetFullPath((Split-Path -Parent $env:SYNC_BAT)).TrimEnd('\')
$expectedRemote = 'https://github.com/nurkansirma2-hue/ElpiOkulYonetim.git'
$allowedRemotes = @($expectedRemote, 'git@github.com:nurkansirma2-hue/ElpiOkulYonetim.git')
$reportDir = Join-Path $env:LOCALAPPDATA 'OkulYonetim\SyncReports'
$log = [Collections.Generic.List[string]]::new()
$step = 'Baslangic'
$exitCode = 1
function Note([string]$t) { Write-Host $t; $log.Add($t) }
function RunGit([string[]]$GitArgs) {
    $oldPref = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $out = @(& git.exe -c core.quotepath=false @GitArgs 2>&1 | ForEach-Object { $_.ToString() })
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $oldPref }
    if ($code -ne 0) { throw ('Git basarisiz: git ' + ($GitArgs -join ' ') + ' | ' + ($out -join ' ')) }
    return $out
}
function GitText([string[]]$GitArgs) { return ((RunGit -GitArgs $GitArgs) -join "`n").Trim() }
function CheckBusy {
    foreach ($key in @('rebase-merge','rebase-apply','MERGE_HEAD','CHERRY_PICK_HEAD','REVERT_HEAD','BISECT_LOG')) {
        $path = GitText -GitArgs @('rev-parse','--git-path',$key)
        if (Test-Path -LiteralPath $path) { throw 'Devam eden Git islemi var; hicbir degisiklik yapilmadi.' }
    }
}
function Forbidden([string]$path) {
    $p = $path.Replace('\','/')
    return $p -match '(?i)(^|/)(\.env[^/]*|key\.properties|[^/]+\.(jks|keystore|p12|pfx|pem|key)|id_rsa|id_ed25519)$' -or
        $p -match '(?i)(^|/)(build|\.dart_tool|\.gradle|\.elpi-git-backups|\.codex-remote-attachments|work)/' -or
        $p -match '(?i)\.(apk|aab|ipa|bak|tmp)$' -or
        $p -match '(?i)(^|/)(android/local\.properties|Thumbs\.db|\.DS_Store)$' -or
        $p -match '(?i)^elpi_okul_yonetim/' -or
        $p -match '(?i)^(linux|windows)/flutter/generated_plugin_registrant\.(cc|h)$' -or
        $p -match '(?i)^(linux|windows)/flutter/generated_plugins\.cmake$' -or
        ($p -match '(?i)^OkulYonetimSenkronize_Guvenli_V[0-9]+\.bat$')
}
function RemoteHead([string]$branch) {
    $results = @(RunGit -GitArgs @('ls-remote','--heads','origin',('refs/heads/' + $branch)))
    if ($results.Count -ne 1) { throw ('GitHub uzerinde ' + $branch + ' dali bulunamadi; otomatik dal/depo olusturulmadi.') }
    return (($results[0] -split "`t",2)[0]).Trim()
}
try {
    if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) { throw 'Git for Windows bulunamadi.' }
    if (-not (Test-Path -LiteralPath (Join-Path $repo 'pubspec.yaml') -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $repo 'lib') -PathType Container)) {
        throw 'BAT dosyasini Flutter proje kokune (pubspec.yaml ve lib yanina) koyun.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $repo '.git'))) { throw 'Git deposu bulunamadi; otomatik git init yapilmadi.' }
    Set-Location -LiteralPath $repo
    $top = GitText -GitArgs @('rev-parse','--show-toplevel')
    if ([IO.Path]::GetFullPath($top).TrimEnd('\') -ine $repo) { throw 'Beklenmeyen Git proje koku.' }
    CheckBusy
    $branch = GitText -GitArgs @('branch','--show-current')
    if (-not $branch) { throw 'Aktif dal bulunamadi (detached HEAD).' }
    $origin = GitText -GitArgs @('remote','get-url','origin')
    if ($origin -notin $allowedRemotes) { throw ('Origin beklenen depo degil: ' + $origin) }
    $pushUrls = @(RunGit -GitArgs @('remote','get-url','--push','--all','origin'))
    if ($pushUrls.Count -ne 1 -or $pushUrls[0] -notin $allowedRemotes) { throw 'Push adresi beklenen GitHub deposu degil.' }
    $step = 'Onizleme'
    Note '=== GUVENLI ONIZLEME: HENUZ PROJE DOSYALARI/GIT KAYDI DEGISTIRILMEDI ==='
    Note ('Yerel proje: ' + $repo)
    Note ('GitHub adresi: ' + $origin)
    Note ('Aktif dal: ' + $branch)
    $status = @(RunGit -GitArgs @('status','--short','--untracked-files=all'))
    Note ('Yerel degisiklik satiri: ' + $status.Count)
    foreach ($line in $status) { Note ('  ' + $line) }
    $staged = @(RunGit -GitArgs @('diff','--cached','--name-only','--no-renames')) | Where-Object { $_ }
    $unstaged = @(RunGit -GitArgs @('diff','--name-only','--no-renames')) | Where-Object { $_ }
    $untracked = @(RunGit -GitArgs @('ls-files','--others','--exclude-standard')) | Where-Object { $_ }
    $changed = @($staged + $unstaged + $untracked | Sort-Object -Unique)
    if (@($changed | Where-Object { $_.StartsWith('"') -or $_ -match '[
	]' }).Count) {
        throw 'Ozel karakterli/quoted dosya adlari var; elle inceleme gerekli.'
    }
    $blockedStaged = @($staged | Where-Object { Forbidden $_ })
    $trackedChanges = @($staged + $unstaged | Sort-Object -Unique)
    $blockedTracked = @($trackedChanges | Where-Object { Forbidden $_ })
    $excluded = @($changed | Where-Object { Forbidden $_ })
    $eligible = @($changed | Where-Object { -not (Forbidden $_) })
    if ($excluded.Count) { Note ('HARIC/KORUMALI: ' + ($excluded -join ', ')) }
    Note ('Gonderime uygun degisen dosya sayisi: ' + $eligible.Count)
    foreach ($path in $eligible) { Note ('  UYGUN: ' + $path + $(if ($staged -ccontains $path) { ' [STAGED]' } else { '' })) }
    $deleted = @(RunGit -GitArgs @('diff','--name-only','--diff-filter=D','HEAD'))
    if ($deleted.Count -ge 20) { throw '20 veya daha fazla takip edilen dosya silinmis; elle inceleme gerekir.' }
    $remoteBefore = RemoteHead $branch
    $localHead = GitText -GitArgs @('rev-parse','HEAD')
    Note ('Yerel HEAD: ' + $localHead)
    Note ('GitHub HEAD: ' + $remoteBefore)
    Note 'GitHub -> Yerel: Yerel degisiklikler korunarak, yalniz cakismasiz fast-forward; YAZ yetkisi sayilmaz.'
    Note 'Yerel -> GitHub: Yalniz UYGUN dosyalar, mevcut staged dahil; YAZ onayi zorunlu.'
    Note 'Reset, rebase, stash, force push, git clean ve otomatik silme YOK.'
    # Remote commit local object database'de yoksa merge-base sonucuna guvenmeyiz.
    # AL, fetch sonrasi --ff-only ile yerel degisiklikleri korur.
    if ($remoteBefore -ne $localHead) {
        Note 'FARKLI HEAD: GitHub degisiklikleri varsa AL ile fast-forward denenebilir; ayrisma varsa durur.'
    }
    $answer = (Read-Host 'Secim: GitHub dan guncellemek icin AL / Yereli gondermek icin YAZ / vazgec Enter').Trim()
    if ($answer -ceq 'AL') {
        $step = 'AL oncesi kontrol'
        # Yereldeki alakasiz makine dosyalari ve takip edilen dosyalar korunur.
        # Cakisma kontrolu fetch sonrasi GitHub'dan gelen gercek dosya listesine gore yapilir.
        CheckBusy
        if ((GitText -GitArgs @('rev-parse','HEAD')) -ne $localHead) { throw 'Yerel HEAD onizlemeden sonra degisti.' }
        if ((RemoteHead $branch) -ne $remoteBefore) { throw 'GitHub onizlemeden sonra degisti; yeniden calistirin.' }
        $step = 'GitHub fetch'
        RunGit -GitArgs @('fetch','--no-tags','origin',('refs/heads/' + $branch)) | Out-Null
        $fetchHead = GitText -GitArgs @('rev-parse','FETCH_HEAD')
        if ($fetchHead -ne $remoteBefore) { throw 'Fetch sonucu beklenen commit degil; birlestirme yapilmadi.' }
        & git.exe merge-base --is-ancestor $localHead $fetchHead
        if ($LASTEXITCODE -ne 0) { throw 'Git gecmisleri ayrismis (fast-forward mumkun degil); merge/rebase yapilmadi.' }
        $step = 'Cakisma kontrolu'
        # GitHub tarafindan degisecek dosyalar ve yerel staged/unstaged/untracked dosyalar
        # ayniysa (veya dosya/klasor yolu cakisiyorsa) en ufak riskte dur.
        $incoming = @(RunGit -GitArgs @('diff','--name-only','--no-renames',$localHead,$fetchHead)) | Where-Object { $_ }
        $currentTracked = @(@(RunGit -GitArgs @('diff','--cached','--name-only','--no-renames')) + @(RunGit -GitArgs @('diff','--name-only','--no-renames')) | Where-Object { $_ })
        $currentUntracked = @(RunGit -GitArgs @('ls-files','--others','--exclude-standard')) | Where-Object { $_ }
        $localPaths = @($currentTracked + $currentUntracked | Sort-Object -Unique)
        $conflicts = @(
            foreach ($remotePath in $incoming) {
                $normalizedRemote = $remotePath.Replace('\','/')
                foreach ($localPath in $localPaths) {
                    $normalizedLocal = $localPath.Replace('\','/')
                    if ($normalizedRemote -ieq $normalizedLocal -or
                        $normalizedRemote.StartsWith(($normalizedLocal + '/'),[StringComparison]::OrdinalIgnoreCase) -or
                        $normalizedLocal.StartsWith(($normalizedRemote + '/'),[StringComparison]::OrdinalIgnoreCase)) {
                        $remotePath
                        break
                    }
                }
            }
        )
        if ($conflicts.Count) {
            Note ('CAKISAN DOSYALAR: ' + ($conflicts -join ', '))
            throw 'GitHub guncellemesi yerelde degistirilmis dosyalarla cakisiyor. Yerel dosyalar korundu.'
        }
        if ((GitText -GitArgs @('rev-parse','HEAD')) -ne $localHead) { throw 'Yerel HEAD fetch sonrasinda degisti.' }
        if ((RemoteHead $branch) -ne $remoteBefore) { throw 'GitHub fetch sonrasi degisti; birlestirme yapilmadi.' }
        Note ('GitHub dan degisecek dosya: ' + $incoming.Count + '; yerel degisiklikler korunuyor.')
        $step = 'Fast-forward'
        # Git, indeks ve izlenmeyen dosyalar acisindan ek guvenlik kontrolu de yapar.
        # Cakisma tespit ederse --ff-only islemi hata verir; reset/stash/clean uygulanmaz.
        RunGit -GitArgs @('merge','--ff-only','FETCH_HEAD') | Out-Host
        Note ('BASARILI: GitHub guncellemeleri yerel ' + $branch + ' dalina alindi.')
        Note 'NOT: Calisan BAT dosyasi guncellendiyse sonraki calistirmada yeni kod devreye girer.'
        $exitCode = 0
    }
    elseif ($answer -ceq 'YAZ') {
        $step = 'YAZ oncesi kontrol'
        if ($blockedTracked.Count) { throw ('Takip edilen korumali dosyalar degismis: ' + ($blockedTracked -join ', ')) }
        if ($blockedStaged.Count) { throw ('Staging alaninda korumali dosya var: ' + ($blockedStaged -join ', ')) }
        CheckBusy
        if ((GitText -GitArgs @('rev-parse','HEAD')) -ne $localHead) { throw 'HEAD onizlemeden sonra degisti.' }
        if ((RemoteHead $branch) -ne $remoteBefore) { throw 'GitHub onizlemeden sonra degisti.' }
        # Yalniz gonderilebilir dosyalari karsilastir. Gradle/Flutter tarafindan
        # anlik olusturulan HARIC dosyalar YAZ islemini gereksiz durdurmasin.
        # Staging alani ise tam olarak onizlemede oldugu gibi kalmalidir.
        $stagedNow = @(RunGit -GitArgs @('diff','--cached','--name-only','--no-renames')) | Where-Object { $_ }
        if (($stagedNow -join "`n") -cne ($staged -join "`n")) { throw 'Staging listesi onizlemeden sonra degisti.' }
        $unstagedNow = @(RunGit -GitArgs @('diff','--name-only','--no-renames')) | Where-Object { $_ }
        $untrackedNow = @(RunGit -GitArgs @('ls-files','--others','--exclude-standard')) | Where-Object { $_ }
        $currentChanged = @($stagedNow + $unstagedNow + $untrackedNow | Sort-Object -Unique)
        $currentEligible = @($currentChanged | Where-Object { -not (Forbidden $_) })
        if (($currentEligible -join "`n") -cne ($eligible -join "`n")) {
            throw 'Gonderilebilir dosya listesi degisti; yeniden calistirin.'
        }
        $currentBlockedTracked = @($stagedNow + $unstagedNow | Sort-Object -Unique | Where-Object { Forbidden $_ })
        if ($currentBlockedTracked.Count) { throw ('Takip edilen korumali dosyalar degismis: ' + ($currentBlockedTracked -join ', ')) }
        # Uzak HEAD yerelde yoksa gonderime izin verme: once AL ile guncelleme alinmali.
        & git.exe cat-file -e ($remoteBefore + '^{commit}') 2>$null
        if ($LASTEXITCODE -ne 0) { throw 'GitHub commit yerelde bilinmiyor; once guvenli AL veya ayri inceleme gerekir.' }
        & git.exe merge-base --is-ancestor $remoteBefore HEAD
        if ($LASTEXITCODE -ne 0) { throw 'GitHub, yerel HEAD atasi degil. Once AL/ayri inceleme gerekli.' }
        $pending = [int](GitText -GitArgs @('rev-list','--count',($remoteBefore + '..HEAD')))
        Note ('GitHub icin bekleyen yerel commit: ' + $pending)
        if ($pending -gt 0) {
            $pendingPaths = @(RunGit -GitArgs @('log','--format=','--name-only','--no-renames',($remoteBefore + '..HEAD'))) | Where-Object { $_ }
            if (@($pendingPaths | Where-Object { Forbidden $_ }).Count) { throw 'Bekleyen commit gecmisinde korumali dosyalar var; gonderim durduruldu.' }
            $objects = @(RunGit -GitArgs @('rev-list','--objects',($remoteBefore + '..HEAD')))
            foreach ($entry in $objects) {
                $oid = ($entry -split ' ',2)[0]
                if ((GitText -GitArgs @('cat-file','-t',$oid)) -eq 'blob' -and [long](GitText -GitArgs @('cat-file','-s',$oid)) -ge 100000000L) {
                    throw ('Gonderilecek gecmiste 100 MB veya buyuk dosya var: ' + $oid)
                }
            }
        }
        if ($pending -eq 0 -and $eligible.Count -eq 0) {
            Note 'Gonderilecek degisiklik yok.'
            $exitCode = 0
        } else {
            # YAZ secimi onizlemede gorunen silmeleri de kapsar. Yine de ikinci onay iste.
            $confirm = (Read-Host ('ONAY: ' + $eligible.Count + ' uygun dosya (staged dahil) ve bekleyen commitleri GitHub a gondermek icin tekrar YAZ yazin')).Trim()
            if ($confirm -cne 'YAZ') { Note 'IPTAL: GitHub a gonderim yapilmadi.'; $exitCode = 0 }
            else {
                if ((RemoteHead $branch) -ne $remoteBefore) { throw 'GitHub onay sirasinda degisti.' }
                $step = 'Git add/commit'
                foreach ($path in $eligible) { RunGit -GitArgs @('add','-A','--',$path) | Out-Null }
                $stagedPaths = @(RunGit -GitArgs @('diff','--cached','--name-only','--no-renames')) | Where-Object { $_ }
                if (@($stagedPaths | Where-Object { Forbidden $_ }).Count) { throw 'Staging alanina korumali dosya girdi; push yapilmadi.' }
                & git.exe diff --cached --quiet
                if ($LASTEXITCODE -eq 1) {
                    RunGit -GitArgs @('commit','-m',('Onayli cift yonlu senkronizasyon - ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))) | Out-Host
                    Note 'Yerel commit olusturuldu.'
                } elseif ($LASTEXITCODE -ne 0) { throw 'Commit oncesi diff kontrolu basarisiz.' }
                $step = 'Push'
                RunGit -GitArgs @('push','origin',('HEAD:refs/heads/' + $branch)) | Out-Host
                Note ('BASARILI: GitHub a normal push tamamlandi. Dal: ' + $branch)
                $exitCode = 0
            }
        }
    } else {
        Note 'IPTAL: Herhangi bir fetch/merge/add/commit/push yapilmadi.'
        $exitCode = 0
    }
} catch {
    Note ('DURDURULDU (' + $step + '): ' + $_.Exception.Message)
    Note 'Yerel dosyalar otomatik silinmedi, resetlenmedi, stash uygulanmadi veya force push yapilmadi.'
} finally {
    try {
        New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
        $report = Join-Path $reportDir ('Guvenli_Senkronizasyon_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff') + '.txt')
        $log.Add('Rapor: ' + $report)
        [IO.File]::WriteAllLines($report,$log,[Text.UTF8Encoding]::new($true))
        Write-Host ('Rapor: ' + $report)
    } catch { Write-Host ('Rapor kaydi olusturulamadi: ' + $_.Exception.Message) }
}
exit $exitCode
