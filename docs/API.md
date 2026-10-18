# The Olympus API, for addon authors

Olympus 1.2.4 lets other addons read, with the player's permission, what Olympus already shows
that player on its own pages. An addon can also contribute one page to the Olympus window without
copying its shell. This page is the whole contract of version 1 (`OlympusAPI.VERSION`).

- **Read-only data.** The ordinary data functions send no chat line, decree, whisper or addon
  message and change nothing in Olympus. The optional, separately identified player-sighting
  capability is the sole exception: an authorized operator may explicitly start or stop a short,
  request-bound exact-name search, explicitly start a visible session that rotates a bounded set
  of selected exact names, or start a five-minute hostile-area search for one selected map.
- **Only what the player already sees, at no more detail.** The Wanted list and its bounties, the
  public rankings, the player's own frame and title, and his own Olympus guild, rank and role.
- **One permission per addon.** Your addon calls `OlympusAPI.Register`, the player answers **Yes**
  or **No** for it on Olympus's privacy page, and no data comes back or search starts before a Yes.
  The line describes both the reads and, when available to that player's signed role, the bounded
  player-sighting requests.
- **One shared client-owned page.** A registered handle may claim the one client-owned slot in
  Olympus's tab rail. Olympus owns the window shell; your addon owns that page's frames and
  callbacks. Hosting the page grants no data access. It works while the answer is pending or refused.
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

An authorized guild-tools UI can feature-detect a short, consented last-seen search. It must render
the returned `kind` honestly: a native map or converted world target point for `exact-unit` or
`exact-group`, and the
observer's encounter point for `nearby`. None of them is continuous tracking:

```lua
if OlympusAPI.Has("network.sightings") then
	api:On("SIGHTING_CHANGED", function(_, search)
		-- Refresh your own search UI. search.sightings are session-only copies.
	end)

	-- Call from the player's explicit Start action, or from a visible bounded session
	-- the player explicitly started, with an exact Name-Realm.
	local search, reason = api:StartPlayerSearch("Example-Realm")

	-- A separate explicit action can start one five-minute hostile-area search for a
	-- selected zone or micro-map. It is a last-seen session, not a live scan.
	local area, areaReason = api:StartAreaSearch(84)
end
```

If your addon has a page of its own, register it through the same handle. This is independent of
the player's data answer:

```lua
if OlympusAPI.Has("ui.surface") then
	local ok, reason = api:RegisterSurface({
		label = "Map tools",
		icon = "Interface\\Icons\\INV_Misc_Map_01",
		build = function(parent, context)
			-- Make this page's frames as children of parent.
			-- context is { style = "hd" or "old", apiVersion = 1 }.
		end,
		refresh = function(parent, context)
			-- Optional: update the already-built page while it is selected.
		end,
	})
end
```

`OlympusAPI` is `nil` when Olympus is not installed, is older than 1.2.4, or was just updated to
1.2.4 and the game has not restarted since: a file an update adds is loaded only when the game
starts, not on a `/reload`. Always check for it.

## Permission

`OlympusAPI.Register("MyAddon")` adds a line for your addon to Olympus's privacy page (the page
`/oly privacy` opens). The line shows your TOC's `## Title` (colour and texture codes removed) and
says, in Olympus's own words, what a Yes lets your addon read and, for an authorized operator,
which exact-name request, visible name-rotation session or five-minute hostile-area search it may
start. The page opens by itself once for a new line, outside combat and instances,
while the player is in an Olympus guild; the player can
answer there at any time, and change the answer whenever he likes.

- `"pending"`: never answered. Your calls return nothing.
- `"granted"`: the player said Yes. Your calls return data.
- `"refused"`: the player said No. Your calls return nothing.

The page's **Authorize all** button deliberately answers every visible pending line, including an
addon's; **Keep current choices** closes without granting it. Each addon also has its own Yes and
No. The answer is kept for the player's account and stays across sessions. When a later permission
contract gives more, every addon's line is asked again. This answer gates the data methods, their
events and starting an exact-name search, bounded rotation or hostile-area search. Cancelling does
not require a read grant because it can only reduce disclosure; changing the answer to No first
cancels and forgets every search owned by that handle. A registered UI surface works while the
answer is pending or refused and receives no data from Olympus by doing so.

Participating observers have a separate Olympus-owned, explicit setting named **Guild tools:
player sightings**. It defaults off until the player chooses its own Yes or the privacy page's
deliberate **Authorize all** action. A requester cannot turn it on for anyone. While both this
permission and location sharing stay on, the client can keep at most
64 exact Name-Realm observations, captured only when the game directly presents that player through
a target, nameplate or mouseover, in memory for up to 15 minutes. A current or later authorized
request can receive that recent last-seen record. It is never written to saved variables and is
cleared when this permission, location sharing or network participation is turned off. Turning either
permission off also cancels queued reports and withdraws live results. An observer's answer still
goes only to the verified requester through Olympus. An explicitly started hostile-area search
broadcasts its selected map ID for five minutes. Each participating client may return at
most six recent or new hostile-player observations actually exposed by target, nameplate or
mouseover on that map, and the requester keeps at most 48 rows. The area copy always omits the
observer's name and guild.

## Reference

### `OlympusAPI.VERSION`

A number: `1` for this contract. A change that breaks this contract raises it. New fields may be
added to the tables below without raising it: ignore the fields you do not know.

### `OlympusAPI.SURFACE_LIMIT`

The number of client-owned pages the shared tab rail can host in one session: `1`. This is
separate from the 16 addons that may register data handles.

### `OlympusAPI.Has(feature)`

`true` when this build gives that feature, `false` otherwise:

| Feature | What |
|---|---|
| `"wanted"` | `handle:GetWanted()` |
| `"rankings"` | `handle:GetRankings()` |
| `"rankings.slayers"`, `"rankings.donors"`, `"rankings.church"`, `"rankings.games"` | that kind of ranking (a build without the games has no `"rankings.games"`) |
| `"profile"` | `handle:GetProfile()` |
| `"network.sightings"` | request-bound exact-name and hostile-area searches through `StartPlayerSearch`, `StartAreaSearch`, their cancel/get methods, and explicit host-owned area map pins |
| `"ui.guild-tools"` | `handle:OpenGuildTools([section[, target]])`, which opens an authorized section of Olympus's own Watch workspace without returning its records |
| `"callbacks"`, and each event's name | `handle:On(...)` |
| `"ui.surface"` | one page through `handle:RegisterSurface(...)` and its lifecycle methods |

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

### `handle:StartPlayerSearch(name)`

Starts one short request-bound sighting search and returns its initial session, or `nil` and a
reason. This is available only when `OlympusAPI.Has("network.sightings")`, after that addon's
permission is granted by its own Yes or **Authorize all**,
to a locally verified signed role allowed to operate guild tools. `name` must be one exact
`Name-Realm`; Olympus does not run `/who`, inspect, target, invite, move, attack or otherwise act on
that player. Call it only from an explicit Start action or while a visible, user-started session is
rotating names the user selected. A session must be off by default, remain visibly stoppable, stop
on `/reload`, and cancel its current request when stopped. It must not start more than three searches
per minute; cancel before rotating so it does not fill the three-active-search bound.

The request is broadcast to the Olympus network. It contains the target name and an opaque request
id; expiry is enforced locally by each client and is not sent as a wire field. A member can answer
only if they independently opted into **Guild tools: player sightings** and share their own
location. The answer comes from either a current direct target/nameplate/mouseover observation or a
matching recent observation captured that way and kept only in the bounded memory cache described
above. The private answer goes only to the verified issuer of that request. A live answer rechecks
the same visible unit token, canonical name, GUID and coordinate when it leaves. A cached answer
rechecks the immutable record's age and fields plus the observer's current consent, location-sharing
and network eligibility; it never pretends the vanished unit was revalidated live.

```lua
{
	id = "opaque request id",
	target = "Example-Realm",
	status = "searching", -- later complete; callbacks may also report cancelled or ended
	createdAt = 1792000000,
	expiresAt = 1792000600,
	sightings = {
		{
			target = "Example-Realm",
			observer = "Scout-Realm",
			observerGuild = "Olympus Example",
			seenAt = 1792000123,
			receivedAt = 1792000125, -- when this requester accepted the private answer
			expiresAt = 1792001023, -- result lifetime; do not alert or share at/after this time
			mapID = 84,
			x = 520, y = 375, -- 0..1000, rounded to 0.1% of the map
			layer = 123,
			kind = "exact-group", -- or "exact-unit" / "nearby"
			accuracyYards = 0, -- optional; 0 marks a native unit point, not an estimated radius
		},
	},
	observers = 1,
	confirmed = false, -- true after two independently verified observers report it
}
```

The exact optional fields may grow compatibly. `exact-unit` means WoW returned a map point directly,
or a world position that the bundled supported map library could place on the observer's current
map, for the visible target/mouseover/nameplate token. `exact-group` means the visible identity
matched a real party/raid token by canonical name and GUID (and `UnitIsUnit` where available), and
WoW returned that group token's map point or convertible world position. Conversion rejects another
instance and out-of-map coordinates. Both carry `accuracyYards = 0`; this describes a native point rather
than an estimated radius, not a guarantee that the player has stayed there. `nearby` is the
observer's encounter point and deliberately omits `accuracyYards`, because the game exposes no
honest yard radius for that fallback. Sessions and results are bounded, memory-only and expire;
the observation cache is also memory-only, holds at most 64 names for at most 15 minutes and is
cleared on consent, location-sharing or network opt-out. Consumers must not turn last-seen results
into a permanent movement history. `receivedAt` and `expiresAt` are sanitized local timestamps from
the requester's result. Consumers must stop alerts and sharing at or after `expiresAt`; an absent or
invalid expiry must fail closed rather than make a result permanent.

The consumer may maintain a bounded set of exact-name searches only while its visible,
user-started tool session remains on. It must cancel a request before rotating it out, deduplicate
repeated results, stop alerts when a result expires and stop every request when the session ends,
the UI reloads or permission is revoked. An API Yes alone does not start a search or session.

### `handle:CancelPlayerSearch(id)`

Stops a request that this same handle started. It broadcasts the cancellation, cancels queued
answers and withdraws its live results. Returns `true`, or `false` and `"unknown"`, `"unavailable"`
or a transport/state reason. The call itself needs no read grant, but after a No has already
cancelled and forgotten the request, a later call for that id returns `"unknown"`.

### `handle:GetPlayerSearch(id)` and `handle:GetPlayerSearches()`

Return a fresh copy of one request owned by this handle, or every live request it owns, after the
same permission and guild checks as the other reads. A handle cannot read or cancel a request
started by another addon. `GetPlayerSearch` returns `nil, "unknown"` for an id it does not own.

### `handle:StartAreaSearch(mapID)`

Starts one bounded hostile-area last-seen session and returns its initial snapshot, or `nil` and a
reason. `mapID` must be the explicit positive UI map ID of a zone or micro-map; it is not a player
name, an anchor name or an instruction to guess the current map. Call this only from a visible
Start action by the player. The selected map ID is broadcast to the Olympus network, and the
session ends after five minutes, on cancellation, on permission or network opt-out, or on UI
reload.

An observer participates only after the separate **Guild tools: player sightings** permission is
granted by its own Yes or **Authorize all**, and while sharing location. Its client can answer only
for a hostile player that WoW actually exposed as a
current target, mouseover or nameplate, or for a recent observation captured through one of those
tokens while both permissions remained on. This does not enumerate a zone and does not locate a
player that no participating client saw. Each observer contributes at most six distinct rows;
pending plus sent rows count together. The requester aggregates at most 48 target rows. The same
15-minute, 64-name, memory-only observation cache and exact/native-versus-nearby semantics described
for exact-name searches apply.

The returned area shape deliberately omits observer identity and guild:

```lua
{
	id = "opaque request id",
	mode = "area",
	scope = "hostile",
	mapID = 84,
	status = "searching",
	createdAt = 1792000000,
	expiresAt = 1792000300,
	sightings = {
		{
			target = "Example-Realm",
			seenAt = 1792000123,
			receivedAt = 1792000125, -- optional
			expiresAt = 1792001023,
			mapID = 84,
			x = 520, y = 375,
			layer = 123,
			kind = "nearby", -- or "exact-unit" / "exact-group"
			-- accuracyYards = 0 only for a native exact point
		},
	},
}
```

`nearby` remains the observing member's encounter position, not the target's exact position and
not a claimed radius. The row does not contain `observer`, `observerGuild`, a GUID or another
internal field. Consumers must present this as recent last-seen evidence and remove expired rows.

### `handle:CancelAreaSearch(id)`

Stops an area session that this same handle started, broadcasts its map-bound cancellation, forgets
its rows and removes any host-owned pins for that handle. Returns `true`, or `false` and
`"unknown"`, `"unavailable"` or a transport/state reason. Like exact cancellation, it needs no
read grant because it can only reduce disclosure.

### `handle:GetAreaSearch(id)` and `handle:GetAreaSearches()`

Return a fresh sanitized copy of one owned area session, or every live area session this handle
owns, after the same permission and guild checks as the other reads. They never return another
addon's session. `GetAreaSearch` returns `nil, "unknown"` for a foreign, stale or wrong-mode id.

### `handle:ShowAreaSearchOnMap(id)`

On an explicit player action, shows the non-expired sanitized rows of this handle's live area
session as host-owned world-map pins and focuses that selected map. It uses Olympus's bundled map
compatibility path and native game artwork; it creates no minimap pin and exposes no observer
metadata. Once shown, the pins refresh when that session changes even when the addon did not
subscribe to `SIGHTING_CHANGED`. They are removed on cancellation, expiry/completion, permission
revocation or UI reload. If the bundled compatibility check reports that world-map icon injection
is unavailable, including on a client or gamepad UI that disables that path, the call returns
`false, "unsupported"`; the sanitized area rows remain readable so the consumer can use a list or
another non-map fallback instead of claiming pins were shown. Otherwise it returns `true`, or
`false` and `"unknown"`, `"empty"`, `"ended"`, `"unavailable"` or `"failed"`.

### `handle:ClearAreaSearchMap([id])`

Removes this handle's host-owned area pins. With `id`, it clears only when that exact owned map view
is active; without `id`, it idempotently clears this handle's current view. It cannot clear another
addon's pins. Returns `true`, or `false, "unknown"` for a supplied id that is not the active view.

### `handle:OpenGuildTools([section[, target]])`

Opens Olympus's own Watch workspace. `section` is optional (`"desk"` by default) and may be
`"desk"`, `"reports"`, `"cases"`, `"chat"`, `"justice"` or `"profile"`. `"profile"` requires
an explicit character name in `target`; a full `Name-Realm` avoids ambiguity. Olympus calls
`Watch.OpenMember(target)` so the Watch module still resolves the name and applies its own access
control. The caller receives only success or failure: records, retained public messages and action
history remain inside the host-owned Watch page.

Olympus confirms the resulting page before selecting its own Watch tab. If name resolution, access,
page selection or tab navigation fails, it restores the Watch page that was open before the call.
The route works independently of the addon's data-sharing answer because it grants no data and no
write primitive. Returns `true`, or `false` and `"section"`, `"target"`, `"name"`, `"guild"`,
`"access"`, `"unavailable"`, `"failed"`, or a host-navigation reason.

### `handle:RegisterSurface(spec)`

Registers this handle's one client-owned page in the Olympus tab rail. The shared rail has one
client-owned slot per session (`OlympusAPI.SURFACE_LIMIT` is `1`); data handles remain available
when that slot is already occupied. Olympus places the page immediately before the built-in
Workshop tab. The caller cannot choose an internal key, replace an Olympus page or reorder the
normal pages. Registration does not select or build the page by itself.

`spec` is a table with these fields:

| Field | Required | Contract |
|---|---|---|
| `label` | yes | non-empty string, at most 96 bytes; used for the tab tooltip or bottom-tab text |
| `icon` | yes | non-empty texture path or positive file ID |
| `build(parent, context)` | yes | creates the page as children of `parent`; runs once for each Olympus window style |
| `portrait` | no | non-empty texture path or positive file ID shown in the shell while this page is selected |
| `visible()` | no | return `false` to hide the page; may run repeatedly and should be idempotent |
| `refresh(parent, context)` | no | updates the built page while selected; may run repeatedly and should be idempotent |
| `help(parent, context)` | no | handles the yellow title-bar help button while selected; without it Olympus opens its normal help |
| `availableWhenLocked` | no | boolean, `false` by default; `true` also offers the page beside the non-member Join screen |

`parent` fills the content area below the title bar. Olympus retains the outer frame, close and
help buttons, tab rails and portrait frame. Treat `context` as read-only. It has exactly the form
`{ style = "old" or "hd", apiVersion = 1 }` and contains no addon name, consent key or internal
owner key. The optional portrait applies only while this page is selected. Olympus's portrait
returns on its own pages.

The surface is independent of the data permission: registering, opening and refreshing it work
while `Status()` is `"pending"` or `"refused"`, and do not change that status or grant a data read.
The page's code still belongs to the calling addon. Olympus contains errors from its `visible`,
`build`, `refresh` and `help` callbacks so one page cannot stop the window or another page.

Returns `true`, or `false` and one of these reasons:

| Reason | Why |
|---|---|
| `"registered"` | this handle already registered its one surface |
| `"surface-full"` | the shared client-owned surface slot is already occupied; the handle remains usable for data and may retry later in another session |
| `"invalid-spec"` | `spec` is not a table |
| `"invalid-label"`, `"invalid-icon"`, `"invalid-portrait"` | that field has the wrong type or range |
| `"invalid-build"`, `"invalid-refresh"`, `"invalid-visible"`, `"invalid-help"` | that callback is missing when required or is not a function |
| `"invalid-locked-availability"` | `availableWhenLocked` is present and is not a boolean |
| `"unavailable"` | this Olympus build cannot host API surfaces |
| `"failed"` | the host rejected the call before it could return a more specific reason |

### `handle:OpenSurface()` and `handle:ToggleSurface()`

`OpenSurface` opens the Olympus window on this handle's registered page. `ToggleSurface` opens it,
or hides the Olympus window when that page is already selected. They return `true`, or `false` and
`"unregistered"`, `"unavailable"`, `"hidden"`, `"build-failed"` or `"failed"`. A `visible`
callback that returns false or raises an error makes the page `"hidden"`; a `build` callback that
raises an error makes it `"build-failed"` for that window style.

### `handle:RefreshSurface()`

Asks Olympus to re-evaluate this handle's registered page. If the page is selected, Olympus calls
its optional `refresh`. It returns `true`, or `false` and `"unregistered"`, `"unavailable"` or
`"failed"`. A refresh callback error is contained; the accepted refresh request still returns
`true` so a broken callback cannot escape through the host.

### `handle:IsSurfaceOpen()`

Returns `true` only when this handle's page is selected in the visible Olympus window, `false` when
it is not, or `false` and `"unregistered"`, `"unavailable"` or `"failed"` when the question could
not be answered.

### `handle:GetWanted()`

The Wanted list as the Wanted tab lists it, its entries in its order: each Horde player with a
bounty open or a kill of ours (one a member killed who killed none of ours, 0 points and 0 kills, is
not on it):

```lua
{
	{ place = 1, name = "Grashk Bloodfen-Emberfall", guid = "Player-4002-00C0FFEE", bounty = 42, kills = 3, cycle = 2 },
	...
}
```

`bounty` is the current bounty in points, `kills` the Olympus members he killed, counted as the
bounty counts them (the same member again within 10 minutes is one), `cycle` the bounty's cycle; `name` can be `nil` when the game has not told a name for that GUID. Never the
victims, the claims, the sightings, who added or took off an entry, nor any time.

### `handle:GetRankings([kind])`

Every public ranking (no argument), or one kind: `"slayers"`, `"donors"`, `"church"` or `"games"`.
A kind this build lacks, or one with nothing public now (the Church's ranking closed, the
Treasury's ranking not shown to the army), is `nil`.

```lua
{
	slayers = {
		month = { { place = 1, name = "Torvin Hale-Emberfall", points = 70, claims = 1 }, ... }, -- this month, at most 50
		all = { ... },     -- all time, at most 50
		signed = { ... },  -- the signed top three this client holds, when it holds one (name nil when unknown)
	},
	donors = { all = { "Name-Realm", ... } }, -- the all-time top three (see below)
	church = { missionaries = { "Name-Realm", ... }, apostles = { "Name-Realm", ... } }, -- its public top three
	games = { -- only the games the King made public
		arena = { { place = 1, name = "Name-Realm", rating = 1520, wins = 9, losses = 2 }, ... },
		bones = { { place = 1, name = "Name-Realm", games = 12, won = 8 }, ... },
	},
}
```

The Slayers boards are this client's own (what it observed), as the Wanted tab says. A game the
King keeps to the staff is not there, whoever the player is. Lottery results are private history
and never appear in rankings, including when an older client published a Lottery ranking word.

`donors` is there only while the King shows every member the Treasury's ranking (it is off until he
does), whoever the player is: the King's and the Treasury keepers' own view never counts. `all` is
the all-time top three, which head that ranking. `donors.month`, the month's top three, comes only
in a build whose honour frames show them (the koi; 1.2.4 shows it): still check for it.

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
| `SIGHTING_CHANGED` | `fn(event, search)`: the current full owned exact-name or area search for non-terminal changes; cancellation or disappearance may be the terminal marker `{ id = id, status = "cancelled" or "ended" }` | after a start method has returned, its queued send completes, a result arrives or is withdrawn, or the search is cancelled or disappears |
| `PERMISSION_CHANGED` | `fn(event, status)`: `"granted"` or `"refused"` | the player answered your line |

- The data events come only while the player's answer is Yes (`WANTED_CHANGED` and
  `RANKINGS_CHANGED` only in an Olympus guild), and only when the data you would get differs from
  what you were last told: you may register before the Yes. `On` and the Yes take the data as it is
  then as told, so no event comes for it: read it yourself once (`Status()` is `"granted"`, or
  `PERMISSION_CHANGED` with `"granted"`), as the examples below do.
- A burst of changes is told once, about 2 seconds after it, never in combat (it waits for the
  combat to end).
- `SIGHTING_CHANGED` is scoped to opaque ids that this same handle started. Another registered
  addon never receives or reads them. Each start method itself returns the initial snapshot;
  initialize from that return rather than depending on the later queued-send transition to produce
  a callback. Treat a terminal marker as an instruction to discard every previously copied result
  for that id.
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
| `"unavailable"` | this build does not provide the optional player-sighting capability |
| `"member"`, `"authority"` | the player is not a current member or their signed Olympus role cannot start that guild-tools request |
| `"netoff"`, `"instance"` | network access is disabled for this player, or the player is currently in an instance |
| `"transport"`, `"channel"` | the guarded addon transport or the Olympus channel is not ready |
| `"target"` | the exact `Name-Realm` is malformed or names the requester |
| `"map"` | an area search was given a secret, unknown, non-zone or non-micro map ID |
| `"capacity"`, `"queue"` | the bounded sighting-session or send queue cannot accept the request |
| `"unknown"` | that search id was not started by this handle |
| `"unsupported"`, `"empty"`, `"ended"`, `"failed"` | an explicit area map view is unsupported, has no current rows, has ended, or its guarded draw failed |

## What it never gives

The census of the guilds, other players' private data, the Wanted page's victims or stored
sightings, a movement history, the GUID of an Olympus member merely because they are a member, the
staff's views, or any secret: no key, no sealed channel name, no signature, no private list. The
optional request-bound capability returns only a current or at-most-15-minute recent native
last-seen result: a native observed or matching group-unit point where WoW exposes one, otherwise
the consenting observer's encounter point, to the verified requester, then expires it. A hostile-
area session is one selected map for five minutes, at most six rows per observer and 48 at the
requester; its public rows omit the observer and guild.
Each row is built field by field from the page's own data, so what Olympus adds to its own tables
later never reaches your addon unless this contract adds it.

## What it is not

Every addon runs in the same Lua environment, so this is a courtesy boundary, not a lock: an
addon could read Olympus's saved variables directly. The API is the supported and consented way
in: it asks the player, gives your addon a stable contract, and keeps Olympus from handing out
anything on its own. Please use it, and only for what the player said Yes to.

Olympus's line on the privacy page tells the player exactly what may be read and that an authorized
operator's exact search sends a target name, or an area search sends one selected map ID, and can
receive private, expiring observer reports. It also explains the bounded memory-only
recent-observation cache and that a consumer may maintain a bounded rotation only while its visible,
user-started tool session remains on. Everything else remains read-only. Keep that trust: never
start a search or session without the player's action, broaden its audience, keep it running after
the visible session ends, present a nearby encounter point as exact, or persist a movement history.

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

Showing the player's own title in your frame. The data events come only when something changes,
so read it once at the start and on the player's Yes too:

```lua
local function ShowTitle(profile)
	MyFrame.title:SetText(profile and profile.member and profile.title or "")
end
api:On("PROFILE_CHANGED", function(_, profile) ShowTitle(profile) end)
api:On("PERMISSION_CHANGED", function(_, status)
	if status == "granted" then ShowTitle(api:GetProfile()) else ShowTitle(nil) end
end)
if api:Status() == "granted" then ShowTitle(api:GetProfile()) end
```
