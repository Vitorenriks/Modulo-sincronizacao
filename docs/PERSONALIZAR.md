# Personalizar

Três níveis, do mais barato ao mais caro: trocar a marca, trocar a tela,
trocar o servidor.

---

## 1. A marca de uma instalação (sem compilador)

Tudo que identifica o cliente está em dois arquivos ao lado do `.exe`:

**`marca.json`**

```json
{
  "nome": "Ordens de Serviço",
  "organizacao": "ACME",
  "icone": "marca.ico",
  "prefixo": "os",
  "porta": 8880,
  "faixaPortas": 40
}
```

| Campo | O que faz | Padrão |
|---|---|---|
| `nome` | Título na aba, na bandeja e nos avisos | `Aplicação` |
| `organizacao` | Entra no título depois do travessão. Deixe vazio se não quiser | vazio |
| `icone` | Nome do `.ico` ao lado do `.exe`. Só o nome — caminho é ignorado | `marca.ico` |
| `prefixo` | Prefixo dos arquivos em `dados\`. **Não troque depois de a ferramenta entrar em uso** | `dados` |
| `porta` | Onde começa a procurar porta livre (1024–65000) | `8850` |
| `faixaPortas` | Quantas portas tentar a partir dali | `40` |

Arquivo ausente ou com erro de vírgula não impede o programa de abrir: cada
campo cai no padrão. Grave sempre em **UTF-8 sem BOM**.

> **`prefixo` é o único campo perigoso.** Ele entra no nome dos arquivos de
> dados. Trocar com a ferramenta em uso faz o servidor parar de enxergar o que
> já existe — os dados continuam lá, mas a tela abre vazia. Para renomear de
> verdade, renomeie também os arquivos em `dados\`.

**`marca.ico`** — o ícone da bandeja, da barra de tarefas e do arquivo no
Explorer. Trocar o arquivo troca o ícone da bandeja na próxima abertura. O ícone
que o **Explorer** desenha no `.exe` é o que foi embutido na compilação: para
trocar aquele, é preciso recompilar (o `novo-projeto.ps1` faz as duas coisas de
uma vez).

Para gerar um `.ico` correto a partir do logo do cliente:

```powershell
. .\ferramentas\Icone.ps1
Resolve-IconeDaMarca -Origem "C:\logos\acme.png" -Destino ".\projetos\ACME\marca.ico"
```

Aceita `.png`, `.jpg` e `.ico`. Gera os tamanhos que o Windows realmente pede
(16, 24, 32, 48, 64 e 256), em vez de deixar o sistema encolher um quadro grande
na marra — que é o que faz o ícone ficar borrado ao lado do relógio.

**As cores da tela** ficam em `_app/tela/estilo.css`, nas variáveis do `:root` (e nas
do bloco de tema escuro logo abaixo). `--cor-marca` é a única que costuma mudar
de cliente para cliente.

---

## 2. A sua própria aplicação

`_app/` é HTML, CSS e JavaScript comuns. Sem build, sem npm, sem CDN — a pasta
pode estar numa máquina sem internet, e uma dependência externa que não carrega
é uma tela branca sem explicação.

### Onde mexer, pasta por pasta

```
_app\
  index.html       troque o corpo da página pela sua
  principal.js     ajuste a fiação: quais ações a sua tela oferece
  dominio\
    regras.js      APAGUE e escreva o seu: zerar() e aplicar()
  aplicacao\
    log.js         NÃO MEXA — é o cliente do protocolo, igual em todo projeto
  tela\
    quadro.js      APAGUE e escreva a sua tela
    estilo.css     as cores no :root; o resto é neutro de propósito
```

Duas pastas se apagam, uma se mantém. Se você se pegar precisando editar
`aplicacao/log.js` para a sua aplicação funcionar, quase sempre é sinal de que
alguma regra foi parar no lugar errado — vale reler as três regras abaixo antes
de mexer nele.

A separação não é burocracia: é ela que deixa `dominio/regras.js` ser testável
sem navegador, e é ela que permite recalcular o log inteiro do zero a cada
mudança. O detalhe de por que cada camada existe está em
[ARQUITETURA.md](ARQUITETURA.md#o-mapa-uma-pasta-por-camada).

### O contrato

Quem chama `criarLog` é `principal.js` — a raiz de composição:

```js
var Log = criarLog({
  zerar:     function ()                    { return { /* estado vazio */ }; },
  aplicar:   function (estado, op, meta)    { /* muda o estado. NÃO toca na tela */ },
  aoMudar:   function (estado, info)        { /* desenha. NÃO toca no estado */ },
  intervalo: 2000
});

Log.iniciar();                       // lê a marca, descobre quem é você, carrega o log
Log.enviar({ t: 'nova', id: 'x' });  // grava uma operação
Log.eu.usuario                       // 'ana'
Log.eu.podeGravar                    // false quando a pasta é só leitura
Log.eu.autores                       // quem mais tem arquivo nesta pasta
Log.eu.erro                          // texto do último problema, ou null
```

`meta` traz `{ autor, seq, em }` — quem gravou, em que ordem, quando.

`info` traz `{ eu, total }`. `total` é o número de operações do log, ou `-1`
quando o desenho veio de uma alteração local que ainda não foi para o disco.

### As três regras que não dá para quebrar

**1. `aplicar` muda estado, `aoMudar` desenha.** Nunca os dois no mesmo lugar —
e é por isso que eles moram em pastas diferentes: `aplicar` em `dominio/`,
o desenho em `tela/`. É essa separação que permite recalcular o log inteiro do
zero a cada mudança, e é o recálculo do zero que garante que a sua tela e a do
colega sejam idênticas. Regra prática: se `document` aparecer em `dominio/`,
alguma coisa está no lugar errado.

**2. Operações são absolutas, nunca relativas.**

```js
Log.enviar({ t: 'mover', id: 7, coluna: 'feito' });   // certo
Log.enviar({ t: 'mover', id: 7, direcao: 'direita' }); // errado
```

"Para a direita" depende de onde o item estava. Duas pessoas clicando ao mesmo
tempo, ou o mesmo log tocado daqui a um ano, dão resultados diferentes.

**3. `aplicar` tem que aguentar a mesma operação duas vezes, e operações fora de
ordem.** Criar algo que já existe: ignore. Alterar algo que já foi apagado:
ignore. Os dois casos acontecem de verdade quando dois arquivos sincronizam com
atraso diferente.

```js
function aplicar(estado, op, meta) {
  if (op.t === 'nova') {
    if (estado.itens[op.id]) return;        // repetida
    estado.itens[op.id] = { id: op.id, texto: op.texto, autor: meta.autor };
    return;
  }
  var item = estado.itens[op.id];
  if (!item) return;                        // já apagado
  if (op.t === 'texto') item.texto = op.texto;
}
```

### Carga inicial de dados

Para a ferramenta já nascer com o cadastro que existia na planilha, grave um
arquivo `dados\<prefixo>.origem.jsonl` com uma operação por linha, no formato do
log (`{"autor":"origem","seq":1,"em":"...","op":{...}}`). O autor `origem` é
tratado como carga inicial e não aparece na lista de pessoas mexendo.

### Enquanto desenvolve

Deixe o `.exe` aberto e recarregue o navegador (`Ctrl+F5`) — o servidor lê os
arquivos de `_app/` do disco a cada pedido e manda `no-store`, então não há
cache para limpar nem processo para reiniciar. Só o `marca.json` é lido uma vez,
na abertura.

---

## 3. O servidor

`src/Servidor.cs`, um arquivo, sem dependência externa. Ele continua sendo um
arquivo só de propósito — o motivo está em
[ARQUITETURA.md](ARQUITETURA.md#camada-por-camada). Compilar:

```powershell
.\build.ps1                                              # saida\Servidor.exe
.\build.ps1 -Saida "saida\Teste.exe" -Icone "logo.png"   # com ícone
```

Antes de mexer, leia os limites em [ARQUITETURA.md](ARQUITETURA.md) — em especial
**por que o código está em C# 5 e WinForms clássico**. Usar C# moderno obriga a
instalar SDK para compilar e runtime para rodar, e isso quebra a promessa de
copiar a pasta e usar.

Duas armadilhas que já custaram caro:

- **O fonte é UTF-8 sem BOM.** O `build.ps1` passa `/codepage:65001`; sem isso os
  acentos das mensagens viram lixo na tela do usuário.
- **Os `.ps1` são UTF-8 COM BOM.** O PowerShell 5.1 lê script sem BOM como ANSI,
  e aí quem vira lixo são os acentos dos próprios scripts. Se editar em um
  editor que salva sem BOM, corrija antes de commitar.

Depois de recompilar, os projetos já entregues **não** se atualizam sozinhos:
cada um tem a própria cópia do `.exe`. Substituir o executável dentro da pasta do
cliente é a atualização — os dados em `dados\` não são tocados.
