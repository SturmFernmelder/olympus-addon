# Testing an Olympus beta

An automated pass and an in-game pass are different evidence. Record both. A green
repository check means the Lua, fixtures and package invariants passed offline; it does not mean
that a World of Warcraft client, gamepad flow or exchange between real players was observed.

## 1. Build gate (automated)

Start from the exact commit to be tested, in a clean Git worktree. `package.sh` refuses tracked
changes and any untracked or ignored file under `Olympus/` or `Olympus_Arena/` that could enter a
zip.

```bash
git status --short
git diff --check
bash tests/check-scripts.sh
bash scripts/check.sh
node --test web/test/*.test.mjs
scripts/package.sh --test N
```

The last command writes four tester artifacts:

- `dist/Olympus-<version>-testN.zip`
- `dist/Olympus-<version>-testN.files.txt`, the sorted files in that zip
- `dist/Olympus-<version>-testN.sha256`, the zip's SHA-256
- `dist/Olympus-<version>-testN.txt`, install and rollback instructions

Review the manifest before distributing the zip. On macOS verify it from `dist/` with
`shasum -a 256 -c Olympus-<version>-testN.sha256`; on Linux use `sha256sum -c`.
Keep the test zip and its sidecars together. Test builds expire, identify their build and commit
in game, stay in their test group, and are not release files.

## 2. One Windows client (observed)

1. Quit World of Warcraft. Back up both addon folders and
   `WTF/Account/<ACCOUNT>/SavedVariables/Olympus.lua`. Keep the backup outside `Interface/AddOns`.
2. Verify the downloaded zip in PowerShell. The printed hash must equal the first field of the
   supplied `.sha256` file:

   ```powershell
   (Get-FileHash .\Olympus-<version>-testN.zip -Algorithm SHA256).Hash
   ```

3. Turn off automatic updates for Olympus while testing. Delete the installed `Olympus` and
   `Olympus_Arena` folders, then extract the zip directly into
   `<WoW flavor>\Interface\AddOns\`. Do not leave an extra zip-named directory around them.
4. Restart the game. Confirm the addon list shows the test number and `/oly arena status` shows
   the expected build, base version, lane and commit. Record any Lua error before continuing.
5. Walk the main windows at the tester's normal resolution and UI scale, then at one smaller
   scale. Check tabs, Back, scroll areas, hover help, overlays, portraits, close/reopen and combat
   transitions. Run the built-in simulation/UI tour where it is available.
6. Repeat the critical path with gamepad mode on, then turn it off during the same session. No
   protected game window should be forced and no taint or blocked-action error should appear.
7. Check `enUS`, `ptBR`, and at least one locale that intentionally falls back to English. Look
   for clipped labels, broken format placeholders and buttons narrower than their text.
8. `/reload`, relog, and restart the client. Record what persisted and what the client discarded.
   Use `/oly bug` and, after a reload or logout, `WOW_HOST=user@pc scripts/logs.sh` for the evidence.

Rollback is also an observed gate: quit the game, remove both test folders, reinstall the current
release from the addon app, restore saved data only if needed, restart, and confirm the release
version loads without errors.

## 3. Mixed-version and multi-account session (observed)

Use the same zip and SHA-256 on every tester. Use free games and a party or raid. Bets, gold
stakes, entry-fee pots and paid Lottery tickets are not part of a beta or release. Do not bypass
the gate to test dormant financial code on somebody's real character.

The minimum useful session has two participants, an organizer, a spectator, and one client on
the previous public release. Also keep one
non-participant outside the group. Record each character, version, role, client flavor, gamepad
state and join/leave time.

Exercise a complete successful cycle before the hostile cases. Then cover, without bypassing the
buttons and functions players really use:

- a late join, leave and rejoin; `/reload` and a client disconnect during an open session;
- an older client in the group and an older client outside it;
- an unauthorized action, a repeated click, duplicate result and attempted double recording;
- a stale or delayed action, actions arriving in a different order, and a session closed early;
- an unavailable participant, cancellation, disconnect and recovery;
- gamepad and keyboard users together, combat/instance transitions, ignore/block and rate limits;
- a ten-minute burst/soak with several simultaneous users, watching queues, memory and errors.

After each game, compare the players' results and history, then compare any permitted public
summary on the spectator. An unexplained difference is a failed gate, even when the UI looked
correct. Treasury contributions use their separate, normal manual mail/trade checks; they are
not game stakes or prizes.

For the 1.2.1 candidate, include these focused live checks:

The Wanted paragraph below describes the historical 1.2.1 local-only capture path. It is
superseded for 1.2.3 and later by ordinary-member public intake. For the consolidated 1.2.4
candidate, use the Wanted checks in section 4 instead of expecting another client's own
verified observation to stay local. The installation and build instructions above still apply.

- Bones: two players exchange Players messages, then switch to Everyone with a spectator.
  Private messages must never reach the spectator. Collapse/reopen the side panel; keep an
  unfinished draft in each tab; repeat with gamepad mode. Disable spectators during a queued
  public message: it must not be delivered. The innkeeper's practice has no multiplayer chat.
  In `/oly arena sim boneschat`, check the red square/yellow arrow to the right of Sit Down,
  including while the setup covers the table. It must remain clickable above the table's
  surfaces; collapse restores the original width without an extra bar. Expanded chat must have
  no world-visible seam between it and the table. Close the preview, then check that normal
  pages show real records or honest empty lists, not sample opponents or results. Repeat with
  `/oly arena sim off`; this empty layout preview is not proof of multiplayer routing.
  After completing the innkeeper lesson, find an opponent outside an inn/camp: Find opens and
  can search, but New Table remains blocked. Meet in the same mapped inn, at a real Forever
  campfire with **Campfire Nearby** on each player, or at an explicitly registered Board camp
  (`/oly camp`, requiring location consent). For a physical fire, keep location sharing off:
  the open Play page must enable New Table when the effect appears and disable it when the
  effect disappears, without reopening. No camp post or consent change should occur. A retained
  camping benefit or a classic cooking fire alone is not enough. The first lesson still requires
  the innkeeper. In a party and within ten yards, start
  and finish a free game. Both players must see their result exactly once in Your Games,
  including after a reload. Check an older retained ledger result whose detailed companion
  history is missing; show only the details actually retained, without inventing a replay.
- Chat: hide guild names through the gear. Normal, deleted and Bones table headers must follow
  the choice without losing the draft. Tooltips and guild searches must still identify the guild.
  Reload to check persistence, then show the names again. New native chat lines follow the
  choice; previously printed native lines are unchanged. Other players see their own choice.
- The Watch: create a timeout, appeal while a councillor is offline, then overlap online later.
  The subject sees only "a moderator"; authorized staff retain the actor. A preview role grants
  no permissions. Compare current timeout, appeal and decision once, without duplicate rows.
- Wanted: each participant sends their own observed kill/death evidence to a reviewer. Unknown
  identity is not accepted on a claimed guild alone. Publish the reviewed rankings; a trusted
  relay should recover the unchanged signed word for a recipient that already pinned that
  issuer independently. A new recipient without the pin cannot bootstrap from the relay.
  Separately check local capture: with a moderator's name-only listing, a locally observed
  Horde player's recent fatal killing blow against you should learn their GUID and add one
  bounty, not two after retries. Nonfatal damage, animals, stale recaps and conflicting pinned
  GUIDs must not count. Repeat without a prior listing to check automatic own-death discovery.
  The Horde target list is local; another client's observation or Slayers publication does not
  synchronize that list. A missing local recap is not proof that no PvP death occurred.
- Weekly brief: as an ordinary member, open Realm > Your week, in five lines in the main
  window. Check five readable sections on parchment, Back, switching tabs, and reopening;
  repeat in gamepad mode. The personal brief must not appear in the Throne or as an automatic
  popup after login/reload. No sharing setting changes; the separate public Board summary
  must not reveal private dues or poll data.
- Lottery: draw Mechanostrider and check its full label above, not across, the result numbers at
  the normal and smaller UI scales. Keep the five-place animation and free tickets.

The in-addon Director checklist is the session record. Mark each item Pass, Fail or Skip with a
short observation, then copy its test report. A skip is not a pass.

## Evidence and promotion

Keep one small table for every candidate:

| Gate | Evidence | Result |
|---|---|---|
| Repository and package | commit, command log, manifest, SHA-256 | Pass / Fail |
| Windows client | client build, screenshots, `/oly bug`, saved log | Pass / Fail / Not run |
| Gamepad, locales and UI | client build and observations | Pass / Fail / Not run |
| Mixed-version session | roster, versions and report | Pass / Fail / Not run |
| Multi-account/adversarial | roster, ledger reconciliation and report | Pass / Fail / Not run |
| Rollback | release restored and restarted | Pass / Fail / Not run |

Do not describe a client or multiplayer gate as passed until somebody observed it. Do not promote
a candidate with an unexplained Lua error, an unintended recipient, a missing recovery path, an
unreconciled balance or a rollback failure.

A [CurseForge Beta file](https://support.curseforge.com/support/solutions/articles/9000197242-file-types-and-additional-fields)
is a public, opt-in distribution. Use it only after the build is safe to publish. Named or closed
testers receive the expiring test zip and its checksum directly; that test zip is not uploaded to
CurseForge or GitHub.

## 4. Consolidated 1.2.4 live checks

Use [RELEASE-1.2.4.md](RELEASE-1.2.4.md) as the candidate's behavior and limitation list.
Apply sections 1–3 for installation, checksum, exact commit, input modes and evidence. This
section adds the current checks; it does not record any of them as passed and authorizes no
publication. Record **Pass / Fail / Not run**, with the client build, exact candidate, input
mode, roles, observed result and screenshot or error log. Stop on an unexplained Lua error or
an unintended recipient.

### Start and retain evidence

After a full client restart, use these in-game commands:

```text
/oly status
/oly arena status
/oly bug
/oly perf reset
/oly perf on
```

Confirm the supplied candidate/build/commit before testing. Play the normal workload, including
the busy Chat, Census, Realm, Treasury and Games pages. Then use `/oly perf` and save its
copyable report, screenshots and `/oly bug` output; finish with `/oly perf off`.
Repeat the same workload with Olympus disabled **after another full client restart**. Record
visible stutter, worst spikes and surrounding events; average CPU or RAM alone is insufficient.
Do not claim the enabled/disabled comparison passed from a Lua fixture or a short idle session.

### Windows UI, privacy and honours

1. Run `/oly privacy`. Close it with X without changing an existing choice, reload and relog.
   Existing choices should remain; the same questions should not reopen automatically. A new
   question may be asked once. Check that the version letter follows a pending privacy page
   without repeatedly reopening a previously answered page or the main window.
2. Run `/oly profile`. Test Look, Icons, Who sees what, Letters, Back and reopening. With Games
   off, an ordinary member can still select a personal portrait fallback icon, but no Games
   sharing is enabled. Council chat icons remain restricted to actual High Councillors. Own and
   other portrait/name right-clicks open **View profile** in the normal Olympus shell.
3. On an actually authorized author client, run `/oly honours preview`. Open every gallery
   family, including gold/silver/bronze, monthly, cross, charm and Slayer examples. The preview
   must create no saved award/letter/Wanted entry, change no worn pick and consume no real
   waiting letter. An ordinary member or a role preview gets no author gallery. Close it before
   testing a real earned letter.
4. Check paper, portrait, ring, words, red seal beside the signature and all buttons at normal
   and smaller UI scales. Honour art has no duplicate dragon beneath it; rank dragons remain.
   All cross frames are larger; other-honour size normalization is not claimed complete. A
   local red-cross choice is labelled local and other clients see the ordinary chosen honour.
5. Check a newly earned eligible honour, reload, lose/regain it and change place. First eligible
   letters should not repeat; subsequent movement uses quiet notices. The King gets no letter
   from himself. The completed-month koi/Bones charm and a retained cornucopia choice need
   their own checks; do not create fake saved achievements to mark them passed.
6. Click native `[Olympus]` in chat: its input targets Olympus when writing is permitted. Test
   the native chat UI and any chat replacement separately. With mouse input and a free guild
   shortcut, an authorized High Councillor's Shift + guild key opens The Watch; existing saved
   or override bindings are not replaced. Hotkey opt-out and gamepad mode remain respected.
7. As the real King, enable location sharing in the Throne, reload, enter/leave an instance,
   and wait for the map to load. The status distinguishes configured opt-in from effective
   location availability and resumes without an off/on workaround. Games live-table settings
   remain independent. Compare the visible crown/layer on another client.
8. Repeat native kick, promote, demote and rank changes with the game's guild window open and
   an Olympus question open. No Olympus line should be inserted into native guild roster menus.
   Separately reproduce the reported network-ban attempt in a battleground with authorized
   moderators; retain the exact action/error/stack. Generic popup checks do not prove this
   previously intermittent error resolved.

### Two or more real clients

- **Wanted:** use ordinary verified members from different Olympus guilds, with capture consent
  enabled, and a spectator. Perform agreed outdoor PvP observations; run `/oly wanted status`
  on sender and receiver. A player's own observed death/kill should reach the other client.
  Retry the same evidence: one death counts once. Nonfatal damage, animals, stale recaps,
  unresolved identities and instance deaths must not count. Zero/zero entries stay out of all
  views. Compare points, kills, revenge notice/avenger actions and the bounty's reset after a
  claim. Test a proved Olympian alt link and an unlinked character separately: do not infer
  Horde account ownership or claim the unrelated two-account farming case solved.
- **Role rooms and Games:** check approved HC, GM, centurion, department, Church and Watch
  audiences with one authorized participant and one excluded client. A role preview grants
  no membership. Enter must yield an echo/history entry or an explanation of failure/partial
  delivery. With many rooms, selection and drafting remain responsive. Finish a Bones game:
  participants can continue its conversation; spectators retain read-only history. Reload and
  reconnect within retention limits; a lifecycle update must not open the window by itself.
- **Guild authority:** an ordinary sister-guild master cannot send a global Crown decree,
  muster, agenda or moderation action. Their own authorized guild actions stay available.
  Verify Heraldry correspondent revocation while a message is queued. The King's centurions
  match the signed High Council; no conflicting manual appointment control is offered. Lottery
  draws remain King/author/HC-only, with no public Lottery ranking and no paid tickets.
- **Records:** compare the participants' retained game/duel results and closed-month ranking
  after reload, later join and recovery from another holder. Exercise more than one day/month
  page where records actually exist; a full rotating page should not label older coverage
  missing. Missing halves, conflicts and untrusted seals cannot become completed evidence.
  Record what is unavailable; do not fabricate historical games or infer a full replay.
- **Church:** check retained appointments while the source is offline, then reconnect; a signed
  Apostle must not degrade from incomplete data. Check the twelfth direct missionary and
  rejection of a thirteenth for both Apostle and missionary. A 5,000-entry offline fixture
  does not establish live synchronization performance. For correspondent daily history,
  **950 does not qualify; more than 950 does**. Unknown days pause with no increment and no
  break; known nonqualifying days must follow the implemented daily rule. Compare the average
  membership tie-break. Observe a real daily boundary and a following day before marking this
  gate passed. Clock jumps or a single-day session cannot replace that observation; existing
  snapshots cannot prove a historical streak.

### Treasury, dues, campaign and private quote transfer

1. As an ordinary member, open the dues page and Privacy reminder switch. With no retained
   receipt, payment is unknown. A successful native send may show sent, but not confirmed.
   Arrange a normal contribution with a pinned Treasurer; compare partial and counted receipt
   states after actual native mail/trade intake. A manual ledger entry must not authenticate an
   unrelated later receipt. Request a retained missing receipt through the page and reload.
   Dismissing the local reminder leaves sharing choices intact and keeps reminders quiet in
   combat/instances. No automatic payment, sanction or new grace-period policy is expected.
2. As authorized staff, inspect affiliated Treasury snapshots, let the sharer go offline and
   reload. Retained gold/items show their observation age; absent data stays unknown. Check an
   unauthorized client cannot read restricted details. Public numeric summaries must not
   disclose private donor names or item histories.
3. As the actual King, start a voluntary campaign through its Treasury controls. Check purpose,
   gold/material goals and the 14-day window. As a real keeper, explicitly assign an eligible
   newly received voluntary gift. Current-week dues remain reserved; old/manual money, sales,
   transfers and custody cannot be assigned as fresh campaign gifts. Cancel confirmation, then
   accept once, retry and reload: the same receipt cannot be counted twice. Public clients see
   only aggregates. Closing needs the King's purchases note and removes the bar; it moves no
   gold or items and awards no privilege. Do not manufacture receipts to exercise these checks.
4. For a deliberately arranged same-character guild move, retain source records and run:

   ```text
   /oly carry prepare <destination guild master-Realm>
   /oly carry
   /oly carry offer
   /oly carry cancel
   ```

   Prepare in the source guild; cancel its question first and verify nothing is sent. Confirm
   preparation, move by a human invitation and wait for the complete destination roster. Offer
   to that exact verified master. The master opens `/oly carry`, cancels the acceptance question
   once, then explicitly accepts the pending offer while it is fresh: only their current private
   master view may show unverified quotes.
   Compare original author/time/relay against retained originals. Destination Loot/Court/Dues/
   pardons/ranks/keys must not change. Revoke queued and completed copies; delivery cancels/hides
   the quote view and replay cannot restore it. Demotion, stale roster, another guild, unknown
   alt and replacement master grant no inherited copy. Offline withdrawal delivery is not
   guaranteed. See [history-carry.md](history-carry.md) for bounds and remaining limitations.

Justice scoring, other-honour normalization, unlinked Horde/account anti-farming, full signed
history continuity, named merger inheritance and a new dues grace policy remain open. Keep
those distinct from the implemented controls and from every unobserved live gate above.
