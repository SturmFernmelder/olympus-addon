# Partial history carry for 1.2.4 testing

This is a bounded, opt-in quote copy for the **same character** moving manually between
Olympus sister guilds. It is not the full historical continuity or named merger inheritance
requested in F26-14. No quoted row enters Loot, Court, pardons, Dues, ranks, keys or any other
authoritative ledger. No guild invitation, kick, punishment or payment action is performed.

## Player flow

1. While still in the original guild, with a current complete roster, run
   `/oly carry prepare <destination guild master-Realm>` and confirm the question.
   The destination guild master must have a current signed role or pinned King identity
   accepted by `Data.AuthorizedRank`; an ordinary census claim is insufficient. If this
   authority is unavailable, preparing is refused. Nothing is sent at preparation.
2. Arrange the guild move with the officers and accept the game's manual invitation.
3. Once the destination's roster confirms this character and its same verified master,
   open `/oly carry`, then choose **Offer prepared quotes** (or `/oly carry offer`).
4. That master opens `/oly carry`, reviews the warning and explicitly accepts the quote
   copy. Offers expire after three minutes. Queued messages recheck guild, identity,
   complete roster, authority and revocation before every native send.
5. The moved character can choose **Revoke this transfer** or `/oly carry cancel`.
   Revocation cancels pending data and sends a private withdrawal to the same recipient.
   The receiving client hides its copy and retains a replay floor when it hears withdrawal.
   This is an ordinary addon whisper: delivery to an offline recipient is not guaranteed.

The view is private to the exact consenting guild master's character, while still verified
as that character's current own guild master and while the quoted subject remains in the
current complete roster. A replacement master or an alt receives no inherited copy.
There is no automatic transfer between characters, even a confirmed alt.

## What can be quoted

- Current source-guild Loot notes naming this exact character: original writer, original
  time, note reference, revision, item, recipient, words and existing relay provenance.
  Unsigned notes remain **quoted/unverified**, including their claimed original source.
- This character's retained Court messages only, read through `Court.Messages()`;
  other people's Chronicle entries never enter the snapshot. The retained reference
  preserves the original server timestamp and the row also keeps its observation time.
  An unknown source guild stays unknown.
- A currently cached pardon observation, if present: its first observed local time only.
  That cache cannot establish the King's original deadline. No end date is calculated
  and no pardon is applied in the destination.
- If `Dues.PayerReceiptFacts(week)` is present, the current character's retained private
  pinned-Treasurer receipt facts for up to the retained five weeks. Issuer, source,
  sequence, week, original time, copper and amount remain quoted provenance. Relaying
  those facts does not authenticate the relay or create a new payment confirmation.

The copy holds at most 24 rows and 4,096 encoded bytes, split into at most 24 private
180-byte fragments, each with its own bounded `XC~1` envelope. An oversized snapshot
is refused, not silently imported partially. Pending offers (8), saved imports (32) and
durable replay/revocation floors (128, including pending reservations) are bounded.
Reaching a retention limit refuses new work. No public or outsider chunk assembler is
extended; existing Comm member admission, server-stamped sender and queue guards apply.

The sender's source-guild claim and original quotes cannot be reverified after a move.
All UI text says they are unverified. Faction and realm-group scope are checked, as are
the current destination guild and exact roster identities. This partial path supplies no
signed continuity, lost-record reconstruction, guild merger, Crown deadline, payment
inheritance, points recalculation or authoritative original-author fact.

## Validation and remaining live checks

`OLYMPUS_TEST_FILTER='carry:' luajit tests/run.lua` exercises the actual Carry functions,
Comm dispatcher and scheduler, Loot book and Court/Chronicle readers. Coverage includes
both consents, sender/recipient forgery, other-character subjects, missing consent,
faction/realm scope, replay, conflicts, revocation, expiry, malformed/oversized packets,
bounded state, stale rosters, role/guild changes and cancellation before native send.
The original WIP's binary SHA256 digest failed transport tests; encoding its binary digest
as hexadecimal restores successful bounded packets. A signed destination role also now
keeps the multiple return values that the WIP's Lua `and` expression discarded.

Run the consolidated `bash scripts/check.sh` after integration. The gamepad session pass
loads the TOC and exercises all Olympus dialog definitions through existing dialog flows;
the carry consent questions use Olympus's own dialog in both input modes.

Still needed in the real Forever client, with two players and retained source records:

1. Verify the signed/pinned destination identity before preparation, then cancel the
   preparation question: no outbound offer or private data should appear.
2. Prepare as an ordinary member, move manually, and verify the new complete roster.
   A stale source roster, a demoted destination master or an unknown alt must not send.
3. Offer and cancel the master's question: no records should arrive. Offer again and
   explicitly accept; only the exact current destination master should see unverified
   quotes. Other members, Lords of another guild and replacement masters see none.
4. Check original Loot writer/relay and Court timestamps against the retained originals;
   verify a quoted receipt changes no payment status and pardon observations create no
   pardon or deadline. Loot books and the destination Chronicle remain unchanged.
5. Revoke during a longer queued copy, then revoke a completed copy. Data stops, the
   accepted view disappears once the withdrawal arrives, and replay cannot restore it.
   Check what happens with an offline master; no guaranteed delivery is claimed.
6. Reload each client, switch guild/role, and use mouse/gamepad input modes. The saved
   copy keeps the same private reader boundary and both consent windows fit/read well.

No Windows install, live multiplayer acceptance, publication or release is implied by
offline checks or this implementation.
