--!strict
--[[
	Sacos de dinheiro (secção 5 do documento) -- ADAPTADOR.

	ESTADO: esqueleto. A logica vai para src/Server/Core/LootCore.luau, com
	testes: quem tem que saco, o limite por jogador, que WalkSpeed aplicar e se
	uma entrega e valida.

	Este ficheiro fica com a parte que so existe dentro do Roblox: criar as Parts
	dos sacos nos marcadores do mapa, o WeldConstraint ao HumanoidRootPart,
	escrever o Humanoid.WalkSpeed e ouvir os Remotes PickUpBag / DropBag.

	Todos os pedidos do cliente passam primeiro pelo ValidacaoCore (ja testado):
	este ficheiro nao faz contas de distancia proprias.
]]

local LootService = {}

function LootService.init() end

function LootService.start() end

return LootService
