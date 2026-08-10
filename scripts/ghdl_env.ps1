# Localiza o GHDL e o coloca no PATH da sessao atual.
# GHDL_HOME tem precedencia, para instalacoes fora dos caminhos usuais.
$candidates = @(
    $env:GHDL_HOME,
    "C:\ghdl\bin",
    "C:\Program Files\ghdl\bin",
    "C:\msys64\mingw64\bin"
)
foreach ($c in $candidates) {
    if ($c -and (Test-Path (Join-Path $c "ghdl.exe"))) {
        $env:PATH = "$c;$env:PATH"
        break
    }
}
if (-not (Get-Command ghdl -ErrorAction SilentlyContinue)) {
    Write-Error "GHDL nao encontrado. Baixe ghdl-mcode-<versao>-mingw64.zip em https://github.com/ghdl/ghdl/releases e aponte GHDL_HOME para a pasta bin."
    exit 1
}
