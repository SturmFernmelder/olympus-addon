local _, ns = ...
local L = ns.L
L.DUESROSTER_SHARE = "Share native reset checkpoints privately with the federal Treasurer"
L.DUESROSTER_PRIVACY = "Optional, off by default and expires after 31 days. Your current native Guild Master client captures complete member names and confirmed alt groups near both weekly resets. Only the pinned federal Treasurer receives those signed observations, not public OlympusNet. Missing or incomplete evidence stays unknown. Turning this off revokes retained coverage. No money, invitations, punishment, or feature restrictions are automatic."
L.DUESROSTER_FOREIGN = "Private recorded weeks: %s (complete signed Guild Master checkpoints only)"
L.DUESROSTER_NO_PROOF = "Private reset sharing unavailable: current signed leadership proof missing"
if GetLocale and GetLocale() == "ptBR" then
	L.DUESROSTER_SHARE = "Compartilhar checkpoints nativos do reset em privado com o Tesoureiro federal"
	L.DUESROSTER_PRIVACY = "Opcional, desligado por padrão e expira em 31 dias. O cliente do Guild Master nativo atual captura nomes completos e grupos de alts confirmados perto dos dois resets semanais. Só o Tesoureiro federal fixado recebe essas observações assinadas, nunca a OlympusNet pública. Provas ausentes ou incompletas continuam desconhecidas. Desligar revoga a cobertura retida. Não há dinheiro, convites, punição ou restrições automáticos."
	L.DUESROSTER_FOREIGN = "Semanas privadas registradas: %s (somente checkpoints completos do Guild Master assinados)"
	L.DUESROSTER_NO_PROOF = "Compartilhamento privado indisponível: falta a prova assinada da liderança atual"
end
