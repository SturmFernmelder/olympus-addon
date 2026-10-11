local ADDON, ns = ...
local L = ns.L
L.MAINKEY_ON, L.MAINKEY_OFF = "on", "off"
L.MAINKEY_STATUS = "Olympus Y shortcut: %s. Only an unbound Y is used; saved bindings are never changed. /oly hotkey on|off"
L.HELP_MAINKEY = "  /oly hotkey on|off - open/close Olympus with Y, only when Y is unbound (mouse and keyboard)."
if GetLocale and GetLocale() == "ptBR" then
	L.MAINKEY_ON, L.MAINKEY_OFF = "ligado", "desligado"
	L.MAINKEY_STATUS = "Atalho Y do Olympus: %s. Só usa Y sem atribuição; suas teclas salvas não são alteradas. /oly hotkey on|off"
	L.HELP_MAINKEY = "  /oly hotkey on|off - abre/fecha Olympus com Y, somente se Y estiver livre (mouse e teclado)."
end
