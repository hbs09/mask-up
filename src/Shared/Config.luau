--!strict
--[[
	Todos os numeros do jogo num unico sitio.

	Regra de ouro nº4 do documento: "Configuracao em tabelas (valores dos sacos,
	precos, tempos), nunca numeros espalhados pelo codigo". Se precisares de
	afinar o equilibrio do jogo, e aqui -- e so aqui.

	Esta congelado (table.freeze) para nenhum servico lhe poder escrever em
	runtime: um bug desses mudava o jogo para todos os jogadores do servidor e
	seria muito dificil de encontrar.

	Os valores sao os iniciais da secção 8 do documento ("ajustar nos testes").
	As invariantes entre eles estao fixadas em tests/Config.spec.luau -- incluindo
	a mais importante, que o assalto tem de ser ganhavel.
]]

-- O table.freeze e superficial: congelar so o Config deixava Config.sacos e
-- Config.tempos a descoberto, que sao exatamente as tabelas que alguem poderia
-- alterar por engano. Esta funcao desce a arvore toda.
local function congelarProfundo<T>(tabela: T): T
	for _, valor in tabela :: any do
		if type(valor) == "table" then
			congelarProfundo(valor)
		end
	end

	return table.freeze(tabela :: any)
end

local Config = {
	-- Secção 8: especificacao do primeiro assalto, a Joalharia.
	assalto = {
		jogadoresMaximos = 4,
		duracaoAlvoSegundos = { minimo = 300, maximo = 600 },
	},

	-- Quanto vale cada saco e quao lento fica quem o carrega.
	sacos = {
		pequeno = { valor = 5000, velocidade = 14 }, -- montras
		grande = { valor = 20000, velocidade = 10 }, -- cofre
	},

	velocidadeNormal = 16, -- o WalkSpeed por omissao do Roblox

	-- Um saco por jogador; dois com o Game Pass da Fase 5.
	limiteSacosPorJogador = 1,

	-- Secção 8: "minimo de 2 sacos para chamar a fuga".
	minimoSacosParaFuga = 2,

	-- Passado diretamente a ValidacaoCore.novo(), por isso os nomes dos campos
	-- tem de corresponder aos que esse modulo espera.
	interacao = {
		distanciaMaxima = 12,
		cooldown = 0.5,
	},

	tempos = {
		lobby = 15, -- espera antes de arrancar o assalto
		fuga = 60, -- tempo para chegar a carrinha depois de ela aparecer
		fim = 10, -- ecra de resultados antes de voltar ao Lobby
	},

	recompensas = {
		-- Multiplicador por terminar sem nunca disparar o alarme.
		bonusFurtivo = 1.25,
		xpPorSacoPequeno = 50,
		xpPorSacoGrande = 150,
	},

	progressao = {
		-- Passado a PerfilCore.novo(). Custo do nivel n para n+1 = xpBase * n.
		xpBase = 100,
		nivelMaximo = 50,
	},

	-- Quantos pontos de saque o MapBuilder cria. O Config.spec usa estes valores
	-- para garantir que ha saque suficiente para atingir minimoSacosParaFuga.
	mapa = {
		montras = 4,
		cofres = 1,
		guardas = 3, -- secção 8: 3 a 4 guardas
		camaras = 2,
		civis = 3,
	},
}

return congelarProfundo(Config)
