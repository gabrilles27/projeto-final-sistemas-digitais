--------------------------------------------------------------------------------
-- tb_fp_precision.vhd
--
-- Caracterizacao numerica do algoritmo. Nao instancia DUT e nao verifica RTL.
--
-- Os testbenches de regressao comparam o RTL com o modelo do algoritmo, o que
-- estabelece a fidelidade da implementacao mas nao mede exatidao: modelo e RTL
-- reproduzem o mesmo truncamento e erram juntos. Aqui o algoritmo e confrontado
-- com fp_add_exact, que soma a + b pela definicao matematica do formato e so
-- entao codifica o resultado.
--
-- Percorre os 4098 x 4098 = 16.793.604 pares de operandos legais e classifica
-- cada um em tres grupos:
--
--   (a) a soma exata cabe no formato e o algoritmo acerta;
--   (b) a soma exata cabe no formato e o algoritmo erra;
--   (c) a soma exata nao cabe no formato - fora de faixa, abaixo do menor
--       normalizado, ou exigindo mais de 8 bits de significando. Nesses pares
--       algum erro e inevitavel e nao se cobra acerto.
--
-- O grupo (b) decorre do alinhamento sem bit de guarda: o 2o estagio descarta
-- os bits deslocados para fora do significando antes da subtracao, de modo que
-- uma diferenca exatamente representavel pode sair errada - nao por uma fracao
-- de ULP, mas por um fator de 2.
--
-- O elo com o hardware vem dos demais passos, que comparam o RTL com o mesmo
-- modelo de algoritmo vetor a vetor.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.fp_pkg.all;

entity tb_fp_precision is
   generic (
      -- Expoentes varridos. Com 0..15 (o padrao) a varredura e exaustiva sobre
      -- todo o espaco de operandos legais.
      E_LO : natural := 0;
      E_HI : natural := 15
   );
end entity;

architecture tb of tb_fp_precision is

   -- Valor de um operando como inteiro escalado por 256 (exato, sem real).
   function ival(x : fp_op_t) return integer is
      variable v : integer;
   begin
      v := to_integer(unsigned(x.f)) * (2 ** to_integer(unsigned(x.e)));
      if x.s = '1' then
         return -v;
      end if;
      return v;
   end function;

begin

   stim : process
      variable o1, o2 : fp_op_t;
      variable alg    : fp_alg_t;
      variable ex     : fp_exact_t;

      variable n_total : natural := 0;
      variable n_a     : natural := 0;   -- exata e o algoritmo acerta
      variable n_b     : natural := 0;   -- exata e o algoritmo erra
      variable n_c     : natural := 0;   -- nao exatamente representavel
      variable n_big   : natural := 0;   -- (c) acima da faixa
      variable n_small : natural := 0;   -- (c) abaixo do menor normalizado
      variable n_fit   : natural := 0;   -- (c) exigiria mais de 8 bits

      -- Perfil do erro dentro do grupo (b). O erro e medido em ULP do
      -- resultado EXATO: um ULP vale 2^e_exato na escala inteira (x256).
      variable n_1ulp  : natural := 0;   -- erro de exatamente 1 ULP
      variable n_mulp  : natural := 0;   -- erro de mais de 1 ULP (cancelamento)
      variable n_rat2  : natural := 0;   -- resultado = 2x o valor exato
      variable n_zero  : natural := 0;   -- algoritmo devolve zero, exato nao e

      variable vg, vx  : integer;
      variable dif     : integer;
      variable ulp     : integer;
      variable shown   : natural := 0;

      -- Pior razao |obtido / exato| encontrada, e o par que a produziu.
      variable worst   : real := 1.0;
      variable wa, wb  : fp_op_t;
      variable rat     : real;

      -- Guarda o primeiro exemplo de cada tipo de erro, para o relatorio.
      variable ex_a1, ex_b1 : fp_op_t;
      variable have_ex      : boolean := false;

      -- Percorre todos os operandos legais: 4096 normalizados + 2 zeros.
      -- idx 0..4095 -> s,e,f normalizado ; 4096 -> +0 ; 4097 -> -0
      function nth_op(i : natural) return fp_op_t is
         variable r : fp_op_t;
      begin
         if i >= 4096 then
            r   := FP_ZERO;
            if i = 4097 then
               r.s := '1';                       -- o "menos zero"
            end if;
            return r;
         end if;
         r.s := '0';
         if i >= 2048 then
            r.s := '1';
         end if;
         r.e := std_logic_vector(to_unsigned((i / 128) mod 16, 4));
         r.f := std_logic_vector(to_unsigned(128 + (i mod 128), 8));
         return r;
      end function;

   begin
      report "==================================================================";
      report " CARACTERIZACAO NUMERICA - algoritmo do livro x soma exata";
      report "==================================================================";

      for i1 in 0 to 4097 loop
         o1 := nth_op(i1);
         -- Fora da faixa de expoentes pedida? (so os normalizados tem expoente)
         next when i1 < 4096
                   and (to_integer(unsigned(o1.e)) < E_LO
                        or to_integer(unsigned(o1.e)) > E_HI);
         for i2 in 0 to 4097 loop
            o2 := nth_op(i2);
            next when i2 < 4096
                      and (to_integer(unsigned(o2.e)) < E_LO
                           or to_integer(unsigned(o2.e)) > E_HI);

            n_total := n_total + 1;
            ex      := fp_add_exact(o1, o2);

            if not ex.exact then
               n_c := n_c + 1;
               if    ex.too_big   then n_big   := n_big + 1;
               elsif ex.too_small then n_small := n_small + 1;
               else                    n_fit   := n_fit + 1;
               end if;
            else
               alg := fp_add_alg(o1, o2);
               if alg.r = ex.r then
                  n_a := n_a + 1;
               else
                  n_b := n_b + 1;
                  vg  := ival(alg.r);
                  vx  := ival(ex.r);
                  dif := abs(vg - vx);
                  ulp := 2 ** to_integer(unsigned(ex.r.e));

                  if dif = ulp then
                     n_1ulp := n_1ulp + 1;      -- perdeu so o bit truncado
                  else
                     n_mulp := n_mulp + 1;      -- cancelamento: o erro cresce
                  end if;

                  if vg = 0 then
                     n_zero := n_zero + 1;
                  elsif vx /= 0 then
                     if vg = 2 * vx then
                        n_rat2 := n_rat2 + 1;
                     end if;
                     rat := abs(real(vg) / real(vx));
                     if rat > worst then
                        worst := rat;
                        wa    := o1;
                        wb    := o2;
                     end if;
                  end if;

                  if not have_ex then
                     have_ex := true;
                     ex_a1   := o1;
                     ex_b1   := o2;
                  end if;
               end if;
            end if;
         end loop;
      end loop;

      -------------------------------------------------------------------------
      report "==================================================================";
      report " RESUMO - caracterizacao numerica";
      report "   pares avaliados ............................ " & integer'image(n_total);
      report "   (a) soma exata representavel, algoritmo OK . " & integer'image(n_a);
      report "   (b) soma exata representavel, ALGORITMO ERRA " & integer'image(n_b);
      report "   (c) soma nao representavel no formato ...... " & integer'image(n_c);
      report "         acima da faixa ....................... " & integer'image(n_big);
      report "         abaixo do menor normalizado .......... " & integer'image(n_small);
      report "         exigiria mais de 8 bits .............. " & integer'image(n_fit);
      report "   somas exatamente representaveis (a + b) .... "
             & integer'image(n_a + n_b);
      report "   perfil do erro no grupo (b):";
      report "         erro de exatamente 1 ULP ............. " & integer'image(n_1ulp);
      report "         erro maior que 1 ULP (cancelamento) .. " & integer'image(n_mulp);
      report "         destes, resultado = 2x o exato ....... " & integer'image(n_rat2);
      report "         algoritmo devolve zero, exato nao e .. " & integer'image(n_zero);
      report "         pior razao |obtido/exato| ............ " & real'image(worst);
      report "==================================================================";

      report " Pior caso encontrado:" & LF
             & "   A      = " & fp_str(wa) & LF
             & "   B      = " & fp_str(wb) & LF
             & "   exato  = " & fp_str(fp_add_exact(wa, wb).r) & LF
             & "   obtido = " & fp_str(fp_add_alg(wa, wb).r);

      if have_ex then
         report " Primeiro caso do grupo (b):" & LF
                & "   A      = " & fp_str(ex_a1) & LF
                & "   B      = " & fp_str(ex_b1) & LF
                & "   exato  = " & fp_str(fp_add_exact(ex_a1, ex_b1).r) & LF
                & "   obtido = " & fp_str(fp_add_alg(ex_a1, ex_b1).r);
      end if;

      -- O exemplo citado no relatorio: 256 - 255 = 1, mas o circuito da 2.
      report " Exemplo do relatorio (256 + (-255)):" & LF
             & "   exato  = " & fp_str(fp_add_exact(op('0', 9, 128),
                                                    op('1', 8, 255)).r) & LF
             & "   obtido = " & fp_str(fp_add_alg(op('0', 9, 128),
                                                  op('1', 8, 255)).r);

      -------------------------------------------------------------------------
      -- Propriedades que este passo estabelece:
      -------------------------------------------------------------------------
      assert n_b > 0
         report "A perda por truncamento deveria ter sido observada."
         severity failure;

      -- Teto do erro: um fator de 2. O alinhamento descarta no maximo o peso de
      -- um bit alem do que o formato ja descartaria, entao o resultado pode
      -- dobrar, mas nao mais que isso.
      assert worst <= 2.0
         report "Erro maior que um fator de 2 - o teto assumido no relatorio "
                & "esta errado."
         severity failure;

      -- O algoritmo nao zera um resultado nao nulo: o cancelamento catastrofico
      -- erra a magnitude, mas nao apaga o numero.
      assert n_zero = 0
         report "O algoritmo devolveu zero para uma soma exata nao nula."
         severity failure;

      report "CARACTERIZACAO CONCLUIDA.";
      wait;
   end process;

end architecture;
