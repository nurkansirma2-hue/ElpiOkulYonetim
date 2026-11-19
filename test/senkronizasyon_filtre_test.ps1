$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$checks = 0
foreach ($name in @('OkulYonetimSenkronize.bat', 'OkulYonetimSenkronize_Duzeltilmis_V12.bat')) {
    $text = [IO.File]::ReadAllText((Join-Path $root $name))
    $marker = [regex]::Match($text, '(?m)^#===POWERSHELL_BASLANGIC===\r?$')
    if (!$marker.Success) { throw "$name : PowerShell bolumu bulunamadi" }
    $tokens = $null; $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput(
        $text.Substring($marker.Index + $marker.Length), [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
    # Yalniz saf filtre fonksiyonlari yuklenir; BAT, Git ve ag islemleri calismaz.
    foreach ($functionName in @('Generated', 'Protected', 'Risky')) {
        $definition = $ast.Find({ param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq $functionName
        }, $true)
        if (!$definition) { throw "Eksik fonksiyon: $functionName" }
        . ([scriptblock]::Create($definition.Extent.Text))
    }
    foreach ($path in @(
        'android/app/src/main/kotlin/com/example/elpi_okul_yonetim/MainActivity.kt',
        'android\app\src\main\kotlin\com\example\elpi_okul_yonetim\DriveBelgeChannel.kt',
        'android/app/src/main/kotlin/com/example/elpi_okul_yonetim/DbfKaynakChannel.kt',
        'android/app/src/main/kotlin/com/example/elpi_okul_yonetim/RehberlikOcrChannel.kt',
        'lib/services/bilgi_toplama_google_service.dart'
    )) {
        if ((Generated $path) -or (Protected $path) -or (Risky $path)) {
            throw "$name kaynak dosyasini engelliyor: $path"
        }
        $checks++
    }
    foreach ($path in @(
        'elpi_okul_yonetim/lib/main.dart', 'elpi_okul_yonetim\pubspec.yaml',
        'android/.gradle/cache.bin', 'build/app.apk', '.dart_tool/package_config.json',
        '.elpi-git-backups/backup/config', 'work/test.txt', 'output/release.aab',
        'android/local.properties', 'windows/flutter/generated_plugin_registrant.cc',
        'linux/flutter/generated_plugins.cmake', '.env', 'android/key.properties', 'upload.jks'
    )) {
        if (!((Generated $path) -or (Protected $path) -or (Risky $path))) {
            throw "$name korunmasi gereken dosyaya izin veriyor: $path"
        }
        $checks++
    }
}
Write-Output "$checks filtre kontrolu ve iki PowerShell sozdizimi kontrolu basarili."
