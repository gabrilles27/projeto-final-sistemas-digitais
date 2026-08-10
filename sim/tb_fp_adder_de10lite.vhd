--------------------------------------------------------------------------------
-- tb_fp_adder_de10lite.vhd
--
-- ETAPA 2/3 - Testbench do nivel de topo, do jeito que a placa e usada.
--
-- Este testbench nao olha para dentro do projeto: ele so mexe em SW, KEY e
-- MAX10_CLK1_50 e le HEX0..HEX5 e LEDR, exatamente como uma pessoa em frente a
-- placa. Para cada caso ele:
--
--   1. da um reset com KEY(1);
--   2. carrega os quatro campos (frac A, sinal+exp A, frac B, sinal+exp B)
--      apertando KEY(0), com repique mecanico SIMULADO em cima do botao;
--   3. decodifica os displays de volta para digitos e compara com o resultado
--      do modelo do algoritmo;
--   4. confere os LEDs de diagnostico, o eco em HEX1/HEX0 e os pontos decimais.
--
-- A decodificacao dos 7 segmentos e feita por seg_expected(), que descreve
-- cada digito pelo conjunto de segmentos acesos ("abcdef" para o zero, por
-- exemplo) e monta o vetor por codigo. SSEG_MINUS e SSEG_BLANK vem da MESMA
-- formulacao ("g" e nada aceso). Nao podem ser copia das constantes de
-- fp_adder_de10lite.vhd: uma copia faria a checagem de HEX5 comparar a tabela
-- do RTL com ela mesma, e nenhum erro de polaridade ou de ordem de bits seria
-- detectado.
--
-- Repique como estimulo. Durante o repique as chaves SW(7..0) mostram um valor
-- diferente do pretendido. Um pulso de carga espurio latcharia esse outro byte,
-- e o eco o denunciaria. Manter SW constante durante o repique tornaria o teste
-- incapaz de falhar: os pulsos extras apenas reescreveriam o mesmo valor.
--
-- Operando nao normalizado. Os ultimos casos carregam significandos com o bit 7
-- em '0', padroes que o formato nao define. O nivel de topo deve trata-los como
-- zero e acender o ponto decimal do eco. Sem esse saneamento (ver
-- rtl/fp_adder_de10lite.vhd) a ordenacao do 1o estagio erra e o resultado sai
-- com sinal e magnitude errados; por isso estes casos sao verificados aqui.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library std;
use std.textio.all;

library work;
use work.fp_pkg.all;

entity tb_fp_adder_de10lite is
   generic (
      -- Alem de verificar, o testbench grava o estado exato dos seis displays
      -- e dos dez LEDs em cada caso. E desse arquivo que sai a figura
      -- "painel esperado" do relatorio, usada para conferir a placa real.
      CSV_FILE : string := "sim/waves/board_panel.csv"
   );
end entity;

architecture tb of tb_fp_adder_de10lite is

   constant CLK_PERIOD  : time    := 20 ns;   -- 50 MHz, como o MAX10_CLK1_50
   constant DEB_BITS_TB : natural := 3;       -- janela curta so para a simulacao

   signal clk  : std_logic := '0';
   signal sw   : std_logic_vector(9 downto 0) := (others => '0');
   signal key  : std_logic_vector(1 downto 0) := (others => '1');  -- solto = '1'
   signal ledr : std_logic_vector(9 downto 0);
   signal hex0, hex1, hex2, hex3, hex4, hex5 : std_logic_vector(7 downto 0);

   signal sim_done : boolean := false;

   -- Converte um padrao de 7 segmentos de volta para o digito que ele mostra.
   -- Devolve -1 se o padrao nao corresponde a nenhum digito hexadecimal.
   function sseg_to_digit(seg : std_logic_vector(6 downto 0)) return integer is
   begin
      for d in 0 to 15 loop
         if seg = seg_expected(d) then
            return d;
         end if;
      end loop;
      return -1;
   end function;

begin

   ----------------------------------------------------------------------------
   clk <= not clk after CLK_PERIOD / 2 when not sim_done else '0';

   ----------------------------------------------------------------------------
   dut : entity work.fp_adder_de10lite
      generic map (DEB_BITS => DEB_BITS_TB)
      port map (
         MAX10_CLK1_50 => clk,
         SW            => sw,
         KEY           => key,
         LEDR          => ledr,
         HEX0 => hex0, HEX1 => hex1, HEX2 => hex2,
         HEX3 => hex3, HEX4 => hex4, HEX5 => hex5
      );

   ----------------------------------------------------------------------------
   stim : process
      variable n_case : natural := 0;
      variable n_err  : natural := 0;

      file     csv : text;
      variable l   : line;
      variable fst : file_open_status;

      -- Espelho do banco de registradores mantido pelo testbench. Depois de
      -- cada carga os quatro campos sao lidos pelo eco e comparados com este
      -- espelho, e nao apenas o campo recem-escrito. E o que permite detectar
      -- uma escrita espuria: ela cai num campo que a carga legitima nao
      -- reescreve.
      type mirror_t is array (0 to 3) of std_logic_vector(7 downto 0);

      -- Os mesmos valores de reset/energizacao declarados no RTL:
      --   A = +0.11000000 x 2^4 (=12), B = +0.10000000 x 2^2 (=2)
      constant MIR_RST : mirror_t := ("11000000",   -- 00: significando de A
                                      "00000100",   -- 01: sinal e expoente de A
                                      "10000000",   -- 10: significando de B
                                      "00000010");  -- 11: sinal e expoente de B
      variable mir : mirror_t := MIR_RST;

      -- Um vetor de 8 bits como texto binario, para o arquivo do painel.
      function b8(v : std_logic_vector(7 downto 0)) return string is
         variable r : string(1 to 8);
      begin
         for i in 0 to 7 loop
            if v(7 - i) = '1' then
               r(i + 1) := '1';
            else
               r(i + 1) := '0';
            end if;
         end loop;
         return r;
      end function;

      function b10(v : std_logic_vector(9 downto 0)) return string is
         variable r : string(1 to 10);
      begin
         for i in 0 to 9 loop
            if v(9 - i) = '1' then
               r(i + 1) := '1';
            else
               r(i + 1) := '0';
            end if;
         end loop;
         return r;
      end function;

      -- Aperta KEY(0) uma vez, com repique mecanico simulado na descida e na
      -- subida. Durante todo o repique as chaves mostram "outro", um byte
      -- diferente do pretendido, de modo que qualquer pulso de carga que escape
      -- do anti-repique escreva o valor errado e seja detectado pelo eco. O
      -- valor pretendido so aparece depois que o botao esta firme.
      --
      -- Cada semiperiodo dura BOUNCE_HALF ciclos, valor escolhido entre dois
      -- limites:
      --
      --   * abaixo da janela do anti-repique (2**(DEB_BITS_TB-1)+1 = 5 ciclos
      --     consecutivos de discordancia), para que um anti-repique correto
      --     rejeite o repique inteiro - o contador zera a cada alternancia e
      --     nunca chega ao fim da janela;
      --
      --   * acima do atraso do sincronizador de 2 flip-flops, para que um
      --     anti-repique defeituoso alcance a saida ainda dentro do repique,
      --     enquanto as chaves mostram "outro".
      --
      -- Um semiperiodo curto demais anula o teste: o pulso espurio de um
      -- anti-repique quebrado sairia so depois do fim do repique, quando as
      -- chaves ja mostram o valor certo, e nada seria detectado.
      --
      -- O campo apontado durante o repique tambem tem de ser outro (a "isca").
      -- Se a isca fosse o mesmo campo que esta sendo carregado, a carga
      -- legitima no fim do repique reescreveria o valor certo por cima e
      -- apagaria a evidencia da escrita espuria.
      procedure press_load(sel : std_logic_vector(1 downto 0);
                           dat : std_logic_vector(7 downto 0)) is
         constant outro       : std_logic_vector(7 downto 0) := not dat;
         constant isca        : std_logic_vector(1 downto 0) := not sel;
         constant BOUNCE_HALF : time := 2 * CLK_PERIOD;
      begin
         sw(9 downto 8) <= isca;
         sw(7 downto 0) <= outro;
         for i in 1 to 6 loop                -- repique ao pressionar
            key(0) <= '0';
            wait for BOUNCE_HALF;
            key(0) <= '1';
            wait for BOUNCE_HALF;
         end loop;
         key(0)         <= '0';              -- pressionado de verdade
         sw(9 downto 8) <= sel;              -- agora sim o campo pretendido
         sw(7 downto 0) <= dat;              -- e o valor pretendido
         wait for 40 * CLK_PERIOD;

         sw(9 downto 8) <= isca;
         sw(7 downto 0) <= outro;
         for i in 1 to 6 loop                -- repique ao soltar
            key(0) <= '1';
            wait for BOUNCE_HALF;
            key(0) <= '0';
            wait for BOUNCE_HALF;
         end loop;
         key(0)         <= '1';              -- solto de verdade
         sw(9 downto 8) <= sel;
         sw(7 downto 0) <= dat;
         wait for 40 * CLK_PERIOD;
      end procedure;

      -- Le os quatro campos pelo eco e compara com o espelho. Deixa SW(9..8)
      -- em "11" ao terminar, que e o estado esperado pelo resto do caso.
      procedure check_all_fields(ctx : string) is
         variable hi, lo : integer;
      begin
         for k in 0 to 3 loop
            sw(9 downto 8) <= std_logic_vector(to_unsigned(k, 2));
            wait for 3 * CLK_PERIOD;
            hi := sseg_to_digit(hex1(6 downto 0));
            lo := sseg_to_digit(hex0(6 downto 0));
            if hi /= to_integer(unsigned(mir(k)(7 downto 4)))
               or lo /= to_integer(unsigned(mir(k)(3 downto 0))) then
               n_err := n_err + 1;
               report "  " & ctx & ": campo " & integer'image(k)
                      & " mostra " & integer'image(hi) & "/" & integer'image(lo)
                      & " e deveria mostrar "
                      & integer'image(to_integer(unsigned(mir(k)(7 downto 4)))) & "/"
                      & integer'image(to_integer(unsigned(mir(k)(3 downto 0))))
                      severity error;
            end if;
         end loop;
      end procedure;

      -- Carrega um campo: seleciona em SW(9..8), aperta o botao (o campo e o
      -- dado sao postos pelo press_load) e confere pelo eco que todos os quatro
      -- campos ficaram com o valor esperado: o carregado com o novo byte, os
      -- demais intactos.
      procedure load_field(sel : std_logic_vector(1 downto 0);
                           dat : std_logic_vector(7 downto 0)) is
      begin
         sw(9 downto 8) <= sel;
         sw(7 downto 0) <= dat;
         wait for 5 * CLK_PERIOD;
         press_load(sel, dat);

         mir(to_integer(unsigned(sel))) := dat;
         check_all_fields("apos carregar o campo "
                          & integer'image(to_integer(unsigned(sel))));

         -- Mexe nas chaves SEM apertar o botao: nenhum registrador pode mudar.
         sw(9 downto 8) <= sel;
         sw(7 downto 0) <= not dat;
         wait for 20 * CLK_PERIOD;
         check_all_fields("apos mexer nas chaves sem apertar o botao");

         sw(9 downto 8) <= sel;
         sw(7 downto 0) <= dat;
         wait for 5 * CLK_PERIOD;
      end procedure;

      -- KEY(1) passa pelo anti-repique, entao precisa ser mantido pressionado
      -- por toda a janela (2**(DEB_BITS_TB-1) ciclos mais os dois do
      -- sincronizador). Os 30 ciclos adotados sao bem mais que o minimo.
      procedure do_reset is
      begin
         key(1) <= '0';
         wait for 30 * CLK_PERIOD;
         key(1) <= '1';
         wait for 30 * CLK_PERIOD;
         mir := MIR_RST;
      end procedure;

      -- Roda um caso completo, do reset a leitura dos displays.
      --
      -- x e y sao os operandos como carregados pelas chaves. O resultado
      -- esperado e calculado sobre os operandos saneados, que e o que o nivel
      -- de topo entrega ao nucleo quando o valor carregado nao e um numero
      -- valido no formato.
      procedure run_case(nome : string; x, y : fp_op_t) is
         variable alg     : fp_alg_t;
         variable d_frac_h, d_frac_l, d_exp : integer;
         variable exp_frac_h, exp_frac_l, exp_exp : integer;
         variable ok      : boolean := true;
         variable echo_hi, echo_lo, exp_echo_hi : integer;
      begin
         n_case := n_case + 1;
         alg    := fp_add_alg(sanitize(x), sanitize(y));

         -- O modelo so vale se o que chega ao nucleo respeita o formato. Se o
         -- saneamento falhar, isto para a simulacao em vez de comparar contra
         -- um resultado sem sentido.
         assert not alg.bad_input
            report "  o operando saneado ainda viola o formato" severity failure;

         do_reset;
         load_field("00", x.f);                       -- significando de A
         load_field("01", "000" & x.s & x.e);         -- sinal e expoente de A
         load_field("10", y.f);                       -- significando de B
         load_field("11", "000" & y.s & y.e);         -- sinal e expoente de B

         wait for 5 * CLK_PERIOD;

         -- Leitura dos displays do resultado
         d_frac_h := sseg_to_digit(hex4(6 downto 0));
         d_frac_l := sseg_to_digit(hex3(6 downto 0));
         d_exp    := sseg_to_digit(hex2(6 downto 0));

         exp_frac_h := to_integer(unsigned(alg.r.f(7 downto 4)));
         exp_frac_l := to_integer(unsigned(alg.r.f(3 downto 0)));
         exp_exp    := to_integer(unsigned(alg.r.e));

         if d_frac_h /= exp_frac_h or d_frac_l /= exp_frac_l or d_exp /= exp_exp then
            ok := false;
            report "  displays errados: HEX4/3/2 mostram "
                   & integer'image(d_frac_h) & "/" & integer'image(d_frac_l)
                   & "/" & integer'image(d_exp) & " e deveriam mostrar "
                   & integer'image(exp_frac_h) & "/" & integer'image(exp_frac_l)
                   & "/" & integer'image(exp_exp)
                   severity error;
         end if;

         -- Sinal em HEX5
         if alg.r.s = '1' then
            if hex5(6 downto 0) /= SSEG_MINUS then
               ok := false;
               report "  HEX5 deveria mostrar o traco de menos" severity error;
            end if;
         else
            if hex5(6 downto 0) /= SSEG_BLANK then
               ok := false;
               report "  HEX5 deveria estar apagado" severity error;
            end if;
         end if;

         -- Ponto decimal do resultado: aceso apenas em HEX3.
         if hex3(7) /= '0' then
            ok := false;
            report "  o ponto decimal de HEX3 deveria estar aceso" severity error;
         end if;
         if hex4(7) = '0' or hex2(7) = '0' then
            ok := false;
            report "  so HEX3 deveria ter o ponto aceso no resultado" severity error;
         end if;

         -- Pontos decimais do eco: avisam operando invalido.
         if (hex1(7) = '0') /= (not is_valid(x)) then
            ok := false;
            report "  ponto de HEX1 (operando A invalido) errado" severity error;
         end if;
         if (hex0(7) = '0') /= (not is_valid(y)) then
            ok := false;
            report "  ponto de HEX0 (operando B invalido) errado" severity error;
         end if;

         -- Eco: SW(9..8) ficou em "11", entao HEX1/HEX0 mostram o byte
         -- "000" & sinal & expoente do operando B.
         echo_hi := sseg_to_digit(hex1(6 downto 0));
         echo_lo := sseg_to_digit(hex0(6 downto 0));
         if y.s = '1' then
            exp_echo_hi := 1;
         else
            exp_echo_hi := 0;
         end if;
         if echo_hi /= exp_echo_hi then
            ok := false;
            report "  eco HEX1 (sinal de B) = " & integer'image(echo_hi)
                   & ", esperado " & integer'image(exp_echo_hi) severity error;
         end if;
         if echo_lo /= to_integer(unsigned(y.e)) then
            ok := false;
            report "  eco HEX0 (expoente de B) = " & integer'image(echo_lo)
                   & ", esperado " & integer'image(to_integer(unsigned(y.e)))
                   severity error;
         end if;

         -- LEDs de diagnostico
         if to_integer(unsigned(ledr(3 downto 0))) /= alg.exp_diff then
            ok := false;
            report "  LEDR(3..0) (exp_diff) = "
                   & integer'image(to_integer(unsigned(ledr(3 downto 0))))
                   & ", esperado " & integer'image(alg.exp_diff) severity error;
         end if;
         if to_integer(unsigned(ledr(6 downto 4))) /= alg.leado then
            ok := false;
            report "  LEDR(6..4) (leado) = "
                   & integer'image(to_integer(unsigned(ledr(6 downto 4))))
                   & ", esperado " & integer'image(alg.leado) severity error;
         end if;
         if (ledr(7) = '1') /= alg.carry then
            ok := false;
            report "  LEDR(7) (carry) errado" severity error;
         end if;
         if (ledr(8) = '1') /= ((alg.r.e = "0000") and (alg.r.f = "00000000")) then
            ok := false;
            report "  LEDR(8) (resultado nulo) errado" severity error;
         end if;
         if (ledr(9) = '1') /= alg.overflow then
            ok := false;
            report "  LEDR(9) (saturacao) errado" severity error;
         end if;

         -- Registra o painel completo (o que a placa deve mostrar neste caso).
         write(l, integer'image(n_case - 1) & ";" & nome
                  & ";" & fp_str(x) & ";" & fp_str(y) & ";" & fp_str(alg.r)
                  & ";" & b8(hex5) & ";" & b8(hex4) & ";" & b8(hex3)
                  & ";" & b8(hex2) & ";" & b8(hex1) & ";" & b8(hex0)
                  & ";" & b10(ledr));
         writeline(csv, l);

         if ok then
            report "  OK  " & nome & " -> " & fp_str(alg.r);
         else
            n_err := n_err + 1;
            report "  FALHOU  " & nome severity error;
         end if;
      end procedure;

   begin
      report "==================================================================";
      report " ETAPA 2/3 - testbench do nivel de topo (interface da DE10-Lite)";
      report "==================================================================";

      file_open(fst, csv, CSV_FILE, write_mode);
      assert fst = open_ok
         report "Nao foi possivel abrir " & CSV_FILE
                & ". Rode o simulador a partir da raiz do projeto."
         severity failure;
      write(l, string'("case;nome;opA;opB;resultado;"
                       & "HEX5;HEX4;HEX3;HEX2;HEX1;HEX0;LEDR"));
      writeline(csv, l);

      -------------------------------------------------------------------------
      -- Energizacao: antes de qualquer reset, os registradores ja devem conter
      -- o par padrao, vindo dos valores iniciais declarados no RTL.
      -------------------------------------------------------------------------
      wait for 5 * CLK_PERIOD;
      if sseg_to_digit(hex4(6 downto 0)) /= 14
         or sseg_to_digit(hex3(6 downto 0)) /= 0
         or sseg_to_digit(hex2(6 downto 0)) /= 4 then
         n_err := n_err + 1;
         report "Na energizacao o resultado deveria ser 0.E0 x 2^4 (=14), mas "
                & "os displays mostram "
                & integer'image(sseg_to_digit(hex4(6 downto 0))) & "/"
                & integer'image(sseg_to_digit(hex3(6 downto 0))) & "/"
                & integer'image(sseg_to_digit(hex2(6 downto 0)))
                severity error;
      else
         report "  OK  energizacao: +12 + (+2) = +14  ->  0.E0 x 2^4";
      end if;

      -------------------------------------------------------------------------
      -- Confere o par de operandos carregado no reset.
      --
      -- A verificacao e feita por "if" que incrementa n_err, e nao por um
      -- "assert" solto: o GHDL nao interrompe a simulacao em severity error,
      -- entao uma assercao isolada falharia sem impedir que o "OK" seguinte
      -- fosse impresso e o teste terminasse aprovado.
      -------------------------------------------------------------------------
      do_reset;
      wait for 5 * CLK_PERIOD;
      if sseg_to_digit(hex4(6 downto 0)) /= 14
         or sseg_to_digit(hex3(6 downto 0)) /= 0
         or sseg_to_digit(hex2(6 downto 0)) /= 4 then
         n_err := n_err + 1;
         report "Apos o reset o resultado deveria ser 0.11100000 x 2^4 "
                & "(E0 / exp 4), mas os displays mostram "
                & integer'image(sseg_to_digit(hex4(6 downto 0))) & "/"
                & integer'image(sseg_to_digit(hex3(6 downto 0))) & "/"
                & integer'image(sseg_to_digit(hex2(6 downto 0)))
                severity error;
      else
         report "  OK  valores padrao do reset: +12 + (+2) = +14  ->  0.E0 x 2^4";
      end if;

      -------------------------------------------------------------------------
      -- Reset com KEY(0) PRESSIONADO nao pode gerar carga espuria.
      --
      -- O reset zera o estado do anti-repique de KEY(0). Sem a trava de carga
      -- do RTL, ao sair do reset a transicao solto->pressionado seria vista
      -- como uma borda e sobrescreveria um campo do par padrao com o que
      -- estivesse nas chaves (aqui, a_frac viraria 0xC3 em vez de 0xC0).
      -------------------------------------------------------------------------
      sw(9 downto 8) <= "00";
      sw(7 downto 0) <= "11000011";        -- lixo pronto para ser latchado
      key(0)         <= '0';               -- botao de carga PRESSIONADO
      wait for 5 * CLK_PERIOD;
      do_reset;
      wait for 60 * CLK_PERIOD;
      key(0) <= '1';
      wait for 60 * CLK_PERIOD;
      if sseg_to_digit(hex4(6 downto 0)) /= 14
         or sseg_to_digit(hex3(6 downto 0)) /= 0
         or sseg_to_digit(hex2(6 downto 0)) /= 4 then
         n_err := n_err + 1;
         report "Reset com KEY(0) pressionado gerou carga espuria: os displays "
                & "mostram " & integer'image(sseg_to_digit(hex4(6 downto 0)))
                & "/" & integer'image(sseg_to_digit(hex3(6 downto 0)))
                & "/" & integer'image(sseg_to_digit(hex2(6 downto 0)))
                & " em vez de 14/0/4"
                severity error;
      else
         report "  OK  reset com KEY(0) pressionado nao alterou os operandos";
      end if;

      -------------------------------------------------------------------------
      -- Um glitch curto em KEY(1) nao pode apagar os operandos.
      --
      -- Ligado como reset assincrono cru, um pulso de 1 ns em KEY(1) (o clock
      -- tem 20 ns) zeraria os dois operandos; filtrado pelo anti-repique, ele
      -- nao tem efeito. Para o teste valer, primeiro carregamos um valor
      -- diferente do padrao - se o glitch resetasse, o valor voltaria ao padrao.
      -------------------------------------------------------------------------
      load_field("00", "10010000");        -- a_frac = 0x90, diferente do padrao
      key(1) <= '0';
      wait for 1 ns;
      key(1) <= '1';
      wait for 20 * CLK_PERIOD;
      sw(9 downto 8) <= "00";
      wait for 5 * CLK_PERIOD;
      if sseg_to_digit(hex1(6 downto 0)) /= 9
         or sseg_to_digit(hex0(6 downto 0)) /= 0 then
         n_err := n_err + 1;
         report "Um glitch de 1 ns em KEY(1) alterou os operandos: o eco de "
                & "a_frac mostra "
                & integer'image(sseg_to_digit(hex1(6 downto 0))) & "/"
                & integer'image(sseg_to_digit(hex0(6 downto 0)))
                & " em vez de 9/0"
                severity error;
      else
         report "  OK  glitch de 1 ns em KEY(1) foi filtrado";
      end if;

      -------------------------------------------------------------------------
      -- Casos dirigidos, os mesmos das etapas anteriores.
      -------------------------------------------------------------------------
      for i in 0 to N_DIR - 1 loop
         report dir_name(i);
         run_case(dir_name(i), DIR_A(i), DIR_B(i));
      end loop;

      -------------------------------------------------------------------------
      -- Operandos nao normalizados: o formato nao os define, o nivel de topo
      -- os trata como zero e avisa pelo ponto decimal do eco.
      --
      -- O primeiro caso e o par mais severo: sem o saneamento, +4 (com o
      -- significando nao normalizado) + (-7,1875) sairia como +28,75, com sinal
      -- e magnitude errados, em vez do -3,1875 que o operando saneado produz.
      -------------------------------------------------------------------------
      report "--- Operandos nao normalizados (devem ser tratados como zero) ---";
      run_case("N0  A nao normalizado (f=40)",
               op('0', 4, 16#40#), op('1', 3, 16#E6#));
      run_case("N1  B nao normalizado (f=7F)",
               op('0', 5, 16#C0#), op('1', 2, 16#7F#));
      run_case("N2  os dois nao normalizados",
               op('1', 6, 16#01#), op('0', 1, 16#33#));
      run_case("N3  frac zero com expoente nao nulo",
               op('0', 7, 16#00#), op('0', 3, 16#80#));

      -------------------------------------------------------------------------
      report "==================================================================";
      report " RESUMO - nivel de topo";
      report "   casos executados ... " & integer'image(n_case);
      report "   casos com falha .... " & integer'image(n_err);
      report "==================================================================";

      file_close(csv);

      assert n_err = 0
         report "Testbench de topo REPROVADO."
         severity failure;

      report "Nivel de topo APROVADO: os " & integer'image(n_case)
             & " casos foram carregados pelos botoes e lidos nos displays com "
             & "o valor correto.";

      sim_done <= true;
      wait;
   end process;

end architecture;
