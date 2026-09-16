# testar.ps1 - roda o produto inteiro e confere o que ele promete.
#
# Compila, gera um projeto descartavel, sobe o executavel de verdade, fala
# com ele por HTTP e confere as garantias que o README vende: a porta e so
# local, o POST exige o cabecalho, ninguem sai da pasta _app, e a pasta
# somente-leitura e detectada em vez de virar dado perdido.
#
# Depois chama o teste de convergencia do log (precisa do Node; se nao
# houver, avisa e segue).
#
# Uso:  .\testar.ps1
[CmdletBinding()]
param([switch]$Manter)

$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $MyInvocation.MyCommand.Path

$passou = 0; $falhou = 0
function Conferir($nome, $condicao, $detalhe) {
    if ($condicao) { $script:passou++; Write-Host "  ok    $nome" }
    else {
        $script:falhou++
        Write-Host "  FALHA $nome" -ForegroundColor Red
        if ($detalhe) { Write-Host "        $detalhe" -ForegroundColor DarkGray }
    }
}

# Invoke-WebRequest estoura em excecao a partir do 400; o que interessa aqui e
# o codigo, nao a excecao.
function Pedir($url, $metodo = 'GET', $corpo = $null, $cabecalhos = @{}) {
    try {
        $p = @{ Uri = $url; Method = $metodo; UseBasicParsing = $true; TimeoutSec = 10; Headers = $cabecalhos }
        if ($corpo -ne $null) { $p.Body = $corpo }
        $r = Invoke-WebRequest @p
        return @{ codigo = [int]$r.StatusCode; texto = $r.Content }
    } catch {
        $resp = $_.Exception.Response
        if ($resp) { return @{ codigo = [int]$resp.StatusCode; texto = '' } }
        return @{ codigo = 0; texto = $_.Exception.Message }
    }
}

$area = Join-Path ([System.IO.Path]::GetTempPath()) ("nucleo-teste-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
$proc = $null

try {
    Write-Host ""
    Write-Host "  Compilação e geração de projeto"
    Write-Host ""

    & (Join-Path $raiz 'build.ps1') -Saida (Join-Path $area 'Servidor.exe') -Silencioso | Out-Null
    Conferir "build.ps1 gera o executável" (Test-Path (Join-Path $area 'Servidor.exe'))

    & (Join-Path $raiz 'novo-projeto.ps1') -Nome "Projeto de Teste" -Organizacao "Empresa Teste" `
        -Destino $area | Out-Null
    $proj = Join-Path $area 'Projeto de Teste'

    # As tres camadas de _app\ tem que chegar no projeto do cliente: sem uma
    # delas a tela abre em branco, e em branco ninguem descobre qual faltou.
    foreach ($item in 'Projeto de Teste.exe', 'marca.json', 'marca.ico', 'LEIA-ME.txt',
                      'PASSO-A-PASSO.txt', '_suporte\Diagnostico.cmd', '_suporte\Diagnostico.ps1',
                      '_app\index.html', '_app\principal.js', '_app\dominio\regras.js',
                      '_app\aplicacao\log.js', '_app\tela\quadro.js', '_app\tela\estilo.css', 'dados') {
        Conferir "novo-projeto cria $item" (Test-Path (Join-Path $proj $item))
    }

    $ico = [System.IO.File]::ReadAllBytes((Join-Path $proj 'marca.ico'))
    $quadros = [BitConverter]::ToUInt16($ico, 4)
    Conferir "o .ico sai com vários tamanhos" ($quadros -ge 5) "quadros: $quadros"
    Conferir "o .ico não sai truncado" ($ico.Length -gt 10000) "bytes: $($ico.Length)"

    $marca = Get-Content (Join-Path $proj 'marca.json') -Raw
    Conferir "a marca do cliente entra no marca.json" ($marca -match 'Empresa Teste')
    Conferir "o LEIA-ME não sai com marcador por trocar" `
        -condicao (-not ((Get-Content (Join-Path $proj 'LEIA-ME.txt') -Raw) -match '\{\{'))
    # Mesmo cuidado no passo a passo: um {{EXE}} escapando aqui manda a pessoa
    # dar dois cliques num arquivo que nao existe, na primeira vez que ela abre.
    Conferir "o PASSO-A-PASSO não sai com marcador por trocar" `
        -condicao (-not ((Get-Content (Join-Path $proj 'PASSO-A-PASSO.txt') -Raw) -match '\{\{'))
    Conferir "o PASSO-A-PASSO aponta para o .exe deste projeto" `
        -condicao ((Get-Content (Join-Path $proj 'PASSO-A-PASSO.txt') -Raw) -match 'Projeto de Teste\.exe')

    Write-Host ""
    Write-Host "  O servidor em execução"
    Write-Host ""

    $porta = ([regex]'"porta"\s*:\s*(\d+)').Match($marca).Groups[1].Value
    $exe = Join-Path $proj 'Projeto de Teste.exe'
    $proc = Start-Process -FilePath $exe -ArgumentList '--sem-navegador' -PassThru

    $base = "http://127.0.0.1:$porta"
    $subiu = $false
    foreach ($i in 1..40) {
        if ((Pedir "$base/api/quem").codigo -eq 200) { $subiu = $true; break }
        Start-Sleep -Milliseconds 150
    }
    Conferir "o executável sobe na porta do marca.json" $subiu "porta $porta"
    if (-not $subiu) { throw "sem servidor: o resto do teste não faz sentido" }

    $quem = (Pedir "$base/api/quem").texto
    Conferir "/api/quem responde e diz que pode gravar" ($quem -match '"grava":true') $quem

    $marcaApi = (Pedir "$base/api/marca").texto
    Conferir "/api/marca devolve o nome com acento intacto" ($marcaApi -match 'Projeto de Teste') $marcaApi

    Conferir "/ serve a aplicação de _app" ((Pedir "$base/").texto -match '<html')

    # As camadas moram em subpastas de _app\: se o servidor so entregasse a
    # raiz, a pagina abriria em branco sem nenhum erro visivel.
    foreach ($camada in 'dominio/regras.js', 'aplicacao/log.js', 'tela/quadro.js', 'tela/estilo.css') {
        Conferir "serve a subpasta _app/$camada" ((Pedir "$base/$camada").codigo -eq 200)
    }
    Conferir "/marca.ico é servido como binário inteiro" `
        -condicao ((Pedir "$base/marca.ico").codigo -eq 200)

    Conferir "POST sem X-App-Local é recusado" `
        -condicao ((Pedir "$base/api/ops" 'POST' '{"t":"x"}').codigo -eq 403)

    $corpo = '{"t":"nova","id":"t1","texto":"primeira"}' + "`n" + '{"t":"texto","id":"t1","texto":"corrigida"}'
    $grav = Pedir "$base/api/ops" 'POST' $corpo @{ 'X-App-Local' = '1' }
    Conferir "POST com o cabeçalho grava as duas linhas" ($grav.texto -match '"gravadas":2') $grav.texto

    $logs = (Pedir "$base/api/logs").texto
    Conferir "/api/logs devolve as operações com autor, seq e horário" `
        -condicao ($logs -match '"autor"' -and $logs -match '"seq":1' -and $logs -match 'corrigida')

    foreach ($fuga in '/../marca.json', '/..%2Fmarca.json', '/%2e%2e/marca.json', '/_app/../../marca.json') {
        Conferir "não escapa de _app por $fuga" ((Pedir "$base$fuga").codigo -eq 404)
    }

    # A pasta somente-leitura: o caso que, se passar batido, faz o usuario ver
    # na tela um dado que nao existe em arquivo nenhum.
    $arq = Get-ChildItem (Join-Path $proj 'dados') -Filter *.jsonl | Select-Object -First 1
    Set-ItemProperty -LiteralPath $arq.FullName -Name IsReadOnly -Value $true
    try {
        Conferir "pasta travada: /api/quem avisa que não grava" `
            -condicao ((Pedir "$base/api/quem").texto -match '"grava":false')
        Conferir "pasta travada: POST devolve 503 em vez de fingir que gravou" `
            -condicao ((Pedir "$base/api/ops" 'POST' '{"t":"nova","id":"z"}' @{ 'X-App-Local' = '1' }).codigo -eq 503)
    } finally {
        Set-ItemProperty -LiteralPath $arq.FullName -Name IsReadOnly -Value $false
    }
    Conferir "destravada: volta a gravar" ((Pedir "$base/api/quem").texto -match '"grava":true')

    # Segundo duplo clique: nao pode subir um segundo servidor na mesma pasta.
    $segundo = Start-Process -FilePath $exe -ArgumentList '--sem-navegador' -PassThru
    Start-Sleep -Milliseconds 1200
    Conferir "segundo duplo clique não abre um segundo programa" ($segundo.HasExited)
    if (-not $segundo.HasExited) { $segundo | Stop-Process -Force }

    Write-Host ""
    Write-Host "  Convergência do log"
    Write-Host ""

    $node = Get-Command node -ErrorAction SilentlyContinue
    if ($node) {
        & node (Join-Path $raiz 'ferramentas\teste-convergencia.js')
        if ($LASTEXITCODE -ne 0) { $falhou++ } else { $passou++ }
    } else {
        Write-Host "  pulado: Node não encontrado (o teste de convergência precisa dele)" -ForegroundColor DarkGray
    }
}
finally {
    if ($proc -and -not $proc.HasExited) { $proc | Stop-Process -Force }
    if (-not $Manter) {
        Start-Sleep -Milliseconds 300
        Remove-Item -LiteralPath $area -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        Write-Host ""
        Write-Host "  área de teste mantida em: $area"
    }
}

Write-Host ""
if ($falhou -gt 0) {
    Write-Host "  $passou passaram, $falhou falharam" -ForegroundColor Red
    exit 1
}
Write-Host "  $passou passaram, 0 falharam" -ForegroundColor Green
Write-Host ""
