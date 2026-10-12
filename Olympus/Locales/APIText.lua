local ADDON, ns = ...
local L = ns.L
-- 1.2.4: the Olympus API for other addons (API.lua): each addon's line on the privacy page.
L.API_CONSENT_LABEL = "Another addon: %s"
L.API_CONSENT_TEXT = "It asks to read what Olympus shows you: the Wanted list and its bounties, the public rankings, your own frame and title, your guild, rank and role. Never your location, the census, other players' private data or Olympus's keys, and it sends nothing for you. Yes: it reads them on this computer. No, or no answer: it gets nothing. Each addon is asked on its own; Accept all never answers for it."
if GetLocale and GetLocale() == "ptBR" then
	L.API_CONSENT_LABEL = "Outro addon: %s"
	L.API_CONSENT_TEXT = "Ele pede para ler o que o Olympus mostra a você: a lista de Wanted e suas recompensas, os rankings públicos, sua moldura e seu título, sua guilda, seu posto e sua função. Nunca a sua localização, o censo, dados privados de outros jogadores ou as chaves do Olympus, e ele não envia nada por você. Sim: ele lê isso neste computador. Não, ou sem resposta: ele não recebe nada. Cada addon é perguntado à parte; Aceitar tudo nunca responde por ele."
end
