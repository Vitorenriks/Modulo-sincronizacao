# build.ps1 - compila o servidor em um .exe.
#
# Usa o csc que ja vem no Windows (.NET Framework 4). Nao precisa instalar
# Visual Studio, nem SDK, nem nada: e o compilador que esta em toda maquina
# Windows desde o 8. E por isso que o projeto todo continua em C# 5 e em
# WinForms classico - o dia em que precisar de SDK para gerar o executavel,
# a promessa de "copiar a pasta e pronto" acaba.
#
# O .exe sai SEM marca compilada: nome, organizacao e porta vem do
# marca.json ao lado dele. O icone e a unica coisa que tambem entra dentro
# do binario, porque o Windows le o icone do arquivo .exe direto do disco -
# o Explorer nao abre marca.json para desenhar a miniatura.
#
# Uso:
#    .\build.ps1
#    .\build.ps1 -Saida "saida\Meu App.exe" -Icone "C:\logos\empresa.png"
[CmdletBinding()]
param(
    [string]$Saida  = "saida\Servidor.exe",
    [string]$Icone  = "",
    [string]$Fonte  = "src\Servidor.cs",
    [switch]$Silencioso
)

$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $raiz 'ferramentas\Icone.ps1')

function Resolver([string]$p) {
    if ([System.IO.Path]::IsPathRooted($p)) { return $p }
    return (Join-Path $raiz $p)
}

$fonteAbs = Resolver $Fonte
$saidaAbs = Resolver $Saida
if (-not (Test-Path -LiteralPath $fonteAbs)) { throw "Não achei o fonte: $fonteAbs" }

$pastaSaida = Split-Path -Parent $saidaAbs
if ($pastaSaida -and -not (Test-Path -LiteralPath $pastaSaida)) {
    New-Item -ItemType Directory -Path $pastaSaida -Force | Out-Null
}

$csc = Get-ChildItem "$env:WINDIR\Microsoft.NET\Framework64\v4.*\csc.exe" -ErrorAction SilentlyContinue |
       Sort-Object FullName | Select-Object -Last 1
if (-not $csc) {
    $csc = Get-ChildItem "$env:WINDIR\Microsoft.NET\Framework\v4.*\csc.exe" -ErrorAction SilentlyContinue |
           Sort-Object FullName | Select-Object -Last 1
}
if (-not $csc) {
    throw "Não achei o csc.exe do .NET Framework 4. Ative o .NET Framework 3.5/4.x em 'Recursos do Windows'."
}

# O icone vira um .ico completo num arquivo temporario: assim o build aceita
# png/jpg direto e nunca embute um icone de um quadro so.
$icoTmp = Join-Path ([System.IO.Path]::GetTempPath()) ("marca-build-" + [Guid]::NewGuid().ToString('N') + ".ico")
$nomeParaIcone = [System.IO.Path]::GetFileNameWithoutExtension($saidaAbs)
$origemIcone = if ($Icone) { Resolver $Icone } else { "" }
$comoVeio = Resolve-IconeDaMarca -Origem $origemIcone -Destino $icoTmp -NomeDoProjeto $nomeParaIcone

try {
    $argumentos = @(
        '/nologo'
        '/target:winexe'          # sem janela de console atras do navegador
        '/platform:anycpu'
        '/optimize+'
        '/codepage:65001'         # o fonte e UTF-8 sem BOM; sem isso os acentos viram lixo
        '/warnaserror-'
        "/out:$saidaAbs"
        "/win32icon:$icoTmp"      # o icone que o Explorer e a barra de tarefas mostram
        "/resource:$icoTmp,marca.ico"   # a copia de reserva, lida se o .ico da pasta sumir
        '/reference:System.dll'
        '/reference:System.Drawing.dll'
        '/reference:System.Windows.Forms.dll'
        $fonteAbs
    )

    # Sem 2>&1: com ErrorActionPreference 'Stop', redirecionar a stderr de um
    # executavel nativo no PowerShell 5.1 vira excecao mesmo quando o csc
    # terminou bem. Quem decide aqui e o codigo de saida.
    $saidaCsc = & $csc.FullName @argumentos
    if ($LASTEXITCODE -ne 0) {
        $saidaCsc | ForEach-Object { Write-Host $_ }
        throw "A compilação falhou (csc devolveu $LASTEXITCODE)."
    }
    if (-not $Silencioso) {
        $kb = [int]((Get-Item -LiteralPath $saidaAbs).Length / 1024)
        Write-Host "  compilado: $saidaAbs  ($kb KB, ícone $comoVeio)"
    }
}
finally {
    Remove-Item -LiteralPath $icoTmp -Force -ErrorAction SilentlyContinue
}

# Quem chamou por script recebe o caminho; quem chamou no terminal ja viu a
# linha acima e nao quer o caminho repetido.
if ($Silencioso) { $saidaAbs }
