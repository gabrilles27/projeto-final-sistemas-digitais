# render_board.ps1
#
# Le sim/waves/board_panel.csv (gravado pelo testbench tb_fp_adder_de10lite) e
# desenha o painel da DE10-Lite - os seis displays de 7 segmentos e os dez LEDs -
# exatamente como eles devem aparecer em cada caso de teste.
#
# O desenho nao e uma foto da placa: e o estado dos pinos de saida obtido na
# simulacao do nivel de topo, usado como gabarito na conferencia da placa real.
#
# Uso:  pwsh scripts/render_board.ps1

param(
    [string]$Csv = "sim/waves/board_panel.csv",
    [string]$Out = "docs/img/painel_esperado.svg"
)

if (-not (Test-Path $Csv)) {
    Write-Error "Nao encontrado $Csv. Rode antes: scripts/run_ghdl.ps1"
    exit 1
}

$rows = Import-Csv -Path $Csv -Delimiter ';'

# ------------------------------------------------------------------ geometria
$labelW = 340
$dw = 30; $dh = 52; $t = 6; $dgap = 12
$hexW = ($dw + $dgap) * 6 + 30
$ledR = 7; $ledGap = 22
$ledW = $ledGap * 10 + 20
$rowH = 78
$top  = 96
$width  = $labelW + $hexW + $ledW + 40
$height = $top + $rows.Count * $rowH + 30

$sb = [System.Text.StringBuilder]::new()
function A($s) { [void]$sb.AppendLine($s) }
function Esc($t) { $t -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' }

$ON  = "#ff3b30"; $OFF = "#40201f"
$LON = "#ff453a"; $LOFF = "#3a1d1c"

A "<svg xmlns='http://www.w3.org/2000/svg' width='$width' height='$height' viewBox='0 0 $width $height' font-family='DejaVu Sans Mono, Consolas, monospace'>"
A "<rect width='$width' height='$height' fill='#12161b'/>"
A "<text x='14' y='26' font-size='14' font-weight='bold' fill='#e6edf3'>DE10-Lite - painel esperado em cada caso de teste</text>"
A "<text x='14' y='44' font-size='10' fill='#9aa7b4'>Pinos HEX5..HEX0 e LEDR9..0 lidos na simulacao do topo. Gabarito - nao e foto.</text>"
A "<text x='14' y='59' font-size='10' fill='#9aa7b4'>Resultado: [sinal][frac alto][frac baixo .][exp] = s 0.FF x 2^E ; HEX1/HEX0 = eco.</text>"

# cabecalhos de coluna
$hx = $labelW
for ($i = 0; $i -lt 6; $i++) {
    $cx = $hx + $i * ($dw + $dgap) + $dw / 2
    $nome = "HEX$(5 - $i)"
    A "<text x='$cx' y='$($top - 10)' font-size='10' text-anchor='middle' fill='#7d8b99'>$nome</text>"
}
$lx = $labelW + $hexW
for ($i = 0; $i -lt 10; $i++) {
    $cx = $lx + $i * $ledGap + $ledR
    $nome = 9 - $i
    A "<text x='$cx' y='$($top - 10)' font-size='9' text-anchor='middle' fill='#7d8b99'>$nome</text>"
}
A "<text x='$($lx + $ledW / 2 - 10)' y='$($top - 28)' font-size='10' text-anchor='middle' fill='#7d8b99'>LEDR</text>"

# --------------------------------------------------- desenho de um digito
# $bits: string de 8 caracteres, MSB primeiro -> dp g f e d c b a ; '0' = aceso
function Digit($x, $y, $bits) {
    $dp = $bits[0]; $g = $bits[1]; $f = $bits[2]; $e = $bits[3]
    $d  = $bits[4]; $c = $bits[5]; $b = $bits[6]; $a = $bits[7]
    $col = { param($ch) if ($ch -eq '0') { $ON } else { $OFF } }
    $half = ($dh - $t) / 2
    # horizontais
    A "<rect x='$($x+$t)' y='$y' width='$($dw-2*$t)' height='$t' rx='2' fill='$(& $col $a)'/>"
    A "<rect x='$($x+$t)' y='$($y+$half)' width='$($dw-2*$t)' height='$t' rx='2' fill='$(& $col $g)'/>"
    A "<rect x='$($x+$t)' y='$($y+$dh-$t)' width='$($dw-2*$t)' height='$t' rx='2' fill='$(& $col $d)'/>"
    # verticais
    $vh = $half - $t
    A "<rect x='$x' y='$($y+$t)' width='$t' height='$vh' rx='2' fill='$(& $col $f)'/>"
    A "<rect x='$($x+$dw-$t)' y='$($y+$t)' width='$t' height='$vh' rx='2' fill='$(& $col $b)'/>"
    A "<rect x='$x' y='$($y+$half+$t)' width='$t' height='$vh' rx='2' fill='$(& $col $e)'/>"
    A "<rect x='$($x+$dw-$t)' y='$($y+$half+$t)' width='$t' height='$vh' rx='2' fill='$(& $col $c)'/>"
    # ponto decimal
    A "<circle cx='$($x+$dw+4)' cy='$($y+$dh-2)' r='2.6' fill='$(& $col $dp)'/>"
}

# --------------------------------------------------------------------- linhas
$y = $top
$idx = 0
foreach ($r in $rows) {

    if ($idx % 2 -eq 0) {
        A "<rect x='0' y='$y' width='$width' height='$rowH' fill='#171c22'/>"
    }

    # rotulo: nome curto + a conta em decimal
    $nome = ($r.nome -replace '\s+', ' ').Trim()
    $va = if ($r.opA -match '\(([^)]*)\)') { $matches[1] } else { "?" }
    $vb = if ($r.opB -match '\(([^)]*)\)') { $matches[1] } else { "?" }
    $vr = if ($r.resultado -match '\(([^)]*)\)') { $matches[1] } else { "?" }
    A "<text x='14' y='$($y + 24)' font-size='11' fill='#e6edf3'>$(Esc $nome)</text>"
    A "<text x='14' y='$($y + 42)' font-size='10.5' fill='#8fa3b8'>$(Esc "$va  +  $vb  =  $vr")</text>"
    $ha = $r.opA -replace ' \(.*', ''
    $hb = $r.opB -replace ' \(.*', ''
    $hexTxt = "A: " + $ha + "   B: " + $hb
    A "<text x='14' y='$($y + 59)' font-size='9.5' fill='#6b7c8d'>$(Esc $hexTxt)</text>"

    # displays HEX5..HEX0
    $order = @($r.HEX5, $r.HEX4, $r.HEX3, $r.HEX2, $r.HEX1, $r.HEX0)
    for ($i = 0; $i -lt 6; $i++) {
        $x = $labelW + $i * ($dw + $dgap)
        Digit $x ($y + 12) $order[$i]
    }
    # separador visual entre o resultado (HEX5..HEX2) e o eco (HEX1..HEX0)
    $sepX = $labelW + 4 * ($dw + $dgap) - 6
    A "<line x1='$sepX' y1='$($y+10)' x2='$sepX' y2='$($y+$rowH-8)' stroke='#2c3742' stroke-width='1'/>"

    # LEDs
    $bitsL = $r.LEDR
    for ($i = 0; $i -lt 10; $i++) {
        $cx = $labelW + $hexW + $i * $ledGap + $ledR
        $cy = $y + 34
        $fill = if ($bitsL[$i] -eq '1') { $LON } else { $LOFF }
        A "<circle cx='$cx' cy='$cy' r='$ledR' fill='$fill' stroke='#0d1117' stroke-width='1'/>"
    }

    A "<line x1='0' y1='$($y + $rowH)' x2='$width' y2='$($y + $rowH)' stroke='#232a31' stroke-width='1'/>"
    $y += $rowH
    $idx++
}

A "<text x='14' y='$($height - 10)' font-size='9.5' fill='#7d8b99'>LEDR(3..0)=exp_diff | LEDR(6..4)=leado | LEDR(7)=carry-out | LEDR(8)=resultado nulo | LEDR(9)=saturacao</text>"
A "</svg>"

$dir = Split-Path -Parent $Out
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
$abs = Join-Path (Get-Location).Path ($Out -replace '/','\')
[System.IO.File]::WriteAllText($abs, $sb.ToString(), (New-Object System.Text.UTF8Encoding $false))
Write-Host "SVG gravado em $Out ($width x $height)"
