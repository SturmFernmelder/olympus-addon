# Olympus 1.2.1

This correction release contains the completed subset below, not the entire longer-term backlog.
Automated checks and live multiplayer checks are separate gates; use
[the beta checklist](BETA-TESTING.md) for the latter. Cross-client acceptance remains ongoing.

## Player-facing changes

- Bones has a collapsible chat beside the table. **Players** is for the two players; **Everyone**
  is for players and spectators when the table permits watching. It reuses the main chat's
  bubbles, name marks, textured Search box, conversation inset, input border and tab style, with
  separate drafts and searches. Collapsing it restores the table's original width, without an
  empty side strip. A red square with a yellow arrow sits just right of **Sit Down**, shifted
  slightly left while chat is available. The native chat background also fills the join between
  chat and table. Innkeeper practice does not pretend to have a multiplayer room.
  Authors and test builds can inspect that layout locally with `/oly arena sim boneschat`, then
  leave by closing the preview or with `/oly arena sim off`. The preview has empty chat tabs
  and sends no invitations or messages; it is not a multiplayer test. Ordinary test-build pages
  no longer fill empty real lists with invented showcase records.
- The Chat gear can hide guild labels beside sender names locally. Guild identity remains in
  tooltips, searches and message evidence; permissions and transport are unchanged.
- The Watch's notices identify **a moderator**, not their name. Authorized staff keep the actor
  in their audit. Retained unresolved appeals can retry when council members come online later;
  a failed queue submission no longer permanently marks an appeal as sent.
- Wanted publication no longer fails the real communication queue's guard validation. Trusted
  peers can relay an unchanged signed Slayers ranking to a client that already independently
  pinned its original issuer. Relay never supplies that initial trust or silently rotates a key.
- Wanted evidence requires verified membership and positive identity for the sender's own kill
  or death. A claimed guild or an unknown GUID is not enough. Evidence still needs human review.
  A name-only manual listing no longer prevents a locally verified fatal own-death recap from
  learning that Horde player's GUID and counting once. A same-name different GUID cannot
  replace a pinned identity. These observations stay local; this is not a shared Horde list.
- The Board offers a public weekly summary of facts this client knows. **Your week, in five
  lines** is a separate personal parchment page in the main window's Realm tab, available to
  every member, not a Throne page. The old automatic personal popup is removed. Unknown
  coverage and receipts are shown honestly; opening either brief does not turn on sharing.
- The King may leave a short message with an audience. The recipient retains it in their local
  Chronicle with its sender; this does not create a jury or another punishment system.
- Invitations through the addon warn about a character blocked from the network, with a reason
  and date. The officer still chooses; native guild invitations are not silently declined.
- Removing a member from the guild is no longer refused with "Interface action failed because of
  an AddOn" because an Olympus question was open. With mouse and keyboard, while one of the game's
  guild windows is open, Olympus asks its questions in its own windows. A question already open
  as a game popup moves there as soon as the guild window (or a member's card) opens, keeping what
  was typed in its box. An officer reported the same failure, now and then, when changing a rank:
  Olympus also no longer adds its lines to the game's guild roster right-click menu, where the
  game's own promote, demote, rank and removal are (a guildmate's Olympus lines stay in the other
  right-click menus and on the Olympus window's rows). The rank case still needs an in-game check.
  Escape still closes these questions, now together with the guild window. One limit remains: if
  an Olympus popup closed while another game popup stayed open, the removal can still be refused
  until every game popup has closed. The gamepad UI is unchanged.
- Any member can report a chat line from the Chat tab: right-click another player's line in the
  Olympus channel, or the name on it, and choose **Report to Olympus**. Any line from the last day
  can be reported, not only the 20 newest. The report goes to the online officers of the
  reporter's own guild (the guild master, Captains, appointed Watchers and signed moderators) and
  shows in their Watch under **Reports** and **Cases**. With no officer online it waits on the
  reporter's client for a day.
- A member's report also reaches the King and the High Council, in their Watch under **Reports**
  and **Cases**, the tab where the High Council works. It goes by logged whisper to the King's
  client while it is on, which keeps it apart from any guild's Watch and passes it on to the
  councillors whose clients asked lately. Each councillor's client asks every 15 minutes while the
  King's client is on and gets every report it received since his last one, including one that
  reached it late. The King's client takes a report only from a reporter it already knows in the
  guild he names: the King's own guild by its roster, another guild when his own earlier messages
  there (his lines in the Olympus chats, for one) spoke for it. A report from anyone else reaches
  his guild's officers only. It keeps only the lines it heard itself in the Olympus channel, so a
  case never shows words its player did not write. Per-player and per-guild rate limits apply. A
  councillor never receives a case about himself or a name his player linked, and the King's chat
  names no one. The council's reports and cases have their own sections, apart from the guild's,
  so an officer on the council, and the King, act on them in Olympus's chats and never with their
  guild's Watch; an officer can still send his own guild's case to the King for the council's
  vote. With the King's client off, the report waits for it on the reporter's client for a day.
  Multiplayer verification is still needed.
- The Olympus shortcut is **Shift + the game's guild key** (Shift-J on Forever, where the game
  binds Y to Legacy and G to Target Last Hostile, so the old Y shortcut never came on there). It is
  read from the player's own guild key binding and falls back to Shift-J when that key has a
  modifier or none is bound. As before it is used only while that key is unbound, saved bindings
  are never changed, and `/oly hotkey on|off` switches it. A key of the player's own can be set in
  the game's Key Bindings, under AddOns: **Toggle Olympus**.
- **Ask to update** in a player's right-click menu is now only for the author, the King and the
  High Council. A 1.2.1 client ignores an ask from anyone else, which older versions can still
  send. **Check version** stays available to every member.
- The race chat's short label is **Skyborn**. Long Lottery animal names stay on one line above
  the drawn numbers, with the original five-place animation kept.
- Finding a Bones opponent updates the existing Find window while searching and reviewing
  offers, rather than opening a second, smaller search window. Accepted matches retain their
  dedicated meeting view, with the Find window closed first. After the first innkeeper lesson,
  Find works from any location; creating or starting the table still requires an inn or an
  camp. Forever's **Campfire Nearby** effect now qualifies a physical campfire without posting
  a Board camp or enabling location sharing. Each player validates their own effect; the party,
  proximity and first-lesson checks remain. The New Table button updates as the effect changes.
- The detailed update parchment uses the existing game icons. For someone who has not seen the
  1.2.0 letter, that release's news comes before 1.2.1. The history keeps each letter separately.
  An empty first-session save no longer causes the letter to reopen on every login. With saved
  history available, a new version can still open its letter once; the help button and
  `/oly letters` always keep the history accessible.

## Reliability and review work

- Guild Masters can publish bounded guild charters. Recruitment uses corroborated guild fit
  rather than treating a claimed rank as authority; invitations and transfers remain manual.
- Officers can post a twenty-minute, zone-only muster. Participation requires existing location
  consent and the matching faction and realm scope; it does not publish exact coordinates or
  automatically invite anyone.
- The actual King and pinned Treasurer can inspect a private five-week contribution history.
  Missing snapshots stay unknown. This is reporting, not an automatic charge or feature lock.
- Moderation replay and appeal quotas are bounded separately from target self-testimony.
  Arena relays reject known identity contradictions while preserving valid late testimony.
  Capacity limits preserve active Arena records instead of evicting an ongoing event.
- Bones resync cannot invent the local player's decisions; reload retains locally witnessed
  retry proof. An opponent's instant departure claim is not accepted without local observation
  of the full grace period.
- Your Bones games also read retained own-game ledger records when the companion did not have
  its detailed history loaded at completion. Existing detailed entries win and duplicate
  results are not displayed twice. This does not invent missing rolls or reset saved history.
- Crafting accepts a sequence only after validating the actual payload and state. Arena profile
  history has a real bound. Church appointment and seen-check authority no longer comes from
  a claimed census rank alone.
- Remote rehearsal enrollment is off until the player explicitly permits it. Turning it off
  leaves an enrolled participant locally or closes their own directed session. No gold rehearsal
  bypasses the shipped financial gate.
- Photo-tour rolls no longer replace the game's global roll function. Innkeeper handoff waits
  for the native conversation to close and keeps the addon-only gamepad route.
- A bug report's blocked-call stack now starts at the call the game refused, not at the Olympus
  handler that recorded it. A block kept from an older version no longer heads a newer
  version's report, and the status line names that block's version. This does not change who
  caused a block; it only keeps an old one from appearing current.
- The test simulator isolates each client's popup/slash registrations, preventing old worlds
  from being retained by later clients. Diagnostic timing is optional; assertions and gameplay
  scenarios are retained. Affected runs include the complete Bones/Farkle regression family,
  while shared chat changes still require the full gate.

## Games stay free

No bets, gold stakes, paid Lottery tickets or entry-fee pots are enabled. Every package profile
excludes wager-only modules. Dormant local implementation is not a promise of a future release.

## Limits that must remain visible

Display privacy is not wire anonymity: clients receiving a moderation packet can inspect its
server-stamped sender. Previewing a staff role grants no real permission. Old appeals without
retained text cannot be reconstructed, and target self-testimony is not independent proof of a
moderator's action.

A new Wanted recipient without an independently pinned issuer cannot bootstrap from relay.
The Horde target list remains local to each client. The distributed signed word contains the
reviewed Slayers top three, not Horde targets: simply seeing Horde or waiting for another
player's observations does not populate the target list.
An unknown evidence identity is refused rather than placed in an unverified reviewer inbox;
the sender's original local observation stays saved. There is not yet a reviewer acceptance
receipt or guaranteed same-session automatic retry.

Not every longer-term governance, recruitment, identity-backend or contribution proposal is
implemented. Real-client and multiplayer verification is still needed.

If the beta client fails to restore SavedVariables, the addon cannot distinguish another login
from a new installation or recognize a later upgrade reliably. The automatic letter stays quiet
in that unknown state rather than repeating; this is not a fix for the client's save loading.

## Private test installation

Use the filtered test package, not the raw source tree. Close the client and keep a recoverable
backup of both addon folders and SavedVariables **outside AddOns**. A private installation may
contain CouncilList.lua, LinkCA.lua and DevPerf.lua: preserve those files and restore only their
needed entries into the new TOC. Do not restore the old TOC wholesale. The generic deploy script
replaces both folders and does not perform this private-file preservation; do not use it for
this installation.
