local ADDON, ns = ...
local L = ns.L

-- 1.2, the Blood Arena: the words of the fights part (fights and honours; the chat marks part's few strings too), English then a ptBR block (the pattern of
-- Locales.lua). Empty until that package fills it; loaded before Core.lua (Olympus.toc).

-- The fighter's nickname (the design): two fixed lists, never free text (the King's screen shows it).
-- ARENA_EPI_ORDER: "an" (adjective, noun) or "na" (noun, adjective); ARENA_EPI_FMT puts the two.
L.ARENA_EPI_A = { "Unbroken", "Crimson", "Silent", "Iron", "Golden", "Swift", "Grim", "Wild", "Stone", "Storm", "Night", "Blood",
	"Ashen", "Frost", "Burning", "Hollow", "Steel", "Thunder", "Shadow", "Radiant", "Savage", "Ancient", "Restless", "Fearless",
	"Grinning", "Howling", "Scarlet", "Bitter", "Dauntless", "Laughing", "Wandering", "Last" }
L.ARENA_EPI_N = { "Wolf", "Hammer", "Storm", "Blade", "Fang", "Shield", "Lion", "Bear", "Serpent", "Hawk", "Raven", "Boar", "Stag",
	"Fist", "Anvil", "Thorn", "Viper", "Tempest", "Warden", "Reaper", "Butcher", "Hound", "Gryphon", "Tiger", "Oak", "Axe", "Spear",
	"Flame", "Ghost", "Dragon", "Kodo", "Murloc" }
L.ARENA_EPI_ORDER = "an"
L.ARENA_EPI_FMT = "the %s %s"

-- The honours' titles (the design): one table, so the moderators can edit them. A class's and a
-- race's are patterns with the class's or the race's name (gold, silver, bronze).
L.HONOR_TITLES = {
	["arena-champion"] = "Arena Champion", ["arena-champion-2"] = "Arena Contender", ["arena-champion-3"] = "Arena Challenger",
	["donor-top-1"] = "Patron of Olympus", ["donor-top-2"] = "Benefactor of Olympus", ["donor-top-3"] = "Friend of the Treasury",
	["donor-month-1"] = "Golden Hand", ["donor-month-2"] = "Silver Hand", ["donor-month-3"] = "Bronze Hand",
	["level-race-20"] = "First to 20", ["level-race-40"] = "First to 40", ["level-race-60"] = "First to 60",
	["guild-top-leader"] = "Wisest of Olympus",
	["oracle-1"] = "Oracle", ["oracle-2"] = "Seer", ["oracle-3"] = "Soothsayer",
	["missionary-1"] = "Good Shepherd", ["missionary-2"] = "Faithful Shepherd", ["missionary-3"] = "Shepherd",
	["the-dev"] = "The Royal Dev",
}
L.HONOR_CLASS_TITLE = { "%s Champion", "%s Contender", "%s Challenger" }
L.HONOR_RACE_TITLE = { "Best %s Fighter", "%s Contender", "%s Challenger" }
L.HONOR_CLASS_NAMES = { warrior = "Warrior", paladin = "Paladin", hunter = "Hunter", rogue = "Rogue", priest = "Priest", shaman = "Shaman",
	mage = "Mage", warlock = "Warlock", druid = "Druid" }
L.HONOR_RACE_NAMES = { human = "Human", dwarf = "Dwarf", nightelf = "Night Elf", gnome = "Gnome", orc = "Orc", undead = "Undead",
	tauren = "Tauren", troll = "Troll" }
L.HONOR_METAL_GOLD, L.HONOR_METAL_SILVER, L.HONOR_METAL_BRONZE = "gold", "silver", "bronze"

-- The King's letter (the design): one per family, in his voice, naming the honour's title (%s);
-- signed by his title alone, never a name. (1.2.4, the author: the King talks the way he talks on
-- stream, plain and blunt, not a herald's speech.)
L.HONOR_LETTER_HEAD = "A letter from the King"
L.HONOR_LETTER_SIGN = "- The King"
L.HONOR_LETTER_WEAR = "Wear it"
-- (1.2.4: Most Wanted's Slayer letter, its first button: the Wanted tab.)
L.HONOR_LETTER_SLAYERS = "Slayers"
L.HONOR_LETTER_LATER = "Later"
L.HONOR_LETTER = {
	arena = "Okay, listen.\n\nYou walked into the arena and beat everybody. Not most people. Everybody. So you're %s now, and the gryphon is yours.\n\nHeads up: every tryhard in Olympus wants it off you now. Don't let them.",
	class = "Hey,\n\nI checked. Of everyone playing your class in Olympus, nobody fights like you. That's huge. You're %s now.\n\nThe rest of them are gonna study every move you make. Let them. They still won't keep up.",
	race = "Hey,\n\nYour whole race just got a new name to brag about, and it's yours. You're %s now.\n\nGo show your people how it's done.",
	["donor-top"] = "Dude,\n\nYou've put more gold into Olympus than almost anyone. That's not a little, that's insane. You're %s, and the cornucopia stays yours as long as you stay in the top three.\n\nI see it, and so does everybody else. Thank you.",
	["donor-month"] = "Hey,\n\nLast month your gold kept the lights on in Olympus. Genuinely, thank you. You're %s, and the koi is yours for the month.\n\nKeep that hand open.",
	level = "Holy.\n\nYou got there before anybody else in Olympus. First. Nobody can ever take that from you. The comet is yours, and so is the name %s.\n\nNow go touch some grass. Or don't. Respect either way.",
	guild = "Listen,\n\nYour guild has the highest levels in all of Olympus. Top of the list. You're %s, and the owl sits on your banner while your guild stays first.\n\nKeep your people climbing, because the others are coming.",
	oracle = "Okay,\n\nLast month you called the arena better than anyone. Fight after fight, you just knew. You're %s, and the raven is yours this month.\n\nEverybody's gonna copy your picks now. Can't blame them.",
	missionary = "Hey,\n\nIn the last thirty days you brought more people into our guilds than almost anyone. That's how Olympus grows. You're %s, and the shepherd's crook is yours while you stay in the top three.\n\nKeep bringing them in.",
}

-- The rankings' switches (the owner's one compact view).
L.ARENA_PERIOD_TODAY = "Today"
L.ARENA_PERIOD_WEEK = "This week"
L.ARENA_PERIOD_MONTH = "This month"
L.ARENA_PERIOD_ALL = "All time"
L.ARENA_CAT_GLOBAL = "Global"
L.ARENA_CLASS_NAMES = { WA = "Warrior", PA = "Paladin", HU = "Hunter", RO = "Rogue", PR = "Priest", SH = "Shaman", MA = "Mage", WL = "Warlock", DR = "Druid" }
L.ARENA_RACE_NAMES = { [1] = "Human", [2] = "Orc", [3] = "Dwarf", [4] = "Night Elf", [5] = "Undead", [6] = "Tauren", [7] = "Gnome", [8] = "Troll" }

-- Fight Nights, tournaments, the week's rows.
L.ARENA_CARD_NO = "Fight Night #%d"
L.ARENA_TOURNEY = "Tournament"
L.ARENA_WEEK_CARD_TIP = "The Blood Arena: %d bouts. Open the Arena tab for the card."
L.ARENA_WEEK_FIGHT = "%s vs %s"

-- 1.2.3, the duels: a challenge refused for a reason (Kit.Why), and a confirmed win that earned no
-- qualification points (ArenaFights.QualNote: the opponent, then why).
L.FIGHTS_WHY_BUSY = "You already have a duel open with this player: fight it first, or let it lapse."
L.FIGHTS_WHY_EXPIRED = "That challenge lapsed."
L.ARENA_QUAL_NONE = "Your win over %s earned no qualification points: %s."
L.ARENA_QUAL_WHY_NATIVE = "the game did not end that duel here (no duel finished)"
L.ARENA_QUAL_WHY_REPORT = "the two clients did not report the same result"
L.ARENA_QUAL_WHY_INT = "one of you was killed by something else during the duel"
L.ARENA_QUAL_WHY_UNSEEN = "this client did not see both characters during the duel (target your opponent)"
L.ARENA_QUAL_WHY_GUILD = "one of you is not in an Olympus guild"
L.ARENA_QUAL_WHY_REALM = "one of you is on a realm outside the realm group"
L.ARENA_QUAL_WHY_LEVEL = "a level could not be read"
L.ARENA_QUAL_WHY_SHORT = "it lasted under 15 seconds, or its length was not seen"
L.ARENA_QUAL_WHY_DAY = "your 10 counted duels for today are done"
L.ARENA_QUAL_WHY_PAIR = "3 counted duels against this opponent in 7 days are done"
L.ARENA_QUAL_WHY_LEVELS = "your opponent is 10 or more levels below you (0 points)"

-- The Chronicle's lines (what this client saw done).
L.ARENA_CHRONICLE_CORRECT = "corrected the result of fight %s, round %d"
L.ARENA_CHRONICLE_RULED = "ruled fight %s, round %d, himself (no duel line agreed)"
L.ARENA_CHRONICLE_SEASON = "opened arena season %d"
L.ARENA_CHRONICLE_TAKEOVER = "took over tournament %s"
L.ARENA_CHRONICLE_DRAW = "draw disputed: tournament %s, step %d (the roll seen here differs)"
L.ARENA_CHRONICLE_WORD = "belt word %s for %s"
L.ARENA_CHRONICLE_DISPUTED = "fight %s, round %d: the arbiter's duel line against the reports (disputed)"

-- The person card, the history's Consent line.
L.ARENA_PERSON_LINE = "Arena: %d  (%d-%d)"
L.ARENA_PERSON_PROFILE = "Arena profile"
-- (1.1.6, the games' ledger: the privacy page's one line, Consent.Intro)
L.CONSENT_GAMES_RECORDED = "Game results are recorded: each game you play (Bones, the Arena, the Lottery's practice: when, who, the result and the score) shows in your own list and goes to the King, the High Council and the author (and the auditors he signs), nobody else."
L.ARENA_CONSENT_HISTORY = "Show my list of fights on my arena profile"
L.ARENA_CONSENT_HISTORY_TEXT = "Your record, rating, tier and belts always show (the rankings need them). This chooses whether your list of fights shows too. Fights of public events (a Fight Night, a tournament, a public arbiter's bout) show whatever you choose: their cards and brackets show them anyway. The Olympus channel can be read by anyone on it: this chooses what the addon shows, not what a modified client could read."

-- The profile's Edit (ProfileEdit.lua).
L.PROFILE_EDIT_TITLE = "My arena profile"
L.PROFILE_FRAME_RANK = "My rank's frame"
L.PROFILE_FRAME_NONE = "No frame"
L.PROFILE_FRAME_RED_CROSS = "Red cross (only you see it)"
L.PROFILE_TITLE_NONE = "No title"
L.PROFILE_FRAME = "Frame: %s"
L.PROFILE_TITLE = "Title: %s"
L.PROFILE_NICK_A = "Epithet"
L.PROFILE_NICK_N = "Beast"
L.PROFILE_EMBLEM = "Emblem"
L.PROFILE_HISTORY_PUBLIC = "History: public"
L.PROFILE_HISTORY_PRIVATE = "History: private"
L.PROFILE_LOCK = "Keep my pick"
L.PROFILE_LOCKED = "Pick kept"
L.PROFILE_LETTERS = "The King's letters"
L.PROFILE_COUNCIL_ICON = "My council icon"
L.PROFILE_HONOURS = "Your honours"
L.PROFILE_NO_HONOURS = "None yet: belts, podiums, donations, the level race, the Oracle, the best guild."
L.PROFILE_PREVIEW = "As others see you: %s\nNickname: %s"
L.PROFILE_ICON_REFUSED = "That icon can't be used here: pick one of your honours' marks (or, for your emblem, one of the game's icons)."
L.HONOR_LETTER_WAITING = "A letter from the King awaits you: open the Olympus window or your arena profile to read it."

if GetLocale and GetLocale() == "ptBR" then
	L.ARENA_EPI_A = { "Inquebrável", "Carmesim", "Silencioso", "de Ferro", "de Ouro", "Veloz", "Sombrio", "Selvagem", "de Pedra", "da Tempestade",
		"da Noite", "de Sangue", "Cinzento", "Gélido", "Ardente", "Vazio", "de Aço", "do Trovão", "das Sombras", "Radiante", "Feroz", "Ancestral",
		"Inquieto", "Destemido", "Risonho", "Uivante", "Escarlate", "Amargo", "Intrépido", "Gargalhante", "Errante", "Derradeiro" }
	L.ARENA_EPI_N = { "Lobo", "Martelo", "Temporal", "Gume", "Dente", "Escudo", "Leão", "Urso", "Serpente", "Falcão", "Corvo", "Javali", "Cervo",
		"Punho", "Malho", "Espinho", "Víbora", "Furacão", "Guardião", "Ceifador", "Açougueiro", "Cão", "Grifo", "Tigre", "Carvalho", "Machado",
		"Arpão", "Fogo", "Fantasma", "Dragão", "Kodo", "Murloc" }
	L.ARENA_EPI_ORDER = "na"
	L.ARENA_EPI_FMT = "o %s %s"
	L.HONOR_TITLES = {
		["arena-champion"] = "Campeão da Arena", ["arena-champion-2"] = "Desafiante da Arena", ["arena-champion-3"] = "Pretendente da Arena",
		["donor-top-1"] = "Patrono do Olympus", ["donor-top-2"] = "Benfeitor do Olympus", ["donor-top-3"] = "Amigo do Tesouro",
		["donor-month-1"] = "Mão de Ouro", ["donor-month-2"] = "Mão de Prata", ["donor-month-3"] = "Mão de Bronze",
		["level-race-20"] = "Primeiro ao 20", ["level-race-40"] = "Primeiro ao 40", ["level-race-60"] = "Primeiro ao 60",
		["guild-top-leader"] = "O Mais Sábio do Olympus",
		["oracle-1"] = "Oráculo", ["oracle-2"] = "Vidente", ["oracle-3"] = "Adivinho",
		["missionary-1"] = "Bom Pastor", ["missionary-2"] = "Pastor Fiel", ["missionary-3"] = "Pastor",
		["the-dev"] = "The Royal Dev",
	}
	L.HONOR_CLASS_TITLE = { "Campeão %s", "Desafiante %s", "Pretendente %s" }
	L.HONOR_RACE_TITLE = { "Melhor Lutador %s", "Desafiante %s", "Pretendente %s" }
	L.HONOR_CLASS_NAMES = { warrior = "Guerreiro", paladin = "Paladino", hunter = "Caçador", rogue = "Ladino", priest = "Sacerdote", shaman = "Xamã",
		mage = "Mago", warlock = "Bruxo", druid = "Druida" }
	L.HONOR_RACE_NAMES = { human = "Humano", dwarf = "Anão", nightelf = "Elfo Noturno", gnome = "Gnomo", orc = "Orc", undead = "Morto-vivo",
		tauren = "Tauren", troll = "Troll" }
	L.HONOR_METAL_GOLD, L.HONOR_METAL_SILVER, L.HONOR_METAL_BRONZE = "ouro", "prata", "bronze"
	L.HONOR_LETTER_HEAD = "Uma carta do Rei"
	L.HONOR_LETTER_SIGN = "- O Rei"
	L.HONOR_LETTER_WEAR = "Usar"
	L.HONOR_LETTER_SLAYERS = "Slayers"
	L.HONOR_LETTER_LATER = "Depois"
	L.HONOR_LETTER = {
		arena = "Olha só.\n\nVocê entrou na arena e ganhou de todo mundo. Não da maioria. De todo mundo. Agora você é %s, e o grifo é seu.\n\nSó avisando: todo tryhard do Olympus vai querer tirar ele de você. Não deixa.",
		class = "E aí,\n\nEu conferi. De todo mundo da sua classe no Olympus, ninguém luta como você. Isso é enorme. Agora você é %s.\n\nO resto vai estudar cada movimento seu. Deixa. Mesmo assim não vão te acompanhar.",
		race = "E aí,\n\nA sua raça inteira ganhou um nome novo pra se gabar, e é o seu. Agora você é %s.\n\nVai lá mostrar pro seu povo como se faz.",
		["donor-top"] = "Cara,\n\nVocê colocou mais ouro no Olympus do que quase todo mundo. Isso não é pouca coisa, é insano. Você é %s, e a cornucópia fica com você enquanto estiver entre os três primeiros.\n\nEu vejo, e todo mundo vê também. Valeu mesmo.",
		["donor-month"] = "E aí,\n\nNo mês passado o seu ouro manteve as luzes do Olympus acesas. Sério, obrigado. Você é %s, e o koi é seu este mês.\n\nContinua com essa mão aberta.",
		level = "Caramba.\n\nVocê chegou lá antes de qualquer um no Olympus. Primeiro. Isso ninguém tira de você nunca mais. O cometa é seu, e o nome %s também.\n\nAgora vai tocar grama. Ou não. Respeito de qualquer jeito.",
		guild = "Escuta,\n\nA sua guilda tem os níveis mais altos de todo o Olympus. Topo da lista. Você é %s, e a coruja fica no seu estandarte enquanto a sua guilda for a primeira.\n\nMantém o seu pessoal subindo, porque os outros estão vindo.",
		oracle = "Olha,\n\nNo mês passado você leu a arena melhor que qualquer um. Luta após luta, você simplesmente sabia. Você é %s, e o corvo é seu este mês.\n\nAgora todo mundo vai copiar os seus palpites. Não dá pra culpar.",
		missionary = "E aí,\n\nNos últimos trinta dias você trouxe mais gente pras nossas guildas do que quase todo mundo. É assim que o Olympus cresce. Você é %s, e o cajado é seu enquanto estiver entre os três primeiros.\n\nContinua trazendo.",
	}
	L.ARENA_PERIOD_TODAY = "Hoje"
	L.ARENA_PERIOD_WEEK = "Esta semana"
	L.ARENA_PERIOD_MONTH = "Este mês"
	L.ARENA_PERIOD_ALL = "Desde sempre"
	L.ARENA_CAT_GLOBAL = "Geral"
	L.ARENA_CLASS_NAMES = { WA = "Guerreiro", PA = "Paladino", HU = "Caçador", RO = "Ladino", PR = "Sacerdote", SH = "Xamã", MA = "Mago", WL = "Bruxo", DR = "Druida" }
	L.ARENA_RACE_NAMES = { [1] = "Humano", [2] = "Orc", [3] = "Anão", [4] = "Elfo Noturno", [5] = "Morto-vivo", [6] = "Tauren", [7] = "Gnomo", [8] = "Troll" }
	L.ARENA_CARD_NO = "Noite da Luta #%d"
	L.ARENA_TOURNEY = "Torneio"
	L.ARENA_WEEK_CARD_TIP = "A Arena de Sangue: %d lutas. Abra a aba Arena para ver o card."
	L.ARENA_WEEK_FIGHT = "%s contra %s"
	L.FIGHTS_WHY_BUSY = "Você já tem um duelo aberto com esse jogador: lutem esse primeiro, ou deixem expirar."
	L.FIGHTS_WHY_EXPIRED = "Esse desafio expirou."
	L.ARENA_QUAL_NONE = "Sua vitória sobre %s não deu pontos de qualificação: %s."
	L.ARENA_QUAL_WHY_NATIVE = "o jogo não encerrou esse duelo aqui (nenhum duelo terminado)"
	L.ARENA_QUAL_WHY_REPORT = "os dois clientes não relataram o mesmo resultado"
	L.ARENA_QUAL_WHY_INT = "um de vocês foi morto por outra coisa durante o duelo"
	L.ARENA_QUAL_WHY_UNSEEN = "este cliente não viu os dois personagens durante o duelo (mire no adversário)"
	L.ARENA_QUAL_WHY_GUILD = "um de vocês não está numa guilda Olympus"
	L.ARENA_QUAL_WHY_REALM = "um de vocês está num reino fora do grupo de reinos"
	L.ARENA_QUAL_WHY_LEVEL = "não deu para ler um nível"
	L.ARENA_QUAL_WHY_SHORT = "durou menos de 15 segundos, ou a duração não foi vista"
	L.ARENA_QUAL_WHY_DAY = "seus 10 duelos que contam hoje já foram"
	L.ARENA_QUAL_WHY_PAIR = "3 duelos que contam contra esse adversário em 7 dias já foram"
	L.ARENA_QUAL_WHY_LEVELS = "seu adversário está 10 ou mais níveis abaixo de você (0 pontos)"
	L.ARENA_CHRONICLE_CORRECT = "corrigiu o resultado da luta %s, round %d"
	L.ARENA_CHRONICLE_RULED = "decidiu a luta %s, round %d, ele mesmo (nenhuma linha de duelo concordou)"
	L.ARENA_CHRONICLE_SEASON = "abriu a temporada %d da arena"
	L.ARENA_CHRONICLE_TAKEOVER = "assumiu o torneio %s"
	L.ARENA_CHRONICLE_DRAW = "sorteio contestado: torneio %s, passo %d (a rolagem vista aqui é outra)"
	L.ARENA_CHRONICLE_WORD = "palavra de cinturão %s para %s"
	L.ARENA_CHRONICLE_DISPUTED = "luta %s, round %d: a linha de duelo do árbitro contra os relatos (contestada)"
	L.ARENA_PERSON_LINE = "Arena: %d  (%d-%d)"
	L.ARENA_PERSON_PROFILE = "Perfil da arena"
	L.CONSENT_GAMES_RECORDED = "Os resultados dos jogos ficam registrados: cada jogo que você joga (Bones, a Arena, o treino da Loteria: quando, quem, o resultado e o placar) aparece na sua própria lista e vai para o Rei, o Alto Conselho e o autor (e os auditores que ele assina), mais ninguém."
	L.ARENA_CONSENT_HISTORY = "Mostrar a minha lista de lutas no meu perfil da arena"
	L.ARENA_CONSENT_HISTORY_TEXT = "O seu cartel, rating, divisão e cinturões sempre aparecem (os rankings precisam deles). Isto escolhe se a sua lista de lutas aparece também. Lutas de eventos públicos (uma Noite da Luta, um torneio, uma luta de árbitro público) aparecem seja qual for a sua escolha: os cards e chaves delas já as mostram. O canal do Olympus pode ser lido por quem estiver nele: isto escolhe o que o addon mostra, não o que um cliente modificado poderia ler."
	L.PROFILE_EDIT_TITLE = "Meu perfil da arena"
	L.PROFILE_ICON_REFUSED = "Esse ícone não serve aqui: escolha a marca de uma das suas honras (ou, para o emblema, um ícone do jogo)."
	L.HONOR_LETTER_WAITING = "Uma carta do Rei espera por você: abra a janela do Olympus ou o seu perfil da arena para lê-la."
	L.PROFILE_FRAME_RANK = "A moldura do meu posto"
	L.PROFILE_FRAME_NONE = "Sem moldura"
	L.PROFILE_FRAME_RED_CROSS = "Cruz vermelha (só você a vê)"
	L.PROFILE_TITLE_NONE = "Sem título"
	L.PROFILE_FRAME = "Moldura: %s"
	L.PROFILE_TITLE = "Título: %s"
	L.PROFILE_NICK_A = "Epíteto"
	L.PROFILE_NICK_N = "Fera"
	L.PROFILE_EMBLEM = "Emblema"
	L.PROFILE_HISTORY_PUBLIC = "Histórico: público"
	L.PROFILE_HISTORY_PRIVATE = "Histórico: privado"
	L.PROFILE_LOCK = "Manter a escolha"
	L.PROFILE_LOCKED = "Escolha mantida"
	L.PROFILE_LETTERS = "As cartas do Rei"
	L.PROFILE_COUNCIL_ICON = "Meu ícone do conselho"
	L.PROFILE_HONOURS = "As suas honrarias"
	L.PROFILE_NO_HONOURS = "Nenhuma ainda: cinturões, pódios, doações, a corrida de níveis, o Oráculo, a melhor guilda."
	L.PROFILE_PREVIEW = "Como os outros o veem: %s\nApelido: %s"
end
