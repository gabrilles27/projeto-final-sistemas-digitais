--------------------------------------------------------------------------------
-- tb_fp_adder_waves.vhd
--
-- Testbench curto, que gera formas de onda legiveis no GTKWave e no
-- Questa. Os testbenches de regressao rodam centenas de milhares de vetores e
-- nao servem para inspecao visual; este roda so os casos dirigidos, um a
-- cada 100 ns, com os dois nucleos lado a lado.
--
-- ATENCAO: este passo GERA ARTEFATOS (o .ghw, o .vcd e a tabela .csv de onde
-- sai a figura do relatorio). Ele nao substitui a regressao. Mesmo assim ele
-- confere cada caso contra os modelos de fp_pkg - sem isso, uma figura gerada
-- a partir de saidas erradas entraria no relatorio sem ninguem notar.
--
-- Os sinais que interessam para a analise do 4o estagio (normalizacao) estao
-- replicados aqui no nivel de topo do testbench, com nomes curtos, para que
-- aparecam na primeira tela do visualizador sem precisar navegar na hierarquia:
--
--   sum_dbg     - resultado do 3o estagio, 9 bits (o bit 8 e o carry-out)
--   leado_dbg   - zeros a esquerda contados no 4o estagio
--   expdiff_dbg - deslocamento de alinhamento do 2o estagio
--   carry_dbg   - carry-out
--   zero_dbg    - cancelamento exato
--   ovf_dbg     - saturacao por estouro de expoente
--   case_id     - indice do caso dirigido em execucao
--
-- Os quatro cenarios de normalizacao pedidos no enunciado aparecem nos casos
-- C1 (carry-out), C2 (subtracao com 1 deslocamento a esquerda, leado = 1),
-- C3 (7 deslocamentos a esquerda) e C4 (resultado convertido para zero).
-- O caso sem deslocamento nenhum (leado = 0) e o C0. Os casos C5, C6 e C10
-- mostram os defeitos D2, D3 e D1: neles as saidas dos dois nucleos divergem
-- na mesma janela de tempo, o que fica evidente na forma de onda.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library std;
use std.textio.all;

library work;
use work.fp_pkg.all;

entity tb_fp_adder_waves is
   generic (
      -- Alem das formas de onda, o testbench grava uma tabela com o valor de
      -- todos os sinais em cada caso. E dessa tabela que sai o diagrama do
      -- relatorio, entao o desenho vem dos dados reais da simulacao.
      CSV_FILE : string := "sim/waves/directed_cases.csv"
   );
end entity;

architecture tb of tb_fp_adder_waves is

   constant STEP : time := 100 ns;

   -- Entradas
   signal sign1, sign2 : std_logic := '0';
   signal exp1,  exp2  : std_logic_vector(3 downto 0) := (others => '0');
   signal frac1, frac2 : std_logic_vector(7 downto 0) := (others => '0');

   -- Saidas do nucleo original (livro)
   signal orig_sign : std_logic;
   signal orig_exp  : std_logic_vector(3 downto 0);
   signal orig_frac : std_logic_vector(7 downto 0);

   -- Saidas do nucleo adaptado (DE10-Lite)
   signal new_sign : std_logic;
   signal new_exp  : std_logic_vector(3 downto 0);
   signal new_frac : std_logic_vector(7 downto 0);

   -- Sinais internos trazidos para o topo do testbench
   signal expdiff_dbg : std_logic_vector(3 downto 0);
   signal leado_dbg   : std_logic_vector(2 downto 0);
   signal carry_dbg   : std_logic;
   signal zero_dbg    : std_logic;
   signal ovf_dbg     : std_logic;
   signal sum_dbg     : std_logic_vector(8 downto 0);

   -- Marcadores de leitura da forma de onda
   signal case_id  : integer range -1 to 63 := -1;
   signal divergem : std_logic := '0';   -- '1' quando os dois nucleos discordam

begin

   ----------------------------------------------------------------------------
   dut_orig : entity work.fp_adder
      port map (
         sign1 => sign1, sign2 => sign2,
         exp1  => exp1,  exp2  => exp2,
         frac1 => frac1, frac2 => frac2,
         sign_out => orig_sign, exp_out => orig_exp, frac_out => orig_frac
      );

   dut_new : entity work.fp_adder_fixed
      port map (
         sign1 => sign1, sign2 => sign2,
         exp1  => exp1,  exp2  => exp2,
         frac1 => frac1, frac2 => frac2,
         sign_out => new_sign, exp_out => new_exp, frac_out => new_frac,
         dbg_exp_diff => expdiff_dbg,
         dbg_leado    => leado_dbg,
         dbg_carry    => carry_dbg,
         dbg_zero     => zero_dbg,
         dbg_ovf      => ovf_dbg
      );

   ----------------------------------------------------------------------------
   -- Reconstrucao do barramento sum do 3o estagio, para que ele apareca na
   -- forma de onda sem depender de sondar a hierarquia interna do DUT.
   ----------------------------------------------------------------------------
   sum_rebuild : process(sign1, sign2, exp1, exp2, frac1, frac2)
      variable big_f, small_f : unsigned(7 downto 0);
      variable big_e, small_e : unsigned(3 downto 0);
      variable bs, ss         : std_logic;
      variable fa             : unsigned(7 downto 0);
   begin
      if (exp1 & frac1) > (exp2 & frac2) then
         bs := sign1; ss := sign2;
         big_e := unsigned(exp1); small_e := unsigned(exp2);
         big_f := unsigned(frac1); small_f := unsigned(frac2);
      else
         bs := sign2; ss := sign1;
         big_e := unsigned(exp2); small_e := unsigned(exp1);
         big_f := unsigned(frac2); small_f := unsigned(frac1);
      end if;
      fa := shift_right(small_f, to_integer(big_e - small_e));
      if bs = ss then
         sum_dbg <= std_logic_vector(('0' & big_f) + ('0' & fa));
      else
         sum_dbg <= std_logic_vector(('0' & big_f) - ('0' & fa));
      end if;
   end process;

   divergem <= '1' when (orig_sign /= new_sign)
                     or (orig_exp  /= new_exp)
                     or (orig_frac /= new_frac) else '0';

   ----------------------------------------------------------------------------
   stim : process
      file     csv   : text;
      variable l     : line;
      variable st    : file_open_status;
      variable n_err : natural := 0;

      function sl(b : std_logic) return string is
      begin
         if b = '1' then
            return "1";
         else
            return "0";
         end if;
      end function;

      procedure apply(i : natural) is
         variable alg : fp_alg_t;
      begin
         case_id <= i;
         sign1 <= DIR_A(i).s;  exp1 <= DIR_A(i).e;  frac1 <= DIR_A(i).f;
         sign2 <= DIR_B(i).s;  exp2 <= DIR_B(i).e;  frac2 <= DIR_B(i).f;

         -- Amostra no meio da janela, com o circuito combinacional ja estavel.
         wait for STEP / 2;

         -- Auto-verificacao: a figura do relatorio so vale se os dados dela
         -- estiverem certos.
         alg := fp_add_alg(DIR_A(i), DIR_B(i));
         if (new_sign, new_exp, new_frac) /= alg.r then
            n_err := n_err + 1;
            report "caso " & integer'image(i) & ": nucleo adaptado deu "
                   & fp_str((new_sign, new_exp, new_frac))
                   & " e deveria dar " & fp_str(alg.r)
                   severity error;
         end if;
         if (orig_sign, orig_exp, orig_frac) /= alg.book then
            n_err := n_err + 1;
            report "caso " & integer'image(i) & ": nucleo do livro deu "
                   & fp_str((orig_sign, orig_exp, orig_frac))
                   & " e deveria dar " & fp_str(alg.book)
                   severity error;
         end if;
         if (divergem = '1') /= (alg.r /= alg.book) then
            n_err := n_err + 1;
            report "caso " & integer'image(i) & ": marcador 'divergem' errado"
                   severity error;
         end if;

         write(l, integer'image(i) & ";" & dir_name(i)
                  & ";" & sl(sign1) & ";" & hstr(exp1) & ";" & hstr(frac1)
                  & ";" & sl(sign2) & ";" & hstr(exp2) & ";" & hstr(frac2)
                  & ";" & hstr(expdiff_dbg)
                  & ";" & integer'image(to_integer(unsigned(sum_dbg)))
                  & ";" & integer'image(to_integer(unsigned(leado_dbg)))
                  & ";" & sl(carry_dbg) & ";" & sl(zero_dbg) & ";" & sl(ovf_dbg)
                  & ";" & sl(orig_sign) & ";" & hstr(orig_exp) & ";" & hstr(orig_frac)
                  & ";" & sl(new_sign)  & ";" & hstr(new_exp)  & ";" & hstr(new_frac)
                  & ";" & sl(divergem));
         writeline(csv, l);
         wait for STEP / 2;
      end procedure;
   begin
      report "Gerando formas de onda dos " & integer'image(N_DIR)
             & " casos dirigidos (100 ns por caso).";

      file_open(st, csv, CSV_FILE, write_mode);
      assert st = open_ok
         report "Nao foi possivel abrir " & CSV_FILE
                & ". Rode o simulador a partir da raiz do projeto."
         severity failure;

      write(l, string'("case;nome;s1;e1;f1;s2;e2;f2;exp_diff;sum;leado;carry;"
                       & "zero;ovf;orig_s;orig_e;orig_f;new_s;new_e;new_f;divergem"));
      writeline(csv, l);

      wait for STEP;                       -- janela inicial em repouso
      for i in 0 to N_DIR - 1 loop
         apply(i);
      end loop;
      case_id <= -1;
      wait for STEP;

      file_close(csv);

      assert n_err = 0
         report "Os dados da figura do relatorio nao conferem com os modelos."
         severity failure;

      report "Formas de onda e tabela geradas e conferidas ("
             & integer'image(N_DIR) & " casos).";
      wait;
   end process;

end architecture;
