--!strict
--[[
	HUD: estado do assalto, temporizador, sacos entregues e dinheiro.

	ESTADO: esqueleto.

	Vai construir o ScreenGui por codigo, sem ficheiros de interface para manter
	em paralelo com o Rojo. Ouve dois Remotes e mais nada:
	  HeistStateChanged  -- muda o texto do estado e o temporizador
	  UpdateHUD          -- dinheiro, sacos entregues / minimo

	Nao calcula nada: se o HUD precisar de fazer uma conta para saber o que
	mostrar, essa conta pertence ao servidor.
]]

local HUDController = {}

function HUDController.init() end

function HUDController.start() end

return HUDController
