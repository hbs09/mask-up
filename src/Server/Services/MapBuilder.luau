--!strict
--[[
	Constroi a joalharia de teste com Parts -- ADAPTADOR.

	ESTADO: esqueleto.

	Porque e que o mapa e gerado por codigo: desbloqueia toda a programacao antes
	de existir um mapa bonito. Os nomes seguem a secção 3 do documento, por isso
	quando substituires isto por um mapa feito a mao no Studio, os servicos
	continuam a encontrar tudo sem uma linha alterada.

	Arvore que vai criar (quantidades em Config.mapa):
	  Workspace/Map/Joalharia/   chao, paredes, entrada
	  Workspace/Loot/            Montra1..4 (sacos pequenos), Cofre (saco grande)
	  Workspace/EscapeZone/      zona da carrinha, nas traseiras
	  Workspace/Waypoints/       W1..W6, rotas dos guardas (prontas p/ Fase 1)
	  Workspace/Guards/          vazia por agora
	  Workspace/Cameras/         vazia por agora
	  + SpawnLocation do lobby
	  + BotaoAlarmeTeste, para exercitar Furtivo -> Alarme -> Fuga antes de
	    existirem guardas
]]

local MapBuilder = {}

function MapBuilder.init() end

function MapBuilder.start() end

return MapBuilder
