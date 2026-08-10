#===============================================================================
# run_ghdl.ps1 - compila e roda TODA a verificacao no GHDL.
#
# Executar a partir da raiz do projeto:
#     pwsh scripts/run_ghdl.ps1
#
# Etapas executadas:
#   0. checagem de que o RTL sintetizavel e VHDL-93 valido (o que o Quartus
#      aceita sem precisar ligar a opcao VHDL-2008);
#   1. tb_fp_adder_orig      - valida o codigo do livro;
#   2. tb_fp_adder_fixed     - valida o nucleo adaptado e compara com o original;
#   3. tb_fp_adder_de10lite  - valida o nivel de topo pela interface da placa;
#   4. tb_fp_precision       - caracteriza o erro numerico do algoritmo contra
#                              um oraculo independente, nos 16.793.604 pares;
#   5. tb_fp_adder_waves     - gera os artefatos (.vcd/.ghw e a tabela dos
#                              casos dirigidos) e confere os dados da figura.
#
# O passo 4 e o mais demorado (cerca de 1 minuto): ele percorre todo o espaco
# de operandos legais. Os demais levam poucos segundos.
#
# Codigo de saida 0 = tudo passou.
#===============================================================================
$ErrorActionPreference = "Stop"

. "$PSScriptRoot/ghdl_env.ps1"

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$STD   = "--std=08"
$WORK  = "build"
$WORK93 = "build93"

New-Item -ItemType Directory -Force -Path $WORK, $WORK93, "sim/waves", "docs/img" | Out-Null

$RTL = @(
    "rtl/fp_adder.vhd",
    "rtl/fp_adder_fixed.vhd",
    "rtl/hex_to_sseg.vhd",
    "rtl/debounce.vhd",
    "rtl/fp_adder_de10lite.vhd"
)
$SIM = @(
    "sim/fp_pkg.vhd",
    "sim/tb_fp_adder_orig.vhd",
    "sim/tb_fp_adder_fixed.vhd",
    "sim/tb_fp_adder_de10lite.vhd",
    "sim/tb_fp_precision.vhd",
    "sim/tb_fp_adder_waves.vhd"
)

function Invoke-Step($titulo, $bloco) {
    Write-Host ""
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host " $titulo" -ForegroundColor Cyan
    Write-Host "==============================================================" -ForegroundColor Cyan
    & $bloco
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FALHOU: $titulo" -ForegroundColor Red
        exit 1
    }
}

# --- 0. compatibilidade VHDL-93 do RTL sintetizavel -----------------------------
Invoke-Step "0. RTL sintetizavel compila como VHDL-93 (compatibilidade Quartus)" {
    ghdl -a --std=93 --workdir=$WORK93 $RTL
    if ($LASTEXITCODE -eq 0) { ghdl -e --std=93 --workdir=$WORK93 -o "$WORK93/top" fp_adder_de10lite }
}

# --- 0b. sintetizabilidade -----------------------------------------------------
# "ghdl --synth" elabora o topo ate uma netlist. Nao substitui o Quartus, mas pega
# cedo o que a analise sozinha nao pega: latches acidentais, sinais sem driver,
# construcoes nao sintetizaveis. Deve terminar sem nenhum aviso.
Invoke-Step "0b. RTL elabora ate netlist (ghdl --synth)" {
    New-Item -ItemType Directory -Force -Path "build_synth" | Out-Null
    ghdl --synth --std=93 --workdir=build_synth `
        rtl/fp_adder_fixed.vhd rtl/hex_to_sseg.vhd rtl/debounce.vhd rtl/fp_adder_de10lite.vhd `
        -e fp_adder_de10lite > build_synth/netlist.vhd
}

# --- analise ------------------------------------------------------------------
Invoke-Step "Analise (VHDL-2008)" {
    ghdl -a $STD --workdir=$WORK $RTL
    if ($LASTEXITCODE -eq 0) { ghdl -a $STD --workdir=$WORK $SIM }
}

# --- 1. Etapa 1 ---------------------------------------------------------------
Invoke-Step "1. ETAPA 1 - validacao do VHDL original do livro" {
    ghdl -e $STD --workdir=$WORK -o "$WORK/tb_fp_adder_orig" tb_fp_adder_orig
    if ($LASTEXITCODE -eq 0) { ghdl -r $STD --workdir=$WORK tb_fp_adder_orig }
}

# --- 2. Etapa 2 ---------------------------------------------------------------
Invoke-Step "2. ETAPA 2 - validacao do nucleo adaptado" {
    ghdl -e $STD --workdir=$WORK -o "$WORK/tb_fp_adder_fixed" tb_fp_adder_fixed
    if ($LASTEXITCODE -eq 0) { ghdl -r $STD --workdir=$WORK tb_fp_adder_fixed }
}

# --- 3. topo ------------------------------------------------------------------
Invoke-Step "3. ETAPA 2/3 - nivel de topo pela interface da DE10-Lite" {
    ghdl -e $STD --workdir=$WORK -o "$WORK/tb_fp_adder_de10lite" tb_fp_adder_de10lite
    if ($LASTEXITCODE -eq 0) { ghdl -r $STD --workdir=$WORK tb_fp_adder_de10lite }
}

# --- 4. caracterizacao numerica -----------------------------------------------
# Percorre os 16.793.604 pares de operandos legais comparando o algoritmo com um
# oraculo independente (soma exata). E o passo que estabelece os numeros da
# secao de precisao do relatorio. Demora cerca de 1 minuto.
Invoke-Step "4. Caracterizacao numerica (algoritmo x soma exata)" {
    ghdl -e $STD --workdir=$WORK -o "$WORK/tb_fp_precision" tb_fp_precision
    if ($LASTEXITCODE -eq 0) { ghdl -r $STD --workdir=$WORK tb_fp_precision }
}

# --- 5. artefatos -------------------------------------------------------------
# Este passo grava arquivos (formas de onda e a tabela da figura). Ele confere
# os proprios dados que grava, mas nao e um passo de regressao: a verificacao
# esta nos passos 1 a 4.
Invoke-Step "5. Geracao de artefatos: formas de onda e tabela dos casos dirigidos" {
    ghdl -e $STD --workdir=$WORK -o "$WORK/tb_fp_adder_waves" tb_fp_adder_waves
    if ($LASTEXITCODE -eq 0) {
        ghdl -r $STD --workdir=$WORK tb_fp_adder_waves `
            --vcd=sim/waves/fp_adder_waves.vcd `
            --wave=sim/waves/fp_adder_waves.ghw
    }
}

# --- 6. figuras do relatorio --------------------------------------------------
& "$PSScriptRoot/render_waveform.ps1"
& "$PSScriptRoot/render_board.ps1"

Write-Host ""
Write-Host "==============================================================" -ForegroundColor Green
Write-Host " TUDO PASSOU" -ForegroundColor Green
Write-Host "==============================================================" -ForegroundColor Green
Write-Host " Formas de onda: gtkwave sim/waves/fp_adder_waves.ghw sim/waves/fp_adder_waves.gtkw"
exit 0
