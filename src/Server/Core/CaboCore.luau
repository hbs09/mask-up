--!strict
--[[
	O minijogo do cabo (secção 5 do documento).

	> O servidor escolhe o fio certo e guarda-o; o cliente so envia o fio
	> escolhido

	Esse requisito e de SEGURANCA, nao de jogo, e e ele que da forma a este
	modulo. O fio certo vive em `fioCerto` e nunca sai daqui: nem no retorno do
	`escolher`, nem na ordem de `coresDoPuzzle`, nem em mensagem de erro nenhuma.
	O unico sitio por onde a resposta sai e `pista()`, que o servidor usa para
	escrever o esquema escondido no mapa -- e esse texto nunca vai para o cliente
	sem o jogador ter ido fisicamente la ler.

	Modulo PURO, e o gerador de aleatorios e injetado. Sem isso nao se podia
	afirmar nada nos testes sobre qual o fio escolhido.
]]

local CaboCore = {}
CaboCore.__index = CaboCore

export type Config = {
	cores: { string },
}

export type Motivo = "errado" | "fechado" | "nao_aberto" | "cor_invalida"

type Campos = {
	config: Config,
	aleatorio: (quantas: number) -> number,
	-- A resposta. Nunca sai deste modulo a nao ser por `pista()`.
	fioCerto: string?,
	-- Quem tem o painel aberto. Um painel, nao um por pessoa.
	jogadorComPainel: number?,
	resolvido: boolean,
	-- Depois de uma tentativa (certa ou errada) o painel fecha de vez.
	gasto: boolean,
}

export type Core = typeof(setmetatable({} :: Campos, CaboCore))

function CaboCore.novo(deps: { config: Config, aleatorio: (quantas: number) -> number }): Core
	return setmetatable({
		config = deps.config,
		aleatorio = deps.aleatorio,
		fioCerto = nil,
		jogadorComPainel = nil,
		resolvido = false,
		gasto = false,
	}, CaboCore)
end

--[[
	Escolhe o fio certo. Chamado no arranque do assalto.

	O indice do aleatorio e preso a gama valida: um gerador mal comportado --
	ou trocado por engano por um que devolva 0 ou um numero fracionario -- nao
	pode deixar o puzzle sem resposta, porque isso tornava o painel impossivel
	sem ninguem perceber.
]]
function CaboCore.gerarPuzzle(self: Core)
	local quantas = #self.config.cores
	local indice = math.floor(self.aleatorio(quantas))

	indice = math.clamp(indice, 1, quantas)

	self.fioCerto = self.config.cores[indice]
	self.jogadorComPainel = nil
	self.resolvido = false
	self.gasto = false
end

--[[
	As cores a mostrar no painel.

	Devolve uma COPIA e na ordem do Config, nao na do sorteio. As duas coisas
	importam: a copia impede que alguem altere o puzzle a partir de fora, e a
	ordem fixa impede que a posicao do fio certo revele a resposta a quem
	comparasse duas partidas.
]]
function CaboCore.coresDoPuzzle(self: Core): { string }
	if not self.fioCerto then
		return {}
	end

	return table.clone(self.config.cores)
end

--[[
	A resposta, para o servidor escrever no esquema escondido no mapa.

	E o unico caminho por onde o fio certo sai, e e usado para gerar texto que o
	jogador so le se for fisicamente ao esconderijo.
]]
function CaboCore.pista(self: Core): string?
	return self.fioCerto
end

function CaboCore.estaResolvido(self: Core): boolean
	return self.resolvido
end

-- false se o painel ja foi usado. Abrir por outro jogador substitui quem o
-- tinha aberto: e um painel, nao um por pessoa.
function CaboCore.abrir(self: Core, jogadorId: number): boolean
	if not self.fioCerto or self.gasto then
		return false
	end

	self.jogadorComPainel = jogadorId
	return true
end

--[[
	Cortar um fio. Devolve (acertou, motivo).

	Uma cor invalida NAO gasta a tentativa: senao um cliente a enviar lixo tirava
	a tentativa ao jogador, o que seria um exploit ao contrario.
]]
function CaboCore.escolher(self: Core, jogadorId: number, cor: any): (boolean, Motivo?)
	if self.gasto then
		return false, "fechado"
	end
	if not self.fioCerto or self.jogadorComPainel ~= jogadorId then
		return false, "nao_aberto"
	end
	if type(cor) ~= "string" or table.find(self.config.cores, cor) == nil then
		return false, "cor_invalida"
	end

	self.gasto = true
	self.jogadorComPainel = nil

	if cor == self.fioCerto then
		self.resolvido = true
		return true
	end

	-- O motivo e um codigo, nunca a resposta.
	return false, "errado"
end

-- Preparar o assalto seguinte. O fio certo tem de ser sorteado de novo: herdar
-- a resposta tornava o segundo assalto trivial para quem a tivesse decorado.
function CaboCore.reiniciar(self: Core)
	self.fioCerto = nil
	self.jogadorComPainel = nil
	self.resolvido = false
	self.gasto = false
end

return CaboCore
