# Tutorial: Implementação de Somador Ponto Flutuante na DE10-Lite

**Autores:** Daniel Mendes Vale de Sá (11201921422), Gabrielly Souza Santiago (11202231242), Pedro Henrique de Moraes Lui (11201722622).

**Disciplina:** Sistemas Digitais Q2.2026

**Data:** 07/08/2026

---
*Etapa 1*
## 1. Objetivo do Projeto
O objetivo deste projeto é validar o funcionamento do somador de ponto flutuante simplificado de 13 bits, adaptá-lo para a placa DE10-Lite e verificar, por meio de simulações e testes na FPGA, que as modificações realizadas não alteram a lógica matemática do circuito.

## 2. Descrição gráfica do funcionamento do sistema

O sistema implementa um somador de ponto flutuante simplificado de 13 bits. Cada operando possui três campos:

| Campo        | Quantidade de bits | Entradas do operando A | Entradas do operando B |
| ------------ | -----------------: | ---------------------- | ---------------------- |
| Sinal (s)    |                  1 | `sign1`                | `sign2`                |
| Expoente (e) |                  4 | `exp1(3 downto 0)`     | `exp2(3 downto 0)`     |
| Fração (f)   |                  8 | `frac1(7 downto 0)`    | `frac2(7 downto 0)`    |

O valor representado por cada operando é:

$$
valor = (-1)^s \times 0.f \times 2^e
$$

Considerando a fração como um número inteiro de 8 bits, tem-se:

$$
valor = (-1)^s \times \frac{f}{256} \times 2^e
$$

O circuito recebe dois operandos e realiza a soma em quatro etapas principais: comparação das magnitudes, alinhamento dos expoentes, soma (ou subtração) das frações e normalização do resultado.

```mermaid
flowchart LR

A["Entradas
sign1
exp1
frac1

sign2
exp2
frac2"]

B["Comparação das Magnitudes (Stage 1)"]

C["Alinhamento
dos Expoentes (Stage 2)"]

D["Soma / Subtração (Stage 3)"]

E["Normalização (Stage 4)"]

F["Saídas
sign_out
exp_out
frac_out"]

A --> B
B --> C
C --> D
D --> E
E --> F
```

### Entradas e saídas

| Sinal | Tipo | Descrição |
|:------|:----:|:----------|
| `sign1` | Entrada | Bit de sinal do primeiro operando |
| `exp1` | Entrada | Expoente do primeiro operando |
| `frac1` | Entrada | Fração do primeiro operando |
| `sign2` | Entrada | Bit de sinal do segundo operando |
| `exp2` | Entrada | Expoente do segundo operando |
| `frac2` | Entrada | Fração do segundo operando |
| `sign_out` | Saída | Bit de sinal do resultado |
| `exp_out` | Saída | Expoente do resultado |
| `frac_out` | Saída | Fração do resultado |

### 2.1 Primeiro estágio: ordenação dos operandos

O primeiro estágio identifica qual operando possui a maior magnitude.

A comparação é feita usando a concatenação do expoente com a fração:

```vhdl
exp1 & frac1
exp2 & frac2
```

A condição utilizada é equivalente a:

```vhdl
if (exp1 & frac1) > (exp2 & frac2) then
    -- operando 1 é o maior
else
    -- operando 2 é o maior
end if;
```

O maior operando é armazenado nos sinais terminados em `b`, de *big*:

```text
signb
expb
fracb
```

O menor operando é armazenado nos sinais terminados em `s`, de *small*:

```text
signs
exps
fracs
```

### 2.2 Segundo estágio: alinhamento dos expoentes

Para somar dois números de ponto flutuante, as duas frações precisam estar associadas ao mesmo expoente.

Primeiro é calculada a diferença entre os expoentes:

```vhdl
exp_diff <= expb - exps;
```

Como `expb` pertence ao operando de maior magnitude, a diferença é sempre maior ou igual a zero.

Depois, a fração do menor operando é deslocada para a direita:

```vhdl
fraca <= shift_right(fracs, to_integer(exp_diff));
```

O sufixo `a` indica que o valor está alinhado, de *aligned*.

### 2.3 Terceiro estágio: soma ou subtração

O circuito utiliza representação sinal-magnitude. Por isso, a operação depende dos sinais dos operandos.

| Condição         | Operação                 |
| ---------------- | ------------------------ |
| `signb = signs`  | Soma das magnitudes      |
| `signb /= signs` | Subtração das magnitudes |

A operação pode ser representada por:

```vhdl
sum <= ('0' & fracb) + ('0' & fraca) when signb = signs else
       ('0' & fracb) - ('0' & fraca);
```

As frações possuem 8 bits, mas a soma é feita com 9 bits:

```text
'0' & fracb
'0' & fraca
```

O bit adicional permite armazenar o carry da soma:

```text
sum(8) = carry-out
```

O sinal do resultado é inicialmente o sinal do operando de maior magnitude:

```vhdl
signn <= signb;
```

Isso ocorre porque, em uma subtração entre magnitudes, o resultado possui o sinal do operando de maior módulo.

### 2.4 Quarto estágio: normalização

Após a soma ou subtração, o resultado pode não estar no formato normalizado esperado.

O quarto estágio realiza três operações:

1. verifica se houve carry;
2. conta os zeros à esquerda;
3. ajusta a fração e o expoente.

#### Contagem de zeros à esquerda

O sinal `leado` informa quantos deslocamentos para a esquerda são necessários para colocar o primeiro bit `1` na posição mais significativa da fração.

| `sum(7 downto 0)` | `leado` |
| ----------------- | ------- |
| `1xxxxxxx`        | `000`   |
| `01xxxxxx`        | `001`   |
| `001xxxxx`        | `010`   |
| `0001xxxx`        | `011`   |
| `00001xxx`        | `100`   |
| `000001xx`        | `101`   |
| `0000001x`        | `110`   |
| `00000001`        | `111`   |

O deslocamento é feito por:

```vhdl
sum_norm <= shift_left(sum(7 downto 0), to_integer(leado));
```

#### Decisão do resultado final

| Situação               | Operação                                                                  |
| ---------------------- | ------------------------------------------------------------------------- |
| Resultado igual a zero | Sinal, expoente e fração são zerados                                |
| Carry igual a `1`      | Fração deslocada uma posição para a direita e expoente incrementado |
| `leado > expb`         | Resultado considerado pequeno demais e convertido em zero                 |
| Caso normal            | Fração deslocada para a esquerda e expoente reduzido                |

*Etapa 2*
## 3. Adaptações de Hardware (DE10-Lite)
O projeto original foi desenvolvido para uma plataforma FPGA diferente da DE10-Lite. Para possibilitar sua utilização na placa, foi criada uma nova interface de hardware, preservando a lógica matemática do somador de ponto flutuante e adaptando apenas os módulos responsáveis pela interação com o usuário e pela visualização dos resultados.

### O que mudamos no VHDL original

- **Removemos o módulo `disp_mux`.** No circuito original, os quatro displays de sete segmentos compartilhavam os mesmos sinais e eram acionados alternadamente pelo módulo `disp_mux`. Como a DE10-Lite possui seis displays independentes (`HEX0` a `HEX5`), esse módulo deixou de ser necessário e foi removido.

- **Removemos os operandos fixos.** O circuito original utilizava parte dos operandos fixa porque a placa possuía poucas chaves de entrada. Na DE10-Lite, os dois operandos passaram a ser armazenados em registradores e carregados campo a campo pelas chaves e botões, permitindo representar qualquer combinação de entradas.

- **Reorganizamos as entradas.** As chaves `SW(9 downto 8)` passaram a selecionar o campo que será carregado e `SW(7 downto 0)` fornecem os dados. O botão `KEY(0)` realiza a carga do campo selecionado e `KEY(1)` executa o reset. Como os botões da DE10-Lite são ativos em nível baixo, foi necessário adaptar essa lógica e adicionar um circuito de *debounce*, garantindo que cada pressão do botão fosse reconhecida apenas uma vez.

- **Roteamos sinais internos para os LEDs.** Alguns sinais internos do somador foram ligados aos LEDs (`LEDR`) para facilitar a visualização do funcionamento do circuito durante os testes na placa.

- **Adicionamos a validação dos operandos.** No circuito original, a fração era montada de forma que o bit mais significativo fosse sempre `1`, garantindo que o operando estivesse normalizado. Como na DE10-Lite os operandos são carregados livremente pelas chaves, passou a ser possível inserir valores não normalizados. Nesses casos, o circuito poderia identificar incorretamente o operando de maior magnitude e produzir resultados com sinal e magnitude incorretos. Para evitar esse problema, foi adicionada uma etapa de validação entre os registradores e o núcleo do somador. Se um operando não estiver normalizado e também não representar o zero canônico, ele é tratado como zero, e essa condição é indicada ao usuário no painel da placa.

### Descrição gráfica do sistema

```mermaid
flowchart LR

SW["SW(9..0)<br/> Dados dos operandos"]

KEY["KEY(0) e KEY(1)<br/> Carga e Reset"]

DB["Debounce"]

REG["Registradores"]

VAL["Validação<br/> dos operandos"]

CORE["fp_adder_fixed"]

HEX["HEX0...HEX5<br/> Resultado"]

LED["LEDR(0)...LEDR(9)<br/> Validação"]

SW --> REG
KEY --> DB
DB --> REG

REG --> VAL
VAL --> CORE

CORE --> HEX
CORE --> LED
```

### Interface da DE10-Lite

| Recurso | Função |
|---------|--------|
| `SW(9 downto 8)` | Seleciona o campo do operando que será carregado |
| `SW(7 downto 0)` | Dados do campo selecionado |
| `KEY(0)` | Carrega o campo selecionado |
| `KEY(1)` | Reinicia os registradores com os valores padrão |
| `HEX5` | Sinal do resultado |
| `HEX4` e `HEX3` | Fração do resultado |
| `HEX2` | Expoente do resultado |
| `HEX1` e `HEX0` | Exibem o campo carregado e indicam operandos inválidos |
| `LEDR(3 downto 0)` | Diferença entre os expoentes (`exp_diff`) |
| `LEDR(6 downto 4)` | Quantidade de zeros à esquerda (`leado`) |
| `LEDR(7)` | Carry da soma |
| `LEDR(8)` | Resultado igual a zero |
| `LEDR(9)` | Overflow do expoente |

### Seleção dos campos dos operandos por SW(9 downto 8)

| `SW(9 downto 8)` | Campo carregado                | Dados                      |
| ---------------- | ------------------------------ | -------------------------- |
| `00`             | Significando do operando A     | `SW(7 downto 0)`           |
| `01`             | Sinal e expoente do operando A | `SW(4)` e `SW(3 downto 0)` |
| `10`             | Significando do operando B     | `SW(7 downto 0)`           |
| `11`             | Sinal e expoente do operando B | `SW(4)` e `SW(3 downto 0)` |

## 4. Evidências de Validação

### Simulação 
Abaixo, a imagem do funcionamento do 4º estágio (normalização). Considerar os 4 casos detalhados.

![Print das Telas do Simulador com as Formas de Onda](link-da-imagem-aqui.jpg)

### Código VHDL Final 
```vhdl
-- Insira aqui o VHDL final e faça ênfase nos trechos de código mais importantes da sua adaptação, isto é, eles devem estar claramente identificados.
```
*Etapa 3*

### Funcionamento na Placa
Abaixo, imagens do funcionamento na Placa para 4 casos.

*Etapa 4 (considerando qeu a Etapa 4 considera toda a documentação em si)*
## 5. Diário de Bordo de IA 
Utilizamos o [ChatGPT/Claude/Gemini] para auxiliar na geração do Testbench e na refatoração do código. Abaixo está a análise crítica do uso da ferramenta.

**Prompts Utilizados:**
> "Insira aqui o prompt exato que você usou..."

**O Erro da IA (Alucinação):**
> Descreva aqui o que a IA errou (ex: tentou usar pinos inexistentes, criou clock em testbench de circuito combinacional, etc).

**A Correção Humana:**
> Como você corrigiu o código gerado para que ele funcionasse na nossa placa e na simulação.

## 6. Contribuição dos participantes
 * Daniel Mendes Vale de Sá, Administração do Projeto, Desenvolvimento, implementação e teste de software, Análise Formal
 * Gabrielly Souza Santiago, Redação do manuscrito original, Documentação técnica
 * Pedro Henrique de Moraes Lui, Redação do manuscrito original, Validação de dados e experimentos
