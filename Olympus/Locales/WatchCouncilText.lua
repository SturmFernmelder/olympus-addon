local ADDON, ns = ...
local L = ns.L
-- 1.2.1: the High Council's own sections in The Watch (Watch.lua: its reports and cases, apart from
-- any guild's), and what the King's client keeps of a council report.
L.WATCH_CASES_TITLE_COUNCIL = "Cases of the High Council"
L.WATCH_COUNCIL_TIP = "Reports from members of every Olympus guild, taken and passed on by the King's client: only from a reporter it already knows in the guild he names, and only with the lines it heard itself in the Olympus channel. The King and the High Council act on them in Olympus's chats, never with a guild's Watch. A report proves nothing by itself."
L.WATCH_REPORT_LINES_COUNCIL = "%d of the %d lines it named, each one the King's client heard itself in the Olympus channel (any other was left out)."
L.WATCH_COUNCIL_DETAIL = "The High Council's reports and cases: from members of every Olympus guild, through the King's client. Nothing here is a sanction until the King or a councillor chooses one in Olympus's chats."
if GetLocale and GetLocale() == "ptBR" then
	L.WATCH_CASES_TITLE_COUNCIL = "Casos do High Council"
	L.WATCH_COUNCIL_TIP = "Denúncias de membros de todas as guildas do Olympus, recebidas e repassadas pelo cliente do King: só de quem ele já conhece na guilda que diz, e só com as linhas que ele mesmo ouviu no canal do Olympus. O King e o High Council agem nelas nos chats do Olympus, nunca com a Watch de uma guilda. Uma denúncia sozinha não prova nada."
	L.WATCH_REPORT_LINES_COUNCIL = "%d das %d linhas que ela indicou, cada uma ouvida pelo próprio cliente do King no canal do Olympus (as outras ficaram de fora)."
	L.WATCH_COUNCIL_DETAIL = "As denúncias e os casos do High Council: de membros de todas as guildas do Olympus, pelo cliente do King. Nada aqui é uma sanção até o King ou um conselheiro escolher uma nos chats do Olympus."
end
