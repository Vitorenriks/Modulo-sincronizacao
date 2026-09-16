# novo-projeto.ps1 - monta uma pasta pronta para entregar a um cliente.
#
# O resultado e uma pasta que a pessoa copia para o OneDrive / SharePoint /
# rede e compartilha com o time. Dentro dela:
#
#    <Nome>.exe      o servidor, com o icone da empresa
#    marca.json      nome, organizacao, porta e prefixo dos dados
#    marca.ico       o icone, tambem solto, para trocar sem recompilar
#    _app\           a aplicacao em si (HTML/CSS/JS) - e o que se edita
#    dados\          vazio; enche sozinho conforme as pessoas usam
#    LEIA-ME.txt     instrucoes para quem vai usar, nao para quem programa
#
# Uso:
#    .\novo-projeto.ps1 -Nome "Painel da Qualidade"
#    .\novo-projeto.ps1 -Nome "Ordens de Servico" -Organizacao "ACME" `
#                       -Icone "C:\logos\acme.png" -Destino "C:\Entregas"
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Nome,
    [string]$Organizacao = "",
    [string]$Icone = "",
    [string]$Destino = "",
    [string]$Prefixo = "",
    [int]$Porta = 0,
    [switch]$Forcar
)

$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $raiz 'ferramentas\Icone.ps1')

# Mesma limpeza que o servidor faz em C#: o prefixo do marca.json e o nome
# que o servidor deriva do usuario precisam sair iguais dos dois lados, senao
# o log de uma pessoa nao casa com o padrao de busca da outra.
function Limpar([string]$s) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($c in $s.ToLowerInvariant().ToCharArray()) {
        if ([char]::IsLetterOrDigit($c) -and [int]$c -lt 128) { [void]$sb.Append($c) }
        elseif ($c -eq ' ' -or $c -eq '.' -or $c -eq '_' -or $c -eq '-') { [void]$sb.Append('-') }
    }
    $limpo = $sb.ToString().Trim('-')
    if (-not $limpo) { return 'app' }
    return $limpo
}

# Nome de arquivo do .exe: mantem acentos e espacos (e o que a pessoa ve no
# Explorer), tira so o que o Windows recusa.
function NomeDeArquivo([string]$s) {
    $limpo = $s
    foreach ($c in [System.IO.Path]::GetInvalidFileNameChars()) {
        $limpo = $limpo.Replace([string]$c, '')
    }
    $limpo = $limpo.Trim().Trim('.')
    if (-not $limpo) { return 'Servidor' }
    return $limpo
}

$apelido = Limpar $Nome
if (-not $Prefixo) { $Prefixo = $apelido }
$Prefixo = Limpar $Prefixo

# Porta derivada do nome: dois projetos diferentes na mesma maquina abrem em
# faixas diferentes e nao ficam se empurrando na hora de achar porta livre.
# Nao e obrigatorio acertar - o servidor procura a proxima livre de qualquer
# jeito - mas evita que todo mundo comece em 8850.
if ($Porta -le 0) {
    $soma = 0
    foreach ($c in $apelido.ToCharArray()) { $soma = ($soma * 31 + [int]$c) % 100 }
    $Porta = 8800 + ($soma % 60) * 10
}

if (-not $Destino) { $Destino = Join-Path $raiz 'projetos' }
if (-not [System.IO.Path]::IsPathRooted($Destino)) { $Destino = Join-Path $raiz $Destino }

$nomeArquivo = NomeDeArquivo $Nome
$pasta = Join-Path $Destino $nomeArquivo

if (Test-Path -LiteralPath $pasta) {
    # Recriar por cima apagaria dados\ de um projeto que ja esta em uso. So
    # com -Forcar, e mesmo assim dados\ e _app\ ficam onde estao.
    if (-not $Forcar) {
        throw "Já existe: $pasta`nUse -Forcar para regravar o executável e a marca (dados\ e _app\ são preservados)."
    }
}

Write-Host ""
Write-Host "  Projeto:      $Nome"
if ($Organizacao) { Write-Host "  Organização:  $Organizacao" }
Write-Host "  Pasta:        $pasta"
Write-Host "  Porta base:   $Porta"
Write-Host "  Dados:        dados\$Prefixo.<usuario>@<maquina>.jsonl"
Write-Host ""

New-Item -ItemType Directory -Path $pasta -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $pasta 'dados') -Force | Out-Null

# o icone
$icoDestino = Join-Path $pasta 'marca.ico'
$origemIcone = if ($Icone) { if ([System.IO.Path]::IsPathRooted($Icone)) { $Icone } else { Join-Path $raiz $Icone } } else { "" }
$comoVeio = Resolve-IconeDaMarca -Origem $origemIcone -Destino $icoDestino -NomeDoProjeto $Nome
Write-Host "  ícone:        marca.ico ($comoVeio)"

# o executavel
$exe = Join-Path $pasta ($nomeArquivo + '.exe')
& (Join-Path $raiz 'build.ps1') -Saida $exe -Icone $icoDestino -Silencioso | Out-Null
Write-Host "  executável:   $nomeArquivo.exe"

# a marca
function Escapar([string]$s) { return $s.Replace('\', '\\').Replace('"', '\"') }

$marca = @"
{
  "nome": "$(Escapar $Nome)",
  "organizacao": "$(Escapar $Organizacao)",
  "icone": "marca.ico",
  "prefixo": "$Prefixo",
  "porta": $Porta,
  "faixaPortas": 40
}
"@
# Sem BOM: o leitor do marca.json e um scanner simples e o BOM entraria como
# primeiro caractere da primeira chave.
[System.IO.File]::WriteAllText((Join-Path $pasta 'marca.json'), $marca, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  marca:        marca.json"

# a aplicacao
$destinoApp = Join-Path $pasta '_app'
if (Test-Path -LiteralPath $destinoApp) {
    Write-Host "  aplicação:    _app\ já existia, mantida como está"
} else {
    Copy-Item -LiteralPath (Join-Path $raiz 'modelo\_app') -Destination $destinoApp -Recurse -Force
    Write-Host "  aplicação:    _app\ (modelo de exemplo — troque pelo seu)"
}

# os textos para quem vai usar. Mesmos marcadores nos dois; sem BOM, para nao
# aparecer um caractere estranho na primeira linha de quem abre no Notepad.
function Render([string]$modelo, [string]$destino) {
    $t = (Get-Content -LiteralPath (Join-Path $raiz $modelo) -Raw -Encoding UTF8).
            Replace('{{NOME}}', $Nome).
            Replace('{{EXE}}', $nomeArquivo + '.exe').
            Replace('{{ORGANIZACAO}}', $(if ($Organizacao) { $Organizacao } else { 'sua equipe' }))
    [System.IO.File]::WriteAllText((Join-Path $pasta $destino), $t, (New-Object System.Text.UTF8Encoding($false)))
}

Render 'modelo\LEIA-ME.txt' 'LEIA-ME.txt'
Write-Host "  instruções:   LEIA-ME.txt"

Render 'modelo\PASSO-A-PASSO.txt' 'PASSO-A-PASSO.txt'
Write-Host "  primeira vez: PASSO-A-PASSO.txt"

# o suporte. Fica numa subpasta para nao competir com o que o usuario final
# precisa ver na raiz - e porque quem vai abrir isto so abre quando algo deu
# errado, com alguem do outro lado pedindo. O servidor ignora a pasta: ele
# so serve o que esta em _app.
$suporte = Join-Path $pasta '_suporte'
New-Item -ItemType Directory -Path $suporte -Force | Out-Null
foreach ($f in @('Diagnostico.ps1', 'Diagnostico.cmd', 'Diagnostico-corrigir.cmd')) {
    Copy-Item -LiteralPath (Join-Path $raiz "ferramentas\$f") -Destination $suporte -Force
}
Write-Host "  suporte:      _suporte\Diagnostico.cmd"

Write-Host ""
Write-Host "  Pronto. Próximos passos:"
Write-Host "    1. edite _app\ até a aplicação fazer o que precisa;"
Write-Host "    2. copie a pasta inteira para o OneDrive/SharePoint/rede;"
Write-Host "    3. compartilhe com o time e peça duplo clique em $nomeArquivo.exe."
Write-Host ""
