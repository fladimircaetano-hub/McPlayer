# Gera os APKs arm64/arm32 do McPlayer e VERIFICA antes de publicar.
#
# Por que existe: já foram publicados APKs sem a configuração do Supabase
# (aparece "Ativação remota DESLIGADA" na TV) e um upload truncado no catbox.
# Este script falha se o APK não tiver a URL/chave embutida, se o ZIP estiver
# corrompido ou se a assinatura for inválida.
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File tool\build_release.ps1
#   powershell -ExecutionPolicy Bypass -File tool\build_release.ps1 -ReleaseTag 2025
#   powershell -ExecutionPolicy Bypass -File tool\build_release.ps1 -SkipBuild   # só verifica
#
# A URL e a anon key saem de dashboard\js\config.js (fonte única), então o app
# e o painel nunca ficam apontando para projetos diferentes.

param(
    [string]$ReleaseTag = "",
    [string]$AppName = "McPlayer",
    [string]$OutDir = "",
    # Pasta com os APKs a verificar (padrao: build\app\outputs\flutter-apk).
    # Use para conferir um APK ja publicado, ex.: -ApkDir C:\temp\baixado
    [string]$ApkDir = "",
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

# ---------- 1. Configuração do Supabase (vem do dashboard) ----------
$cfgPath = Join-Path $root 'dashboard\js\config.js'
if (-not (Test-Path $cfgPath)) { throw "Nao encontrei $cfgPath" }
$cfgText = Get-Content $cfgPath -Raw
$supabaseUrl = [regex]::Match($cfgText, "supabaseUrl:\s*'([^']+)'").Groups[1].Value
$supabaseKey = [regex]::Match($cfgText, "supabaseAnonKey:\s*'([^']+)'").Groups[1].Value
if (-not $supabaseUrl -or -not $supabaseKey) {
    throw "Nao consegui ler supabaseUrl/supabaseAnonKey de dashboard\js\config.js"
}

# ---------- 2. Versão do pubspec ----------
$pubspec = Get-Content (Join-Path $root 'pubspec.yaml') -Raw
$fullVersion = [regex]::Match($pubspec, '(?m)^version:\s*(\S+)').Groups[1].Value
$versionName = ($fullVersion -split '\+')[0]
if (-not $ReleaseTag) { $ReleaseTag = ($fullVersion -split '\+')[1] }
if (-not $OutDir) { $OutDir = Join-Path $root ("dist\{0}_v{1}+{2}" -f (Get-Date -Format 'yyyy-MM-dd'), $versionName, $ReleaseTag) }

Write-Host "Versao : $fullVersion (tag $ReleaseTag)" -ForegroundColor Cyan
Write-Host "App    : $AppName" -ForegroundColor Cyan
Write-Host "Supabase: $supabaseUrl" -ForegroundColor Cyan
Write-Host "Saida  : $OutDir" -ForegroundColor Cyan

# ---------- 3. Build ----------
if (-not $SkipBuild) {
    Write-Host "`n==> flutter build apk --split-per-abi" -ForegroundColor Yellow
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'   # flutter escreve avisos no stderr
    & flutter build apk --release --split-per-abi `
        "--dart-define=SUPABASE_URL=$supabaseUrl" `
        "--dart-define=SUPABASE_ANON_KEY=$supabaseKey" `
        "--dart-define=APP_NAME=$AppName" `
        "--dart-define=RELEASE_TAG=$ReleaseTag"
    $buildCode = $LASTEXITCODE
    $ErrorActionPreference = $prevEap
    if ($buildCode -ne 0) { throw "flutter build falhou (codigo $buildCode)" }
}

# ---------- 4. Ferramentas do Android ----------
$sdk = $env:ANDROID_SDK_ROOT
if (-not $sdk) { $sdk = $env:ANDROID_HOME }
if (-not $sdk) { $sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
$btDir = $null
if (Test-Path (Join-Path $sdk 'build-tools')) {
    $btDir = Get-ChildItem (Join-Path $sdk 'build-tools') -Directory |
        Sort-Object { try { [version]$_.Name } catch { [version]'0.0' } } -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}
$aapt2 = if ($btDir) { Join-Path $btDir 'aapt2.exe' } else { $null }
$apksigner = if ($btDir) { Join-Path $btDir 'apksigner.bat' } else { $null }
$zipalign = if ($btDir) { Join-Path $btDir 'zipalign.exe' } else { $null }

Add-Type -AssemblyName System.IO.Compression.FileSystem
$enc = [Text.Encoding]::GetEncoding(28591)   # Latin1 (funciona no PS 5.1)

# Chama um .exe sem deixar o stderr dele virar erro fatal no PowerShell 5.1
# (com $ErrorActionPreference = 'Stop', qualquer stderr aborta o script).
function Invoke-Native($exe, [string[]]$arguments) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = @(& $exe @arguments 2>&1)
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $prev }
    [pscustomobject]@{ Output = $out; ExitCode = $code }
}

function Get-ZipEntryBytes($zipPath, $entryName) {
    $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $entry = $zip.GetEntry($entryName)
        if (-not $entry) { return $null }
        $ms = New-Object IO.MemoryStream
        $entry.Open().CopyTo($ms)
        return $ms.ToArray()
    } finally { $zip.Dispose() }
}

# ---------- 5. Verificação ----------
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
if ($ApkDir) {
    if (-not (Test-Path $ApkDir)) { throw "ApkDir nao existe: $ApkDir" }
    $apkDir = (Resolve-Path $ApkDir).Path
} else {
    $apkDir = Join-Path $root 'build\app\outputs\flutter-apk'
}
$targets = @(
    @{ File = 'app-arm64-v8a-release.apk';    Abi = 'arm64-v8a';   Label = 'arm64' },
    @{ File = 'app-armeabi-v7a-release.apk';  Abi = 'armeabi-v7a'; Label = 'arm32' }
)

$results = @()
foreach ($t in $targets) {
    $src = Join-Path $apkDir $t.File
    if (-not (Test-Path $src)) { throw "APK nao encontrado: $src" }

    Write-Host "`n==> Verificando $($t.File)" -ForegroundColor Yellow
    $errors = @()

    # 5.1 ZIP integro (le todas as entradas e valida CRC)
    # Pega tambem o caso "upload truncado" (download pela metade): OpenRead estoura.
    $entryCount = 0
    $zipOk = $true
    try {
        $zip = [IO.Compression.ZipFile]::OpenRead($src)
        $entryCount = $zip.Entries.Count
        $crcErrors = 0
        foreach ($e in $zip.Entries) {
            try { $s = $e.Open(); $buf = New-Object byte[] 65536; while (($s.Read($buf, 0, 65536)) -gt 0) {}; $s.Close() }
            catch { $crcErrors++ }
        }
        $zip.Dispose()
        if ($crcErrors -gt 0) { $errors += "$crcErrors entradas corrompidas" }
    } catch {
        $zipOk = $false
        $errors += "ZIP corrompido/truncado: $($_.Exception.Message)"
    }

    # 5.2 Config do Supabase dentro do libapp.so
    $soBytes = $null
    if ($zipOk) {
        try { $soBytes = Get-ZipEntryBytes $src ("lib/{0}/libapp.so" -f $t.Abi) }
        catch { $errors += "nao consegui ler libapp.so: $($_.Exception.Message)" }
    }
    if ($zipOk -and -not $soBytes) {
        $errors += ("lib/{0}/libapp.so ausente (ABI errada?)" -f $t.Abi)
    } elseif ($soBytes) {
        $soText = $enc.GetString($soBytes)
        if (-not $soText.Contains($supabaseUrl)) { $errors += "SUPABASE_URL nao embutida -> apareceria 'Ativacao remota DESLIGADA'" }
        if (-not $soText.Contains($supabaseKey.Substring(0, 40))) { $errors += "SUPABASE_ANON_KEY nao embutida" }
    }

    # 5.3 Manifesto / ABI / versionCode
    $versionCode = ''
    $nativeCode = ''
    if ($aapt2 -and (Test-Path $aapt2)) {
        $badging = (Invoke-Native $aapt2 @('dump', 'badging', $src)).Output
        $pkgLine = $badging | Where-Object { $_ -like 'package:*' } | Select-Object -First 1
        if ($pkgLine -match "versionCode='(\d+)'") { $versionCode = $Matches[1] }
        $nativeLine = $badging | Where-Object { $_ -like 'native-code:*' } | Select-Object -First 1
        if ($nativeLine) { $nativeCode = $nativeLine }
        if ($nativeCode -and -not $nativeCode.Contains($t.Abi)) { $errors += "native-code nao contem $($t.Abi)" }
        if (-not $pkgLine) { $errors += "manifesto ilegivel (APK invalido?)" }
    }

    # 5.4 Assinatura
    $certDn = ''
    $debugCert = $false
    if ($apksigner -and (Test-Path $apksigner)) {
        # --verbose e obrigatorio: sem ele o apksigner so imprime os certificados
        # e nao a linha "Verifies" (foi o que deu falso negativo na 1a versao).
        $sigRun = Invoke-Native $apksigner @('verify', '--verbose', '--print-certs', $src)
        $sig = $sigRun.Output
        $sigExit = $sigRun.ExitCode
        if ($sigExit -ne 0 -or ($sig | Where-Object { $_ -match 'DOES NOT VERIFY' })) {
            $errors += "assinatura invalida (apksigner exit $sigExit)"
        }
        $dnLine = $sig | Where-Object { $_ -match 'certificate DN:' } | Select-Object -First 1
        if ($dnLine) { $certDn = ($dnLine -split 'certificate DN:')[1].Trim() }
        if ($certDn -match 'Android Debug') { $debugCert = $true }
    }

    # 5.5 Alinhamento
    if ($zipalign -and (Test-Path $zipalign)) {
        $alignRun = Invoke-Native $zipalign @('-c', '-p', '4', $src)
        if ($alignRun.ExitCode -ne 0) { $errors += "zipalign invalido: $($alignRun.Output)" }
    }

    $hash = (Get-FileHash $src -Algorithm SHA256).Hash
    $size = (Get-Item $src).Length

    $destName = "mcplayer_v{0}_{1}_{2}.apk" -f $versionName, $ReleaseTag, $t.Label
    $dest = Join-Path $OutDir $destName
    Copy-Item $src $dest -Force

    $results += [pscustomobject]@{
        Apk         = $destName
        ABI         = $t.Abi
        VersionCode = $versionCode
        MB          = [math]::Round($size / 1MB, 1)
        Bytes       = $size
        SHA256      = $hash
        Assinatura  = $(if ($debugCert) { 'DEBUG (ok p/ sideload, NAO p/ Play Store)' } else { $certDn })
        Entradas    = $entryCount
        Erros       = $(if ($errors.Count -eq 0) { 'OK' } else { $errors -join ' | ' })
    }
}

# ---------- 6. Relatório ----------
$results | Format-Table Apk, ABI, VersionCode, MB, Entradas, Erros -AutoSize | Out-String | Write-Host

$shaFile = Join-Path $OutDir 'SHA256.txt'
$results | ForEach-Object { "{0}  {1}" -f $_.SHA256, $_.Apk } | Set-Content $shaFile -Encoding ascii
Write-Host "SHA256 gravado em $shaFile" -ForegroundColor Green

$failed = $results | Where-Object { $_.Erros -ne 'OK' }
if ($failed) {
    Write-Host "`nFALHOU - NAO PUBLIQUE ESTES APKS:" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host ("  {0}: {1}" -f $_.Apk, $_.Erros) -ForegroundColor Red }
    exit 1
}

Write-Host "`nOK - APKs prontos em $OutDir" -ForegroundColor Green
Write-Host "Depois de subir (catbox/GitHub), confira o TAMANHO e o SHA-256 no link publicado." -ForegroundColor Green
Write-Host "Tamanhos esperados : arm64 $((($results | Where-Object ABI -eq 'arm64-v8a').Bytes)/1MB -as [int]) MB | arm32 $((($results | Where-Object ABI -eq 'armeabi-v7a').Bytes)/1MB -as [int]) MB"
