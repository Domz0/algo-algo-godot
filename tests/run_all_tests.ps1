param(
    [string]$Godot = 'C:\Users\Tinpod\Downloads\Godot_v4.7.2-stable_win64.exe'
)
# Ejecuta cada suite y verifica también su resumen: un error de GDScript puede interrumpir un caso
# sin que el ejecutable gráfico de Windows propague un código de salida distinto de cero.
$ErrorActionPreference = 'Stop'
$projectPath = Split-Path -Parent $PSScriptRoot
$logPath = Join-Path $projectPath '.godot/test-logs'
New-Item -ItemType Directory -Path $logPath -Force | Out-Null
$suites = @('run_tests', 'run_scene_tests', 'run_logistics_tests', 'run_acquisition_tests', 'run_extended_tests')
$failedSuites = @()
foreach ($suite in $suites) {
    $logFile = Join-Path $logPath ($suite + '.log')
    # Windows PowerShell convierte stderr nativo en errores; se evalua la salida completa abajo.
    $ErrorActionPreference = 'Continue'
    $captured = & $Godot --headless --path $projectPath --log-file $logFile --script "res://tests/$suite.gd" --quit-after 3000 2>&1 | Out-String
    $engineExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    $savedLog = Get-Content -LiteralPath $logFile -Raw -Encoding UTF8
    $fullOutput = $captured + $savedLog
    $summary = [regex]::Matches($fullOutput, '[^\r\n]*\d+ comprobaciones, \d+ fallos\.') | Select-Object -First 1
    if ($engineExit -ne 0 -or $fullOutput -match 'SCRIPT ERROR:|[1-9][0-9]* fallos\.|(?m)^ERROR: (?!Failed to read the root certificate store\.)' -or $fullOutput -notmatch '\d+ comprobaciones, 0 fallos\.') {
        $failedSuites += $suite
        Write-Output "FALLO: $suite"
        Write-Output $fullOutput
    } else {
        Write-Output "PASA: $suite - $summary"
    }
}
if ($failedSuites.Count -gt 0) {
    Write-Output ('Suites fallidas: ' + ($failedSuites -join ', '))
    exit 1
}
Write-Output 'Las cinco suites terminaron sin fallos ni errores de GDScript.'
exit 0
