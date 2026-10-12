<#
    Corre todas as verificacoes do projeto, na ordem do mais rapido para o mais lento.

        .\scripts\verificar.ps1              -- tudo
        .\scripts\verificar.ps1 -Formatar    -- corrige a formatacao em vez de so avisar

    Devolve codigo de saida 0 so se tudo passar, para servir de porta antes de
    um commit.
#>

param(
    [switch]$Formatar
)

$raiz = Split-Path -Parent $PSScriptRoot
$ferramentas = Join-Path $raiz "tools"

if (-not (Test-Path (Join-Path $ferramentas "lune.exe"))) {
    Write-Host "Ferramentas nao instaladas. Corre primeiro: .\scripts\instalar-ferramentas.ps1" -ForegroundColor Red
    exit 1
}

$env:PATH = "$ferramentas;$env:PATH"
Push-Location $raiz

# Codigo puro + testes: sem globais do Roblox (ver comentario em selene.toml).
$codigoPuro = @("src/Server/Core", "tests", ".lune")
# Adaptadores: precisam dos globais do Roblox.
$codigoRoblox = @("src/Shared", "src/Server/Services", "src/Server/Main.server.luau", "src/Client")

$falhas = @()

function Etapa {
    param([string]$Nome, [scriptblock]$Bloco)

    Write-Host ""
    Write-Host "=== $Nome ===" -ForegroundColor Cyan
    & $Bloco
    if ($LASTEXITCODE -ne 0) {
        $script:falhas += $Nome
        Write-Host "FALHOU: $Nome" -ForegroundColor Red
    }
}

# Os adaptadores sao escritos depois do core, por isso durante o arranque do
# projeto alguns destes caminhos ainda nao existem. Verificamos so o que existe,
# em vez de falhar por causa de trabalho que ainda nao comecou.
$puroExistente = $codigoPuro | Where-Object { Test-Path $_ }
$robloxExistente = $codigoRoblox | Where-Object { Test-Path $_ }
$todos = @($puroExistente) + @($robloxExistente)

if ($Formatar) {
    Etapa "stylua (a corrigir)" { stylua $todos }
} else {
    Etapa "stylua --check" { stylua --check $todos }
}

Etapa "selene (codigo puro, sem Roblox)" { selene $puroExistente }

if ($robloxExistente) {
    Etapa "selene (adaptadores Roblox)" { selene --config selene-roblox.toml $robloxExistente }
}

Etapa "auto-teste do harness" { lune run .lune/autoteste-harness.luau }

Etapa "testes" { lune run .lune/tests.luau }

# O rojo build so faz sentido quando a arvore do default.project.json estiver
# toda no disco; antes disso falha por causa de pastas que ainda nao criamos.
if ($robloxExistente.Count -eq $codigoRoblox.Count) {
    Etapa "rojo build" { rojo build --output (Join-Path $env:TEMP "verificacao.rbxlx") }
} else {
    Write-Host ""
    Write-Host "=== rojo build (saltado: adaptadores ainda nao escritos) ===" -ForegroundColor DarkGray
}

Pop-Location

Write-Host ""
if ($falhas.Count -gt 0) {
    Write-Host ("$($falhas.Count) etapa(s) falharam: " + ($falhas -join ", ")) -ForegroundColor Red
    exit 1
}
Write-Host "Tudo passou." -ForegroundColor Green
exit 0
