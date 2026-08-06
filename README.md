# Tutorial: Implementação de Somador Ponto Flutuante na DE10-Lite

**Autores:** Gabrielly Souza Santiago (11202231242), Pedro Henrique de Moraes Lui (11201722622), Daniel Mendes Vale de Sá (11201921422)

**Disciplina:** Sistemas Digitais Q2.2026

**Data:** 07/08/2026

---
*Etapa 1*
## 1. Objetivo do Projeto
O objetivo deste projeto é validar o funcionamento do somador de ponto flutuante simplificado de 13 bits, adaptá-lo para a placa DE10-Lite e verificar, por meio de simulações e testes na FPGA, que as modificações realizadas não alteram a lógica matemática do circuito.

## 2. Descrição gráfica do funcionamento do sistema

O circuito recebe dois operandos em formato de ponto flutuante simplificado de 13 bits e realiza a soma em quatro etapas principais: comparação das magnitudes, alinhamento dos expoentes, soma (ou subtração) das frações e normalização do resultado.

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

*Etapa 2*
## 3. Adaptações de Hardware (DE10-Lite)
O projeto original foi desenvolvido para uma plataforma FPGA diferente da DE10-Lite. Para possibilitar sua utilização na placa, foi criada uma nova interface de hardware, preservando a lógica matemática do somador de ponto flutuante e adaptando apenas os módulos responsáveis pela interação com o usuário e pela visualização dos resultados.

### O que mudamos no VHDL original

- **Removemos** o módulo de multiplexação dos displays (`disp_mux`), uma vez que a DE10-Lite possui seis displays de sete segmentos independentes.
- **Removemos** a interface de teste original, permitindo que os operandos fossem carregados pelo usuário utilizando as chaves (`SW`) e os botões (`KEY`) da DE10-Lite.
- **Reorganizamos** as entradas para que os operandos sejam carregados utilizando as chaves (`SW`) e os botões (`KEY`) da placa.
- **Roteamos** o resultado da operação para os displays de sete segmentos (`HEX0` a `HEX5`) e os sinais auxiliares de validação para os LEDs (`LEDR`).
- **Adicionamos** um circuito de *debounce* para eliminar o efeito de repique mecânico dos botões durante o carregamento dos operandos.

**Descrição gráfica do sistema**
```mermaid
flowchart LR

SW["SW(9..0)<br/>Dados dos operandos"]

KEY["KEY(0) e KEY(1)<br/>Carga e Reset"]

DB["Debounce"]

REG["Registradores"]

CORE["fp_adder_fixed"]

HEX["HEX0...HEX5<br/>Resultado"]

LED["LEDR<br/>Validação"]

SW --> REG
KEY --> DB
DB --> REG

REG --> CORE

CORE --> HEX
CORE --> LED
```

### Interface da DE10-Lite

| Recurso | Função |
|----------|--------|
| `SW` | Entrada dos operandos |
| `KEY` | Carga dos registradores e reset |
| `HEX0–HEX5` | Exibição do resultado da operação |
| `LEDR` | Visualização de sinais internos para validação |

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
Utilize a taxonomia CRediT, seguem exemplos:
 * [Nome do Aluno 1], Administração do Projeto, Desenvolvimento, implementação e teste de software, Análise Formal
 * [Nome do Aluno 2], Validação de dados e experimentos
 * [Nome do Aluno 3], Redação do manuscrito original, Validação de dados e experimentos
