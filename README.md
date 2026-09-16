# Núcleo

**Um servidor web local em C# que transforma uma pasta compartilhada em uma aplicação de equipe.**

Copie a pasta para o OneDrive, SharePoint ou unidade de rede. Compartilhe com o
time. Cada pessoa dá dois cliques no executável que está lá dentro, e a
ferramenta abre no navegador da máquina dela — com o nome e o ícone da empresa,
com os dados de todo mundo juntos, sem instalar nada, sem login, sem servidor,
sem mensalidade.

> O nome "Núcleo" é o nome de trabalho do projeto. Ele aparece só neste README e
> nos documentos de `docs/` — o código não tem marca nenhuma compilada dentro.
> Para rebatizar o produto, troque o texto daqui; para rebatizar uma instalação,
> troque o `marca.json` dela.

---

## 1. Finalidade para o usuário final

Isto é o que a ferramenta faz pela pessoa que vai usá-la no dia a dia — sem
metáfora, sem promessa de futuro:

1. **Ela dá dois cliques num arquivo e a ferramenta abre.** Não instala, não
   pede senha, não pede permissão de administrador, não cria conta, não escolhe
   servidor. Dois cliques.
2. **Ela vê a mesma coisa que os colegas veem.** O que o colega alterou aparece
   na tela dela em poucos segundos — o tempo de a pasta sincronizar.
3. **Ela e o colega podem mexer ao mesmo tempo, sem um apagar o outro.** Cada
   máquina grava no próprio arquivo; a tela mostra a soma de todos. Não existe
   "cópia em conflito", não existe "fulano salvou por cima".
4. **Ela continua trabalhando sem internet.** O que fizer offline entra na fila
   e aparece para os outros quando a pasta voltar a sincronizar.
5. **Ela não perde nada por engano.** Nada é sobrescrito: a pasta guarda o
   histórico completo de quem fez o quê e quando. Dá para reconstruir qualquer
   dia anterior.
6. **Ela sabe quando só pode olhar.** Se a pasta foi compartilhada como "Pode
   exibir", a tela abre em modo leitura e avisa — em vez de oferecer um botão
   que falharia sem explicação.
7. **Os dados dela não saem da empresa.** Tudo mora dentro da pasta, na
   infraestrutura que a empresa já tem. O programa só escuta em `127.0.0.1`:
   nem a máquina ao lado alcança.
8. **Ela reconhece a ferramenta como sendo da casa.** Nome da empresa na aba do
   navegador, logo da empresa no ícone da bandeja e do arquivo.
9. **Ela desinstala arrastando a pasta para a lixeira.** Não fica registro, não
   fica serviço, não fica nada na máquina.

**O que a ferramenta NÃO faz**, dito de frente para ninguém comprar a coisa
errada: não funciona pela internet aberta (é pasta compartilhada, não site
público), não roda no celular, não tem controle de acesso por campo (quem pode
abrir a pasta vê tudo o que está nela), e não substitui um banco de dados para
volumes muito grandes — o limite prático é a casa das dezenas de milhares de
operações por ferramenta.

---

## 2. Solução para o mercado

### O problema

Toda empresa de médio porte tem entre cinco e cinquenta processos internos que
vivem hoje numa **planilha no OneDrive** — controle de ordens de serviço,
checklist de qualidade, escala de plantão, inventário, acompanhamento de
obra, cadastro de fornecedor, aprovação de compra.

Essa planilha:

- trava quando duas pessoas abrem (ou gera "cópia em conflito" e alguém perde
  o trabalho da manhã);
- não valida nada, então a coluna de datas tem texto no meio;
- quebra quando alguém arrasta uma célula;
- e não tem histórico de quem mudou o quê.

As três saídas conhecidas, e por que cada uma emperra:

| Saída | Por que emperra |
|---|---|
| **SaaS de mercado** (Trello, Monday, Notion, Pipefy) | Mensalidade por usuário que cresce com o time; dado sensível sai da empresa; TI corporativa barra a contratação; ninguém quer pagar assinatura por um processo que envolve seis pessoas. |
| **Sistema interno sob medida** (web + banco + hospedagem) | Custa dezenas de milhares de reais, demora meses, e depois precisa de alguém para manter servidor, backup, certificado e senha de usuário — para automatizar uma planilha. |
| **Continuar na planilha** | É o que acontece na prática. O custo não aparece em nota fiscal; aparece em retrabalho. |

Existe uma faixa inteira de processos **importantes demais para a planilha e
pequenos demais para um sistema** — e é exatamente aí que nada é oferecido hoje.

### A solução

O Núcleo entrega o resultado do sistema sob medida com o custo de distribuição
da planilha:

- **Sem infraestrutura.** O "servidor" é um executável de 97 KB dentro da pasta.
  Não há máquina para provisionar, banco para administrar, certificado para
  renovar nem backup para configurar — a pasta já é sincronizada e versionada
  pelo OneDrive/SharePoint que a empresa paga de qualquer jeito.
- **Sem obstáculo de TI.** Não instala, não exige administrador, não abre porta
  no firewall, não manda dado para fora. A conversa com a TI do cliente é
  "é um arquivo na pasta compartilhada", e não uma análise de fornecedor.
- **Sem mensalidade para o cliente final.** Ele paga o desenvolvimento da
  ferramenta, não o direito de continuar usando o que já pagou.
- **Sem prazo de meses.** A parte difícil — concorrência, mesclagem, permissão,
  distribuição, histórico — já está resolvida e não se reescreve. O trabalho por
  cliente é a tela e a regra de negócio, em HTML/CSS/JS comum.

### Para quem vende, e como

O produto tem dois públicos, e é o mesmo código:

**a) Quem presta serviço de automação** (consultoria, TI terceirizada,
desenvolvedor autônomo). O Núcleo vira a base de um catálogo: a mesma fundação,
dezenas de ferramentas diferentes por cima. Cada projeto novo é
`.\novo-projeto.ps1 -Nome "..." -Icone "logo-do-cliente.png"` e depois só a tela.
Isso muda a economia do serviço: uma ferramenta interna deixa de ser um projeto
de dois meses e vira uma entrega de dias, com margem, a um preço que a empresa
de 40 pessoas aprova sem reunião de diretoria.

**b) A TI interna de uma empresa.** Deixa de dizer "não dá" para os vinte
pedidos pequenos que chegam por ano e passa a atender cada um em uma semana,
sem pedir servidor, sem abrir chamado de infraestrutura e sem contratar mais um
SaaS.

**Onde o Núcleo ganha:** de 3 a 50 pessoas, processo interno, dado que não pode
sair, empresa que já usa OneDrive/SharePoint, orçamento que não comporta
mensalidade por usuário.

**Onde o Núcleo perde, e é para dizer na hora:** time acima de ~100 pessoas na
mesma ferramenta, necessidade de acesso externo (cliente final, fornecedor),
permissão por perfil dentro da mesma base, ou volume de banco de dados. Nesses
casos a resposta honesta é um sistema web de verdade — e dizer isso na primeira
reunião é o que sustenta a credibilidade das outras vinte vendas.

---

## 3. Como funciona, em um parágrafo

O executável acha uma porta livre em `127.0.0.1`, sobe um servidor HTTP mínimo,
serve os arquivos de `_app/` (HTML/CSS/JS comum) e expõe cinco rotas de API.
Os dados não são um arquivo de estado: são um **log de operações**, um JSONL por
pessoa, em `dados/`. A tela é o resultado de tocar todas as operações de todo
mundo na ordem, desde o começo. Como cada máquina só escreve no arquivo dela,
duas pessoas trabalhando ao mesmo tempo nunca disputam o mesmo byte — que é
exatamente a causa da "cópia em conflito" do OneDrive. O servidor não interpreta
os dados: anexa linha, devolve as linhas e diz se algo mudou. Toda a regra de
negócio está no navegador, e é por isso que se troca a aplicação inteira sem
recompilar nada.

Detalhes em [`docs/ARQUITETURA.md`](docs/ARQUITETURA.md).

---

## 4. Começando

Pré-requisito: Windows 8 ou mais novo. Nada mais — o compilador usado (`csc` do
.NET Framework 4) já vem no sistema.

```powershell
# 1. criar um projeto para um cliente
.\novo-projeto.ps1 -Nome "Ordens de Serviço" -Organizacao "ACME" -Icone "C:\logos\acme.png"

# 2. abrir o que saiu
explorer .\projetos\"Ordens de Serviço"

# 3. dois cliques em "Ordens de Serviço.exe" — a aplicação de exemplo abre

# 4. editar _app\ até virar a ferramenta que o cliente pediu

# 5. copiar a pasta inteira para o OneDrive e compartilhar com o time
```

Sem `-Icone`, o gerador desenha um ícone com as iniciais do projeto, em uma cor
derivada do nome — para dois projetos nunca saírem iguais na bandeja.

---

## 5. O que tem nesta pasta

```
novo-projeto.ps1     monta uma pasta pronta para entregar ao cliente
build.ps1            compila src\Servidor.cs em um .exe
testar.ps1           roda o produto inteiro e confere o que ele promete
src\Servidor.cs      o servidor inteiro, em um arquivo, sem dependência
ferramentas\
  Icone.ps1          converte o logo do cliente em .ico multi-resolução
  Diagnostico.ps1    por que não abriu na máquina de alguém, e o que fazer
  Diagnostico.cmd    o que a pessoa clica — um .ps1 não abre com dois cliques
  Diagnostico-corrigir.cmd  o mesmo, autorizado a desbloquear o .exe
  teste-convergencia.js   prova que duas pessoas simultâneas convergem
modelo\
  marca.json         modelo da configuração de marca
  LEIA-ME.txt        instruções para o usuário final (com marcadores)
  PASSO-A-PASSO.txt  a primeira abertura, passo a passo, para quem recebe
  _app\              uma pasta por camada; a árvore é o diagrama
    index.html       a página e a ordem de carga
    principal.js     a raiz de composição — liga as três camadas
    dominio\
      regras.js      a regra pura: zerar() e aplicar() — o molde a copiar
    aplicacao\
      log.js         o cliente do protocolo — mantenha este arquivo
    tela\
      quadro.js      desenha o estado; um clique vira uma ação, não um POST
      estilo.css     aparência neutra; as cores ficam no :root
projetos\
  Quadro de Exemplo\ um projeto gerado, pronto para dois cliques
docs\
  ARQUITETURA.md     por que o desenho é esse, e o que quebra se mudar
  API.md             as cinco rotas e o formato do log
  PERSONALIZAR.md    marca, ícone, e como escrever a sua própria _app
legado\              o painel original que deu origem ao projeto; pode apagar
```

Para conferir que tudo está de pé depois de mexer em qualquer coisa:

```powershell
.\testar.ps1
```

São 42 verificações no executável de verdade (porta, cabeçalho obrigatório,
travessia de caminho, pasta somente-leitura, segunda instância, e o que a
pasta de entrega precisa conter) e 10 no protocolo do log (convergência entre máquinas, empate de horário, linha
duplicada, linha truncada, desfazer quando a gravação falha).

---

## 6. Quando não abre na máquina de alguém

Toda pasta gerada sai com um `_suporte\` dentro. A pessoa dá dois cliques em
`_suporte\Diagnostico.cmd` e recebe, em português, na tela: onde a pasta está,
se o `.exe` chegou inteiro, se o Windows bloqueou o arquivo, se ela tem
permissão de gravar, se a ferramenta já estava aberta — e, no fim, o programa
sobe de verdade e é consultado pela porta que ele mesmo abriu. O relatório é
salvo na Área de Trabalho para ela mandar de volta.

O diagnóstico não adivinha: ele confirma pelo sistema qual porta pertence ao
processo que acabou de subir. Varrer a faixa de portas seria mais simples e
diria "funcionou" quando quem respondeu foi a instalação de outra pasta — que
é justamente um dos problemas que ele existe para encontrar.

As causas que aparecem na prática, em ordem de frequência:

| O que a pessoa fez | O que ela vê | O que o diagnóstico diz |
|---|---|---|
| Clicou em "Baixar" em vez de "Adicionar atalho" | abre, mas sozinha | pasta em Downloads, cópia solta |
| Abriu o `.exe` de dentro do `.zip` | não abre, ou some depois | zip aberto por cima, não é pasta |
| Copiou só o `.exe` | "não encontrei a pasta _app" | falta `_app` ao lado |
| Sincronização pela metade | não abre, ou abre vazia | arquivos ainda só na nuvem |
| Arquivo veio por e-mail | "o Windows protegeu seu PC" | `.exe` bloqueado — e corrige |
| Já estava aberta | nada acontece no duplo clique | já rodando, ícone junto ao relógio |
| Duas pastas da mesma ferramenta | o colega não vê o trabalho dela | as duas instalações, com o caminho |

Para diagnosticar uma pasta que não seja a sua, sem copiar nada para dentro
dela:

```powershell
.\ferramentas\Diagnostico.ps1 -Pasta "C:\Users\...\Pasta-Compartilhada"
```

---

## Licença

MIT — ver [LICENSE](LICENSE).
