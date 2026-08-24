## Summary

- Replace `/autofire` with the server's `#attackmode ranged`/`melee` commands for Ranged-style combat and pulling, tracked via a chat event since `Me.AutoFire` never reflects real state on this server.
- Ranged pulling now closes to true engagement range while already firing, instead of stopping short at the loose pull-engage distance and waiting.
- Fix Ranged auto-attack getting stuck (or toggling off entirely) when switching targets, including a clustered-mob edge case in Hunter-mode pulling that skipped the retoggle.
- Lower the minimum Ranged/Spell Combat Distance from 15 to 5, for melee-leaning hybrid builds.

See `CHANGELOG.md` (2026-08-23 and 2026-08-24 entries) for full details.
