#===============================================================================
# run_quartus.ps1 - compila o projeto no Quartus por linha de comando e resume
# o resultado. Nao precisa abrir a GUI.
#
# Executar a partir da raiz do projeto:
#     pwsh scripts/run_quartus.ps1
#
# Alem de compilar, o script confere que o Fitter colocou cada pino exatamente
# onde o .qsf mandou. Essa verificacao existe porque atribuicao de pino errada
# nao gera erro de compilacao: o projeto grava e o display so mostra lixo.
#===============================================================================
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# --- localiza o Quartus -------------------------------------------------------
$cands = @($env:QUARTUS_ROOTDIR)
foreach ($base in @("C:\altera_lite", "C:\intelFPGA_lite", "D:\altera_lite", "D:\intelFPGA_lite")) {
    if (Test-Path $base) {
        Get-ChildItem $base -Directory | Sort-Object Name -Descending | ForEach-Object {
            $cands += (Join-Path $_.FullName "quartus")
        }
    }
}
$qbin = $null
foreach ($c in $cands) {
    if ($c -and (Test-Path (Join-Path $c "bin64\quartus_sh.exe"))) { $qbin = Join-Path $c "bin64"; break }
}
if (-not $qbin) {
    Write-Error "Quartus nao encontrado. Instale o Quartus Prime Lite com suporte a MAX 10, ou aponte QUARTUS_ROOTDIR para a pasta 'quartus' da instalacao."
    exit 1
}
$env:PATH = "$qbin;$env:PATH"
Write-Host "Quartus em: $qbin" -ForegroundColor Cyan

# --- compila ------------------------------------------------------------------
Push-Location quartus
Write-Host "`nCompilando (analise+sintese, fitter, assembler, timing)..." -ForegroundColor Cyan
& quartus_sh --flow compile fp_adder_de10lite | Out-Null
$rc = $LASTEXITCODE
if ($rc -ne 0) {
    Pop-Location
    Write-Host "COMPILACAO FALHOU (codigo $rc). Veja quartus/output_files/*.rpt" -ForegroundColor Red
    exit 1
}

# --- resumo -------------------------------------------------------------------
Write-Host "`n=== RESUMO DA COMPILACAO ===" -ForegroundColor Cyan
Get-Content output_files\fp_adder_de10lite.fit.summary |
    Select-String -Pattern "Fitter Status|Device|Total logic elements|Total combinational|Dedicated logic registers|Total pins|Total PLLs"

$sta = Get-Content output_files\fp_adder_de10lite.sta.rpt
$i = ($sta | Select-String -Pattern "^; Slow 1200mV 85C Model Fmax Summary" | Select-Object -First 1).LineNumber
if ($i) { Write-Host "`nFmax (Slow 85C):"; $sta[($i+2)..($i+3)] }

$slack = Get-Content output_files\fp_adder_de10lite.sta.summary |
         Select-String -Pattern "Slack" | Select-Object -First 1
Write-Host "`nPior slack de setup: $slack"

# --- verificacao dos pinos ----------------------------------------------------
Write-Host "`n=== CONFERENCIA DE PINOS (qsf x fitter) ===" -ForegroundColor Cyan
$qsf = @{}
Select-String -Path fp_adder_de10lite.qsf -Pattern 'set_location_assignment (PIN_\w+)\s+-to\s+(\S+)' | ForEach-Object {
    $qsf[$_.Matches[0].Groups[2].Value] = $_.Matches[0].Groups[1].Value
}
$pin = @{}
Get-Content output_files\fp_adder_de10lite.pin | ForEach-Object {
    if ($_ -match '^(\S+)\s+:\s+(\w+)\s+:\s+(input|output|bidir)') { $pin[$matches[1]] = "PIN_" + $matches[2] }
}
$bad = 0; $ok = 0
foreach ($sig in $qsf.Keys) {
    if ($pin.ContainsKey($sig) -and $pin[$sig] -eq $qsf[$sig]) { $ok++ }
    else { $bad++; Write-Host "  DIVERGE: $sig  qsf=$($qsf[$sig])  fitter=$($pin[$sig])" -ForegroundColor Red }
}
Write-Host "  pinos conferidos OK : $ok"
Write-Host "  divergencias        : $bad"

Pop-Location

if ($bad -ne 0) {
    Write-Host "`nATENCAO: o Fitter nao respeitou alguma atribuicao de pino." -ForegroundColor Red
    exit 1
}

Write-Host "`n==============================================================" -ForegroundColor Green
Write-Host " COMPILACAO OK - quartus/output_files/fp_adder_de10lite.sof" -ForegroundColor Green
Write-Host "==============================================================" -ForegroundColor Green
Write-Host " Gravar na placa: Tools > Programmer, ou"
Write-Host " quartus_pgm -m jtag -o `"p;quartus/output_files/fp_adder_de10lite.sof`""
exit 0
