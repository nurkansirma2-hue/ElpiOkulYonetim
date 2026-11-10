@echo off
setlocal EnableExtensions
chcp 65001 >nul
title ElpiOkulYonetim - GitHub Senkronizasyon
rem SYNC_VERSION: 11
set "SYNC_BAT=%~f0"
set "SYNC_PS=%TEMP%\ElpiOkulYonetim_Sync_%RANDOM%_%RANDOM%.ps1"
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
# BAT dosyasi pubspec.yaml ile ayni klasorde bulunmalidir.
$repo = [IO.Path]::GetFullPath((Split-Path -Parent $env:SYNC_BAT)).TrimEnd('\')
$repoUrl = 'https://github.com/nurkansirma2-hue/ElpiOkulYonetim.git'
$oldUrls = @('https://github.com/nurkansirma2-hue/OkulYonetim.git', 'git@github.com:nurkansirma2-hue/OkulYonetim.git')
$newUrls = @($repoUrl, 'git@github.com:nurkansirma2-hue/ElpiOkulYonetim.git')
$reportDir = Join-Path $env:LOCALAPPDATA 'OkulYonetim\SyncReports'
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
$report = Join-Path $reportDir ('Senkronizasyon_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff') + '.txt')
$events = [Collections.Generic.List[string]]::new()
$stashOid = ''
$stashRestoreFailed = $false
$stagedByScript = $false
$pushedCommits = 0
$branch = ''
$step = 'Baslangic'

function Note([string]$text) {
    $events.Add($text)
    Write-Host $text
}
function Git([string[]]$a) {
    # GitHub bazen "Empty reply from server" dondurur. HTTP/1.1 ve
    # gecici baglanti hatalarinda en fazla 3 deneme; global Git ayari degismez.
    $network = $a.Count -gt 0 -and $a[0] -in @('ls-remote','fetch','push')
    $attempts = if ($network) { 3 } else { 1 }
    for ($attempt = 1; $attempt -le $attempts; $attempt++) {
        if ($network) {
            $result = @(& git.exe -c core.quotepath=false -c http.version=HTTP/1.1 -c http.lowSpeedLimit=1 -c http.lowSpeedTime=30 @a)
        } else {
            $result = @(& git.exe -c core.quotepath=false @a)
        }
        $code = $LASTEXITCODE
        if ($code -eq 0) { return $result }
        if ($attempt -lt $attempts) {
            Note ("GitHub erisim denemesi $attempt/$attempts basarisiz; yeniden deneniyor...")
            Start-Sleep -Seconds (2 * $attempt)
        }
    }
    if ($network) {
        throw ('GitHub baglantisi basarisiz (kod ' + $code + '): git ' + ($a -join ' ') + '. Tarayicida GitHub acilsa bile Git ag/proxy/VPN ayarlari farkli olabilir. CMD uzerinden git -c http.version=HTTP/1.1 ls-remote origin HEAD komutuyla test edin.')
    }
    throw ('Git komutu basarisiz (kod ' + $code + '): git ' + ($a -join ' '))
}
function GitText([string[]]$a) { return ((Git $a) -join "`n").Trim() }
function HasHead {
    & git.exe rev-parse --verify --quiet HEAD > $null
    return $LASTEXITCODE -eq 0
}
function ClearIndex {
    if (HasHead) { Git @('reset','--quiet') | Out-Null }
    else { Git @('read-tree','--empty') | Out-Null }
}
function PrepareRootRepository {
    if (-not (Test-Path -LiteralPath (Join-Path $repo 'pubspec.yaml') -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $repo 'lib') -PathType Container)) {
        throw 'BAT dosyasini pubspec.yaml ve lib klasorunun bulundugu proje kokune koyun.'
    }
    $gitPath = Join-Path $repo '.git'
    if (-not (Test-Path -LiteralPath $gitPath)) {
        Git @('init','--initial-branch=master') | Out-Host
        Git @('remote','add','origin',$repoUrl) | Out-Null
        return
    }
    if (-not (Test-Path -LiteralPath $gitPath -PathType Container) -or
        ((Get-Item -LiteralPath $gitPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Baglantili/worktree Git kaydi otomatik degistirilmez.'
    }
    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'SilentlyContinue'
        & git.exe rev-parse --git-dir *> $null
        $validRepository = $LASTEXITCODE -eq 0
    } finally { $ErrorActionPreference = $oldPreference }
    $tracked = @()
    if ($validRepository) { $tracked = @(Git @('ls-files')) }
    # Yalniz eski alt klasorlu depo -> onaylanan kok proje gecisi.
    if ($validRepository) {
        if ('pubspec.yaml' -in $tracked -or
            'elpi_okul_yonetim/pubspec.yaml' -notin $tracked) { return }
        if (BusyGit) { throw 'Devam eden Git islemi var; kok duzene gecilmedi.' }
        & git.exe diff --cached --quiet
        if ($LASTEXITCODE -ne 0) { throw 'Staging bos degil; kok duzene gecilmedi.' }
        $origin = GitText @('remote','get-url','origin')
        if ($origin -notin ($oldUrls + $newUrls)) { throw 'Beklenmeyen eski depo; Git kaydi degistirilmedi.' }
    }
    # Uzak depo doluysa bagimsiz gecmis olusturup uzerine yazmayalim.
    $remoteHeads = @(Git @('ls-remote','--heads',$repoUrl))
    $remoteTags = @(Git @('ls-remote','--tags',$repoUrl))
    if ($remoteHeads.Count -or $remoteTags.Count) {
        throw 'Yeni GitHub deposu bos degil; eski Git kaydi korunarak gecis durduruldu.'
    }
    $identity = @{}
    foreach ($key in @('user.name','user.email')) {
        $value = @(& git.exe config --global --get $key)
        if ($validRepository) { $value = @(& git.exe config --get $key) }
        if ($LASTEXITCODE -eq 0) { $identity[$key] = ($value -join '').Trim() }
    }
    # Ayni disk uzerinde yeniden adlandirma: gizli .git tasinirken kismi kopya kalmaz.
    $backupRoot = Join-Path $repo ('.elpi-git-backups\' + [guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $backup = Join-Path $backupRoot '.git'
    # Sabit olarak dogrulanan proje kokunun .git klasoru; kaynaklar tasinmaz.
    $script:step = 'Eski gizli Git klasorunu yedekleme'
    [IO.Directory]::Move($gitPath, $backup)
    Note ('Eski Git gecmisi/stash kayitlari yedeklendi: ' + $backup)
    try {
        Git @('init','--initial-branch=master') | Out-Host
        Git @('remote','add','origin',$repoUrl) | Out-Null
        foreach ($key in $identity.Keys) { Git @('config',$key,$identity[$key]) | Out-Null }
    } catch {
        # Yeni, yarim Git kaydini da silmeden ayri sakla ve eski kaydi geri getir.
        if (Test-Path -LiteralPath $gitPath) {
            [IO.Directory]::Move($gitPath, (Join-Path $backupRoot 'yarim-yeni-git'))
        }
        [IO.Directory]::Move($backup, $gitPath)
        throw
    }
    Note 'Kok proje duzeni hazir. Yeni depoya yalniz bu kokteki mevcut kaynaklar gonderilecek.'
}
function BusyGit {
    foreach ($name in @('rebase-merge','rebase-apply','MERGE_HEAD','CHERRY_PICK_HEAD','REVERT_HEAD','BISECT_LOG')) {
        $path = GitText @('rev-parse','--git-path',$name)
        if (Test-Path -LiteralPath $path) { return $true }
    }
    return $false
}
function Protected([string]$path) {
    $p = $path.Replace('\','/')
    return $p -match '(?i)(^|/)(android/local\.properties|(?:linux|windows)/flutter/generated_(?:plugin_registrant\.(?:cc|h)|plugins\.cmake))$' -or
        $p -match '(?i)\.(bak|pending|update\.log|tmp)$' -or
        $p -match '(?i)(^|/)(Thumbs\.db|\.DS_Store)$'
}
function Risky([string]$path) {
    return $path.Replace('\','/') -match '(?i)(^|/)(\.env[^/]*|key\.properties|[^/]+\.(jks|keystore|p12|pfx|pem|key)|id_rsa|id_ed25519)$'
}
function Generated([string]$path) {
    $p = $path.Replace('\','/')
    return $p -match '(?i)\.(apk|aab|ipa)$' -or
        $p -match '(?i)(^|/)(build|\.dart_tool|\.gradle|\.codex-remote-attachments|\.elpi-git-backups|work|elpi_okul_yonetim)/'
}
function GuardWorkingTree {
    # Turkce/Unicode adlari Git yardimcisi tirnaklamadan UTF-8 olarak okur.
    # Sekme/satir sonu gibi gercek kontrol karakterleri yine engellenir.
    $names = @(Git @('ls-files','--cached','--others','--exclude-standard'))
    if (@($names | Where-Object { $_.StartsWith('"') }).Count) {
        throw 'Ozel karakterli dosya adi bulundu; otomatik senkronizasyon durduruldu.'
    }
    $deleted = @(Git @('ls-files','--deleted'))
    if ($deleted.Count -ge 20) {
        throw ($deleted.Count.ToString() + ' takip edilen dosya eksik. Toplu silme/tasima otomatik gonderilmedi. Once proje klasor duzenini kontrol edin.')
    }
}
function SaveLocal {
    $dirty = GitText @('status','--porcelain=v1','--untracked-files=all')
    if (-not $dirty) { return }
    Git @('stash','push','--include-untracked','-m',('ElpiSync-' + [guid]::NewGuid().ToString())) | Out-Host
    # Degisen stash sirasindan bagimsiz, degismez nesne kimligi.
    $script:stashOid = GitText @('rev-parse','refs/stash')
    if (GitText @('status','--porcelain=v1','--untracked-files=all')) {
        throw 'Stash sonrasi yerel degisiklik kaldi; islem durduruldu.'
    }
    Note ('Yerel degisiklikler korundu. Stash: ' + $script:stashOid)
}
function RestoreLocal {
    if (-not $script:stashOid) { return }
    $script:stashRestoreFailed = $true
    Git @('stash','apply',$script:stashOid) | Out-Host
    # Kurtarma kaydi silinmez; baska bir arac tarafindan eklenen stash'e dokunulmaz.
    Note ('Yerel degisiklikler geri yuklendi. Kurtarma stash kaydi korundu: ' + $script:stashOid)
    $script:stashOid = ''
    $script:stashRestoreFailed = $false
}
function CheckHistory([string]$range) {
    # Net fark yerine gonderilecek TUM commitlerdeki dosya adlarini kontrol et.
    $paths = @(Git @('-c','core.quotepath=false','log','--format=','--name-only','--no-renames',$range))
    foreach ($p in ($paths | Where-Object { $_ } | Sort-Object -Unique)) {
        if ((Risky $p) -or (Protected $p) -or (Generated $p)) {
            throw ('Gonderilecek commit gecmisinde otomatik gonderime kapali dosya var: ' + $p + '. Gecmis otomatik degistirilmedi.')
        }
    }
    foreach ($line in (Git @('rev-list','--objects',$range))) {
        $oid = ($line -split ' ',2)[0]
        if ((GitText @('cat-file','-t',$oid)) -ne 'blob') { continue }
        if ([long](GitText @('cat-file','-s',$oid)) -ge 100000000L) {
            throw ('Gonderilecek gecmiste 100 MB veya daha buyuk Git dosyasi var: ' + $oid)
        }
    }
}
function Integrate([string]$remoteRef) {
    if ([int](GitText @('rev-list','--count',"HEAD..$remoteRef")) -eq 0) { return }
    SaveLocal
    & git.exe -c rebase.autoStash=false rebase $remoteRef
    if ($LASTEXITCODE -ne 0) {
        if (BusyGit) { Git @('rebase','--abort') | Out-Host }
        throw 'GitHub degisiklikleri ile cakisma olustu; push yapilmadi.'
    }
    RestoreLocal
}

try {
    if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) { throw 'Git for Windows bulunamadi.' }
    Set-Location -LiteralPath $repo
    $step = 'Kok proje Git duzeni'
    PrepareRootRepository
    $top = GitText @('rev-parse','--show-toplevel')
    if ([IO.Path]::GetFullPath($top).TrimEnd('\') -ine [IO.Path]::GetFullPath($repo).TrimEnd('\')) {
        throw 'Beklenmeyen depo konumu. Klasor otomatik silinmez veya yeniden kurulmaz.'
    }
    if (BusyGit) { throw 'Devam eden Git islemi var; once mevcut islemi tamamlayin.' }
    $branch = GitText @('branch','--show-current')
    if (-not $branch) { throw 'Aktif yerel dal yok (detached HEAD).' }
    & git.exe diff --cached --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Staging alani bos degil; mevcut staging korunarak islem durduruldu.' }
    GuardWorkingTree
    $step = 'Yeni depo baglantisi'
    $origin = GitText @('remote','get-url','origin')
    if ($origin -in $oldUrls) {
        $remotes = @(Git @('remote'))
        if ('eski-okulyonetim' -notin $remotes) {
            Git @('remote','add','eski-okulyonetim',$origin) | Out-Null
        }
        Git @('remote','set-url','origin',$repoUrl) | Out-Null
        Note 'Origin ElpiOkulYonetim olarak degistirildi. Eski depo adresi korundu.'
    } elseif ($origin -notin $newUrls) { throw ('Beklenmeyen origin: ' + $origin) }
    # Ayrica tanimli pushurl ile eski/baska depoya gonderim yapilmasini engelle.
    $pushUrls = @(Git @('remote','get-url','--push','--all','origin'))
    if ($pushUrls.Count -ne 1 -or $pushUrls[0] -notin $newUrls) {
        throw 'Origin push adresi yeni depoyla uyusmuyor; push yapilmadi.'
    }
    $step = 'GitHub kontrolu'
    $heads = @(Git @('ls-remote','--heads','origin'))
    $remoteRef = "refs/remotes/origin/$branch"
    $remoteBranch = @($heads | Where-Object { ($_ -split "`t",2)[1] -eq "refs/heads/$branch" })
    if ($heads.Count -gt 0 -and $remoteBranch.Count -eq 0) {
        throw ('GitHub bos degil, ancak ' + $branch + ' dali yok. Otomatik yeni dal acilmadi.')
    }
    $emptyRemote = $heads.Count -eq 0
    if (-not $emptyRemote) {
        Git @('fetch','--no-tags','origin',("+refs/heads/{0}:{1}" -f $branch,$remoteRef)) | Out-Host
        Integrate $remoteRef
    } else { Note ('Yeni GitHub deposu bos. Ilk gonderim yerel ' + $branch + ' daliyla yapilacak.') }

    $step = 'Yerel degisiklikleri hazirlama'
    GuardWorkingTree
    $stagedByScript = $true
    Git @('add','-A','--','.') | Out-Null
    $staged = @(Git @('-c','core.quotepath=false','diff','--cached','--name-only'))
    foreach ($p in $staged) {
        if (Risky $p) { throw ('Gizli anahtar/ortam dosyasi bulundu: ' + $p) }
        if ((Protected $p) -or (Generated $p)) {
            if (HasHead) { Git @('reset','--quiet','HEAD','--',$p) | Out-Null }
            else { Git @('rm','--cached','--quiet','--',$p) | Out-Null }
        }
    }
    & git.exe diff --cached --quiet
    $diffExit = $LASTEXITCODE
    if ($diffExit -eq 1) {
        Git @('commit','-m',('Yerel proje degisikliklerini senkronize et - ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))) | Out-Host
    } elseif ($diffExit -ne 0) { throw 'Staging kontrolu basarisiz.' }
    $stagedByScript = $false
    $step = 'Push oncesi gecmis kontrolu'
    $range = if ($emptyRemote) { 'HEAD' } else { "$remoteRef..HEAD" }
    CheckHistory $range
    $count = [int](GitText @('rev-list','--count',$range))
    if ($count -gt 0) {
        Note ("GitHub'a gonderilmeyi bekleyen commit: $count; dal: $branch")
        $confirmation = (Read-Host "GitHub'a gondermek icin YAZ yazin (iptal: Enter)").Trim()
        if ($confirmation -cne 'YAZ') {
            Note 'GitHub gonderimi onaylanmadi. Yerel commitler korundu; push yapilmadi.'
            $exitCode = 0
        } else {
            # Force push yok. Arada uzak dal degisirse Git gonderimi reddeder.
            Git @('push','--set-upstream','origin',("HEAD:refs/heads/$branch")) | Out-Host
            $pushedCommits = $count
        }
    }
    $step = 'Son kontrol'
    if ($count -eq 0 -or $pushedCommits -gt 0) {
        $remoteHead = @(Git @('ls-remote','--heads','origin',"refs/heads/$branch"))
        if ($remoteHead.Count -ne 1 -or ($remoteHead[0] -split "`t",2)[0] -ne (GitText @('rev-parse','HEAD'))) {
            throw 'Son kontrolde yerel ve uzak dal esit degil. Tekrar senkronizasyon gerekli.'
        }
    }
    if ($count -gt 0 -and $pushedCommits -eq 0) {
        Note 'TAMAMLANDI: Yerel commitler hazir, ancak GitHub gonderimi yapilmadi.'
    } else {
        Note ('BASARILI: ' + $pushedCommits + ' commit gonderildi. Dal: ' + $branch)
    }
    if ($count -eq 0 -or $pushedCommits -gt 0) { Note 'GitHub senkronizasyonu kontrol edildi. Flutter analiz/test veya APK kurulumu yapilmaz.' }
    else { Note 'GitHub senkronizasyonu tamamlanmadi; push onayi verilmedi.' }
    $exitCode = 0
} catch {
    Note ('HATA (' + $step + '): ' + $_.Exception.Message)
    Note ('Konum: ' + $_.InvocationInfo.PositionMessage)
    if ($stagedByScript) {
        try { ClearIndex } catch { Note 'Staging geri alinamadi; git status kontrol edilmeli.' }
    }
    if ($stashOid -and -not $stashRestoreFailed) {
        try { if (-not (BusyGit)) { RestoreLocal } } catch { Note ('Kurtarma stash kaydi korundu: ' + $stashOid) }
    }
    Note ('Basariyla gonderilen commit: ' + $pushedCommits)
    $exitCode = 1
} finally {
    $events.Add('Rapor: ' + $report)
    [IO.File]::WriteAllLines($report,$events,[Text.UTF8Encoding]::new($true))
    Write-Host ('Rapor: ' + $report)
}
exit $exitCode
