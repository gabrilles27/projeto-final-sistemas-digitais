#===============================================================================
# run_questa.do
#
# Script de regressao para o Questa/ModelSim. Executar a partir da raiz do
# projeto:
#
#     vsim -c -do sim/run_questa.do          # modo linha de comando
#     do sim/run_questa.do                   # de dentro da GUI do Questa
#
# Roda os quatro passos de verificacao e, no fim, deixa carregado o testbench de
# formas de onda com os sinais dos quatro estagios adicionados na janela Wave.
#
# O passo 4 (caracterizacao numerica) percorre os 16.793.604 pares de operandos
# legais e leva cerca de um minuto.
#===============================================================================

if {[file exists work]} { vdel -all -lib work }
vlib work
vmap work work

echo "=== Compilando ==="
vcom -2008 -work work rtl/fp_adder.vhd
vcom -2008 -work work rtl/fp_adder_fixed.vhd
vcom -2008 -work work rtl/hex_to_sseg.vhd
vcom -2008 -work work rtl/debounce.vhd
vcom -2008 -work work rtl/fp_adder_de10lite.vhd
vcom -2008 -work work sim/fp_pkg.vhd
vcom -2008 -work work sim/tb_fp_adder_orig.vhd
vcom -2008 -work work sim/tb_fp_adder_fixed.vhd
vcom -2008 -work work sim/tb_fp_adder_de10lite.vhd
vcom -2008 -work work sim/tb_fp_precision.vhd
vcom -2008 -work work sim/tb_fp_adder_waves.vhd

echo "=== ETAPA 1 - validacao do VHDL original ==="
vsim -c work.tb_fp_adder_orig
run -all
quit -sim

echo "=== ETAPA 2 - validacao do nucleo adaptado ==="
vsim -c work.tb_fp_adder_fixed
run -all
quit -sim

echo "=== ETAPA 2/3 - nivel de topo da DE10-Lite ==="
vsim -c work.tb_fp_adder_de10lite
run -all
quit -sim

echo "=== Caracterizacao numerica (algoritmo x soma exata) ==="
vsim -c work.tb_fp_precision
run -all
quit -sim

echo "=== Geracao de artefatos: formas de onda dos casos dirigidos ==="
vsim work.tb_fp_adder_waves

add wave -divider "ENTRADAS"
add wave -radix binary /tb_fp_adder_waves/sign1
add wave -radix hex    /tb_fp_adder_waves/exp1
add wave -radix hex    /tb_fp_adder_waves/frac1
add wave -radix binary /tb_fp_adder_waves/sign2
add wave -radix hex    /tb_fp_adder_waves/exp2
add wave -radix hex    /tb_fp_adder_waves/frac2

add wave -divider "1o ESTAGIO - ORDENACAO"
add wave -radix binary /tb_fp_adder_waves/dut_orig/signb
add wave -radix hex    /tb_fp_adder_waves/dut_orig/expb
add wave -radix hex    /tb_fp_adder_waves/dut_orig/fracb
add wave -radix hex    /tb_fp_adder_waves/dut_orig/fracs

add wave -divider "2o ESTAGIO - ALINHAMENTO"
add wave -radix unsigned /tb_fp_adder_waves/expdiff_dbg
add wave -radix hex      /tb_fp_adder_waves/dut_orig/fraca

add wave -divider "3o ESTAGIO - SOMA/SUBTRACAO"
add wave -radix unsigned /tb_fp_adder_waves/sum_dbg
add wave -radix binary   /tb_fp_adder_waves/carry_dbg

add wave -divider "4o ESTAGIO - NORMALIZACAO"
add wave -radix unsigned /tb_fp_adder_waves/leado_dbg
add wave -radix hex      /tb_fp_adder_waves/dut_orig/sum_norm
add wave -radix binary   /tb_fp_adder_waves/zero_dbg
add wave -radix binary   /tb_fp_adder_waves/ovf_dbg

add wave -divider "SAIDA - NUCLEO ORIGINAL"
add wave -radix binary /tb_fp_adder_waves/orig_sign
add wave -radix hex    /tb_fp_adder_waves/orig_exp
add wave -radix hex    /tb_fp_adder_waves/orig_frac

add wave -divider "SAIDA - NUCLEO ADAPTADO"
add wave -radix binary /tb_fp_adder_waves/new_sign
add wave -radix hex    /tb_fp_adder_waves/new_exp
add wave -radix hex    /tb_fp_adder_waves/new_frac

add wave -divider "DIVERGENCIA / CASO"
add wave -radix binary   /tb_fp_adder_waves/divergem
add wave -radix unsigned /tb_fp_adder_waves/case_id

run -all
wave zoom full
