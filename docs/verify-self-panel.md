# Optional personal verification panel (candidate)

The **My verification** tab reads the installed Olympus Verify bridge when the tab opens or refreshes. It detects both `OlympusVerifyBridge242.QueueSelf` and `.Status` after `PLAYER_LOGIN`; an absent bridge is not cached. Without Verify, the tab explains that the optional bridge is unavailable. `/oly verify` remains guild/GM approval, `/oly discord` is unchanged, and Olympus Link is not activated.

Paste your own Discord verification code and deliberately press **Submit code** once. The input is cleared before the dot-call `QueueSelf(code)`. A `true` boolean means only that a local request exists. It does not establish disk persistence, delivery, verified membership, payment or a Discord role. A false return is not success; an exception or unexpected return is unconfirmed. Refresh, page opening and status reads never submit or retry. No request ID is returned or inferred from another descriptor.

| Short status | Next action |
| --- | --- |
| Pending delivery | Wait; inspect `/olv status`. Do not submit the same request again. |
| Delivery acknowledged | Check Discord `/verify-status` for current verification and access. |
| Request rejected | Check Discord `/verify-status`; ask staff to review the original before submitting again. |
| Delivery route unavailable | Keep the original; ask staff to check the supported route. |
| Delivery unconfirmed | Keep the original; inspect `/olv status` or ask staff. Do not resubmit. |

Hover a record for its next action. The direct `Status()` envelope must be version **243**, `deliveryOnly=true`, `membershipProof=false`, `roleAuthority=false`, with a finite whole `total`, boolean `truncated`, and a request list. The generic Olympus Bridge API stays **1**. At most 20 descriptors are shown using allowlisted request kinds and delivery states, a finite timestamp, and a 32-hex opaque display reference. Extra codes, GUIDs, names, request bodies, native proof/MAC, donation payloads and collector fields are never rendered. A donation descriptor is a declaration, not payment confirmation. Display references are not transport IDs or reliable matches to a just-submitted code.

No new SavedVariables, queue, transport, expiry, deletion, role mapping, Watcher requirement or forced reload loop is introduced. The existing Verify machine handles delivery and normal reload/logout persistence. Backend-only releases do not require officer Sync. Automatic website feed remains off. The current seven-day GM grace implementation is unchanged; the conflicting 48-hour policy remains unresolved.

OLYMPUS PRIME is accepted by the attended SiteAggregate exporter in addition to the historical guild names. It exports only the current player's own guild with the existing Alliance, scope, native-roster provenance, freshness, completeness and masking checks. Wire schema/version and producer `1.3.2-site.1` are unchanged. This is not permission to enable an automatic website feed.

Offline regressions exercise the actual module: absent/present/login timing, dot calls, one deliberate submission, reentrancy/double-click protection, false/unconfirmed returns, five states, incompatible envelopes, redaction and truncation. Prime regressions exercise the actual exporter and its refusal paths. Offline models do not establish native client acceptance.

Before shipping, test on the supported native branches with Verify absent and with current Verify installed: open Olympus after login, find My verification, type a code, submit once, confirm the cleared input and local-only wording, and refresh/reopen without another request. Confirm the tab/input/buttons and record tooltips fit both window styles and gamepad-mode transitions. Inspect `/olv status` and Discord `/verify-status` separately; do not manufacture verification by changing a local status. Test an attended Prime export and refusal after a guild change, partial/stale scan or invalid scope. Member-to-officer transport, current server GUID and cross-client/native behavior remain pending until directly observed.
