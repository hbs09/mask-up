--!strict
--[[
	Arranca os controladores do cliente (secção 3 do documento).

	O cliente PEDE, nunca DECIDE. Nenhum ficheiro desta pasta pode somar
	dinheiro, mudar o estado do assalto ou decidir que um saco foi entregue:
	tudo isso vem do servidor pelos Remotes HeistStateChanged e UpdateHUD.

	Se um controlador precisar de guardar estado de jogo para funcionar, e sinal
	de que a decisao esta no lado errado.
]]

local Controllers = script.Parent.Controllers

local HUDController = require(Controllers.HUDController)
local InteractController = require(Controllers.InteractController)

HUDController.init()
InteractController.init()

HUDController.start()
InteractController.start()

print("[Client] cliente pronto")
