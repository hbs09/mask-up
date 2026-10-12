--!strict
--[[
	Prompts de interacao e atalhos de teclado.

	ESTADO: esqueleto.

	Vai ligar os ProximityPrompt.Triggered dos sacos e dos objetos aos Remotes
	(PickUpBag, DropBag, RequestInteract) e a tecla G para largar o saco.

	E so um tradutor de input para pedido: nao verifica distancias nem se o
	jogador pode agir. Essas verificacoes sao do servidor (ValidacaoCore), porque
	qualquer verificacao feita aqui pode ser removida por quem usa um executor.
]]

local InteractController = {}

function InteractController.init() end

function InteractController.start() end

return InteractController
