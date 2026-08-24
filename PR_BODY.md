## Summary

- Add support for Monk's innate `Mend` ability, which previously had no way to be configured (the Lua only handled AA-based abilities, not core class skills).
- Exposed as a new "Special Skills" section on the Disciplines tab, with the same target/trigger/threshold/min-XTarget/burn/priority controls as a real Discipline. Defaults to self-heal at 75% HP.
- Fires through the existing `isSpecialSkill`/`runtime.fireSkill` pipeline (`/doability` instead of `/disc`), which was already wired into the combat loop but never exposed in the UI.
- Scoped to Mend only for now; `Feign Death` uses the same mechanism but is intentionally left out pending its own design discussion (dropping to the floor on an automated trigger has different failure modes than a self-heal).

See `CHANGELOG.md` (2026-08-24 entry) for details.
