local ADDON, ns = ...
local L = ns.L
L.TAB_SELF_VERIFY = "My verification"
L.SELF_VERIFY_SUBMIT = "Submit code"
if GetLocale and GetLocale() == "ptBR" then
	L.TAB_SELF_VERIFY = "Minha verificação"
	L.SELF_VERIFY_SUBMIT = "Enviar código"
end
