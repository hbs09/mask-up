--!strict
--[[
	Visao dos guardas e barra de suspeicao (secção 5 do documento:
	"visao = angulo (ex.: 90°) + distancia + raycast sem obstaculos; barra de
	suspeita antes de dar o alarme").

	Modulo PURO: posicoes sao { x, y, z } e o tempo decorrido vem por parametro.
	Nao conhece `game`, `Vector3`, `Humanoid` nem `Raycast`.

	O raycast NAO esta aqui de proposito -- precisa do mundo fisico. A divisao de
	trabalho com o GuardService e:

	    GuardaCore    angulo + distancia  ->  vale a pena lancar um raycast?
	    GuardService  raycast             ->  viu de facto?
	    GuardaCore    suspeicao           ->  ja viu tempo suficiente?

	Esta ordem poupa raycasts: so se lanca um para alvos que ja estao dentro do
	cone, em vez de um por guarda por jogador por tick.
]]

local GuardaCore = {}
GuardaCore.__index = GuardaCore

export type Posicao = { x: number, y: number, z: number }

export type Config = {
	-- Abertura TOTAL do cone, em graus. 90 significa 45° para cada lado.
	angulo: number,
	distancia: number,
	segundosParaDetetar: number,
	segundosParaEsquecer: number,
}

type Campos = {
	config: Config,
	-- Cosseno do meio-angulo, pre-calculado: comparar cossenos evita chamar
	-- math.acos em cada verificacao, e sao muitas por segundo.
	cosseneMeioAngulo: number,
	distanciaQuadrada: number,
	-- [guardaId][alvoId] = nivel de 0 a 1
	suspeita: { [number]: { [number]: number } },
	-- [guardaId][alvoId] = true depois de a barra encher, para `acabouDeDetetar`
	-- ser verdadeiro uma unica vez por travessia.
	jaDetetado: { [number]: { [number]: boolean } },
}

export type Core = typeof(setmetatable({} :: Campos, GuardaCore))

local function numeroFinito(valor: unknown): boolean
	return type(valor) == "number" and valor == valor and valor ~= math.huge and valor ~= -math.huge
end

local function posicaoValida(posicao: unknown): boolean
	if type(posicao) ~= "table" then
		return false
	end

	local p = posicao :: Posicao
	return numeroFinito(p.x) and numeroFinito(p.y) and numeroFinito(p.z)
end

function GuardaCore.novo(deps: { config: Config }): Core
	local config = deps.config

	return setmetatable({
		config = config,
		cosseneMeioAngulo = math.cos(math.rad(config.angulo / 2)),
		distanciaQuadrada = config.distancia * config.distancia,
		suspeita = {},
		jaDetetado = {},
	}, GuardaCore)
end

--[[
	O alvo esta dentro do cone de visao? Angulo e distancia, em tres dimensoes.

	Verificar em 3D e deliberado: um cone so horizontal faria um guarda ver
	alguem dois andares acima, porque no plano a direcao esta certa.

	`olharPara` e a direcao para onde o guarda olha (nao precisa de estar
	normalizada). Devolve false para entradas invalidas, pelo mesmo princípio do
	ValidacaoCore: na duvida, nao ve.
]]
function GuardaCore.dentroDoCone(
	self: Core,
	posGuarda: Posicao,
	olharPara: Posicao,
	posAlvo: Posicao
): boolean
	if
		not posicaoValida(posGuarda)
		or not posicaoValida(olharPara)
		or not posicaoValida(posAlvo)
	then
		return false
	end

	local paraAlvoX = posAlvo.x - posGuarda.x
	local paraAlvoY = posAlvo.y - posGuarda.y
	local paraAlvoZ = posAlvo.z - posGuarda.z

	local distanciaQuadrada = paraAlvoX * paraAlvoX + paraAlvoY * paraAlvoY + paraAlvoZ * paraAlvoZ

	if distanciaQuadrada > self.distanciaQuadrada then
		return false
	end

	-- Alvo exactamente na posicao do guarda: nao ha angulo definido, mas estar
	-- dentro do guarda nao pode contar como estar escondido.
	if distanciaQuadrada == 0 then
		return true
	end

	local olharQuadrado = olharPara.x * olharPara.x
		+ olharPara.y * olharPara.y
		+ olharPara.z * olharPara.z

	-- Direcao nula nao tem orientacao, e normalizar seria divisao por zero.
	if olharQuadrado == 0 then
		return false
	end

	--[[
		Comparamos o cosseno do angulo em vez do angulo.

		cos(angulo) = (a . b) / (|a| * |b|)

		O cosseno decresce com o angulo, por isso "dentro do cone" e
		`cosseno >= cos(meioAngulo)`. Isto evita um math.acos por verificacao, e
		sao muitas: 3 guardas x 4 jogadores x 5 vezes por segundo.
	]]
	local produtoInterno = paraAlvoX * olharPara.x
		+ paraAlvoY * olharPara.y
		+ paraAlvoZ * olharPara.z
	local cosseno = produtoInterno / math.sqrt(distanciaQuadrada * olharQuadrado)

	return cosseno >= self.cosseneMeioAngulo
end

local function nivelAtual(self: Core, guardaId: number, alvoId: number): number
	local porGuarda = self.suspeita[guardaId]
	return (porGuarda and porGuarda[alvoId]) or 0
end

function GuardaCore.suspeitaDe(self: Core, guardaId: number, alvoId: number): number
	return nivelAtual(self, guardaId, alvoId)
end

-- A suspeicao do guarda que mais notou este alvo. Serve o indicador visual: o
-- jogador quer saber o pior caso, nao a media.
function GuardaCore.maiorSuspeitaDe(self: Core, alvoId: number): number
	local maior = 0

	for _, porGuarda in self.suspeita do
		local nivel = porGuarda[alvoId]
		if nivel and nivel > maior then
			maior = nivel
		end
	end

	return maior
end

--[[
	Faz a barra subir ou descer e diz se foi AGORA que ela encheu.

	`viuAgora` ja inclui o resultado do raycast feito pelo adaptador.

	Devolve (nivel de 0 a 1, acabouDeDetetar). O segundo valor e verdadeiro uma
	unica vez por travessia: sem isso, o alarme seria pedido 5 vezes por segundo
	enquanto o jogador continuasse a vista. O AlarmService tambem ignora
	repeticoes, mas depender disso seria contar com a rede de seguranca em vez
	da logica.

	Esquecer e mais lento que detetar (`segundosParaEsquecer` >
	`segundosParaDetetar`), para quem foi notado ter de se esconder de verdade em
	vez de sair da vista por um instante.
]]
function GuardaCore.atualizarSuspeita(
	self: Core,
	guardaId: number,
	alvoId: number,
	dt: number,
	viuAgora: boolean
): (number, boolean)
	local nivel = nivelAtual(self, guardaId, alvoId)

	-- dt invalido ou negativo: nao mexer na barra, em vez de a corromper.
	if not numeroFinito(dt) or dt < 0 then
		return nivel, false
	end

	if viuAgora then
		nivel = math.min(1, nivel + dt / self.config.segundosParaDetetar)
	else
		nivel = math.max(0, nivel - dt / self.config.segundosParaEsquecer)
	end

	local porGuarda = self.suspeita[guardaId]
	if porGuarda == nil then
		porGuarda = {}
		self.suspeita[guardaId] = porGuarda
	end
	porGuarda[alvoId] = nivel

	local detetados = self.jaDetetado[guardaId]
	if detetados == nil then
		detetados = {}
		self.jaDetetado[guardaId] = detetados
	end

	local acabouDeDetetar = false
	if nivel >= 1 then
		if not detetados[alvoId] then
			detetados[alvoId] = true
			acabouDeDetetar = true
		end
	elseif nivel <= 0 then
		-- So depois de esquecer por completo e que pode voltar a "descobrir" o
		-- mesmo jogador. Rearmar a meio da barra daria alarmes aos pares.
		detetados[alvoId] = nil
	end

	return nivel, acabouDeDetetar
end

-- Chamar quando um jogador sai, para as tabelas nao crescerem sem fim.
function GuardaCore.esquecerAlvo(self: Core, alvoId: number)
	for _, porGuarda in self.suspeita do
		porGuarda[alvoId] = nil
	end
	for _, detetados in self.jaDetetado do
		detetados[alvoId] = nil
	end
end

-- Preparar o assalto seguinte.
function GuardaCore.reiniciar(self: Core)
	self.suspeita = {}
	self.jaDetetado = {}
end

return GuardaCore
