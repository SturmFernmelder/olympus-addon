# Olympus 1.2.3

Fixes from the King's stream, a lighter Olympus, and Most Wanted that finally fills itself. It
contains everything in 1.2.2. Games stay free: no bets, no gold at stake.

## Memory and performance

- **The Chat tab no longer rebuilds every line for each new one.** With the Olympus window open it
  allocated about 2.5 MB per new line; a redraw for a new line now allocates a few KB. Census
  updates no longer force the whole tab to be rebuilt.
- The Church keeper's first tick after login, its tally, the guild roster scan and census reports
  do far less work and make far less garbage every minute.
- **`/oly perf` measures memory too:** what each part of Olympus allocates, the frames where the
  memory jumps, the highest heap, and Olympus's own memory as the game reports it.

## Fixes from the King's stream

- The privacy page no longer opens again after updating for a player who had already closed it
  (1.2.0 and 1.2.1 only remembered that for the session).
- The Olympus window no longer opens by itself when another member claims your crafting request.
- The update letter shows a moment after you close the privacy page, and retries every 10 seconds
  while it waits, instead of once a minute.
- The King's crown on the map sends his layer right after login, without turning it off and on.

## Who reaches the whole army

- **Royal decrees and Tabard inspections:** only the King, his Steward, his Hands, the High
  Council and the King's guild. Any other guild master's reach his own guild alone, as guild
  decrees.
- **Call to Arms and Muster:** the King, his Steward, the High Council, the King's Hands and the
  King's guild's officers. Any other guild's officers call their own guild alone.
- **Officer musters, layer-hop trust and moderator protection** follow the same rule: no guild
  master or officer of another guild has an action that reaches every guild.
- Clients on 1.2.3 ignore the army-wide versions from anyone else, so older clients are ignored
  too.

## Most Wanted

- **It fills itself.** A Horde player who kills an Olympus member, or is killed by one, enters
  Most Wanted from that member's own death recap or killing blow, and every member sees it. No
  list, no Send button and no review are needed.
- **Bounties:** each death adds the victim's office (King 100, High Council 50, guild master 30,
  centurion 20, another office 10) plus his level. A kill pays the Horde player's level twice plus
  his whole bounty, which then starts again from zero. Killing the one who killed you adds 100 for
  revenge. Only outside instances. Repeated deaths and kills within a few minutes don't stack.
- Only the King, the High Council or the author can remove an entry; removing it cancels what it
  counted on every client.
- **`/oly wanted status`** opens a copyable page with what was captured this session and why
  anything was refused.

## Honours

- **The top 3 missionaries wear the Shepherd's crook** in gold, silver and bronze, with the titles
  Good Shepherd, Faithful Shepherd and Shepherd.
- A newly earned frame switches on by itself only if it is released, so the cornucopia is no
  longer lost. The profile lists only frames you can wear, and your pick stays.
- The author's character shows the silver dragon before his name in the game's chat and wears the
  title The Royal Dev.

## Chat

- The race and class chat rooms are gone from the Chat tab.

## For testers

- `/oly perf on`, play a while, then `/oly perf`: the report shows time and memory per part.
- `/oly wanted status` after dying to, or killing, a Horde player.
