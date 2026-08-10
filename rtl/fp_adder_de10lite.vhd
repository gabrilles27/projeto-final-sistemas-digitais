--------------------------------------------------------------------------------
-- fp_adder_de10lite.vhd
--
-- ETAPA 2/3 - Nivel de topo para a placa Terasic DE10-Lite (MAX 10,
-- 10M50DAF484C7G). Substitui o fp_adder_test do livro (Listing 3.20).
--
-- O QUE MUDOU EM RELACAO AO CIRCUITO DE TESTE ORIGINAL
-- ----------------------------------------------------
-- 1. Removemos o disp_mux. A placa do livro tinha 4 displays multiplexados no
--    tempo, com 4 sinais de anodo (an) e um unico barramento sseg. A DE10-Lite
--    tem 6 displays independentes (HEX0..HEX5), cada um com seu proprio
--    barramento. A multiplexacao deixou de existir, e com ela sumiram os
--    contadores que ela exigia.
--
-- 2. Removemos os operandos fixos. O livro amarrava um operando a uma constante
--    ("1000" no expoente, "10101" no significando) e duplicava chaves para
--    formar o outro, porque so havia 8 chaves para 26 bits. Com isso era
--    impossivel alcancar os casos criticos pedidos no enunciado. Aqui os dois
--    operandos ficam em registradores e sao carregados campo a campo, o que da
--    acesso a qualquer par de entradas.
--
-- 3. Reorganizamos as entradas. SW(9..8) escolhe o campo, SW(7..0) traz o dado,
--    KEY(0) carrega e KEY(1) da reset. Os botoes da DE10-Lite sao ativos em
--    nivel baixo, ao contrario dos do livro, e AMBOS passam por anti-repique.
--
-- 4. Roteamos os sinais internos dos estagios para os LEDs (LEDR), para que os
--    quatro estagios do algoritmo possam ser conferidos na propria placa.
--
-- 5. SANEAMENTO DO OPERANDO. O formato de 13 bits so define dois tipos de
--    operando: normalizado (bit 7 do significando em '1') ou zero canonico.
--    O nucleo depende disso - o 1o estagio ordena comparando o padrao de bits
--    exp&frac, que so e ordem de magnitude sob essa premissa. O circuito de
--    teste do livro garantia a premissa POR CONSTRUCAO, amarrando o bit:
--
--        frac1 <= '1' & sw(1) & sw(0) & "10101";
--        frac2 <= '1' & sw(6 downto 0);
--
--    Ao trocar operandos fixos por registradores carregados livremente pelas
--    chaves, essa garantia se perdeu: era possivel carregar um significando
--    com o bit 7 em '0'. Nesse caso a ordenacao erra, a subtracao de 9 bits
--    empresta e o emprestimo e lido como carry - resultado com SINAL e
--    magnitude errados. A garantia e restaurada aqui, entre os registradores e
--    o nucleo (sinais *_eff), e a condicao e avisada no painel.
--
-- MAPA DE USO
-- -----------
--   SW(9..8) : campo a ser carregado
--                00 -> significando do operando A   (dado em SW(7..0))
--                01 -> sinal e expoente de A        (sinal em SW(4), exp em SW(3..0))
--                10 -> significando do operando B   (dado em SW(7..0))
--                11 -> sinal e expoente de B        (sinal em SW(4), exp em SW(3..0))
--   SW(7..0) : dado a ser carregado
--   KEY(0)   : carrega o campo selecionado (pressionar = nivel baixo)
--   KEY(1)   : reset, recarrega o par de operandos padrao
--
--   HEX5 : sinal do resultado ('-' quando negativo, apagado quando positivo)
--   HEX4 : significando do resultado, digito mais significativo
--   HEX3 : significando do resultado, digito menos significativo (ponto aceso,
--          separando o significando do expoente)
--   HEX2 : expoente do resultado
--   HEX1 : eco do campo selecionado em SW(9..8), digito mais significativo.
--          PONTO DECIMAL ACESO = o operando A carregado nao e valido e esta
--          sendo tratado como zero.
--   HEX0 : eco do campo selecionado em SW(9..8), digito menos significativo.
--          PONTO DECIMAL ACESO = idem para o operando B.
--
--   LEDR(3..0) : exp_diff  - deslocamento aplicado no 2o estagio (alinhamento)
--   LEDR(6..4) : leado     - zeros a esquerda contados no 4o estagio
--   LEDR(7)    : carry-out do 3o estagio
--   LEDR(8)    : resultado nulo (cancelamento exato ou conversao para zero)
--   LEDR(9)    : saturacao por estouro de expoente
--
-- O sinal do resultado nao ocupa LED porque ja aparece em HEX5.
--
-- Leitura do resultado: HEX5..HEX2 mostram  s 0.FF x 2^E .
--
-- ENERGIZACAO
-- -----------
-- Todos os registradores tem valor inicial explicito. Na placa esse e o valor
-- de energizacao gravado no .sof; na simulacao e o estado em t=0. Escrever os
-- valores iniciais no RTL torna o comportamento de energizacao parte da
-- especificacao, em vez de deixa-lo a cargo da inferencia de presets pela
-- ferramenta de sintese - e permite que a simulacao comece do mesmo estado que
-- a placa, e nao em 'U'.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fp_adder_de10lite is
   generic (
      -- Largura dos contadores de anti-repique. Com 20 bits, a janela e de
      -- 2**19 = 524.288 ciclos, ou 10,486 ms a 50 MHz.
      -- O testbench instancia com um valor pequeno para encurtar a simulacao.
      DEB_BITS : natural := 20
   );
   port(
      MAX10_CLK1_50 : in  std_logic;
      SW            : in  std_logic_vector(9 downto 0);
      KEY           : in  std_logic_vector(1 downto 0);
      LEDR          : out std_logic_vector(9 downto 0);
      HEX0          : out std_logic_vector(7 downto 0);
      HEX1          : out std_logic_vector(7 downto 0);
      HEX2          : out std_logic_vector(7 downto 0);
      HEX3          : out std_logic_vector(7 downto 0);
      HEX4          : out std_logic_vector(7 downto 0);
      HEX5          : out std_logic_vector(7 downto 0)
   );
end fp_adder_de10lite;

architecture arch of fp_adder_de10lite is

   -- Padroes de segmento usados fora do decodificador hexadecimal.
   constant SSEG_BLANK : std_logic_vector(6 downto 0) := "1111111";
   constant SSEG_MINUS : std_logic_vector(6 downto 0) := "0111111";  -- so o segmento g

   -- Valores carregados no reset e na energizacao:
   --   A = +0.11000000 x 2^4 (=12), B = +0.10000000 x 2^2 (=2).
   -- Resultado esperado logo apos o reset: +0.11100000 x 2^4 (=14).
   constant A_SIGN_RST : std_logic                    := '0';
   constant A_EXP_RST  : std_logic_vector(3 downto 0) := "0100";
   constant A_FRAC_RST : std_logic_vector(7 downto 0) := "11000000";
   constant B_SIGN_RST : std_logic                    := '0';
   constant B_EXP_RST  : std_logic_vector(3 downto 0) := "0010";
   constant B_FRAC_RST : std_logic_vector(7 downto 0) := "10000000";

   signal clk : std_logic;

   signal key0_press, key1_press : std_logic;
   signal load_pulse             : std_logic;
   signal load_en                : std_logic;
   signal key0_sync              : std_logic_vector(1 downto 0) := (others => '0');
   signal armed                  : std_logic := '0';
   signal reset                  : std_logic;

   -- Registradores de operando (valor inicial = valor de reset)
   signal a_sign : std_logic := A_SIGN_RST;
   signal b_sign : std_logic := B_SIGN_RST;
   signal a_exp  : std_logic_vector(3 downto 0) := A_EXP_RST;
   signal b_exp  : std_logic_vector(3 downto 0) := B_EXP_RST;
   signal a_frac : std_logic_vector(7 downto 0) := A_FRAC_RST;
   signal b_frac : std_logic_vector(7 downto 0) := B_FRAC_RST;

   -- Operandos saneados, que e o que o nucleo recebe de fato
   signal a_ok, b_ok         : std_logic;
   signal a_bad, b_bad       : std_logic;
   signal a_sign_eff         : std_logic;
   signal b_sign_eff         : std_logic;
   signal a_exp_eff          : std_logic_vector(3 downto 0);
   signal b_exp_eff          : std_logic_vector(3 downto 0);
   signal a_frac_eff         : std_logic_vector(7 downto 0);
   signal b_frac_eff         : std_logic_vector(7 downto 0);

   -- Resultado
   signal r_sign : std_logic;
   signal r_exp  : std_logic_vector(3 downto 0);
   signal r_frac : std_logic_vector(7 downto 0);

   -- Diagnostico
   signal d_expdiff : std_logic_vector(3 downto 0);
   signal d_leado   : std_logic_vector(2 downto 0);
   signal d_carry   : std_logic;
   signal d_ovf     : std_logic;
   signal r_is_zero : std_logic;

   -- Eco do campo selecionado
   signal echo : std_logic_vector(7 downto 0);

begin

   clk <= MAX10_CLK1_50;

   ----------------------------------------------------------------------------
   -- Botoes. Na DE10-Lite pressionado = '0', por isso a inversao.
   ----------------------------------------------------------------------------
   key0_press <= not KEY(0);
   key1_press <= not KEY(1);

   ----------------------------------------------------------------------------
   -- Reset a partir de KEY(1).
   --
   -- KEY(1) e um pino mecanico e por isso passa pelo mesmo anti-repique de
   -- KEY(0). Ligado direto como reset assincrono, um glitch de 1 ns (o clock
   -- tem 20 ns) bastaria para apagar os dois operandos; filtrado, ele so age
   -- depois de a janela de anti-repique inteira confirmar o nivel.
   --
   -- Este anti-repique nao tem reset (nao ha de onde tirar um: e ele que gera
   -- o reset). Por isso os registradores de debounce.vhd tem valor inicial.
   ----------------------------------------------------------------------------
   deb_reset : entity work.debounce
      generic map (CNT_BITS => DEB_BITS)
      port map (
         clk   => clk,
         reset => '0',
         din   => key1_press,
         level => reset,
         rise  => open,
         fall  => open
      );

   ----------------------------------------------------------------------------
   -- Botao de carga.
   ----------------------------------------------------------------------------
   deb_load : entity work.debounce
      generic map (CNT_BITS => DEB_BITS)
      port map (
         clk   => clk,
         reset => reset,
         din   => key0_press,
         level => open,
         rise  => load_pulse,
         fall  => open
      );

   ----------------------------------------------------------------------------
   -- Trava de carga espuria apos o reset.
   --
   -- O reset zera o estado interno do anti-repique de KEY(0), inclusive quando
   -- o botao esta pressionado. Ao sair do reset, o anti-repique ve a transicao
   -- solto->pressionado e emite um pulso de borda espurio, sobrescrevendo um
   -- campo do par padrao. Aqui a carga so e habilitada depois de o botao ter
   -- sido visto SOLTO ao menos uma vez desde o ultimo reset.
   --
   -- A condicao olha para o BOTAO (sincronizado), nao para o nivel de saida do
   -- anti-repique: logo apos o reset esse nivel esta baixo porque o reset o
   -- zerou, e nao porque o botao foi solto - usa-lo aqui rearmaria a carga a
   -- tempo de deixar o pulso espurio passar.
   ----------------------------------------------------------------------------
   process(clk)
   begin
      if rising_edge(clk) then
         key0_sync <= key0_sync(0) & key0_press;
         if reset = '1' then
            armed <= '0';
         elsif key0_sync(1) = '0' then
            armed <= '1';
         end if;
      end if;
   end process;

   load_en <= load_pulse and armed;

   ----------------------------------------------------------------------------
   -- Banco de registradores dos dois operandos.
   --
   -- O reset e sincrono: ele vem do anti-repique, ou seja, ja esta alinhado ao
   -- clock. O estado de energizacao vem dos valores iniciais dos sinais.
   ----------------------------------------------------------------------------
   process(clk)
   begin
      if rising_edge(clk) then
         if reset = '1' then
            a_sign <= A_SIGN_RST;
            a_exp  <= A_EXP_RST;
            a_frac <= A_FRAC_RST;
            b_sign <= B_SIGN_RST;
            b_exp  <= B_EXP_RST;
            b_frac <= B_FRAC_RST;
         elsif load_en = '1' then
            case SW(9 downto 8) is
               when "00" =>
                  a_frac <= SW(7 downto 0);
               when "01" =>
                  a_sign <= SW(4);
                  a_exp  <= SW(3 downto 0);
               when "10" =>
                  b_frac <= SW(7 downto 0);
               when others =>
                  b_sign <= SW(4);
                  b_exp  <= SW(3 downto 0);
            end case;
         end if;
      end if;
   end process;

   ----------------------------------------------------------------------------
   -- Saneamento do operando (ver item 5 do cabecalho).
   --
   -- Um operando so e valido se estiver normalizado (bit 7 do significando em
   -- '1') ou for o zero canonico (expoente e significando nulos). Qualquer
   -- outro padrao de bits nao representa numero nenhum neste formato: em vez de
   -- alimentar o nucleo com ele e obter um resultado sem sentido, vale zero - e
   -- o ponto decimal do eco avisa que isso aconteceu.
   ----------------------------------------------------------------------------
   a_ok <= '1' when a_frac(7) = '1'
                    or (a_frac = "00000000" and a_exp = "0000") else '0';
   b_ok <= '1' when b_frac(7) = '1'
                    or (b_frac = "00000000" and b_exp = "0000") else '0';

   a_bad <= not a_ok;
   b_bad <= not b_ok;

   a_sign_eff <= a_sign      when a_ok = '1' else '0';
   a_exp_eff  <= a_exp       when a_ok = '1' else "0000";
   a_frac_eff <= a_frac      when a_ok = '1' else "00000000";
   b_sign_eff <= b_sign      when b_ok = '1' else '0';
   b_exp_eff  <= b_exp       when b_ok = '1' else "0000";
   b_frac_eff <= b_frac      when b_ok = '1' else "00000000";

   -- Eco: mostra o conteudo atual do campo selecionado (o valor CARREGADO, nao
   -- o saneado, para que se veja o que foi digitado).
   with SW(9 downto 8) select
      echo <= a_frac                 when "00",
              "000" & a_sign & a_exp when "01",
              b_frac                 when "10",
              "000" & b_sign & b_exp when others;

   ----------------------------------------------------------------------------
   -- Nucleo do somador: a versao ADAPTADA (fp_adder_fixed), com as correcoes
   -- D1, D2 e D3. O que segue o livro aqui e a natureza do bloco - puramente
   -- combinacional, sem registro entre os quatro estagios -, nao o seu
   -- conteudo. O rtl/fp_adder.vhd original nao entra na sintese.
   ----------------------------------------------------------------------------
   fp_add_unit : entity work.fp_adder_fixed
      port map (
         sign1 => a_sign_eff, sign2 => b_sign_eff,
         exp1  => a_exp_eff,  exp2  => b_exp_eff,
         frac1 => a_frac_eff, frac2 => b_frac_eff,
         sign_out     => r_sign,
         exp_out      => r_exp,
         frac_out     => r_frac,
         dbg_exp_diff => d_expdiff,
         dbg_leado    => d_leado,
         dbg_carry    => d_carry,
         dbg_zero     => open,      -- so o cancelamento exato; o LED usa a condicao ampla
         dbg_ovf      => d_ovf
      );

   -- Resultado nulo visto na saida: cobre tanto o cancelamento exato quanto a
   -- conversao para zero por ser pequeno demais para ser normalizado.
   r_is_zero <= '1' when (r_exp = "0000" and r_frac = "00000000") else '0';

   ----------------------------------------------------------------------------
   -- Displays de 7 segmentos.
   ----------------------------------------------------------------------------
   HEX5 <= '1' & SSEG_MINUS when r_sign = '1' else '1' & SSEG_BLANK;

   u_hex4 : entity work.hex_to_sseg
      port map (hex => r_frac(7 downto 4), dp => '0', sseg => HEX4);

   u_hex3 : entity work.hex_to_sseg
      port map (hex => r_frac(3 downto 0), dp => '1', sseg => HEX3);

   u_hex2 : entity work.hex_to_sseg
      port map (hex => r_exp, dp => '0', sseg => HEX2);

   -- Os pontos decimais de HEX1/HEX0 sinalizam operando invalido.
   u_hex1 : entity work.hex_to_sseg
      port map (hex => echo(7 downto 4), dp => a_bad, sseg => HEX1);

   u_hex0 : entity work.hex_to_sseg
      port map (hex => echo(3 downto 0), dp => b_bad, sseg => HEX0);

   ----------------------------------------------------------------------------
   -- LEDs de diagnostico.
   ----------------------------------------------------------------------------
   LEDR(3 downto 0) <= d_expdiff;
   LEDR(6 downto 4) <= d_leado;
   LEDR(7)          <= d_carry;
   LEDR(8)          <= r_is_zero;
   LEDR(9)          <= d_ovf;

end arch;
