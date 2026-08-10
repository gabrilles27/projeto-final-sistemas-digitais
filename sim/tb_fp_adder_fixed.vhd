--------------------------------------------------------------------------------
-- tb_fp_adder_fixed.vhd
--
-- Etapa 2 - verificacao de que a adaptacao para a DE10-Lite preservou a logica
-- matematica do nucleo original.
--
-- Aplica o mesmo estimulo do tb_fp_adder_orig (mesmos casos dirigidos, mesmas
-- varreduras, mesma semente do gerador) aos dois nucleos simultaneamente e
-- verifica quatro condicoes, todas com tolerancia zero:
--
--   (1) o nucleo adaptado coincide bit a bit com o modelo do algoritmo
--       corrigido;
--
--   (2) os sinais de diagnostico (exp_diff, leado, carry, zero, ovf) que vao
--       para os LEDs tambem coincidem, o que estende a verificacao aos estagios
--       intermediarios e nao apenas a saida;
--
--   (3) o nucleo original coincide bit a bit com o modelo do algoritmo do
--       livro, e onde os dois nucleos divergem a diferenca e a prevista por
--       D1/D2/D3, com o valor previsto exigido em cada vetor;
--
--   (4) a cobertura do estimulo e medida, e nao estimada: o testbench registra
--       quais dos 4098 operandos legais foram efetivamente aplicados e quantos
--       operandos distintos o gerador pseudoaleatorio alcanca.
--
-- A condicao (3) e a comparacao vetor a vetor entre os dois nucleos, e nao uma
-- inspecao do codigo.
--
-- A exatidao numerica do algoritmo esta fora do escopo deste testbench: os dois
-- nucleos implementam o mesmo algoritmo e erram juntos. Ela e medida em
-- sim/tb_fp_precision.vhd, contra o oraculo fp_add_exact.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.fp_pkg.all;

entity tb_fp_adder_fixed is
   generic (
      RUN_SWEEP  : boolean := true;
      RUN_COVER  : boolean := true;
      RUN_RANDOM : boolean := true;
      N_RANDOM   : natural := 100000
   );
end entity;

architecture tb of tb_fp_adder_fixed is

   signal a, b : fp_op_t := FP_ZERO;

   -- Nucleo adaptado
   signal n_sign : std_logic;
   signal n_exp  : std_logic_vector(3 downto 0);
   signal n_frac : std_logic_vector(7 downto 0);
   signal n_diff : std_logic_vector(3 downto 0);
   signal n_lead : std_logic_vector(2 downto 0);
   signal n_cy   : std_logic;
   signal n_zero : std_logic;
   signal n_ovf  : std_logic;

   -- Nucleo original, para a comparacao lado a lado
   signal o_sign : std_logic;
   signal o_exp  : std_logic_vector(3 downto 0);
   signal o_frac : std_logic_vector(7 downto 0);

begin

   ----------------------------------------------------------------------------
   dut_new : entity work.fp_adder_fixed
      port map (
         sign1 => a.s, sign2 => b.s,
         exp1  => a.e, exp2  => b.e,
         frac1 => a.f, frac2 => b.f,
         sign_out => n_sign, exp_out => n_exp, frac_out => n_frac,
         dbg_exp_diff => n_diff, dbg_leado => n_lead,
         dbg_carry => n_cy, dbg_zero => n_zero, dbg_ovf => n_ovf
      );

   dut_ref : entity work.fp_adder
      port map (
         sign1 => a.s, sign2 => b.s,
         exp1  => a.e, exp2  => b.e,
         frac1 => a.f, frac2 => b.f,
         sign_out => o_sign, exp_out => o_exp, frac_out => o_frac
      );

   ----------------------------------------------------------------------------
   stim : process
      variable n_total  : natural := 0;
      variable n_fail   : natural := 0;   -- (1) adaptado != modelo corrigido
      variable n_dbgerr : natural := 0;   -- (2) sinais internos errados
      variable n_olderr : natural := 0;   -- (3) original != modelo do livro
      variable n_diff_d : natural := 0;   -- (3) os dois nucleos diferem, previsto
      variable n_diff_x : natural := 0;   -- (3) diferem fora do previsto
      variable shown    : natural := 0;
      variable rnd      : rnd_t := RND_SEED;
      variable ra, rb   : fp_op_t;

      -- (4) cobertura: quais operandos legais foram realmente aplicados.
      variable cov   : cover_t := (others => false);
      variable n_cov : natural := 0;

      procedure check(x, y : fp_op_t; verbose : boolean) is
         variable alg  : fp_alg_t;
         variable got  : fp_op_t;
         variable old  : fp_op_t;
         variable want : fp_op_t;
      begin
         a <= x;
         b <= y;
         wait for 5 ns;

         alg     := fp_add_alg(x, y);
         got     := (n_sign, n_exp, n_frac);
         old     := (o_sign, o_exp, o_frac);
         n_total := n_total + 1;

         cov(op_code(x)) := true;
         cov(op_code(y)) := true;

         -- A premissa do formato vale para todo o estimulo aplicado ao nucleo.
         assert not alg.bad_input
            report "ESTIMULO INVALIDO (viola 'normalizado ou zero'): A = "
                   & fp_str(x) & "  B = " & fp_str(y)
            severity failure;

         ----------------------------------------------------------------------
         -- (1) resultado do nucleo adaptado
         ----------------------------------------------------------------------
         if got /= alg.r then
            n_fail := n_fail + 1;
            if shown < 20 then
               shown := shown + 1;
               report "RESULTADO DIVERGENTE DO MODELO DO ALGORITMO" & LF
                      & "   A       = " & fp_str(x) & LF
                      & "   B       = " & fp_str(y) & LF
                      & "   obtido  = " & fp_str(got) & LF
                      & "   esperado= " & fp_str(alg.r)
                      severity error;
            end if;
         elsif verbose then
            report "   OK       " & fp_str(got);
         end if;

         ----------------------------------------------------------------------
         -- (2) sinais internos levados aos LEDs
         ----------------------------------------------------------------------
         if to_integer(unsigned(n_diff)) /= alg.exp_diff
            or to_integer(unsigned(n_lead)) /= alg.leado
            or (n_cy = '1') /= alg.carry
            or (n_zero = '1') /= alg.exact_cancel
            or (n_ovf = '1') /= alg.overflow
         then
            n_dbgerr := n_dbgerr + 1;
            if shown < 20 then
               shown := shown + 1;
               report "DIAGNOSTICO DIVERGENTE" & LF
                      & "   A = " & fp_str(x) & "  B = " & fp_str(y) & LF
                      & "   exp_diff obtido=" & integer'image(to_integer(unsigned(n_diff)))
                      & " esperado=" & integer'image(alg.exp_diff) & LF
                      & "   leado    obtido=" & integer'image(to_integer(unsigned(n_lead)))
                      & " esperado=" & integer'image(alg.leado)
                      severity error;
            end if;
         end if;

         ----------------------------------------------------------------------
         -- (3) o nucleo original tem de reproduzir o modelo do livro, bit a
         --     bit, e a diferenca entre os dois nucleos tem de ser a prevista.
         ----------------------------------------------------------------------
         if old /= alg.book then
            n_olderr := n_olderr + 1;
            if shown < 20 then
               shown := shown + 1;
               report "O NUCLEO ORIGINAL NAO BATE COM O MODELO DO LIVRO" & LF
                      & "   A        = " & fp_str(x) & LF
                      & "   B        = " & fp_str(y) & LF
                      & "   obtido   = " & fp_str(old) & LF
                      & "   previsto = " & fp_str(alg.book)
                      severity error;
            end if;
         end if;

         if old /= got then
            -- Valor previsto para a diferenca, por familia de defeito.
            if alg.exact_cancel and alg.expb >= 8 then
               want := (alg.signb,
                        std_logic_vector(to_unsigned(alg.expb - 7, 4)),
                        "00000000");                                  -- D2
            elsif alg.overflow then
               want := (alg.signb, "0000",
                        std_logic_vector(to_unsigned(alg.sum9 / 2, 8)));  -- D3
            else
               want := (alg.signb, "0000", "00000000");               -- D1
            end if;

            if old = want and got = alg.r then
               n_diff_d := n_diff_d + 1;
            else
               n_diff_x := n_diff_x + 1;
               if shown < 20 then
                  shown := shown + 1;
                  report "DIFERENCA ENTRE OS NUCLEOS FORA DO PREVISTO" & LF
                         & "   A        = " & fp_str(x) & LF
                         & "   B        = " & fp_str(y) & LF
                         & "   original = " & fp_str(old) & LF
                         & "   previsto = " & fp_str(want) & LF
                         & "   adaptado = " & fp_str(got)
                         severity error;
               end if;
            end if;
         end if;
      end procedure;

   begin
      report "==================================================================";
      report " ETAPA 2 - validacao do nucleo adaptado (fp_adder_fixed)";
      report "==================================================================";

      report "--- Casos dirigidos ---";
      for i in 0 to N_DIR - 1 loop
         report dir_name(i);
         report "   A = " & fp_str(DIR_A(i)) & "   B = " & fp_str(DIR_B(i));
         check(DIR_A(i), DIR_B(i), true);
      end loop;

      if RUN_SWEEP then
         report "--- Varredura densa (expoentes x sinais x significandos) ---";
         for e1 in 0 to 15 loop
            for e2 in 0 to 15 loop
               for s1 in 0 to 1 loop
                  for s2 in 0 to 1 loop
                     for i1 in FRACS'range loop
                        for i2 in FRACS'range loop
                           check(op_from(s1, e1, FRACS(i1)),
                                 op_from(s2, e2, FRACS(i2)), false);
                        end loop;
                     end loop;
                  end loop;
               end loop;
            end loop;
         end loop;

         report "--- Varredura com operando zero ---";
         for e2 in 0 to 15 loop
            for s2 in 0 to 1 loop
               for i2 in FRACS'range loop
                  check(FP_ZERO, op_from(s2, e2, FRACS(i2)), false);
                  check(op_from(s2, e2, FRACS(i2)), FP_ZERO, false);
               end loop;
            end loop;
         end loop;
         check(FP_ZERO, FP_ZERO, false);
      end if;

      if RUN_COVER then
         report "--- Varredura de cobertura (todos os operandos legais) ---";
         for s in 0 to 1 loop
            for e in 0 to 15 loop
               for fi in 128 to 255 loop
                  for k in 0 to COVER_N - 1 loop
                     check(op_from(s, e, std_logic_vector(to_unsigned(fi, 8))),
                           COVER_B(k), false);
                     check(COVER_B(k),
                           op_from(s, e, std_logic_vector(to_unsigned(fi, 8))),
                           false);
                  end loop;
               end loop;
            end loop;
         end loop;
         for s in 0 to 1 loop
            for k in 0 to COVER_N - 1 loop
               check(op_from(s, 0, "00000000"), COVER_B(k), false);
               check(COVER_B(k), op_from(s, 0, "00000000"), false);
            end loop;
         end loop;
      end if;

      if RUN_RANDOM then
         report "--- Vetores pseudoaleatorios ---";
         for i in 1 to N_RANDOM loop
            rand_op(rnd, ra);
            rand_op(rnd, rb);
            check(ra, rb, false);
         end loop;
      end if;

      -------------------------------------------------------------------------
      -- (4) cobertura medida
      -------------------------------------------------------------------------
      n_cov := 0;
      for c in 0 to 8191 loop
         if cov(c) then
            n_cov := n_cov + 1;
         end if;
      end loop;

      report "==================================================================";
      report " RESUMO ETAPA 2";
      report "   vetores aplicados ......................... " & integer'image(n_total);
      report "   (1) adaptado != modelo corrigido .......... " & integer'image(n_fail);
      report "   (2) diagnosticos divergentes .............. " & integer'image(n_dbgerr);
      report "   (3) original != modelo do livro ........... " & integer'image(n_olderr);
      report "   (3) nucleos diferem, valor previsto ....... " & integer'image(n_diff_d);
      report "   (3) nucleos diferem, valor imprevisto ..... " & integer'image(n_diff_x);
      report "   (4) operandos legais aplicados ............ " & integer'image(n_cov)
             & " de " & integer'image(N_LEGAL_OPS);
      report "==================================================================";

      assert n_fail = 0
         report "ETAPA 2 REPROVADA: o nucleo adaptado nao bate com o modelo."
         severity failure;
      assert n_dbgerr = 0
         report "ETAPA 2 REPROVADA: sinais de diagnostico incorretos."
         severity failure;
      assert n_olderr = 0
         report "ETAPA 2 REPROVADA: o nucleo original nao bate com o modelo do livro."
         severity failure;
      assert n_diff_x = 0
         report "ETAPA 2 REPROVADA: os dois nucleos diferem de forma imprevista."
         severity failure;
      assert n_diff_d > 0
         report "As correcoes D1/D2/D3 nao foram exercitadas pelo estimulo."
         severity failure;

      -- A cobertura de operandos e uma afirmacao do relatorio: se o estimulo
      -- deixar de alcancar todos os operandos legais, o numero publicado deixa
      -- de valer e o testbench avisa.
      assert n_cov = N_LEGAL_OPS
         report "COBERTURA INCOMPLETA: o estimulo aplicou apenas "
                & integer'image(n_cov) & " dos " & integer'image(N_LEGAL_OPS)
                & " operandos legais."
         severity failure;

      report "ETAPA 2 APROVADA: " & integer'image(n_total)
             & " vetores conferem com o modelo; as unicas saidas que mudaram "
             & "em relacao ao codigo do livro sao as " & integer'image(n_diff_d)
             & " correcoes D1/D2/D3, todas com o valor previsto; o estimulo "
             & "cobriu os " & integer'image(n_cov) & " operandos legais.";
      wait;
   end process;

   ----------------------------------------------------------------------------
   -- Entropia do gerador pseudoaleatorio.
   --
   -- Medicao separada, puramente aritmetica (nao aplica vetor no DUT). Um
   -- numero grande de "vetores aleatorios" nao significa nada se eles se
   -- repetem: um gerador cujos campos sejam funcao uns dos outros alcanca
   -- poucas centenas de operandos distintos por mais que se sorteie. Este
   -- processo mede quantos dos 4098 operandos legais o gerador de fato
   -- produz, para que o numero publicado no relatorio seja verificavel.
   ----------------------------------------------------------------------------
   entropia : process
      variable s     : rnd_t := RND_SEED;
      variable o     : fp_op_t;
      variable rcov  : cover_t := (others => false);
      variable n     : natural := 0;
      variable n_bad : natural := 0;
   begin
      for i in 1 to 2 * N_RANDOM loop
         rand_op(s, o);
         rcov(op_code(o)) := true;
         if not is_valid(o) then
            n_bad := n_bad + 1;
         end if;
      end loop;

      for c in 0 to 8191 loop
         if rcov(c) then
            n := n + 1;
         end if;
      end loop;

      report "Gerador pseudoaleatorio: " & integer'image(2 * N_RANDOM)
             & " sorteios alcancaram " & integer'image(n)
             & " operandos distintos dos " & integer'image(N_LEGAL_OPS)
             & " legais.";

      assert n_bad = 0
         report "O gerador produziu um operando que viola o formato."
         severity failure;

      -- Piso de diversidade: se o gerador degenerar, o teste para em vez de
      -- seguir reportando "100.000 vetores" que na verdade sao poucas dezenas.
      assert n >= 4000
         report "Gerador pseudoaleatorio degenerado: so "
                & integer'image(n) & " operandos distintos."
         severity failure;
      wait;
   end process;

end architecture;
