// tela/quadro.js - desenha o estado, e so isso.
//
// Esta camada e a mais de fora do lado do navegador. Le o estado e monta os
// elementos; nao muda o estado, nao fala com o servidor e nao sabe o que e
// uma operacao. Um clique nao grava nada aqui: chama uma das funcoes de
// `acoes`, que o principal.js entrega ja ligada ao caso de uso.
//
// E por isso que a dependencia aponta para dentro: a tela conhece o nome das
// acoes, e nao o caminho ate o disco. Trocar o quadro por outra tela nao
// encosta em dominio/ nem em aplicacao/.
//
// A busca que o ARQUITETURA.md descreve tem que sair vazia neste arquivo: se
// o nome do objeto de log aparecer aqui, a tela furou as acoes.

function criarTela(acoes) {

  function texto(el, valor) { el.textContent = valor; }

  function desenhar(estado, info) {
    var eu = info.eu;

    document.title = eu.marca.nome || 'Aplicação';
    texto(document.getElementById('titulo'), eu.marca.nome || 'Aplicação');
    texto(document.getElementById('subtitulo'),
          eu.marca.organizacao ? eu.marca.organizacao : '');

    if (eu.marca.icone) {
      var logo = document.getElementById('logo');
      logo.src = eu.marca.icone;
      logo.hidden = false;
    }

    texto(document.getElementById('quem'), eu.usuario + (eu.podeGravar ? '' : ' · só leitura'));
    document.getElementById('quem').className = 'etiqueta' + (eu.podeGravar ? '' : ' etiqueta-leitura');

    var outros = (eu.autores || []).filter(function (a) { return a.autor !== eu.usuario; });
    texto(document.getElementById('pessoas'),
          outros.length ? outros.length + (outros.length === 1 ? ' outra pessoa neste quadro' : ' outras pessoas neste quadro') : '');

    var aviso = document.getElementById('aviso');
    if (eu.erro) { texto(aviso, eu.erro); aviso.hidden = false; aviso.className = 'aviso aviso-erro'; }
    else if (!eu.podeGravar) {
      texto(aviso, 'Esta pasta foi compartilhada como somente leitura. Dá para acompanhar tudo, mas não para alterar. Peça permissão de edição a quem compartilhou.');
      aviso.hidden = false; aviso.className = 'aviso';
    } else { aviso.hidden = true; }

    var quadro = document.getElementById('quadro');
    quadro.innerHTML = '';
    for (var i = 0; i < COLUNAS.length; i++) quadro.appendChild(montarColuna(estado, COLUNAS[i], eu));

    var total = Object.keys(estado.cartoes).length;
    texto(document.getElementById('contagem'),
          total + (total === 1 ? ' cartão' : ' cartões'));
  }

  function montarColuna(estado, coluna, eu) {
    var div = document.createElement('section');
    div.className = 'coluna';

    var cartoes = estado.ordem
      .map(function (id) { return estado.cartoes[id]; })
      .filter(function (c) { return c && c.coluna === coluna.id; });

    var cab = document.createElement('h2');
    cab.innerHTML = '';
    cab.appendChild(document.createTextNode(coluna.titulo));
    var conta = document.createElement('span');
    conta.className = 'conta';
    conta.textContent = cartoes.length;
    cab.appendChild(conta);
    div.appendChild(cab);

    for (var i = 0; i < cartoes.length; i++) div.appendChild(montarCartao(cartoes[i], coluna, eu));

    if (eu.podeGravar) {
      var form = document.createElement('form');
      form.className = 'novo';
      var campo = document.createElement('input');
      campo.type = 'text';
      campo.placeholder = 'Adicionar em ' + coluna.titulo.toLowerCase() + '…';
      campo.maxLength = 500;
      form.appendChild(campo);
      form.onsubmit = function (e) {
        e.preventDefault();
        var t = campo.value.trim();
        if (!t) return;
        campo.value = '';
        acoes.criar(t, coluna.id);
      };
      div.appendChild(form);
    }
    return div;
  }

  function montarCartao(c, coluna, eu) {
    var art = document.createElement('article');
    art.className = 'cartao';

    var p = document.createElement('p');
    p.textContent = c.texto;
    if (eu.podeGravar) {
      p.title = 'Clique para editar';
      p.onclick = function () {
        var novo = prompt('Texto do cartão:', c.texto);
        if (novo === null) return;
        novo = novo.trim();
        if (!novo || novo === c.texto) return;
        acoes.editar(c.id, novo);
      };
    }
    art.appendChild(p);

    var pe = document.createElement('div');
    pe.className = 'pe';

    var autor = document.createElement('span');
    autor.className = 'fraco';
    autor.textContent = c.autor;
    pe.appendChild(autor);

    if (eu.podeGravar) {
      var acoesEl = document.createElement('span');
      acoesEl.className = 'acoes';
      for (var i = 0; i < COLUNAS.length; i++) {
        (function (destino) {
          if (destino.id === coluna.id) return;
          var b = document.createElement('button');
          b.textContent = destino.titulo;
          b.title = 'Mover para ' + destino.titulo;
          b.onclick = function () { acoes.mover(c.id, destino.id); };
          acoesEl.appendChild(b);
        })(COLUNAS[i]);
      }
      var x = document.createElement('button');
      x.className = 'apagar';
      x.textContent = '×';
      x.title = 'Apagar';
      x.onclick = function () {
        if (confirm('Apagar este cartão?')) acoes.apagar(c.id);
      };
      acoesEl.appendChild(x);
      pe.appendChild(acoesEl);
    }

    art.appendChild(pe);
    return art;
  }

  return { desenhar: desenhar };
}
