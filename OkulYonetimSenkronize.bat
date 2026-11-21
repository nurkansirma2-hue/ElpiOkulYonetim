@echo off
setlocal EnableExtensions
chcp 65001 >nul
title ElpiOkulYonetim - Guvenli GitHub Senkronizasyon V18
rem SYNC_VERSION: 18
rem Bu surum inceleme + acik YAZ onayiyla GITHUB'A GONDERME icindir.
rem GitHub'dan otomatik pull/rebase, reset, stash, git init veya remote degisikligi YAPMAZ.
set "SYNC_BAT=%~f0"
set "SYNC_PS=%TEMP%\ElpiOkulYonetim_Sync_V18_%RANDOM%_%RANDOM%.ps1"
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
        ($p -match '(?i)^OkulYonetimSenkronize_Guvenli_V[0-9]+\.bat$' -and $p -ine 'OkulYonetimSenkronize_Guvenli_V18.bat')
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
    # Mevcut staging'e dokunulmaz.
    & git.exe diff --cached --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Staging alaninda onceden hazirlanmis dosyalar var; korunarak durduruldu.' }
    $step = 'Onizleme'
    Note '=== SALT OKUNUR ONIZLEME: HENUZ HICBIR DOSYA/GIT KAYDI DEGISTIRILMEDI ==='
    Note ('Yerel proje: ' + $repo)
    Note ('Islem yonu: YEREL -> GITHUB (' + $branch + ')')
    Note ('GitHub adresi: ' + $origin)
    $status = @(RunGit -GitArgs @('status','--short','--untracked-files=all'))
    Note ('Yerel degisiklik satiri: ' + $status.Count)
    foreach ($line in $status) { Note ('  ' + $line) }
    $changed = @(RunGit -GitArgs @('ls-files','--modified','--deleted','--others','--exclude-standard')) | Where-Object { $_ }
    if (@($changed | Where-Object { $_.StartsWith('"') -or $_ -match '[\r\n\t]' }).Count) {
        throw 'Kontrol karakterli veya Git tarafindan tirnaklanan dosya adi var; guvenli inceleme icin durduruldu.'
    }
    # Yalniz takip EDILMEYEN uretilmis dosyalari sessizce degil, raporlayarak haric tut.
    # Onceden Git tarafindan izlenen riskli dosyalara dokunma; inceleme icin durdur.
    $trackedChanges = @(RunGit -GitArgs @('ls-files','--modified','--deleted')) | Where-Object { $_ }
    $blockedTracked = @($trackedChanges | Where-Object { Forbidden $_ })
    $excluded = @($changed | Where-Object { Forbidden $_ })
    $eligible = @($changed | Where-Object { -not (Forbidden $_) })
    if ($excluded.Count) { Note ('HARIC TUTULAN (gonderilmeyecek) dosyalar: ' + ($excluded -join ', ')) }
    Note ('Gonderime uygun degisen dosya sayisi: ' + $eligible.Count)
    foreach ($path in $eligible) { Note ('  UYGUN: ' + $path) }
    $deleted = @(RunGit -GitArgs @('ls-files','--deleted'))
    if ($deleted.Count -ge 20) { throw '20 veya daha fazla takip edilen dosya silinmis; toplu silme riski nedeniyle durduruldu.' }
    $remoteBefore = RemoteHead $branch
    $localHead = GitText -GitArgs @('rev-parse','HEAD')
    Note ('Yerel HEAD: ' + $localHead)
    Note ('GitHub HEAD: ' + $remoteBefore)
    Note 'UYARI: Bu arac otomatik pull, rebase, reset, stash, force push veya dal degisikligi YAPMAZ.'
    Note 'UYARI: Islemden once yerel farklar ve eski commitler incelenmelidir.'
    Note 'UYARI: YAZ onayindan sonra yeni commit ve normal push yapilabilir.'
    if ($blockedTracked.Count) { throw ('Git tarafindan takip edilen korumali dosyalar degismis; inceleme gerekli: ' + ($blockedTracked -join ', ')) }
    # Once uzak dalin yerelde bilinen ve HEAD ile uyumlu olmasini sagla.
    # fetch sadece uzak izleme referansini degistirir; onay oncesi bunu da YAPMIYORUZ.
    $knownRemote = @(& git.exe rev-parse --verify --quiet ('refs/remotes/origin/' + $branch) 2>$null)
    if ($LASTEXITCODE -ne 0 -or $knownRemote.Count -ne 1 -or $knownRemote[0].Trim() -ne $remoteBefore) {
        throw 'GitHub dali yereldeki origin referansi ile ayni degil. Guvenli olarak durduruldu; once ayri inceleme/senkronizasyon gerekiyor.'
    }
    & git.exe merge-base --is-ancestor $remoteBefore HEAD
    if ($LASTEXITCODE -ne 0) { throw 'GitHub degisiklikleri yerelde yok veya tarih ayrismis. Pull/rebase otomatik yapilmadi.' }
    $pending = [int](GitText -GitArgs @('rev-list','--count',($remoteBefore + '..HEAD')))
    Note ('GitHub icin bekleyen yerel commit: ' + $pending)
    if ($pending -gt 0) {
        # Olasi sirlarin veya 100 MB bloblarin onceki commitlerden yuklenmesini engelle.
        $pendingPaths = @(RunGit -GitArgs @('log','--format=','--name-only','--no-renames',($remoteBefore + '..HEAD'))) | Where-Object { $_ }
        $badHistory = @($pendingPaths | Where-Object { Forbidden $_ })
        if ($badHistory.Count) { throw ('Gonderilmeyi bekleyen Git gecmisinde yasakli dosya var: ' + ($badHistory -join ', ')) }
        $objects = @(RunGit -GitArgs @('rev-list','--objects',($remoteBefore + '..HEAD')))
        foreach ($entry in $objects) {
            $oid = ($entry -split ' ',2)[0]
            if ((GitText -GitArgs @('cat-file','-t',$oid)) -eq 'blob' -and [long](GitText -GitArgs @('cat-file','-s',$oid)) -ge 100000000L) {
                throw ('Gonderilecek gecmiste 100 MB veya buyuk blob var: ' + $oid)
            }
        }
    }
    if ($pending -eq 0 -and $eligible.Count -eq 0) { Note 'Degisiklik yok. Gonderim gerekmiyor.'; $exitCode = 0 }
    else {
        $answer = (Read-Host 'ONAY: Yalniz UYGUN listelenen dosyalari commit edip GitHub a gondermek icin YAZ yazin (vazgec: Enter)').Trim()
        if ($answer -cne 'YAZ') { Note 'IPTAL: git add/commit/push yapilmadi.'; $exitCode = 0 }
        else {
            $step = 'Onay sonrasi guvenlik kontrolu'
            # Onaydan sonra uzak dal degismisse kesinlikle gonderme.
            $remoteNow = RemoteHead $branch
            if ($remoteNow -ne $remoteBefore) { throw 'GitHub dali onizleme sirasinda degisti; iptal edildi.' }
            CheckBusy
            & git.exe diff --cached --quiet
            if ($LASTEXITCODE -ne 0) { throw 'Onizleme sonrasi staging degisti; iptal edildi.' }
            $currentChanged = @(RunGit -GitArgs @('ls-files','--modified','--deleted','--others','--exclude-standard')) | Where-Object { $_ }
            if ((@($currentChanged | Sort-Object) -join "`n") -cne (@($changed | Sort-Object) -join "`n")) { throw 'Dosya listesi onizlemeden sonra degisti; iptal edildi.' }
            $currentEligible = @($currentChanged | Where-Object { -not (Forbidden $_) })
            if ((@($currentEligible | Sort-Object) -join "`n") -cne (@($eligible | Sort-Object) -join "`n")) { throw 'Gonderim listesi degisti; iptal edildi.' }
            $currentTracked = @(RunGit -GitArgs @('ls-files','--modified','--deleted')) | Where-Object { $_ }
            if (@($currentTracked | Where-Object { Forbidden $_ }).Count) { throw 'Takip edilen korumali dosya degismis; iptal edildi.' }
            $step = 'Git add/commit'
            if ($currentEligible.Count) {
                # Yalniz onizlemede gorulen dosyalari stage et; toplu git add -A kullanma.
                # Dosyalardaki degisiklikler kullanicinin YAZ yetkisiyle kaydedilir.
                foreach ($path in $currentEligible) { RunGit -GitArgs @('add','-A','--',$path) | Out-Null }
                $stagedPaths = @(RunGit -GitArgs @('diff','--cached','--name-only'))
                if (@($stagedPaths | Where-Object { Forbidden $_ }).Count) { throw 'Stage edilenler arasinda yasakli dosya var. GitHub a gonderilmedi; staging incelemesi gerekli.' }
                & git.exe diff --cached --quiet
                if ($LASTEXITCODE -eq 1) {
                    RunGit -GitArgs @('commit','-m',('Onayli yerel senkronizasyon - ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))) | Out-Host
                    Note 'Yerel commit olusturuldu.'
                } elseif ($LASTEXITCODE -ne 0) { throw 'Commit oncesi diff kontrolu basarisiz.' }
            }
            $step = 'Push'
            # Gecmiste sakli gizli anahtarlar varsa bunun denetimi icin ayrica inceleme gerekir.
            # Otomatik gecmis yeniden yazma, force push yapilmaz.
            RunGit -GitArgs @('push','origin',('HEAD:refs/heads/' + $branch)) | Out-Host
            Note ('BASARILI: Normal push tamamlandi. Dal: ' + $branch)
            $exitCode = 0
        }
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
