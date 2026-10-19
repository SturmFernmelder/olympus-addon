# Record mode: the witnesses' file format (format 1)

This page describes the file that Olympus's record mode writes for the Guinness World Records
attempt (recording on 2026-10-20 and 2026-10-21). It gives everything an offline verifier needs:
where the data is, its exact layout, the hash rule and how to compare witnesses. The verifier can be
built from this page alone, without reading any Lua. The code is `Olympus/Record.lua`. The tests are
in `tests/record.lua`, and the two sample files are `tests/fixtures/record-sample.lua` and
`tests/fixtures/record-sample-b.lua`.

## 1. What is recorded, and the units

- **Characters, not people.** A guild roster lists characters, and a player can have several.
- **Online at one instant means accounts online.** A WoW account has at most one character logged
  in at a time. So the characters online in a roster at one server instant equal the accounts
  online among that guild's characters. The one exception is a player who multiboxes with several
  paid accounts.
- **One client reads only its own guild's roster.** Each guild therefore needs its own
  witnesses. Census reports from other guilds come from those guilds' reporters, not from the
  witness.
- **Zero new messages.** Record mode sends nothing: no addon message, no chat line, no whisper.
  A test reads `Olympus/Record.lua` and fails if it contains any send call. Everything stays in the
  witness's own SavedVariables until the witness sends the file.
- **Opt-in.** `/oly record on` turns it on for one character. It stays on for that character
  until `/oly record off`. It is off by default, and a player who never turns it on has no
  `OlympusRecordDB` at all.

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
  lines must be byte-identical wherever it appears.

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

A **session** is one login or `/reload` of one character with record mode on, in one guild. A
change of guild ends the session, and the next one starts in the new guild.

| Field | Type | Meaning |
|---|---|---|
| `id` | string | `<GUID>:<start>`, made from the S line's fields 5 and 3 |
| `char` | string | the character, `Name-Realm`, a convenience copy of S field 4 |
| `start` | number | the session's start in server time, a convenience copy of S field 3 |
| `lines` | array of strings | **the records**, in order. These are the only chained data |
| `marks` | array of strings | `"<i>:<hash>"`: the chain's hash after line `i`, stored for every S, C and Z line |
| `head` | string | the chain's hash after line `n` (64 lowercase hex digits) |
| `n` | number | how many lines `head` covers. It equals `#lines` in every written file, because the logout hashes everything |
| `ended` | number | the server time of the Z line |

Only `lines` is evidence. `marks`, `head` and `n` are commitments that the verifier recomputes
and compares. Everything else is a convenience and must agree with the lines.

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
- **Order.** Line 1 is the S line. The last line of every written session is the Z line. An M
  line comes before the first C line that refers to its member. E lines fall between the others
  as reports arrive.

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
| 14 | the player's own BattleTag (`BNGetInfo()`'s 2nd return), empty when the game gives none | `SampleWitness#0000` |
| 15 | client interface number (`GetBuildInfo()`'s 4th) | `16001` |
| 16 | client version and build | `1.60.1.70450` |
| 17 | client locale | `enUS` |

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
  was partial: some offline members may be missing from fields 10 and 11. Record mode asks again
  up to 3 times before it writes a partial read. Field 9 counts rows, so a row the game gave
  twice counts twice. The bitmaps count each member once.
- **Timing.** The roster is requested (`C_GuildInfo.GuildRoster()`, listed in Forever's
  `GuildInfoDocumentation.lua`) at the slot and read 1 s after the game's `GUILD_ROSTER_UPDATE`,
  or 4 s after the request at the latest. In the tests `at − slot` is 2 s; in the game it depends
  on the server's answer and has not been measured yet. The game may throttle roster requests,
  so the data can be a few seconds older than `at`.
- **Never in combat.** A quarter hour that falls in combat is read once combat ends, if that
  happens within 5 minutes of the slot. A session that begins up to 5 minutes after a slot also
  reads that slot at once. `at − slot` shows how late each read was. Otherwise there is no C line
  for that slot: a missing slot means no reading, never zero.
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
| 3 | why: `logout` (also a `/reload`), `off`, `guild` (the witness left or changed guild) or `full` | `logout` |
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
- **Check.** Recompute every `h_i`. The session is valid when every mark equals its `h_i`,
  `head` equals `h_n`, and `id` equals `S[5] .. ":" .. S[3]`. Marks exist only for S, C and Z
  lines, so the first mark that differs, at line `i`, places the change after the previous
  mark's line and at or before line `i`. An M or E line edited after the last C line breaks
  only the Z mark and `head`.

Vectors (checked against Python's `hashlib`):

```
SHA256("")                                   = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
seed for GUID Player-0000-00000001, start 1792483200
  SHA256("olympus-record-1|Player-0000-00000001|1792483200")
                                             = fb8d3cadfb9b6377f6f6ca518a1953bdd8edb24e424ee1aef982ecdc7e638b9f
h1 for the line
  S|1|1792483200|Witness Example-ClassicBetaPvP|Player-0000-00000001|Olympus Example|4|Soldier|Alliance|ClassicBetaPvP|ClassicBetaPvP|1.2.5.1||SampleWitness#0000|16001|1.60.1.70450|enUS
                                             = fab4a9c5c564c053fdf89d00322d9c59b253f74af68cf346ce6b51ac9aa5c080
```

The samples (section 10):

```
tests/fixtures/record-sample.lua    session Player-0000-0000000A:1792504740, 17 lines,
  head 8d4b9293d2601663f36c667d0ab4853a827023ddae3797ed0af6b2158b8d19ac
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
  can, and at least before sending each day's file.
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
3. Deduplicate sessions by `id` across files. Copies with the same `id` must be identical up to
   the shorter one's `n`. Flag any that are not.
4. Rebuild each session's dictionary from its M lines (`number -> name|GUID`), and each
   member's level from the M lines and the C lines' field 12.
5. Decode each C line's fields 10 and 11 into sets of `name|GUID`.
6. Group the Q checkpoints by (guild, case-insensitive; slot). For each group, compare across
   witnesses:
   - the total (field 6);
   - the set of members on the roster (field 10, decoded);
   - the set of members online (field 11, decoded).

   Flag every difference with the witnesses' `at` times. A member who logs in or out between two
   witnesses' reads, a second or two apart, is an expected small difference, not a
   contradiction.
7. **Independence.** Sessions in one file come from one WoW account and are one witness.
   Sessions with the same non-empty BattleTag (S field 14) are one person. Sessions of the same
   character on different days are still one witness. Count independent witnesses per group
   accordingly.
8. **The figure at a slot T.** Per guild, take the online set its independent witnesses agree
   on. Where they do not agree, the verifier's rule should be the conservative one: the
   intersection, or the lowest count. Then sum over the guilds and label the result "characters
   online at T = accounts online at T among the guilds' rosters". For a guild with no witness,
   take only the E line of that slot (the report nearest after T, field 3). Mark it as the
   guild's reporter's claim, not as witnessed.
9. Manual marks (`M` checkpoints) are extra points, at the time the witness asked for them.
   Compare them only where several witnesses marked within a few seconds of each other.

`luajit scripts/record-check.lua FILE...` already does steps 1 to 6 for the quarter hours, and
exits 1 when a chain breaks.

## 9. Limits and sizes

| Limit | Value |
|---|---|
| quarter hour checkpoints | every 900 s of server time, read up to 300 s late (combat), else missed |
| manual marks | one a minute |
| E lines | the first per guild per quarter hour; at most 7,000 per UTC day |
| lines per file | 30,000. After that the session ends with `Z ... full` and no new one begins |
| hashing in the game | about 2 KB of lines per frame, paused in combat, finished at logout |

Measured by `tests/record.lua`, for one witness in a 1,000-member guild recording for two whole
days, with a `/reload` every 8 hours (6 sessions, 6,000 M lines, 192 checkpoints, 40% of the
guild online and changing every quarter hour):

- the roster lines take **495,555 bytes**;
- the whole `OlympusRecordDB` as the game writes it takes **1,896,735 bytes**. 70 other guilds'
  E lines for every quarter hour of both days are most of that.

A real witness online for part of each day writes much less.

## 10. The samples

`tests/fixtures/record-sample.lua` (witness A) and `tests/fixtures/record-sample-b.lua` (witness
B) are fake files: invented names, the realm names that Olympus's other fixtures use, and GUIDs
on server `0000`. Each file has an `OlympusDB` before `OlympusRecordDB`, which a verifier must
skip. Both witnesses are in `<Olympus Example>`:

- A logs in at 13:59 UTC on 2026-10-20 and turns record mode on. A takes 14:00, marks at 14:10,
  takes 14:15 and logs out at 14:20.
- B logs in at 14:05, takes 14:15 and logs out at 14:20.
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
