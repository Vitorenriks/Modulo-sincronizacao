# Icone.ps1 - monta o .ico da marca a partir do logo da empresa.
#
# Por que nao copiar o arquivo do cliente e pronto: quase todo logo que chega
# e PNG ou JPG, e o Windows precisa de .ico para o icone do executavel. E
# quase todo .ico que chega tem UM quadro so, grande demais - ai a bandeja
# encolhe 256x256 para 16x16 na marra e o icone fica borrado ao lado do
# relogio. Aqui a imagem e redimensionada uma vez por tamanho, com
# interpolacao boa, e todos os quadros entram no mesmo arquivo.
#
# Os quadros sao gravados como DIB (bitmap cru), nao como PNG embutido: PNG
# dentro de .ico so e lido a partir do Vista e algumas versoes do .NET
# tropecam nele. DIB e maior em bytes e funciona em tudo.

Add-Type -AssemblyName System.Drawing

# Os tamanhos que o Windows realmente pede: bandeja e barra de titulo (16),
# ajustes de DPI (24), lista de arquivos (32), icones grandes (48/64) e a
# visualizacao extra grande do Explorer (256). O quadro de 256 vai comprimido
# em PNG - em DIB cru ele sozinho pesa 270 KB, mais do que o resto somado.
$TAMANHOS_ICO = @(16, 24, 32, 48, 64, 256)
$TAMANHO_EM_PNG = 256

# BinaryWriter.Write com um byte[] vindo de uma hashtable: o PowerShell
# escolhe a sobrecarga de UM byte e grava 1 byte no lugar do vetor inteiro -
# sem erro nenhum, so um arquivo truncado. A forma de tres argumentos nao tem
# essa ambiguidade, entao e a unica usada aqui.
function Write-Bytes {
    param([System.IO.BinaryWriter]$W, [byte[]]$Bytes)
    $W.Write($Bytes, 0, $Bytes.Length)
}

function Test-EhIco {
    param([string]$Caminho)
    if (-not (Test-Path -LiteralPath $Caminho)) { return $false }
    return ([System.IO.Path]::GetExtension($Caminho).ToLowerInvariant() -eq '.ico')
}

# Desenha a imagem dentro de um quadrado de $Lado, mantendo a proporcao e
# centralizando. Fundo transparente: logo quadrado ocupa tudo, logo deitado
# ganha faixa vazia em cima e embaixo em vez de esticar.
function New-QuadroBitmap {
    param([System.Drawing.Image]$Origem, [int]$Lado)

    $bmp = New-Object System.Drawing.Bitmap($Lado, $Lado, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.Clear([System.Drawing.Color]::Transparent)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

        $escala = [Math]::Min($Lado / $Origem.Width, $Lado / $Origem.Height)
        $w = [int][Math]::Round($Origem.Width * $escala)
        $h = [int][Math]::Round($Origem.Height * $escala)
        $x = [int](($Lado - $w) / 2)
        $y = [int](($Lado - $h) / 2)
        $g.DrawImage($Origem, $x, $y, $w, $h)
    } finally { $g.Dispose() }
    return $bmp
}

# Um quadro do .ico: cabecalho DIB + pixels de baixo para cima + mascara AND.
function Get-QuadroDib {
    param([System.Drawing.Bitmap]$Bmp)

    $lado = $Bmp.Width
    $ret = New-Object System.Drawing.Rectangle(0, 0, $lado, $lado)
    $dados = $Bmp.LockBits($ret, [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
                           [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $strideOrigem = $dados.Stride
        $bruto = New-Object byte[] ($strideOrigem * $lado)
        [System.Runtime.InteropServices.Marshal]::Copy($dados.Scan0, $bruto, 0, $bruto.Length)
    } finally { $Bmp.UnlockBits($dados) }

    $fluxo = New-Object System.IO.MemoryStream
    $w = New-Object System.IO.BinaryWriter($fluxo)

    # BITMAPINFOHEADER. A altura vai DOBRADA porque o formato espera a imagem
    # e a mascara empilhadas - quem informa so a altura real recebe um icone
    # cortado ao meio.
    $w.Write([uint32]40)
    $w.Write([int32]$lado)
    $w.Write([int32]($lado * 2))
    $w.Write([uint16]1)
    $w.Write([uint16]32)
    $w.Write([uint32]0)                      # sem compressao
    $w.Write([uint32]($lado * $lado * 4))
    $w.Write([int32]0); $w.Write([int32]0)   # resolucao: irrelevante em icone
    $w.Write([uint32]0); $w.Write([uint32]0)

    # Pixels: DIB e de baixo para cima, e a ordem de bytes do Format32bppArgb
    # na memoria ja e BGRA - a mesma do DIB. So a ordem das linhas inverte.
    $stride = $lado * 4
    for ($linha = $lado - 1; $linha -ge 0; $linha--) {
        $w.Write($bruto, $linha * $strideOrigem, $stride)
    }

    # Mascara AND, 1 bit por pixel, linha alinhada em 4 bytes. Fica toda zero:
    # a transparencia real vem do canal alfa dos pixels acima.
    $bytesLinha = [int][Math]::Ceiling($lado / 8.0)
    if ($bytesLinha % 4 -ne 0) { $bytesLinha += 4 - ($bytesLinha % 4) }
    Write-Bytes -W $w -Bytes (New-Object byte[] ($bytesLinha * $lado))

    $w.Flush()
    return $fluxo.ToArray()
}

# O quadro grande vai como PNG, que e o que o formato permite desde o Vista.
function Get-QuadroPng {
    param([System.Drawing.Bitmap]$Bmp)
    $fluxo = New-Object System.IO.MemoryStream
    $Bmp.Save($fluxo, [System.Drawing.Imaging.ImageFormat]::Png)
    return $fluxo.ToArray()
}

function New-ArquivoIco {
    param([System.Drawing.Image]$Origem, [string]$Destino)

    $quadros = @()
    foreach ($lado in $TAMANHOS_ICO) {
        $bmp = New-QuadroBitmap -Origem $Origem -Lado $lado
        try {
            $bytes = if ($lado -ge $TAMANHO_EM_PNG) { Get-QuadroPng -Bmp $bmp } else { Get-QuadroDib -Bmp $bmp }
            $quadros += ,@{ Lado = $lado; Bytes = [byte[]]$bytes }
        }
        finally { $bmp.Dispose() }
    }

    $fluxo = New-Object System.IO.MemoryStream
    $w = New-Object System.IO.BinaryWriter($fluxo)
    $w.Write([uint16]0)                  # reservado
    $w.Write([uint16]1)                  # 1 = icone
    $w.Write([uint16]$quadros.Count)

    $deslocamento = 6 + (16 * $quadros.Count)
    foreach ($q in $quadros) {
        # 256 nao cabe em um byte: o formato combina que 0 quer dizer 256.
        $medida = if ($q.Lado -ge 256) { 0 } else { $q.Lado }
        $w.Write([byte]$medida); $w.Write([byte]$medida)
        $w.Write([byte]0); $w.Write([byte]0)
        $w.Write([uint16]1); $w.Write([uint16]32)
        $w.Write([uint32]$q.Bytes.Length)
        $w.Write([uint32]$deslocamento)
        $deslocamento += $q.Bytes.Length
    }
    foreach ($q in $quadros) { Write-Bytes -W $w -Bytes $q.Bytes }
    $w.Flush()

    $pasta = Split-Path -Parent $Destino
    if ($pasta -and -not (Test-Path -LiteralPath $pasta)) {
        New-Item -ItemType Directory -Path $pasta -Force | Out-Null
    }
    [System.IO.File]::WriteAllBytes($Destino, $fluxo.ToArray())
    $w.Dispose()
}

# Sem logo do cliente, desenha um: quadrado arredondado com as iniciais. A cor
# sai do nome do projeto, entao dois projetos diferentes na mesma bandeja
# nunca saem com o mesmo icone - que e o problema real de usar um generico.
function New-IconePadrao {
    param([string]$Nome, [string]$Destino)

    $iniciais = -join (($Nome -split '[^\p{L}\p{N}]+' | Where-Object { $_ }) |
                        Select-Object -First 2 | ForEach-Object { $_.Substring(0,1).ToUpperInvariant() })
    if (-not $iniciais) { $iniciais = 'A' }

    $soma = 0
    foreach ($c in $Nome.ToCharArray()) { $soma = ($soma * 31 + [int]$c) % 360 }
    $cor = Get-CorDeMatiz -Matiz $soma

    $lado = 256
    $bmp = New-Object System.Drawing.Bitmap($lado, $lado, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.Clear([System.Drawing.Color]::Transparent)
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

        $r = 48
        $caminho = New-Object System.Drawing.Drawing2D.GraphicsPath
        $caminho.AddArc(0, 0, $r*2, $r*2, 180, 90)
        $caminho.AddArc($lado-$r*2, 0, $r*2, $r*2, 270, 90)
        $caminho.AddArc($lado-$r*2, $lado-$r*2, $r*2, $r*2, 0, 90)
        $caminho.AddArc(0, $lado-$r*2, $r*2, $r*2, 90, 90)
        $caminho.CloseFigure()
        $pincel = New-Object System.Drawing.SolidBrush($cor)
        $g.FillPath($pincel, $caminho)

        $fonte = New-Object System.Drawing.Font('Segoe UI Semibold', 110, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
        $formato = New-Object System.Drawing.StringFormat
        $formato.Alignment = [System.Drawing.StringAlignment]::Center
        $formato.LineAlignment = [System.Drawing.StringAlignment]::Center
        $branco = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
        $g.DrawString($iniciais, $fonte, $branco, (New-Object System.Drawing.RectangleF(0, 0, $lado, $lado)), $formato)

        $pincel.Dispose(); $branco.Dispose(); $fonte.Dispose(); $caminho.Dispose()
    } finally { $g.Dispose() }

    try { New-ArquivoIco -Origem $bmp -Destino $Destino } finally { $bmp.Dispose() }
}

# Matiz -> RGB com saturacao e brilho fixos, para nenhuma cor sorteada sair
# clara demais para texto branco em cima.
function Get-CorDeMatiz {
    param([int]$Matiz)
    $s = 0.52; $v = 0.62
    $h = ($Matiz % 360) / 60.0
    $i = [int][Math]::Floor($h)
    $f = $h - $i
    $p = $v * (1 - $s); $q = $v * (1 - $s * $f); $t = $v * (1 - $s * (1 - $f))
    switch ($i % 6) {
        0 { $r=$v; $g=$t; $b=$p }
        1 { $r=$q; $g=$v; $b=$p }
        2 { $r=$p; $g=$v; $b=$t }
        3 { $r=$p; $g=$q; $b=$v }
        4 { $r=$t; $g=$p; $b=$v }
        5 { $r=$v; $g=$p; $b=$q }
    }
    return [System.Drawing.Color]::FromArgb(255, [int]($r*255), [int]($g*255), [int]($b*255))
}

# Ponto de entrada usado pelos scripts: recebe o que o cliente mandou (png,
# jpg, ico ou nada) e devolve sempre um .ico completo no destino.
function Resolve-IconeDaMarca {
    param(
        [string]$Origem,
        [Parameter(Mandatory=$true)][string]$Destino,
        [string]$NomeDoProjeto = 'Aplicação'
    )

    if (-not $Origem) {
        New-IconePadrao -Nome $NomeDoProjeto -Destino $Destino
        return 'padrao'
    }
    if (-not (Test-Path -LiteralPath $Origem)) {
        throw "Não achei o arquivo de ícone: $Origem"
    }

    # .ico com varios quadros ja esta pronto; com um quadro so, e remontado a
    # partir do maior quadro que ele tiver.
    if (Test-EhIco $Origem) {
        $bytes = [System.IO.File]::ReadAllBytes($Origem)
        $quadros = if ($bytes.Length -ge 6) { [BitConverter]::ToUInt16($bytes, 4) } else { 0 }
        if ($quadros -ge 4) {
            Copy-Item -LiteralPath $Origem -Destination $Destino -Force
            return 'copiado'
        }
        $ico = New-Object System.Drawing.Icon($Origem, 256, 256)
        try {
            $bmp = $ico.ToBitmap()
            try { New-ArquivoIco -Origem $bmp -Destino $Destino } finally { $bmp.Dispose() }
        } finally { $ico.Dispose() }
        return 'remontado'
    }

    $img = [System.Drawing.Image]::FromFile((Resolve-Path -LiteralPath $Origem).Path)
    try { New-ArquivoIco -Origem $img -Destino $Destino } finally { $img.Dispose() }
    return 'convertido'
}
