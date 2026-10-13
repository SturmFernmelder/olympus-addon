# Olympus 1.2.4 — test candidate

This candidate brings the current changes together for testing on WoW: Forever. These notes
describe implemented behavior, not a completed Windows or multiplayer acceptance test. No
publication or release is claimed. Games remain free; bets, gold stakes and paid Lottery
tickets stay disabled.

## Guilds, departments and communication

- Census and The Realm show the same average level, with independent sorting and consistent
  tie-breaks. Longer headings fit their columns.
- Church appointments remain available when their source is offline. Apostles and missionaries
  can each have twelve direct missionaries; the retained Church and its synchronization support
  up to 5,000 Church members. Incomplete information does not silently demote a signed Apostle.
- Heraldry handles the guild's Decrees, Agenda and musters through the current own-guild master
  or verified correspondent. Army authority keeps its separate verified Crown, author and
  Heraldry Council duties. An ordinary guild master gains no army-wide Crown powers.
- Centurions are now Legates: up to 25 explicitly appointed leaders per guild, including the
  King's guild. A signed High Council title does not automatically appoint a Legate.
  Each organizes their own agreed group of 40 total (leader plus up to 39 guildmates), coordinating
  attendance at events, raids and wars. Naming explains this purpose; the appointed character gets
  a quiet local notice. Existing officer oversight remains. Legacy oversized saved groups remain
  read-only until an authorized confirmed review archives the old membership and replaces it.
  Historical command/role/room identifiers remain compatible. These are optional, fluid groups,
  not exclusive partitions or a restriction on following another leader. Their online counts use
  the fresh native roster and label unknown status. No automatic invites or kicks.
- Approved role rooms show delivery failures and partial delivery. Class and race rooms remain
  removed. Games lists live Arena/Bones conversations; after a Bones game ends, participants
  can continue its conversation while spectators retain read-only history, within retention
  limits. A lifecycle update does not open the window automatically.
- Native `[Olympus]` links open the Olympus input when the character may write there. A free
  Shift + guild shortcut opens The Watch for an actually authorized High Councillor; other
  characters retain the normal window toggle. Existing bindings and hotkey opt-out are respected.

## Honours and profiles

- The normal Olympus window holds My profile, its look, personal portrait fallback icon,
  privacy summary and retained letters. Self and other-player menus say **View profile**.
  Every member can choose a personal icon with Games off; that local choice does not enable
  sharing. Council chat icons remain High-Council-only.
- Released honours include the all-time donor cornucopia, completed-month donor koi, best-guild
  owl, Apostle crosses, missionary crooks, Bones charms and Slayer skeletal horses. The koi and
  Bones charm cover the month after the ranked month. A chosen cornucopia remains selectable.
- Honour portraits and letters hide the duplicate dragon underneath, retaining the portrait
  ring. All cross frames use the larger cross geometry. A signed Apostle's optional red cross
  is client-local, and its picker explains that other clients see the ordinary chosen honour.
- An honour letter is remembered per character, category/place and applicable monthly period.
  The King receives no letter from himself. Later losses, returns and place changes use quiet,
  bounded notices. Letter text, parchment layout and the red seal beside the signature were
  revised; clipping and actual texture appearance still need the client checks below.
- `/oly honours preview` opens the author's gallery of every existing letter family, using
  the actual framed parchment. It creates no award, saved letter, Wanted entry or broadcast,
  and cannot consume a waiting real letter. It is not available through a role preview.

## Wanted, records and performance

- Verified ordinary members' own observed outdoor kills and deaths can reach other clients.
  Empty zero-point/zero-kill entries are hidden, and repeated reports of one death count once.
  Bounties use the existing victim office/level and target-level formula, with revenge notices
  and a reset after a claim. `/oly wanted status` explains local captures and refusals.
- Bounty cooldowns also compare owners established by reciprocal alt links, known local
  characters or independently verified ownership. Unconfirmed characters are not linked by
  guesswork; this is partial anti-farming protection, not a solution for unrelated accounts.
- Independently validated game records and authenticated monthly seals can be retained and
  relayed. Catch-up rotates over retained days and months; a full bounded page is not treated
  as proof that older records are missing. Missing evidence is not reconstructed.
- Background census traffic redraws the open main Chat summary at most once a minute; chat
  messages and access changes keep their separate refresh paths. Existing incremental chat
  layout, coalesced census updates and `/oly perf` time/memory reports remain available.
  A lower offline cost does not establish that live stutter or spikes have been eliminated.

## Treasury, dues and voluntary campaigns

- Authorized Treasury views retain affiliated guild snapshots after their sharers go offline,
  showing the last observation's age. Restricted details do not become public donor lists.
- The current character's dues page distinguishes unknown, sent, partial receipt and confirmed
  receipt. A successful send alone proves no receipt. Confirmations use observed native
  mail/trade intake from the pinned Treasurer; manually edited or old ledger money does not
  become fresh payment proof. Missing private receipts can be requested through the page.
- A character-local dues reminder can be dismissed or changed on Privacy. It stays quiet in
  combat and instances and does not make a payment, impose a sanction or open a recurring popup.
- The actual King can define a voluntary campaign purpose, gold/material goals and a 14-day
  receipt window. A real keeper explicitly assigns eligible newly received voluntary gifts;
  verified current-week dues remain reserved. Only aggregate progress is reported to the King
  and published by him. A receipt cannot be assigned twice, and closing records the King's
  purchases note. The jar moves no money and grants no rank, payment exemption or privilege.
- `/oly carry` offers a bounded, explicitly unverified quote copy for the same character moving
  manually between sister guilds. Preparation sends nothing; the exact verified destination
  guild master must accept privately. Revocation cancels queued data and hides the recipient's
  copy once delivered. Loot notes, own Court messages, pardon observations and own retained
  receipt facts remain quotes, never authoritative imports. See [history carry](history-carry.md).

## Open limitations and acceptance gates

- The Watch's private Justice requests record explicit King/High Council assignments to a
  currently verified Justice correspondent. Receipt is acknowledged by the actual assignee;
  delivery while offline does not start the timer. The existing removal dialog remains a manual
  native action, with no new kick permission. A later complete fresh roster absence is recorded
  separately; it never proves who caused the removal. The original issuer must explicitly review
  completion, labeled human-confirmed. Cancellation/decision delivery has bounded retries and
  acknowledgement. Staff see local held details; correspondents see only their own requests.
  Reports are a separate count of locally retained accepted reporter/subject pairs, not all-time
  work or quality. This is not a synchronized army-wide ranking, composite score or new honour.
- Cross enlargement is implemented; consistent normalization of the other honour families
  against the rank dragons is still open. Approved artwork needs visual acceptance in game.
- Plain bronze role portraits now belong to correspondents, not Legates. Their existing
  verified chat/nameplate identity marks remain. A separate Legate badge has not been supplied;
  this candidate does not invent its art or replace the native PvP badge.
- Level Race ships explicitly off: no collection, level-claim send/receive, effective standings
  or live level honours. Old evidence stays retained and the author's art/letter previews still
  work. A future release must deliberately define and open its launch; ordinary settings and
  role previews cannot start it. Future tournament honours are not rewards for qualifier ranking.
- Unlinked Horde characters and unrelated accounts cannot be proved to share an owner through
  the current anti-farming path. The reported two-account farming scenario remains a live check.
- History carry supplies no full signed continuity, named guild-merger inheritance, transferred
  payment status or original royal pardon deadline. Withdrawal to an offline master is not
  guaranteed. No new dues grace-period policy is implemented.
- Church correspondent streaks count completed UTC days with observed membership strictly above
  950 during that exact person's appointment. Each new management starts with no inherited days;
  a same-appointment heartbeat does not reset it. Unknown/capped days pause, observed days at or
  below 950 break the streak, and equally weighted daily averages break ties. Older local
  checkpoints remain scoped to their original management. Keeper catch-up recovers retained raw
  observations from the latest seven days, not an unretained all-time history. A same-day test
  cannot validate tomorrow's real daily transition or prove a missed historical day.
- Windows, actual gamepad behavior, locales, mixed versions, multiplayer delivery, historical
  recovery, native guild actions, the reported network-ban error in a battleground, and live
  performance remain acceptance gates. Test instructions are in [BETA-TESTING.md](BETA-TESTING.md).
