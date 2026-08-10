# render_waveform.ps1
#
# Le sim/waves/directed_cases.csv (gravado pelo proprio testbench
# tb_fp_adder_waves) e desenha um diagrama de tempo em SVG.
#
# O desenho NAO e ilustrativo: cada celula vem do valor amostrado na simulacao.
# Serve para o relatorio; para o "print de tela" do GTKWave use o .ghw junto
# com sim/waves/fp_adder_waves.gtkw.
#
# Uso:  pwsh scripts/render_waveform.ps1
#       (a partir da raiz do projeto)

param(
    [string]$Csv = "sim/waves/directed_cases.csv",
    [string]$Out = "docs/img/waveform_estagios.svg"
)

if (-not (Test-Path $Csv)) {
    Write-Error "Nao encontrado $Csv. Rode antes: scripts/run_ghdl.ps1"
    exit 1
}

$rows = Import-Csv -Path $Csv -Delimiter ';'
$n = $rows.Count

# ---------------------------------------------------------------- geometria
$labelW = 132
$colW   = 74
$rowH   = 25
$topH   = 66
$padB   = 34
$width  = $labelW + $colW * $n + 16
$secH   = 20

# Definicao das faixas: nome exibido, coluna do CSV, tipo (bit/bus), cor
$lanes = @(
    @{ sec = "Entradas (13 bits cada)" },
    @{ n = "sign1";    c = "s1";       t = "bit" },
    @{ n = "exp1";     c = "e1";       t = "bus" },
    @{ n = "frac1";    c = "f1";       t = "bus" },
    @{ n = "sign2";    c = "s2";       t = "bit" },
    @{ n = "exp2";     c = "e2";       t = "bus" },
    @{ n = "frac2";    c = "f2";       t = "bus" },
    @{ sec = "2o estagio - alinhamento" },
    @{ n = "exp_diff"; c = "exp_diff"; t = "bus" },
    @{ sec = "3o estagio - soma/subtracao" },
    @{ n = "sum";      c = "sum";      t = "bus" },
    @{ n = "carry_out";c = "carry";    t = "bit" },
    @{ sec = "4o estagio - normalizacao" },
    @{ n = "leado";    c = "leado";    t = "bus" },
    @{ n = "zero";     c = "zero";     t = "bit" },
    @{ n = "ovf (sat)";c = "ovf";      t = "bit" },
    @{ sec = "Saida do nucleo ORIGINAL (livro)" },
    @{ n = "sign_out"; c = "orig_s";   t = "bit" },
    @{ n = "exp_out";  c = "orig_e";   t = "bus" },
    @{ n = "frac_out"; c = "orig_f";   t = "bus" },
    @{ sec = "Saida do nucleo ADAPTADO (DE10-Lite)" },
    @{ n = "sign_out"; c = "new_s";    t = "bit" },
    @{ n = "exp_out";  c = "new_e";    t = "bus" },
    @{ n = "frac_out"; c = "new_f";    t = "bus" },
    @{ sec = "" },
    @{ n = "DIVERGEM";  c = "divergem"; t = "bit"; hl = $true }
)

# altura total
$h = $topH
foreach ($l in $lanes) { if ($l.ContainsKey("sec")) { $h += $secH } else { $h += $rowH } }
$height = $h + $padB

$sb = [System.Text.StringBuilder]::new()
function Add-Line($s) { [void]$sb.AppendLine($s) }

$esc = { param($t) $t -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' }

Add-Line "<svg xmlns='http://www.w3.org/2000/svg' width='$width' height='$height' viewBox='0 0 $width $height' font-family='DejaVu Sans Mono, Consolas, monospace'>"
Add-Line "<rect width='$width' height='$height' fill='#ffffff'/>"
Add-Line "<text x='10' y='20' font-size='13' font-weight='bold' fill='#111'>Somador de ponto flutuante 13 bits - $n casos dirigidos (100 ns por caso)</text>"
Add-Line "<text x='10' y='36' font-size='10' fill='#555'>Valores extraidos de sim/waves/directed_cases.csv, gravado pelo testbench tb_fp_adder_waves. Barramentos em hexadecimal, exceto sum e leado (decimal).</text>"

# ------------------------------------------------------------ cabecalho de casos
for ($i = 0; $i -lt $n; $i++) {
    $x = $labelW + $i * $colW
    $fill = if ($i % 2 -eq 0) { "#f7f8fa" } else { "#ffffff" }
    Add-Line "<rect x='$x' y='$topH' width='$colW' height='$($height - $topH - $padB)' fill='$fill'/>"
    $cx = $x + $colW / 2
    Add-Line "<text x='$cx' y='$($topH - 6)' font-size='11' font-weight='bold' text-anchor='middle' fill='#111'>C$i</text>"
}

# --------------------------------------------------------------------- faixas
$y = $topH
foreach ($lane in $lanes) {

    if ($lane.ContainsKey("sec")) {
        if ($lane.sec -ne "") {
            Add-Line "<rect x='0' y='$y' width='$width' height='$secH' fill='#eceff3'/>"
            $ty = $y + 14
            $t = & $esc $lane.sec
            Add-Line "<text x='8' y='$ty' font-size='10.5' font-weight='bold' fill='#2b3a4a'>$t</text>"
        }
        $y += $secH
        continue
    }

    $labY = $y + $rowH / 2 + 4
    $labFill = if ($lane.hl) { "#a3121b" } else { "#333" }
    $labWeight = if ($lane.hl) { "bold" } else { "normal" }
    Add-Line "<text x='$($labelW - 10)' y='$labY' font-size='11' text-anchor='end' fill='$labFill' font-weight='$labWeight'>$($lane.n)</text>"

    $vals = @($rows | ForEach-Object { $_.($lane.c) })

    if ($lane.t -eq "bit") {
        $yHi = $y + 5
        $yLo = $y + $rowH - 6
        $d = ""
        $prev = $null
        for ($i = 0; $i -lt $n; $i++) {
            $x0 = $labelW + $i * $colW
            $x1 = $x0 + $colW
            $yv = if ($vals[$i] -eq "1") { $yHi } else { $yLo }
            if ($null -eq $prev) { $d += "M $x0 $yv " } else { $d += "L $x0 $yv " }
            $d += "L $x1 $yv "
            $prev = $vals[$i]
        }
        $stroke = if ($lane.hl) { "#d1242f" } else { "#0969da" }
        $sw = if ($lane.hl) { "2.4" } else { "1.8" }
        Add-Line "<path d='$d' fill='none' stroke='$stroke' stroke-width='$sw'/>"
        # marca visual nos instantes em nivel alto
        for ($i = 0; $i -lt $n; $i++) {
            if ($vals[$i] -eq "1") {
                $cx = $labelW + $i * $colW + $colW / 2
                $ty = $y + $rowH / 2 + 3
                $col = if ($lane.hl) { "#d1242f" } else { "#0969da" }
                Add-Line "<text x='$cx' y='$($y + 4)' font-size='9' text-anchor='middle' fill='$col'>1</text>"
            }
        }
    }
    else {
        # barramento: celulas hexagonais, com fusao de valores iguais adjacentes
        $yT = $y + 4
        $yB = $y + $rowH - 5
        $yM = ($yT + $yB) / 2
        $i = 0
        while ($i -lt $n) {
            $j = $i
            while ($j + 1 -lt $n -and $vals[$j + 1] -eq $vals[$i]) { $j++ }
            $x0 = $labelW + $i * $colW
            $x1 = $labelW + ($j + 1) * $colW
            $k = 5
            $pts = "$($x0+$k),$yT $($x1-$k),$yT $x1,$yM $($x1-$k),$yB $($x0+$k),$yB $x0,$yM"
            Add-Line "<polygon points='$pts' fill='#eef4fb' stroke='#0969da' stroke-width='1.2'/>"
            $cx = ($x0 + $x1) / 2
            $ty = $yM + 4
            $txt = & $esc $vals[$i]
            Add-Line "<text x='$cx' y='$ty' font-size='11' text-anchor='middle' fill='#0b2b4a'>$txt</text>"
            $i = $j + 1
        }
    }

    Add-Line "<line x1='0' y1='$($y + $rowH)' x2='$width' y2='$($y + $rowH)' stroke='#e6e8eb' stroke-width='0.6'/>"
    $y += $rowH
}

# ------------------------------------------------------------------- rodape
Add-Line "<line x1='$labelW' y1='$topH' x2='$labelW' y2='$($height - $padB)' stroke='#c9ced6' stroke-width='1'/>"
for ($i = 0; $i -le $n; $i++) {
    $x = $labelW + $i * $colW
    Add-Line "<line x1='$x' y1='$topH' x2='$x' y2='$($height - $padB)' stroke='#dfe3e8' stroke-width='0.7'/>"
}

$legend = "C1 carry-out | C2 subtracao alinhada | C3 normalizacao de 7 casas | C4 resultado -> zero | C5 [D2] cancelamento exato | C6 [D3] estouro de expoente | C10 [D1] menos zero"
$ly = $height - 14
Add-Line "<text x='10' y='$ly' font-size='10' fill='#444'>$(& $esc $legend)</text>"
Add-Line "</svg>"

$dir = Split-Path -Parent $Out
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
[System.IO.File]::WriteAllText((Resolve-Path -LiteralPath "." ).Path + "\" + ($Out -replace '/','\'), $sb.ToString(), (New-Object System.Text.UTF8Encoding $false))
Write-Host "SVG gravado em $Out ($width x $height)"
