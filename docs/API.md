# A API do servidor

São cinco rotas. Todas respondem em `http://127.0.0.1:<porta>` e nenhuma responde
fora da máquina local. Todas mandam `Cache-Control: no-store`.

Quem escreve uma aplicação normalmente **não usa nada disto diretamente**:
`_app/aplicacao/log.js` embrulha tudo. Esta página é para quando algo não está
batendo, ou para quem quer falar com o servidor de outra linguagem.

---

## `GET /api/quem`

Quem é esta pessoa e ela pode gravar.

```json
{ "usuario": "vitor-cunha", "porta": 8880, "grava": true }
```

`usuario` vem do login do Windows, já reduzido a minúsculas sem acento — é o
mesmo texto que aparece no nome do arquivo de dados dela.

`grava` é a pergunta que decide a tela inteira. A resposta sai de **tentar abrir
o arquivo para escrita** e fechar sem escrever byte nenhum — não de ler atributo
nem de conferir ACL. Pasta compartilhada como "Pode exibir", arquivo marcado como
somente-leitura e pasta sem permissão dão erros diferentes; abrir para escrita
cobre os três de uma vez.

## `GET /api/marca`

O nome e o ícone desta instalação, lidos do `marca.json`.

```json
{ "nome": "Ordens de Serviço", "organizacao": "ACME", "icone": "/marca.ico" }
```

`icone` vem vazio se não houver `.ico` na pasta. Perguntar aqui, em vez de
escrever o nome no HTML, é o que permite rebatizar uma instalação sem abrir o
`_app/`.

## `GET /api/versao`

Mudou alguma coisa? E quem está mexendo?

```json
{
  "versao": "os.ana@pc-ana.jsonl:8120:639249910058336947|os.bruno@pc-bruno.jsonl:3300:639249911122334455|",
  "eu": "ana",
  "autores": [
    { "autor": "ana",   "em": "2026-09-14T13:56:45.8336947Z", "bytes": 8120 },
    { "autor": "bruno", "em": "2026-09-14T13:58:02.1122334Z", "bytes": 3300 }
  ]
}
```

`versao` é um carimbo do estado da pasta: nome, tamanho e data de cada arquivo de
log. **Não tem formato garantido** — é para comparar com o carimbo anterior, não
para interpretar. Se for igual ao último, nada mudou e não vale a pena pedir os
dados de novo. É esta rota que a aplicação chama de dois em dois segundos; a
pesada (`/api/logs`) só é chamada quando o carimbo muda.

`autores` é a lista de quem tem arquivo na pasta. O autor `origem` é omitido de
propósito: ele representa uma carga inicial de dados, não uma pessoa.

## `GET /api/logs`

Todos os arquivos de log, concatenados, uma operação por linha (JSONL).
`Content-Type: text/plain`.

```
{"autor":"ana","seq":1,"em":"2026-09-14T13:57:00.2345518Z","op":{"t":"nova","id":"a1","texto":"Revisar procedimento"}}
{"autor":"ana","seq":2,"em":"2026-09-14T13:57:00.2345518Z","op":{"t":"mover","id":"a1","coluna":"fazendo"}}
```

O envelope é do servidor; o miolo de `op` é da aplicação — o servidor nunca olha
lá dentro.

| Campo | De onde vem |
|---|---|
| `autor` | login do Windows de quem gravou |
| `seq` | contador por arquivo, começando em 1 |
| `em` | horário UTC ISO-8601 da gravação |
| `op` | o que a aplicação mandou, intacto |

As linhas vêm agrupadas por arquivo, **não** em ordem cronológica global:
ordenar é trabalho de quem lê (por `em`, depois `autor`, depois `seq` — ver
[ARQUITETURA.md](ARQUITETURA.md)). Linha truncada por sincronização no meio da
gravação é descartada aqui e reaparece inteira depois.

## `POST /api/ops`

Grava operações no arquivo **desta** pessoa. Uma operação JSON por linha, no
corpo.

```
POST /api/ops
X-App-Local: 1

{"t":"nova","id":"a1","texto":"Revisar procedimento"}
{"t":"mover","id":"a1","coluna":"fazendo"}
```

```json
{ "gravadas": 2, "versao": "os.ana@pc-ana.jsonl:260:639249910202355713|" }
```

O cabeçalho **`X-App-Local`** é obrigatório; sem ele a resposta é `403`. É o que
impede um site aberto em outra aba de varrer as portas locais e escrever no log
da equipe: cabeçalho personalizado obriga o navegador a pedir preflight, e o
servidor não responde preflight.

Respostas possíveis:

| Código | Quando | O que a aplicação deve fazer |
|---|---|---|
| `200` | gravou | seguir; `gravadas` diz quantas linhas entraram |
| `403` | veio sem `X-App-Local`, ou não é `POST` | erro de programação, não de ambiente |
| `503` | o arquivo não aceitou escrita | **desfazer na tela** e avisar a pessoa |

O `503` é o caso importante. Ele acontece com pasta em "Pode exibir", disco
cheio ou arquivo travado pelo antivírus — e a aplicação precisa *saber* que não
gravou, senão a tela passa a mostrar uma alteração que não existe em arquivo
nenhum. `_app/aplicacao/log.js` já trata isso: aplica na tela na hora, e desfaz
se a gravação falhar.

## `GET /marca.ico`

O ícone da instalação, para o HTML usar como favicon sem copiar o arquivo para
dentro de `_app/`. `404` se não houver ícone na pasta.

---

## Fora dessas rotas

Qualquer outro caminho é servido como arquivo de `_app/`, e **só** de lá. `/` é
`_app/index.html`. Caminho que tente sair da pasta (`..`, `%2e%2e`, caminho
absoluto) recebe `404`.

Tipos reconhecidos: `.html`, `.js`, `.css`, `.json`, `.svg`, `.ico`, `.png`,
`.jpg`, `.gif`, `.webp`, `.woff`, `.woff2`, `.pdf`, `.csv`. Qualquer outra
extensão sai como `text/plain`.
