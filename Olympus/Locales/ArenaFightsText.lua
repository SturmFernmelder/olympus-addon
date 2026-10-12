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
	-- (1.2.4)
	["apostle-1"] = "Light of Olympus", ["apostle-2"] = "Voice of Olympus", ["apostle-3"] = "Herald of Olympus",
	["bones-1"] = "Master of Bones", ["bones-2"] = "Luck's Favourite", ["bones-3"] = "Steady Hand",
	["wanted-slayer-1"] = "Bane of the Horde", ["wanted-slayer-2"] = "Horde Hunter", ["wanted-slayer-3"] = "Bounty Hunter",
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
-- signed by his title alone, never a name.
L.HONOR_LETTER_HEAD = "A letter from the King"
L.HONOR_LETTER_SIGN = "- The King"
L.HONOR_LETTER_WEAR = "Wear it"
L.HONOR_LETTER_LATER = "Later"
L.HONOR_LETTER = {
	arena = "Warrior,\n\nThe sand remembers every blow, and so do I. You stood where others fell, and Olympus names you %s. Wear the gryphon with pride: every eye in the arena is on you now.\n\nDefend it well.",
	class = "Champion,\n\nAmong all who share your calling, none fights as you do. Olympus names you %s. Let your rivals study your every move, and let them fail to match it.",
	race = "Fighter,\n\nYour people have a new standard to follow. Olympus names you %s. Ride at the head of your kin, and let the arena hear of it.",
	["donor-top"] = "Friend,\n\nThe treasury of Olympus stands taller for your generosity. You are named %s, and the cornucopia is yours while your name stays among the three. The realm does not forget those who give.",
	["donor-month"] = "Friend,\n\nThis past month your gold kept Olympus strong. For it you are named %s, and the koi is yours for the month ahead. May your hand stay open.",
	level = "Adventurer,\n\nNobody in Olympus got there before you. The comet is yours, and with it the name %s: a record written for as long as Olympus stands.",
	guild = "Lord,\n\nBy the levels of its members, your guild stands above every other in Olympus. You are named %s, and the owl watches over your banner while your guild leads. Keep them climbing.",
	oracle = "Seer,\n\nLast month you read the arena better than anyone. You are named %s, and the raven is yours for this month. Olympus will be watching your next wager.",
	missionary = "Missionary,\n\nThe flock of Olympus grows because of you: in the last thirty days few brought as many people into our guilds. You are named %s, and the shepherd's crook is yours while you stay among the three. May the flock keep growing.",
	-- (1.2.4)
	apostle = "Apostle,\n\nIn the last thirty days few Apostles brought as many souls to Olympus as you. You are named %s, and the cross is yours while you stay among the three. Keep the faith, and keep them coming.",
	bones = "Player,\n\nThe tavern still talks of your throws last month. You are named %s, and the lucky charm is yours for the month ahead. May the bones fall your way.",
	["wanted-slayer"] = "Slayer,\n\nThe Horde counts its dead, and your name keeps coming up. Olympus names you %s. Ride the skeletal horse where the Horde can see it.",
}

-- 1.2.4, the notices (HonorsNet.Tell): every move on a list after the King's first letter for its
-- place, a strip at the top of the screen and a line in chat. Each list's name, a place's words,
-- and the lines.
L.HONOR_RANKING = { ["donor-top"] = "Top donors", ["donor-month"] = "Donors of the month", guild = "Best guild",
	["wanted-slayer"] = "Slayers", apostle = "Apostles", missionary = "Missionaries", bones = "Bones" }
L.HONOR_PLACE = { "1st", "2nd", "3rd" }
L.HONOR_NOTICE_DOWN = "%s: you dropped to %s place."
L.HONOR_NOTICE_OUT = "%s: you are off the list, and its frame is no longer yours."
L.HONOR_NOTICE_BACK = "%s: you are back on the list, in %s place."
L.HONOR_NOTICE_UP = "%s: you regained %s place."
L.HONOR_NOTICE_GUILD_OUT = "Best guild: your guild is no longer first, and the owl is no longer yours."
L.HONOR_NOTICE_GUILD_BACK = "Best guild: your guild is first again, and the owl is yours again."
L.HONOR_NOTICE_SINCE = "Since your last visit: %s."
L.HONOR_NOTICE_PART_PLACE = "%s, %s place"
L.HONOR_NOTICE_PART_OUT = "%s, off the list"
L.HONOR_NOTICE_MORE = "%d more"

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
-- (1.2.4) A letter held in an instance or Busy: its chat line, and its words on the Decrees tab.
L.HONOR_LETTER_HELD = "A letter from the King awaits you: it opens once you are out of the instance and not Busy (or open the Olympus window to read it now)."
L.HELD_HONOR_LETTER = "a letter from the King"

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
		["apostle-1"] = "Luz do Olympus", ["apostle-2"] = "Voz do Olympus", ["apostle-3"] = "Arauto do Olympus",
		["bones-1"] = "Mestre dos Ossos", ["bones-2"] = "Favorito da Sorte", ["bones-3"] = "Mão Firme",
		["wanted-slayer-1"] = "Ruína da Horda", ["wanted-slayer-2"] = "Caçador da Horda", ["wanted-slayer-3"] = "Caçador de Recompensas",
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
	L.HONOR_LETTER_LATER = "Depois"
	L.HONOR_LETTER = {
		arena = "Guerreiro,\n\nA areia se lembra de cada golpe, e eu também. Você ficou de pé onde outros caíram, e o Olympus o chama de %s. Use o grifo com orgulho: todos os olhos da arena estão em você agora.\n\nDefenda-o bem.",
		class = "Campeão,\n\nEntre todos que seguem o seu caminho, ninguém luta como você. O Olympus o chama de %s. Que os rivais estudem cada movimento seu, e que não consigam igualá-lo.",
		race = "Lutador,\n\nO seu povo tem um novo estandarte a seguir. O Olympus o chama de %s. Cavalgue à frente dos seus, e que a arena ouça falar disso.",
		["donor-top"] = "Amigo,\n\nO tesouro do Olympus está mais alto pela sua generosidade. Você é chamado de %s, e a cornucópia é sua enquanto o seu nome estiver entre os três. O reino não esquece quem dá.",
		["donor-month"] = "Amigo,\n\nNo último mês o seu ouro manteve o Olympus forte. Por isso você é chamado de %s, e o koi é seu pelo mês que vem. Que a sua mão siga aberta.",
		level = "Aventureiro,\n\nNinguém no Olympus chegou lá antes de você. O cometa é seu, e com ele o nome %s: um recorde escrito enquanto o Olympus existir.",
		guild = "Lorde,\n\nPelos níveis dos seus membros, a sua guilda está acima de todas as outras do Olympus. Você é chamado de %s, e a coruja guarda o seu estandarte enquanto a sua guilda liderar. Continue a fazê-los subir.",
		oracle = "Vidente,\n\nNo último mês você leu a arena melhor que qualquer um. Você é chamado de %s, e o corvo é seu por este mês. O Olympus vai observar a sua próxima aposta.",
		missionary = "Missionário,\n\nO rebanho do Olympus cresce por sua causa: nos últimos trinta dias, poucos trouxeram tanta gente para as nossas guildas. Você é chamado de %s, e o cajado é seu enquanto estiver entre os três. Que o rebanho continue a crescer.",
		apostle = "Apóstolo,\n\nNos últimos trinta dias, poucos Apóstolos trouxeram tantas almas ao Olympus quanto você. Você é chamado de %s, e a cruz é sua enquanto estiver entre os três. Mantenha a fé, e que elas continuem a chegar.",
		bones = "Jogador,\n\nA taverna ainda fala dos seus lances do último mês. Você é chamado de %s, e o amuleto da sorte é seu pelo mês que vem. Que os ossos caiam a seu favor.",
		["wanted-slayer"] = "Slayer,\n\nA Horda conta os seus mortos, e o seu nome não para de aparecer. O Olympus o chama de %s. Cavalgue o cavalo esqueleto onde a Horda possa vê-lo.",
	}
	L.HONOR_RANKING = { ["donor-top"] = "Maiores doadores", ["donor-month"] = "Doadores do mês", guild = "Melhor guilda",
		["wanted-slayer"] = "Slayers", apostle = "Apóstolos", missionary = "Missionários", bones = "Bones" }
	L.HONOR_PLACE = { "1º", "2º", "3º" }
	L.HONOR_NOTICE_DOWN = "%s: você caiu para o %s lugar."
	L.HONOR_NOTICE_OUT = "%s: você saiu da lista, e a moldura não é mais sua."
	L.HONOR_NOTICE_BACK = "%s: você voltou à lista, em %s lugar."
	L.HONOR_NOTICE_UP = "%s: você recuperou o %s lugar."
	L.HONOR_NOTICE_GUILD_OUT = "Melhor guilda: a sua guilda não é mais a primeira, e a coruja não é mais sua."
	L.HONOR_NOTICE_GUILD_BACK = "Melhor guilda: a sua guilda é a primeira de novo, e a coruja é sua outra vez."
	L.HONOR_NOTICE_SINCE = "Desde a sua última visita: %s."
	L.HONOR_NOTICE_PART_PLACE = "%s, %s lugar"
	L.HONOR_NOTICE_PART_OUT = "%s, fora da lista"
	L.HONOR_NOTICE_MORE = "mais %d"
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
	L.HONOR_LETTER_HELD = "Uma carta do Rei espera por você: ela abre quando você sair da instância e não estiver Ocupado (ou abra a janela do Olympus para lê-la agora)."
	L.HELD_HONOR_LETTER = "uma carta do Rei"
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
