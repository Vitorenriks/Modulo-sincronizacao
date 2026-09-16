// principal.js - a raiz de composicao: o unico arquivo que conhece as tres
// camadas ao mesmo tempo.
//
// Aqui, e so aqui, o dominio, o protocolo e a tela se encontram:
//
//   dominio/regras.js    zerar() e aplicar()  - a regra pura
//   aplicacao/log.js     criarLog()           - ordem, mesclagem, gravacao
//   tela/quadro.js       criarTela()          - os elementos na pagina
//
// A tela recebe `acoes` em vez de chamar o log direto. E o que mantem a
// dependencia apontando para dentro: quadro.js sabe que existe "criar um
// cartao", e nao sabe que isso vira uma linha JSONL num arquivo da pasta.
// Trocar o transporte mexe aqui, nao na tela.

var Tela = criarTela({
  criar:  function (texto, colunaId) { Log.enviar({ t: 'nova', id: novoId(), texto: texto, coluna: colunaId }); },
  mover:  function (id, colunaId)    { Log.enviar({ t: 'mover', id: id, coluna: colunaId }); },
  editar: function (id, texto)       { Log.enviar({ t: 'texto', id: id, texto: texto }); },
  apagar: function (id)              { Log.enviar({ t: 'apagar', id: id }); }
});

var Log = criarLog({
  zerar: zerar,
  aplicar: aplicar,
  aoMudar: Tela.desenhar,
  intervalo: 2000
});

Log.iniciar();

// Voltar para a aba e o momento em que a pessoa mais espera ver o que mudou;
// nao faz sentido deixar ela olhando dados velhos ate o proximo tique. E um
// evento de janela, nao uma regra: por isso mora aqui, e nao no log.js.
window.addEventListener('focus', function () { Log.recarregar(false); });
