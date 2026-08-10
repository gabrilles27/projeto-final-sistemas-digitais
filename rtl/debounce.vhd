--------------------------------------------------------------------------------
-- debounce.vhd
--
-- ETAPA 2 - Sincronizador + anti-repique + detector de borda para os botoes.
--
-- Por que isto existe: o circuito do livro era puramente combinacional e nao
-- tinha como carregar os 26 bits dos dois operandos, porque a placa dele
-- tambem nao tinha entradas suficientes. A solucao adotada aqui e carregar os
-- campos um a um, com um botao. Isso obriga a tratar o repique mecanico do
-- botao: sem isso, um unico toque geraria varios pulsos de carga e o valor
-- escrito no registrador seria imprevisivel.
--
-- Estrutura:
--   1. dois flip-flops em serie sincronizam a entrada assincrona ao clock
--      (evita metaestabilidade);
--   2. um contador so deixa o nivel "estavel" mudar depois que a entrada
--      sincronizada permanece diferente por 2**(CNT_BITS-1) ciclos;
--   3. rise/fall geram um pulso de um unico ciclo nas bordas do nivel estavel.
--
-- A janela vale 2**(CNT_BITS-1) ciclos, porque o disparo e o bit mais alto do
-- contador. Com CNT_BITS = 20 a 50 MHz isso da 524.288 ciclos = 10,486 ms,
-- folgado sobre o repique mecanico tipico (1 a 10 ms). A simulacao instancia
-- com um valor pequeno para nao gastar tempo.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity debounce is
   generic (
      CNT_BITS : natural := 20
   );
   port(
      clk   : in  std_logic;
      reset : in  std_logic;
      din   : in  std_logic;   -- entrada bruta, ja em logica ativa-alta
      level : out std_logic;   -- nivel estavel
      rise  : out std_logic;   -- pulso de 1 ciclo na borda de subida
      fall  : out std_logic    -- pulso de 1 ciclo na borda de descida
   );
end debounce;

architecture arch of debounce is
   -- Os valores iniciais sao o estado de energizacao do dispositivo (os
   -- registradores do MAX 10 acordam em '0' apos a configuracao). Existem para
   -- que o bloco possa ser usado tambem SEM reset - e o caso do filtro do
   -- proprio botao de reset, que nao tem de onde tirar um - e para que a
   -- simulacao comece do mesmo estado que a placa, em vez de 'U'.
   signal sync     : std_logic_vector(1 downto 0) := (others => '0');
   signal stable_r : std_logic := '0';
   signal stable_d : std_logic := '0';
   signal cnt      : unsigned(CNT_BITS - 1 downto 0) := (others => '0');
begin

   process(clk, reset)
   begin
      if reset = '1' then
         sync     <= (others => '0');
         stable_r <= '0';
         stable_d <= '0';
         cnt      <= (others => '0');
      elsif rising_edge(clk) then
         sync     <= sync(0) & din;
         stable_d <= stable_r;

         if sync(1) = stable_r then
            -- entrada concorda com o nivel atual: zera a janela
            cnt <= (others => '0');
         else
            cnt <= cnt + 1;
            -- Testar o bit mais significativo evita comparar com uma constante
            -- calculada a partir do generic (que estouraria em larguras grandes).
            if cnt(CNT_BITS - 1) = '1' then
               stable_r <= sync(1);
               cnt      <= (others => '0');
            end if;
         end if;
      end if;
   end process;

   level <= stable_r;
   rise  <= stable_r and (not stable_d);
   fall  <= (not stable_r) and stable_d;

end arch;
