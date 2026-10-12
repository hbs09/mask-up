--!strict
--[[
	A maquina de estados do assalto (secção 4 do documento) e as contas do
	pagamento.

	Modulo PURO: nao conhece `game`, Remotes, jogadores nem temporizadores.
	Trabalha com ids de jogador (numeros) e e avisado de fora quando o tempo
	acaba. Isso tem duas consequencias boas:

	  - testar o fim da fuga e instantaneo, em vez de esperar 60 segundos;
	  - so existe um sitio onde as regras do assalto vivem, e esse sitio nao
	    depende do Studio para correr.

	Quem traduz isto para o mundo do Roblox e o HeistService: ouve
	`aoMudarEstado` e envia o Remote HeistStateChanged, e usa `task.delay` para
	os temporizadores.
]]

local HeistCore = {}
HeistCore.__index = HeistCore

export type Saco = { valor: number, velocidade: number }

export type Config = {
	minimoSacosParaFuga: number,
	sacos: { [string]: Saco },
	recompensas: {
		bonusFurtivo: number,
		xpPorSacoPequeno: number,
		xpPorSacoGrande: number,
	},
}

export type Estados = { [string]: string }

export type Pagamento = {
	valorBruto: number,
	dinheiroPorJogador: number,
	xpPorJogador: number,
	bonusFurtivoAplicado: boolean,
}

export type ResultadoEntrega = {
	aceite: boolean,
	motivo: string?,
	totalSacos: number,
	chamouFuga: boolean,
}

type Campos = {
	config: Config,
	estados: Estados,
	transicoes: { [string]: { string } },
	estado: string,
	houveAlarme: boolean,
	motivoAlarme: string?,
	sacosPorJogador: { [number]: number },
	valorAcumulado: number,
	xpAcumulado: number,
	totalSacos: number,
	ouvintes: { (novo: string, anterior: string) -> () },
	avisar: (mensagem: string) -> (),
}

export type Core = typeof(setmetatable({} :: Campos, HeistCore))

--[[
	`avisar` e opcional e serve para reportar erros em ouvintes.

	Nao chamamos `warn` diretamente porque `warn` e um global do Roblox, e este
	modulo tem de continuar a correr fora do Studio -- o selene recusa globais
	do Roblox em Core/ precisamente para impedir essa fuga. Mas engolir o erro
	em silencio esconderia bugs, por isso quem monta o core decide para onde vai
	a mensagem: o HeistService passa `warn`, os testes passam um recolhor.
]]
export type Deps = {
	config: Config,
	estados: Estados,
	avisar: ((mensagem: string) -> ())?,
}

function HeistCore.novo(deps: Deps): Core
	local e = deps.estados

	--[[
		As transicoes legais. Esta tabela e a regra: tudo o que nao esta aqui e
		recusado, em vez de ser permitido por omissao.

		Alem do caminho normal da secção 4, inclui duas saidas para Fim que o
		documento implica sem as desenhar: ele diz que se entra em Fim por
		"todos presos ou tempo esgotado", e so se e preso depois do alarme --
		sem Alarme -> Fim essa condicao do proprio documento era inalcancavel.
	]]
	local transicoes = {
		[e.Lobby] = { e.Furtivo },
		[e.Furtivo] = { e.Alarme, e.Fuga, e.Fim },
		[e.Alarme] = { e.Fuga, e.Fim },
		[e.Fuga] = { e.Fim },
		[e.Fim] = { e.Lobby },
	}

	local self = setmetatable({
		config = deps.config,
		estados = e,
		transicoes = transicoes,
		estado = e.Lobby,
		houveAlarme = false,
		motivoAlarme = nil,
		sacosPorJogador = {},
		valorAcumulado = 0,
		xpAcumulado = 0,
		totalSacos = 0,
		ouvintes = {},
		avisar = deps.avisar or function() end,
	}, HeistCore)

	return self
end

function HeistCore.estadoAtual(self: Core): string
	return self.estado
end

function HeistCore.transicoesPossiveis(self: Core, estado: string): { string }
	return self.transicoes[estado] or {}
end

-- Registar um ouvinte para cada mudanca de estado. E assim que o HeistService
-- sabe que tem de enviar o Remote, sem o core conhecer Remotes.
function HeistCore.aoMudarEstado(self: Core, ouvinte: (novo: string, anterior: string) -> ())
	table.insert(self.ouvintes, ouvinte)
end

local function avisarOuvintes(self: Core, novo: string, anterior: string)
	for _, ouvinte in self.ouvintes do
		--[[
			Protegido de proposito: se o HUD de um jogador tiver um bug, o assalto
			tem de continuar para os outros em vez de parar a meio de uma
			transicao.

			xpcall e nao pcall porque o ouvinte nao devolve nada, e nesse caso o
			tipo do pcall e so `(boolean)` -- ler um segundo valor com a mensagem
			de erro era um erro de aridade. O handler do xpcall recebe o erro
			diretamente.
		]]
		xpcall(ouvinte, function(erro)
			self.avisar(
				string.format(
					"[HeistCore] ouvinte falhou em %s->%s: %s",
					anterior,
					novo,
					tostring(erro)
				)
			)
		end, novo, anterior)
	end
end

--[[
	Muda de estado, se a transicao for legal.
	Devolve (true) ou (false, motivo) com motivo em "estado_desconhecido" ou
	"transicao_ilegal".
]]
function HeistCore.transitar(self: Core, novo: any): (boolean, string?)
	if type(novo) ~= "string" or self.transicoes[novo] == nil then
		return false, "estado_desconhecido"
	end

	local permitidas = self.transicoes[self.estado]
	if not table.find(permitidas, novo) then
		return false, "transicao_ilegal"
	end

	local anterior = self.estado
	self.estado = novo

	if novo == self.estados.Alarme then
		self.houveAlarme = true
	end

	avisarOuvintes(self, novo, anterior)

	return true
end

--[[
	A unica forma de ir para Alarme. Devolve false se o alarme nao se aplica
	(ja esta a tocar, ou o assalto nao esta em Furtivo) -- o documento pede
	exatamente isto, para tres guardas a verem o mesmo jogador nao dispararem o
	alarme tres vezes.
]]
function HeistCore.dispararAlarme(self: Core, motivo: string): boolean
	if self.estado ~= self.estados.Furtivo then
		return false
	end

	local ok = self:transitar(self.estados.Alarme)
	if ok then
		self.motivoAlarme = motivo
	end

	return ok
end

-- O motivo do PRIMEIRO disparo, que e o que interessa para perceber o que
-- correu mal no assalto.
function HeistCore.motivoDoAlarme(self: Core): string?
	return self.motivoAlarme
end

function HeistCore.totalSacosEntregues(self: Core): number
	return self.totalSacos
end

function HeistCore.sacosDoJogador(self: Core, jogadorId: number): number
	return self.sacosPorJogador[jogadorId] or 0
end

-- true se o assalto nunca passou pelo Alarme.
function HeistCore.foiFurtivo(self: Core): boolean
	return not self.houveAlarme
end

--[[
	Registar um saco entregue na carrinha.

	Aceita em Furtivo, Alarme e Fuga: continuar a saquear enquanto se corre para
	a carrinha e uma decisao de jogo, nao um descuido.

	Quando o total atinge `minimoSacosParaFuga`, chama a fuga -- e e aqui que
	isso e decidido, uma vez so, em vez de em cada servico que entrega sacos.
]]
function HeistCore.registarSacoEntregue(
	self: Core,
	jogadorId: number,
	tipoSaco: string
): ResultadoEntrega
	local estadosQueAceitam = {
		self.estados.Furtivo,
		self.estados.Alarme,
		self.estados.Fuga,
	}

	if not table.find(estadosQueAceitam, self.estado) then
		return {
			aceite = false,
			motivo = "estado",
			totalSacos = self.totalSacos,
			chamouFuga = false,
		}
	end

	local saco = self.config.sacos[tipoSaco]
	if not saco then
		return {
			aceite = false,
			motivo = "tipo_desconhecido",
			totalSacos = self.totalSacos,
			chamouFuga = false,
		}
	end

	self.totalSacos += 1
	self.sacosPorJogador[jogadorId] = (self.sacosPorJogador[jogadorId] or 0) + 1
	self.valorAcumulado += saco.valor

	local recompensas = self.config.recompensas
	self.xpAcumulado += if tipoSaco == "grande"
		then recompensas.xpPorSacoGrande
		else recompensas.xpPorSacoPequeno

	-- Chamar a fuga so na transicao, nao em cada saco a partir dai.
	local chamouFuga = false
	if self.totalSacos >= self.config.minimoSacosParaFuga and self.estado ~= self.estados.Fuga then
		chamouFuga = self:transitar(self.estados.Fuga)
	end

	return { aceite = true, motivo = nil, totalSacos = self.totalSacos, chamouFuga = chamouFuga }
end

--[[
	O que pagar no ecra final.

	Cada jogador recebe o TOTAL, nao uma fatia: dividir penalizava equipas
	maiores, o que contraria "o cooperativo e o trunfo do jogo" do documento, e
	e tambem a convencao do genero. Para passar a dividir, basta dividir
	`dinheiroPorJogador` pelo numero de jogadores aqui.

	O bonus furtivo aplica-se so ao dinheiro. Multiplicar tambem o xp fazia a
	progressao disparar de maneira dificil de equilibrar.
]]
function HeistCore.calcularPagamento(self: Core): Pagamento
	local furtivo = self:foiFurtivo()
	local multiplicador = if furtivo then self.config.recompensas.bonusFurtivo else 1

	return {
		valorBruto = self.valorAcumulado,
		dinheiroPorJogador = math.floor(self.valorAcumulado * multiplicador),
		xpPorJogador = self.xpAcumulado,
		bonusFurtivoAplicado = furtivo and self.valorAcumulado > 0,
	}
end

--[[
	Preparar o assalto seguinte.

	Os ouvintes NAO sao removidos: o HeistService registou-se uma vez no arranque
	e tem de continuar a receber as mudancas nos assaltos seguintes.
]]
function HeistCore.reiniciar(self: Core)
	self.estado = self.estados.Lobby
	self.houveAlarme = false
	self.motivoAlarme = nil
	self.sacosPorJogador = {}
	self.valorAcumulado = 0
	self.xpAcumulado = 0
	self.totalSacos = 0
end

return HeistCore
