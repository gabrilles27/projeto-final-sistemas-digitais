#===============================================================================
# fp_adder_de10lite.sdc
#
# Restricoes de tempo (TimeQuest / Timing Analyzer).
#
# O somador em si e combinacional: o clock so existe por causa do anti-repique
# e dos registradores de operando. Por isso a unica restricao real e o clock de
# 50 MHz da placa; chaves, botoes, LEDs e displays sao assincronos em relacao a
# ele e ficam como false path, o que evita que o Timing Analyzer reporte
# violacoes que nao tem significado fisico aqui.
#===============================================================================

create_clock -name {MAX10_CLK1_50} -period 20.000 [get_ports {MAX10_CLK1_50}]

derive_clock_uncertainty

# Entradas assincronas: chaves e botoes (os botoes passam por sincronizador
# de dois flip-flops dentro do projeto).
set_false_path -from [get_ports {SW[*]}]  -to [all_registers]
set_false_path -from [get_ports {KEY[*]}] -to [all_registers]

# Saidas puramente visuais: nenhum requisito de tempo.
set_false_path -from * -to [get_ports {LEDR[*]}]
set_false_path -from * -to [get_ports {HEX0[*]}]
set_false_path -from * -to [get_ports {HEX1[*]}]
set_false_path -from * -to [get_ports {HEX2[*]}]
set_false_path -from * -to [get_ports {HEX3[*]}]
set_false_path -from * -to [get_ports {HEX4[*]}]
set_false_path -from * -to [get_ports {HEX5[*]}]
