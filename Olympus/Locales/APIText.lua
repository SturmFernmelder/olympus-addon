local ADDON, ns = ...
local L = ns.L
-- 1.2.4: the Olympus API for other addons (API.lua): each addon's line on the privacy page. Its
-- promises are Olympus's own (review of 1.2.4): what the other addon does with what it read is its own.
L.API_CONSENT_LABEL = "Another addon: %s"
L.API_CONSENT_TEXT = "It asks to read what Olympus shows you: the Wanted list and its bounties, the public rankings, your own frame and title, your guild, rank and role. Never your location, the census, other players' private data or Olympus's keys. Yes: Olympus lets it read them on this computer, sends nothing for it and gives it no way to send anything for you; what that addon then does with what it read is up to that addon, so say Yes only to addons you trust. No, or no answer: it gets nothing. Each addon is asked on its own; Accept all never answers for it."
if GetLocale and GetLocale() == "ptBR" then
	L.API_CONSENT_LABEL = "Outro addon: %s"
	L.API_CONSENT_TEXT = "Ele pede para ler o que o Olympus mostra a você: a lista de Wanted e suas recompensas, os rankings públicos, sua moldura e seu título, sua guilda, seu posto e sua função. Nunca a sua localização, o censo, dados privados de outros jogadores ou as chaves do Olympus. Sim: o Olympus permite que ele leia isso neste computador, não envia nada por ele e não lhe dá meio de enviar nada por você; o que esse addon faz depois com o que leu é com ele, então diga Sim só a addons em que você confia. Não, ou sem resposta: ele não recebe nada. Cada addon é perguntado à parte; Aceitar tudo nunca responde por ele."
end
