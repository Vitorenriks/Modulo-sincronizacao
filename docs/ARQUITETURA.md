# Arquitetura

Este documento explica **por que** o desenho é esse. A parte de "como usar" está
no README; a parte de "quais rotas existem" está em [API.md](API.md).

---

## O mapa: uma pasta por camada

A árvore de pastas **é** o diagrama de arquitetura. Não há um desenho separado
que possa ficar desatualizado: se um arquivo está em `dominio/`, ele não pode
importar tela nem rede, e isso se confere abrindo o arquivo.

```
Servidor C#\
│
├── src\                        INFRAESTRUTURA — o processo hospedeiro
│   └── Servidor.cs                HTTP, disco, bandeja, marca.json
│                                  não sabe o que a aplicação faz
│
├── modelo\                     O MOLDE copiado para cada projeto novo
│   ├── marca.json                 configuração da instalação
│   ├── LEIA-ME.txt                texto para o usuário final
│   └── _app\                      a aplicação servida no navegador
│       ├── index.html             a página e a ordem de carga
│       ├── principal.js        RAIZ DE COMPOSIÇÃO — liga as três camadas
│       ├── dominio\            DOMÍNIO — a regra, e só ela
│       │   └── regras.js          zerar(), aplicar(), COLUNAS, novoId()
│       ├── aplicacao\          APLICAÇÃO — o caso de uso
│       │   └── log.js             criarLog(): ordem, mesclagem, gravação
│       └── tela\               APRESENTAÇÃO — pixels
│           ├── quadro.js          criarTela(acoes): monta os elementos
│           └── estilo.css         cores e espaçamento
│
├── dados\                      PERSISTÊNCIA (criada em cada instalação)
│                                  um .jsonl por pessoa; só cresce no fim
│
├── ferramentas\                FERRAMENTAL — não vai para o cliente
│   ├── Icone.ps1                  logo do cliente → .ico multi-resolução
│   └── teste-convergencia.js      prova que duas pessoas convergem
│
├── build.ps1                   ENTREGA — compila src\ em um .exe
├── novo-projeto.ps1            ENTREGA — monta a pasta do cliente
├── testar.ps1                  ENTREGA — roda o produto inteiro
│
├── projetos\                   SAÍDA gerada; nada aqui é fonte
├── docs\                       estes documentos
└── legado\                     o painel original; pode apagar
```

### A regra de dependência

Uma seta só aponta **para dentro**. Quem está mais perto do mundo (tela, HTTP,
disco) conhece quem está mais perto da regra; nunca o contrário.

```
   tela\  ──────┐
                ├──► dominio\   (o centro: não conhece ninguém)
   aplicacao\ ──┘

   principal.js ──► tela\, aplicacao\, dominio\   (o único que vê os três)

   src\Servidor.cs ──► nada de _app\   (serve bytes; não lê o conteúdo)
```

O que isso compra, em concreto: dá para trocar o quadro de tarefas por um
formulário de ordem de serviço mexendo em `dominio/` e `tela/` e **sem abrir**
`aplicacao/log.js`. E dá para portar o hospedeiro para Linux reescrevendo
`src/` sem tocar em uma linha de `_app/`.

### Camada por camada

**`dominio/regras.js` — o centro.**
`zerar()` devolve um estado vazio; `aplicar(estado, op, meta)` toca uma operação
nesse estado. Só isso. Não há `document`, não há `fetch`, não há `Date.now()`
dentro de `aplicar` — o horário chega em `meta`, vindo de fora, porque uma regra
que consulta o relógio dá resultado diferente a cada execução e deixa de ser
reconstruível. É a camada que dá para testar sem navegador e sem executável,
porque não há nada aqui para simular.

**`aplicacao/log.js` — o caso de uso.**
Fala com as cinco rotas, ordena os eventos, descarta linha repetida e linha
truncada, recalcula o estado do zero, aplica a escrita otimista e desfaz quando
a gravação falha. Não há uma linha de regra de negócio aqui: `zerar` e `aplicar`
chegam por parâmetro. É por isso que `PERSONALIZAR.md` manda apagar o resto e
**manter este arquivo** — ele é o mesmo em todo projeto entregue.

**`tela/quadro.js` — a apresentação.**
Lê o estado e monta os elementos. Não muda o estado, não chama `fetch` e não
sabe o que é uma operação. Um clique não grava nada aqui: chama
`acoes.criar(...)`, `acoes.mover(...)`. Quem liga essas ações ao log é
`principal.js`. A tela conhece o **nome** da ação, não o caminho até o disco.

**`principal.js` — a raiz de composição.**
O único arquivo que conhece as três camadas ao mesmo tempo, e o lugar onde a
troca de transporte acontece se um dia acontecer. São quinze linhas de fiação e
mais comentário do que código, de propósito: tudo o que é decisão está nas
camadas, e o que sobra aqui é só ligar uma na outra.

**`src/Servidor.cs` — a infraestrutura, e por que continua um arquivo só.**
Por dentro ele tem as mesmas fronteiras (marca, HTTP, roteamento, dados, ícone,
bandeja — nessa ordem, com um cabeçalho em cada bloco). Por fora continua **um
arquivo**, e isso é decisão, não descuido: o `csc` do sistema compila sem
projeto, sem SDK e sem lista de fontes para manter em dia, e o README promete
"o servidor inteiro, em um arquivo, sem dependência". Espalhar 900 linhas em
seis pastas tornaria o diagrama mais bonito e a compilação mais frágil — e a
fronteira que realmente importa aqui já está garantida por outra coisa: o
servidor **não consegue** depender da regra de negócio, porque nunca abre o
conteúdo do que serve.

### Como conferir que a regra não foi quebrada

Não há linter para isso, e não precisa de um — as perguntas cabem em três
buscas:

```powershell
cd modelo\_app
Select-String -Path dominio\*.js, aplicacao\*.js -Pattern 'document\.|window\.'
Select-String -Path dominio\*.js, tela\*.js      -Pattern 'fetch'
Select-String -Path tela\*.js                    -Pattern 'Log\.'
```

| Se aparecer alguma linha | A camada que vazou |
|---|---|
| `document.` ou `window.` em `dominio/` ou `aplicacao/` | regra ou caso de uso mexendo em tela |
| `fetch` em `dominio/` ou `tela/` | alguém pulou o caso de uso |
| `Log.` em `tela/` | a tela furou as `acoes` e foi direto no log |
| `estado.` sendo **atribuído** em `tela/` | a tela está mudando o que deveria só desenhar |

Hoje as três buscas saem vazias, e há uma quarta que vale mais que as outras:
`ferramentas/teste-convergencia.js` carrega `aplicacao/log.js` entregando
**só** `fetch` e `setInterval`. Se um dia esse arquivo precisar de `document`
ou de `window` para sequer carregar, o teste quebra — a fronteira é verificada
a cada `.\testar.ps1`, não confiada à boa vontade de quem edita.

---

## A decisão que define tudo: log de operações, não arquivo de estado

A alternativa óbvia seria guardar um `dados.json` com o estado atual e reescrevê-lo
a cada mudança. É o que quase todo mundo faz, e é o que não funciona numa pasta
sincronizada:

> Ana e Bruno abrem a ferramenta. Ana muda o item 3. Bruno muda o item 7. As duas
> máquinas reescrevem `dados.json` inteiro. O OneDrive recebe duas versões do
> mesmo arquivo, escolhe uma e renomeia a outra para "dados-cópia em conflito
> (DESKTOP-XYZ).json". Uma das duas alterações some, e ninguém é avisado.

Não há como resolver isso com trava, com retry ou com "salvar mais rápido": o
problema é **dois escritores no mesmo arquivo**.

A solução é tirar a disputa:

- **Um arquivo por pessoa.** `dados/<prefixo>.<usuario>@<maquina>.jsonl`. Ana
  escreve só no arquivo da Ana. Bruno, só no do Bruno. O OneDrive nunca precisa
  escolher entre duas versões, porque nunca existem duas versões do mesmo arquivo.
- **Só acrescentar, nunca reescrever.** Cada operação é uma linha nova no fim do
  arquivo. Um arquivo que só cresce no fim sincroniza sem ambiguidade e sobrevive
  a um desligamento no meio da gravação: o pior caso é a última linha sair pela
  metade, e ela é descartada na leitura.
- **O estado é calculado, não guardado.** A tela é o resultado de tocar todas as
  operações de todos os arquivos, na ordem. Ninguém precisa combinar nada.

O preço é que o log cresce para sempre, e é um preço barato: uma ferramenta com
uso pesado por dois anos fica na casa de alguns megabytes de texto.

## A ordem é definida, e é a mesma em toda máquina

Juntar os arquivos não basta — é preciso que toda máquina os junte na **mesma
ordem**, senão duas telas mostram coisas diferentes a partir das mesmas linhas.

A ordem é: **horário UTC, depois autor, depois sequência.**

O autor e a sequência não são enfeite. Dois cliques em máquinas diferentes caem
no mesmo milissegundo com mais frequência do que a intuição sugere, e sem
critério de desempate a ordenação fica à mercê da implementação de `sort` do
navegador. Com o desempate, o resultado é idêntico em qualquer máquina, hoje e
daqui a um ano.

Os relógios das máquinas não são perfeitamente sincronizados, e isso é aceito de
propósito: um desvio de alguns segundos reordena operações que, na prática, não
competem entre si. Trocar isso por relógio lógico (Lamport, vetor de versão)
custaria um campo a mais em cada linha e um problema a mais para explicar, sem
mudar nada no que a pessoa vê.

## O estado é recalculado do zero a cada mudança

Mudou alguma coisa na pasta? Zera o estado e toca o log inteiro de novo.

Parece desperdício. Não é: são milhares de linhas, e o navegador faz isso em
milissegundos. Em troca, desaparece a classe de bug mais cara desse tipo de
aplicação — **o estado que foi ficando errado aos poucos** e que ninguém sabe
desde quando, porque a aplicação aplicou uma alteração parcial em cima de uma
base que já estava torta.

É também o que torna as operações fáceis de escrever: `aplicar()` nunca precisa
saber se já rodou antes.

## O servidor não sabe o que é a aplicação

`src/Servidor.cs` não interpreta o conteúdo de uma operação. Ele anexa linha,
devolve as linhas e informa se algo mudou. Nada mais.

Isso é uma decisão de produto, não de estilo:

- a aplicação inteira pode ser trocada editando `_app/`, **sem compilador**;
- quem escreve a tela não precisa saber C#;
- o mesmo executável, byte a byte, serve a todos os clientes — o que muda é o
  `marca.json` e o `_app/`;
- um erro na regra de negócio nunca corrompe o armazenamento.

## Por que .NET Framework 4 e WinForms clássico

Porque o `csc` do .NET Framework 4 **já está em toda máquina Windows** desde o 8.
Não é preciso instalar SDK, runtime, Visual Studio ou nada.

Migrar para .NET moderno traria `Span<T>`, `HttpListener` melhor e sintaxe mais
curta — e traria junto a necessidade de publicar self-contained (um executável de
70 MB em vez de 97 KB) ou de exigir runtime instalado na máquina de cada usuário.
Qualquer uma das duas quebra a promessa central: *copiar a pasta e usar*.

É por isso que o código está em C# 5, usa `delegate` em vez de lambda em alguns
pontos, e `ContextMenu` em vez de `ContextMenuStrip`. Não é código antigo por
descuido; é a versão que compila com o que a máquina já tem.

## Escolhas de segurança

| Escolha | Motivo |
|---|---|
| Escuta só em `127.0.0.1` | Nenhuma outra máquina alcança a porta, e o Windows não pede liberação de firewall — o aviso que faria metade dos usuários desistirem na primeira tentativa. |
| `POST` exige o cabeçalho `X-App-Local` | Impede que um site aberto em outra aba varra as portas locais e escreva no log da equipe. Cabeçalho personalizado obriga o navegador a pedir preflight, e preflight não é respondido. |
| Arquivos servidos só de `_app/`, com a raiz terminada em barra | Sem a barra final, uma pasta vizinha chamada `_apparte` passaria no teste de prefixo. O caminho é resolvido para absoluto antes da comparação, então `..` e `%2e%2e` não escapam. |
| Corpo limitado a 32 MB | Acima disso não é operação; é engano ou ataque. |
| `marca.json` só aceita o nome do arquivo de ícone | `Path.GetFileName()` impede que a configuração aponte para fora da pasta. |
| Permissão vem do sistema de arquivos | Não há "modo leitura" no JavaScript que alguém contorne pelo console: quem nega a escrita é a permissão da pasta, e a aplicação apenas pergunta e obedece. |

Vale dizer o que **não** é protegido: quem consegue abrir a pasta consegue ler e
escrever tudo o que está nela, e pode editar o `.jsonl` na mão. O controle de
acesso é o do OneDrive/SharePoint/rede, no nível da pasta. Isso é adequado para
ferramenta interna de equipe e inadequado para dado que precise de segregação
entre membros da mesma equipe.

## Uma instância por pasta, por máquina

Dois processos abertos na mesma pasta gravariam no mesmo arquivo com dois
contadores de sequência independentes: as duas alterações sairiam com o mesmo
número e a mesclagem descartaria uma delas achando que era linha repetida. Perda
de dado, sem erro na tela.

O mutex tem o nome derivado do **caminho da pasta**, então duas ferramentas
diferentes na mesma máquina não brigam entre si. O segundo duplo clique lê a
porta anotada no `%TEMP%` da máquina e reabre a janela existente — que é o que a
pessoa espera que aconteça.

A porta fica no `%TEMP%` local, e não na pasta compartilhada, de propósito:
informação que só interessa a um computador não deve sincronizar para os outros.

## Limites conhecidos

- **Volume.** O navegador relê o log inteiro a cada mudança. Na casa das dezenas
  de milhares de operações isso ainda é instantâneo; na casa dos milhões, não. A
  saída, quando chegar lá, é compactar o log antigo num arquivo `origem` (o autor
  `origem` já é tratado como carga inicial, e não como pessoa).
- **Latência.** A atualização é do tempo do OneDrive, não de WebSocket. Na
  prática, segundos. Não serve para algo que precise de tempo real de verdade.
- **Só Windows.** WinForms, bandeja, `csc` do sistema. Portar para outro sistema
  significa reescrever o processo hospedeiro, não o protocolo — `_app/` e o
  formato do log são independentes de plataforma.
- **Sem assinatura digital.** O SmartScreen avisa na primeira execução. Um
  certificado de assinatura de código resolve, e é a melhoria com melhor relação
  custo/benefício se o volume de entregas crescer.
