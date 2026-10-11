# Olympus 1.2.2

A correction release: mostly fixes for the stutter and the problems the last updates brought, plus a round of security work. It contains everything in 1.2.1 (published on CurseForge on 8 October). Games stay free: no bets, gold stakes, paid Lottery tickets or entry-fee pots.

## Performance

- **Less stutter at busy hours.** The level race no longer runs its checks inside every census message. Its checks are now light and run once, a few seconds after a burst of reports.
- News of other guilds' census reports now causes one refresh per burst, at most once a second, instead of one per message.
- The world map is no longer redrawn while it is closed. It is drawn once when you open it.
- The Chat tab redraws less often and with less work: a message bubble that has not changed is moved, not laid out again.
- Once-a-minute background jobs now start at different moments, so they no longer all run on the same frame.
- **New: `/oly perf`.** Use `/oly perf on` to measure what Olympus costs your game and `/oly perf` to open a report you can copy and send. `/oly perf off` stops it and `/oly perf reset` clears it. While off, it costs nothing.

## Fixes

- Removing a member from the guild is no longer refused with "Interface action failed because of an AddOn" while an Olympus question is open. With mouse and keyboard, while a game guild window is open, Olympus asks its questions in its own windows. It also no longer adds lines to the game's guild roster right-click menu.
- The privacy page no longer opens by itself every session.
- Bones: the innkeeper window no longer opens at every inn visit. After invitations from two players, Olympus asks once whether to stop invitations. A die you picked stays lit while the table is busy.
- The King's letter about a new frame shows once per honour on each character, in a proper window, and never to the King about himself.
- Church counts no longer drop when a keeper's ledger fills up, and all of a busy Apostle's invitations now reach the ledger.
- A guild master who is online is no longer shown as away because of an old report.
- Bug reports now start a blocked call's trace at the call the game refused, and a block from an older version no longer heads a newer report.
- Census search treats l, I and 1 as the same letter, and 0 and O as the same letter.
- The minimap button is only placed when there is a minimap.

## Security

- Only the author, the King and the High Council can send **Ask to update**. Asks from anyone else are ignored.
- Layer hops: **Always invite**, **For Olympus!** and auto-accept now act only for your own guild roster, the King, his Steward and Hands, and signed Lords and Captains. They no longer act for a census rank or a guild a player only claims. Officers of other guilds can still be invited with a click.
- Signed leadership lists are only accepted once every part is in and verified, and only while they are valid. Old or expired lists can no longer lock a client out.
- `/oly status` and `/oly bug` no longer show your sealed channel's name, and a key typed with `/oly key` never appears in errors, the log or a report.
- The crafting fee desk now books a fee mail only when the seller's own word or the desk's check names that fee, so a made-up buyer cannot claim it.
- Text copied for Discord carries no formatting or pings from other players' words.

## New in this update

- Clicking **[Olympus]**, **[Captains]** or **[Lords]** in game chat opens the chat box for that channel, just like **[Party]**.
- **Report to Olympus**: right-click another player's line in the Chat tab, or their name on it, to report any line from the last day. Your report also reaches the King and the High Council.
- **Toggle Olympus** in the game's Key Bindings (under AddOns) lets you choose your own key. The built-in shortcut is now Shift + your guild key (Shift-J by default), used only while that key is free.
- The Skyborn race room is open to both factions.

## Already in 1.2.1

- Live Bones tables have a chat panel you can collapse: **Players** for the two players, and **Everyone** to include spectators.
- **Your week, in five lines** is a personal page in the Realm tab, and the Board shows a public weekly summary.
