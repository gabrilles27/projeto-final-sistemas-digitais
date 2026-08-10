#===============================================================================
# capture_gtkwave.ps1 - abre o GTKWave com as formas de onda do projeto e salva
# um print da janela em docs/img/gtkwave_print.png.
#
# Torna o print das telas do simulador reproduzivel por comando, em vez de
# depender de uma captura manual.
#
# Uso (a partir da raiz do projeto):
#     pwsh scripts/capture_gtkwave.ps1
#     pwsh scripts/capture_gtkwave.ps1 -GtkwaveExe "C:\caminho\gtkwave.exe"
#
# O script abre uma janela no desktop por alguns segundos e a fecha em seguida.
# Mouse e teclado devem ficar livres durante a execucao.
#===============================================================================
param(
    [string]$GtkwaveExe = "",
    [string]$Ghw        = "sim/waves/fp_adder_waves.ghw",
    [string]$Gtkw       = "sim/waves/fp_adder_waves.gtkw",
    [string]$Tcl        = "sim/waves/zoom_fit.tcl",
    [string]$Out        = "docs/img/gtkwave_print.png",
    [int]   $Width      = 1600,
    [int]   $Height     = 950,
    [int]   $WaitSec    = 6
)
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# --- localiza o gtkwave -------------------------------------------------------
if (-not $GtkwaveExe) {
    $cands = @(
        $env:GTKWAVE_EXE,
        "C:\gtkwave\bin\gtkwave.exe",
        "C:\Program Files\gtkwave\bin\gtkwave.exe",
        "C:\msys64\mingw64\bin\gtkwave.exe"
    )
    $c = Get-Command gtkwave -ErrorAction SilentlyContinue
    if ($c) { $cands = @($c.Source) + $cands }
    foreach ($p in $cands) { if ($p -and (Test-Path $p)) { $GtkwaveExe = $p; break } }
}
if (-not $GtkwaveExe -or -not (Test-Path $GtkwaveExe)) {
    Write-Error @"
GTKWave nao encontrado.
Baixe o pacote standalone em https://github.com/gtkwave/gtkwave/releases
(gtkwave_gtk3_mingw64_standalone.tgz), extraia, e rode de novo passando
  -GtkwaveExe "<pasta>\bin\gtkwave.exe"
ou defina a variavel de ambiente GTKWAVE_EXE.
"@
    exit 1
}
if (-not (Test-Path $Ghw)) {
    Write-Error "Nao encontrado $Ghw. Rode antes: pwsh scripts/run_ghdl.ps1"
    exit 1
}
Write-Host "GTKWave : $GtkwaveExe"

# --- API do Windows para achar, posicionar e capturar a janela ----------------
if (-not ("Win32Cap" -as [type])) {
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32Cap {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after,
                                    int X, int Y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@
}
Add-Type -AssemblyName System.Drawing, System.Windows.Forms

$outDir = Split-Path -Parent $Out
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

# --- abre o GTKWave -----------------------------------------------------------
Write-Host "Abrindo $Ghw com o layout de $Gtkw ..."
$argv = @($Ghw, $Gtkw)
if ($Tcl -and (Test-Path $Tcl)) { $argv += @("-S", $Tcl) }   # aplica o zoom completo
$p = Start-Process -FilePath $GtkwaveExe -ArgumentList $argv -PassThru

try {
    # espera a janela existir e o GTK terminar de desenhar
    $h = [IntPtr]::Zero
    for ($i = 0; $i -lt ($WaitSec * 4); $i++) {
        Start-Sleep -Milliseconds 250
        $p.Refresh()
        if ($p.HasExited) { throw "O GTKWave fechou sozinho. Verifique se o .ghw e valido." }
        if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $h = $p.MainWindowHandle; break }
    }
    if ($h -eq [IntPtr]::Zero) { throw "A janela do GTKWave nao apareceu em $WaitSec s." }

    # O GTK3 costuma trocar a janela principal durante a inicializacao, entao o
    # primeiro handle pode ficar obsoleto. Reconsulta e so segue quando o
    # retangulo estabiliza num tamanho plausivel.
    $r = New-Object Win32Cap+RECT
    $w = 0; $ht = 0
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 400
        $p.Refresh()
        if ($p.HasExited) { throw "O GTKWave fechou sozinho." }
        if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $h = $p.MainWindowHandle }

        [void][Win32Cap]::ShowWindow($h, 9)          # SW_RESTORE
        [void][Win32Cap]::SetWindowPos($h, [IntPtr]::Zero, 0, 0, $Width, $Height, 0x0040)
        if ([Win32Cap]::GetWindowRect($h, [ref]$r)) {
            $w = $r.R - $r.L
            $ht = $r.B - $r.T
            if ($w -gt 300 -and $ht -gt 200) { break }
        }
    }
    if ($w -le 300 -or $ht -le 200) {
        throw "Nao foi possivel obter a janela do GTKWave (retangulo $w x $ht)."
    }
    Write-Host "Janela: $w x $ht"
    Start-Sleep -Seconds 3                            # deixa o GTK redesenhar

    # Captura via PrintWindow: le o conteudo direto do contexto da janela, entao
    # funciona mesmo se outra janela estiver por cima. O SetForegroundWindow nem
    # sempre e obedecido pelo Windows quando quem chama nao esta em primeiro
    # plano, e ai um CopyFromScreen capturaria a janela errada.
    $bmp = New-Object System.Drawing.Bitmap $w, $ht
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc()
    $okPw = [Win32Cap]::PrintWindow($h, $hdc, 2)   # 2 = PW_RENDERFULLCONTENT
    $g.ReleaseHdc($hdc)
    $g.Dispose()

    # Confere que a captura nao saiu em branco/preta (acontece com algumas
    # janelas aceleradas por GPU); nesse caso cai para a captura de tela.
    $distintas = @{}
    for ($x = 10; $x -lt $w; $x += 97) {
        for ($y = 10; $y -lt $ht; $y += 89) { $distintas[$bmp.GetPixel($x, $y).ToArgb()] = 1 }
    }
    if (-not $okPw -or $distintas.Count -lt 3) {
        Write-Host "PrintWindow nao rendeu conteudo; tentando captura de tela..." -ForegroundColor Yellow
        $bmp.Dispose()
        [void][Win32Cap]::SetForegroundWindow($h)
        Start-Sleep -Seconds 2
        $bmp = New-Object System.Drawing.Bitmap $w, $ht
        $g   = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size)
        $g.Dispose()
    }

    $abs = Join-Path (Get-Location).Path ($Out -replace '/','\')
    $bmp.Save($abs, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()

    Write-Host "Print salvo em $Out ($w x $ht, $($distintas.Count) cores distintas amostradas)" -ForegroundColor Green
}
finally {
    if ($p -and -not $p.HasExited) { $p.Kill(); $p.WaitForExit(3000) }
}
exit 0
