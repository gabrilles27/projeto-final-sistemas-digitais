--------------------------------------------------------------------------------
-- fp_pkg.vhd
--
-- Pacote de apoio a simulacao.
--
-- Define dois modelos do somador, com papeis distintos:
--
--   fp_add_exact  Oraculo. Soma a + b pela definicao matematica do formato, em
--                 aritmetica inteira exata, e so entao procura a codificacao
--                 canonica do resultado. Nao ordena, nao alinha e nao trunca:
--                 nao compartilha nenhum estagio com o RTL.
--
--   fp_add_alg    Modelo do algoritmo de 4 estagios do livro (ordenar,
--                 alinhar, somar, normalizar) em aritmetica inteira,
--                 reproduzindo o truncamento do alinhamento. Publica tambem os
--                 sinais internos dos estagios e, no campo "book", a saida do
--                 4o estagio original, sem as correcoes D1/D2/D3.
--
-- Os dois papeis nao sao intercambiaveis. fp_add_alg mede a fidelidade do RTL
-- ao algoritmo; como reproduz o mesmo truncamento, nao mede precisao. O erro
-- numerico do algoritmo so aparece na comparacao contra fp_add_exact, de onde
-- sai a classificacao (a)/(b)/(c) da caracterizacao.
--
-- O pacote contem ainda a lista de casos dirigidos compartilhada pelos
-- testbenches, utilidades de formatacao, um decodificador de 7 segmentos
-- independente do RTL e o gerador pseudoaleatorio.
--
-- Convencao de valor:  valor = (-1)**s * (f / 256) * 2**e
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

package fp_pkg is

   ----------------------------------------------------------------------------
   -- Tipos
   ----------------------------------------------------------------------------

   -- Um operando no formato simplificado de 13 bits.
   type fp_op_t is record
      s : std_logic;                     -- sinal (1 = negativo)
      e : std_logic_vector(3 downto 0);  -- expoente, sem sinal
      f : std_logic_vector(7 downto 0);  -- significando 0.f, sem sinal
   end record;

   type fp_op_arr_t is array (natural range <>) of fp_op_t;

   -- Resultado do modelo do algoritmo. Alem do valor final, expoe os sinais
   -- internos que o RTL adaptado tambem publica, para que o testbench consiga
   -- checar os estagios intermediarios e nao so a saida.
   type fp_alg_t is record
      r            : fp_op_t;   -- resultado do algoritmo corrigido (D1/D2/D3)
      book         : fp_op_t;   -- resultado do algoritmo original do livro
      exact_cancel : boolean;   -- a soma dos significandos deu exatamente zero
      underflow    : boolean;   -- resultado pequeno demais -> convertido a zero
      overflow     : boolean;   -- carry-out com expoente ja no maximo (15)
      carry        : boolean;   -- houve carry-out no 3o estagio
      leado        : natural;   -- zeros a esquerda contados no 4o estagio
      exp_diff     : natural;   -- deslocamento aplicado no 2o estagio
      signb        : std_logic; -- sinal do operando de maior magnitude
      expb         : natural;   -- expoente do operando de maior magnitude
      sum9         : natural;   -- 3o estagio em 9 bits (o bit 8 e o carry)
      bad_input    : boolean;   -- entrada viola a premissa "normalizado ou zero"
   end record;

   -- Resultado do oraculo.
   --
   -- "exact" e falso quando a soma matematica existe mas nao cabe no formato.
   -- Isso acontece por tres motivos distintos, mantidos separados porque o
   -- relatorio precisa distinguir "o formato nao alcanca" de "o algoritmo
   -- errou":
   --   too_big   : |soma| > 0.11111111 x 2^15
   --   too_small : 0 < |soma| < 0.10000000 x 2^0  (precisaria de desnormalizado)
   --   nenhum dos dois, com exact = false : a soma cai dentro da faixa mas
   --      exigiria mais de 8 bits de significando.
   type fp_exact_t is record
      r         : fp_op_t;   -- codificacao canonica da soma (so vale se exact)
      exact     : boolean;   -- a soma exata e representavel no formato
      is_zero   : boolean;   -- a soma exata e exatamente zero
      too_big   : boolean;   -- acima do maior representavel
      too_small : boolean;   -- abaixo do menor normalizado, mas nao zero
   end record;

   constant FP_ZERO : fp_op_t := ('0', "0000", "00000000");

   ----------------------------------------------------------------------------
   -- Funcoes de construcao e formatacao
   ----------------------------------------------------------------------------

   -- Constroi um operando a partir de valores inteiros (comodidade nos TBs).
   function op(s : std_logic; e : natural; f : natural) return fp_op_t;

   -- Idem, mas recebendo o significando ja como vetor (usado nas varreduras).
   function op_from(s : integer; e : integer; f : std_logic_vector(7 downto 0))
      return fp_op_t;

   -- Verdadeiro se o operando respeita a premissa do livro: ou o bit mais
   -- significativo do significando e '1' (normalizado), ou o numero e zero.
   function is_valid(x : fp_op_t) return boolean;

   -- O operando como o nucleo tem direito de receber. Um padrao de bits que nao
   -- e normalizado nem zero canonico nao representa numero nenhum neste
   -- formato; o nivel de topo o substitui por zero antes de alimentar o nucleo
   -- (ver rtl/fp_adder_de10lite.vhd). Esta funcao e o modelo dessa protecao.
   function sanitize(x : fp_op_t) return fp_op_t;

   -- Valor real do operando, util para as mensagens de log.
   function fp_val(x : fp_op_t) return real;

   -- Formatacao "s=0 e=7 f=B0 (+88.000)".
   function fp_str(x : fp_op_t) return string;

   -- Um digito hexadecimal / um vetor em hexa.
   function hchar(v : std_logic_vector(3 downto 0)) return character;
   function hstr(v : std_logic_vector) return string;

   -- Codigo de 13 bits do operando (s & e & f), usado para medir cobertura.
   function op_code(x : fp_op_t) return natural;          -- 0 .. 8191
   type cover_t is array (0 to 8191) of boolean;

   -- Quantos dos 8192 padroes de bits sao operandos legais.
   --   4096 normalizados (f(7)='1', 16 expoentes, 2 sinais)
   --   +  2 zeros canonicos (+0 e -0)
   constant N_LEGAL_OPS : natural := 4098;

   ----------------------------------------------------------------------------
   -- Oraculo
   --
   -- Representa cada operando como inteiro com sinal escalado por 256
   --    va = (-1)^s * f * 2^e        (faixa: +-255 * 32768 = +-8.355.840)
   -- soma os dois exatamente, e so entao procura a codificacao canonica.
   -- Nao ordena, nao alinha, nao trunca, nao conta zeros a esquerda: nao tem
   -- estagio nenhum em comum com o RTL.
   ----------------------------------------------------------------------------
   function fp_add_exact(a, b : fp_op_t) return fp_exact_t;

   ----------------------------------------------------------------------------
   -- Modelo do algoritmo
   --
   -- Reproduz o algoritmo de 4 estagios (ordenar / alinhar / somar / normalizar)
   -- com aritmetica inteira, incluindo o truncamento dos bits descartados no
   -- alinhamento (o projeto ignora arredondamento, conforme o livro).
   --
   -- Diferente do RTL original em tres pontos, que sao justamente os defeitos
   -- documentados no relatorio:
   --   D1: zero sempre sai canonico, com sinal '0' (nunca "menos zero");
   --   D2: cancelamento exato sempre sai como e=0, f=0;
   --   D3: carry-out com expoente 15 satura no maior valor representavel em vez
   --       de dar a volta no contador de expoente.
   --
   -- Este modelo herda do livro a ausencia de bit de guarda e reproduz o erro
   -- de truncamento junto com o RTL, por construcao. A precisao numerica e
   -- medida contra fp_add_exact.
   ----------------------------------------------------------------------------
   function fp_add_alg(a, b : fp_op_t) return fp_alg_t;

   ----------------------------------------------------------------------------
   -- Casos dirigidos compartilhados pelos testbenches.
   ----------------------------------------------------------------------------
   constant N_DIR : natural := 14;

   constant DIR_A : fp_op_arr_t(0 to N_DIR - 1) := (
      ('0', "0111", "10010000"),   -- C0  +0.10010000 x 2^7   = +72
      ('0', "0011", "11000000"),   -- C1  +0.11000000 x 2^3   = +6
      ('0', "0011", "10001000"),   -- C2  +0.10001000 x 2^3   = +4.25
      ('0', "1001", "10000000"),   -- C3  +0.10000000 x 2^9   = +256
      ('0', "0011", "10000000"),   -- C4  +0.10000000 x 2^3   = +4
      ('0', "1001", "10101010"),   -- C5  +0.10101010 x 2^9   = +340
      ('0', "1111", "11111111"),   -- C6  +0.11111111 x 2^15  = +32640
      ('0', "1111", "11111111"),   -- C7  +0.11111111 x 2^15  = +32640
      ('0', "0000", "00000000"),   -- C8  zero
      ('0', "0000", "00000000"),   -- C9  zero
      ('0', "0101", "10101010"),   -- C10 +0.10101010 x 2^5   = +21.25
      ('0', "0100", "11000000"),   -- C11 +0.11000000 x 2^4   = +12
      ('0', "1101", "11010000"),   -- C12 +0.11010000 x 2^13  = +6656
      ('0', "1110", "11101110")    -- C13 +0.11101110 x 2^14  = +15232
   );

   constant DIR_B : fp_op_arr_t(0 to N_DIR - 1) := (
      ('0', "0101", "10000000"),   -- C0  +0.10000000 x 2^5   = +16
      ('0', "0011", "10100000"),   -- C1  +0.10100000 x 2^3   = +5
      ('1', "0100", "11000000"),   -- C2  -0.11000000 x 2^4   = -12
      ('1', "1001", "10000001"),   -- C3  -0.10000001 x 2^9   = -258
      ('1', "0011", "10000001"),   -- C4  -0.10000001 x 2^3   = -4.03125
      ('1', "1001", "10101010"),   -- C5  -0.10101010 x 2^9   = -340
      ('0', "1111", "11111111"),   -- C6  +0.11111111 x 2^15  = +32640
      ('0', "0000", "10000000"),   -- C7  +0.10000000 x 2^0   = +0.5
      ('1', "0110", "11000000"),   -- C8  -0.11000000 x 2^6   = -48
      ('0', "0000", "00000000"),   -- C9  zero
      ('1', "0101", "10101010"),   -- C10 -0.10101010 x 2^5   = -21.25
      ('1', "0100", "10000000"),   -- C11 -0.10000000 x 2^4   = -8
      ('0', "0000", "00000000"),   -- C12 zero
      ('0', "0000", "00000000")    -- C13 zero
   );

   function dir_name(i : natural) return string;

   ----------------------------------------------------------------------------
   -- Estimulo compartilhado pelas varreduras.
   ----------------------------------------------------------------------------

   -- Significandos representativos: varredura densa em expoentes e sinais.
   type frac_tbl_t is array (0 to 11) of std_logic_vector(7 downto 0);
   constant FRACS : frac_tbl_t := (
      "10000000", "10000001", "10001000", "10010000",
      "10100000", "10101010", "10111111", "11000000",
      "11010101", "11100000", "11110000", "11111111"
   );

   -- Parceiros fixos da varredura de cobertura total de operandos: cada um dos
   -- 4098 operandos legais e aplicado, dos dois lados, contra este conjunto.
   -- E o que leva a cobertura de operandos a 100% (ver A9 no relatorio).
   constant COVER_N : natural := 4;
   constant COVER_B : fp_op_arr_t(0 to COVER_N - 1) := (
      ('0', "0000", "10000000"),   -- menor normalizado positivo, +0.5
      ('0', "1111", "11111111"),   -- maior representavel, +32640
      ('1', "0111", "10101010"),   -- negativo no meio da faixa, -85
      ('0', "0000", "00000000")    -- zero
   );

   ----------------------------------------------------------------------------
   -- Decodificador de 7 segmentos INDEPENDENTE do RTL.
   --
   -- O digito e descrito pelo conjunto de segmentos acesos, em texto, e a
   -- conversao para o vetor ativo-baixo da DE10-Lite e feita por codigo.
   -- Repetir a tabela de padroes de rtl/hex_to_sseg.vhd faria a verificacao
   -- comparar a tabela com ela mesma; partindo dos segmentos, erros de
   -- polaridade ou de ordem de bits no RTL sao detectados.
   --
   -- Mapa de bits da DE10-Lite: HEXn(0)=a, (1)=b, (2)=c, (3)=d, (4)=e, (5)=f,
   -- (6)=g, (7)=ponto decimal. Segmento aceso = '0'.
   ----------------------------------------------------------------------------
   function sseg_of(lit : string) return std_logic_vector;   -- 7 bits, ativo-baixo
   function seg_letters(d : integer) return string;
   function seg_expected(d : integer) return std_logic_vector;

   -- Derivados da MESMA formulacao por segmentos, e nao copiados do RTL: o
   -- traco de menos acende so o segmento g, e o display apagado nao acende
   -- nenhum. Sao constantes deferidas porque o valor vem de sseg_of, cujo corpo
   -- so existe no corpo do pacote.
   constant SSEG_MINUS : std_logic_vector(6 downto 0);
   constant SSEG_BLANK : std_logic_vector(6 downto 0);

   ----------------------------------------------------------------------------
   -- Gerador pseudoaleatorio deterministico (LFSR de 32 bits).
   -- Deterministico: o mesmo conjunto de vetores e reproduzido em qualquer
   -- simulador, o que torna o resultado do teste auditavel.
   ----------------------------------------------------------------------------
   subtype rnd_t is unsigned(31 downto 0);
   constant RND_SEED : rnd_t := x"ACE1F0D5";

   procedure lfsr_step(variable s : inout rnd_t);
   procedure rand_op(variable s : inout rnd_t; variable o : out fp_op_t);

end package fp_pkg;


package body fp_pkg is

   ----------------------------------------------------------------------------
   function op(s : std_logic; e : natural; f : natural) return fp_op_t is
      variable r : fp_op_t;
   begin
      r.s := s;
      r.e := std_logic_vector(to_unsigned(e, 4));
      r.f := std_logic_vector(to_unsigned(f, 8));
      return r;
   end function;

   ----------------------------------------------------------------------------
   function op_from(s : integer; e : integer; f : std_logic_vector(7 downto 0))
      return fp_op_t is
      variable r : fp_op_t;
   begin
      if s = 0 then
         r.s := '0';
      else
         r.s := '1';
      end if;
      r.e := std_logic_vector(to_unsigned(e, 4));
      r.f := f;
      return r;
   end function;

   ----------------------------------------------------------------------------
   function is_valid(x : fp_op_t) return boolean is
   begin
      if x.f(7) = '1' then
         return true;                                   -- normalizado
      end if;
      return (x.f = "00000000") and (x.e = "0000");     -- zero canonico
   end function;

   ----------------------------------------------------------------------------
   function sanitize(x : fp_op_t) return fp_op_t is
   begin
      if is_valid(x) then
         return x;
      end if;
      return FP_ZERO;
   end function;

   ----------------------------------------------------------------------------
   function fp_val(x : fp_op_t) return real is
      variable m : real;
   begin
      m := real(to_integer(unsigned(x.f))) / 256.0
           * 2.0 ** to_integer(unsigned(x.e));
      if x.s = '1' then
         return -m;
      end if;
      return m;
   end function;

   ----------------------------------------------------------------------------
   function op_code(x : fp_op_t) return natural is
      variable c : natural := 0;
   begin
      if x.s = '1' then
         c := 4096;
      end if;
      return c + to_integer(unsigned(x.e)) * 256 + to_integer(unsigned(x.f));
   end function;

   ----------------------------------------------------------------------------
   function hchar(v : std_logic_vector(3 downto 0)) return character is
      constant TBL : string(1 to 16) := "0123456789ABCDEF";
   begin
      if is_x(v) then
         return 'X';
      end if;
      return TBL(to_integer(unsigned(v)) + 1);
   end function;

   function hstr(v : std_logic_vector) return string is
      constant NV  : std_logic_vector(v'length - 1 downto 0) := v;
      variable res : string(1 to (v'length + 3) / 4);
      variable idx : integer;
      variable nib : std_logic_vector(3 downto 0);
   begin
      for i in res'range loop
         idx := (res'length - i) * 4;
         nib := (others => '0');
         for k in 0 to 3 loop
            if idx + k <= NV'left then
               nib(k) := NV(idx + k);
            end if;
         end loop;
         res(i) := hchar(nib);
      end loop;
      return res;
   end function;

   ----------------------------------------------------------------------------
   function fp_str(x : fp_op_t) return string is
      variable sv : std_logic_vector(3 downto 0) := "0000";
   begin
      sv(0) := x.s;
      return "s=" & hchar(sv)
             & " e=" & hchar(x.e)
             & " f=" & hstr(x.f)
             & " (" & real'image(fp_val(x)) & ")";
   end function;

   ----------------------------------------------------------------------------
   -- Oraculo independente: soma exata e depois codifica.
   ----------------------------------------------------------------------------
   function fp_add_exact(a, b : fp_op_t) return fp_exact_t is
      variable res : fp_exact_t;
      variable va, vb, sm, m, t : integer;
      variable e   : integer;
      variable neg : std_logic;
   begin
      res.r         := FP_ZERO;
      res.exact     := false;
      res.is_zero   := false;
      res.too_big   := false;
      res.too_small := false;

      -- Valor de cada operando, escalado por 256 para ficar inteiro.
      va := to_integer(unsigned(a.f)) * (2 ** to_integer(unsigned(a.e)));
      if a.s = '1' then
         va := -va;
      end if;
      vb := to_integer(unsigned(b.f)) * (2 ** to_integer(unsigned(b.e)));
      if b.s = '1' then
         vb := -vb;
      end if;

      -- Soma exata. Faixa: +-16.711.680, folgada dentro de integer.
      sm := va + vb;

      if sm = 0 then
         res.is_zero := true;
         res.exact   := true;
         res.r       := FP_ZERO;
         return res;
      end if;

      if sm < 0 then
         neg := '1';
         m   := -sm;
      else
         neg := '0';
         m   := sm;
      end if;

      -- Menor expoente que traz a magnitude para 8 bits. Como m > 0, ao sair do
      -- laco vale t <= 255; e se houve ao menos uma divisao, t >= 128.
      e := 0;
      t := m;
      while t > 255 loop
         t := t / 2;
         e := e + 1;
      end loop;

      if e > 15 then
         res.too_big := true;                 -- passa de 0.11111111 x 2^15
         return res;
      end if;
      if t < 128 then
         res.too_small := true;               -- so ocorre com e=0, isto e, m<128
         return res;
      end if;
      if t * (2 ** e) /= m then
         return res;                          -- exigiria mais de 8 bits
      end if;

      res.exact := true;
      res.r.s   := neg;
      res.r.e   := std_logic_vector(to_unsigned(e, 4));
      res.r.f   := std_logic_vector(to_unsigned(t, 8));
      return res;
   end function;

   ----------------------------------------------------------------------------
   -- Modelo do algoritmo de 4 estagios.
   ----------------------------------------------------------------------------
   function fp_add_alg(a, b : fp_op_t) return fp_alg_t is
      variable res   : fp_alg_t;
      variable big   : fp_op_t;
      variable small : fp_op_t;
      variable eb    : integer;
      variable es    : integer;
      variable fb    : integer;
      variable fs    : integer;
      variable d     : integer;
      variable fa    : integer;
      variable sum   : integer;
      variable s8    : integer;
      variable l     : integer;
      variable mant  : integer;
   begin
      res.r            := FP_ZERO;
      res.book         := FP_ZERO;
      res.exact_cancel := false;
      res.underflow    := false;
      res.overflow     := false;
      res.carry        := false;
      res.leado        := 0;
      res.exp_diff     := 0;
      res.signb        := '0';
      res.expb         := 0;
      res.sum9         := 0;
      res.bad_input    := not (is_valid(a) and is_valid(b));

      -- 1o estagio: ordenar. O criterio e o do livro - compara o padrao de bits
      -- e&f, o que equivale a comparar as magnitudes desde que os operandos
      -- estejam normalizados ou sejam zero (premissa registrada em bad_input).
      if (a.e & a.f) > (b.e & b.f) then
         big   := a;
         small := b;
      else
         big   := b;
         small := a;
      end if;

      eb := to_integer(unsigned(big.e));
      es := to_integer(unsigned(small.e));
      fb := to_integer(unsigned(big.f));
      fs := to_integer(unsigned(small.f));

      res.signb := big.s;
      res.expb  := eb;

      -- 2o estagio: alinhar, deslocando o menor para a direita.
      -- A divisao inteira reproduz o descarte dos bits que saem do vetor - e e
      -- exatamente aqui que nasce a perda de precisao medida no relatorio: sem
      -- bit de guarda, o que sai do vetor some antes da subtracao.
      d            := eb - es;
      res.exp_diff := d;
      if d >= 8 then
         fa := 0;
      else
         fa := fs / (2 ** d);
      end if;

      -- 3o estagio: somar ou subtrair os significandos ja alinhados.
      if big.s = small.s then
         sum := fb + fa;
      else
         sum := fb - fa;
      end if;

      -- Com entradas validas isto nunca ocorre. Com entradas invalidas o RTL
      -- calcula em 9 bits sem sinal e o "emprestimo" volta como carry; aqui so
      -- registramos que a premissa foi violada.
      if sum < 0 then
         res.bad_input := true;
         sum           := 0;
      end if;

      res.sum9  := sum;
      res.carry := (sum > 255);

      -- Contagem de zeros a esquerda sobre os 8 bits baixos, exatamente como
      -- o codificador de prioridade do RTL (que satura em 7 e, por isso, nao
      -- distingue "sum = 0" de "sum = 1" - a origem do defeito D2).
      s8 := sum mod 256;
      if    s8 >= 128 then l := 0;
      elsif s8 >=  64 then l := 1;
      elsif s8 >=  32 then l := 2;
      elsif s8 >=  16 then l := 3;
      elsif s8 >=   8 then l := 4;
      elsif s8 >=   4 then l := 5;
      elsif s8 >=   2 then l := 6;
      else                 l := 7;
      end if;
      res.leado := l;

      -- 4o estagio: normalizar.
      if sum = 0 then
         -- Cancelamento exato: o resultado e zero e deve sair na forma canonica.
         res.exact_cancel := true;
         res.r            := FP_ZERO;

      elsif sum > 255 then
         -- Carry-out: desloca o significando uma casa a direita e incrementa o
         -- expoente. Se o expoente ja esta no maximo, o valor nao e
         -- representavel: saturamos no maior numero da faixa.
         if eb = 15 then
            res.overflow := true;
            res.r.s      := big.s;
            res.r.e      := "1111";
            res.r.f      := "11111111";
         else
            res.r.s := big.s;
            res.r.e := std_logic_vector(to_unsigned(eb + 1, 4));
            res.r.f := std_logic_vector(to_unsigned(sum / 2, 8));
         end if;

      elsif l > eb then
         -- Precisaria de mais deslocamentos do que o expoente permite:
         -- resultado abaixo do menor normalizado, converte para zero.
         res.underflow := true;
         res.r         := FP_ZERO;

      else
         mant    := s8 * (2 ** l);
         res.r.s := big.s;
         res.r.e := std_logic_vector(to_unsigned(eb - l, 4));
         res.r.f := std_logic_vector(to_unsigned(mant, 8));
      end if;

      ------------------------------------------------------------------------
      -- 4o estagio do livro, sem nenhuma das correcoes.
      --
      -- Os tres primeiros estagios sao os mesmos (o livro e a versao corrigida
      -- so divergem na normalizacao), por isso o calculo e compartilhado.
      -- Com este campo o testbench da Etapa 1 exige o VALOR EXATO que o codigo
      -- original produz em cada vetor, inclusive nos vetores em que ele erra.
      --
      --   sem tratamento de sum = 0  -> D2 (e = expb-7, f = 0, se expb >= 8)
      --   expb + 1 em 4 bits         -> D3 (da a volta para 0 quando expb = 15)
      --   sign_out <= signb sempre   -> D1 (zero com sinal)
      ------------------------------------------------------------------------
      if sum > 255 then
         res.book.s := big.s;
         res.book.e := std_logic_vector(to_unsigned((eb + 1) mod 16, 4));
         res.book.f := std_logic_vector(to_unsigned(sum / 2, 8));
      elsif l > eb then
         res.book.s := big.s;
         res.book.e := "0000";
         res.book.f := "00000000";
      else
         res.book.s := big.s;
         res.book.e := std_logic_vector(to_unsigned(eb - l, 4));
         res.book.f := std_logic_vector(to_unsigned((s8 * (2 ** l)) mod 256, 8));
      end if;

      return res;
   end function;

   ----------------------------------------------------------------------------
   function dir_name(i : natural) return string is
   begin
      case i is
         when 0  => return "C0  soma alinhada, sem normalizacao";
         when 1  => return "C1  carry-out apos soma (eg.4 do livro)";
         when 2  => return "C2  subtracao com expoentes diferentes (eg.1)";
         when 3  => return "C3  normalizacao maxima: 7 deslocamentos (eg.2)";
         when 4  => return "C4  resultado pequeno demais -> zero (eg.3)";
         when 5  => return "C5  cancelamento exato, expoente alto  [D2]";
         when 6  => return "C6  carry-out com expoente 15          [D3]";
         when 7  => return "C7  alinhamento descarta todo o menor";
         when 8  => return "C8  zero + normalizado";
         when 9  => return "C9  zero + zero";
         when 10 => return "C10 cancelamento exato, expoente baixo [D1]";
         when 11 => return "C11 subtracao com 1 deslocamento";
         when 12 => return "C12 exibe o digito d nos displays";
         when others => return "C13 exibe o digito E nos displays";
      end case;
   end function;

   ----------------------------------------------------------------------------
   function sseg_of(lit : string) return std_logic_vector is
      variable v : std_logic_vector(6 downto 0) := (others => '1');  -- apagado
   begin
      for i in lit'range loop
         v(character'pos(lit(i)) - character'pos('a')) := '0';       -- acende
      end loop;
      return v;
   end function;

   function seg_letters(d : integer) return string is
   begin
      case d is
         when  0 => return "abcdef";
         when  1 => return "bc";
         when  2 => return "abdeg";
         when  3 => return "abcdg";
         when  4 => return "bcfg";
         when  5 => return "acdfg";
         when  6 => return "acdefg";
         when  7 => return "abc";
         when  8 => return "abcdefg";
         when  9 => return "abcdfg";
         when 10 => return "abcefg";    -- A
         when 11 => return "cdefg";     -- b
         when 12 => return "adef";      -- C
         when 13 => return "bcdeg";     -- d
         when 14 => return "adefg";     -- E
         when others => return "aefg";  -- F
      end case;
   end function;

   function seg_expected(d : integer) return std_logic_vector is
   begin
      return sseg_of(seg_letters(d));
   end function;

   -- Valor das constantes deferidas, agora que sseg_of ja foi elaborada.
   constant SSEG_MINUS : std_logic_vector(6 downto 0) := sseg_of("g");
   constant SSEG_BLANK : std_logic_vector(6 downto 0) := sseg_of("");

   ----------------------------------------------------------------------------
   procedure lfsr_step(variable s : inout rnd_t) is
      variable b : std_logic;
   begin
      b := s(31) xor s(21) xor s(1) xor s(0);
      s := s(30 downto 0) & b;
   end procedure;

   procedure rand_op(variable s : inout rnd_t; variable o : out fp_op_t) is
      variable t : fp_op_t;
   begin
      -- 13 passos de LFSR por operando, e cada campo le uma janela DIFERENTE
      -- dos 13 bits recem-gerados (s(12..0)).
      --
      -- As janelas precisam ser disjuntas. Se sinal, expoente e significando
      -- lessem faixas sobrepostas do mesmo registrador, um campo passaria a ser
      -- funcao do outro e o gerador alcancaria apenas algumas centenas dos 4098
      -- operandos legais, por mais sorteios que fossem feitos.
      for k in 1 to 13 loop
         lfsr_step(s);
      end loop;
      t.s := s(12);
      t.e := std_logic_vector(s(11 downto 8));
      t.f := '1' & std_logic_vector(s(7 downto 1));   -- normalizado por construcao

      -- Mais 4 bits, independentes dos anteriores, decidem se o operando e o
      -- zero canonico (aproximadamente 1 em 16), para exercitar esse caminho.
      for k in 1 to 4 loop
         lfsr_step(s);
      end loop;
      if s(3 downto 0) = "0000" then
         t := FP_ZERO;
      end if;

      o := t;
   end procedure;

end package body fp_pkg;
