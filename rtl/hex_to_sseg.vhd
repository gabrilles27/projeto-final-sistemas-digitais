--------------------------------------------------------------------------------
-- hex_to_sseg.vhd
--
-- ETAPA 2 - Decodificador hexadecimal -> display de 7 segmentos da DE10-Lite.
--
-- Substitui o hex_to_sseg do livro, que era escrito para a placa Nexys/S3.
-- Duas diferencas de hardware obrigaram a reescrita:
--
--   * ordem dos bits. No livro, sseg(6) e o segmento 'a' e sseg(0) e o 'g'.
--     Na DE10-Lite o mapeamento e o inverso: HEXn(0)=a, (1)=b, (2)=c, (3)=d,
--     (4)=e, (5)=f, (6)=g e (7)=ponto decimal. Reaproveitar a tabela do livro
--     sem inverter acenderia os segmentos espelhados.
--
--   * o ponto decimal. Na DE10-Lite ele e o bit 7 do proprio barramento do
--     display, e nao um pino separado.
--
-- Os displays sao de anodo comum: segmento aceso = '0'.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity hex_to_sseg is
   port(
      hex  : in  std_logic_vector(3 downto 0);
      dp   : in  std_logic;                      -- '1' acende o ponto decimal
      sseg : out std_logic_vector(7 downto 0)    -- ativo-baixo; sseg(7) = ponto
   );
end hex_to_sseg;

architecture arch of hex_to_sseg is
   signal seg : std_logic_vector(6 downto 0);
begin

   -- Tabela na ordem g f e d c b a (bit 6 ... bit 0), '0' = aceso.
   with hex select
      seg <=
         "1000000" when "0000",   -- 0 : a b c d e f
         "1111001" when "0001",   -- 1 : b c
         "0100100" when "0010",   -- 2 : a b d e g
         "0110000" when "0011",   -- 3 : a b c d g
         "0011001" when "0100",   -- 4 : b c f g
         "0010010" when "0101",   -- 5 : a c d f g
         "0000010" when "0110",   -- 6 : a c d e f g
         "1111000" when "0111",   -- 7 : a b c
         "0000000" when "1000",   -- 8 : todos
         "0010000" when "1001",   -- 9 : a b c d f g
         "0001000" when "1010",   -- A : a b c e f g
         "0000011" when "1011",   -- b : c d e f g
         "1000110" when "1100",   -- C : a d e f
         "0100001" when "1101",   -- d : b c d e g
         "0000110" when "1110",   -- E : a d e f g
         "0001110" when "1111",   -- F : a e f g
         "1111111" when others;   -- apagado (entrada com X/U na simulacao)

   sseg(6 downto 0) <= seg;
   sseg(7)          <= not dp;    -- ponto tambem e ativo-baixo

end arch;
