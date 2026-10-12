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

--[[
	O table.freeze e superficial: congelar so o Config deixava Config.sacos e
	Config.tempos a descoberto, que sao exatamente as tabelas que alguem poderia
	alterar por engano. Esta funcao desce a arvore toda.

	Congela no lugar em vez de devolver a tabela: uma versao generica
	`<T>(tabela: T): T` nao passa o verificador de tipos, porque o table.freeze
	devolve um tipo selado que nao se relaciona com o T de entrada.
]]
local function congelarProfundo(tabela: { [any]: any })
	for _, valor in tabela do
		if type(valor) == "table" then
			congelarProfundo(valor)
		end
	end

	table.freeze(tabela)
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

	-- Passado a GuardaCore.novo(). Secção 5 do documento: "visao = angulo
	-- (ex.: 90°) + distancia + raycast sem obstaculos; barra de suspeita antes
	-- de dar o alarme".
	visao = {
		angulo = 90, -- abertura TOTAL do cone: 45° para cada lado
		--[[
			20 e nao 40, e o motivo e geometrico em vez de gosto.

			O cone de um guarda cobre (angulo/360) * pi * r². Com r = 40 isso da
			1257 studs quadrados, e tres guardas cobriam 3770 numa loja de 2400 --
			157% da area. Havia mais visao do que chao, e portanto nenhuma rota
			furtiva possivel. Com r = 20 a cobertura cai para 39% e ha janelas
			reais.

			O Config.spec fixa esta relacao como invariante, para afinar isto nao
			voltar a tornar o assalto impossivel em silencio.
		]]
		distancia = 20,
		-- Tempo a vista descoberta antes de o guarda dar o alarme. Atravessar um
		-- cone de passagem nao deve custar o assalto.
		segundosParaDetetar = 2.5,
		-- Tempo escondido para a barra voltar a zero. Mais longo que o de
		-- detetar de proposito: quem foi notado tem de se esconder de verdade,
		-- em vez de sair da vista por um instante.
		segundosParaEsquecer = 4,
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

	-- Comportamento dos guardas. Quantos sao e como se mexem; o que VEEM esta
	-- em `visao`, porque as cameras da Fase 1 vao reutilizar esse cone.
	guardas = {
		quantidade = 3, -- secção 8: 3 a 4 guardas
		velocidade = 8, -- mais lentos que o jogador (16), para dar para contornar
		--[[
			Pausa em cada waypoint. Sem ela a ronda e um circuito continuo e nunca
			ha janelas para atravessar.

			3 segundos e nao 2: parado, o cone do guarda e previsivel e da-se para
			aprender a ronda. Em movimento continuo o cone varre a sala e a unica
			tatica possivel e esperar por sorte.
		]]
		pausaNoWaypoint = 3,
		--[[
			Desenhar as arestas do cone de visao no chao.

			Serve para testar, mas provavelmente fica no jogo final: sem isto,
			saber se estas dentro do campo de visao de um guarda e adivinhar, e
			um jogo furtivo em que a fronteira nao se ve e um jogo de sorte.
			Se um dia se quiser uma dificuldade mais dura, passa a false.
		]]
		mostrarCone = true,
	},

	-- Quantos pontos de saque o MapBuilder cria. O Config.spec usa estes valores
	-- para garantir que ha saque suficiente para atingir minimoSacosParaFuga.
	mapa = {
		montras = 4,
		cofres = 1,
		camaras = 2, -- Fase 1
		civis = 3, -- Fase 1
	},
}

congelarProfundo(Config)

return Config
