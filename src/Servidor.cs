// Servidor.cs - o executavel que fica DENTRO da pasta compartilhada.
//
// E um host local para aplicacoes internas. Nao sabe o que a aplicacao faz:
// serve os arquivos de _app/ no navegador, guarda um log de operacoes em
// dados/ e diz quando esse log muda. Toda a regra de negocio mora no
// navegador - e o que permite trocar a aplicacao inteira sem recompilar
// nada aqui.
//
// Cada pessoa da duplo clique no executavel da PROPRIA maquina, dentro da
// pasta compartilhada. Ele:
//
//   1. acha uma porta livre em 127.0.0.1 (so local, nunca na rede);
//   2. serve a aplicacao a partir de _app/;
//   3. le TODOS os dados/<prefixo>*.jsonl e devolve como um log so;
//   4. anexa as operacoes novas APENAS no arquivo desta pessoa;
//   5. fica na bandeja, ao lado do relogio, ate alguem mandar sair.
//
// POR QUE UM ARQUIVO POR PESSOA (dados/<prefixo><usuario>@<maquina>.jsonl):
// duas maquinas gravando o MESMO arquivo e o que faz o OneDrive criar
// "copia em conflito" e alguem perder trabalho sem perceber. Aqui cada
// maquina so escreve no arquivo dela, e a tela mostra a soma de todos.
//
// SO-LEITURA SAI DE GRACA: se a pasta foi compartilhada como "Pode exibir",
// o Windows recusa a escrita, o POST /api/ops volta em erro e a aplicacao
// entra em modo de leitura sozinha. Quem nega e a permissao da pasta, nao
// uma variavel no JavaScript.
//
// NADA DE MARCA ESTA COMPILADO AQUI. Nome, organizacao, icone, porta e
// prefixo dos dados vem do marca.json ao lado do executavel. Trocar a marca
// de uma instalacao e editar um arquivo de texto e trocar um .ico - nao
// precisa de compilador. O build.ps1 embute uma copia do icone no
// executavel para o caso de o arquivo sumir.
//
// Para compilar, ver build.ps1 na raiz do projeto.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Reflection;
using System.Globalization;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Windows.Forms;

class Servidor
{
    // A marca. Lida uma vez, na abertura, do marca.json ao lado do .exe.
    // Todo campo tem padrao: arquivo ausente ou torto nao impede de abrir.
    static string Nome = "Aplicação";         // aparece na bandeja e nos avisos
    static string Organizacao = "";           // opcional; entra no titulo depois do travessao
    static string Prefixo = "dados.";         // prefixo dos arquivos de log
    static string ArquivoIcone = "marca.ico"; // .ico ao lado do .exe (opcional)
    static int PortaInicial = 8850;
    static int FaixaPortas = 40;

    static string PastaExe;
    static string PastaApp;
    static string PastaDados;
    static string MeuArquivo;
    static string Usuario;
    static int Porta;
    static int Seq;
    static readonly object Trava = new object();
    static volatile bool Rodando = true;
    static NotifyIcon Bandeja;

    // Guarda contra outra aba/site falando com a porta local: um site
    // qualquer nao consegue mandar cabecalho personalizado sem preflight, e
    // preflight aqui nao e respondido.
    const string CABECALHO = "X-App-Local:";

    // Escrita de pagina inteira so acontece na resposta; o corpo e sempre UTF-8
    // sem BOM, porque BOM no meio de um JSONL quebra o JSON.parse do navegador.
    static readonly Encoding Utf8 = new UTF8Encoding(false);

    static Mutex Sozinho;

    static string Titulo()
    {
        return Organizacao.Length > 0 ? Nome + " — " + Organizacao : Nome;
    }

    [STAThread]
    static void Main(string[] args)
    {
        try
        {
            PastaExe = Path.GetDirectoryName(Application.ExecutablePath);
            PastaApp = Path.Combine(PastaExe, "_app");
            PastaDados = Path.Combine(PastaExe, "dados");

            LerMarca(Path.Combine(PastaExe, "marca.json"));

            if (!Directory.Exists(PastaApp))
            {
                MessageBox.Show(
                    "Não encontrei a pasta _app ao lado do executável.\n\n" +
                    "O executável precisa ficar DENTRO da pasta compartilhada, junto de _app e dados.\n\n" +
                    "Procurei em:\n" + PastaApp,
                    Titulo(), MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            Directory.CreateDirectory(PastaDados);

            // UMA instancia por pasta, por maquina.
            //
            // Dois processos abertos ao mesmo tempo gravariam no MESMO
            // arquivo com dois contadores de sequencia independentes: as
            // duas alteracoes sairiam com o mesmo numero, e a mesclagem
            // descartaria uma delas achando que era linha repetida. Perda
            // de dado, sem erro na tela.
            //
            // Alem de proteger, e o comportamento que a pessoa espera: dar
            // duplo clique de novo reabre a aplicacao, nao abre um segundo
            // programa.
            // --sem-navegador serve para conferir o executavel por script
            // sem abrir uma janela na cara de ninguem.
            bool abrirNavegador = true;
            for (int i = 0; i < args.Length; i++)
                if (args[i] == "--sem-navegador") abrirNavegador = false;

            string chave = Assinatura(PastaExe);
            bool primeiro;
            Sozinho = new Mutex(true, "Local\\AppLocal-" + chave, out primeiro);
            if (!primeiro)
            {
                ReabrirExistente(chave, abrirNavegador);
                return;
            }

            Usuario = Limpar(Environment.UserName);
            string maquina = Limpar(Environment.MachineName);
            MeuArquivo = Path.Combine(PastaDados, Prefixo + Usuario + "@" + maquina + ".jsonl");
            Seq = ContarLinhas(MeuArquivo);

            Porta = AcharPorta(PortaInicial);
            if (Porta == 0)
            {
                MessageBox.Show("Não consegui abrir nenhuma porta local entre " + PortaInicial +
                    " e " + (PortaInicial + FaixaPortas - 1) + ".",
                    Titulo(), MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            Thread servidor = new Thread(Servir);
            servidor.IsBackground = true;
            servidor.Start();

            // A porta escolhida fica anotada no temp DA MAQUINA, nao na pasta
            // compartilhada: e informacao local, e nada que so interessa a um
            // computador deve ficar sincronizando para os outros.
            // O nome leva a assinatura da pasta - e o que o segundo duplo
            // clique le para reabrir a janela certa, e nao a de outra pasta.
            try
            {
                File.WriteAllText(Path.Combine(Path.GetTempPath(), "app-local-porta-" + chave + ".txt"),
                                  Porta.ToString(CultureInfo.InvariantCulture));
            }
            catch (Exception) { }

            if (abrirNavegador) Abrir();
            MontarBandeja();
            Application.Run();
        }
        catch (Exception e)
        {
            MessageBox.Show("Falha ao iniciar:\n\n" + e.Message,
                Titulo(), MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        finally
        {
            Rodando = false;
            if (Bandeja != null) Bandeja.Visible = false;
        }
    }

    // marca.json. E um objeto raso de texto e numero - e e lido por um
    // scanner de ~40 linhas em vez de uma biblioteca de JSON de proposito:
    // o arquivo e editado a mao por quem instala, e um erro de virgula nao
    // pode impedir o programa de abrir. Chave desconhecida e ignorada,
    // chave ausente fica no padrao.
    static void LerMarca(string arquivo)
    {
        Dictionary<string, string> m = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        try
        {
            if (File.Exists(arquivo)) m = LerObjetoRaso(File.ReadAllText(arquivo, Encoding.UTF8));
        }
        catch (Exception) { }

        Nome = Texto(m, "nome", Nome);
        Organizacao = Texto(m, "organizacao", Organizacao);
        ArquivoIcone = Texto(m, "icone", ArquivoIcone);
        PortaInicial = Numero(m, "porta", PortaInicial, 1024, 65000);
        FaixaPortas = Numero(m, "faixaPortas", FaixaPortas, 1, 500);

        // O prefixo entra no nome dos arquivos de dados e e recortado de
        // volta em Versao() para achar o autor. Se vier vazio ou com
        // caractere que nao vale em nome de arquivo, o log inteiro vira
        // ilegivel - entao passa pela mesma limpeza do nome de usuario.
        Prefixo = Limpar(Texto(m, "prefixo", "dados")) + ".";
    }

    static string Texto(Dictionary<string, string> m, string chave, string padrao)
    {
        string v;
        if (m.TryGetValue(chave, out v) && v != null && v.Trim().Length > 0) return v.Trim();
        return padrao;
    }

    static int Numero(Dictionary<string, string> m, string chave, int padrao, int min, int max)
    {
        string v;
        int n;
        if (m.TryGetValue(chave, out v) && int.TryParse(v.Trim(), NumberStyles.Integer,
            CultureInfo.InvariantCulture, out n) && n >= min && n <= max) return n;
        return padrao;
    }

    // Le "chave": "valor" e "chave": numero do primeiro nivel. Objeto ou
    // lista aninhada e ignorado - esta liberado no arquivo para quem quiser
    // guardar configuracao da propria aplicacao junto da marca.
    static Dictionary<string, string> LerObjetoRaso(string texto)
    {
        Dictionary<string, string> m = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        int i = 0, profundidade = 0;
        while (i < texto.Length)
        {
            char c = texto[i];
            if (c == '{' || c == '[') { profundidade++; i++; continue; }
            if (c == '}' || c == ']') { profundidade--; i++; continue; }
            if (c != '"' || profundidade != 1) { i++; continue; }

            string chave = LerTexto(texto, ref i);
            while (i < texto.Length && char.IsWhiteSpace(texto[i])) i++;
            if (i >= texto.Length || texto[i] != ':') continue;
            i++;
            while (i < texto.Length && char.IsWhiteSpace(texto[i])) i++;
            if (i >= texto.Length) break;

            if (texto[i] == '"') { m[chave] = LerTexto(texto, ref i); }
            else if (texto[i] == '{' || texto[i] == '[') { }  // aninhado: o laco cuida
            else
            {
                int inicio = i;
                while (i < texto.Length && texto[i] != ',' && texto[i] != '}' && texto[i] != ']') i++;
                m[chave] = texto.Substring(inicio, i - inicio).Trim();
            }
        }
        return m;
    }

    // Entra no abre-aspas e sai depois do fecha-aspas, resolvendo as escapas
    // que o JSON permite.
    static string LerTexto(string texto, ref int i)
    {
        StringBuilder sb = new StringBuilder();
        i++;
        while (i < texto.Length)
        {
            char c = texto[i++];
            if (c == '"') break;
            if (c != '\\') { sb.Append(c); continue; }
            if (i >= texto.Length) break;
            char e = texto[i++];
            if (e == 'n') sb.Append('\n');
            else if (e == 'r') sb.Append('\r');
            else if (e == 't') sb.Append('\t');
            else if (e == 'u' && i + 4 <= texto.Length)
            {
                int cod;
                if (int.TryParse(texto.Substring(i, 4), NumberStyles.HexNumber,
                                 CultureInfo.InvariantCulture, out cod)) sb.Append((char)cod);
                i += 4;
            }
            else sb.Append(e);
        }
        return sb.ToString();
    }

    // Bandeja: o executavel nao tem janela propria de proposito - a janela e
    // o navegador. Sem o icone, nao haveria como fechar o servidor.
    static void MontarBandeja()
    {
        ContextMenu menu = new ContextMenu();
        menu.MenuItems.Add(new MenuItem("Abrir " + Nome, delegate { Abrir(); }));
        menu.MenuItems.Add(new MenuItem("Abrir a pasta de dados", delegate
        {
            try { Process.Start("explorer.exe", "\"" + PastaDados + "\""); } catch { }
        }));
        menu.MenuItems.Add("-");
        menu.MenuItems.Add(new MenuItem("Sair", delegate
        {
            Rodando = false;
            Bandeja.Visible = false;
            Application.Exit();
        }));

        Bandeja = new NotifyIcon();
        Bandeja.Icon = IconeDaMarca(SystemInformation.SmallIconSize);
        // O texto da bandeja tem limite de 63 caracteres; acima disso o
        // NotifyIcon estoura em ArgumentException e o programa nao abre.
        Bandeja.Text = Cortar(Nome + " (porta " + Porta + ")", 63);
        Bandeja.ContextMenu = menu;
        Bandeja.Visible = true;
        Bandeja.DoubleClick += delegate { Abrir(); };
        Bandeja.ShowBalloonTip(4000, Cortar(Titulo(), 63),
            "Aberto no navegador. Para fechar, clique aqui com o botão direito e escolha Sair.",
            ToolTipIcon.Info);
    }

    static string Cortar(string s, int max)
    {
        return s.Length <= max ? s : s.Substring(0, max);
    }

    // Assinatura estavel da pasta: da o mesmo resultado toda vez, na mesma
    // maquina, para a mesma pasta - e resultado diferente para pastas
    // diferentes, para que duas pastas distintas nao briguem pelo mesmo mutex.
    static string Assinatura(string caminho)
    {
        string s = caminho.ToLowerInvariant();
        ulong h = 1469598103934665603UL;
        foreach (char c in s) { h ^= c; h *= 1099511628211UL; }
        return h.ToString("x16");
    }

    // Segundo duplo clique: em vez de abrir outro programa, reabre a janela do
    // que ja esta rodando. Se a porta anotada nao responder (o programa morreu
    // sem apagar o arquivo), nao force: so avise, para ninguem ficar clicando.
    static void ReabrirExistente(string chave, bool abrirNavegador)
    {
        string arquivo = Path.Combine(Path.GetTempPath(), "app-local-porta-" + chave + ".txt");
        int porta = 0;
        try { if (File.Exists(arquivo)) int.TryParse(File.ReadAllText(arquivo).Trim(), out porta); }
        catch (Exception) { }

        if (porta > 0 && Responde(porta))
        {
            if (!abrirNavegador) return;
            try { Process.Start("http://127.0.0.1:" + porta + "/"); return; } catch (Exception) { }
        }
        if (!abrirNavegador) return;

        MessageBox.Show(
            Nome + " já está aberto nesta máquina, mas não consegui trazer a janela de volta.\n\n" +
            "Procure o ícone perto do relógio, clique com o botão direito e escolha " +
            "\"Abrir " + Nome + "\". Se ele não estiver lá, escolha \"Sair\" e abra de novo.",
            Titulo(), MessageBoxButtons.OK, MessageBoxIcon.Information);
    }

    static bool Responde(int porta)
    {
        try
        {
            using (TcpClient c = new TcpClient())
            {
                IAsyncResult r = c.BeginConnect(IPAddress.Loopback, porta, null, null);
                if (!r.AsyncWaitHandle.WaitOne(600)) return false;
                c.EndConnect(r);
                return true;
            }
        }
        catch (Exception) { return false; }
    }

    static void Abrir()
    {
        try { Process.Start("http://127.0.0.1:" + Porta + "/"); }
        catch (Exception e)
        {
            MessageBox.Show("Abra no navegador:  http://127.0.0.1:" + Porta + "/\n\n(" + e.Message + ")",
                Titulo());
        }
    }

    // Servidor. So escuta em 127.0.0.1 - nao aceita conexao de fora da
    // maquina, e por isso nao dispara pedido de liberacao no firewall.
    static int AcharPorta(int inicio)
    {
        for (int p = inicio; p < inicio + FaixaPortas; p++)
        {
            try
            {
                TcpListener teste = new TcpListener(IPAddress.Loopback, p);
                teste.Start();
                teste.Stop();
                return p;
            }
            catch (SocketException) { }
        }
        return 0;
    }

    static void Servir()
    {
        TcpListener ouvinte = new TcpListener(IPAddress.Loopback, Porta);
        ouvinte.Start();
        while (Rodando)
        {
            try
            {
                TcpClient cliente = ouvinte.AcceptTcpClient();
                ThreadPool.QueueUserWorkItem(delegate(object o) { Atender((TcpClient)o); }, cliente);
            }
            catch (Exception) { if (!Rodando) break; }
        }
        try { ouvinte.Stop(); } catch { }
    }

    static void Atender(TcpClient cliente)
    {
        try
        {
            using (cliente)
            using (NetworkStream fluxo = cliente.GetStream())
            {
                cliente.ReceiveTimeout = 15000;
                cliente.SendTimeout = 15000;

                // Cabecalho: le byte a byte ate a linha em branco. Sao poucos
                // bytes e evita ter que adivinhar onde o corpo comeca.
                MemoryStream cabecalho = new MemoryStream();
                int b, casados = 0;
                while (casados < 4 && (b = fluxo.ReadByte()) >= 0)
                {
                    cabecalho.WriteByte((byte)b);
                    if ((casados == 0 || casados == 2) && b == '\r') casados++;
                    else if ((casados == 1 || casados == 3) && b == '\n') casados++;
                    else casados = (b == '\r') ? 1 : 0;
                    if (cabecalho.Length > 32768) return;
                }
                if (cabecalho.Length == 0) return;

                string texto = Utf8.GetString(cabecalho.ToArray());
                string[] linhas = texto.Split(new string[] { "\r\n" }, StringSplitOptions.None);
                string[] pedido = linhas[0].Split(' ');
                if (pedido.Length < 2) return;

                string metodo = pedido[0];
                string caminho = pedido[1];
                int corte = caminho.IndexOf('?');
                if (corte >= 0) caminho = caminho.Substring(0, corte);

                int tamanho = 0;
                bool marcado = false;
                for (int i = 1; i < linhas.Length; i++)
                {
                    string l = linhas[i];
                    if (l.StartsWith("Content-Length:", StringComparison.OrdinalIgnoreCase))
                        int.TryParse(l.Substring(15).Trim(), out tamanho);
                    if (l.StartsWith(CABECALHO, StringComparison.OrdinalIgnoreCase)) marcado = true;
                }

                // Corpo maior que isso nao e operacao: e engano ou ataque. 32 MB
                // de JSONL em um POST so ja seria um log inteiro.
                if (tamanho < 0 || tamanho > 33554432) return;

                string corpo = "";
                if (tamanho > 0)
                {
                    byte[] buf = new byte[tamanho];
                    int lidos = 0;
                    while (lidos < tamanho)
                    {
                        int n = fluxo.Read(buf, lidos, tamanho - lidos);
                        if (n <= 0) break;
                        lidos += n;
                    }
                    corpo = Utf8.GetString(buf, 0, lidos);
                }

                Rotear(fluxo, metodo, caminho, corpo, marcado);
            }
        }
        catch (Exception) { }  // conexao fechada pelo navegador: normal
    }

    static void Rotear(Stream saida, string metodo, string caminho, string corpo, bool marcado)
    {
        if (caminho == "/api/quem")
        {
            // `grava` e a resposta para a pergunta que decide a tela inteira:
            // esta pessoa consegue escrever no log dela? Com a pasta
            // compartilhada como "Pode exibir", nao consegue - e a aplicacao
            // ja abre em modo de leitura, sem oferecer botao que falharia.
            Responder(saida, 200, "application/json",
                "{\"usuario\":" + Aspas(Usuario) + ",\"porta\":" + Porta +
                ",\"grava\":" + (PodeGravar() ? "true" : "false") + "}");
            return;
        }

        // A tela nao repete o nome da instalacao: pergunta para ca. Trocar a
        // marca e editar o marca.json, sem abrir o HTML.
        if (caminho == "/api/marca")
        {
            Responder(saida, 200, "application/json",
                "{\"nome\":" + Aspas(Nome) + ",\"organizacao\":" + Aspas(Organizacao) +
                ",\"icone\":" + Aspas(TemIcone() ? "/marca.ico" : "") + "}");
            return;
        }

        if (caminho == "/api/versao")
        {
            Responder(saida, 200, "application/json", Versao());
            return;
        }

        if (caminho == "/api/logs")
        {
            Responder(saida, 200, "text/plain", Logs());
            return;
        }

        if (caminho == "/api/ops")
        {
            if (metodo != "POST" || !marcado) { Responder(saida, 403, "text/plain", "só pela aplicação"); return; }
            int gravadas;
            try { gravadas = Anexar(corpo); }
            catch (Exception e)
            {
                // Pasta em "Pode exibir", disco cheio, arquivo travado pelo
                // antivirus: a aplicacao precisa SABER que nao gravou, senao
                // mostra na tela uma alteracao que nao existe no arquivo.
                Responder(saida, 503, "application/json",
                    "{\"erro\":" + Aspas(e.Message) + ",\"gravadas\":0}");
                return;
            }
            Responder(saida, 200, "application/json",
                "{\"gravadas\":" + gravadas + ",\"versao\":" + Aspas(Carimbo()) + "}");
            return;
        }

        // O icone da marca sai da raiz para o HTML poder usa-lo como favicon
        // sem copiar o arquivo para dentro de _app/.
        if (caminho == "/marca.ico" && TemIcone())
        {
            Enviar(saida, 200, "image/x-icon", File.ReadAllBytes(CaminhoIcone()));
            return;
        }

        // Arquivos. "/" e a aplicacao; o resto vem de _app/, e so de la.
        string relativo = (caminho == "/" || caminho == "") ? "index.html" : caminho.TrimStart('/');
        relativo = Uri.UnescapeDataString(relativo).Replace('/', Path.DirectorySeparatorChar);
        string raiz = PastaApp.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        string alvo;
        try { alvo = Path.GetFullPath(Path.Combine(PastaApp, relativo)); }
        catch (Exception) { Responder(saida, 404, "text/plain", "não encontrado: " + caminho); return; }

        // A barra no fim da raiz nao e enfeite: sem ela, uma pasta vizinha
        // chamada "_apparte" passaria no teste de prefixo.
        if (!alvo.StartsWith(raiz, StringComparison.OrdinalIgnoreCase) || !File.Exists(alvo))
        {
            Responder(saida, 404, "text/plain", "não encontrado: " + caminho);
            return;
        }
        // O favicon e binario. Lido como texto UTF-8, cada byte que nao forma
        // caractere valido vira '?' na volta e o navegador recebe um .ico
        // picado - a aba fica sem icone e ninguem descobre por que. Por isso
        // binario vai como bytes, sem passar por string; o resto, que e tudo
        // texto, continua como era.
        if (Binario(alvo)) Enviar(saida, 200, Tipo(alvo), File.ReadAllBytes(alvo));
        else Responder(saida, 200, Tipo(alvo), File.ReadAllText(alvo, Encoding.UTF8));
    }

    // Os dados. Tres operacoes e nenhuma interpretacao: anexar linha, devolver
    // todas as linhas, dizer se mudou alguma coisa.

    // Consegue escrever no log desta pessoa? A resposta sai de TENTAR abrir
    // o arquivo para anexar - nao de ler atributo nem de conferir ACL.
    // "Pode exibir" no OneDrive, arquivo marcado como somente-leitura e
    // pasta sem permissao dao erros diferentes; abrir para escrita cobre os
    // tres de uma vez. Nao escreve byte nenhum: abre e fecha.
    static bool PodeGravar()
    {
        try
        {
            using (FileStream f = new FileStream(MeuArquivo, FileMode.Append,
                                                 FileAccess.Write, FileShare.ReadWrite))
            {
                return true;
            }
        }
        catch (Exception) { return false; }
    }

    // Os arquivos do log, em ordem estavel. GetFiles com padrao pode trazer
    // vizinhos por causa do nome curto 8.3 do Windows, entao o prefixo e
    // conferido de novo aqui - e ele que recorta o autor mais abaixo.
    static string[] ArquivosDeLog()
    {
        List<string> lista = new List<string>();
        try
        {
            foreach (string f in Directory.GetFiles(PastaDados, Prefixo + "*.jsonl"))
            {
                string nome = Path.GetFileName(f);
                if (nome.Length > Prefixo.Length + 6 &&
                    nome.StartsWith(Prefixo, StringComparison.OrdinalIgnoreCase) &&
                    nome.EndsWith(".jsonl", StringComparison.OrdinalIgnoreCase))
                    lista.Add(f);
            }
        }
        catch (Exception) { }
        string[] arquivos = lista.ToArray();
        Array.Sort(arquivos, StringComparer.OrdinalIgnoreCase);
        return arquivos;
    }

    // Carimbo do estado da pasta: nome + tamanho + data de cada log. Se nada
    // mudou, o carimbo e o mesmo, e a aplicacao nem pede os dados de novo.
    static string Carimbo()
    {
        StringBuilder sb = new StringBuilder();
        try
        {
            foreach (string f in ArquivosDeLog())
            {
                FileInfo fi = new FileInfo(f);
                sb.Append(fi.Name).Append(':').Append(fi.Length).Append(':')
                  .Append(fi.LastWriteTimeUtc.Ticks).Append('|');
            }
        }
        catch (Exception) { sb.Append("erro"); }
        return sb.ToString();
    }

    static string Versao()
    {
        StringBuilder autores = new StringBuilder();
        try
        {
            foreach (string f in ArquivosDeLog())
            {
                FileInfo fi = new FileInfo(f);
                string nome = fi.Name;
                // recorta pelo tamanho real do prefixo e do ".jsonl": trocar o
                // prefixo sem mexer aqui cortaria o nome do autor no lugar errado
                nome = nome.Substring(Prefixo.Length, nome.Length - Prefixo.Length - 6);
                int arroba = nome.IndexOf('@');
                string autor = arroba > 0 ? nome.Substring(0, arroba) : nome;
                // "origem" e a carga inicial da aplicacao, nao uma pessoa: nao
                // entra na lista de quem esta mexendo.
                if (autor == "origem") continue;
                if (autores.Length > 0) autores.Append(',');
                autores.Append("{\"autor\":").Append(Aspas(autor))
                       .Append(",\"em\":").Append(Aspas(fi.LastWriteTimeUtc.ToString("o", CultureInfo.InvariantCulture)))
                       .Append(",\"bytes\":").Append(fi.Length).Append('}');
            }
        }
        catch (Exception) { }
        return "{\"versao\":" + Aspas(Carimbo()) + ",\"eu\":" + Aspas(Usuario) +
               ",\"autores\":[" + autores + "]}";
    }

    static string Logs()
    {
        StringBuilder sb = new StringBuilder();
        try
        {
            foreach (string f in ArquivosDeLog())
            {
                // Aberto para leitura mesmo com outro processo escrevendo: o
                // OneDrive mexe nesses arquivos o tempo todo.
                using (FileStream fs = new FileStream(f, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                using (StreamReader sr = new StreamReader(fs, Encoding.UTF8))
                {
                    string linha;
                    while ((linha = sr.ReadLine()) != null)
                    {
                        linha = linha.Trim();
                        // Linha cortada pela metade (sincronizacao no meio da
                        // gravacao) e descartada aqui: o navegador nunca recebe
                        // JSON quebrado, e a linha reaparece inteira depois.
                        if (linha.Length > 1 && linha[0] == '{' && linha[linha.Length - 1] == '}')
                            sb.Append(linha).Append('\n');
                    }
                }
            }
        }
        catch (Exception) { }
        return sb.ToString();
    }

    // Recebe uma operacao por linha, ja em JSON, e anexa ao MEU arquivo com
    // autor, sequencia e horario. So este processo escreve neste arquivo.
    static int Anexar(string corpo)
    {
        if (string.IsNullOrEmpty(corpo)) return 0;
        string[] linhas = corpo.Replace("\r\n", "\n").Split('\n');
        StringBuilder sb = new StringBuilder();
        int n = 0;
        lock (Trava)
        {
            foreach (string bruta in linhas)
            {
                string linha = bruta.Trim();
                if (linha.Length < 2 || linha[0] != '{') continue;
                Seq++;
                sb.Append("{\"autor\":").Append(Aspas(Usuario))
                  .Append(",\"seq\":").Append(Seq)
                  .Append(",\"em\":").Append(Aspas(DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture)))
                  .Append(",\"op\":").Append(linha).Append("}\n");
                n++;
            }
            if (n > 0)
            {
                // Uma gravacao so, em modo append: o arquivo nunca fica sem as
                // linhas anteriores, nem que o processo morra no meio.
                using (FileStream fs = new FileStream(MeuArquivo, FileMode.Append, FileAccess.Write, FileShare.Read))
                {
                    byte[] bytes = Utf8.GetBytes(sb.ToString());
                    fs.Write(bytes, 0, bytes.Length);
                    fs.Flush(true);
                }
            }
        }
        return n;
    }

    static int ContarLinhas(string arquivo)
    {
        int n = 0;
        try
        {
            if (!File.Exists(arquivo)) return 0;
            using (FileStream fs = new FileStream(arquivo, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            using (StreamReader sr = new StreamReader(fs, Encoding.UTF8))
                while (sr.ReadLine() != null) n++;
        }
        catch (Exception) { }
        return n;
    }

    static void Responder(Stream saida, int codigo, string tipo, string corpo)
    {
        // O charset entra aqui, e nao no Enviar, porque so faz sentido em
        // texto: declarar charset num .ico e mentira que alguns navegadores
        // levam a serio.
        Enviar(saida, codigo, tipo + "; charset=utf-8", Utf8.GetBytes(corpo));
    }

    static void Enviar(Stream saida, int codigo, string tipo, byte[] bytes)
    {
        StringBuilder cab = new StringBuilder();
        cab.Append("HTTP/1.1 ").Append(codigo).Append(' ').Append(Motivo(codigo)).Append("\r\n");
        cab.Append("Content-Type: ").Append(tipo).Append("\r\n");
        cab.Append("Content-Length: ").Append(bytes.Length).Append("\r\n");
        // Nada de cache: a aplicacao pergunta pelos dados o tempo todo.
        cab.Append("Cache-Control: no-store\r\n");
        cab.Append("Connection: close\r\n\r\n");
        byte[] cabBytes = Encoding.ASCII.GetBytes(cab.ToString());
        saida.Write(cabBytes, 0, cabBytes.Length);
        saida.Write(bytes, 0, bytes.Length);
        saida.Flush();
    }

    static string Motivo(int codigo)
    {
        if (codigo == 200) return "OK";
        if (codigo == 403) return "Forbidden";
        if (codigo == 404) return "Not Found";
        if (codigo == 503) return "Service Unavailable";
        return "Error";
    }

    static string Tipo(string arquivo)
    {
        string ext = Path.GetExtension(arquivo).ToLowerInvariant();
        if (ext == ".html") return "text/html";
        if (ext == ".js") return "application/javascript";
        if (ext == ".css") return "text/css";
        if (ext == ".json") return "application/json";
        if (ext == ".svg") return "image/svg+xml";
        if (ext == ".ico") return "image/x-icon";
        if (ext == ".png") return "image/png";
        if (ext == ".jpg" || ext == ".jpeg") return "image/jpeg";
        if (ext == ".gif") return "image/gif";
        if (ext == ".webp") return "image/webp";
        if (ext == ".woff2") return "font/woff2";
        if (ext == ".woff") return "font/woff";
        if (ext == ".pdf") return "application/pdf";
        if (ext == ".csv") return "text/csv";
        return "text/plain";
    }

    static bool Binario(string arquivo)
    {
        string ext = Path.GetExtension(arquivo).ToLowerInvariant();
        return ext == ".ico" || ext == ".png" || ext == ".jpg" || ext == ".jpeg" ||
               ext == ".gif" || ext == ".webp" || ext == ".woff" || ext == ".woff2" ||
               ext == ".pdf";
    }

    static string Aspas(string s) { return "\"" + Esc(s) + "\""; }

    static string Esc(string s)
    {
        if (s == null) return "";
        StringBuilder sb = new StringBuilder();
        foreach (char c in s)
        {
            if (c == '"' || c == '\\') sb.Append('\\').Append(c);
            else if (c == '\n') sb.Append("\\n");
            else if (c == '\r') sb.Append("\\r");
            else if (c == '\t') sb.Append("\\t");
            else if (c < 32) sb.Append("\\u").Append(((int)c).ToString("x4"));
            else sb.Append(c);
        }
        return sb.ToString();
    }

    // Nome de usuario vira nome de arquivo: sem espaco, sem acento estranho,
    // sem barra. "Vitor Cunha" -> "vitor-cunha".
    static string Limpar(string s)
    {
        if (string.IsNullOrEmpty(s)) return "usuario";
        StringBuilder sb = new StringBuilder();
        foreach (char c in s.ToLowerInvariant())
        {
            if (char.IsLetterOrDigit(c) && c < 128) sb.Append(c);
            else if (c == ' ' || c == '.' || c == '_' || c == '-') sb.Append('-');
        }
        string limpo = sb.ToString().Trim('-');
        return limpo.Length == 0 ? "usuario" : limpo;
    }

    // O icone da bandeja.
    //
    // Primeiro o arquivo ao lado do .exe (marca.ico, ou o que o marca.json
    // disser): e o que permite trocar o icone de uma instalacao sem
    // compilador. Depois o que foi embutido no build. Por ultimo o generico
    // do Windows - um icone feio e melhor que um programa que nao abre.
    //
    // Em qualquer um dos casos pedimos o QUADRO do tamanho certo - 16x16 na
    // bandeja. Sem passar o tamanho, o .NET pega o maior quadro (256) e
    // encolhe na marra, e o resultado fica borrado ao lado dos outros.
    static string CaminhoIcone()
    {
        // So o nome do arquivo: marca.json nao pode apontar para fora da pasta.
        return Path.Combine(PastaExe, Path.GetFileName(ArquivoIcone));
    }

    static bool TemIcone()
    {
        try { return File.Exists(CaminhoIcone()); }
        catch (Exception) { return false; }
    }

    static Icon IconeDaMarca(Size tamanho)
    {
        try
        {
            if (TemIcone())
                using (Stream s = File.OpenRead(CaminhoIcone()))
                    return new Icon(s, tamanho);
        }
        catch (Exception) { }
        try
        {
            using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("marca.ico"))
                if (s != null) return new Icon(s, tamanho);
        }
        catch (Exception) { }
        return SystemIcons.Application;
    }
}
