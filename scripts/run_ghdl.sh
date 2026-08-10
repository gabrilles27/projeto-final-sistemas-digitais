#!/usr/bin/env bash
#===============================================================================
# run_ghdl.sh - mesma verificacao do run_ghdl.ps1, para Linux/macOS/Git Bash.
#
# Executar a partir da raiz do projeto:
#     ./scripts/run_ghdl.sh
#===============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v ghdl >/dev/null 2>&1; then
    echo "GHDL nao encontrado no PATH." >&2
    echo "Linux:  sudo apt install ghdl gtkwave" >&2
    echo "Windows: baixe ghdl-mcode-<versao>-mingw64.zip em" >&2
    echo "         https://github.com/ghdl/ghdl/releases e adicione bin/ ao PATH." >&2
    exit 1
fi

STD="--std=08"
WORK="build"
WORK93="build93"
mkdir -p "$WORK" "$WORK93" sim/waves docs/img

RTL="rtl/fp_adder.vhd rtl/fp_adder_fixed.vhd rtl/hex_to_sseg.vhd rtl/debounce.vhd rtl/fp_adder_de10lite.vhd"
SIM="sim/fp_pkg.vhd sim/tb_fp_adder_orig.vhd sim/tb_fp_adder_fixed.vhd sim/tb_fp_adder_de10lite.vhd sim/tb_fp_precision.vhd sim/tb_fp_adder_waves.vhd"

banner() {
    echo
    echo "=============================================================="
    echo " $1"
    echo "=============================================================="
}

banner "0. RTL sintetizavel compila como VHDL-93 (compatibilidade Quartus)"
# shellcheck disable=SC2086
ghdl -a --std=93 --workdir="$WORK93" $RTL
ghdl -e --std=93 --workdir="$WORK93" -o "$WORK93/top" fp_adder_de10lite

banner "0b. RTL elabora ate netlist (ghdl --synth)"
mkdir -p build_synth
ghdl --synth --std=93 --workdir=build_synth \
     rtl/fp_adder_fixed.vhd rtl/hex_to_sseg.vhd rtl/debounce.vhd rtl/fp_adder_de10lite.vhd \
     -e fp_adder_de10lite > build_synth/netlist.vhd

banner "Analise (VHDL-2008)"
# shellcheck disable=SC2086
ghdl -a $STD --workdir="$WORK" $RTL
# shellcheck disable=SC2086
ghdl -a $STD --workdir="$WORK" $SIM

banner "1. ETAPA 1 - validacao do VHDL original do livro"
ghdl -e $STD --workdir="$WORK" -o "$WORK/tb_fp_adder_orig" tb_fp_adder_orig
ghdl -r $STD --workdir="$WORK" tb_fp_adder_orig

banner "2. ETAPA 2 - validacao do nucleo adaptado"
ghdl -e $STD --workdir="$WORK" -o "$WORK/tb_fp_adder_fixed" tb_fp_adder_fixed
ghdl -r $STD --workdir="$WORK" tb_fp_adder_fixed

banner "3. ETAPA 2/3 - nivel de topo pela interface da DE10-Lite"
ghdl -e $STD --workdir="$WORK" -o "$WORK/tb_fp_adder_de10lite" tb_fp_adder_de10lite
ghdl -r $STD --workdir="$WORK" tb_fp_adder_de10lite

banner "4. Caracterizacao numerica (algoritmo x soma exata)"
# Percorre os 16.793.604 pares de operandos legais. Leva cerca de um minuto.
ghdl -e $STD --workdir="$WORK" -o "$WORK/tb_fp_precision" tb_fp_precision
ghdl -r $STD --workdir="$WORK" tb_fp_precision

banner "5. Geracao de artefatos: formas de onda e tabela dos casos dirigidos"
ghdl -e $STD --workdir="$WORK" -o "$WORK/tb_fp_adder_waves" tb_fp_adder_waves
ghdl -r $STD --workdir="$WORK" tb_fp_adder_waves \
     --vcd=sim/waves/fp_adder_waves.vcd \
     --wave=sim/waves/fp_adder_waves.ghw

echo
echo "=============================================================="
echo " TUDO PASSOU"
echo "=============================================================="
echo " Formas de onda: gtkwave sim/waves/fp_adder_waves.ghw sim/waves/fp_adder_waves.gtkw"
