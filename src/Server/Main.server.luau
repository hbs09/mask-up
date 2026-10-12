--!strict
--[[
	Arranca os servicos pela ordem certa (secção 3 do documento).

	Porque e que isto existe em vez de cada servico se arrancar sozinho: os
	servicos precisam uns dos outros (o LootService avisa o HeistService, o
	AlarmService muda o estado do assalto). Se cada um fizesse `require` do
	outro, tinhamos requires circulares, que em Luau falham de maneiras
	confusas.

	A solucao e injecao de dependencias em duas fases:
	  1. init(deps)  -- cada servico recebe referencias; ninguem corre logica
	  2. start()     -- agora que todos existem, ligar eventos e arrancar loops

	Assim nenhum servico faz require de outro servico, e a ordem de arranque fica
	visivel num unico ficheiro em vez de implicita nos imports.
]]

local ServerScriptService = game:GetService("ServerScriptService")

local Services = ServerScriptService.Services

local DataService = require(Services.DataService)
local MapBuilder = require(Services.MapBuilder)
local AlarmService = require(Services.AlarmService)
local LootService = require(Services.LootService)
local HeistService = require(Services.HeistService)

-- Fase 1: init. Nenhum servico deve tocar no Workspace nem ligar eventos aqui.
DataService.init()
MapBuilder.init()

AlarmService.init({
	-- O AlarmService so precisa de saber o estado e poder disparar o alarme.
	-- Passamos funcoes em vez do servico inteiro para a dependencia ser
	-- explicita e pequena.
	heist = {
		estadoAtual = HeistService.estadoAtual,
		dispararAlarme = HeistService.dispararAlarme,
	},
})

LootService.init()
HeistService.init()

-- Fase 2: start. O mapa primeiro, porque os outros procuram objetos nele.
MapBuilder.start()
DataService.start()
AlarmService.start()
LootService.start()
HeistService.start()

print("[Main] servidor pronto")
