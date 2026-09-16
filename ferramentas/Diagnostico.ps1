# Diagnostico.ps1 - descobre por que a ferramenta nao abriu na maquina de alguem.
#
# Vai junto com o Diagnostico.cmd para DENTRO da pasta entregue, e a pessoa da
# dois cliques no .cmd. Nao instala nada, nao precisa de administrador e nao
# altera nada - a unica excecao e desbloquear o .exe, e so quando -Corrigir
# e pedido.
#
# Texto sem acento de proposito: isto roda numa janela de console de maquina
# desconhecida, onde a pagina de codigo pode ser 437, 850 ou 65001. Acento
# ali vira lixo e assusta quem esta lendo. O portugues com acento fica no
# PASSO-A-PASSO.txt, que e lido em editor de texto.
#
# A ordem das verificacoes nao e arbitraria: vai do que mais quebra na pratica
# (pasta errada, arquivo bloqueado, sincronizacao pela metade) para o que quase
# nunca quebra (porta, navegador). A ultima sobe o executavel de verdade e
# conversa com ele: se essa passar, a ferramenta funciona naquela maquina e o
# problema esta em como a pessoa estava abrindo.
#
# Uso:
#    .\Diagnostico.ps1
#    .\Diagnostico.ps1 -Corrigir        # desbloqueia o .exe, se estiver bloqueado
[CmdletBinding()]
param(
    [string]$Pasta = "",
    [switch]$Corrigir
)

$ErrorActionPreference = 'Continue'

# Onde olhar. O diagnostico e entregue em _suporte\, dentro da pasta da
# ferramenta, para nao poluir o que o usuario final ve - entao se nao houver
# .exe ao lado dele, a pasta que interessa e a de cima.
if (-not $Pasta) {
    $aqui = Split-Path -Parent $MyInvocation.MyCommand.Path
    $Pasta = $aqui
    if (@(Get-ChildItem -LiteralPath $aqui -Filter *.exe -File -ErrorAction SilentlyContinue).Count -eq 0) {
        $pai = Split-Path -Parent $aqui
        if ($pai -and @(Get-ChildItem -LiteralPath $pai -Filter *.exe -File -ErrorAction SilentlyContinue).Count -gt 0) {
            $Pasta = $pai
        }
    }
}

$linhas = New-Object System.Collections.ArrayList
$problemas = New-Object System.Collections.ArrayList

function Diga([string]$texto) {
    Write-Host $texto
    [void]$linhas.Add($texto)
}
function Secao([string]$t) { Diga ""; Diga $t; Diga ("-" * 64) }
function Ok([string]$t)    { Diga "  [ ok ]   $t" }
function Aviso([string]$t) { Diga "  [aviso]  $t" }
function Falha([string]$t, [string]$comoResolver) {
    Diga "  [FALHA]  $t"
    [void]$problemas.Add(@{ o = $t; como = $comoResolver })
}

Diga ""
Diga "================================================================"
Diga " Diagnostico da ferramenta"
Diga " $(Get-Date -Format 'dd/MM/yyyy HH:mm')"
Diga "================================================================"

# ----------------------------------------------------------------- a maquina
Secao "1. A maquina"

$os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
Diga "  Windows:    $($os.Caption) ($([Environment]::OSVersion.Version))"
Diga "  Maquina:    $env:COMPUTERNAME"
Diga "  Usuario:    $env:USERNAME"
Diga "  PowerShell: $($PSVersionTable.PSVersion)"

$v = [Environment]::OSVersion.Version
if ($v.Major -lt 6 -or ($v.Major -eq 6 -and $v.Minor -lt 2)) {
    Falha "Windows anterior ao 8." "A ferramenta precisa de Windows 8 ou mais novo."
} else {
    Ok "Versao do Windows suportada."
}

# O .exe e .NET Framework 4. Windows 8 ja vem com 4.5, o 10 e o 11 com 4.8 -
# entao essa chave so falta em instalacao muito mexida. Mas quando falta, o
# sintoma e exatamente o que se relata: dois cliques e nada acontece.
$rel = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -Name Release -ErrorAction SilentlyContinue).Release
if ($rel) {
    Ok ".NET Framework 4 presente (release $rel)."
} else {
    Falha "Nao achei o .NET Framework 4 nesta maquina." "Painel de Controle > Programas > Ativar ou desativar recursos do Windows > marcar '.NET Framework 4.x'."
}

# ------------------------------------------------------------------- a pasta
Secao "2. Onde a pasta esta"

Diga "  Pasta: $Pasta"
Diga "  Tamanho do caminho: $($Pasta.Length) caracteres"
if ($Pasta.Length -gt 200) {
    Aviso "Caminho muito longo. Tao fundo assim, o Windows pode recusar arquivos dentro da pasta."
}

# As pastas de sincronizacao desta maquina, por conta. Le todas as contas
# configuradas, e nao so a variavel de ambiente, porque quem tem conta pessoal
# e do trabalho ao mesmo tempo tem duas raizes diferentes.
$raizes = New-Object System.Collections.ArrayList
foreach ($r in @($env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial)) {
    if ($r -and -not $raizes.Contains($r)) { [void]$raizes.Add($r) }
}
foreach ($c in (Get-ChildItem "HKCU:\SOFTWARE\Microsoft\OneDrive\Accounts" -ErrorAction SilentlyContinue)) {
    $uf = (Get-ItemProperty $c.PSPath -Name UserFolder -ErrorAction SilentlyContinue).UserFolder
    if ($uf -and -not $raizes.Contains($uf)) { [void]$raizes.Add($uf) }
}

if ($raizes.Count -eq 0) {
    Aviso "Nao achei nenhuma pasta do OneDrive configurada nesta maquina."
} else {
    foreach ($r in $raizes) { Diga "  Sincronizacao configurada: $r" }
}

$dentroDeSync = $false
foreach ($r in $raizes) {
    if ($Pasta.ToLower().StartsWith($r.ToLower())) { $dentroDeSync = $true }
}

$temp = [System.IO.Path]::GetTempPath()
$baixados = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'
$pb = $Pasta.ToLower()

# Compara por TRECHO, e nao so pelo comeco: o caminho pode chegar aqui com o
# nome curto do Windows (VITORC~1 em vez de "Vitor Cunha"), e a comparacao
# direta com o caminho do temp falharia calada - justamente no caso que mais
# interessa pegar.
$noTemp = $pb.StartsWith($temp.ToLower()) -or ($pb -like '*\appdata\local\temp\*')
# O Explorer abre .zip numa pasta chamada Temp1_<nome>.zip; o WinRAR usa Rar$.
$noZip = ($pb -match '\\temp\d+_') -or ($pb -like '*rar$*') -or ($pb -like '*.zip\*')

if ($noZip) {
    # Campeao de "nao abriu": dois cliques no .zip abrem uma janela que PARECE
    # uma pasta, mas e o zip aberto por cima. O .exe nao acha o _app, ou roda e
    # grava num lugar que desaparece no proximo reinicio.
    Falha "Isto e um .zip aberto por cima, nao uma pasta de verdade." "Feche esta janela. Clique no .zip com o botao direito > 'Extrair tudo' e abra de onde extraiu. Melhor ainda: abra a pasta compartilhada, sem .zip."
} elseif ($noTemp) {
    Falha "A pasta esta na area temporaria do Windows." "Este lugar e apagado pelo Windows sem avisar. Mova a pasta para um lugar de verdade, ou melhor: abra a pasta compartilhada pelo Explorer."
} elseif ($pb.StartsWith($baixados.ToLower())) {
    Falha "A pasta esta em Downloads - e uma copia baixada, solta nesta maquina." "Abre e funciona, mas so para voce: nada do que fizer aqui chega ao time. Apague esta copia e abra a pasta compartilhada pelo Explorer."
} elseif ($Pasta.StartsWith("\\")) {
    Ok "A pasta esta numa unidade de rede."
} elseif ($dentroDeSync) {
    Ok "A pasta esta dentro de uma pasta sincronizada - e o lugar certo."
} else {
    Aviso "A pasta nao esta no OneDrive nem em unidade de rede. A ferramenta abre, mas so esta maquina vera os dados."
}

# ------------------------------------------------------- conteudo obrigatorio
Secao "3. O que tem na pasta"

$exes = @(Get-ChildItem -LiteralPath $Pasta -Filter *.exe -File -ErrorAction SilentlyContinue)
$exe = $null
if ($exes.Count -eq 0) {
    Falha "Nao existe nenhum .exe nesta pasta." "A sincronizacao nao terminou, ou o antivirus removeu o arquivo. Confira pelo site do OneDrive se o .exe esta la e espere a sincronizacao acabar."
} else {
    $exe = $exes[0]
    if ($exes.Count -gt 1) { Aviso "Ha mais de um .exe aqui; testando '$($exe.Name)'." }
    Diga "  Executavel: $($exe.Name)  ($([int]($exe.Length / 1024)) KB)"

    if ($exe.Length -eq 0) {
        Falha "O .exe esta com 0 byte." "O arquivo nao baixou de verdade. Botao direito nele > 'Sempre manter neste dispositivo'."
    } else {
        # Um .exe de verdade comeca com 'MZ'. Antivirus que "limpa" o arquivo e
        # sincronizacao interrompida deixam um arquivo do tamanho certo com
        # conteudo errado - e o duplo clique nao faz nada, sem mensagem nenhuma.
        $mz = $null
        try {
            $fs = [System.IO.File]::OpenRead($exe.FullName)
            $b = New-Object byte[] 2
            [void]$fs.Read($b, 0, 2)
            $fs.Close()
            $mz = [string][char]$b[0] + [string][char]$b[1]
        } catch {
            Falha "Nao consegui nem ler o .exe: $($_.Exception.Message)" "Antivirus em cima do arquivo, ou sincronizacao em andamento."
        }
        if ($mz -and $mz -ne "MZ") {
            Falha "O .exe nao e um programa valido (comeca com '$mz', deveria ser 'MZ')." "Chegou corrompido ou foi alterado pelo antivirus. Peca o arquivo de novo a quem entregou a pasta."
        } elseif ($mz -eq "MZ") {
            Ok "O .exe e um programa valido."
        }
    }
}

# O _app. Nao da para exigir uma lista de arquivos: cada ferramenta tem a sua
# aplicacao, e uma entrega de cliente nao se parece nada com o modelo de
# exemplo. O que TODA aplicacao tem, porque e o que o servidor serve na raiz,
# e o index.html - e e exatamente ele que falta quando a sincronizacao para no
# meio ou quando alguem copiou so o .exe.
$pastaApp = Join-Path $Pasta '_app'
if (-not (Test-Path -LiteralPath $pastaApp)) {
    Falha "Nao existe a pasta _app aqui." "O .exe foi copiado sozinho, sem a pasta. Copie a PASTA INTEIRA, ou volte a abrir a pasta compartilhada original."
} else {
    $arquivosApp = @(Get-ChildItem -LiteralPath $pastaApp -Recurse -File -ErrorAction SilentlyContinue)
    if (-not (Test-Path -LiteralPath (Join-Path $pastaApp 'index.html'))) {
        Falha "A pasta _app existe, mas nao tem index.html." "A sincronizacao nao terminou de baixar a pasta. Espere o icone do OneDrive ficar verde, ou botao direito na pasta > 'Sempre manter neste dispositivo'."
    } elseif ($arquivosApp.Count -lt 2) {
        Falha "A pasta _app tem so $($arquivosApp.Count) arquivo - esta chegando pela metade." "Espere a sincronizacao terminar (icone verde no OneDrive) e rode este diagnostico de novo."
    } else {
        Ok "A pasta _app tem index.html e $($arquivosApp.Count) arquivo(s) no total."
    }
}

$marcaJson = Join-Path $Pasta 'marca.json'
$portaBase = 8850
$faixa = 40
if (Test-Path -LiteralPath $marcaJson) {
    $m = Get-Content -LiteralPath $marcaJson -Raw -Encoding UTF8
    if ($m -match '"nome"\s*:\s*"([^"]*)"')   { Diga "  Nome configurado: $($Matches[1])" }
    if ($m -match '"porta"\s*:\s*(\d+)')      { $portaBase = [int]$Matches[1] }
    if ($m -match '"faixaPortas"\s*:\s*(\d+)'){ $faixa = [int]$Matches[1] }
    Ok "marca.json presente."
} else {
    Aviso "Sem marca.json - a ferramenta abre com o nome e a porta padrao."
}

$pastaDados = Join-Path $Pasta 'dados'
if (Test-Path -LiteralPath $pastaDados) {
    $n = @(Get-ChildItem -LiteralPath $pastaDados -Filter *.jsonl -ErrorAction SilentlyContinue).Count
    Ok "Pasta dados presente ($n arquivo(s) de log, um por pessoa que ja usou)."
} else {
    Aviso "Sem pasta dados - o programa cria sozinho na primeira abertura."
}

# --------------------------------------------------------- bloqueios e nuvem
Secao "4. Bloqueios"

$bloqueado = $false
if ($exe) {
    # Marca de origem: tudo que veio de download, zip ou e-mail chega marcado,
    # e o Windows mostra "o Windows protegeu seu PC" - ou simplesmente recusa.
    $z = Get-Item -LiteralPath $exe.FullName -Stream Zone.Identifier -ErrorAction SilentlyContinue
    if ($z) {
        if ($Corrigir) {
            Unblock-File -LiteralPath $exe.FullName
            Ok "O .exe estava bloqueado como 'arquivo da internet' - desbloqueado agora."
        } else {
            $bloqueado = $true
            Falha "O .exe esta bloqueado pelo Windows como arquivo vindo da internet." "Botao direito no .exe > Propriedades > marcar 'Desbloquear' > OK. Ou de dois cliques no arquivo Diagnostico-corrigir.cmd, aqui nesta pasta."
        }
    } else {
        Ok "O .exe nao esta bloqueado."
    }

    # Arquivo so na nuvem: o duplo clique costuma funcionar (o Windows baixa na
    # hora), mas com pasta grande e rede ruim a primeira abertura estoura o
    # tempo - e a pessoa relata que "nao abriu".
    $soNaNuvem = @()
    $todos = @($exe) + @(Get-ChildItem -LiteralPath (Join-Path $Pasta '_app') -Recurse -File -ErrorAction SilentlyContinue)
    foreach ($f in $todos) {
        $a = [int]$f.Attributes
        # OFFLINE 0x1000, RECALL_ON_OPEN 0x40000, RECALL_ON_DATA_ACCESS 0x400000
        if (($a -band 0x1000) -or ($a -band 0x40000) -or ($a -band 0x400000)) { $soNaNuvem += $f.Name }
    }
    if ($soNaNuvem.Count -gt 0) {
        Aviso "$($soNaNuvem.Count) arquivo(s) estao apenas na nuvem, ainda nao nesta maquina: $(($soNaNuvem | Select-Object -First 5) -join ', ')"
        Aviso "Botao direito na pasta > 'Sempre manter neste dispositivo' resolve e deixa a abertura rapida."
    } else {
        Ok "Todos os arquivos estao de fato nesta maquina."
    }
}

# Gravar: e a mesma pergunta que a ferramenta faz para decidir entre modo de
# edicao e modo de leitura. Tentar escrever de verdade cobre pasta "Pode
# exibir", arquivo somente-leitura e permissao negada de uma vez.
$onde = if (Test-Path -LiteralPath $pastaDados) { $pastaDados } else { $Pasta }
$teste = Join-Path $onde ("teste-diagnostico-" + [Guid]::NewGuid().ToString('N') + ".tmp")
try {
    [System.IO.File]::WriteAllText($teste, "teste")
    Remove-Item -LiteralPath $teste -Force
    Ok "Esta maquina consegue gravar na pasta."
} catch {
    Falha "Esta maquina NAO consegue gravar na pasta." "A pasta foi compartilhada como 'Pode exibir'. A ferramenta abre em modo somente leitura. Peca permissao de edicao a quem compartilhou."
}

# ------------------------------------------------------------ porta e janela
Secao "5. Porta e navegador"

$livres = 0
for ($p = $portaBase; $p -lt $portaBase + $faixa; $p++) {
    try {
        $l = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $p)
        $l.Start(); $l.Stop(); $livres++
    } catch { }
}
if ($livres -eq 0) {
    Falha "Nenhuma porta livre entre $portaBase e $($portaBase + $faixa - 1)." "Reinicie a maquina. Se continuar, algum programa esta ocupando essa faixa inteira."
} else {
    Ok "$livres porta(s) livre(s) na faixa $portaBase-$($portaBase + $faixa - 1)."
}

$nav = (Get-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice" -Name ProgId -ErrorAction SilentlyContinue).ProgId
if ($nav) {
    Ok "Navegador padrao: $nav"
} else {
    Aviso "Nao achei navegador padrao definido. O programa sobe, mas pode nao conseguir abrir a janela sozinho."
}

$rodando = @()
$outrasPastas = @()
if ($exe) {
    $nomeSemExt = [System.IO.Path]::GetFileNameWithoutExtension($exe.Name)
    foreach ($pr in (Get-Process -ErrorAction SilentlyContinue)) {
        try {
            if ($pr.Path -eq $exe.FullName) { $rodando += $pr }
            elseif ($pr.Path -and [System.IO.Path]::GetFileName($pr.Path) -eq $exe.Name) { $outrasPastas += $pr }
        } catch { }
    }
    if ($rodando.Count -gt 0) {
        Aviso "A ferramenta JA esta rodando nesta maquina (processo $($rodando[0].Id))."
        Aviso "Ela fica ao lado do relogio, no canto da barra de tarefas - clique na setinha para ver os icones escondidos. Duplo clique de novo so traz a janela de volta."
    }
    # Achado que passa despercebido e custa caro: a MESMA ferramenta aberta a
    # partir de duas pastas diferentes. As duas funcionam, as duas parecem
    # certas, e cada uma tem os seus dados - nenhuma ve a outra.
    if ($outrasPastas.Count -gt 0) {
        Falha "A mesma ferramenta esta aberta a partir de OUTRA pasta desta maquina." "Sao duas instalacoes separadas, cada uma com os seus dados - nenhuma ve o trabalho da outra. Decida qual pasta e a oficial, feche a outra e apague. A outra pasta e: $(($outrasPastas | ForEach-Object { $_.Path }) -join ' | ')"
    }
}

# A porta que um processo especifico esta escutando. Perguntar ao sistema quem
# e o dono do socket e a unica forma honesta: varrer a faixa acha a instancia
# de OUTRA pasta e faz o diagnostico dizer "funcionou" quando nao funcionou.
#
# Devolve 0 quando o processo nao escuta nada - e isso e uma RESPOSTA, nao uma
# falta de resposta: programa vivo sem porta aberta e programa parado numa
# janela de erro.
function PortaDoProcesso([int]$processo) {
    try {
        # Sem correspondencia, este cmdlet levanta erro em vez de devolver
        # lista vazia; por isso o catch tambem significa "nao escuta nada".
        $c = @(Get-NetTCPConnection -OwningProcess $processo -State Listen -ErrorAction Stop)
        foreach ($x in $c) { if ($x.LocalPort -gt 0) { return [int]$x.LocalPort } }
    } catch { }
    return 0
}

# Se este cmdlet nao existir (Windows muito podado), nao da para perguntar ao
# sistema, e nesse caso vale ler a porta que o programa anota - com prazo de
# validade, porque o arquivo sobrevive ao programa que o escreveu.
$temNetTcp = $null -ne (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue)

# ----------------------------------------------------------- o teste de fato
Secao "6. Teste de verdade: subir a ferramenta e conversar com ela"

$funcionou = $false
if (-not $exe) {
    Diga "  Sem .exe para testar."
} elseif ($bloqueado) {
    # Nao e cautela exagerada: abrir um .exe marcado como "vindo da internet"
    # faz o Windows levantar a janela "Deseja executar este arquivo?", que e
    # modal - e este diagnostico ficaria parado esperando resposta, sem dizer
    # por que. Melhor nao tentar e explicar.
    Diga "  Nao vou abrir o programa enquanto ele estiver bloqueado: o Windows"
    Diga "  levantaria a janela 'Deseja executar este arquivo?' e este"
    Diga "  diagnostico ficaria parado esperando resposta."
    Diga ""
    Diga "  Desbloqueie primeiro (o veredicto abaixo diz como) e rode de novo."
    Diga "  (A janela do Windows e justamente o que acontece no duplo clique:"
    Diga "  se ela aparecer, e so responder que quer executar.)"
} else {
    $proc = $null
    try {
        if ($rodando.Count -eq 0) {
            # --sem-navegador: sobe o servidor sem jogar uma janela na cara de
            # quem esta rodando o diagnostico.
            $proc = Start-Process -FilePath $exe.FullName -ArgumentList "--sem-navegador" -PassThru -ErrorAction Stop
            Diga "  Iniciado (processo $($proc.Id)). Esperando responder..."
            Start-Sleep -Seconds 3
        } else {
            Diga "  Ja estava rodando; vou conversar com a instancia aberta."
        }

        # De quem e a porta que vamos testar. Sem isto o diagnostico mente: se o
        # programa morreu ao subir e havia outra instancia (de outra pasta) na
        # mesma faixa, a varredura acharia ELA e daria tudo certo.
        $alvo = 0
        if ($proc) {
            $proc.Refresh()
            if ($proc.HasExited) {
                Falha "O programa subiu e fechou sozinho em menos de 3 segundos (codigo $($proc.ExitCode))." "Quase sempre ha uma janela de erro aberta na tela agora, ou que apareceu e foi fechada. LEIA o texto dela e mande junto com este relatorio - e a informacao que falta."
            } else {
                $alvo = $proc.Id
            }
        } elseif ($rodando.Count -gt 0) {
            $alvo = $rodando[0].Id
        }

        $porta = 0
        $deOnde = ""
        if ($alvo -gt 0) {
            if ($temNetTcp) {
                $porta = PortaDoProcesso $alvo
                $deOnde = "confirmada pelo sistema como porta do processo $alvo"
            } else {
                # Anotacao do proprio programa, e so se for recente: o arquivo
                # fica no temp depois do programa morrer, e uma porta velha faria
                # o teste conversar com outra instancia e dar tudo certo a toa.
                $anot = Get-ChildItem $env:TEMP -Filter "app-local-porta-*.txt" -ErrorAction SilentlyContinue |
                        Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-1) } |
                        Sort-Object LastWriteTime | Select-Object -Last 1
                if ($anot) {
                    $lido = 0
                    if ([int]::TryParse((Get-Content -LiteralPath $anot.FullName -Raw).Trim(), [ref]$lido)) {
                        $porta = $lido
                        $deOnde = "anotada pelo programa agora (nao confirmada pelo sistema)"
                    }
                }
            }
        }

        $resposta = $null
        if ($porta -gt 0) {
            Diga "  Porta $porta - $deOnde."
            try {
                $r = Invoke-WebRequest -Uri "http://127.0.0.1:$porta/api/quem" -UseBasicParsing -TimeoutSec 5
                if ($r.Content -match '"usuario"') { $resposta = $r.Content }
            } catch {
                Falha "O programa esta rodando e ocupou a porta $porta, mas nao respondeu: $($_.Exception.Message)" "Antivirus ou firewall interferindo na propria maquina. Vale repetir o teste com o antivirus pausado, e avisar quem entregou a ferramenta."
            }
        } elseif ($alvo -gt 0) {
            Falha "O programa esta rodando (processo $alvo), mas nao abriu porta nenhuma." "Quando isto acontece ha uma janela de erro esperando resposta na tela. Procure por ela, leia o texto e mande junto com este relatorio."
        }

        if ($resposta) {
            $funcionou = $true
            if ($proc) { Ok "A ferramenta subiu e respondeu na porta $porta." }
            else       { Ok "A ferramenta, que ja estava aberta, respondeu na porta $porta." }
            Diga "  Resposta: $resposta"
            if ($resposta -match '"grava"\s*:\s*false') {
                Aviso "Ela abriu em modo SOMENTE LEITURA (grava:false) - pasta compartilhada como 'Pode exibir'."
            } else {
                Ok "Modo de edicao liberado (grava:true)."
            }
            Diga "  Endereco que o navegador deve abrir: http://127.0.0.1:$porta/"
        }
        # Sem 'else' aqui: cada motivo de nao ter resposta ja foi reportado
        # acima, com o que fazer em cada caso. Um 'else' generico so repetiria
        # a mesma falha com menos informacao.
    } catch {
        Falha "Nao consegui nem iniciar o programa: $($_.Exception.Message)" "Se a mensagem fala de permissao, o antivirus ou a politica desta maquina esta bloqueando executavel nessa pasta."
    } finally {
        # Fecha so o que este diagnostico abriu; se ja estava rodando, deixa como estava.
        if ($proc) {
            try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue; Diga "  Programa de teste encerrado." } catch { }
        }
    }
}

# --------------------------------------------------------------- o veredicto
Secao "VEREDICTO"

if ($problemas.Count -eq 0 -and $funcionou) {
    Diga "  A ferramenta FUNCIONA nesta maquina - este diagnostico subiu ela e"
    Diga "  conversou com ela agora mesmo."
    Diga ""
    Diga "  Se o duplo clique parecia nao fazer nada, quase sempre e um destes:"
    Diga "    - ela JA estava aberta: procure o icone ao lado do relogio, no"
    Diga "      canto da barra de tarefas (clique na setinha para ver os"
    Diga "      escondidos), botao direito > Abrir;"
    Diga "    - a janela do navegador abriu ATRAS de outra janela;"
    Diga "    - o aviso 'o Windows protegeu seu PC' apareceu e foi fechado sem"
    Diga "      clicar em 'Mais informacoes' > 'Executar assim mesmo'."
} elseif ($problemas.Count -eq 0) {
    Diga "  Nenhum problema conhecido na pasta, mas o programa nao respondeu."
    Diga "  Mande este relatorio para quem entregou a ferramenta."
} else {
    Diga "  $($problemas.Count) problema(s) encontrado(s):"
    $i = 1
    foreach ($p in $problemas) {
        Diga ""
        Diga "  $i) $($p.o)"
        Diga "     O QUE FAZER: $($p.como)"
        $i++
    }
}

# O relatorio vai para a Area de Trabalho porque e o unico lugar que qualquer
# pessoa acha sem instrucao - e porque a pasta da ferramenta pode ser
# somente-leitura, e nesse caso nao teria onde gravar.
$destino = Join-Path ([Environment]::GetFolderPath('Desktop')) ("diagnostico-" + $env:COMPUTERNAME + ".txt")
try {
    [System.IO.File]::WriteAllLines($destino, [string[]]$linhas, (New-Object System.Text.UTF8Encoding($false)))
    Diga ""
    Diga "================================================================"
    Diga " Relatorio salvo na Area de Trabalho:"
    Diga "   $(Split-Path -Leaf $destino)"
    Diga " Mande esse arquivo para quem entregou a ferramenta."
    Diga "================================================================"
} catch {
    Diga ""
    Diga " (nao consegui salvar o relatorio: $($_.Exception.Message))"
}
Diga ""
