// dominio/regras.js - a regra de negocio do exemplo, e so ela.
//
// Esta camada e o centro: nao conhece tela, nao conhece servidor, nao
// conhece o formato do log. Recebe um estado e uma operacao, devolve o
// estado seguinte. Da para testar tudo o que esta aqui sem navegador e sem
// executavel, porque nao ha nada aqui para simular.
//
// Esta aqui para ser apagado. O que vale a pena copiar e o formato:
//
//   1. zerar()   devolve um estado vazio;
//   2. aplicar() recebe UMA operacao e muda o estado - sem tocar na tela.
//
// Separar isso da tela e o que permite recalcular o log inteiro do zero a
// cada mudanca. Se aplicar() mexesse na tela, recalcular piscaria tudo.
//
// As operacoes precisam ser IDEMPOTENTES e completas em si: "mover o cartao
// 7 para feito" reconstroi igual em qualquer maquina, hoje ou daqui a um
// ano. "mover o cartao 7 uma coluna para a direita" nao - depende de onde
// ele estava, e duas pessoas fazendo isso ao mesmo tempo dao resultados
// diferentes em cada maquina.

var COLUNAS = [
  { id: 'fazer',  titulo: 'A fazer'  },
  { id: 'fazendo', titulo: 'Fazendo' },
  { id: 'feito',  titulo: 'Feito'    }
];

function zerar() {
  return { cartoes: {}, ordem: [] };
}

function aplicar(estado, op, meta) {
  if (op.t === 'nova') {
    if (estado.cartoes[op.id]) return;           // linha repetida: ignora
    estado.cartoes[op.id] = {
      id: op.id,
      texto: String(op.texto || '').slice(0, 500),
      coluna: op.coluna || 'fazer',
      autor: meta.autor,
      em: meta.em
    };
    estado.ordem.push(op.id);
    return;
  }

  var c = estado.cartoes[op.id];
  if (!c) return;                                 // alteracao de algo ja apagado

  if (op.t === 'mover')  { c.coluna = op.coluna; c.mexeu = meta.autor; }
  if (op.t === 'texto')  { c.texto = String(op.texto || '').slice(0, 500); c.mexeu = meta.autor; }
  if (op.t === 'apagar') {
    delete estado.cartoes[op.id];
    var i = estado.ordem.indexOf(op.id);
    if (i >= 0) estado.ordem.splice(i, 1);
  }
}

function novoId() {
  return Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
}
