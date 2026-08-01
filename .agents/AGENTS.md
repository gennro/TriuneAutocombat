# TriuneAutocombat — Project Rules for Antigravity

## Project Overview

**TriuneAutocombat** is a MacroQuest ImGui Lua autocombat engine for EverQuest
progression servers. It automates targeting, spell casting, pet management, and
navigation for a "trio" of three EverQuest characters played together. It is
written entirely in Lua 5.1 / LuaJIT and runs inside MacroQuest2 via
`/lua run triune`. The project has four Lua modules and one large data file.

## File Map

| File | Role |
|---|---|
| `lua/triune.lua` | Main engine: UI, loadout, combat loop, persistence. Entry point. |
| `lua/triune_common.lua` | Shared library: navigation, spell helpers, class detection, ImGui theme. |
| `lua/triune_spellbook.lua` | Standalone spellbook browser + memorization queue window. |
| `lua/triune_cursor.lua` | Standalone cursor item manager window. |
| `config/triune_data.lua` | Era-correct spell/disc/AA database (generated, not hand-edited). |
| `CHANGELOG.md` | Full history of changes, newest date first. |
| `README.md` | User-facing documentation including commands, features, file structure. |

> **Note:** `triune_loadout.lua` is written to the MQ config directory at runtime — it is NOT in this repo.

## Module Dependency Chain

```
triune.lua
  └── requires triune_common.lua

triune_spellbook.lua
  └── requires triune_common.lua

triune_cursor.lua
  └── requires triune_common.lua (multi-path search)
```

`triune_common.lua` has **no project-level dependencies** — it only requires `mq`.

---

## MANDATORY: CHANGELOG.md Update Rule

**After every meaningful code change, you MUST update `CHANGELOG.md`.**

"Meaningful" includes: bug fixes, new features, refactors, new helpers, UI changes,
performance improvements, new slash commands, new config fields, or any behavioral change.

### CHANGELOG Format

```markdown
## YYYY-MM-DD

- Short present-tense description of change.
  - Sub-bullet for implementation detail if needed.
- Another change on the same date.

> **TLDR:** One-sentence summary of the day's changes (optional, for large batches).

---
```

Rules:
- Dates are always `YYYY-MM-DD` format (current local date).
- Newest date goes at the **top** of the file, below the `# Triune AutoCombat Change Log` heading.
- Each bullet describes **what changed and why**, not just what the code does.
- Sub-bullets explain implementation choices when the top-level bullet alone is unclear.
- The `---` horizontal rule separates date sections.
- If the current date section already exists, **append new bullets to it** rather than creating a duplicate date section.

---

## MANDATORY: README.md Update Rule

**Update `README.md` whenever any of the following change:**

- A new combat mode is added (update the mode table in Features)
- A new slash command is added (update the Commands table)
- The file structure changes (update the File Structure block)
- A new major feature section is added (add a new `###` subsection)
- The version number changes (update the "Current version:" line at the bottom)

### Version Number Location

The canonical version is defined in `lua/triune.lua`:
```lua
local VERSION = '3.25-commonmod'
```

The README must always reflect this value:
```markdown
Current version: **3.25-commonmod**
```

---

## Lua Compatibility Rules

This project runs on **Lua 5.1 / LuaJIT** inside MacroQuest. Do NOT use:

- `//` (integer division — not valid in Lua 5.1; use `math.floor(a/b)`)
- `|`, `&`, `~` bitwise operators — use the `bit` library: `bit.bor()`, `bit.band()`, etc.
- `<< >>` shift operators — use `bit.lshift()`, `bit.rshift()`
- `goto` (not in LuaJIT by default)
- String methods not in 5.1 (`string.pack`, `utf8`, etc.)

Prefer:
- `pcall()` guards around all TLO (Top Level Object) accesses — they can return nil unexpectedly
- `local` for every variable; never rely on implicit globals
- Explicit `nil` checks before indexing any MQ TLO result

---

## MacroQuest API Conventions

### TLO Access Pattern
```lua
-- GOOD: pcall guard prevents crashes on nil/missing spawns
local ok, val = pcall(function() return mq.TLO.Me.Gem(slot).Name() end)
if ok and val then ... end

-- BAD: direct access crashes if TLO returns nil unexpectedly
local val = mq.TLO.Me.Gem(slot).Name()
```

### ImGui Thread Safety
- **Never call `mq.delay()` from an ImGui render callback** — it is a non-yieldable thread and will crash with "Cannot delay from non-yieldable thread".
- Queue actions via a `pending*` flag (e.g., `reDetectRequested`, `pendingAction`) and execute them in the main coroutine loop.
- Pattern used in `triune_cursor.lua` (pendingAction) and `triune.lua` (reDetectRequested).

### Command Execution
```lua
mq.cmd('/command arg')       -- fire and forget
mq.cmdf('/command %s', arg)  -- formatted string version
```

### Event Handling
- Register chat events with `mq.event('name', 'pattern', handler)`
- Must call `mq.doevents()` in the main loop to process queued events

---

## State Table Conventions

All runtime state is stored in **four structured tables** (not bare locals):

| Table | Purpose |
|---|---|
| `ctrl` | User-configurable control surface (mode, settings, thresholds). Persisted. |
| `runtime` | Transient combat/loop state (timestamps, pending flags, last-cast tracking). |
| `petState` | Pet management state (pet list, last command, manual hunter hold). |
| `pursuit` | Navigation/targeting state (target id, nav stalls, wander loc, unreachable set). |
| `stuckState` | Anti-stuck system state (position history, counters, recovery timestamps). |

When adding new state, always add it to the appropriate table — never add a bare top-level local (Lua 5.1 main chunk has a 200-local limit that was already hit once in this project).

---

## Code Style

- Section headers use `-- ====` / `-- ----` banner comments as present throughout the files.
- Functions exported from `triune_common.lua` are always `common.functionName`.
- Color constants use descriptive names: `GOOD`, `WARN`, `ERR`, `ARC`, `GOLD`, `MUTED`.
- The unified dark theme must be applied to every ImGui window via `common.pushTheme()` / `common.popTheme()`.
- Class abbreviations always use the mixed-case data-file format: `War`, `Clr`, `Pal`, `Rng`, `SK`, `Dru`, `Mnk`, `Brd`, `Rog`, `Shm`, `Nec`, `Wiz`, `Mag`, `Enc`, `Bst`, `Ber`.
