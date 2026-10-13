local ADDON, ns = ...
local L = ns.L
L.CHURCH_FULLNESS_RULE = "Current management: completed UTC days observed above 950 members. Every new appointment starts afresh. Any observation of 950 or fewer breaks the streak. An unobserved or capped day is unknown: no point, no reset. This is client-observed roster evidence, not server certification or proof of continuous 24-hour fullness."
L.CHURCH_FULLNESS_ROW = "%s - %s"
L.CHURCH_FULLNESS_VALUE = "%d days · average %.1f"
L.CHURCH_FULLNESS_ZERO = "0 days"
L.CHURCH_FULLNESS_PAUSED = "%s · unknown day (paused)"
L.CHURCH_FULLNESS_TIP = "Each qualifying day's native roster observations during this person's CURRENT appointment are averaged first; daily averages have equal weight in the tie-break. Every new appointment starts from zero, even when the same person returns. A predecessor's history is never inherited. Incomplete days never score; missing or capped evidence is unknown and pauses only this management's proved streak. No census snapshot or unverified retrospective claim creates a day."
if GetLocale() == "ptBR" then
	L.CHURCH_FULLNESS_RULE = "Gestão atual: dias UTC completos observados com mais de 950 membros. Cada nova nomeação começa do zero. Qualquer observação de 950 ou menos interrompe a sequência. Dia sem observação ou limitado é desconhecido: não pontua nem zera. São evidências do roster observadas por clientes, não certificação do servidor nem prova de lotação contínua por 24 horas."
	L.CHURCH_FULLNESS_ROW = "%s - %s"
	L.CHURCH_FULLNESS_VALUE = "%d dias · média %.1f"
	L.CHURCH_FULLNESS_ZERO = "0 dias"
	L.CHURCH_FULLNESS_PAUSED = "%s · dia desconhecido (pausado)"
	L.CHURCH_FULLNESS_TIP = "Primeiro se calcula a média das observações do roster nativo de cada dia qualificado durante a nomeação ATUAL dessa pessoa; as médias diárias têm peso igual no desempate. Cada nova nomeação começa do zero, inclusive quando a mesma pessoa retorna. O histórico do antecessor nunca é herdado. Dias incompletos não pontuam; evidência ausente ou limitada é desconhecida e pausa somente a sequência comprovada desta gestão. Nenhum censo ou relato retrospectivo não verificado cria um dia."
end
