--!strict
--[[
	Os cinco estados do assalto (secção 4 do documento).

	Cada chave e igual ao seu valor de proposito: o estado viaja pelo Remote
	HeistStateChanged como texto e e comparado no cliente sem precisar de
	nenhuma tabela de traducao.

	Quem manda nas transicoes e o HeistCore, nao este ficheiro: aqui estao so os
	nomes, porque o cliente tambem precisa deles para o HUD.
]]

local HeistState = {
	-- Jogadores juntam-se; o anfitriao escolhe a dificuldade.
	Lobby = "Lobby",

	-- Assalto a decorrer sem alarme: guardas patrulham, camaras ativas.
	Furtivo = "Furtivo",

	-- Alguem foi visto: vagas de policia, portas trancadas.
	Alarme = "Alarme",

	-- Saque minimo entregue: a carrinha chega e ha tempo para sair.
	Fuga = "Fuga",

	-- Ecra de resultados: pagar dinheiro e XP, voltar ao Lobby.
	Fim = "Fim",
}

return table.freeze(HeistState)
