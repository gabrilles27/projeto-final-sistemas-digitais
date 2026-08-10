--------------------------------------------------------------------------------
-- fp_adder_fixed.vhd
--
-- ETAPA 2 - Nucleo do somador adaptado para a DE10-Lite.
--
-- Mantem o algoritmo de 4 estagios do livro (ordenar / alinhar / somar /
-- normalizar) e a mesma interface de dados. As mudancas em relacao ao
-- rtl/fp_adder.vhd original estao marcadas com [D1], [D2], [D3] e [ADAPT]:
--
--   [D1] Zero canonico. O original faz "sign_out <= signb" sempre, entao um
--        resultado nulo vindo de um operando negativo sai como "menos zero"
--        (na placa: o display mostraria o traco de menos junto de 00.0). Aqui
--        o sinal e forcado a '0' sempre que o resultado for zero.
--
--   [D2] Cancelamento exato. O contador de zeros a esquerda do original satura
--        em 7 e usa o mesmo codigo "111" para sum = 0 e para sum = 1. Com isso,
--        quando os dois operandos se cancelam e o expoente do maior e >= 7, o
--        teste de underflow (leado > expb) nao dispara e a saida fica
--        e = expb-7 com f = 0 - uma representacao invalida, ja que o formato
--        exige "normalizado ou zero". A correcao e um sinal explicito de
--        resultado nulo, testado antes de tudo.
--
--   [D3] Estouro de expoente. Se ha carry-out e o expoente do maior operando ja
--        e 15, expb+1 da a volta para 0 e o maior numero da faixa vira o menor.
--        Aqui o resultado satura no maior valor representavel
--        (0.11111111 x 2^15) e a condicao e sinalizada em dbg_ovf.
--
--   [ADAPT] Os dois deslocadores descritos por "with ... select" (9 e 8 linhas)
--        foram trocados por shift_right/shift_left do numeric_std. O hardware
--        gerado e o mesmo barrel shifter, mas o codigo deixa de repetir a
--        tabela - e o testbench tb_fp_adder_fixed prova a equivalencia vetor a
--        vetor contra a versao original.
--
--   [ADAPT] Saidas de diagnostico (dbg_*) foram acrescentadas para levar os
--        sinais internos dos estagios 2, 3 e 4 ate os LEDs da placa. Sao
--        saidas puras: podem ser deixadas em "open" sem afetar o resultado.
--
-- O codigo e VHDL-93, para compilar tanto no GHDL quanto no Quartus Prime Lite
-- sem depender da opcao VHDL-2008.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fp_adder_fixed is
   port(
      -- Operando 1 e operando 2, formato simplificado de 13 bits.
      sign1, sign2 : in  std_logic;
      exp1, exp2   : in  std_logic_vector(3 downto 0);
      frac1, frac2 : in  std_logic_vector(7 downto 0);
      -- Resultado.
      sign_out     : out std_logic;
      exp_out      : out std_logic_vector(3 downto 0);
      frac_out     : out std_logic_vector(7 downto 0);
      -- Diagnostico (opcional, pode ficar em "open").
      dbg_exp_diff : out std_logic_vector(3 downto 0);  -- deslocamento do 2o estagio
      dbg_leado    : out std_logic_vector(2 downto 0);  -- zeros a esquerda, 4o estagio
      dbg_carry    : out std_logic;                     -- carry-out do 3o estagio
      dbg_zero     : out std_logic;                     -- resultado nulo
      dbg_ovf      : out std_logic                      -- saturacao por estouro
   );
end fp_adder_fixed;

architecture arch of fp_adder_fixed is
   -- Sufixos b, s, a, n: numero maior, menor, alinhado e normalizado.
   signal signb, signs               : std_logic;
   signal expb, exps, expn           : unsigned(3 downto 0);
   signal fracb, fracs, fraca, fracn : unsigned(7 downto 0);
   signal sum_norm                   : unsigned(7 downto 0);
   signal exp_diff                   : unsigned(3 downto 0);
   signal sum                        : unsigned(8 downto 0);  -- 1 bit extra p/ o carry
   signal leado                      : unsigned(2 downto 0);
   signal signn                      : std_logic;
   signal is_zero                    : std_logic;
   signal is_ovf                     : std_logic;
begin

   ----------------------------------------------------------------------------
   -- 1o estagio: ordenar, colocando o de maior magnitude em (signb, expb, fracb).
   --
   -- A comparacao e feita sobre o padrao de bits exp&frac. Isso equivale a
   -- comparar as magnitudes porque o formato exige que todo operando esteja
   -- normalizado (bit 7 do significando em '1') ou seja exatamente zero.
   --
   -- [ADAPT] O livro escreve "(exp1 & frac1) > (exp2 & frac2)", que compara
   -- dois std_logic_vector usando o operador implicito de ordenacao de arrays.
   -- O resultado e o mesmo para vetores de '0'/'1' de igual comprimento, mas a
   -- comparacao e lexicografica sobre o tipo enumerado, nao numerica - e o GHDL
   -- avisa ("comparing non-numeric vector is unexpected"). A conversao
   -- explicita para unsigned diz o que se quer de fato, elimina o aviso e nao
   -- muda o hardware (a equivalencia e verificada em tb_fp_adder_fixed).
   ----------------------------------------------------------------------------
   process(sign1, sign2, exp1, exp2, frac1, frac2)
   begin
      if unsigned(exp1 & frac1) > unsigned(exp2 & frac2) then
         signb <= sign1;
         signs <= sign2;
         expb  <= unsigned(exp1);
         exps  <= unsigned(exp2);
         fracb <= unsigned(frac1);
         fracs <= unsigned(frac2);
      else
         signb <= sign2;
         signs <= sign1;
         expb  <= unsigned(exp2);
         exps  <= unsigned(exp1);
         fracb <= unsigned(frac2);
         fracs <= unsigned(frac1);
      end if;
   end process;

   ----------------------------------------------------------------------------
   -- 2o estagio: alinhar o menor, deslocando seu significando a direita pela
   -- diferenca de expoentes. Os bits que saem sao descartados (sem
   -- arredondamento, como no projeto original).
   --
   -- [ADAPT] shift_right ja devolve tudo zero quando a contagem passa da
   -- largura do vetor, o que cobre o caso exp_diff >= 8 sem uma linha extra.
   ----------------------------------------------------------------------------
   exp_diff <= expb - exps;
   fraca    <= shift_right(fracs, to_integer(exp_diff));

   ----------------------------------------------------------------------------
   -- 3o estagio: soma/subtracao em sinal-magnitude. Os operandos sao estendidos
   -- em 1 bit para acomodar o carry-out.
   ----------------------------------------------------------------------------
   sum <= ('0' & fracb) + ('0' & fraca) when signb = signs else
          ('0' & fracb) - ('0' & fraca);

   ----------------------------------------------------------------------------
   -- 4o estagio: normalizacao.
   ----------------------------------------------------------------------------

   -- [D2] Deteccao explicita de resultado nulo. E este sinal - e nao o valor
   -- saturado do contador de zeros - que decide o caso de cancelamento exato.
   is_zero <= '1' when sum = 0 else '0';

   -- Contagem de zeros a esquerda (codificador de prioridade sobre sum(7..0)).
   -- Satura em 7, como no livro, mas aqui isso e inofensivo: o caso sum = 0 ja
   -- foi tratado por is_zero.
   leado <= "000" when (sum(7) = '1') else
            "001" when (sum(6) = '1') else
            "010" when (sum(5) = '1') else
            "011" when (sum(4) = '1') else
            "100" when (sum(3) = '1') else
            "101" when (sum(2) = '1') else
            "110" when (sum(1) = '1') else
            "111";

   -- [ADAPT] Deslocamento a esquerda pela quantidade de zeros contados.
   sum_norm <= shift_left(sum(7 downto 0), to_integer(leado));

   -- Montagem do resultado normalizado.
   process(sum, sum_norm, expb, leado, signb, is_zero)
   begin
      if is_zero = '1' then
         -- [D2] Cancelamento exato: zero canonico, independente do expoente.
         -- [D1] Zero nao carrega sinal.
         signn  <= '0';
         expn   <= (others => '0');
         fracn  <= (others => '0');
         is_ovf <= '0';

      elsif sum(8) = '1' then
         -- Carry-out: desloca o significando uma casa a direita, expoente + 1.
         if expb = "1111" then
            -- [D3] Expoente ja no maximo: satura em vez de dar a volta.
            signn  <= signb;
            expn   <= (others => '1');
            fracn  <= (others => '1');
            is_ovf <= '1';
         else
            signn  <= signb;
            expn   <= expb + 1;
            fracn  <= sum(8 downto 1);
            is_ovf <= '0';
         end if;

      elsif leado > expb then
         -- Menor que o menor normalizado (0.10000000 x 2^0): converte para zero.
         -- [D1] Tambem aqui o zero sai sem sinal.
         signn  <= '0';
         expn   <= (others => '0');
         fracn  <= (others => '0');
         is_ovf <= '0';

      else
         signn  <= signb;
         expn   <= expb - leado;
         fracn  <= sum_norm;
         is_ovf <= '0';
      end if;
   end process;

   ----------------------------------------------------------------------------
   -- Saidas
   ----------------------------------------------------------------------------
   sign_out <= signn;
   exp_out  <= std_logic_vector(expn);
   frac_out <= std_logic_vector(fracn);

   dbg_exp_diff <= std_logic_vector(exp_diff);
   dbg_leado    <= std_logic_vector(leado);
   dbg_carry    <= sum(8);
   dbg_zero     <= is_zero;
   dbg_ovf      <= is_ovf;

end arch;
