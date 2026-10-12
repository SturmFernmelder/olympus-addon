# The Olympus API, for addon authors

Olympus 1.2.4 lets other addons read, with the player's permission, what Olympus already shows
that player on its own pages. This page is the whole contract of version 1 (`OlympusAPI.VERSION`).

- **Read-only.** No function sends a chat line, a decree, a whisper or any addon message for the
  player, and none changes anything in Olympus.
- **Only what the player already sees, at no more detail.** The Wanted list and its bounties, the
  public rankings, the player's own frame and title, and his own Olympus guild, rank and role.
- **One permission per addon.** Your addon calls `OlympusAPI.Register`, the player answers **Yes**
  or **No** for it on Olympus's privacy page, and nothing comes back before a Yes.
- **Copies.** Every table you get is built for that call. Changing it changes only your copy.
- **Pushed, not polled.** Callbacks tell you when something changed.

## Getting started

Add Olympus as an optional dependency in your TOC, so that it loads before your addon when both
are installed:

```
## OptionalDeps: Olympus
```

Then register once, when your addon loads:

```lua
local api
if OlympusAPI and OlympusAPI.VERSION >= 1 then
	api = OlympusAPI.Register("MyAddon") -- your addon's folder name, as in its TOC file's name
end
if not api then return end -- no Olympus, an older one, or the name was refused

api:On("PERMISSION_CHANGED", function(event, status)
	if status == "granted" then
		-- the player said Yes: read what you need now
	end
end)

api:On("WANTED_CHANGED", function(event, rows)
	-- rows is what api:GetWanted() returns now, your own copy
end)

if api:Status() == "granted" then
	local rows = api:GetWanted()
end
```

`OlympusAPI` is `nil` when Olympus is not installed, is older than 1.2.4, or was just updated to
1.2.4 and the game has not restarted since: a file an update adds is loaded only when the game
starts, not on a `/reload`. Always check for it.

## Permission

`OlympusAPI.Register("MyAddon")` adds a line for your addon to Olympus's privacy page (the page
`/oly privacy` opens). The line shows your TOC's `## Title` (colour and texture codes removed) and
says, in Olympus's own words, what a Yes lets your addon read. The page opens by itself once for a
new line, outside combat and instances, while the player is in an Olympus guild; the player can
answer there at any time, and change the answer whenever he likes.

- `"pending"`: never answered. Your calls return nothing.
- `"granted"`: the player said Yes. Your calls return data.
- `"refused"`: the player said No. Your calls return nothing.

The page's **Accept all** button never answers for an addon: only the player's own Yes on your
line does. Each addon is asked on its own. The answer is kept for the player's account and stays
across sessions. When a later API version gives more than version 1 does, every addon's line is
asked again.

## Reference

### `OlympusAPI.VERSION`

A number: `1` for this contract. A change that breaks this contract raises it. New fields may be
added to the tables below without raising it: ignore the fields you do not know.

### `OlympusAPI.Has(feature)`

`true` when this build gives that feature, `false` otherwise:

| Feature | What |
|---|---|
| `"wanted"` | `handle:GetWanted()` |
| `"rankings"` | `handle:GetRankings()` |
| `"rankings.slayers"`, `"rankings.donors"`, `"rankings.church"`, `"rankings.games"` | that kind of ranking (a build without the games has no `"rankings.games"`) |
| `"profile"` | `handle:GetProfile()` |
| `"callbacks"`, and each event's name | `handle:On(...)` |

### `OlympusAPI.Register(addonName)`

Returns your addon's **handle**, or `nil` and a reason:

| Reason | Why |
|---|---|
| `"name"` | not a string, empty, longer than 64 characters, or with a vertical bar or a control character |
| `"self"` | Olympus's own name |
| `"unknown"` | no installed addon has that name |
| `"taken"` | that name was already registered this session (a handle is given once per session, to the first caller) |
| `"full"` | 16 addons already registered this session |
| `"consent"` | the privacy page could not take the line (Olympus's privacy file is missing) |

Keep the handle in a local variable: it is your addon's own. `OlympusAPI` and every handle are
read-only tables. Every method works with `handle:Method(...)` and `handle.Method(...)` alike.

### `handle:Status()`

`"granted"`, `"refused"` or `"pending"`. Free: it never counts against the rate limit.

### `handle:Name()`

The name you registered.

### `handle:GetWanted()`

The Wanted list as the Wanted tab lists it, its active entries in its order:

```lua
{
	{ place = 1, name = "Grashk Bloodfen-Emberfall", guid = "Player-4002-00C0FFEE", bounty = 42, kills = 3, cycle = 2 },
	...
}
```

`bounty` is the current bounty in points, `kills` the Olympus members he killed, `cycle` the
bounty's cycle; `name` can be `nil` when the game has not told a name for that GUID. Never the
victims, the claims, the sightings, who added or took off an entry, nor any time.

### `handle:GetRankings([kind])`

Every public ranking (no argument), or one kind: `"slayers"`, `"donors"`, `"church"` or `"games"`.
A kind this build lacks, or one with nothing public now (the Church's ranking closed), is `nil`.

```lua
{
	slayers = {
		month = { { place = 1, name = "Torvin Hale-Emberfall", points = 70, claims = 1 }, ... }, -- this month, at most 50
		all = { ... },     -- all time, at most 50
		signed = { ... },  -- the signed top three this client holds, when it holds one (name nil when unknown)
	},
	donors = { month = { "Name-Realm", ... }, all = { "Name-Realm", ... } }, -- the top three of each
	church = { missionaries = { "Name-Realm", ... }, apostles = { "Name-Realm", ... } }, -- its public top three
	games = { -- only the games the King made public
		arena = { { place = 1, name = "Name-Realm", rating = 1520, wins = 9, losses = 2 }, ... },
		bones = { { place = 1, name = "Name-Realm", games = 12, won = 8 }, ... },
		lottery = { latest = { { name = "Name-Realm", day = "10-11", beast = "07 Sheep", amount = 25000 }, ... },
			biggest = { { place = 1, name = "Name-Realm", amount = 25000 }, ... } },
	},
}
```

The Slayers boards are this client's own (what it observed), as the Wanted tab says. A game the
King keeps to the staff is not there, whoever the player is. `amount` is in copper.

### `handle:GetProfile()`

The player himself. In an Olympus guild:

```lua
{ member = true, name = "Lida Fenn-Emberfall", guild = "Olympus Ember", rank = "Member", rankIndex = 3,
	role = "member", frame = "donor-top-3", title = "Friend of the Treasury" }
```

`rankIndex` is 0 for the guild master. `role` is the highest he holds: `"king"`, `"councillor"`,
`"steward"`, `"treasurer"`, `"guildmaster"`, `"officer"` or `"member"`. `frame` is the frame his
profile shows: an honour's key, `"rank"` (his rank's frame) or `"none"`. `title` is his title's
words, or `nil`.

Outside an Olympus guild it is `{ member = false }`, and `GetWanted` and `GetRankings` return
`nil, "guild"`.

### `handle:On(event, fn)` and `handle:Off(event[, fn])`

`On` adds a callback and returns `true` (`false` for an unknown event, a non-function, or past 4
callbacks for that event). `Off` removes that callback, or every one of yours for the event
without `fn`.

| Event | `fn(event, ...)` | When |
|---|---|---|
| `WANTED_CHANGED` | `fn(event, rows)`: what `GetWanted()` returns | the Wanted list changed |
| `RANKINGS_CHANGED` | `fn(event, rankings)`: what `GetRankings()` returns | a public ranking changed |
| `PROFILE_CHANGED` | `fn(event, profile)`: what `GetProfile()` returns | the frame, title, guild, rank or role changed, or the player joined or left an Olympus guild |
| `PERMISSION_CHANGED` | `fn(event, status)`: `"granted"` or `"refused"` | the player answered your line |

- The data events come only while the player's answer is Yes (`WANTED_CHANGED` and
  `RANKINGS_CHANGED` only in an Olympus guild), and only when the data you would get differs from
  what you were last told: you may register before the Yes.
- A burst of changes is told once, about 2 seconds after it, never in combat (it waits for the
  combat to end).
- Each callback gets its own copy, and its call never counts against the rate limit.
- A callback that raises an error is caught: Olympus logs it with your addon's name, and Olympus and
  the other callbacks go on. A callback that fails 3 times is removed.

### Failures

Every data method returns `nil` and a reason when it gives nothing:

| Reason | Why |
|---|---|
| `"pending"`, `"refused"` | no Yes from the player |
| `"guild"` | the player is in no Olympus guild |
| `"busy"` | more than 20 data calls from your addon in 10 seconds: wait, or use the callbacks |
| `"kind"` | `GetRankings` was given an unknown kind |

## What it never gives

The census of the guilds, other players' private data, a location (the Wanted page's victims and
sightings stay on the page), the GUID of an Olympus member, the times of anyone's activity, the
staff's views, or any secret: no key, no sealed channel name, no signature, no private list.
Each row is built field by field from the page's own data, so what Olympus adds to its own tables
later never reaches your addon unless this contract adds it.

## What it is not

Every addon runs in the same Lua environment, so this is a courtesy boundary, not a lock: an
addon could read Olympus's saved variables directly. The API is the supported and consented way
in: it asks the player, gives your addon a stable contract, and keeps Olympus from handing out
anything on its own. Please use it, and only for what the player said Yes to.

## Examples

Marking Wanted Horde players on your nameplates, by GUID:

```lua
local wanted = {}
local function Take(rows)
	wipe(wanted)
	for _, r in ipairs(rows or {}) do if r.guid then wanted[r.guid] = r.bounty end end
end
api:On("WANTED_CHANGED", function(_, rows) Take(rows) end)
api:On("PERMISSION_CHANGED", function(_, status)
	if status == "granted" then Take(api:GetWanted()) else wipe(wanted) end
end)
if api:Status() == "granted" then Take(api:GetWanted()) end

local function Bounty(unit) return wanted[UnitGUID(unit) or ""] end
```

Showing the month's top Slayer:

```lua
local function TopSlayer()
	local slayers = api:GetRankings("slayers")
	local first = slayers and slayers.month[1]
	return first and first.name, first and first.points
end
```

Showing the player's own title in your frame:

```lua
api:On("PROFILE_CHANGED", function(_, profile)
	MyFrame.title:SetText(profile.member and profile.title or "")
end)
```
