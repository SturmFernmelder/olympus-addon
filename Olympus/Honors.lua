local ADDON, ns = ...

-- Olympus honours (1.2): frames and titles a player earns (arena belts and their podium, the
-- top donors, the level race, the guild with the highest average level, the month's best
-- predictors), which of them a player shows, and the rules that decide who holds each. Pure
-- functions over the values passed in: no events, no messages, no saved data, no WoW API. The
-- treasury, the census, the arena, the bank and the profile feed them and keep what they return.
--
-- Who works them out. The donor rankings, the level race's book, the podium and the Oracle are
-- the realm's, not each client's: one authority runs Donors, LevelRace, Podium and Oracle and
-- broadcasts what they return (the Treasurer's client for the donors, since his book's lines
-- never leave it, Treasury.DuesLine; a clerk for the level race and the podium; a bank for the
-- Oracle; how it is signed or pinned is the spec's to say). Every other client takes those lists
-- and that book as given and only runs Holdings, Update and Shown on them. Clients that ran
-- LevelRace on what each of them heard would keep different places forever, and a viewer whose
-- book differs would refuse a real pick. Given the same lists and book, every client works out
-- the same honours, so a viewer checks a player's pick himself (Honors.Shown) and never takes it
-- on his word.
--
-- The honours (one extra title besides the Olympus rank, one portrait frame, and the nameplate
-- mark that goes with the frame):
--   belt         the arena's belts: global ("A"), per class ("C" and the class's two letters, as
--                Roster.ClassCode gives them), per race ("R" and UnitRace's race ID). Held while
--                the arena's belt registry names the player (inputs.belts).
--   podium       the silver (2nd) and bronze (3rd) of a belt's category: the first two fighters
--                of the category's table, other than the belt's holder, among those eligible for
--                contender status (Honors.Podium). A vacant belt still gives its silver and
--                bronze (to the table's first two). Held while the podium words name the player
--                (inputs.podium). One family with the belt: gold (the belt) 1, silver 2, bronze 3.
--   tier         the arena's small tier badge (bronze, silver, gold): a badge beside the name in
--                the arena's own screens, no frame, no mark, no title (it never goes on unit
--                frames or nameplates, where bronze, silver and gold already mean the rank).
--   donor-top    the top 3 donors of all time (the cornucopia).
--   donor-month  the top 3 donors of the last month (1st to 3rd; 4th and below nothing), held
--                through the month after it; the month running is the race (Donors().race.month)
--                (the koi).
--   level        the FIRST to reach level 20 (bronze), 40 (silver) and 60 (gold), per realm and
--                faction: permanent, never taken away (the comet; the addon writes the level on
--                its blank medallion). One place per milestone (the owner's honours table, the design
--                the design: the 2nd and 3rd at every 10 levels are gone).
--   oracle       the month's three best predictors (gold, silver and bronze raven): net profit
--                divided by the total staked over the month's settled public markets, at least
--                ORACLE_MIN_MARKETS markets (Honors.Oracle); held through the month after the one
--                scored, as donor-month is.
--   guild        the leader (guild master) of the Olympus guild with the highest average level
--                (the owl, gold only: frame and title). Its members get nothing (the design).
--   missionary   (1.2.3) the Church's top 3 missionaries over the last 30 days (gold, silver and
--                bronze; 4th and below nothing): the Church's top 3 (ChurchCount.Top3, its NR~1~t
--                word: taken from the Head's, the King's or the author's client, no other's; sent
--                by the author's alone, ChurchCount.SendTop, while it is online with the public
--                ranking open), held while that word names him and is no older than its own 30
--                days (the shepherd's crook with its sleeping lamb).
--   apostle      (1.2.4) the Church's top 3 Apostles over the last 30 days: the same NR~1~t word
--                as the missionaries' (its first list), held as theirs (the cross: gold, silver,
--                bronze).
--   bones        (1.2.4) the top 3 players of Bone Throw of the last month (FarkleTable.Best, the
--                games both players' halves agree on, as this client holds them; at least one win),
--                held through the month after it, as donor-month is (the lucky charm).
--   wanted-slayer (1.2.4) the Slayers' signed top 3 (Wanted.GlobalSnapshot's rows: all time, by
--                verified GUID), by his GUID alone, never a name (the skeletal horse; it was the
--                orc's wolf, the arena's, until 1.2.4).
-- Gone with the design: the week's top donor (Donors still works the week out, for the race
-- views; no honour comes of it) and the phoenix.
-- The guild-rank frames (Borders.TIERS, and Borders.MarkOf's marks) stay as they are: "rank" is
-- the frame a player shows when he picks it, has nothing else, or his pick no longer holds.
-- Donor honours show whatever the King's treasury switches say (the owner's decision): nothing
-- here reads them.
--
-- Keys (plain [a-z0-9-], safe in a message). An honour's key names it in a pick (its frame and
-- its title); its art (Honors.ArtOf) is the stem of its files in Olympus/media/honors/:
-- "<art>.tga" the portrait frame, "<art>-mark.tga" its nameplate mark (scripts/make-honors.py
-- brings them in from the finished frames), with its shape ("winged" 220 x 180 of a 256 canvas,
-- "plain" 200 x 200: Borders.lua places them as Max's bronze frames):
--   arena-champion (gryphon-gold, winged), arena-class-<class> (arena-class-mage: mage-gold, the
--     class's beast), arena-race-<race> (arena-race-nightelf: nightsaber-gold, the race's mount);
--   the podium: the belt's key and -2 (silver) or -3 (bronze): arena-champion-2 (gryphon-silver),
--     arena-class-mage-3 (mage-bronze);
--   donor-top-<1-3> (cornucopia-gold/-silver/-bronze), donor-month-<1-3> (koi-...),
--   oracle-<1-3> (raven-...), guild-top-leader (owl-gold, winged);
--   (1.2.3) missionary-<1-3> (crook-gold/-silver/-bronze, plain);
--   (1.2.4) apostle-<1-3> (cross-gold/-silver/-bronze), bones-<1-3> (charm-...), wanted-slayer-<1-3>
--     (skeletal-horse-...), all plain;
--   level-race-<milestone> (level-race-20: comet-bronze, -40 comet-silver, -60 comet-gold; the
--     milestone written on it);
--   the tier's badge: arena-tier-<bronze|silver|gold> (the crossed swords of the arena's
--     division, a badge in the arena's screens: no frame, no mark, no title).
--   A pick's frame may also be "rank" (the Olympus rank's frame) or "none".
--   1.2.1, a preview only (Honors.PREVIEWS: the author's /oly borders test <key>; no honour has
--   these keys, so nobody holds, wears or is awarded them): arena-race-skyborn (owlcat-gold; -2, -3
--   silver and bronze), plain; and apostle-red (cross-red, plain, on the black underlay: its metal
--   "black"), also a signed Apostle's own look on his own screen (Borders.OwnLook), never anyone's
--   honour. (The Apostles' crosses and the Bones' charms were previews too until 1.2.4.)
--
-- API
--   Honors.Key(name) -> key or nil
--       A player's key as honours compare names: through ns.Normal (Forever's "First-Surname",
--       as the game's unit functions give it, is "First Surname"), lower case, no realm
--       (Forever's names are one across a realm group), as Dues.Key.
--   Honors.WeekOf(t, anchor) -> week number
--       The dues' week (Dues.WeekOf): from one weekly reset to the next on the server's clock.
--       anchor: the reset, seconds into a week of the clock (Dues.Anchor()); default RESET_US.
--   Honors.MonthOf(t, offset) -> month number (year * 12 + month - 1)
--       The calendar month of server time t on the realm's clock. offset: seconds from UTC, or
--       function(t) -> seconds (a realm with daylight saving: its offset at t); default 0.
--   Honors.MonthDate(month) -> year, month (1-12)
--   Honors.Donors(gifts, now, opts) -> { all, week, month, weekNo, monthNo, race = { week, month, weekNo, monthNo } }
--       Run by the donors' authority (above); everyone else takes its lists as given.
--       gifts: book lines as Treasury.Record keeps them:
--         { name, money (integer copper), t (server time), kind, out, item, excluded, noted,
--           wk (Dues.Stamp's week), note (a mail's subject, where known), treasurer }
--         treasurer: the line is in a book of the Treasurer's characters (Treasury.DuesLine):
--         that book's name (his dues are taken off per book, as Treasury.PublicRanking does), or
--         true for one book.
--         Or a giver's sum over a stretch of time in the same shape (t: when it got there), with
--         his dues already taken off (Treasury.PublicRanking's) and never `treasurer` (the dues
--         would be taken off once more, and for one week only).
--         Or a giver's sum for one window, as the Treasury's book keeps them (per calendar month
--         and per week, per giver: a book keeps too few lines for a month): the same shape plus
--         window = "all" | "month" | "week", counted in that window alone (its week: wk, else
--         the week of t; its month: the month of t). Its dues already taken off: `treasurer`
--         and `noted` change nothing. Any other window value: no gift.
--       What counts is what the Treasury's ranking counts (Treasury.lua's Add): a line not
--       excluded, no payment, no item, no transfer between keepers, and no arena money (kind "fee"
--       or "arena", or a mail's subject starting "Arena " or "Olympus arena"). A sale, purchase or
--       own line a keeper counted back in (Treasury.Toggle) counts, as it does there.
--       Of the gold in a Treasurer's book, each giver's week counts only above what may be his
--       dues, as the public ranking counts it (Dues.DuesPart): max(0, gold - max(amount, noted
--       gold)). In any other book the dues' note changes nothing (the ranking counts it too).
--       opts: { anchor, offset (see WeekOf, MonthOf), duesAmount, kept }
--         duesAmount: copper, or function(week, book) -> copper: the week's amount as that book
--         kept it (Dues' s.amounts[week]; never Dues.AmountOf for a week gone, Konig's review of
--         1.1); default DUES_AMOUNT.
--         kept: what an earlier call returned, saved by the caller. The closed week's and month's
--         top donors are worked out once, at the first call after they close, and then kept as
--         they were: a book relayed late, or a noted mail stamped for last week, changes nothing
--         while they are held.
--       Each list is { name, key, money, at, place }, most first; a tie goes to who reached the
--       amount first (at: when his total got there), then by name. all: the top 3 of all time;
--       month: the top 3 of the last month (monthNo); week: the top 1 of the last week (weekNo);
--       race.week, race.month: every giver of the week and month running. Honours ask DONOR_MIN.
--   Honors.LevelRace(book, claims, now, opts) -> book, fresh, pending
--       Run by the level race's authority (above); everyone else keeps the book it broadcasts,
--       passed through LevelRace(book, nil, now) to tidy it.
--       book: the places recorded, { [milestone] = { { guid, name, t, place }, ... } } (kept
--       forever; a place in it never changes here: 1.2.1, the caller takes out one the server's
--       word shows false, HonorsNet.CheckPlaces). GUIDs are compared as Holdings compares them (the
--       game's form and the short one are one) and kept as given.
--       claims: level-ups seen happening, { name, guid, level, from, since, t, vouched }:
--         t: when the voucher's census saw him at `level` (its clock, never the player's word);
--         from, since: the level it saw him at before, and when. A claim counts for the
--         milestones it was seen crossing: from < m <= level; without from (the level-up itself
--         seen, at t), m == level only. A player seen for the first time (who joined an Olympus
--         guild at 25, or a veteran when 1.2 ships) makes no claim.
--         vouched: the caller's proof that he is there (HonorsNet.Vouched: the server's roster, or
--         two census senders of his guild; 1.2.1: never one census row), not only his own word.
--       opts: { start }: the race's start (server time). A claim whose crossing may be earlier
--       (since, or t without it, before start) counts for nothing.
--       Returns the new book (a copy), fresh (the places recorded by this call: { milestone,
--       place, guid, name, t }) and pending (per milestone, the claims still waiting, in order:
--       vouched ones younger than CONFIRM_AFTER, and every unvouched one, which never takes a place).
--   Honors.GuildRanking(rows, opts) -> list; Honors.GuildTop(rows, opts) -> row or nil
--       rows: census rows { guild, leader, members (or total), avgLevel, faction, t, off }, a list
--       or a map by guild (ns.rdb.guilds). Highest average first (to the tenth, as the census
--       carries it), then more members, then the guild's name. A guild needs GUILD_MIN_MEMBERS.
--       opts: { faction, skip, now, maxAge }
--         faction: that faction's rows only (a row without one: none).
--         skip: function(guild, row) -> true to leave a guild out. The census's rows need it: the
--         caller leaves out net-off guilds (Data.NetOff) and any no longer Olympus
--         (ns.IsFederation), which the rows don't say.
--         now, maxAge: with now, a row whose report (t, on the same clock) is older than maxAge
--         (default GUILD_MAX_AGE), or has no time, is left out: a guild gone quiet can't win.
--       The leader passed on (GuildTop's) should be the one the census vouches for (two senders,
--       as Data.KnownRank asks), as the borders do.
--   Honors.Podium(cat, ranking, holder, eligible) -> { { cat, place, guid, name }, ... }
--       Run by the clerk at each ledger change (and by a viewer holding the ledger, to check the
--       clerk's words); everyone else takes the words. The silver (place 2) and bronze (place 3)
--       of a belt's category: the first two rows of the category's table, in the order given
--       (ArenaRating.Ranking's: best first), other than the holder, for which eligible(row) is
--       true (contender status: the ledger's rules; nil: every row). holder: the belt's holder
--       (his GUID), nil while it is vacant. A row: { guid or key (the fighter's GUID), name }.
--       A category without a belt (a level bracket, anything else) has no podium: {}. GUIDs are
--       compared as Holdings compares them (the game's form and the short one are one); each
--       row's guid is returned as the ranking gave it.
--   Honors.OracleScores(bets, month, opts) -> rows
--       A bank's rows for one month, from its ledger's bets (the rows other banks whisper to the
--       one that publishes). bets: { name, market, stake (whole copper, > 0), payout (whole
--       copper the bet returned, >= 0), t (the market's settlement, server time), at (the bet's
--       time; default t), mode, public, void, cur (the currency its market's sheet froze) }.
--       opts: { cur, mode, offset, bank }
--         cur (required): the currency scored: "g" (gold, or a rehearsal's capped copper), "p"
--         (glory points), "c" (a rehearsal's chips), as the realm's or the rehearsal's markets
--         run. Without it, no rows: gold, points and chips never add up, and nothing guesses.
--         mode: "L" (default: the live arena) or "T" (a rehearsal).
--         bank: the bank these rows are from (its name), carried on each row for Oracle.
--       A bet counts when its market is public (public = true), settled (not void: a refund
--       predicts nothing), of opts.mode, of opts.cur (b.cur the same; a bet without cur counts
--       for nothing), and settled in `month` (MonthOf of t, with opts.offset: the settlement's
--       month, not the bet's). month: a MonthOf number.
--       A row per bettor, by key: { name, key, profit (the payouts less the stakes), staked,
--       markets (how many different markets), first (his earliest bet's time), cur, bank }.
--   Honors.Oracle(rows, opts) -> top, ranked
--       The month's Oracle from the rows of every bank (a bettor's rows add up: his markets were
--       held by one bank each). A row: { name, profit, staked, markets, first, cur, bank }.
--         bank (optional; a name): a bank's later row for a bettor replaces its earlier one (the
--         caller lists rows as heard: a bank's whisper heard twice counts once). Rows without a
--         bank all add up, so the caller gives every row its bank.
--         cur (optional): the row's currency. opts.cur, when given, keeps the rows of that
--         currency (and those without cur, taken as it); without it, rows of two currencies (or
--         of one beside rows naming none) rank nobody ({}, {}): gold and points never add up.
--       Qualified: at least ORACLE_MIN_MARKETS markets. Ranked by profit divided by staked,
--       compared exactly (no float), then more markets, then the earlier first bet (a row
--       without first after one with it), then by key. top: the first ORACLE_PLACES ({ name,
--       key, profit, staked, markets, first, place }); ranked: every qualified bettor in that
--       order, with place and cur. A malformed row (profit below -staked, staked not above 0,
--       markets not whole, a bad first, cur or bank) is left out.
--   Honors.Holdings(player, inputs) -> list of honours
--       player: { name, guid, guild } (guild: his guild's name, as the viewer knows it; nil when
--       unknown). inputs: { belts = { { cat, guid, name } }, podium = Podium()'s rows (the
--       clerk's words), tiers = { [guid] = "bronze"|"silver"|"gold" }, donors = Donors(), levels
--       = LevelRace()'s book, guild = GuildTop(), oracle = { month = Oracle()'s top (or the
--       bank's word: { name, place }), monthNo }, church = { missionaries = { { name, place } },
--       apostles (1.2.4, the same), at } (1.2.3: ChurchCount.Top3's, its time on the server's
--       clock), bones = { month = { { name, place } }, monthNo } (1.2.4: FarkleTable.Best's top 3
--       of that month), wanted = { rows = { { guid } } } (1.2.4: Wanted.GlobalSnapshot's, in
--       order), now, offset, anchor }.
--       now (optional; offset and anchor as MonthOf and WeekOf take them): a closed period's list
--       holds only while it is the last one: donors.month, oracle.month and bones.month when their
--       monthNo is the month before now's; the Church's top 3 while it is no older than
--       CHURCH_MAX_AGE (Honors.ChurchFresh). Without now the lists are taken as they are.
--       (donors.week gives no honour since the design.) A missionary's and an Apostle's honour's
--       period is now's month: its letter is told once per place per calendar month he holds it
--       in (the koi's clock, MonthOf). The slayers' go by his GUID alone (none without one).
--       Belts, podium and level places go by GUID when both sides have one, else by name; the
--       rest by name. A GUID may come in the game's form ("Player-<serverID>-<8 hex>", as
--       UnitGUID gives it) or the arena's short one (gk, "<serverID>-<8 hex>", as the AV words
--       carry it): both name one character, hex in any case. tiers is looked up by the short
--       form, then by the GUID as given, then by his key. A podium word for a category whose
--       belt he holds is left out (the belt beats it). The best guild's leader holds
--       guild-top-leader (unless his guild, when known, is another); its members hold nothing.
--       An honour: { key, art, shape, metal, kind, family, place, frame, mark, title, badge, cat,
--       milestone, period, guild, order }, sorted by ORDER. frame and title are its key, mark its
--       art's mark ("<art>-mark"); the tier has only its badge. metal: "gold", "silver" or
--       "bronze"; shape: "winged" or "plain" (Honors.ArtOf).
--   Honors.Choose(pick, held, frame, title) -> pick or nil, "frame"|"title"
--       A player's pick { frame, title, seen, locked, back }: frame "rank", "none" or a held
--       honour's frame this version wears; title nil (or "none") or a held honour's title. (1.2.3)
--       The pick's own frame, unchanged, is taken whatever it is (a title alone picked: a frame
--       not held now, or one 1.2.2 switched on that is not released, stays as Update keeps it; the
--       title's click, or the King's letter's Wear it, did nothing). A copy; the pick passed is
--       left alone, and back (Update's) is not kept: what the profile shows is his pick now. A pick
--       without seen (a new profile) gets it from what he holds now, so the next Update finds
--       nothing new and keeps his choice. What a viewer shows of a pick that does not hold (the
--       fallback to the rank's frame and no title) is Shown's.
--   Honors.Update(pick, held, known, told, opts) -> pick, earned, lost
--       After his honours changed: an honour newly earned (its family not held before, or held at
--       a lower place) switches on (frame and title), the first by ORDER when several come at
--       once, unless the player locked his pick (pick.locked = true: set by the caller, kept by
--       Choose and Update; earned still lists what is new). (1.2.3) Its frame only when this
--       version wears it (Honors.FrameShipped): a frame not released yet (the koi, the owl, the
--       comet) leaves the frame worn as it is (the cornucopia stays), its title still switches on.
--       told (optional, 1.2.3): told(h) -> true when that honour's King's letter was told before
--       (HonorsNet: its LetterMark in the profile's lettered); such an honour, earned again (back
--       in the same month to a place already told, after the Church's 30-day ranking dropped him
--       for a day), lists in earned but switches nothing on: a frame he picked himself since stays.
--       Without told every honour earned may switch on. Any frame he picks himself (Choose) stays
--       picked. A family held at another place than before, lower or higher, moves a pick of its
--       old place along (locked or not: the same honour at its new place, and the old place is no
--       longer his; bronze to silver to the belt).
--       (1.2.3) A family lost (its source loaded, and it no longer names him) while an unlocked
--       pick wears its frame or title: the first frame by ORDER this version wears that he holds
--       stands in (else as below: as it is, or his rank's), and the first title by ORDER he holds
--       (else as it is while a family waits for its source, or none); pick.back
--       = { frame = family, title = family } remembers whose, so when that family is his again its
--       honour comes back (at its new place), told or not; and a stand-in is worked out again at
--       each Update while it stands (another lost, or won back). His own pick ends back
--       (Choose), and so does an honour switching on.
--       (1.2.3) A pick naming a frame not released (Choose never took one: only 1.2.0-1.2.2's
--       switch-on could put it there), held or not, locked or not: the first frame by ORDER this
--       version wears that he holds; with none held, while a family this version wears is still
--       remembered in seen with its source not loaded (a login), as it is for a later Update;
--       else his rank's.
--       Otherwise a pick no longer held stays as it is (Shown shows the rank's frame and no title
--       meanwhile): a gap in the inputs (a source not loaded) or a locked pick is never undone.
--       known: the sources loaded, { belt, tier, donor, level, guild, oracle, missionary, apostle,
--       bones, wanted } = true (or true: all; belt covers the podium; 1.2.4: apostle, bones and
--       wanted, the Apostles', the Bones' and the slayers' families). A family is forgotten (lost) only when its source is
--       loaded and it is not held; until its source arrives it stays in seen as it was, so its
--       return is not "new".
--       pick.seen remembers each family held ({ [family] = { place, frame, title, c } }, c: its
--       honour's period) for the next call; a pick without it (a new profile) takes every honour
--       held as newly earned.
--       (1.2.4) opts: { now, offset } (as Moves takes them). A closed month's list (Honors.CYCLE:
--       the koi, the charm, the raven) not held at now because its month is over (its remembered
--       period not CycleOf's at now; none remembered, over too), no word leaving him out, is lost
--       as above (worn: stood in for, back when his again) and stays in seen at the place it
--       ended (ended = true): the next month's list naming him at that place, or a lower one, is
--       not newly earned and switches nothing on (his pick sticks: the cornucopia or "none" he
--       picked stays); a better place is. A word of the same month without him (a correction) is
--       a loss as before. Without opts.now no month is over.
--   Honors.Shown(pick, held) -> frame, mark, title, honour
--       What a pick shows, checked against the honours held: its frame and mark when held, "none"
--       (and the rank's mark) when so picked, else "rank" and "rank"; its title when held, else
--       nil; and the honour whose frame shows (its art and milestone draw it), or nil.
--   Honors.Moves(standing, held, known, opts) -> moves, places
--       (1.2.4) Where the player stands on each family's list against what he was last told
--       (HonorsNet: the King's letter the first time he reaches a place, a notice for any other
--       change). standing: { [family] = { p = place (0: off its list), c = cycle } }, kept by the
--       caller; held and known as Update takes them; opts: { now, offset } (a closed month's list
--       over: CycleOf). A family's cycle (Honors.CYCLE): its honour's period (the month a closed
--       list ranks, the calendar month a rolling one is told in), nil for life.
--       moves: each family whose place or cycle now differs from standing's, by ORDER: { family,
--       kind, from, to (places, 0 off the list), cycle, honour (held now; nil off the list) };
--       kind:
--         seed   not in standing (a first look: a new profile, a family new to this version);
--         cycle  held in another cycle than standing's: the new month's list, or a rolling list's
--                new calendar month; its place is reached anew there;
--         up, down   another place in the same cycle (up: a better one);
--         back   on the list again (the same cycle, or for life) after it was off;
--         out    off the list: its source loaded and naming him no more (a rolling list's, for
--                life or in any month);
--         end    off a closed month's list because that month's turn is over (no word left him
--                out): nothing to say.
--       A family he does not hold whose source is not loaded has no move: unknown is not lost.
--       places: each family as it stands now ({ p, c }); standing's for one not known.
--   Honors.CycleOf(family, now, offset) -> cycle or nil
--       (1.2.4) The cycle a family's list stands in at now: a closed list's month (the month
--       before now's), a rolling list's (now's), nil for life (or without now).
--   Honors.ArtOf(key) -> art, shape, metal | nil
--       An honour key's art stem (its frame "<art>.tga", its mark "<art>-mark.tga"), the frame's
--       shape ("winged" or "plain") and its metal; nil for a key with no art (rank, none, a tier's
--       badge, an unknown key, a class or race the catalogue has no beast for).
--   Honors.ChurchFresh(word, now) -> true | false
--       (1.2.3) The Church's top 3 (Holdings' inputs.church) still names its missionaries at now:
--       its time no older than CHURCH_MAX_AGE (the last 30 days it ranks are over after that); a
--       word without a time, false. Without now, true. HonorsNet.Known asks it too.
--   Honors.ArtFiles() -> { art, ... }  every art stem a held honour can name, and the previews'
--       (Honors.PREVIEWS): the files the addon ships; sorted, for scripts/make-honors.py's list
--       and the tests.

local Honors = {}
ns.Honors = Honors

Honors.WEEK = 7 * 86400
Honors.RESET_US = 486000        -- Tuesday 15:00 UTC, the US realms' weekly reset (Dues.RESET_US)
Honors.DUES_AMOUNT = 10000      -- the dues' amount until the King sets his (Dues.AMOUNT)
Honors.DONOR_MIN = 10000        -- copper a donor honour asks at least: no "top donor" for a few coppers
Honors.DONOR_PLACES = { all = 3, month = 3, week = 1 } -- (week: the race views only, no honour since the design)
Honors.ARENA_NOTES = { "arena", "olympus arena" } -- a mail's subject starting so is arena money (never a donation)
Honors.DUES_NOTE = "olympus fund" -- ...and so the dues' note (Dues.Note)
Honors.MILESTONES = { 20, 40, 60 } -- the level race (the design): the first to 20, 40 and 60
Honors.PLACES = 1               -- places of each milestone of the level race: the first alone
Honors.MAX_LEVEL = 60
Honors.CONFIRM_AFTER = 600      -- a vouched claim takes its place once it is this old (claims timed
                                -- before it, heard late, still get their turn meanwhile)
Honors.SKEW = 300               -- a gift or claim timed further ahead of now is ignored
Honors.GUILD_MIN_MEMBERS = 25   -- members a guild needs for the best-guild plaque (a two-person guild can't win)
Honors.GUILD_MAX_AGE = 2 * 86400 -- a guild's report older than this can't win (opts.now given)
Honors.ORACLE_PLACES = 3        -- the Oracle's gold, silver and bronze
Honors.ORACLE_MIN_MARKETS = 10  -- settled public markets a bettor needs in the month to be ranked
Honors.MISSIONARY_PLACES = 3    -- (1.2.3) the Church's top 3 missionaries: gold, silver and bronze crook
Honors.CHURCH_MAX_AGE = 30 * 86400 -- (1.2.3) a top 3 older than this names nobody (the last 30 days it ranks are over)
Honors.APOSTLE_PLACES = 3       -- (1.2.4) the Church's top 3 Apostles: gold, silver and bronze cross
Honors.BONES_PLACES = 3         -- (1.2.4) the last month's top 3 of Bone Throw: gold, silver and bronze charm
Honors.SLAYER_PLACES = 3        -- (1.2.4) the Slayers' signed top 3 (Wanted.GLOBAL_ROWS): the skeletal horse
-- Which honour comes first: in lists, and when several are earned at once (the one switched on).
-- (1.2.4: the Apostles beside the missionaries, the slayers after them, the Bones after the koi.)
Honors.ORDER = { "belt", "podium", "guild", "donor-top", "apostle", "missionary", "wanted-slayer", "level", "oracle", "donor-month",
	"bones", "tier" }
Honors.DEV_TITLE = "the-dev" -- (1.2.3) the author's own title, a title alone (Honors.Holdings)
-- Where each family's honours come from (Update's known): a family's first word.
Honors.SOURCES = { "belt", "tier", "donor", "level", "guild", "oracle", "missionary", "apostle", "bones", "wanted" }
-- (1.2.4) How each family's list turns over, for its letter and notices (Honors.Moves): "closed", a
-- closed month's list held through the month after it (told once a month it ranks); "month", a
-- rolling ranking told once per calendar month (the Church's last 30 days); any other, for life.
Honors.CYCLE = { ["donor-month"] = "closed", bones = "closed", oracle = "closed", missionary = "month", apostle = "month" }

local MAX_COPPER = 2147483647
local MAX_TIME = 4294967295
local MAX_SUM = 4503599627370496  -- 2^52: the Oracle's sums, and what exact comparison takes
local floor = math.floor

local KIND_ORDER = {}
for i, kind in ipairs(Honors.ORDER) do KIND_ORDER[kind] = i end
local CAT_ORDER = { A = 1, C = 2, R = 3 }
local TIER_PLACE = { gold = 1, silver = 2, bronze = 3 }
-- The art's names of the classes (Roster.ClassCode's codes) and races (UnitRace's IDs).
local CLASS_WORD = { WA = "warrior", PA = "paladin", HU = "hunter", RO = "rogue", PR = "priest",
	SH = "shaman", MA = "mage", WL = "warlock", DR = "druid", DK = "deathknight" }
local RACE_WORD = { [1] = "human", [2] = "orc", [3] = "dwarf", [4] = "nightelf", [5] = "undead",
	[6] = "tauren", [7] = "gnome", [8] = "troll" }
-- The honours' art (the design): each family's beast, in gold, silver and bronze. The arena
-- champion's gryphon and the best guild's owl are winged; the rest are plain.
local METAL = { "gold", "silver", "bronze" }
Honors.METALS = METAL
-- The class champions' beasts, by the class's word (the files are named by class): the Warrior's
-- boar, the Paladin's charger, the Hunter's cheetah, the Rogue's cobra, the Priest's tentacle, the
-- Shaman's spirit wolf, the Mage's sheep, the Warlock's felhunter, the Druid's stag.
Honors.CLASS_ART = { warrior = "boar", paladin = "paladin", hunter = "hunter", rogue = "rogue", priest = "priest",
	shaman = "shaman", mage = "mage", warlock = "warlock", druid = "druid" }
-- The race champions' mounts, by the race's word. (1.2.1: the skyborn's owlcat, a preview only: no
-- race ID gives "skyborn", so no belt or podium is ever his.)
Honors.RACE_ART = { human = "lion", dwarf = "ram", nightelf = "nightsaber", gnome = "mechanostrider", orc = "orc-wolf",
	undead = "skeletal-horse", tauren = "kodo", troll = "raptor", skyborn = "owlcat" }
Honors.WINGED = { gryphon = true, owl = true }
-- The families' beasts: donors of all time, the month's, the Oracle, the level race. (1.2.1, a
-- preview only: the Apostles' cross and the Bones' charm; 1.2.4: both honours.) (1.2.3: the
-- missionaries' shepherd's crook with its sleeping lamb.) (1.2.4, the owner's note of 10-11: the
-- slayers' skeletal horse, "for whoever killed most", the arena's Undead mount; the orc's wolf until
-- then.)
Honors.FAMILY_ART = { ["donor-top"] = "cornucopia", ["donor-month"] = "koi", oracle = "raven", level = "comet",
	["wanted-slayer"] = "skeletal-horse", apostle = "cross", bones = "charm", missionary = "crook" }
-- 1.2.1: the new frames' keys, a preview only (see the top of the file): out of FRAMES_SHIPPED and
-- of every honour, so nobody can wear them or be awarded them. (1.2.4: the crosses and the charms
-- are honours now, out of this list.)
Honors.PREVIEWS = { "apostle-red", "arena-race-skyborn", "arena-race-skyborn-2", "arena-race-skyborn-3" }
-- The red cross: its own art, plain, on the plain underlay tinted black (Borders.lua's UNDERLAY).
Honors.RED_CROSS = "apostle-red"
-- The level race's metal by milestone: bronze the first to 20, silver to 40, gold to 60.
Honors.LEVEL_METAL = { [20] = "bronze", [40] = "silver", [60] = "gold" }
-- The kinds of line the Treasury's ranking never counts (Treasury.lua's Add; the arena's, as
-- the design has them). A sale, a purchase or his own gold is excluded when
-- recorded; counted back in by a keeper (Treasury.Toggle), it counts there, and here.
local NOT_GIFT = { transfer = true, fee = true, arena = true }

---------------------------------------------------------------------------
-- Values
---------------------------------------------------------------------------

function Honors.Key(name)
	if type(name) ~= "string" then return nil end
	-- Forever's "First-Surname" (GetUnitName's) is "First Surname": else every "Example X" is one.
	if ns.Normal then name = ns.Normal(name) end
	if type(name) ~= "string" then return nil end
	local short = name:gsub("%-.*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
	return short ~= "" and short:lower() or nil
end
local Key = Honors.Key

-- Whole copper, more than none and within what the game holds; anything else is no money.
local function Copper(v)
	v = tonumber(v)
	if not v or v ~= v or v <= 0 or v > MAX_COPPER or v ~= floor(v) then return nil end
	return v
end
-- Whole copper, none included (a dues amount of 0 is the King's to set).
local function Amount(v)
	v = tonumber(v)
	if not v or v ~= v or v < 0 or v > MAX_COPPER or v ~= floor(v) then return nil end
	return v
end
-- A server time: whole seconds on the clock.
local function Time(v)
	v = tonumber(v)
	if not v or v ~= v or v < 0 or v > MAX_TIME then return nil end
	return floor(v)
end
-- A character's level: whole, 1 to the cap.
local function Level(v)
	v = tonumber(v)
	if not v or v ~= floor(v) or v < 1 or v > Honors.MAX_LEVEL then return nil end
	return v
end
local function Guid(v) return type(v) == "string" and v ~= "" and v or nil end
-- A GUID as honours compare it: the game's "Player-<serverID>-<8 hex>" (UnitGUID's) and the arena's
-- short form of it (gk, "<serverID>-<8 hex>", as its words carry it) are one character, so both
-- become the short form, hex in capitals. Anything else is compared as it is.
local function GuidKey(v)
	v = Guid(v)
	if not v then return nil end
	local server, hex = v:match("^Player%-(%d+)%-(%x%x%x%x%x%x%x%x)$")
	if not server then server, hex = v:match("^(%d+)%-(%x%x%x%x%x%x%x%x)$") end
	return server and (server .. "-" .. hex:upper()) or v
end
local function Name(v) return type(v) == "string" and v:find("%S") and v or nil end
local function Str(v) return type(v) == "string" and v or nil end

---------------------------------------------------------------------------
-- Clocks
---------------------------------------------------------------------------

function Honors.WeekOf(t, anchor)
	anchor = tonumber(anchor) or Honors.RESET_US
	return floor(((tonumber(t) or 0) - anchor) / Honors.WEEK)
end

-- The civil date of a day counted from 1970-01-01 (Howard Hinnant's days_from_civil, backwards):
-- arithmetic only, so every client gets the same month whatever its own time zone.
local function Civil(days)
	local z = days + 719468
	local era = floor(z / 146097)
	local doe = z - era * 146097
	local yoe = floor((doe - floor(doe / 1460) + floor(doe / 36524) - floor(doe / 146096)) / 365)
	local doy = doe - (365 * yoe + floor(yoe / 4) - floor(yoe / 100))
	local mp = floor((5 * doy + 2) / 153)
	local month = mp < 10 and mp + 3 or mp - 9
	local year = yoe + era * 400 + (month <= 2 and 1 or 0)
	return year, month
end

-- The realm clock's offset at t: one number all year, or its daylight saving's at t.
local function Offset(offset, t)
	if type(offset) == "function" then offset = offset(t) end
	return tonumber(offset) or 0
end

function Honors.MonthOf(t, offset)
	t = tonumber(t) or 0
	local year, month = Civil(floor((t + Offset(offset, t)) / 86400))
	return year * 12 + month - 1
end
function Honors.MonthDate(n)
	n = floor(tonumber(n) or 0)
	return floor(n / 12), n % 12 + 1
end

---------------------------------------------------------------------------
-- Donors
---------------------------------------------------------------------------

-- A subject starting with one of these words (whole words, any case, spaces before it allowed).
local function StartsWith(s, words)
	if type(s) ~= "string" then return false end
	s = s:gsub("^%s+", ""):lower() .. " "
	for _, w in ipairs(words) do
		if s:sub(1, #w) == w and s:sub(#w + 1, #w + 1):match("%s") then return true end
	end
	return false
end
local DUES_WORDS = { Honors.DUES_NOTE }
-- A giver's sum for one window (the Treasury's per-month and per-week sums): counted there alone.
local WINDOWS = { all = true, month = true, week = true }

-- A gift as the donor rankings take it, or nil for what the Treasury's ranking never counts: a
-- payment, an item, a line not counted (excluded), a transfer between keepers, the arena's money.
-- In a Treasurer's book, the dues (sent with their note: noted) take up the week's dues first;
-- a window's sum has its dues taken off already.
local function Gift(g, anchor)
	if type(g) ~= "table" or g.out or g.item or g.excluded then return nil end
	if g.kind ~= nil and NOT_GIFT[g.kind] then return nil end
	if StartsWith(g.note, Honors.ARENA_NOTES) then return nil end
	if g.window ~= nil and not WINDOWS[g.window] then return nil end
	local name, money, t = Name(g.name), Copper(g.money), Time(g.t)
	local key = Key(name)
	if not (key and money and t) then return nil end
	local wk = tonumber(g.wk)
	if not wk or wk ~= floor(wk) then wk = Honors.WeekOf(t, anchor) end
	-- Its Treasurer's book: "" for the one book (treasurer = true), else the book's name's key.
	local book, bookName
	if g.treasurer and not g.window then
		bookName = Name(g.treasurer)
		book = bookName and Key(bookName) or ""
	end
	return { name = name, key = key, money = money, t = t, wk = wk, book = book, bookName = bookName,
		window = g.window, noted = (g.noted or StartsWith(g.note, DUES_WORDS)) and true or false }
end

local function Earlier(a, b)
	if a.t ~= b.t then return a.t < b.t end
	if a.key ~= b.key then return a.key < b.key end
	if a.noted ~= b.noted then return a.noted end
	local ba, bb = a.book and "1" .. a.book or "0", b.book and "1" .. b.book or "0"
	if ba ~= bb then return ba > bb end
	if a.wk ~= b.wk then return a.wk < b.wk end
	return a.money < b.money
end

local function Add(board, e, copper)
	local d = board[e.key]
	if not d then
		d = { key = e.key, money = 0 }
		board[e.key] = d
	end
	d.name, d.at = e.name, e.t
	d.money = math.min(d.money + copper, MAX_COPPER)
end

-- Most first; the same amount: who got there first, then by name. From the top `places` (all
-- when nil), those with at least `least`.
local function Rank(board, places, least)
	local list = {}
	for _, d in pairs(board) do
		if d.money >= (least or 1) then list[#list + 1] = { name = d.name, key = d.key, money = d.money, at = d.at } end
	end
	table.sort(list, function(a, b)
		if a.money ~= b.money then return a.money > b.money end
		if a.at ~= b.at then return a.at < b.at end
		return a.key < b.key
	end)
	for i = #list, (places or #list) + 1, -1 do list[i] = nil end
	for i, d in ipairs(list) do d.place = i end
	return list
end

-- A closed period's list as an earlier call returned it (opts.kept): its well-formed entries, one
-- per giver and per place, by place.
local function Kept(list, places)
	local out, byKey, byPlace = {}, {}, {}
	for _, d in ipairs(type(list) == "table" and list or {}) do
		local name = type(d) == "table" and Name(d.name)
		local key, money, place = Key(name), type(d) == "table" and Copper(d.money), type(d) == "table" and tonumber(d.place)
		if key and money and place and place == floor(place) and place >= 1 and place <= places
			and not byKey[key] and not byPlace[place] then
			byKey[key], byPlace[place] = true, true
			out[#out + 1] = { name = name, key = key, money = money, at = Time(d.at), place = place }
		end
	end
	table.sort(out, function(a, b) return a.place < b.place end)
	return out
end

local function WeekAmount(duesAmount, wk, bookName)
	local v = duesAmount
	if type(v) == "function" then v = v(wk, bookName) end
	return Amount(v) or Honors.DUES_AMOUNT
end

function Honors.Donors(gifts, now, opts)
	opts = type(opts) == "table" and opts or {}
	local anchor = tonumber(opts.anchor) or Honors.RESET_US
	local offset = opts.offset
	now = Time(now) or 0
	local thisWeek, thisMonth = Honors.WeekOf(now, anchor), Honors.MonthOf(now, offset)
	local list = {}
	for _, g in ipairs(type(gifts) == "table" and gifts or {}) do
		local e = Gift(g, anchor)
		if e and e.t <= now + Honors.SKEW then list[#list + 1] = e end
	end
	table.sort(list, Earlier)
	local all, week, month, weekNow, monthNow = {}, {}, {}, {}, {}
	-- [book][key][week] = { gold, noted, counted }: a giver's gold in one of the Treasurer's books
	local toTreasurer = {}
	for _, e in ipairs(list) do
		local copper = e.money
		if e.book then
			-- Of a giver's week in that book, what may be his dues is the week's amount, or all he
			-- sent with the dues' note when that is more; the rest counts (Dues.DuesPart, per book
			-- as Treasury.PublicRanking takes it off). Worked out gift by gift in time, so each gift
			-- counts what it added: never less than before, and the same sum.
			local givers = toTreasurer[e.book] or {}
			toTreasurer[e.book] = givers
			local weeks = givers[e.key] or {}
			givers[e.key] = weeks
			local s = weeks[e.wk] or { gold = 0, noted = 0, counted = 0 }
			weeks[e.wk] = s
			s.gold = math.min(s.gold + e.money, MAX_COPPER)
			if e.noted then s.noted = math.min(s.noted + e.money, MAX_COPPER) end
			local counted = math.max(0, s.gold - math.max(WeekAmount(opts.duesAmount, e.wk, e.bookName), s.noted))
			copper, s.counted = counted - s.counted, counted
		end
		if copper > 0 then
			-- A line counts in every window; a window's sum in its own alone.
			local w = e.window
			if not w or w == "all" then Add(all, e, copper) end
			if not w or w == "week" then
				if e.wk == thisWeek - 1 then Add(week, e, copper) elseif e.wk == thisWeek then Add(weekNow, e, copper) end
			end
			if not w or w == "month" then
				local mo = Honors.MonthOf(e.t, offset)
				if mo == thisMonth - 1 then Add(month, e, copper) elseif mo == thisMonth then Add(monthNow, e, copper) end
			end
		end
	end
	local P, least = Honors.DONOR_PLACES, Honors.DONOR_MIN
	-- The closed week and month: as an earlier call recorded them, once they are (opts.kept).
	local kept = type(opts.kept) == "table" and opts.kept or {}
	local lastWeek, lastMonth
	if tonumber(kept.weekNo) == thisWeek - 1 and type(kept.week) == "table" then
		lastWeek = Kept(kept.week, P.week)
	else
		lastWeek = Rank(week, P.week, least)
	end
	if tonumber(kept.monthNo) == thisMonth - 1 and type(kept.month) == "table" then
		lastMonth = Kept(kept.month, P.month)
	else
		lastMonth = Rank(month, P.month, least)
	end
	return {
		all = Rank(all, P.all, least),
		month = lastMonth, monthNo = thisMonth - 1,
		week = lastWeek, weekNo = thisWeek - 1,
		race = { week = Rank(weekNow), month = Rank(monthNow), weekNo = thisWeek, monthNo = thisMonth },
	}
end

---------------------------------------------------------------------------
-- The level race
---------------------------------------------------------------------------

local function Claim(c, now, start)
	if type(c) ~= "table" then return nil end
	local guid, name, t, level = Guid(c.guid), Name(c.name), Time(c.t), Level(c.level)
	if not (guid and name and t and level) or t > now + Honors.SKEW then return nil end
	-- What the voucher saw before (a level below this one, at or before t); anything else: no claim.
	local from, since
	if c.from ~= nil then
		from = Level(c.from)
		if not from or from >= level then return nil end
	end
	if c.since ~= nil then
		since = Time(c.since)
		if not since or since > t then return nil end
	end
	-- Crossed before the race began, perhaps: nothing.
	if start and (since or t) < start then return nil end
	return { guid = guid, name = name, t = t, level = level, from = from, vouched = c.vouched and true or false }
end

-- The milestones a claim was seen crossing: past `from` up to its level, or its level alone.
local function Crossed(c, m)
	if c.from then return c.from < m and m <= c.level end
	return m == c.level
end

-- The better of two claims to the same milestone: a vouched one over an unvouched one, then the
-- earlier.
local function Before(a, b)
	if a.vouched ~= b.vouched then return a.vouched end
	if a.t ~= b.t then return a.t < b.t end
	return a.guid < b.guid
end

function Honors.LevelRace(book, claims, now, opts)
	now = Time(now) or 0
	opts = type(opts) == "table" and opts or {}
	local start = Time(opts.start)
	book = type(book) == "table" and book or {}
	local byGuid = {}
	for _, c in ipairs(type(claims) == "table" and claims or {}) do
		local claim = Claim(c, now, start)
		if claim then
			local list = byGuid[GuidKey(claim.guid)] or {}
			byGuid[GuidKey(claim.guid)] = list
			list[#list + 1] = claim
		end
	end
	local out, fresh, pending = {}, {}, {}
	for _, m in ipairs(Honors.MILESTONES) do
		-- The places recorded stay as they are (well-formed ones, one each, three at most).
		local places, taken = {}, {}
		for _, p in ipairs(type(book[m]) == "table" and book[m] or {}) do
			local guid = type(p) == "table" and Guid(p.guid)
			if guid and not taken[GuidKey(guid)] and #places < Honors.PLACES then
				taken[GuidKey(guid)] = true
				places[#places + 1] = { guid = guid, name = Name(p.name) or guid, t = Time(p.t), place = #places + 1 }
			end
		end
		-- Each other player's best claim to it.
		local cands = {}
		for guid, list in pairs(byGuid) do
			if not taken[guid] then
				local best
				for _, c in ipairs(list) do
					if Crossed(c, m) and (not best or Before(c, best)) then best = c end
				end
				if best then cands[#cands + 1] = best end
			end
		end
		table.sort(cands, Before)
		-- In order, while there is room: a vouched claim old enough takes the next place. The first
		-- that can't (too fresh, or unvouched) stops the rest, which wait behind it.
		local waiting, open = {}, true
		for _, c in ipairs(cands) do
			if #places >= Honors.PLACES then break end
			if open and c.vouched and now - c.t >= Honors.CONFIRM_AFTER then
				local p = { guid = c.guid, name = c.name, t = c.t, place = #places + 1 }
				places[#places + 1] = p
				fresh[#fresh + 1] = { milestone = m, place = p.place, guid = p.guid, name = p.name, t = p.t }
			else
				open = false
				waiting[#waiting + 1] = { guid = c.guid, name = c.name, t = c.t, vouched = c.vouched }
			end
		end
		out[m], pending[m] = places, waiting
	end
	return out, fresh, pending
end

---------------------------------------------------------------------------
-- The guild with the highest average level
---------------------------------------------------------------------------

function Honors.GuildRanking(rows, opts)
	opts = type(opts) == "table" and opts or {}
	local skip = type(opts.skip) == "function" and opts.skip or nil
	local now, maxAge = Time(opts.now), tonumber(opts.maxAge) or Honors.GUILD_MAX_AGE
	local list = {}
	for k, r in pairs(type(rows) == "table" and rows or {}) do
		if type(r) == "table" and not r.off and (opts.faction == nil or r.faction == opts.faction) then
			local guild = Name(r.guild) or Name(k)
			local leader, members, avg = Name(r.leader), tonumber(r.members or r.total), tonumber(r.avgLevel)
			local t = Time(r.t)
			local fresh = not now or (t ~= nil and now - t <= maxAge)
			if guild and fresh and leader and members and members == floor(members) and members >= Honors.GUILD_MIN_MEMBERS
				and avg and avg >= 1 and avg <= Honors.MAX_LEVEL and not (skip and skip(guild, r)) then
				-- To the tenth, as the census carries it (Codec: avgLevel10): no tie lost to a rounding.
				list[#list + 1] = { guild = guild, leader = leader, members = members, avgLevel = floor(avg * 10 + 0.5) / 10,
					tenths = floor(avg * 10 + 0.5) }
			end
		end
	end
	table.sort(list, function(a, b)
		if a.tenths ~= b.tenths then return a.tenths > b.tenths end
		if a.members ~= b.members then return a.members > b.members end
		local la, lb = a.guild:lower(), b.guild:lower()
		if la ~= lb then return la < lb end
		if a.guild ~= b.guild then return a.guild < b.guild end
		return a.leader < b.leader
	end)
	for i, r in ipairs(list) do r.place, r.tenths = i, nil end
	return list
end
function Honors.GuildTop(rows, opts) return Honors.GuildRanking(rows, opts)[1] end

---------------------------------------------------------------------------
-- The Oracle: the month's best predictors
---------------------------------------------------------------------------

-- A whole number within what the sums keep exact (negative too); anything else: nil.
local function Whole(v)
	v = tonumber(v)
	if not v or v ~= v or v ~= floor(v) or v >= MAX_SUM or v <= -MAX_SUM then return nil end
	return v
end
local function Sum(a, b)
	local s = a + b
	if s >= MAX_SUM then return MAX_SUM - 1 elseif s <= -MAX_SUM then return 1 - MAX_SUM end
	return s
end

-- q and r with a = q * b + r and 0 <= r < b, exactly, for whole a and b (b > 0) under MAX_SUM:
-- the float quotient's floor is off by one at most, and q * b stays under 2^53.
local function DivMod(a, b)
	local q = floor(a / b)
	local r = a - q * b
	if r < 0 then q, r = q - 1, r + b elseif r >= b then q, r = q + 1, r - b end
	return q, r
end

-- a/b against c/d (b, d > 0; whole numbers under MAX_SUM): -1, 0 or 1, exactly. Two ratios of
-- sums of copper can differ by less than a float can tell (and their cross products pass 2^53),
-- so they are compared by their continued fractions: whole parts first, then the remainders'
-- inverses, as Euclid's algorithm runs.
local function Compare(a, b, c, d)
	while true do
		local qa, ra = DivMod(a, b)
		local qc, rc = DivMod(c, d)
		if qa ~= qc then return qa < qc and -1 or 1 end
		if ra == 0 or rc == 0 then
			if ra == rc then return 0 end
			return ra == 0 and -1 or 1
		end
		-- ra/b against rc/d, both between 0 and 1: the larger has the smaller inverse.
		a, b, c, d = d, rc, b, ra
	end
end

local function MarketId(v)
	if type(v) == "number" then return v == v and tostring(v) or nil end
	return type(v) == "string" and v ~= "" and v or nil
end

function Honors.OracleScores(bets, month, opts)
	opts = type(opts) == "table" and opts or {}
	local mode, cur, bank = opts.mode or "L", Str(opts.cur), Name(opts.bank)
	month = tonumber(month)
	local by, rows = {}, {}
	-- No currency, no score: gold, glory points and chips never add up, and no default guesses one.
	if not month or not cur or cur == "" then return rows end
	for _, b in ipairs(type(bets) == "table" and bets or {}) do
		if type(b) == "table" and b.public == true and not b.void and b.mode == mode and b.cur == cur then
			local name, stake, payout, t = Name(b.name), Copper(b.stake), Amount(b.payout), Time(b.t)
			local key, market = Key(name), MarketId(b.market)
			local at = t
			if b.at ~= nil then at = Time(b.at) end
			if key and market and stake and payout and t and at and Honors.MonthOf(t, opts.offset) == month then
				local s = by[key]
				if not s then
					s = { name = name, key = key, profit = 0, staked = 0, markets = 0, first = at, cur = cur, bank = bank,
						seen = {} }
					by[key] = s
					rows[#rows + 1] = s
				end
				s.profit = Sum(s.profit, payout - stake)
				s.staked = Sum(s.staked, stake)
				if not s.seen[market] then s.seen[market], s.markets = true, s.markets + 1 end
				if at < s.first then s.first = at end
			end
		end
	end
	for _, s in ipairs(rows) do s.seen = nil end
	table.sort(rows, function(x, y) return x.key < y.key end)
	return rows
end

function Honors.Oracle(rows, opts)
	opts = type(opts) == "table" and opts or {}
	local want = Str(opts.cur)
	if want == "" then want = nil end
	-- The rows that count, each checked; a bank's later row for a bettor replaces its earlier one.
	local valid, byBank = {}, {}
	for _, r in ipairs(type(rows) == "table" and rows or {}) do
		if type(r) ~= "table" then r = {} end
		local name = Name(r.name)
		local key = Key(name)
		local profit, staked, markets = Whole(r.profit), Whole(r.staked), Whole(r.markets)
		local first, firstOk = nil, true
		if r.first ~= nil then
			first = Time(r.first)
			firstOk = first ~= nil
		end
		local cur, curOk = nil, true
		if r.cur ~= nil then
			cur = Str(r.cur)
			curOk = cur ~= nil and cur ~= ""
		end
		local bank, bankOk = nil, true
		if r.bank ~= nil then
			bank = Key(r.bank)
			bankOk = bank ~= nil
		end
		if key and profit and staked and markets and firstOk and curOk and bankOk and staked > 0 and profit >= -staked
			and markets >= 0 and (not want or not cur or cur == want) then
			local v = { name = name, key = key, profit = profit, staked = staked, markets = markets, first = first,
				cur = cur or want }
			local slot = bank and (bank .. "\0" .. key .. "\0" .. (v.cur or ""))
			if slot and byBank[slot] then
				valid[byBank[slot]] = v
			else
				valid[#valid + 1] = v
				if slot then byBank[slot] = #valid end
			end
		end
	end
	-- Gold and glory points never add up: a set naming two currencies (or one, beside rows that
	-- name none, without opts.cur to say what those are) ranks nobody; opts.cur picks one.
	local cur = valid[1] and (valid[1].cur or false)
	for _, v in ipairs(valid) do
		if (v.cur or false) ~= cur then return {}, {} end
	end
	cur = cur or nil
	local by, list = {}, {}
	for _, v in ipairs(valid) do
		local s = by[v.key]
		if not s then
			s = { name = v.name, key = v.key, profit = 0, staked = 0, markets = 0, cur = cur }
			by[v.key] = s
			list[#list + 1] = s
		end
		s.profit, s.staked, s.markets = Sum(s.profit, v.profit), Sum(s.staked, v.staked), Sum(s.markets, v.markets)
		if v.first and (not s.first or v.first < s.first) then s.first = v.first end
	end
	local ranked = {}
	for _, s in ipairs(list) do
		if s.markets >= Honors.ORACLE_MIN_MARKETS then ranked[#ranked + 1] = s end
	end
	table.sort(ranked, function(x, y)
		local c = Compare(x.profit, x.staked, y.profit, y.staked)
		if c ~= 0 then return c > 0 end
		if x.markets ~= y.markets then return x.markets > y.markets end
		if x.first ~= y.first then
			if not x.first or not y.first then return x.first ~= nil end
			return x.first < y.first
		end
		return x.key < y.key
	end)
	local top = {}
	for i, s in ipairs(ranked) do
		s.place = i
		if i <= Honors.ORACLE_PLACES then
			top[i] = { name = s.name, key = s.key, profit = s.profit, staked = s.staked, markets = s.markets,
				first = s.first, place = i }
		end
	end
	return top, ranked
end

---------------------------------------------------------------------------
-- What a player holds
---------------------------------------------------------------------------

-- An entry is the player's: by GUID when both have one (a renamed character keeps his belt, a
-- namesake gets nothing), by name otherwise.
local function Same(entry, key, guid)
	if type(entry) ~= "table" then return false end
	local g = GuidKey(entry.guid)
	if guid and g then return g == guid end
	return key ~= nil and Key(entry.name) == key
end

-- An honour key's art (see the top of the file): the stem, its shape, its metal.
local function Metal(n) return METAL[tonumber(n) or 1] end
function Honors.ArtOf(key)
	if type(key) ~= "string" or #key > 64 then return nil end
	local beast, place
	local base, p = key:match("^(.-)%-([23])$")
	if not base then base, p = key, 1 end
	place = tonumber(p)
	if base == "arena-champion" then
		beast = "gryphon"
	else
		local class = base:match("^arena%-class%-(%l+)$")
		local race = base:match("^arena%-race%-(%l+)$")
		if class then beast = Honors.CLASS_ART[class]
		elseif race then beast = Honors.RACE_ART[race] end
	end
	if beast then
		local metal = Metal(place)
		return beast .. "-" .. metal, Honors.WINGED[beast] and "winged" or "plain", metal
	end
	local family, n = key:match("^([%l%-]-)%-([123])$")
	if family and Honors.FAMILY_ART[family] and family ~= "level" then
		local b, metal = Honors.FAMILY_ART[family], Metal(n)
		return b .. "-" .. metal, "plain", metal
	end
	local m = tonumber(key:match("^level%-race%-(%d+)$"))
	if m and Honors.LEVEL_METAL[m] then
		return "comet-" .. Honors.LEVEL_METAL[m], "plain", Honors.LEVEL_METAL[m]
	end
	if key == "guild-top-leader" then return "owl-gold", "winged", "gold" end
	if key == Honors.RED_CROSS then return "cross-red", "plain", "black" end
	return nil
end
local ArtOf = Honors.ArtOf

function Honors.ArtFiles()
	local out, seen = {}, {}
	local function Add(art) if art and not seen[art] then seen[art] = true out[#out + 1] = art end end
	local keys = { "arena-champion", "guild-top-leader" }
	for word in pairs(Honors.CLASS_ART) do keys[#keys + 1] = "arena-class-" .. word end
	for word in pairs(Honors.RACE_ART) do keys[#keys + 1] = "arena-race-" .. word end
	for _, k in ipairs(keys) do
		Add((ArtOf(k)))
		if k ~= "guild-top-leader" then Add((ArtOf(k .. "-2"))); Add((ArtOf(k .. "-3"))) end
	end
	for _, family in ipairs({ "donor-top", "donor-month", "oracle", "missionary", "apostle", "bones", "wanted-slayer" }) do
		for n = 1, 3 do Add((ArtOf(family .. "-" .. n))) end
	end
	for _, m in ipairs(Honors.MILESTONES) do Add((ArtOf("level-race-" .. m))) end
	for _, k in ipairs(Honors.PREVIEWS) do Add((ArtOf(k))) end
	table.sort(out)
	return out
end

local function Honour(kind, sub, place, key, o)
	local h = o or {}
	h.kind, h.place, h.key = kind, place, key
	h.family = h.family or kind
	if kind == "tier" then
		-- a badge only: no frame, no mark, no title
		h.metal = h.metal or METAL[place]
	else
		local art, shape, metal = ArtOf(key)
		h.art, h.shape, h.metal = h.art or art, shape, metal
		h.frame, h.mark, h.title = key, h.art, key
	end
	h.order = (KIND_ORDER[kind] or #Honors.ORDER + 1) * 100000 + sub * 100 + place
	return h
end

-- A category's belt (place 1) or its podium (2: silver, 3: bronze): one family, so a holder who
-- loses his belt and stays 2nd, or a 2nd overtaken, is his old honour a place down.
local function Belt(cat, place)
	place = place or 1
	if type(cat) ~= "string" then return nil end
	local base, sub
	if cat == "A" then
		base, sub = "arena-champion", CAT_ORDER.A
	else
		local code = cat:match("^C(%u%u)$")
		local id = tonumber(cat:match("^R(%d+)$"))
		if code then
			base, sub = "arena-class-" .. (CLASS_WORD[code] or code:lower()), CAT_ORDER.C
		elseif id then
			base, sub = "arena-race-" .. (RACE_WORD[id] or tostring(id)), CAT_ORDER.R
		else
			return nil -- (level brackets, or anything else: no honour)
		end
	end
	if place == 1 then return Honour("belt", sub, 1, base, { cat = cat, family = "belt-" .. cat }) end
	return Honour("podium", sub, place, base .. "-" .. place, { cat = cat, family = "belt-" .. cat })
end

function Honors.Podium(cat, ranking, holder, eligible)
	local out = {}
	if not Belt(cat) then return out end
	holder = GuidKey(holder)
	local taken = {}
	for _, r in ipairs(type(ranking) == "table" and ranking or {}) do
		if #out >= 2 then break end
		local guid = type(r) == "table" and Guid(r.guid or r.key)
		local gk = GuidKey(guid)
		if gk and gk ~= holder and not taken[gk] and (not eligible or eligible(r)) then
			taken[gk] = true
			out[#out + 1] = { cat = cat, place = #out + 2, guid = guid, name = Name(r.name) }
		end
	end
	return out
end

-- The player's place on a ranked list (the donors', the Oracle's), as that list's honour.
local function Listed(list, kind, places, key, period, held)
	for _, d in ipairs(type(list) == "table" and list or {}) do
		local place = type(d) == "table" and tonumber(d.place)
		if place and place >= 1 and place <= places and place == floor(place) and Same(d, key, nil) then
			local hkey = places == 1 and kind or (kind .. "-" .. place)
			held[#held + 1] = Honour(kind, 0, place, hkey, { period = period })
			return
		end
	end
end

-- (1.2.3) The Church's top 3 still says something at now: no older than the 30 days it ranks.
function Honors.ChurchFresh(word, now)
	now = Time(now)
	if not now then return true end
	local at = type(word) == "table" and Time(word.at) or nil
	return at ~= nil and now - at <= Honors.CHURCH_MAX_AGE
end
local ChurchFresh = Honors.ChurchFresh

-- A guild's name as two clients compare it: trimmed, any case.
local function GuildKey(v)
	v = Name(v)
	return v and v:gsub("^%s+", ""):gsub("%s+$", ""):lower() or nil
end

function Honors.Holdings(player, inputs)
	player = type(player) == "table" and player or {}
	inputs = type(inputs) == "table" and inputs or {}
	local key, guid = Key(player.name), GuidKey(player.guid)
	local held = {}
	if not key and not guid then return held end
	-- A closed week's or month's list holds while it is the last one (inputs.now given).
	local now = Time(inputs.now)
	local lastMonth = now and Honors.MonthOf(now, inputs.offset) - 1
	local function Current(no, last) return last == nil or tonumber(no) == last end
	local belts = {}
	for _, b in ipairs(type(inputs.belts) == "table" and inputs.belts or {}) do
		if Same(b, key, guid) and not belts[b.cat] then
			local h = Belt(b.cat)
			if h then
				belts[b.cat] = true
				held[#held + 1] = h
			end
		end
	end
	-- The podium: silver or bronze of a category whose belt he does not hold (the better place,
	-- should two words name him).
	local podium, cats = {}, {}
	for _, p in ipairs(type(inputs.podium) == "table" and inputs.podium or {}) do
		local place = type(p) == "table" and tonumber(p.place)
		if (place == 2 or place == 3) and type(p.cat) == "string" and not belts[p.cat] and Same(p, key, guid) then
			if not podium[p.cat] then cats[#cats + 1] = p.cat end
			if not podium[p.cat] or place < podium[p.cat] then podium[p.cat] = place end
		end
	end
	for _, cat in ipairs(cats) do
		local h = Belt(cat, podium[cat])
		if h then held[#held + 1] = h end
	end
	local tiers = type(inputs.tiers) == "table" and inputs.tiers or {}
	local raw = Guid(player.guid)
	local tier = (guid and tiers[guid]) or (raw and tiers[raw]) or (key and tiers[key])
	if TIER_PLACE[tier] then
		held[#held + 1] = Honour("tier", 0, TIER_PLACE[tier], "arena-tier-" .. tier, { badge = "arena-tier-" .. tier })
	end
	local donors = type(inputs.donors) == "table" and inputs.donors or {}
	if key then
		Listed(donors.all, "donor-top", Honors.DONOR_PLACES.all, key, nil, held)
		if Current(donors.monthNo, lastMonth) then
			Listed(donors.month, "donor-month", Honors.DONOR_PLACES.month, key, donors.monthNo, held)
		end
		local oracle = type(inputs.oracle) == "table" and inputs.oracle or {}
		if Current(oracle.monthNo, lastMonth) then
			Listed(oracle.month, "oracle", Honors.ORACLE_PLACES, key, oracle.monthNo, held)
		end
		-- (1.2.3) The Church's top 3 missionaries: the crook, while the word is fresh; told for the
		-- month he holds it in (period: now's month).
		local church = type(inputs.church) == "table" and inputs.church or nil
		if church and ChurchFresh(church, now) then
			local month = now and Honors.MonthOf(now, inputs.offset)
			Listed(church.missionaries, "missionary", Honors.MISSIONARY_PLACES, key, month, held)
			-- (1.2.4) ...and its top 3 Apostles, the cross: the same word, the same clock.
			Listed(church.apostles, "apostle", Honors.APOSTLE_PLACES, key, month, held)
		end
		-- (1.2.4) Bone Throw's last month (the koi's clock): its top 3, the charm, through this month.
		local bones = type(inputs.bones) == "table" and inputs.bones or {}
		if Current(bones.monthNo, lastMonth) then
			Listed(bones.month, "bones", Honors.BONES_PLACES, key, bones.monthNo, held)
		end
	end
	-- (1.2.4) The Slayers' signed top 3 (in its order: 1st, 2nd, 3rd): the skeletal horse, by his GUID
	-- alone, as the Most Wanted frames always went (a name alone is never enough).
	local wanted = type(inputs.wanted) == "table" and inputs.wanted or nil
	if guid and wanted then
		for i, r in ipairs(type(wanted.rows) == "table" and wanted.rows or {}) do
			if i > Honors.SLAYER_PLACES then break end
			if type(r) == "table" and GuidKey(r.guid) == guid then
				held[#held + 1] = Honour("wanted-slayer", 0, i, "wanted-slayer-" .. i)
				break
			end
		end
	end
	local levels = type(inputs.levels) == "table" and inputs.levels or {}
	for _, m in ipairs(Honors.MILESTONES) do
		for i, p in ipairs(type(levels[m]) == "table" and levels[m] or {}) do
			if i > Honors.PLACES then break end
			if Same(p, key, guid) then
				-- The first to each milestone: the comet in its metal; the addon writes the level on it.
				held[#held + 1] = Honour("level", Honors.MAX_LEVEL + 10 - m, i, ("level-race-%d"):format(m),
					{ milestone = m, family = "level-" .. m })
				break
			end
		end
	end
	local g = inputs.guild
	if key and type(g) == "table" then
		local mine, top = GuildKey(player.guild), GuildKey(g.guild)
		if Name(g.leader) and Key(g.leader) == key and (mine == nil or mine == top) then
			held[#held + 1] = Honour("guild", 0, 1, "guild-top-leader", { guild = g.guild })
		end
	end
	-- 1.2.3 (the author's ask): his own title, "The Royal Dev". A title alone (no frame, no mark, no
	-- King's letter), held by the author's character (player.author: Workshop.IsAuthorName, his
	-- name in his realm group, so every client works it out the same); last in ORDER.
	if player.author == true then
		held[#held + 1] = { kind = "dev", family = "dev", place = 1, key = Honors.DEV_TITLE, title = Honors.DEV_TITLE,
			noLetter = true, order = (#Honors.ORDER + 1) * 100000 }
	end
	table.sort(held, function(a, b)
		if a.order ~= b.order then return a.order < b.order end
		return a.key < b.key
	end)
	return held
end

---------------------------------------------------------------------------
-- The pick
---------------------------------------------------------------------------

local function HeldBy(field, value, held)
	if type(value) ~= "string" then return nil end
	for _, h in ipairs(type(held) == "table" and held or {}) do
		if type(h) == "table" and h[field] == value then return h end
	end
	return nil
end

local function ByOrder(a, b)
	local oa, ob = tonumber(a.order) or 0, tonumber(b.order) or 0
	if oa ~= ob then return oa < ob end
	return tostring(a.key) < tostring(b.key)
end

-- Each family at its best place held (a family is held once; a list with two keeps the better).
local function Best(held)
	local best = {}
	for _, h in ipairs(type(held) == "table" and held or {}) do
		if type(h) == "table" and type(h.family) == "string" and type(h.place) == "number" then
			local b = best[h.family]
			if not b or h.place < b.place or (h.place == b.place and ByOrder(h, b)) then best[h.family] = h end
		end
	end
	return best
end
-- (1.2.4: c, its honour's period: a closed month's list over is told from one left, Update's Over.)
local function Seen(h) return { place = h.place, frame = h.frame, title = h.title, c = tonumber(h.period) } end

-- A family's source is loaded (Update's known): true for all, or { [source] = true }.
local function Known(known, family)
	if known == true then return true end
	if type(known) ~= "table" or type(family) ~= "string" then return false end
	local source = family:match("^(%a+)")
	return source ~= nil and known[source] == true
end


local function Copy(pick)
	pick = type(pick) == "table" and pick or {}
	local frame = type(pick.frame) == "string" and pick.frame or "rank"
	local title = type(pick.title) == "string" and pick.title ~= "none" and pick.title or nil
	local seen
	if type(pick.seen) == "table" then
		seen = {}
		for family, s in pairs(pick.seen) do
			if type(family) == "string" and type(s) == "table" and tonumber(s.place) then
				seen[family] = { place = tonumber(s.place), frame = Str(s.frame), title = Str(s.title), c = tonumber(s.c),
					ended = s.ended == true or nil }
			end
		end
	end
	return { frame = frame, title = title, seen = seen, locked = pick.locked == true or nil }
end

-- 1.2.0 (the owner's call): the only honours' frames worn are the all-time donors'. The level race's
-- comet waits for the game's launch; the month's donors, the Arena's, the Oracle's raven, the games',
-- the Church's and the slayers' come later. Their frames stay in the code, worn by nobody here.
-- 1.2.3 (the owner's call, "Cajado entra na 1.2.3"): the missionaries' crook is worn too.
-- 1.2.4 (the owner's calls): the month's donors' koi, the best guild's owl, the Apostles' cross, the
-- Bones' charm and the slayers' skeletal horse too. The level race's comet (the launch), the Arena's
-- (its tournaments) and the Oracle's raven (2.0's bets) still wait.
Honors.FRAMES_SHIPPED = { ["donor-top"] = true, missionary = true, ["donor-month"] = true, guild = true, apostle = true, bones = true,
	["wanted-slayer"] = true }
-- (nil: every family's frame, as the honours' own tests and 2.0 have them.)
local function Shipped(h)
	local s = Honors.FRAMES_SHIPPED
	return h ~= nil and (s == nil or s[h.family or h.kind] == true)
end
Honors.FrameShipped = Shipped

-- (1.2.3) The family a frame's key names, held or not (as Holdings names it: belt-<cat>, level-<m>,
-- guild, or the listed families'); nil for the rank's, none, or a key no honour has.
local CLASS_CODE, RACE_ID = {}, {}
for code, word in pairs(CLASS_WORD) do CLASS_CODE[word] = code end
for id, word in pairs(RACE_WORD) do RACE_ID[word] = id end
local function KeyFamily(key)
	if type(key) ~= "string" or #key > 64 then return nil end
	local base = key:match("^(.-)%-[23]$") or key
	if base == "arena-champion" then return "belt-A" end
	local class = base:match("^arena%-class%-(%l+)$")
	if class then
		local code = CLASS_CODE[class] or (#class == 2 and class:upper())
		return code and ("belt-C" .. code) or nil
	end
	local race = base:match("^arena%-race%-(%w+)$")
	if race then
		local id = RACE_ID[race] or tonumber(race)
		return id and ("belt-R" .. id) or nil
	end
	local m = key:match("^level%-race%-(%d+)$")
	if m then return "level-" .. m end
	if key == "guild-top-leader" then return "guild" end
	local family = key:match("^([%l%-]-)%-[123]$")
	if family and family ~= "level" and Honors.FAMILY_ART[family] then return family end
	return nil
end
-- (1.2.3) A pick's frame of a family this version does not wear (the koi, the owl, the comet...).
local function Unworn(frame)
	if Honors.FRAMES_SHIPPED == nil or frame == "rank" or frame == "none" then return false end
	local family = KeyFamily(frame)
	return family ~= nil and not Shipped({ family = family })
end
-- (1.2.3) The frame worn in place of one the pick can't show: the first by ORDER this version wears
-- that he holds; with none, while a family this version wears is remembered in seen with its source
-- not loaded (a login, a gap), the frame as it is (a later Update finds that one); else his rank's.
-- (1.2.4: a closed month's list remembered over, ended, waits for no source: never one of those.)
local function StandIn(held, seen, best, frame)
	local first
	for _, h in ipairs(held) do
		if type(h) == "table" and h.frame and Shipped(h) and (not first or ByOrder(h, first)) then first = h end
	end
	if first then return first.frame end
	for family, s in pairs(seen) do
		if not best[family] and not s.ended and s.frame and Shipped({ family = family }) then return frame end
	end
	return "rank"
end
-- (1.2.3) ...and a title: the first by ORDER he holds; with none, while a family is remembered with its
-- source not loaded, the title as it is; else none.
local function StandInTitle(held, seen, best, title)
	local first
	for _, h in ipairs(held) do
		if type(h) == "table" and h.title and (not first or ByOrder(h, first)) then first = h end
	end
	if first then return first.title end
	for family, s in pairs(seen) do
		if not best[family] and not s.ended and s.title then return title end
	end
	return nil
end
-- (1.2.4) A closed month's list (Honors.CYCLE) remembered in seen whose month is no longer the one
-- held at opts.now (CycleOf): its month's turn is over, no word left him out (Moves' "end"). A place
-- remembered without its month (1.2.3 kept none) is over too, on the side of his pick. Without
-- opts.now, never.
local function Over(family, was, opts)
	local now = type(opts) == "table" and Time(opts.now) or nil
	if not now or Honors.CYCLE[family] ~= "closed" then return false end
	return was.c ~= Honors.CycleOf(family, now, opts.offset)
end
-- (1.2.3) Update's memory of a frame or title stood in for: { frame = family, title = family }.
local function Back(pick)
	local b = type(pick) == "table" and type(pick.back) == "table" and pick.back or {}
	return { frame = Str(b.frame), title = Str(b.title) }
end

function Honors.Choose(pick, held, frame, title)
	-- (1.2.3: the pick's own frame, unchanged, whatever it is: a title alone is picked.)
	local same = type(pick) == "table" and frame == (type(pick.frame) == "string" and pick.frame or "rank")
	if frame ~= "rank" and frame ~= "none" and not same and not Shipped(HeldBy("frame", frame, held)) then return nil, "frame" end
	if title == "none" then title = nil end
	if title ~= nil and not HeldBy("title", title, held) then return nil, "title" end
	local new = Copy(pick)
	new.frame, new.title = frame, title
	-- A first choice (no Update yet): what he holds now is not new, so it can't undo his choice.
	if not new.seen then
		new.seen = {}
		for family, h in pairs(Best(held)) do new.seen[family] = Seen(h) end
	end
	return new
end

function Honors.Update(pick, held, known, told, opts)
	held = type(held) == "table" and held or {}
	local old = Copy(pick)
	local new = { frame = old.frame, title = old.title, seen = {}, locked = old.locked }
	local seen = old.seen or {}
	local back = Back(pick)
	local best = Best(held)
	local earned, lost = {}, {}
	for family, h in pairs(best) do
		new.seen[family] = Seen(h)
		local was = seen[family]
		if not was or h.place < was.place then earned[#earned + 1] = h end
		if was and h.place ~= was.place then
			-- Another place in its family (bronze to silver, 1st of all time to 2nd, the members'
			-- title to the leader's): a pick of the old place follows it, locked or not, since the
			-- old place is no longer his. A place up is also new, and switches on below.
			if was.frame ~= nil and new.frame == was.frame and h.frame then new.frame = h.frame end
			if was.title ~= nil and new.title == was.title and h.title then new.title = h.title end
		end
	end
	for family, was in pairs(seen) do
		if not best[family] then
			if was.ended then
				-- (1.2.4) A closed month's list over, lost already (below): remembered at the place it
				-- ended, so the next month's list naming him there is no new honour, nor one a place down.
				new.seen[family] = was
			elseif Known(known, family) then
				lost[#lost + 1] = { family = family, place = was.place, frame = was.frame, title = was.title }
				-- (1.2.4) Its month's turn over (the koi, the charm: Over), no word leaving him out: lost
				-- now as any family is (worn, it is stood in for and comes back), and remembered, ended.
				-- (Forgotten, the next month's list naming him at his place again was a new honour: it
				-- switched on by itself over the cornucopia or "none" he picked, every month, wherever a
				-- look fell between the month's turn and the list's first word of it, as HonorsNet's own
				-- look at the month's turn makes sure of.)
				if Over(family, was, opts) then
					new.seen[family] = { place = was.place, frame = was.frame, title = was.title, c = was.c, ended = true }
				end
			else
				-- Its source not loaded yet (a login, a relay's gap): remembered as it was.
				new.seen[family] = was
			end
		end
	end
	table.sort(earned, ByOrder)
	table.sort(lost, function(a, b) return a.family < b.family end)
	local function Told(h) return type(told) == "function" and told(h) == true end
	if not new.locked then
		-- (1.2.3) His pick back: the honour of a family stood in for (below), his again (at its new
		-- place, told or not).
		local f, t = back.frame and best[back.frame], back.title and best[back.title]
		if f and f.frame and Shipped(f) then new.frame, back.frame = f.frame, nil end
		if t and t.title then new.title, back.title = t.title, nil end
		-- A new honour switches on: the first by ORDER that has a frame this version wears, and the
		-- first that has a title; a locked pick stays as the player set it. (1.2.3: 1.2.2 switched on
		-- any frame, so a koi, an owl or a comet earned took the place of the cornucopia worn, and his
		-- rank's frame showed instead: Shown wears none of them. And only an honour told for the
		-- first time: one told before, earned again, leaves his pick as it is.)
		for _, h in ipairs(earned) do
			if h.frame and Shipped(h) and not Told(h) then new.frame, back.frame = h.frame, nil break end
		end
		for _, h in ipairs(earned) do
			if h.title and not Told(h) then new.title, back.title = h.title, nil break end
		end
		-- (1.2.3) A family lost while worn (its source loaded: a fresh word without him): a stand-in,
		-- the first frame (title) by ORDER he holds, and the family remembered to come back to. (It
		-- stayed the pick, and his rank's frame showed with no title, a cornucopia held: the crook's
		-- 30-day ranking drops its holders routinely.)
		for _, x in ipairs(lost) do
			if x.frame ~= nil and new.frame == x.frame and not back.frame and Shipped(x) then back.frame = x.family end
			if x.title ~= nil and new.title == x.title and not back.title then back.title = x.family end
		end
		if back.frame then new.frame = StandIn(held, new.seen, best, new.frame) end
		if back.title then new.title = StandInTitle(held, new.seen, best, new.title) end
	end
	-- (1.2.3) A frame not released yet on the pick (only 1.2.0-1.2.2's switch-on put one there: Choose
	-- never took one), held or not, locked or not: the first frame by ORDER this version wears that he
	-- holds. (1.2.2's koi after its month, an owl after his guild lost first, a pick locked since: his
	-- rank's frame showed, the cornucopia held.)
	if Unworn(new.frame) then new.frame = StandIn(held, new.seen, best, new.frame) end
	new.back = (back.frame or back.title) and back or nil
	-- Otherwise a pick no longer held stays the pick: Shown falls back to the rank meanwhile.
	return new, earned, lost
end

function Honors.Shown(pick, held)
	pick = type(pick) == "table" and pick or {}
	local frame, mark, honour = "rank", "rank", nil
	if pick.frame == "none" then
		frame = "none"
	else
		local h = HeldBy("frame", pick.frame, held)
		if h and Shipped(h) then frame, mark, honour = h.frame, h.mark, h end
	end
	local title = HeldBy("title", pick.title, held) and pick.title or nil
	return frame, mark, title, honour
end

---------------------------------------------------------------------------
-- (1.2.4) The places told: where he stands against what he was last told
---------------------------------------------------------------------------

function Honors.CycleOf(family, now, offset)
	local how = type(family) == "string" and Honors.CYCLE[family] or nil
	now = Time(now)
	if not how or not now then return nil end
	local month = Honors.MonthOf(now, offset)
	return how == "closed" and month - 1 or month
end

-- A move's place in ORDER: its honour's, else its family's kind (belt-<cat> and level-<m> by their
-- first word), then the family's name.
local function MoveOrder(m)
	if m.honour and tonumber(m.honour.order) then return m.honour.order end
	local kind = KIND_ORDER[m.family] and m.family or m.family:match("^(%a+)")
	return (KIND_ORDER[kind] or #Honors.ORDER + 1) * 100000
end

function Honors.Moves(standing, held, known, opts)
	opts = type(opts) == "table" and opts or {}
	standing = type(standing) == "table" and standing or {}
	local best = Best(held)
	local moves, places = {}, {}
	for family, h in pairs(best) do
		local cycle = tonumber(h.period)
		local was = type(standing[family]) == "table" and standing[family] or nil
		local from, wasCycle = was and tonumber(was.p), was and tonumber(was.c)
		places[family] = { p = h.place, c = cycle }
		local kind
		if not from then kind = "seed"
		elseif cycle ~= wasCycle then kind = "cycle"
		elseif from == 0 then kind = "back"
		elseif h.place < from then kind = "up"
		elseif h.place > from then kind = "down" end
		if kind then
			moves[#moves + 1] = { family = family, kind = kind, from = from or 0, to = h.place, cycle = cycle, honour = h }
		end
	end
	for family, was in pairs(standing) do
		local from = type(was) == "table" and tonumber(was.p) or nil
		if not best[family] and type(family) == "string" and from then
			local cycle = tonumber(was.c)
			places[family] = { p = from, c = cycle }
			if from > 0 and Known(known, family) then
				-- A closed month's list whose month is no longer the one held: over, not lost.
				local over = Honors.CYCLE[family] == "closed" and cycle ~= Honors.CycleOf(family, opts.now, opts.offset)
				places[family] = { p = 0, c = cycle }
				moves[#moves + 1] = { family = family, kind = over and "end" or "out", from = from, to = 0, cycle = cycle }
			end
		end
	end
	table.sort(moves, function(a, b)
		local oa, ob = MoveOrder(a), MoveOrder(b)
		if oa ~= ob then return oa < ob end
		return a.family < b.family
	end)
	return moves, places
end
