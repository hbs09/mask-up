--!strict
--[[
	Traduz input em pedidos ao servidor.

	Liga os ProximityPrompt dos sacos e dos objetos aos Remotes, e a tecla G para
	largar o saco.

	NAO verifica distancias nem se o jogador pode agir. Essas verificacoes sao do
	servidor (ValidacaoCore), porque qualquer verificacao feita aqui pode ser
	removida por quem usa um executor. Se este ficheiro precisasse de saber o
	estado do assalto para decidir algo, a decisao estaria no lado errado.

	O ProximityPrompt tem `MaxActivationDistance`, mas isso e conforto, nao
	seguranca: um cliente modificado dispara o Remote sem prompt nenhum. O
	servidor recusa de qualquer maneira.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local InteractController = {}

local TECLA_LARGAR = Enum.KeyCode.G

-- Qual foi o ultimo saco que pedimos para apanhar. Serve so para a tecla G
-- saber o que largar; o servidor e que sabe de verdade quem tem o que.
local ultimoSacoPedido: string? = nil

local function ligarPromptDoSaco(saco: Instance)
	local prompt = saco:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		return
	end

	prompt.Triggered:Connect(function()
		ultimoSacoPedido = saco.Name
		Remotes.PickUpBag:FireServer(saco.Name)
	end)
end

--[[
	Segue a pasta Workspace/Sacos: os sacos sao criados pelo servidor depois do
	cliente arrancar, e voltam a ser criados a cada assalto novo. Sem o
	ChildAdded, os sacos do segundo assalto nao teriam prompt ligado.
]]
local function seguirSacos()
	local pasta = workspace:WaitForChild("Sacos")

	for _, saco in pasta:GetChildren() do
		ligarPromptDoSaco(saco)
	end

	pasta.ChildAdded:Connect(ligarPromptDoSaco)
end

-- Objetos do mundo que usam RequestInteract (por agora, o botao de alarme).
local function ligarPromptDeObjeto(objeto: Instance)
	local prompt = objeto:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		return
	end

	prompt.Triggered:Connect(function()
		Remotes.RequestInteract:FireServer(objeto)
	end)
end

local function seguirObjetos()
	local botao = workspace:WaitForChild("BotaoAlarmeTeste", 30)
	if botao then
		ligarPromptDeObjeto(botao)
	end
end

function InteractController.init() end

function InteractController.start()
	-- Em task.spawn porque usa WaitForChild e nao deve travar o arranque dos
	-- outros controladores se o mapa demorar.
	task.spawn(seguirSacos)
	task.spawn(seguirObjetos)

	UserInputService.InputBegan:Connect(function(input, foiProcessado)
		if foiProcessado then
			return -- o jogador estava a escrever no chat
		end
		if input.KeyCode ~= TECLA_LARGAR then
			return
		end
		if not ultimoSacoPedido then
			return
		end

		Remotes.DropBag:FireServer(ultimoSacoPedido)
	end)

	-- Ao reaparecer, o saco que tinhamos ja nao esta com o personagem novo.
	local jogador = Players.LocalPlayer
	jogador.CharacterAdded:Connect(function()
		ultimoSacoPedido = nil
	end)
end

return InteractController
