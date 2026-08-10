"""
============================================================
SOMADOR FP13
Projeto Sistemas Digitais - UFABC
============================================================

FORMATO UTILIZADO

1 bit de sinal
4 bits de expoente
8 bits de fração

O valor representado é

    (-1)^s × (f / 256) × 2^e

onde

s = sinal
e = expoente
f = fração de 8 bits

------------------------------------------------------------

CONVENÇÃO ADOTADA PELO GRUPO

Como o formato possui apenas 8 bits para a fração,
nem todos os números podem ser representados exatamente.

A conversão utiliza:

✓ normalização
✓ truncamento dos bits excedentes
✓ sem arredondamento

A soma é realizada utilizando os valores já aproximados
para FP13, simulando os números que realmente estarão
representados na placa.

============================================================
"""

import math


def decimal_para_fp13(valor):

    if valor == 0:
        return {
            "sign": 0,
            "exp": 0,
            "frac": 0
        }

    sinal = 0

    if valor < 0:
        sinal = 1
        valor = abs(valor)

    expoente = math.floor(math.log2(valor)) + 1

    fracao = valor / (2 ** expoente)

    # Truncamento
    frac = int(fracao * 256)

    if frac > 255:
        frac = 255

    return {
        "sign": sinal,
        "exp": expoente,
        "frac": frac
    }


def fp13_para_decimal(sign, exp, frac):

    numero = (frac / 256.0) * (2 ** exp)

    if sign:
        numero *= -1

    return numero


def fp13_para_hex(fp):
    """
    Empacota os 13 bits no formato:

        S EEEE FFFFFFFF
        |  |      |
        |  |      +-- 8 bits de fração
        |  +--------- 4 bits de expoente
        +------------ 1 bit de sinal

    Resultado mostrado com 4 dígitos hexadecimais.
    """

    valor = (
        ((fp["sign"] & 0x1) << 12)
        | ((fp["exp"] & 0xF) << 8)
        | (fp["frac"] & 0xFF)
    )

    return valor


def mostrar_fp13(nome, original, fp):

    aproximado = fp13_para_decimal(
        fp["sign"],
        fp["exp"],
        fp["frac"]
    )

    print(f"\n----------- {nome} -----------")

    print(f"Decimal digitado   : {original}")
    print(f"Decimal aproximado : {aproximado}")
    print(f"Erro               : {original - aproximado}")

    print(f"\nSinal     : {fp['sign']}")
    print(f"Fração    : {fp['frac']:08b}")
    print(f"Expoente  : {fp['exp']:04b} ({fp['exp']})")

    print(f"Fração HEX   : {fp['frac']:02X}")
    print(f"Expoente HEX : {fp['exp']:X}")


def somar_fp13(numero1, numero2):

    # --------------------------------------------------
    # Converte os dois números digitados para FP13
    # --------------------------------------------------

    fp1 = decimal_para_fp13(numero1)
    fp2 = decimal_para_fp13(numero2)

    # Valores que realmente serão representados na placa
    aproximado1 = fp13_para_decimal(
        fp1["sign"],
        fp1["exp"],
        fp1["frac"]
    )

    aproximado2 = fp13_para_decimal(
        fp2["sign"],
        fp2["exp"],
        fp2["frac"]
    )

    # --------------------------------------------------
    # Soma utilizando os números JÁ APROXIMADOS
    # --------------------------------------------------

    soma_aproximada = aproximado1 + aproximado2

    # A saída também precisa caber em FP13
    fp_soma = decimal_para_fp13(soma_aproximada)

    resultado_final = fp13_para_decimal(
        fp_soma["sign"],
        fp_soma["exp"],
        fp_soma["frac"]
    )

    hex_final = fp13_para_hex(fp_soma)

    # --------------------------------------------------
    # Exibição
    # --------------------------------------------------

    print("\n==================================================")
    print("                  SOMADOR FP13")
    print("==================================================")

    mostrar_fp13("NÚMERO 1", numero1, fp1)
    mostrar_fp13("NÚMERO 2", numero2, fp2)

    print("\n==================================================")
    print("                    SOMA")
    print("==================================================")

    print(f"\nNúmero 1 aproximado : {aproximado1}")
    print(f"Número 2 aproximado : {aproximado2}")

    print(f"\nSoma dos aproximados: {soma_aproximada}")
    print(f"Resultado FP13      : {resultado_final}")

    print("\n----------- SAÍDA FP13 -----------")

    print(f"Sinal     : {fp_soma['sign']}")
    print(f"Expoente  : {fp_soma['exp']:04b} ({fp_soma['exp']})")
    print(f"Fração    : {fp_soma['frac']:08b}")

    print("\n----------- HEX -----------")

    print(f"Fração HEX   : {fp_soma['frac']:02X}")
    print(f"Expoente HEX : {fp_soma['exp']:X}")

    print(
        f"FP13 HEX     : 0x{hex_final:04X} "
        "(S EEEE FFFFFFFF)"
    )

    print("\n----------- PARA A DE10-LITE -----------")

    print("\n1) Carregar FRAÇÃO do resultado")
    print("SW9 SW8 = 00")
    print(f"SW7..0  = {fp_soma['frac']:08b}")
    print("Pressione KEY0")

    print("\n2) SINAL + EXPOENTE do resultado")
    print("SW9 SW8 = 01")
    print(f"SW4     = {fp_soma['sign']}")
    print(f"SW3..0  = {fp_soma['exp']:04b}")
    print("Pressione KEY0")

    print("\n==================================================")


# ==========================================================
# PROGRAMA PRINCIPAL
# ==========================================================

while True:

    entrada1 = input("\nDigite o primeiro número (q para sair): ")

    if entrada1.lower() == "q":
        break

    entrada2 = input("Digite o segundo número (q para sair): ")

    if entrada2.lower() == "q":
        break

    try:
        numero1 = float(entrada1)
        numero2 = float(entrada2)

        somar_fp13(numero1, numero2)

    except Exception as e:
        print("Erro:", e)