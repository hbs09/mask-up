<#
    Acrescenta a raiz do Norton ao conjunto de certificados do Roblox Studio.

    PORQUE E QUE ISTO E NECESSARIO

    O Norton 360 nesta maquina faz inspecao de HTTPS: o modulo Web Shield
    substitui o certificado de cada site por um gerado por ele
    ("CN=Norton Web/Mail Shield Root"). O Roblox Studio usa curl com OpenSSL e um
    conjunto de certificados proprio (ssl/cacert.pem), que nao inclui essa raiz,
    por isso recusa TODAS as ligacoes:

        HttpError: TlsVerificationFail
        SSL certificate: unable to get local issuer certificate (20)
        url: https://apis.roblox.com/oauth/.well-known/openid-configuration

    O Studio nao consegue autenticar e aparece "erro de conexao" ao arrancar.

    PORQUE E QUE ISTO E SEGURO

    A raiz do Norton JA ESTA na loja de certificados do Windows -- foi o Norton
    que a instalou. Todos os browsers e aplicacoes .NET desta maquina ja confiam
    nela, e o trafego do Roblox ja estava a ser interceptado; apenas falhava.
    Este script nao amplia o alcance do Norton, so deixa o Roblox de ser a
    excecao que rebenta. O Norton fica 100% ativo.

    QUANDO REPETIR

    Cada atualizacao do Studio substitui o cacert.pem. Se o "erro de conexao"
    voltar depois de uma atualizacao, corre isto outra vez.

    PARA DESFAZER

    Restaurar o backup que fica ao lado: cacert.pem.backup
#>

$ErrorActionPreference = "Stop"

$IMPRESSAO_NORTON = "0F7623F7FFCE2CB594977AEFDA022FDDFBAECFC1"
$MARCADOR = "# Norton Web/Mail Shield Root (acrescentado por scripts/confiar-certificado-norton.ps1)"

# --- 1. Encontrar a raiz do Norton na loja do Windows ---
$cert = Get-ChildItem Cert:\LocalMachine\Root, Cert:\CurrentUser\Root -ErrorAction SilentlyContinue |
    Where-Object { $_.Thumbprint -eq $IMPRESSAO_NORTON } |
    Select-Object -First 1

if (-not $cert) {
    Write-Host "Nao encontrei a raiz do Norton ($IMPRESSAO_NORTON) na loja do Windows." -ForegroundColor Yellow
    Write-Host "Se desinstalaste o Norton ou desligaste o Web Shield, este script ja nao e necessario."
    exit 0
}

Write-Host "Raiz encontrada: $($cert.Subject)"

# --- 2. Encontrar o cacert.pem do Studio ---
$instalacoes = Get-ChildItem "$env:LOCALAPPDATA\Roblox\Versions" -Directory -ErrorAction SilentlyContinue |
    ForEach-Object { Join-Path $_.FullName "ssl\cacert.pem" } |
    Where-Object { Test-Path $_ }

if (-not $instalacoes) {
    Write-Host "Nao encontrei nenhum ssl\cacert.pem em $env:LOCALAPPDATA\Roblox\Versions" -ForegroundColor Red
    exit 1
}

# --- 3. Converter o certificado para PEM ---
$base64 = [Convert]::ToBase64String($cert.RawData, "InsertLineBreaks")
$pem = "$MARCADOR`n-----BEGIN CERTIFICATE-----`n$base64`n-----END CERTIFICATE-----`n"

# --- 4. Acrescentar a cada instalacao ---
foreach ($caminho in $instalacoes) {
    $conteudo = Get-Content $caminho -Raw

    if ($conteudo.Contains($IMPRESSAO_NORTON) -or $conteudo.Contains($MARCADOR)) {
        Write-Host "[ja aplicado] $caminho"
        continue
    }

    $backup = "$caminho.backup"
    if (-not (Test-Path $backup)) {
        Copy-Item $caminho $backup
        Write-Host "[backup    ] $backup"
    }

    # Sem BOM e com LF: o OpenSSL e exigente com o formato do PEM.
    $novo = $conteudo.TrimEnd() + "`n`n" + $pem
    [System.IO.File]::WriteAllText($caminho, $novo, (New-Object System.Text.UTF8Encoding $false))

    Write-Host "[aplicado  ] $caminho" -ForegroundColor Green
}

Write-Host ""
Write-Host "Fecha o Roblox Studio por completo e abre outra vez (o cacert.pem e lido no arranque)."
exit 0
