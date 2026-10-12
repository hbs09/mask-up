--!strict
--[[
	Acesso aos Remotes (secção 6 do documento).

	Os RemoteEvents nao sao criados aqui: estao declarados no
	default.project.json, por isso o Rojo cria-os antes de qualquer script
	arrancar. Isso evita a condicao de corrida classica em que o cliente procura
	um Remote que o servidor ainda nao criou.

	Este modulo so os resolve e devolve numa tabela, para o resto do codigo
	escrever `Remotes.PickUpBag` em vez de uma cadeia de WaitForChild.

	Direcao de cada um (do documento):
	  Servidor -> todos    HeistStateChanged, UpdateHUD
	  Cliente  -> servidor RequestInteract, PickUpBag, DropBag,
	                       WireChoice, UseEmergencyKit

	Tudo o que vem do cliente passa pelo ValidacaoCore antes de ter efeito.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local pasta = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes")

local function evento(nome: string): RemoteEvent
	return pasta:WaitForChild(nome) :: RemoteEvent
end

local Remotes = {
	-- Servidor -> clientes
	HeistStateChanged = evento("HeistStateChanged"),
	UpdateHUD = evento("UpdateHUD"),

	-- Cliente -> servidor (sempre validados)
	RequestInteract = evento("RequestInteract"),
	PickUpBag = evento("PickUpBag"),
	DropBag = evento("DropBag"),

	-- Fase 1 e Fase 5: declarados, ainda sem handler.
	WireChoice = evento("WireChoice"),
	UseEmergencyKit = evento("UseEmergencyKit"),
}

return table.freeze(Remotes)
