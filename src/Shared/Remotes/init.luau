--!strict
--[[
	Acesso aos Remotes (secção 6 do documento).

	Os RemoteEvents nao sao criados aqui: estao declarados no
	default.project.json como FILHOS deste modulo, por isso o Rojo cria-os antes
	de qualquer script arrancar. Isso evita a condicao de corrida classica em que
	o cliente procura um Remote que o servidor ainda nao criou.

	Porque e que isto e `Remotes/init.luau` e nao `Remotes.luau`: a estrutura do
	documento pede uma pasta `Shared/Remotes/` com os eventos la dentro, e este
	modulo tambem se queria chamar `Remotes`. Tê-los separados criava DOIS filhos
	chamados "Remotes" dentro de Shared, e aí o `require(Shared.Remotes)` podia
	devolver a pasta em vez do modulo -- e o `WaitForChild("Remotes")` daqui
	podia encontrar-se a si mesmo. Com init.luau, o modulo E a pasta: os eventos
	sao filhos dele e chegam-se por `script`.

	Direcao de cada um (do documento):
	  Servidor -> todos    HeistStateChanged, UpdateHUD
	  Cliente  -> servidor RequestInteract, PickUpBag, DropBag,
	                       WireChoice, UseEmergencyKit

	Tudo o que vem do cliente passa pelo ValidacaoCore antes de ter efeito.
]]

local function evento(nome: string): RemoteEvent
	return script:WaitForChild(nome) :: RemoteEvent
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
