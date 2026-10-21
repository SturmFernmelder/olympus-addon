# The Olympus API, for addon authors

Olympus 1.2.4 lets other addons read, with the player's permission, what Olympus already shows
that player on its own pages. An addon can also contribute one page to the Olympus window without
copying its shell. This page is the whole contract of version 1 (`OlympusAPI.VERSION`).

- **Read-only data.** The ordinary data functions send no chat line, decree, whisper or addon
  message and change nothing in Olympus. The optional, separately identified network capabilities
  are the exceptions: an authorized operator may explicitly start or stop a short, request-bound
  exact-name search, explicitly start a visible session that rotates a bounded set of names the
  player chose/configured or a list source the control declares, run one five-minute hostile-area
  search at a time under the map/cadence rules below, or open the bounded host-owned
  profile-presentation session described below.
- **Only what the player already sees, at no more detail.** The Wanted list and its bounties, the
  public rankings, the player's own frame and title, his own Olympus guild, rank and role, and the
  leader's presence as the leader lines, the leader's map crown and the Realm tab's layer list show it.
- **One permission per addon.** Your addon calls `OlympusAPI.Register`, the player answers **Yes**
  or **No** for it on Olympus's privacy page, and no data comes back, search starts or presentation
  is enabled before a Yes. The line describes the reads and optional bounded network actions.
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
	-- the player explicitly started. Its control must declare every configured list source.
	local search, reason = api:StartPlayerSearch("Example-Realm")

	-- That visible session may run one five-minute area search at a time on the current
	-- map, then rotate no faster than once a minute to an owned exact-result map
	-- until that result expires, even if its exact-name request was rotated out.
	local area, areaReason = api:StartAreaSearch(84)

	-- Where this build supports it, a later area search (after cancelling this one and
	-- waiting out the rotation interval) may also include not-hostile players outside
	-- Olympus guilds. Label each returned row by its hostile field.
	if OlympusAPI.Has("network.sightings.area-scope") then
		-- api:StartAreaSearch(84, "outsiders")
	end
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
says, in Olympus's own words, what a Yes lets your addon read and, where the signed role permits,
which exact-name request, visible name-rotation session, five-minute hostile-area search or bounded
host-owned profile presentation it may start, and the quiet presence it may turn on (an addon
the Olympus team has not authorized for the reserved features below is asked only about the
ordinary reads). The page opens by itself once for a new line, outside combat and instances,
while the player is in an Olympus guild; the player can
answer there at any time, and change the answer whenever he likes.

- `"pending"`: never answered. Your calls return nothing.
- `"granted"`: the player said Yes. Your calls return data.
- `"refused"`: the player said No. Your calls return nothing.

The page's **Authorize all** button deliberately answers every visible pending line, including an
addon's; **Keep current choices** closes without granting it. Each addon also has its own Yes and
No. The answer is kept for the player's account and stays across sessions. When a later permission
contract gives more, every addon's line is asked again. This answer gates the data methods, their
events and starting an exact-name search, bounded rotation, hostile-area search or profile
presentation, or turning on the quiet presence. Cancelling a search, stopping a profile session,
disabling that handle's own presentation and turning off the quiet presence it turned on do not
require a grant because they can only remove state. Changing the answer to No first cancels and
forgets every search owned by that handle, closes its profile session, disables its effect and ends
the quiet presence it turned on. A later Yes does not resume a stopped exact-name or area session: the player must use
the visible Start action again. A registered UI surface works while the answer is pending or
refused and receives no data from Olympus by doing so.

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
observer's name and guild. A wider area search (scope `"outsiders"`) may also receive players the
observer's game shows as not hostile whose guild, as that client reads it, is not an Olympus guild,
or who have no guild; never the observer, the observer's group or an Olympus guild's player. Each
such row is labelled `hostile = false` and counts toward the same limits.

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
| `"leader"` | `handle:GetLeaderPresence()` and `LEADER_CHANGED` |
| `"network.sightings"` | request-bound exact-name and hostile-area searches through `StartPlayerSearch`, `StartAreaSearch`, their cancel/get methods, and explicit host-owned area map pins |
| `"network.sightings.area-scope"` | `handle:StartAreaSearch(mapID, scope)` accepts `"outsiders"` as well as `"hostile"` |
| `"network.profile-effects"` | one bounded host-owned profile-presentation session through `StartProfileSession`, `StopProfileSession`, `SetProfileEffect` and `GetProfileSession` |
| `"presence.quiet"` | the session's quiet presence through `SetQuietPresence`, `GetQuietPresence` and `QUIET_PRESENCE_CHANGED` |
| `"ui.guild-tools"` | `handle:OpenGuildTools([section[, target]])`, which opens an authorized section of Olympus's own Watch workspace without returning its records |
| `"callbacks"`, and each event's name | `handle:On(...)` |
| `"ui.surface"` | one page through `handle:RegisterSurface(...)` and its lifecycle methods |

**Reserved features.** `"leader"`, `"network.sightings"`, `"network.sightings.area-scope"`,
`"network.profile-effects"` and `"presence.quiet"` are reserved for
addons the Olympus team has authorized. `Has` still says whether this build has them. For any other
addon, their methods return `nil` and `"unauthorized"` (`false` and `"unauthorized"` for the cancel and map methods,
`SetQuietPresence`, `StartProfileSession`, `StopProfileSession` and `SetProfileEffect`), `On`
returns `false` for `LEADER_CHANGED`, `SIGHTING_CHANGED`, `PROFILE_EFFECT_SESSION_CHANGED` and
`QUIET_PRESENCE_CHANGED`, and its line on the privacy page lists only what it can read: it is asked
about neither the profile presentation nor the quiet presence.

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
reason. This is a reserved feature, for an authorized addon only. It is available when
`OlympusAPI.Has("network.sightings")`, after that addon's
permission is granted by its own Yes or **Authorize all**,
to a locally verified signed role allowed to operate guild tools. `name` must be one exact
`Name-Realm`; Olympus does not run `/who`, inspect, target, invite, move, attack or otherwise act on
that player. Call it only from an explicit Start action or while a visible, user-started session is
rotating names the player selected or configured, or names from a list source that the same visible
control declared before the click. Do not append a silent list source. A session must be off by
default, remain visibly stoppable, stop on `/reload`, and cancel its current request when stopped.
It must not start more than three searches per minute; cancel before rotating so it does not fill
the three-active-search bound.

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

### `handle:StartAreaSearch(mapID[, scope])`

Starts one bounded area last-seen session and returns its initial snapshot, or `nil` and a
reason. `handle:StartAreaSearch(mapID)` is the original hostile-area search, the same as scope
`"hostile"`: players the observer's game reports as attackable or enemy. Scope `"outsiders"`, when
`OlympusAPI.Has("network.sightings.area-scope")`, also covers players the observer's game reports
as not hostile when the guild that client reads for them (`GetGuildInfo` for the observed player) is not
an Olympus guild, or they have none. It never covers the observer, a member of the observer's party
or raid, or a player in an Olympus guild. Any other scope returns `nil, "scope"`. `mapID` must be the explicit positive UI map ID of a zone or micro-map; it is not a player
name, an anchor name or an instruction to guess the current map. The host accepts only the
player's current map at the time of the call, or a map from an unexpired `exact-unit` or
`exact-group` result obtained by an exact-name search that this same handle owned. Cancelling or
rotating that exact-name request retains only this target/kind/map proof until the result's own
`expiresAt`; it does not extend the result or expose it as a live search. A `nearby` encounter point,
an expired result or another handle's result cannot authorize a map. Permission loss and `/reload` discard every retained proof.

Call this only while a visible session the player explicitly started remains on. One handle may
have only one live area search, and successful area starts must be at least 60 seconds apart. Cancel
the current area before rotating. The visible UI must show the selected map (ID or an honest map
label) and its position in the rotation, keep Stop/Off accessible, and never open the world map automatically.
Only a separate explicit `ShowAreaSearchOnMap` action may do that. Turning the
visible session off, losing permission or `/reload` ends it; neither a later permission grant nor a
saved preference may resume it without a new Start action. Passive configured names and declared
list sources may be remembered, but running state may not. The selected map ID is broadcast to the
Olympus network, and each area request ends after five minutes or on cancellation/network opt-out.

An observer participates only after the separate **Guild tools: player sightings** permission is
granted by its own Yes or **Authorize all**, and while sharing location. Its client can answer only
for a hostile player that WoW actually exposed as a
current target, mouseover or nameplate, or for a recent observation captured through one of those
tokens while both permissions remained on. This does not enumerate a zone and does not locate a
player that no participating client saw. Each observer contributes at most six distinct rows;
pending plus sent rows count together. The requester aggregates at most 48 target rows. The same
15-minute, 64-name, memory-only observation cache and exact/native-versus-nearby semantics described
for exact-name searches apply.

The wider scope travels as a second, separate channel message after the area query. An observer on a
build before it ignores that message and keeps answering only hostile rows; a query without it stays
hostile on every build. A not-hostile row is accepted only for an `"outsiders"` request. Each
observer's six-row cap and the requester's 48-row cap are shared by both kinds of row.

The returned area shape deliberately omits observer identity and guild:

```lua
{
	id = "opaque request id",
	mode = "area",
	scope = "hostile", -- or "outsiders", as requested
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
			hostile = true, -- false only in an "outsiders" search: label it as not hostile
		},
	},
}
```

The requester's own client is an observer of its own area search too. A player that the
requester's own game exposes as a target, mouseover or nameplate (at the start and while the search
lives) enters the search as a row with `own = true`, under the same map, scope and 48-target rules.
Nothing about it is sent, and it needs neither the sharing permission nor location sharing. One row
is kept per target: the newest of an own row and a network row wins, and a network row never says
which member sent it.

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
owns, after the same permission and guild checks as the other reads. Each copy reports the
request's `scope`. They never return another
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

### `handle:SetSightingPins(pins)` and `handle:ClearSightingPins()`

Keep recent rows in sight while a visible session the player explicitly started remains on.
`pins` is a list of at most 96 rows, each a copy of a row this handle read from its own searches:

```lua
{
	target = "Example-Realm",
	category = "hostile", -- or "marked" / "outsider": the dot's fixed colour (red, orange, blue)
	mapID = 84, x = 520, y = 375,
	seenAt = 1792000123, expiresAt = 1792001023,
	kind = "nearby", accuracyYards = 30, -- as the row gave them
	own = true, -- optional: the row's own flag
	marks = { "Watch" }, -- optional: at most three short labels of the consumer's lists
	label = "Horde", -- optional: the consumer's own short name for the category (32 bytes)
}
```

Olympus draws host-owned dots on the world map (mouse and keyboard only; the gamepad UI's map gets
none) and on the minimap, and writes the tooltip itself from those fields: the name, the category (or its `label`),
the marks or "Not marked", how long ago (Olympus's clock against `seenAt`) and the precision (an exact
point, nearby within about N yards, or the observer's encounter point), and "Seen by you" for an own
row. A dot fades as it ages and goes by itself soon after its row's `expiresAt` (at most 15 minutes
after `seenAt`; Olympus looks every 15 seconds, with no call needed). A row past its `expiresAt`, with an unknown category, an invalid
point or a map the game cannot place, is neither drawn nor counted. It never opens the map. Each
call replaces this handle's whole set (a row at the same point as before keeps its dot) and returns
`true` and the number drawn, or `false` and `"invalid"`, `"unavailable"`, `"barred"` (while Olympus
hides locations from this player) or a permission reason. `ClearSightingPins` removes the set;
permission loss, the player no longer being a member, Olympus hiding locations from him and
`/reload` remove it too.

### Profile-presentation session

These methods exist only when `OlympusAPI.Has("network.profile-effects")` is true. This is a
reserved feature, for an authorized addon only (see **Reserved features**). Olympus owns the
art, layout, transport, lifetime and target-frame rendering. The public contract accepts only a
host-defined style identifier and the exact pre-approved caption for that style. It accepts no
texture or atlas path, colour, coordinate, arbitrary message or target player. A presentation is
self-only: each admitted member can announce it only for their own character while a session
opened by a current signed issuer or the addon's author remains live.

`handle:StartProfileSession(style)` asks the host to open the short shared session and returns
`true`, or `false` and a reason. Opening is restricted to a current signed issuer or the addon's author. The host renews
the session every 10 seconds while eligible; a missed lease expires after about 32 seconds.
Only one API owner can hold the local outgoing session at a time.

`handle:StopProfileSession()` closes the session owned by this handle. It remains available after
permission is refused because it can only remove that handle's state. It returns `true`, or `false`
and a reason such as `"owner"` when another handle owns the active session.

`handle:SetProfileEffect(style, enabled[, caption])` enables or disables this handle's self-only
presentation. Enabling requires a live compatible session and the style's exact pre-approved
caption; disabling ignores `caption` and remains available after permission is refused. It returns
`true`, or `false` and a reason. It never assigns an effect to another player.

`handle:GetProfileSession()` returns a fresh sanitized copy of the current session:

```lua
{ style = "shadow", expiresIn = 31.5 }
```

It never returns the issuer, grant identifier, caption, transport epoch or another internal field.
With no live session it returns `nil, "none"`; the normal permission, guild and rate checks still
apply. `expiresIn` is approximate and counts down, so do not poll it. Subscribe to
`PROFILE_EFFECT_SESSION_CHANGED`; its payload is the same sanitized table when a session opens and
`nil` when it closes or expires. Permission revocation closes and disables this handle's state
before Olympus saves the No. All session and presentation state is memory-only and ends on UI
reload or logout.

### Quiet presence

These methods exist only when `OlympusAPI.Has("presence.quiet")` is true. This is a reserved
feature, for an authorized addon only (see **Reserved features**).

`handle:SetQuietPresence(on)` turns the player's own quiet presence on (`true`) or off (`false`) for
the current session. It has no target. Only the King, a High Councillor (each while a current signed
issuer) or the addon's author may turn it on: anyone else gets `false, "authority"`, and outside an
Olympus guild the call returns `false, "guild"`. It needs the player's Yes (`"pending"`,
`"refused"`) and counts against the rate limit (`"busy"`). It returns `true`, or `false` and a
reason. The handle that turned it on may always turn it off (no Yes or role needed for that);
another handle gets `false, "owner"`. A No for that handle ends it.

While it is on, this client stops sending, on its own, the words that announce the player as
online or place him: no hello, no census report (it is never the guild's reporter, so it answers no
census request), no layer announcement, guildmate map dot or layer-hop offer or answer, no answer
to a player-sighting or King's-layer request, no roll-call, version-check, council-help or crafter
answer, no author, Church, Olympus Link, council-help, crafter listing, Wanted reviewer, arena
auditor or arbiter presence, no Wanted sighting, no treasury "taking donations" notice, no repeated
treasury ask (a session's first still goes), no profile-presentation heartbeat and, for the King,
no crown position or layer, no court, no tabard collector lease and no timed repeat of his Hands,
untabarded and agenda lists, writs or minimap-arrow word. No word says it went quiet and no earlier
word is withdrawn, even when the player hides or stops something himself meanwhile: other clients
age it out as after a logout (the crown within 45 seconds, a layer within 21 minutes). Reads keep
working, this client's own requests included. What the player does himself still goes: the
Olympus chat lines he types, a muster call, decree or writ he posts, a list he changes. Records and
lists this client relays for others still go too, and any of them can show other clients that it
is online.

Olympus cannot change what guildmates' clients report from the game's guild roster: the census
still shows a guild leader or officer online (the King's line on other clients, and
`GetLeaderPresence()` on theirs, still say the King is online), and the zone the roster gives may
appear in that census for up to 12 minutes after this client's last hello. The guild roster, `/who`
and chat still show the player. A line on top of Olympus's Census and Realm says it is on.

It is never saved: a `/reload` or a logout ends it. After a login or `/reload`, Olympus says hello
about 6 seconds in (the King's crown, while he shares it, from about 5), and its other presence
words follow within the first two minutes. Call
`SetQuietPresence(true)` as early as you can, and while it returns `false, "guild"` (Olympus does
not know the player's guild yet) try again on `PLAYER_GUILD_UPDATE` or a short timer: whatever left
before it succeeds counts the player online on other clients for up to 12 minutes.

While it is on, `StartProfileSession` and `SetProfileEffect` return `false, "quiet"` for anything
new, and a session or presentation already live on this client stops renewing on the others: they
drop it after about 32 seconds, as after a logout, and it renews again once quiet presence is off.

`handle:GetQuietPresence()` returns a fresh copy of its state, with the usual permission and rate
checks:

```lua
{ on = true, since = 1792000000 } -- since: when it was turned on, as time() gives it
{ on = false }
```

It never says which handle turned it on. Subscribe to `QUIET_PRESENCE_CHANGED`: its payload is the
same table, after a change by any handle.

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

Outside an Olympus guild, or before the player accepted the Olympus Accord (Olympus's terms of
use, 1.2.5.1), it is `{ member = false }`, and `GetWanted` and `GetRankings` return
`nil, "guild"`.

### `handle:GetLeaderPresence()`

The federation leader's presence (the King on Olympus's pages), built field by field from what this
player's own Olympus pages show: the leader lines on the Census and Realm tabs, the leader's crown on
the map, and the Realm tab's layer list. Available when `OlympusAPI.Has("leader")`, to an authorized
addon only (a reserved feature); it needs the same permission, Olympus guild and rate checks as
`GetWanted`.

```lua
{
	name = "Leader", -- the name those lines give
	online = true,
	otherRealm = false,
	realm = nil, -- the realm, only when otherRealm is true (the line names it)
	mapID = 1453, mapName = "Stormwind City", -- the zone the lines name, else the crown's
	position = { mapID = 1453, x = 420, y = 510, seenAt = 1792000123 }, -- the crown, 0..1000
	onYourLayer = false, -- the line that says the player is on the leader's layer
	layer = "Leader's layer", -- the name the Realm tab gives the leader's layer
	layers = { -- only while the player is in that zone, as the Realm tab lists it
		{ name = "Leader's layer", olympus = 12, yours = false, leader = true },
		{ name = "Captain's layer", olympus = 4, yours = true, leader = false },
	},
}
```

Every field is `nil` rather than guessed. With nobody online it is `{ online = false }`; for the
leader himself, `{ name, online = true, isYou = true }`. `position` exists only while the leader
shares the crown and it has not expired (about 45 seconds after the last update). `layers` and
`layer` exist only while the player is in the leader's zone on the same realm; `olympus` is the
Realm tab's "~N with Olympus", a sample of Olympus clients that share their layer, not a population
(the game exposes none). While Olympus hides locations from this player, only `name` and `online`
remain. It never returns another member's name except as a layer name the Realm tab already shows,
nor a population, the census or a movement history.

### `handle:On(event, fn)` and `handle:Off(event[, fn])`

`On` adds a callback and returns `true` (`false` for an unknown event, a non-function, a reserved
event your addon is not authorized for, or past 4 callbacks for that event). `Off` removes that callback, or every one of yours for the event
without `fn`.

| Event | `fn(event, ...)` | When |
|---|---|---|
| `WANTED_CHANGED` | `fn(event, rows)`: what `GetWanted()` returns | the Wanted list changed |
| `RANKINGS_CHANGED` | `fn(event, rankings)`: what `GetRankings()` returns | a public ranking changed |
| `PROFILE_CHANGED` | `fn(event, profile)`: what `GetProfile()` returns | the frame, title, guild, rank or role changed, or the player joined or left an Olympus guild |
| `LEADER_CHANGED` | `fn(event, presence)`: what `GetLeaderPresence()` returns | the leader came online or left, the crown moved, appeared or expired, a layer count or name changed, or the player changed zone or layer |
| `SIGHTING_CHANGED` | `fn(event, search)`: the current full owned exact-name or area search for non-terminal changes; cancellation or disappearance may be the terminal marker `{ id = id, status = "cancelled" or "ended" }` | after a start method has returned, its queued send completes, a result arrives or is withdrawn, or the search is cancelled or disappears |
| `PROFILE_EFFECT_SESSION_CHANGED` | `fn(event, session)`: the sanitized `{ style, expiresIn }` returned by `GetProfileSession()`, or `nil` | a bounded host-owned session opens, closes or expires; heartbeat renewals do not produce callbacks |
| `QUIET_PRESENCE_CHANGED` | `fn(event, state)`: what `GetQuietPresence()` returns | the quiet presence was turned on or off, by any handle |
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
- `PROFILE_EFFECT_SESSION_CHANGED` never includes the issuer, grant id, caption or transport
  state. Read its argument directly; a `nil` argument means there is no live session.
- Each callback gets its own copy, and its call never counts against the rate limit.
- A callback that raises an error is caught: Olympus logs it with your addon's name, and Olympus and
  the other callbacks go on. A callback that fails 3 times is removed.

### Failures

Every data method returns `nil` and a reason when it gives nothing:

| Reason | Why |
|---|---|
| `"pending"`, `"refused"` | no Yes from the player |
| `"guild"` | the player is in no Olympus guild, or has not accepted the Olympus Accord |
| `"busy"` | more than 20 data calls from your addon in 10 seconds: wait, or use the callbacks |
| `"kind"` | `GetRankings` was given an unknown kind |
| `"unauthorized"` | a reserved feature's method, from an addon the Olympus team has not authorized (see `OlympusAPI.Has`) |
| `"unavailable"` | this build does not provide the requested optional capability |
| `"member"`, `"authority"` | the player is not a current member or their signed Olympus role cannot start that guild-tools request or turn on the quiet presence |
| `"netoff"`, `"instance"` | network access is disabled for this player, or the player is currently in an instance |
| `"transport"`, `"channel"` | the guarded addon transport or the Olympus channel is not ready |
| `"target"` | the exact `Name-Realm` is malformed or names the requester |
| `"scope"` | an area search was given a scope other than `"hostile"` or `"outsiders"`, or `"outsiders"` on a build without `"network.sightings.area-scope"` |
| `"map"` | an area search was given a secret, unknown, non-zone/non-micro map, or a map that is neither current nor backed by this handle's fresh exact result |
| `"active"`, `"cooldown"` | this handle already has a live area, or its previous successful area start was less than 60 seconds ago |
| `"capacity"`, `"queue"` | the bounded sighting-session or send queue cannot accept the request |
| `"unknown"` | that search id was not started by this handle |
| `"unsupported"`, `"empty"`, `"ended"`, `"failed"` | an explicit area map view is unsupported, has no current rows, has ended, or its guarded draw failed |
| `"none"` | no bounded profile-presentation session is live |
| `"style"`, `"state"`, `"caption"` | an unknown host style, non-boolean enable state, or caption that is not the exact pre-approved text |
| `"held"`, `"session"`, `"owner"` | the local moderation hold is active, no compatible profile session is live, or another API handle owns the local state |
| `"quiet"` | the quiet presence is on: a new profile session or presentation waits until it is off |

## What it never gives

The census of the guilds, other players' private data, the Wanted page's victims or stored
sightings, a movement history, the GUID of an Olympus member merely because they are a member, the
staff's views, or any secret: no key, no sealed channel name, no signature, no private list. The
optional request-bound capability returns only a current or at-most-15-minute recent native
last-seen result: a native observed or matching group-unit point where WoW exposes one, otherwise
the consenting observer's encounter point, to the verified requester, then expires it. A hostile-
area session is one selected map for five minutes, at most six rows per observer and 48 at the
requester; its public rows omit the observer and guild. Its wider scope adds only not-hostile
players outside Olympus guilds and the observer's group, each labelled. The leader presence gives
only what the leader lines, the crown and the Realm tab's layers show, never a population. Area rotation is one live map per handle,
at least 60 seconds between successful starts, and only the current map or an owned native exact
result map until that result expires. Rotating its exact-name request does not extend or discard
that result; permission loss and `/reload` do discard it.
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
user-started tool session remains on. A visible Start must declare selected/configured names and any
included list source; the session must show its selected area and rotation position and provide
Stop/Off. Everything else remains read-only. Keep that trust: never start a search or session
without the player's action, silently add a list source, auto-resume after permission or reload,
broaden its audience, keep it running after the visible session ends, or present a nearby encounter point as exact.
Never persist a movement history.

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
