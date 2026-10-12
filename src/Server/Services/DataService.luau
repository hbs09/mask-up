--!strict
--[[
	Perfis dos jogadores (secção 5 do documento).

	Este ficheiro e um ADAPTADOR: toda a logica de o que e um perfil valido, como
	sobe de nivel e como se migra de uma versao antiga esta no PerfilCore, que e
	puro e tem testes. Aqui so ligamos isso aos eventos do Roblox (jogador entra,
	jogador sai) e, na Fase 3, ao DataStore.

	NESTA FASE O PERFIL E SO DE SESSAO: perde-se quando o jogador sai. E
	deliberado. O DataStore exige um place publicado e "Enable Studio Access to
	API Services", e o documento so o coloca na Fase 3. Como a FORMA do perfil ja
	esta fixada e testada, trocar o armazenamento nao obriga a mexer em quem o
	consome.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local PerfilCore = require(ServerScriptService.Core.PerfilCore)

type Perfil = PerfilCore.Perfil

local DataService = {}

local core: PerfilCore.Core
local perfis: { [Player]: Perfil } = {}

function DataService.init()
	core = PerfilCore.novo(Config.progressao)
end

function DataService.start()
	local function carregar(jogador: Player)
		--[[
			TODO Fase 3: substituir por DataStore.
			  local ok, guardado = pcall(function()
			      return armazem:GetAsync("jogador_" .. jogador.UserId)
			  end)
			  perfis[jogador] = core:migrar(if ok then guardado else nil)
			E guardar ao sair e de 2 em 2 minutos, com pcall e novas tentativas.

			O `migrar(nil)` aqui nao e um atalho: e o mesmo caminho que um
			jogador novo percorre no DataStore, por isso ja esta testado.
		]]
		perfis[jogador] = core:migrar(nil)
	end

	for _, jogador in Players:GetPlayers() do
		carregar(jogador)
	end
	Players.PlayerAdded:Connect(carregar)

	Players.PlayerRemoving:Connect(function(jogador)
		-- TODO Fase 3: guardar antes de limpar.
		perfis[jogador] = nil
	end)
end

-- Pode devolver nil se o jogador sair a meio de uma operacao.
function DataService.obterPerfil(jogador: Player): Perfil?
	return perfis[jogador]
end

function DataService.adicionarDinheiro(jogador: Player, quantia: number): number?
	local perfil = perfis[jogador]
	if not perfil then
		return nil
	end

	return core:adicionarDinheiro(perfil, quantia)
end

-- Devolve quantos niveis subiu, para o ecra final poder festejar.
function DataService.adicionarXp(jogador: Player, quantia: number): number
	local perfil = perfis[jogador]
	if not perfil then
		return 0
	end

	return core:adicionarXp(perfil, quantia)
end

function DataService.registarAssalto(jogador: Player, foiFurtivo: boolean)
	local perfil = perfis[jogador]
	if perfil then
		core:registarAssalto(perfil, foiFurtivo)
	end
end

return DataService
