--!strict
--[[
	Arranca os controladores do cliente (secção 3 do documento).

	O cliente PEDE, nunca DECIDE. Nenhum ficheiro desta pasta pode somar
	dinheiro, mudar o estado do assalto ou decidir que um saco foi entregue:
	tudo isso vem do servidor pelos Remotes HeistStateChanged e UpdateHUD.

	Se um controlador precisar de guardar estado de jogo para funcionar, e sinal
	de que a decisao esta no lado errado.
]]

--[[
	WaitForChild e nao `script.Parent.Controllers` direto: em runtime, o conteudo
	de StarterPlayerScripts e COPIADO para Players.<nome>.PlayerScripts, e este
	LocalScript pode arrancar antes de a pasta Controllers chegar. Sem a espera, o
	erro e "Controllers is not a valid member of PlayerScripts".
]]
local Controllers = script.Parent:WaitForChild("Controllers")

local HUDController = require(Controllers:WaitForChild("HUDController"))
local InteractController = require(Controllers:WaitForChild("InteractController"))

HUDController.init()
InteractController.init()

HUDController.start()
InteractController.start()

print("[Client] cliente pronto")
