local _, ns = ...
local L = ns.L
L.JUSTICE_RESPONSE_TITLE = "Response time - private retained evidence"
L.JUSTICE_RESPONSE_COVERAGE = "Original issuer and assignee signatures only; at most 60 requests for 30 days. Lower median receipt-to-manual-attempt time sorts first. Sample size, unknown delivery, pending and human-confirmed completion are separate; this is not quality or proof of who caused removal."
L.JUSTICE_TASKS_UNKNOWN_TIME = "unknown"
L.JUSTICE_RESPONSE_COUNTS = "Received: %d · timed attempts: %d · pending: %d · human-confirmed: %d · cancelled: %d · delivery unknown: %d"
L.JUSTICE_RESPONSE_UNVERIFIED = "Legacy/local-only: %d · original evidence or current authority unknown: %d. Neither is ranked."
L.JUSTICE_RESPONSE_SYNC = "Original proofs awaiting keys or verification: %d. Partial private coverage; an offline or older client is not inactivity."
if GetLocale and GetLocale() == "ptBR" then
	L.JUSTICE_RESPONSE_TITLE = "Tempo de resposta - provas privadas retidas"
	L.JUSTICE_RESPONSE_COVERAGE = "Somente assinaturas originais do emissor e destinatário; até 60 pedidos por 30 dias. A menor mediana entre recebimento e tentativa manual aparece primeiro. Amostra, entrega desconhecida, pendências e conclusão confirmada por pessoa são medidas separadas; não avalia qualidade nem prova quem causou a expulsão."
	L.JUSTICE_TASKS_UNKNOWN_TIME = "desconhecido"
	L.JUSTICE_RESPONSE_COUNTS = "Recebidos: %d · tentativas cronometradas: %d · pendentes: %d · confirmados por pessoa: %d · cancelados: %d · entrega desconhecida: %d"
	L.JUSTICE_RESPONSE_UNVERIFIED = "Legados/somente locais: %d · prova original ou autoridade atual desconhecida: %d. Nenhum entra na classificação."
	L.JUSTICE_RESPONSE_SYNC = "Provas originais aguardando chaves ou verificação: %d. Cobertura privada parcial; cliente offline ou antigo não significa inatividade."
end
