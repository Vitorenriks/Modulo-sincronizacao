// teste-convergencia.js - prova a promessa central do produto.
//
// O argumento de venda do Nucleo e "duas pessoas mexem ao mesmo tempo e ninguem
// apaga ninguem". Isso nao e uma frase de marketing: e uma propriedade do
// modelo de log, e ou ela vale sempre, ou nao vale nada. Este arquivo verifica
// que ela vale - inclusive nos casos que so aparecem em campo, semanas depois:
// arquivo que chega fora de ordem, linha duplicada pela sincronizacao, linha
// truncada no meio da gravacao, gravacao recusada por pasta somente-leitura.
//
// Roda o `modelo/_app/aplicacao/log.js` de verdade, sem copia e sem
// adaptacao - o que esta sendo testado e o arquivo que vai dentro de cada
// projeto entregue.
//
// Uso:  node ferramentas\teste-convergencia.js

const fs = require('fs');
const path = require('path');

const CAMINHO_LOG = path.join(__dirname, '..', 'modelo', '_app', 'aplicacao', 'log.js');

// Uma pasta compartilhada de mentira: um vetor de linhas por pessoa, que e
// exatamente o que o servidor tem no disco.
function criarPasta() {
  return { arquivos: {}, seq: {} };
}

function gravar(pasta, autor, op, em) {
  pasta.seq[autor] = (pasta.seq[autor] || 0) + 1;
  if (!pasta.arquivos[autor]) pasta.arquivos[autor] = [];
  pasta.arquivos[autor].push(JSON.stringify({
    autor: autor,
    seq: pasta.seq[autor],
    em: em,
    op: op
  }));
}

// O servidor de mentira. `ordemDosArquivos` existe porque o servidor real
// devolve os arquivos na ordem do nome, e o que garante que a maquina da Ana e
// a do Bruno cheguem na mesma tela e a ORDENACAO no cliente - nao a ordem em
// que as linhas chegaram. Embaralhar aqui e o coracao do teste.
function criarServidor(pasta, opcoes) {
  opcoes = opcoes || {};
  const eu = opcoes.eu || 'ana';
  let podeGravar = opcoes.podeGravar !== false;
  let recusarPost = !!opcoes.recusarPost;
  let ordemDosArquivos = opcoes.ordemDosArquivos || null;

  function nomes() {
    const lista = Object.keys(pasta.arquivos);
    if (ordemDosArquivos) {
      return ordemDosArquivos.filter(a => lista.indexOf(a) >= 0)
             .concat(lista.filter(a => ordemDosArquivos.indexOf(a) < 0));
    }
    return lista.sort();
  }

  function carimbo() {
    return nomes().map(a => a + ':' + pasta.arquivos[a].length).join('|');
  }

  function json(objeto) {
    return Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(objeto) });
  }

  return {
    trocarOrdem(nova) { ordemDosArquivos = nova; },
    definirRecusa(v)  { recusarPost = v; },
    fetch(caminho, opcoes2) {
      if (caminho === '/api/marca') return json({ nome: 'Teste', organizacao: '', icone: '' });
      if (caminho === '/api/quem')  return json({ usuario: eu, porta: 1, grava: podeGravar });
      if (caminho === '/api/versao') {
        return json({
          versao: carimbo(),
          eu: eu,
          autores: nomes().map(a => ({ autor: a, em: '', bytes: 0 }))
        });
      }
      if (caminho === '/api/logs') {
        const texto = nomes().map(a => pasta.arquivos[a].join('\n')).join('\n') + '\n';
        return Promise.resolve({ ok: true, status: 200, text: () => Promise.resolve(texto) });
      }
      if (caminho === '/api/ops') {
        if (recusarPost) {
          return Promise.resolve({ ok: false, status: 503, json: () => Promise.resolve({ erro: 'sem permissão' }) });
        }
        const agora = new Date().toISOString();
        opcoes2.body.split('\n').filter(l => l.trim()).forEach(l => gravar(pasta, eu, JSON.parse(l), agora));
        return json({ gravadas: 1, versao: carimbo() });
      }
      return Promise.reject(new Error('rota desconhecida: ' + caminho));
    }
  };
}

// O log.js de verdade, carregado com o ambiente do navegador substituido.
// Sao duas coisas so - `fetch` e `setInterval` - e essa lista curta e a
// prova de que a camada de aplicacao nao encosta em tela: se um dia ela
// precisar de `document` ou de `window` para carregar, a fronteira vazou.
function carregarCriarLog(servidor) {
  const fonte = fs.readFileSync(CAMINHO_LOG, 'utf8');
  const semRelogio = () => 0;   // o teste chama recarregar() na mao
  return new Function('fetch', 'setInterval',
                      fonte + '\nreturn criarLog;')(servidor.fetch, semRelogio);
}

// Um reduzidor simples, com as regras que PERSONALIZAR.md manda seguir:
// ignorar o que ja existe, ignorar o que ja foi apagado.
function zerar() { return { itens: {}, ordem: [] }; }

function aplicar(estado, op, meta) {
  if (op.t === 'nova') {
    if (estado.itens[op.id]) return;
    estado.itens[op.id] = { id: op.id, texto: op.texto, autor: meta.autor };
    estado.ordem.push(op.id);
    return;
  }
  const item = estado.itens[op.id];
  if (!item) return;
  if (op.t === 'texto') item.texto = op.texto;
  if (op.t === 'apagar') {
    delete estado.itens[op.id];
    const i = estado.ordem.indexOf(op.id);
    if (i >= 0) estado.ordem.splice(i, 1);
  }
}

function retrato(estado) {
  return JSON.stringify(estado.ordem.map(id => estado.itens[id]));
}

async function montar(pasta, opcoes) {
  const servidor = criarServidor(pasta, opcoes);
  const criarLog = carregarCriarLog(servidor);
  const log = criarLog({ zerar, aplicar, aoMudar() {}, intervalo: 999999 });
  await log.iniciar();
  return { log, servidor };
}

let passou = 0, falhou = 0;

function conferir(nome, condicao, detalhe) {
  if (condicao) { passou++; console.log('  ok    ' + nome); }
  else { falhou++; console.log('  FALHA ' + nome + (detalhe ? '\n        ' + detalhe : '')); }
}

async function testes() {

  // 1. Convergencia: a mesma pasta, lida em ordens diferentes, da a mesma tela.
  {
    const pasta = criarPasta();
    gravar(pasta, 'ana',   { t: 'nova', id: 'a', texto: 'primeiro' },  '2026-01-01T10:00:00.000Z');
    gravar(pasta, 'bruno', { t: 'nova', id: 'b', texto: 'segundo' },   '2026-01-01T10:00:01.000Z');
    gravar(pasta, 'ana',   { t: 'texto', id: 'b', texto: 'corrigido' },'2026-01-01T10:00:02.000Z');
    gravar(pasta, 'bruno', { t: 'nova', id: 'c', texto: 'terceiro' },  '2026-01-01T10:00:03.000Z');

    const naOrdem   = await montar(pasta, { eu: 'ana',   ordemDosArquivos: ['ana', 'bruno'] });
    const invertida = await montar(pasta, { eu: 'bruno', ordemDosArquivos: ['bruno', 'ana'] });

    conferir('convergência: ordem dos arquivos não muda o resultado',
             retrato(naOrdem.log.estado) === retrato(invertida.log.estado),
             retrato(naOrdem.log.estado) + '\n        ' + retrato(invertida.log.estado));

    conferir('convergência: a alteração da Ana sobre o item do Bruno valeu',
             naOrdem.log.estado.itens.b.texto === 'corrigido');
  }

  // 2. Empate de horario: dois cliques no mesmo milissegundo, em maquinas
  //    diferentes. Sem desempate por autor, cada maquina ordenaria de um jeito.
  {
    const pasta = criarPasta();
    const mesmoInstante = '2026-01-01T10:00:00.000Z';
    gravar(pasta, 'ana',   { t: 'nova', id: 'x', texto: 'da ana' },   mesmoInstante);
    gravar(pasta, 'bruno', { t: 'texto', id: 'x', texto: 'do bruno' }, mesmoInstante);

    const a = await montar(pasta, { eu: 'ana',   ordemDosArquivos: ['ana', 'bruno'] });
    const b = await montar(pasta, { eu: 'bruno', ordemDosArquivos: ['bruno', 'ana'] });

    conferir('empate de horário: desempatado por autor, igual nas duas máquinas',
             retrato(a.log.estado) === retrato(b.log.estado),
             retrato(a.log.estado) + '\n        ' + retrato(b.log.estado));
  }

  // 3. Linha duplicada pela sincronizacao e linha truncada no meio da gravacao.
  {
    const pasta = criarPasta();
    gravar(pasta, 'ana', { t: 'nova', id: 'a', texto: 'único' }, '2026-01-01T10:00:00.000Z');
    pasta.arquivos['ana'].push(pasta.arquivos['ana'][0]);          // duplicada
    pasta.arquivos['ana'].push('{"autor":"ana","seq":9,"em":"2026');// truncada
    pasta.arquivos['ana'].push('');                                 // linha vazia

    const { log } = await montar(pasta, { eu: 'ana' });
    conferir('lixo no arquivo não derruba a tela nem duplica o item',
             log.estado.ordem.length === 1 && log.estado.itens.a.texto === 'único',
             retrato(log.estado));
  }

  // 4. Operacao sobre item ja apagado por outra pessoa.
  {
    const pasta = criarPasta();
    gravar(pasta, 'ana',   { t: 'nova',   id: 'a', texto: 'vai sumir' }, '2026-01-01T10:00:00.000Z');
    gravar(pasta, 'ana',   { t: 'apagar', id: 'a' },                     '2026-01-01T10:00:01.000Z');
    gravar(pasta, 'bruno', { t: 'texto',  id: 'a', texto: 'tarde demais' },'2026-01-01T10:00:02.000Z');

    const { log } = await montar(pasta, { eu: 'ana' });
    conferir('alteração sobre item apagado é ignorada sem erro',
             log.estado.ordem.length === 0, retrato(log.estado));
  }

  // 5. Escrita otimista: aparece na hora e continua la depois de reler o disco.
  {
    const pasta = criarPasta();
    const { log } = await montar(pasta, { eu: 'ana' });
    await log.enviar({ t: 'nova', id: 'n1', texto: 'na hora' });
    conferir('escrita otimista: item aparece e sobrevive à releitura',
             log.estado.ordem.length === 1 && log.estado.itens.n1.texto === 'na hora',
             retrato(log.estado));
    conferir('escrita otimista: não duplicou ao voltar do disco',
             Object.keys(log.estado.itens).length === 1);
  }

  // 6. Pasta somente-leitura: o POST volta 503 e a tela tem que DESFAZER.
  //    E o caso que, se der errado, mostra ao usuario um dado que nao existe.
  {
    const pasta = criarPasta();
    const { log, servidor } = await montar(pasta, { eu: 'ana' });
    servidor.definirRecusa(true);
    await log.enviar({ t: 'nova', id: 'fantasma', texto: 'não gravou' });

    conferir('gravação recusada: o item é desfeito na tela',
             log.estado.ordem.length === 0, retrato(log.estado));
    conferir('gravação recusada: a pessoa é avisada',
             typeof log.eu.erro === 'string' && log.eu.erro.indexOf('gravar') >= 0,
             String(log.eu.erro));
  }

  // 7. Pasta compartilhada como "Pode exibir": nem tenta gravar.
  {
    const pasta = criarPasta();
    const { log } = await montar(pasta, { eu: 'ana', podeGravar: false });
    const resultado = await log.enviar({ t: 'nova', id: 'x', texto: 'nem tenta' });
    conferir('modo leitura: enviar() não faz nada e devolve false',
             resultado === false && log.estado.ordem.length === 0);
  }

  console.log('');
  console.log('  ' + passou + ' passaram, ' + falhou + ' falharam');
  process.exit(falhou ? 1 : 0);
}

console.log('');
console.log('  Convergência do log (modelo/_app/aplicacao/log.js)');
console.log('');
testes().catch(e => { console.error(e); process.exit(1); });
