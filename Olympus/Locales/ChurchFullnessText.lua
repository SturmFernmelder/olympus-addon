local ADDON, ns = ...
local L = ns.L
L.CHURCH_FULLNESS_RULE = "Completed UTC days observed above 950 members. Any observation of 950 or fewer breaks the streak. An unobserved or capped day is unknown: no point, no reset. This is client-observed roster evidence, not server certification or proof of continuous 24-hour fullness."
L.CHURCH_FULLNESS_ROW = "%s — %s"
L.CHURCH_FULLNESS_VALUE = "%d days · average %.1f"
L.CHURCH_FULLNESS_ZERO = "0 days"
L.CHURCH_FULLNESS_PAUSED = "%s · unknown day (paused)"
L.CHURCH_FULLNESS_TIP = "Each qualifying day's native roster observations are averaged first; those daily averages have equal weight in the streak's tie-break. Current incomplete days never score. No census snapshot or unverified retrospective claim creates a day. Retained private keeper evidence is bounded; missing history stays unknown. This is the GUILD's observed streak, shown with its current correspondent, not a claim about that person's tenure."
if GetLocale() == "ptBR" then
	L.CHURCH_FULLNESS_RULE = "Dias UTC completos observados com mais de 950 membros. Qualquer observação de 950 ou menos interrompe a sequência. Dia sem observação ou limitado é desconhecido: não pontua nem zera. São evidências do roster observadas por clientes, não certificação do servidor nem prova de lotação contínua por 24 horas."
	L.CHURCH_FULLNESS_ROW = "%s — %s"
	L.CHURCH_FULLNESS_VALUE = "%d dias · média %.1f"
	L.CHURCH_FULLNESS_ZERO = "0 dias"
	L.CHURCH_FULLNESS_PAUSED = "%s · dia desconhecido (pausado)"
	L.CHURCH_FULLNESS_TIP = "Primeiro se calcula a média das observações do roster nativo de cada dia qualificado; essas médias diárias têm peso igual no desempate da sequência. Dias ainda em andamento não pontuam. Nenhum censo atual ou relato retrospectivo não verificado cria um dia. As evidências privadas retidas pelos responsáveis são limitadas; histórico ausente permanece desconhecido. É a sequência observada da GUILDA, mostrada com seu correspondente atual, não uma afirmação sobre o mandato dessa pessoa."
end
