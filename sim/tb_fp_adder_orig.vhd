--------------------------------------------------------------------------------
-- tb_fp_adder_orig.vhd
--
-- Etapa 1 - validacao de rtl/fp_adder.vhd (Listing 3.19) contra o modelo do
-- algoritmo do livro, fp_add_alg(...).book.
--
-- Criterio de aprovacao: em cada vetor a saida do DUT coincide bit a bit com o
-- modelo, inclusive nos vetores em que o algoritmo do livro erra. Nesses, o
-- valor errado especifico e exigido, e nao apenas tolerado.
--
-- Onde o modelo do livro difere do modelo corrigido, a diferenca e classificada
-- em tres familias, cada uma com valor previsto:
--
--   D1  Zero com sinal. O RTL original faz sign_out <= signb sem condicao,
--       entao um resultado nulo herda o sinal do maior operando.
--       Previsto: (signb = '1', e = 0, f = 0).
--
--   D2  Cancelamento exato (sum = 0) com expoente do maior operando >= 8. O
--       contador de zeros a esquerda satura em 7 e nao distingue sum = 0 de
--       sum = 1, entao o teste de underflow (leado > expb) nao dispara.
--       Previsto: (signb, e = expb - 7, f = 0).
--       Em expb = 7 o ramo normal ja produz e = 0 e f = 0, que e o zero
--       canonico; por isso o limiar e 8, e nao 7.
--
--   D3  Carry-out com o expoente ja em 15: expb + 1 da a volta para 0.
--       Previsto: (signb, e = 0, f = sum/2).
--
-- Diferenca fora dessas familias, ou dentro de uma delas com valor diferente do
-- previsto, reprova a simulacao.
--
-- Estimulo aplicado:
--   1. os 14 casos dirigidos de fp_pkg;
--   2. varredura densa: 16 expoentes x 2 sinais em cada operando, sobre 12
--      significandos representativos;
--   3. varredura de cobertura: cada um dos 4098 operandos legais, dos dois
--      lados, contra COVER_B, o que leva a cobertura de operandos a 100%;
--   4. 100.000 vetores pseudoaleatorios deterministicos.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.fp_pkg.all;

entity tb_fp_adder_orig is
   generic (
      RUN_SWEEP  : boolean := true;   -- varredura densa
      RUN_COVER  : boolean := true;   -- varredura de cobertura total
      RUN_RANDOM : boolean := true;   -- vetores pseudoaleatorios
      N_RANDOM   : natural := 100000
   );
end entity;

architecture tb of tb_fp_adder_orig is

   signal a, b     : fp_op_t := FP_ZERO;
   signal sign_out : std_logic;
   signal exp_out  : std_logic_vector(3 downto 0);
   signal frac_out : std_logic_vector(7 downto 0);

begin

   ----------------------------------------------------------------------------
   -- Unidade sob teste: o codigo do livro, sem nenhuma alteracao.
   ----------------------------------------------------------------------------
   dut : entity work.fp_adder
      port map (
         sign1    => a.s,
         sign2    => b.s,
         exp1     => a.e,
         exp2     => b.e,
         frac1    => a.f,
         frac2    => b.f,
         sign_out => sign_out,
         exp_out  => exp_out,
         frac_out => frac_out
      );

   ----------------------------------------------------------------------------
   stim : process
      variable n_total : natural := 0;
      variable n_ok    : natural := 0;   -- DUT == modelo do livro
      variable n_bad   : natural := 0;   -- DUT != modelo do livro -> FALHA
      variable n_same  : natural := 0;   -- livro e versao corrigida coincidem
      variable n_d1    : natural := 0;
      variable n_d2    : natural := 0;
      variable n_d3    : natural := 0;
      variable n_unexp : natural := 0;   -- divergencia fora de D1/D2/D3 -> FALHA
      variable shown   : natural := 0;
      variable rnd     : rnd_t := RND_SEED;
      variable ra, rb  : fp_op_t;

      -- Aplica um par de operandos, exige o valor exato e classifica.
      procedure check(x, y : fp_op_t; verbose : boolean) is
         variable alg  : fp_alg_t;
         variable got  : fp_op_t;
         variable want : fp_op_t;
      begin
         a <= x;
         b <= y;
         wait for 5 ns;

         alg     := fp_add_alg(x, y);
         got     := (sign_out, exp_out, frac_out);
         n_total := n_total + 1;

         -- A premissa do formato ("normalizado ou zero") vale para todo o
         -- estimulo aplicado ao nucleo. Se algum dia deixar de valer, o
         -- testbench para: o 1o estagio ordena pelo padrao de bits e&f, que so
         -- e ordem de magnitude sob essa premissa.
         assert not alg.bad_input
            report "ESTIMULO INVALIDO (viola 'normalizado ou zero'): A = "
                   & fp_str(x) & "  B = " & fp_str(y)
            severity failure;

         ----------------------------------------------------------------------
         -- (1) O RTL do livro tem de reproduzir o modelo do livro, bit a bit.
         ----------------------------------------------------------------------
         if got = alg.book then
            n_ok := n_ok + 1;
            if verbose then
               report "   OK       " & fp_str(got);
            end if;
         else
            n_bad := n_bad + 1;
            if shown < 20 then
               shown := shown + 1;
               report "SAIDA DIFERENTE DO MODELO DO ALGORITMO DO LIVRO" & LF
                      & "   A       = " & fp_str(x) & LF
                      & "   B       = " & fp_str(y) & LF
                      & "   obtido  = " & fp_str(got) & LF
                      & "   previsto= " & fp_str(alg.book)
                      severity error;
            end if;
         end if;

         ----------------------------------------------------------------------
         -- (2) Onde o livro difere do algoritmo corrigido, exigir o valor
         --     previsto pela familia de defeito correspondente.
         ----------------------------------------------------------------------
         if alg.book = alg.r then
            n_same := n_same + 1;

         elsif alg.exact_cancel and alg.expb >= 8 then
            -- D2: cancelamento exato que nao vira zero canonico.
            want := (alg.signb,
                     std_logic_vector(to_unsigned(alg.expb - 7, 4)),
                     "00000000");
            if alg.book = want then
               n_d2 := n_d2 + 1;
               if verbose or n_d2 <= 3 then
                  report "   [D2] cancelamento exato nao canonico: livro da "
                         & fp_str(alg.book) & " / correto " & fp_str(alg.r);
               end if;
            else
               n_unexp := n_unexp + 1;
               if shown < 20 then
                  shown := shown + 1;
                  report "D2 COM VALOR IMPREVISTO" & LF
                         & "   A = " & fp_str(x) & "  B = " & fp_str(y) & LF
                         & "   livro    = " & fp_str(alg.book) & LF
                         & "   previsto = " & fp_str(want)
                         severity error;
               end if;
            end if;

         elsif alg.overflow then
            -- D3: carry-out com expoente 15; expb+1 da a volta para 0.
            want := (alg.signb, "0000",
                     std_logic_vector(to_unsigned(alg.sum9 / 2, 8)));
            if alg.book = want then
               n_d3 := n_d3 + 1;
               if verbose or n_d3 <= 3 then
                  report "   [D3] estouro de expoente: livro da "
                         & fp_str(alg.book) & " / correto " & fp_str(alg.r);
               end if;
            else
               n_unexp := n_unexp + 1;
               if shown < 20 then
                  shown := shown + 1;
                  report "D3 COM VALOR IMPREVISTO" & LF
                         & "   A = " & fp_str(x) & "  B = " & fp_str(y) & LF
                         & "   livro    = " & fp_str(alg.book) & LF
                         & "   previsto = " & fp_str(want)
                         severity error;
               end if;
            end if;

         elsif alg.book = (alg.signb, "0000", "00000000") and alg.signb = '1'
               and alg.r = FP_ZERO then
            -- D1: o resultado e zero, mas sai com o sinal do maior operando.
            n_d1 := n_d1 + 1;
            if verbose or n_d1 <= 3 then
               report "   [D1] menos zero: livro da " & fp_str(alg.book)
                      & " / correto " & fp_str(alg.r);
            end if;

         else
            n_unexp := n_unexp + 1;
            if shown < 20 then
               shown := shown + 1;
               report "DIVERGENCIA LIVRO x CORRIGIDO FORA DE D1/D2/D3" & LF
                      & "   A        = " & fp_str(x) & LF
                      & "   B        = " & fp_str(y) & LF
                      & "   livro    = " & fp_str(alg.book) & LF
                      & "   corrigido= " & fp_str(alg.r)
                      severity error;
            end if;
         end if;
      end procedure;

   begin
      report "==================================================================";
      report " ETAPA 1 - validacao do VHDL original (Listing 3.19, sem alteracao)";
      report "==================================================================";

      -------------------------------------------------------------------------
      report "--- Casos dirigidos ---";
      for i in 0 to N_DIR - 1 loop
         report dir_name(i);
         report "   A = " & fp_str(DIR_A(i)) & "   B = " & fp_str(DIR_B(i));
         check(DIR_A(i), DIR_B(i), true);
      end loop;

      -------------------------------------------------------------------------
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

      -------------------------------------------------------------------------
      -- Cobertura: os 4098 operandos legais, dos dois lados.
      -------------------------------------------------------------------------
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
         -- os dois zeros canonicos (+0 e -0)
         for s in 0 to 1 loop
            for k in 0 to COVER_N - 1 loop
               check(op_from(s, 0, "00000000"), COVER_B(k), false);
               check(COVER_B(k), op_from(s, 0, "00000000"), false);
            end loop;
         end loop;
      end if;

      -------------------------------------------------------------------------
      if RUN_RANDOM then
         report "--- Vetores pseudoaleatorios ---";
         for i in 1 to N_RANDOM loop
            rand_op(rnd, ra);
            rand_op(rnd, rb);
            check(ra, rb, false);
         end loop;
      end if;

      -------------------------------------------------------------------------
      report "==================================================================";
      report " RESUMO ETAPA 1";
      report "   vetores aplicados .................. " & integer'image(n_total);
      report "   DUT == modelo do algoritmo do livro  " & integer'image(n_ok);
      report "   DUT != modelo (FALHA) .............. " & integer'image(n_bad);
      report "   livro == corrigido ................. " & integer'image(n_same);
      report "   [D1] menos zero .................... " & integer'image(n_d1);
      report "   [D2] cancelamento exato nao canonico " & integer'image(n_d2);
      report "   [D3] estouro de expoente ........... " & integer'image(n_d3);
      report "   divergencias imprevistas (FALHA) ... " & integer'image(n_unexp);
      report "==================================================================";

      assert n_bad = 0
         report "ETAPA 1 REPROVADA: o RTL do livro nao reproduz o modelo do "
                & "algoritmo do livro."
         severity failure;

      assert n_unexp = 0
         report "ETAPA 1 REPROVADA: ha divergencias fora das familias D1/D2/D3 "
                & "ou com valor diferente do previsto."
         severity failure;

      assert (n_d1 > 0) and (n_d2 > 0) and (n_d3 > 0)
         report "Os tres defeitos deveriam ter sido exercitados pelo estimulo."
         severity failure;

      report "ETAPA 1 APROVADA: em " & integer'image(n_total)
             & " vetores a saida do RTL do livro coincide com o modelo do "
             & "algoritmo do livro; as " & integer'image(n_d1 + n_d2 + n_d3)
             & " diferencas em relacao ao algoritmo corrigido sao exatamente "
             & "D1, D2 e D3, com os valores previstos.";
      wait;
   end process;

end architecture;
