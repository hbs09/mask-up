<#
    Instala as ferramentas do projeto em .\tools\

    Porque é que este script existe em vez de um simples `rokit install`?

    O Norton 360 nesta máquina faz inspeção de HTTPS: substitui o certificado de
    cada site por um gerado por ele ("CN=Norton Web/Mail Shield Root"). O Rokit é
    escrito em Rust e usa o rustls com raízes de certificado embutidas no binário,
    por isso não confia no certificado do Norton e o handshake TLS morre com
    "reqwest middleware error: Request failed after 3 retries".

    O PowerShell usa a loja de certificados do Windows, onde o Norton instalou a
    sua raiz, por isso descarrega sem problema. Este script faz esse download
    diretamente, sem desligar nada no antivírus.

    As versões são as mesmas que estão fixadas no rokit.toml. Se um dia o Rokit
    conseguir chegar à rede (ex.: exceção no Norton), `rokit install` passa a
    funcionar e este script deixa de ser necessário.
#>

$ErrorActionPreference = "Stop"

$ferramentas = @(
    @{ nome = "rojo";   url = "https://github.com/rojo-rbx/rojo/releases/download/v7.7.1/rojo-7.7.1-windows-x86_64.zip" }
    @{ nome = "lune";   url = "https://github.com/lune-org/lune/releases/download/v0.11.0/lune-0.11.0-windows-x86_64.zip" }
    @{ nome = "stylua"; url = "https://github.com/JohnnyMorganz/StyLua/releases/download/v2.6.0/stylua-windows-x86_64.zip" }
    @{ nome = "selene"; url = "https://github.com/Kampfkarren/selene/releases/download/0.32.0/selene-0.32.0-windows.zip" }
)

$raiz = Split-Path -Parent $PSScriptRoot
$destino = Join-Path $raiz "tools"
if (-not (Test-Path $destino)) { New-Item -ItemType Directory -Path $destino | Out-Null }

foreach ($f in $ferramentas) {
    $exe = Join-Path $destino "$($f.nome).exe"
    if (Test-Path $exe) {
        Write-Host "[ja existe] $($f.nome)"
        continue
    }

    $zip = Join-Path $env:TEMP "$($f.nome)-download.zip"
    $tmp = Join-Path $env:TEMP "$($f.nome)-extract"

    Write-Host "[download ] $($f.nome)"
    Invoke-WebRequest -Uri $f.url -OutFile $zip

    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath $tmp -Force

    # Os zips variam: uns têm o .exe na raiz, outros dentro de uma pasta.
    $encontrado = Get-ChildItem $tmp -Recurse -Filter "$($f.nome).exe" | Select-Object -First 1
    if (-not $encontrado) { throw "Nao encontrei $($f.nome).exe dentro de $($f.url)" }

    Move-Item $encontrado.FullName $exe -Force
    Remove-Item $zip, $tmp -Recurse -Force
    Write-Host "[instalado] $($f.nome) -> $exe"
}

# --- Plugin do Rojo para o Roblox Studio ---
#
# O `rojo plugin install` falha nesta maquina: procura o valor ContentFolder em
# HKCU:\Software\Roblox\RobloxStudio para descobrir a pasta de plugins, e esse
# valor nao existe neste registo. Copiamos o Rojo.rbxm diretamente para a pasta
# de plugins do Studio, que e exatamente o que esse comando faria.
$pastaPlugins = Join-Path $env:LOCALAPPDATA "Roblox\Plugins"
$plugin = Join-Path $pastaPlugins "Rojo.rbxm"
if (Test-Path $plugin) {
    Write-Host "[ja existe] plugin Rojo"
} else {
    if (-not (Test-Path $pastaPlugins)) { New-Item -ItemType Directory -Path $pastaPlugins -Force | Out-Null }
    Write-Host "[download ] plugin Rojo"
    Invoke-WebRequest -Uri "https://github.com/rojo-rbx/rojo/releases/download/v7.7.1/Rojo.rbxm" -OutFile $plugin
    Write-Host "[instalado] plugin Rojo -> $plugin"
}

Write-Host ""
Write-Host "Versoes instaladas:"
foreach ($f in $ferramentas) {
    $exe = Join-Path $destino "$($f.nome).exe"
    # O `selene --version` devolve codigo de saida -1 mesmo quando funciona, por
    # isso ignoramos o codigo aqui e olhamos so para o texto.
    $v = (& $exe --version 2>&1 | Select-Object -First 1)
    Write-Host ("  {0,-8} {1}" -f $f.nome, $v)
}

Write-Host ""
Write-Host "Para usar nesta sessao de terminal:"
Write-Host "  `$env:PATH = `"$destino;`$env:PATH`""

exit 0
