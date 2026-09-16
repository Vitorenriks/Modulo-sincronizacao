// aplicacao/log.js - o caso de uso, e a unica parte de _app/ que conversa
// com o executavel. O dominio nao sabe que existe um arquivo; a tela nao
// sabe que existe um POST. Quem costura os dois e este arquivo.
//
// Nao ha uma linha de regra de negocio aqui: `zerar` e `aplicar` chegam de
// fora, por parametro. E o que permite trocar a aplicacao inteira sem
// encostar neste arquivo - e por isso PERSONALIZAR.md manda mante-lo.
//
// O MODELO: nada de "salvar o documento". A aplicacao manda OPERACOES
// ("criei o cartao X", "movi o cartao X para Feito"), e o estado da tela e o
// resultado de tocar todas as operacoes de todo mundo, na ordem, desde o
// comeco. Isso e o que faz duas pessoas mexendo ao mesmo tempo, em maquinas
// diferentes, com o OneDrive sincronizando quando da vontade, chegarem na
// MESMA tela - sem ninguem sobrescrever ninguem.
//
// A ORDEM e sempre a mesma em qualquer maquina: horario UTC, e em empate o
// autor e a sequencia. Empate de horario acontece (dois cliques no mesmo
// milissegundo em maquinas diferentes), e sem criterio de desempate as duas
// maquinas montariam a mesma lista em ordens diferentes.
//
// O RECALCULO e do zero. Mudou alguma coisa na pasta? Zera o estado e toca
// o log inteiro de novo. Parece desperdicio e nao e: sao milhares de linhas,
// o navegador faz isso em milissegundos, e em troca nao existe a classe de
// bug mais cara desse tipo de aplicacao - o estado que foi ficando errado
// aos poucos e ninguem sabe desde quando.

function criarLog(opcoes) {
  var zerar     = opcoes.zerar;              // () => estado novo e vazio
  var aplicar   = opcoes.aplicar;            // (estado, op, meta) => void
  var aoMudar   = opcoes.aoMudar;            // (estado, info) => void
  var intervalo = opcoes.intervalo || 2000;  // de quanto em quanto tempo conferir

  var estado = zerar();
  var versaoVista = null;
  var pendentes = [];        // enviadas, ainda nao vistas de volta no log
  var lendo = false;

  // De onde veio o ultimo erro. Sem isso, uma leitura bem-sucedida logo depois
  // de uma gravacao recusada apaga o aviso antes de a pessoa ler - e ela fica
  // sem entender por que o que digitou sumiu da tela. Erro de leitura some
  // sozinho quando o contato volta; erro de gravacao fica ate a proxima
  // tentativa.
  var erroEhDeConexao = false;

  var eu = {
    usuario: '?',
    podeGravar: false,
    marca: { nome: 'Aplicação', organizacao: '', icone: '' },
    autores: [],
    erro: null
  };

  function pegar(caminho) {
    return fetch(caminho, { cache: 'no-store' });
  }

  // Toda escrita leva o X-App-Local. O servidor recusa POST sem ele: e o que
  // impede um site aberto em outra aba de descobrir a porta local e escrever
  // no log da equipe. Cabecalho personalizado obriga o navegador a pedir
  // preflight, e preflight o servidor nao responde.
  function enviarLinhas(linhas) {
    return fetch('/api/ops', {
      method: 'POST',
      headers: { 'Content-Type': 'text/plain', 'X-App-Local': '1' },
      body: linhas.join('\n')
    });
  }

  function ordenar(eventos) {
    eventos.sort(function (a, b) {
      if (a.em !== b.em) return a.em < b.em ? -1 : 1;
      if (a.autor !== b.autor) return a.autor < b.autor ? -1 : 1;
      return (a.seq || 0) - (b.seq || 0);
    });
    return eventos;
  }

  function interpretar(texto) {
    var eventos = [];
    var linhas = texto.split('\n');
    for (var i = 0; i < linhas.length; i++) {
      var linha = linhas[i].trim();
      if (!linha) continue;
      try {
        var ev = JSON.parse(linha);
        if (ev && ev.op) eventos.push(ev);
      } catch (e) {
        // Linha quebrada no meio de uma sincronizacao. O servidor ja descarta
        // quase tudo; o que passar, passa aqui. Uma linha ilegivel nao pode
        // derrubar a tela inteira.
      }
    }
    return ordenar(eventos);
  }

  function reconstruir(eventos) {
    estado = zerar();
    for (var i = 0; i < eventos.length; i++) {
      try { aplicar(estado, eventos[i].op, eventos[i]); }
      catch (e) { }  // operacao de uma versao futura da aplicacao: ignora
    }
    // As minhas que ainda nao voltaram do disco entram por ultimo, para a tela
    // nao "engolir" o que acabei de fazer enquanto o arquivo sincroniza.
    for (var j = 0; j < pendentes.length; j++) {
      try { aplicar(estado, pendentes[j].op, pendentes[j].meta); } catch (e) { }
    }
    return eventos;
  }

  function limparPendentes(eventos) {
    if (!pendentes.length) return;
    var vistos = {};
    for (var i = 0; i < eventos.length; i++) {
      if (eventos[i].op && eventos[i].op._id) vistos[eventos[i].op._id] = true;
    }
    pendentes = pendentes.filter(function (p) { return !vistos[p.op._id]; });
  }

  function recarregar(forcar) {
    if (lendo) return Promise.resolve(false);
    lendo = true;
    return pegar('/api/versao')
      .then(function (r) { return r.json(); })
      .then(function (v) {
        eu.autores = v.autores || [];
        eu.usuario = v.eu || eu.usuario;
        if (!forcar && v.versao === versaoVista) return false;
        versaoVista = v.versao;
        return pegar('/api/logs')
          .then(function (r) { return r.text(); })
          .then(function (texto) {
            var eventos = interpretar(texto);
            limparPendentes(eventos);
            reconstruir(eventos);
            if (erroEhDeConexao) { eu.erro = null; erroEhDeConexao = false; }
            aoMudar(estado, { eu: eu, total: eventos.length });
            return true;
          });
      })
      .catch(function (e) {
        // O executavel foi fechado pela bandeja, ou a maquina hibernou. A tela
        // continua mostrando o ultimo estado bom, com o aviso.
        eu.erro = 'Sem contato com o servidor. O programa ainda está aberto na bandeja?';
        erroEhDeConexao = true;
        aoMudar(estado, { eu: eu, total: -1 });
        return false;
      })
      .then(function (r) { lendo = false; return r; });
  }

  // Envia uma operacao. Aplica na tela na hora (a pessoa nao pode esperar o
  // disco para ver o proprio clique) e so depois grava. Se a gravacao falhar,
  // desfaz: e melhor a linha sumir da tela do que ficar la fingindo que
  // existe no arquivo.
  function enviar(op) {
    if (!eu.podeGravar) return Promise.resolve(false);

    eu.erro = null;            // tentativa nova, aviso velho sai da tela
    erroEhDeConexao = false;

    op._id = eu.usuario + '-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 7);
    var meta = { autor: eu.usuario, em: new Date().toISOString(), seq: 0, op: op };
    var pendente = { op: op, meta: meta };
    pendentes.push(pendente);

    try { aplicar(estado, op, meta); } catch (e) { }
    aoMudar(estado, { eu: eu, total: -1 });

    return enviarLinhas([JSON.stringify(op)])
      .then(function (r) {
        if (!r.ok) throw new Error('o servidor recusou a gravação (HTTP ' + r.status + ')');
        return r.json();
      })
      .then(function () { return recarregar(true); })
      .then(function () { return true; })
      .catch(function (e) {
        pendentes = pendentes.filter(function (p) { return p !== pendente; });
        eu.erro = 'Não consegui gravar: ' + e.message;
        erroEhDeConexao = false;   // nao some na proxima leitura: a pessoa precisa ver
        return recarregar(true).then(function () { return false; });
      });
  }

  function iniciar() {
    return Promise.all([
      pegar('/api/marca').then(function (r) { return r.json(); }),
      pegar('/api/quem').then(function (r) { return r.json(); })
    ]).then(function (res) {
      eu.marca = res[0];
      eu.usuario = res[1].usuario;
      eu.podeGravar = !!res[1].grava;
      return recarregar(true);
    }).then(function () {
      // Conferencia por tempo, nao por evento: e uma pasta sincronizada, nao
      // um banco de dados - ninguem avisa quando o arquivo do colega chega.
      // O ritmo faz parte do caso de uso, entao o relogio fica aqui. Evento
      // de janela (voltar para a aba) nao: aquilo e tela, e quem liga e o
      // principal.js.
      setInterval(function () { recarregar(false); }, intervalo);
      return eu;
    });
  }

  return {
    iniciar: iniciar,
    enviar: enviar,
    recarregar: recarregar,
    get estado() { return estado; },
    get eu() { return eu; }
  };
}
