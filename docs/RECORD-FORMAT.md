# Record mode: the witnesses' file format (format 1)

This page describes the file that Olympus's record mode writes for the Guinness World Records
attempt (recording on 2026-10-20 and 2026-10-21). It gives everything an offline verifier needs:
where the data is, its exact layout, the hash rule and how to compare witnesses. The verifier can be
built from this page alone, without reading any Lua. The code is `Olympus/Record.lua`. A verifier
in Lua can also call the check itself, `Record.VerifyFile` (section 8.1), which uses the recorder's
own hash and line functions. The tests are in `tests/record.lua`, and the two sample files are
`tests/fixtures/record-sample.lua` and `tests/fixtures/record-sample-b.lua`.

## 1. What is recorded, and the units

- **Characters, not people.** A guild roster lists characters, and a player can have several.
- **Online at one instant means accounts online.** A WoW account has at most one character logged
  in at a time. So the characters online in a roster at one server instant equal the game
  accounts online among that guild's characters. It is not a count of people: a player who
  multiboxes with several paid accounts counts once per account. "One instant" needs readings
  taken at the same moment, which section 8 (step 8) defines.
- **One client reads only its own guild's roster.** Each guild therefore needs its own
  witnesses. Census reports from other guilds come from those guilds' reporters, not from the
  witness.
- **Zero new messages.** Record mode sends nothing: no addon message, no chat line, no whisper.
  A test reads `Olympus/Record.lua` and fails if it contains any send call. Everything stays in the
  witness's own SavedVariables until the witness sends the file.
- **Opt-in.** `/oly record on` turns it on for one character. It stays on for that character
  until `/oly record off`. It is off by default, and a player who never turns it on has no
  `OlympusRecordDB` at all.
- **Olympus guilds only.** Record mode works only for a member of an Olympus guild (Olympus's own
  `ns.IsMember`). `/oly record on` is refused elsewhere, and a session ends when the witness's
  guild is not an Olympus guild.
- **Who may record a guild: the author's decision.** The attempt's plan of 28 September said
  that a guild's roster is exported only with its leader's agreement, and that a guild can opt
  out. Record mode does not ask: any member of an Olympus guild who turns it on records that
  guild's roster, GUIDs included, every quarter hour. Whether to require the leader's agreement,
  and how a guild opts out, is the author's call. This page records the difference until he
  decides.

## 2. Collection

- **File.** All of an addon's SavedVariables go into one file, so `OlympusRecordDB` is in
  `WTF\Account\<ACCOUNT>\SavedVariables\Olympus.lua`, next to `OlympusDB`. `<ACCOUNT>` is the
  account's folder name. The file holds every character of that WoW account.
- **When the file is written.** The game writes it at `/reload`, logout or quit, and never in
  between. A crash loses everything since the last write. So witnesses `/reload` or log out
  before they copy the file.
- **New SavedVariable.** The game reads `## SavedVariables: OlympusDB, OlympusRecordDB` only at
  startup. After installing the build, a witness must restart the game (`/reload` is not
  enough). Until then `Record.lua` is not loaded, and `/oly record` prints the restart message.
- **What to send.** At the end of each day, each witness sends `Olympus.lua` to the author.
- **The Forever beta bug.** If the game does not load SavedVariables back at login, every
  session starts with an empty `OlympusRecordDB`. The next write then overwrites the file with
  that session alone, and the record-mode switch is forgotten too. `/oly record status` tells the
  witness which case applies:
  - "loaded this file back with N earlier session(s)": the file accumulates sessions, so each
    day's file also holds the days before;
  - "loaded no earlier record data": on a first use this is normal. Otherwise the witness copies
    the file after **every** logout, before logging in again, and types `/oly record on` again
    after each login.
- **Duplicates.** The verifier must expect the same session in several files, for example
  day 1's sessions again in day 2's file. A session is identified by its `id` (section 4). Its
  lines, `marks`, `n` and `head` must be identical wherever it appears.

## 3. The file's syntax

The file is Lua source written by the game. Parse it as data and never execute it. Only this
subset occurs:

- top-level statements `Name = value`. Skip every name except `OlympusRecordDB`, since
  `OlympusDB` can be several MB;
- tables `{ ... }` whose fields are `["key"] = value,`, `[123] = value,` or `value,`. Array
  values carry a trailing comment such as `-- [17]`. Fields end with `,` (and `;` is also legal);
- strings in double quotes, using Lua 5.1 escapes (`\\`, `\"`, `\n`, `\r`, `\t`, `\ddd` decimal
  and others). The game writes UTF-8 bytes as they are;
- numbers in decimal, plus `true`, `false` and comments `--` up to the end of the line;
- key order is the game's own and has no meaning.

Record lines never contain a byte that needs an escape (section 5.1). An escape inside a record
line is therefore a sign that the file was edited or written by something else. Unescape it as
Lua would, then hash the result: the chain decides.

`scripts/record-check.lua` contains a reference reader for this subset (`M.Parse`, about 100
lines).

## 4. `OlympusRecordDB`

| Field | Type | Meaning |
|---|---|---|
| `format` | string | always `"olympus-record"` |
| `version` | number | `1`, the format on this page. Any other value is another format: refuse it |
| `on` | table | `["Name-Realm"] = <server time>`: the characters of this account that have record mode on, and when it was turned on. Not chained |
| `sessions` | array | the sessions, oldest first (see below) |
| `events` | number | E lines kept on day `eventsDay` (the daily cap). Not chained |
| `eventsDay` | number | the UTC day (`floor(server time / 86400)`) that `events` counts |
| `saves` | number | how many logouts or `/reload`s wrote this table, used to detect whether the game loads the file back. Not chained |

A **session** is one login or `/reload` of one character with record mode on, in one Olympus
guild. A change of guild ends the session, and the next one starts in the new guild if it is an
Olympus guild. A loading screen does not end it: there the game briefly gives no guild name while
the player is still in the guild (`IsInGuild()` is true), and record mode waits.

| Field | Type | Meaning |
|---|---|---|
| `id` | string | `<GUID>:<start>`, made from the S line's fields 5 and 3 |
| `char` | string | the character, `Name-Realm`, a convenience copy of S field 4 |
| `start` | number | the session's start in server time, a convenience copy of S field 3 |
| `lines` | array of strings | **the records**, in order. These are the only chained data |
| `marks` | array of strings | `"<i>:<hash>"`: the chain's hash after line `i`, stored for every S, C and Z line and no other, in line order (`i` in decimal, no leading zero) |
| `head` | string | the chain's hash after line `n` (64 lowercase hex digits) |
| `n` | number | how many lines `head` covers. It equals `#lines` in every written file, because a session is hashed in full when it ends; any other `n`, or none, is refused |
| `ended` | number | the server time of the Z line |

Only `lines` is evidence. `id`, `marks`, `head` and `n` are commitments that the verifier
recomputes and compares: a session that lacks any of them is refused. Everything else is a
convenience and must agree with the lines.

## 5. Lines

### 5.1 General rules

- A line is a string of fields separated by `|`. Field 1 is the line's type: `S`, `M`, `C`, `E`
  or `Z`. Splitting on `|` keeps empty fields: `"C|Q||5"` has 4 fields.
- **Text fields.** Every byte below 0x20, 0x7F, `"`, `\`, `|`, `,` and `:` is replaced by `_`.
  All other bytes are kept as they are, including UTF-8. A missing value is the empty field.
- **Number fields.** Non-negative whole numbers in decimal, with no sign, point, exponent or
  leading zeros (`0` is `0`). A missing value is the empty field.
- **Times** are the server's clock, `GetServerTime()`: Unix seconds (UTC), the same on every
  realm.
- **Lists** are separated by `,`, and a pair inside a list by `:` (`idx:level`).
- **Order.** Line 1 is the S line, and no other line is an S line. The last line of every
  written session is its Z line, and no other line is a Z line. An M line comes before the first
  C line that refers to its member. E lines fall between the others as reports arrive.

### 5.2 `S`: the session's start (always line 1)

| # | Field | Example |
|---|---|---|
| 1 | `S` | `S` |
| 2 | format of the lines | `1` |
| 3 | start, in server time | `1792504740` |
| 4 | witness character, `Name-Realm` | `Witness Example-ClassicBetaPvP` |
| 5 | witness GUID, `UnitGUID("player")` | `Player-0000-0000000A` |
| 6 | guild, `GetGuildInfo("player")` | `Olympus Example` |
| 7 | guild rank index (0 = guild master) | `4` |
| 8 | guild rank name | `Soldier` |
| 9 | faction | `Alliance` |
| 10 | realm (normalised, no spaces) | `ClassicBetaPvP` |
| 11 | Olympus's census realm group | `ClassicBetaPvP` |
| 12 | Olympus version | `1.2.5.1` |
| 13 | test build number, empty for a release | `` |
| 14 | a hash of the player's own BattleTag (below), empty when the game gives none | `973dcf3a...41eb76eb` |
| 15 | client interface number (`GetBuildInfo()`'s 4th) | `16001` |
| 16 | client version and build | `1.60.1.70450` |
| 17 | client locale | `enUS` |

**Field 14** is `SHA256("olympus-record-1|battletag|" .. tag)` as 64 lowercase hex digits, where
`tag` is the BattleTag exactly as `BNGetInfo()`'s 2nd return gives it. The tag itself is never
written, and the status window shows neither the tag nor its hash. The field lets a verifier see
two files of one person (section 8, step 7). Anyone who guesses a tag can test it against the
hash, so it is a pseudonym, not a secret. For `SampleWitness#0000` it is
`973dcf3aa89dd097c64d6764c475996c11ee2aa22b4ec83c542453d341eb76eb`.

### 5.3 `M`: a member, the first time this session sees them

| # | Field | Example |
|---|---|---|
| 1 | `M` | |
| 2 | the member's number in this session (1, 2, 3...) | `4` |
| 3 | name, `Name-Realm` | `Member Bravo-ClassicBetaPvP2` |
| 4 | GUID (empty if the game gave none) | `Player-0000-00000003` |
| 5 | class file (`WARRIOR`, `MAGE`...) | `PRIEST` |
| 6 | level at first sight | `33` |

A member's number is unique to the pair (name, GUID) within one session. If the name or the GUID
changes, the character gets a new number. Numbers mean nothing across sessions or witnesses:
match members by name and GUID.

### 5.4 `C`: a checkpoint of the witness's own guild roster

| # | Field | Example |
|---|---|---|
| 1 | `C` | |
| 2 | kind: `Q` for an automatic quarter hour, `M` for a manual `/oly record mark` | `Q` |
| 3 | slot: for `Q`, the quarter hour (a multiple of 900); for `M`, the time the mark was asked | `1792505700` |
| 4 | when the roster was read, in server time | `1792505702` |
| 5 | guild | `Olympus Example` |
| 6 | total members, `GetNumGuildMembers()`'s 1st return | `8` |
| 7 | online by the game's count, `GetNumGuildMembers()`'s 2nd return (may be empty) | `7` |
| 8 | roster rows read (rows with a name) | `8` |
| 9 | rows flagged online | `7` |
| 10 | **members on the roster**: a bitmap of member numbers (section 6) | `fe8` |
| 11 | **members online**: a bitmap of member numbers | `f68` |
| 12 | level changes since the member's last known level in this session: `idx:level` in ascending idx order, joined by `,`; empty if there are none | `5:13` |

- Field 6 is the server's total, and field 8 is what the client listed. When 8 < 6, the read
  was partial: some offline members may be missing from fields 10 and 11. Record mode reads a
  partial roster 3 times in all, one read per request, the requests about 5 s apart (so about
  12 s), before it writes it as it is. Field 9 counts rows, so a row the game gave twice counts
  twice. The bitmaps count each member once.
- **No roster, no line.** A read with no member (field 6 would be 0) or no row is never written.
  Right after login the game may give no roster yet. Record mode requests it again every 10 s,
  and when none comes within 5 minutes of the slot, there is no C line for that slot.
- **Timing.** Record mode looks at the clock every 5 s, so the roster is requested
  (`C_GuildInfo.GuildRoster()`, listed in Forever's `GuildInfoDocumentation.lua`) 0 to 5 s after
  the slot. It is read 1 s after the game's `GUILD_ROSTER_UPDATE`, or 4 s after the request at the
  latest. In the tests `at − slot` is 2 s; in the game it depends on the server's answer and has
  not been measured yet. The game may throttle roster requests, so the data can be a few seconds
  older than `at`.
- **Never in combat.** A quarter hour that falls in combat is read once combat ends, if that
  happens within 5 minutes of the slot. A session that begins up to 5 minutes after a slot also
  reads that slot at once, unless the file already holds that slot's reading from the same
  character's previous session in the same guild. So one character can still hold two Q lines
  for one slot when the earlier session is in another file (the Forever beta bug, section 2).
  `at − slot` shows how late each read was. Otherwise there is no C line for that slot: a missing
  slot means no reading, never zero.
- The reads use the 1st (name), 4th (level), 9th (online) and 11th (class file) returns of
  `GetGuildRosterInfo(i)` for `i = 1..total`, and the 17th (GUID). This return order is checked
  in Blizzard's Classic Era 1.15.9 `FriendsFrame.lua` (`GetGuildRosterInfo(GetGuildRosterSelection())`,
  17 returns). Olympus's census already reads the same order on Forever (`Roster.lua`).

### 5.5 `E`: a census report from another guild, heard on the channel

| # | Field | Example |
|---|---|---|
| 1 | `E` | |
| 2 | when this client took it, in server time | `1792504870` |
| 3 | the report's own time, field 25 of the report, stamped by its reporter (may be empty) | `1792504868` |
| 4 | guild, as the census keys it | `Olympus Second` |
| 5 | total members, as reported | `950` |
| 6 | online, as reported (the census caps it at the total) | `310` |
| 7 | the guild's addon users, as reported | `12` |
| 8 | the reporter: the sender's name as the server stamped it, `Name-Realm` | `Sample Reporter-ClassicBetaPvP2` |

- Only reports that Olympus's census accepted (`Data.Receive`) are kept. These come from
  Olympus guilds of the witness's faction, never the witness's own guild, and not after a
  conflict outvote.
- **Sampling.** Only the first accepted report of each guild in each quarter hour (by field 2)
  is kept. Guild reporters send about every 170 s, so this is the report nearest after each
  slot. At most 7,000 E lines are kept per UTC day. Beyond that they are only counted, in the
  Z line.
- A report's numbers are its reporter's claim. The same E line heard by several witnesses
  proves that the report was broadcast, not that its count is true.

### 5.6 `Z`: the session's end (always the last line)

| # | Field | Example |
|---|---|---|
| 1 | `Z` | |
| 2 | when, in server time | `1792506000` |
| 3 | why: `logout` (also a `/reload`), `off`, `guild` (the witness left or changed guild, or the guild is not an Olympus guild; never a loading screen) or `full` | `logout` |
| 4 | census reports not kept in this session (the daily cap) | `0` |

## 6. Bitmaps

A bitmap is a set of member numbers written as lowercase hex digits. Digit `d` (from 1) holds
members `4d−3` (value 8), `4d−2` (4), `4d−1` (2) and `4d` (1). Trailing `0` digits are left
out, and the empty set is the empty field.

```
members {1, 3, 4, 9}      -> "b08"   (1+3+4 = 8+2+1 = b; 5-8 none = 0; 9 = 8)
members {1, 2, 4, 6, 7}   -> "d6"
members {1..7, 9}         -> "fe8"
```

## 7. The hash chain

- **Hash.** SHA-256 (`ns.Sign.SHA256`, FIPS 180-4), written as 64 lowercase hex digits. The
  hash input is the line's bytes exactly as stored, with no newline added.
- **Seed.** `h0 = SHA256("olympus-record-1|" .. S[5] .. "|" .. S[3])`, where `S[5]` (the GUID)
  and `S[3]` (the start) are the S line's fields exactly as written.
- **Links.** `h_i = SHA256(h_(i−1) .. "|" .. line_i)` for `i = 1..n`, where `h_(i−1)` is the
  64-character hex string, not raw bytes.
- **Stored.** `head = h_n` with `n = #lines`. `marks` holds `"i:h_i"` for every S, C and Z line.
- **Check.** Recompute every `h_i`. The session is valid when line 1 is its only S line, the
  last line is its only Z line, `n` equals `#lines`, every mark equals its `h_i`, `head` equals
  `h_n`, and `id` equals `S[5] .. ":" .. S[3]`. Each of `id`, `marks`, `n` and `head` must be
  present, and `marks` must hold exactly one mark for each S, C and Z line, none for any other
  line, in line order, each written `i:h_i` with `i` in decimal and no leading zero: a mark left
  out, repeated, out of order, on an M or E line or for line 0 is refused, and so is a wrong mark
  even when the right one for the same line is also there. A line after the Z line is refused
  even when every hash was computed again for it. Marks exist only for S, C and Z lines, so the
  first mark that differs, at line `i`, places the change after the previous mark's line and at
  or before line `i`. An M or E line edited after the last C line breaks only the Z mark and
  `head`. A line removed or moved is found in the same way, at the first mark after it: compare
  each mark with its hash before the marks' places, `n` and `head`, since a removed line also
  moves the S, C and Z lines away from their marks and changes `n`.

Vectors (checked against Python's `hashlib`):

```
SHA256("")                                   = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
seed for GUID Player-0000-00000001, start 1792483200
  SHA256("olympus-record-1|Player-0000-00000001|1792483200")
                                             = fb8d3cadfb9b6377f6f6ca518a1953bdd8edb24e424ee1aef982ecdc7e638b9f
field 14 for the BattleTag SampleWitness#0000
  SHA256("olympus-record-1|battletag|SampleWitness#0000")
                                             = 973dcf3aa89dd097c64d6764c475996c11ee2aa22b4ec83c542453d341eb76eb
h1 for the line
  S|1|1792483200|Witness Example-ClassicBetaPvP|Player-0000-00000001|Olympus Example|4|Soldier|Alliance|ClassicBetaPvP|ClassicBetaPvP|1.2.5.1||973dcf3aa89dd097c64d6764c475996c11ee2aa22b4ec83c542453d341eb76eb|16001|1.60.1.70450|enUS
                                             = b4d70a7f064a26ed45d75604d8a4279db182e0551066bbdd07cb98e4b3e289bf
```

The samples (section 10):

```
tests/fixtures/record-sample.lua    session Player-0000-0000000A:1792504740, 17 lines,
  head 95bd06d6c5853eaad1af8e9e3d42c6c93cea3e8893226b367b586ba648683344
tests/fixtures/record-sample-b.lua  session Player-0000-0000000B:1792505100, 13 lines,
  head d50c51179f068b5bffa0a396a70f33f037f941e6659c4eb0771cbc20cfb8dbf0
```

In the game the client hashes a few lines each frame (about 2 KB of lines a frame, paused in
combat), so a 1000-member guild's first checkpoint (about 1,000 M lines) is spread over frames
rather than done at once. Its cost in the game has not been measured yet. All remaining lines
are hashed at logout, before the game writes the file. `/oly record status` shows the head so far (its first
16 hex digits) and how many lines it covers.

### 7.1 What the chain proves, and what it does not

It proves:

- **Integrity after a published head.** Once a head has left the witness's hands (read out on
  stream, posted in Discord, screenshotted at a checkpoint), no line it covers can change
  without changing that head. Ask witnesses to post their status head at each checkpoint they
  can, and at least before sending each day's file. The status window shows the character but
  no BattleTag and no hash of it, so it can be posted as it is.
- **Order and completeness within a session.** A line cannot be removed, inserted or reordered
  without breaking every later mark and the head.

It does not prove:

- **Anything against the witness before a head is published.** No secret goes into the chain,
  so whoever holds the file can edit it and compute every hash again. A test shows exactly this.
- **That the code that wrote it was Olympus's.** A modified client can write anything.
- **That the counts are true.** Only agreement between **independent witnesses** of one guild,
  and Blizzard's own UI on stream, give weight to a number.
- **People.** It counts characters, and accounts online at one instant (section 1).

## 8. Verifying N witness files

1. Parse each file (section 3) and take `OlympusRecordDB`. Refuse any `format` or `version`
   other than those in section 4.
2. For each session, check the chain (section 7). Report the first broken line, and keep a
   broken session out of the counts.
3. Deduplicate sessions by `id` across files. Copies with the same `id` must be identical: the
   same lines, `marks`, `n`, `head` and stored `id`, each of the same type. Flag any that are not,
   whatever the files' order, and keep every copy of that `id` out of the counts. (The game writes
   a session's marks with its lines, so two genuine copies always have the same marks. A copy
   with only its marks, `n`, `head` or `id` edited is refused by the check in section 7; without
   this rule, whether the session counted would depend on which file came first.)
4. Rebuild each session's dictionary from its M lines (`number -> name|GUID`), and each
   member's level from the M lines and the C lines' field 12.
5. Decode each C line's fields 10 and 11 into sets of `name|GUID`.
6. Group the Q checkpoints by (guild, case-insensitive; slot). For each group, compare across
   witnesses:
   - the total (field 6);
   - the set of members on the roster (field 10, decoded);
   - the set of members online (field 11, decoded).

   Flag every difference with each reading's `at − slot`. A member who logs in or out between
   two witnesses' reads, a second or two apart, is an expected small difference, not a
   contradiction.
7. **Independence.** Sessions in one file come from one WoW account and are one witness.
   Sessions with the same non-empty S field 14 (one BattleTag's hash) are one person. Sessions
   of the same character (S field 4) are one witness, on any day and in any file. Join these
   into witnesses, and keep each witness's reading nearest the slot for each (guild, slot): a
   `/reload` just after a slot can give one witness two readings of it. Count distinct
   witnesses.
8. **The figure at a slot T.** Use only C lines read at most 30 s after T (`at − slot ≤ 30`):
   only these are readings at one server instant. Per guild, take the online set its
   independent witnesses agree on among them. Where they do not agree, the verifier's rule
   should be the conservative one: the intersection, or the lowest count. Sum over the guilds,
   label the result "characters online at T = accounts online at T among the guilds' rosters",
   and give the largest `at − slot` used for that slot.
   - List later readings separately, each labelled "read N s after T", and never add them to the
     figure. A player who switches from a character in guild A (read at T + 2 s) to one in guild B
     (read at T + 4 min) would otherwise count twice.
   - For a guild with no witness, the only data is its E line for that slot. It is the guild's
     reporter's claim, made at field 3 (when the reporter's client made the report, right after
     its roster read). List it separately, labelled with its distance from T (field 3 − T) and as
     the reporter's claim, not witnessed. Add it to the figure only within the same 30 s, and say
     so.
9. Manual marks (`M` checkpoints) are extra points, at the time the witness asked for them.
   Compare them only where several witnesses marked within a few seconds of each other.

`luajit scripts/record-check.lua FILE...` already does steps 1 to 7 for the quarter hours, with
`Record.VerifyFile` and `Record.Dedupe` (section 8.1) for steps 1 to 5. It counts each witness
once, prints each reading's `at − slot` and lists readings more than 30 s after the slot apart. A
session that repeats an earlier one exactly in the same file is listed once, and the file's line
says how many repeats were left out; copies in one file that differ are each listed as such. It
exits 1 when a chain breaks or two copies of one session differ.

### 8.1 The check in Lua: `Record.VerifyFile`

`Olympus/Record.lua` holds the hash rule and the reading of lines once. The recorder writes with
them. `Record.VerifyFile` uses the same functions to check a whole file (steps 1 to 5; the caller
parses the file), so `scripts/record-check.lua` and the Companion's verifier have no copy of their
own. It calls no WoW API, neither when the file loads nor when it runs. It needs Lua 5.1 or
LuaJIT, and the `bit` library that `Olympus/Sign.lua` reads as `_G.bit` (built into LuaJIT).
`tests/record.lua` runs it with no other global.

```lua
local ns = { L = {} }                         -- ns.L: any table (only the game's text reads it)
assert(loadfile("Olympus/Sign.lua"))("Olympus", ns)    -- ns.Sign.SHA256
assert(loadfile("Olympus/Record.lua"))("Olympus", ns)  -- ns.Record
local result = ns.Record.VerifyFile(db, ns.Sign.SHA256)
```

- `db` is `OlympusRecordDB` as the file holds it, parsed as data (section 3;
  `scripts/record-check.lua`'s `M.Parse` reads it).
- `sha256(text)` returns the 32 raw bytes of SHA-256, as `ns.Sign.SHA256` does. When it is
  `nil`, `ns.Sign.SHA256` is used. A function that returns anything other than 32 bytes, such as
  a hex string, raises an error.
- The namespace needs nothing beyond `ns.Sign` and `ns.L`. `ns.On`, the game client's event
  hook, is optional: without it nothing is hooked. Loading adds only `ns.Record`.

`result`:

| Field | Meaning |
|---|---|
| `ok` | `true` when the file is format 1, every session verifies and no two copies of one session differ |
| `why` | set when the file itself is refused (step 1): `"no OlympusRecordDB of format 1"`; `sessions` is then empty |
| `sessions` | the sessions, in the file's order, each copy that repeats an earlier one exactly left out |
| `conflicts` | `{ id = ..., copies = <n> }` for each `id` whose copies in this file differ (step 3). Every copy stays in `sessions`, with `ok = false` |
| `duplicates` | how many exact copies were left out |

Each session:

| Field | Meaning |
|---|---|
| `id` | the stored `id`; when it is not text, `S[5] .. ":" .. S[3]` (the session is then not `ok`) |
| `character` | S field 4, `Name-Realm` |
| `witness` | S field 5, the witness's GUID |
| `guild` | S field 6 |
| `battleTagHash` | S field 14, or `nil` when it is empty |
| `start` | S field 3, in server time |
| `records` | the number of lines, `#lines` |
| `firstHash` | `h_1`, the chain's hash after the S line (its mark `1:...`) |
| `lastHash` | `h_n`, computed again from the lines as they are, even in a broken session. It is the value to compare with a head published at the time, and equals `head` when `ok` |
| `ok` | the chain and every stored commitment agree (section 7) and no other copy in the file differs |
| `brokenAt` | when not `ok` because of the session itself: the first line found wrong, or `0` for the session's own fields (no `lines`; no `id`, `marks`, `n` or `head`; a wrong `id` or `n`; a mark that is not `i:hash` as section 7 writes it, or one for line 0). `nil` when only the copies differ |
| `why` | when not `ok`: the reason, with the line, such as `"line 15: its mark is not its hash"` |
| `copy` | a hash of the copy as stored (its lines, `marks`, `n`, `head` and `id`, each with its type). Two sessions with one `id` are the same copy when their `copy` is equal, and then they check the same |
| `observations` | each C and E line, in order (below) |
| `roster` | `[checkpoint] = { present = {...}, online = {...}, presentKeys = {...}, onlineKeys = {...} }` |

`firstHash` and `lastHash` are `nil` when line 1 is not an S line of format 1, and `lastHash` is
also `nil` when a line is not text. The observations and rosters of a broken session are still
read, but a broken session stays out of the counts (step 2).

Each observation:

| Field | C line | E line |
|---|---|---|
| `kind` | `"C"` | `"E"` |
| `guild` | field 5 | field 4 |
| `checkpoint` | for `Q`, the slot (field 3, a number); for `M`, `"mark:" ..` field 3, the time the mark was asked | the quarter hour of field 2 (`t − t % 900`) |
| `readAt` | field 4 | field 2 |
| `total` | field 6 | field 5 |
| `online` | field 7, the game's count (`nil` when empty) | field 6 |
| `slot` | field 3 | |
| `rows`, `rowsOnline` | fields 8 and 9 | |
| `reportedAt`, `users`, `reporter` | | fields 3, 7 and 8 (`reporter` is `nil` when empty) |
| `line` | the line's index in the session | the same |

Number fields are read only when they are written as section 5.1 says (decimal, no sign, no
leading zero); otherwise they are `nil`.

`roster[checkpoint]` decodes the C line's fields 10 (`present`) and 11 (`online`) with the
session's M lines up to that line (steps 4 and 5): `present` and `online` hold `"Name-Realm"`, and
`presentKeys` and `onlineKeys` hold `"Name-Realm|GUID"`, the identity to compare across witnesses.
Each list is sorted. A member number that no M line gave appears as `"?<number>"`. A session as the
game writes it never holds two C lines for one checkpoint. If an edited file does, `roster` keeps
the first, and `observations` lists both.

Across files, `Record.Dedupe(sessions)` applies step 3 to the sessions of several results:

```lua
local kept, conflicts, duplicates = ns.Record.Dedupe(allSessions)
-- kept: the first copy of each id whose copies all have one `copy`
-- conflicts: { id = ..., copies = { session, ... } } for each id whose copies differ; none is kept
```

`VerifyFile` applies the same function within one file. `Record.Verify(session, sha256)` checks a
single session and returns `true, head, n`, or `false, line, why`.

## 9. Limits and sizes

| Limit | Value |
|---|---|
| quarter hour checkpoints | every 900 s of server time, read up to 300 s late (combat, a late login), else missed |
| a partial roster | read 3 times, about 5 s apart, then written as it is |
| no roster yet | asked again every 10 s, never written; missed after 300 s |
| manual marks | one a minute |
| E lines | the first per guild per quarter hour; at most 7,000 per UTC day |
| lines per file | 120,000 (about 10 MB on disk, at about 86 bytes a line). After that the session ends with `Z ... full` and no new one begins |
| hashing in the game | about 2 KB of lines per frame, paused in combat, finished at logout |

Measured by `tests/record.lua`, for one witness in a 1,000-member guild recording for two whole
days, with a `/reload` every 8 hours (6 sessions, 6,000 M lines, 192 checkpoints, 40% of the
guild online and changing every quarter hour):

- the roster lines take **495,555 bytes**;
- the whole `OlympusRecordDB` as the game writes it takes **1,896,735 bytes**. 70 other guilds'
  E lines for every quarter hour of both days are most of that.

A heavier case, also measured by `tests/record.lua`: a witness in a 1,000-member guild who logs in
again every 50 minutes for a whole day writes 29 sessions, with 70 other guilds reporting all
day. That is 37,204 lines (3,201,836 bytes, about 86 bytes a line), under a third of the limit,
so both days of the attempt fit. A real witness online for part of each day writes much less.

## 10. The samples

`tests/fixtures/record-sample.lua` (witness A) and `tests/fixtures/record-sample-b.lua` (witness
B) are fake files: invented names, the realm names that Olympus's other fixtures use, and GUIDs
on server `0000`. Each file has an `OlympusDB` before `OlympusRecordDB`, which a verifier must
skip. Both witnesses are in `<Olympus Example>`:

- A logs in at 13:59 UTC on 2026-10-20 and turns record mode on. A takes 14:00, marks at 14:10,
  takes 14:15 and logs out at 14:20. A's game gives a BattleTag, so A's S line holds its hash.
- B logs in at 14:05, takes 14:15 and logs out at 14:20. B's game gives none, so field 14 is
  empty.
- Between 14:00 and 14:15, Charlie goes from level 12 to 13, Alpha logs in, Echo leaves and
  Foxtrot joins.
- A's 14:15 checkpoint and B's agree on the total (8), the members and the members online,
  although their member numbers differ: Foxtrot is 9 for A and 8 for B.
- Both witnesses heard the same census reports from their arrival on.

`tests/record.lua` regenerates both samples and fails if either file differs from what it
generates, so the samples always match the code. `OLYMPUS_RECORD_SAMPLE_WRITE=1` rewrites them,
and `OLYMPUS_RECORD_SAMPLE_OUT=DIR` also writes copies to DIR.

## 11. Changes

Format 1 is fixed for the 2026-10-20/21 attempt. Any change to a line, a field or the hash rule
will raise `version` (and the S line's field 2), and this page will describe both formats.

Before the attempt (2026-10-19), while no witness file existed yet, format 1 changed in these
ways without a new version:

- S field 14 holds a hash of the BattleTag (section 5.2), no longer the tag;
- a read with no roster is never written, and a partial one is read about 5 s apart (5.4);
- a loading screen no longer ends a session; a session begins only in an Olympus guild (4);
- a /reload just after a slot does not read it again when the file holds the earlier reading;
- the limit is 120,000 lines per file (9);
- the check refuses a line after the Z line, a second S line and any `n` other than `#lines`
  (7); copies of one session must be identical (8, step 3); each witness counts once per slot,
  and only readings within 30 s of the slot make the figure at one instant (8, steps 7 and 8);
- copies of one session must also have the same `marks` (8, step 3), and the check compares
  `n` after the marks, so a removed line is found at the first mark after it (7). The check is
  available in Lua as `Record.VerifyFile` (8.1);
- the check refuses a session with no `id`, `marks`, `n` or `head`, and requires exactly one mark
  per S, C and Z line in line order (7); copies of one session must also have the same stored
  `id`, of the same type (8, step 3).
