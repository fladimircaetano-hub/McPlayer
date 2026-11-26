# Gera os APKs dos três apps do painel, um após o outro.
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File tool\build_all_apps.ps1
#   powershell -ExecutionPolicy Bypass -File tool\build_all_apps.ps1 -Apps McPlayer
param(
    [string[]]$Apps = @('McPlayer', 'NexPlay', 'CaetanoPlayer')
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$buildScript = Join-Path $root 'tool\build_release.ps1'
if (-not (Test-Path $buildScript)) { throw "Nao encontrei $buildScript" }

foreach ($app in $Apps) {
    Write-Host "`n########## Build: $app ##########" -ForegroundColor Magenta
    & powershell -ExecutionPolicy Bypass -File $buildScript -AppName $app
    if ($LASTEXITCODE -ne 0) { throw "Build falhou para $app (exit $LASTEXITCODE)" }
}

Write-Host "`nTodos os builds concluidos." -ForegroundColor Green
