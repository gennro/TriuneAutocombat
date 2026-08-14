# Triune AutoCombat

> A friendly, easy-to-use combat bot and multiclass automation tool built specifically for the **[Project Triune](https://nms.bestemu.com/)** EverQuest server (via [MacroQuest](https://macroquest.org/)).

---

## What is Triune AutoCombat?

On **[Project Triune](https://nms.bestemu.com/)**, every character is a multiclass combination of three EverQuest classes (a "trio" or "gestalt"). Juggling three full spellbooks, disciplines, and dozens of activated AAs on a single character can get overwhelming fast — that's where **Triune AutoCombat** comes in!

Triune gives you a clean visual in-game window to manage your 3-class combo and automate your combat loop without needing clunky macros or endless hotbars.

It handles all the busywork for you:
- **Multiclass Combat & Spellcasting**: Fires nukes, heals, buffs, DoTs, debuffs, disciplines, and AAs from all 3 of your classes based on simple rules you set.
- **Smart Pulling & Patrols**: Pulls mobs to your camp, roams zones to hunt, or walks custom waypoint routes.
- **Pet Control**: Commands pets from any of your pet classes (Mage, Necro, Beastlord, Shaman, Shadowknight, Enchanter) to attack, pull, or tank while you hang back.
- **Group Assists & Boxing**: Lets your box characters follow the tank, assist on targets, and cast safely from the backline.
- **Auto-Resting**: Sits to med and regenerate mana/endurance when it's safe, and stands up instantly if attacked.

Just type `/ac run` (or click **Start** in the UI) and let your character go to work!

---

## Quick Start Guide

> 📥 **Download the latest version here**: [**GitHub Releases (Latest)**](https://github.com/gennro/TriuneAutocombat/releases/latest)

Getting started takes less than two minutes:

1. **Download & Extract**: Grab the latest release from the link above and extract it into a folder under your user directory (for example, `Documents\MacroQuest`).
2. **Start MacroQuest** and log into [Project Triune](https://nms.bestemu.com/).
3. **Open Triune**: Triune starts automatically on login. If the window is closed, type `/ac` or `/lua run triune`.
4. **Verify Your Classes**: In the **Character Classes & Loadout** section, verify your 3 classes (or click **Re-Detect** to let Triune detect them automatically).
5. **Set Up Your Spells**: Go to the **Spell Gems** tab and choose what each gem slot should do (e.g. *Heal when HP < 50%*, *Snare on incoming mobs*, *Nuke in combat*).
6. **Pick a Mode & Go**: On the **Control** tab, pick your mode (**Manual**, **Puller**, or **Assist**) and click **Start**!

---

## Combat Modes

Triune keeps things simple with **3 main combat modes**:

| Mode | Best For | How It Works |
|---|---|---|
| **Manual** | When you want to drive | You control movement and pick where to go. Triune handles attacking, casting your 3-class loadout spells, using AAs/discs, and healing allies. When the fight is over, it will walk back to your camp if you have one set. |
| **Puller** | The group leader / puller | Automates finding and engaging mobs. Comes in two flavors:<br>• **`Camp`**: Runs out, tags a mob (with a spell, bow, melee hit, or pet), brings it back to camp, and tanks it there.<br>• **`Hunt`**: Roams around the zone, finds mobs, and kills them right where they stand. |
| **Assist** | Box characters & helpers | Follows and assists your Main Assist (MA). Comes in three flavors:<br>• **`Chase`**: Runs right behind the MA and attacks whatever the MA targets.<br>• **`Camp`**: Holds position at camp and only hits mobs that get brought into camp.<br>• **`Backline`**: For healers and casters — stays safely at range and never charges into melee. |

---

## Key Features

### 🎯 Smart Pulling & Target Filters
- **Choose Your Pull Method**: Tag mobs using **Melee**, a **Spell** of your choice, a **Pet**, or **Ranged** (bow/throwing).
- **Stand Back Mode**: Great for pet classes and rangers! Lets your pet tank or keeps you at range without running into melee.
- **Pull Lists**:
  - **Include List (Whitelist)**: Only pull specific mobs you name.
  - **Ignore List (Blacklist)**: Skip unwanted mobs, dangerous roamers, or rares you aren't ready for.
- **Faction Filters**: Choose which mob factions to fight (`Scowling`, `Threatening`, `Indifferent`, etc.) with quick one-click presets like **Hostile Only**. Never accidentally pull a friendly guard or quest NPC again!

---

### 🚩 Waypoint Patrol Routes
- **Walk Custom Routes**: Create a list of waypoints and let your puller smoothly walk the path back and forth (1 ➔ 2 ➔ 3 ➔ 2 ➔ 1) while scanning for mobs.
- **Map Path Lines**: Your waypoint route and arrival circles are drawn directly on your in-game EverQuest map so you can see exactly where your character will walk.
- **Pause & Resume**: Whenever a mob is spotted, patrol pauses to fight. Once the mob dies, patrol picks right back up where it left off.
- **Easy Setup**: Click **Add Current Location** to drop waypoints as you walk, or use chat commands like `/ac wp add`.

---

### 🔮 Simple & Powerful Spell Loadouts
- **12 Spell Gem Slots + AAs + Disciplines**: Set up spells, activated AA abilities, and combat disciplines from all 3 of your classes in one unified loadout.
- **Easy Trigger Rules**: Tell each spell exactly when to fire (e.g. *Target HP < 90%*, *My HP < 40%*, *Missing Buff*, *Always*, *In Combat*).
- **No Wasted Mana**: Triune automatically checks if a DoT, snare, slow, or debuff is already on the mob before casting, so you never double-cast or waste mana.
- **Burn Mode**: Tag big cooldowns and nukes as **Burn Only**, then toggle Burn on when fighting named mobs or big pulls (`/ac burn`).
- **Min XTarget Gate**: Set heavy spells or area-of-effect nukes to only fire when you have multiple enemies on you (e.g. *Only cast if 3+ mobs on XTarget*).
- **Auto-Memorize**: Triune remembers your setup in `triune_loadout.lua` and will automatically memorize missing spells when you're out of combat.

---

### 🐾 Smart Pet Control
- **No Early Aggro**: Pets stay on hold until you actually start hitting the mob, keeping them from pulling accidental adds.
- **Pet Assist %**: Tell your pet to wait until the mob's HP drops to a certain percentage before engaging.
- **Pet Pulling**: Command your pet to tag distant mobs and bring them back to you.

---

### 📱 Compact Mini HUD
Want to clear up screen clutter while playing?
- Switch to the **Mini HUD** (`/ac compact` or click the **Compact** button).
- Gives you a tiny, clean floating window with Start/Pause, mode selection, Burn toggle, and fast one-click buttons for extra tools.
- Shows your live **AA/hr** and **Plat/hr** session rates right on your screen.

---

## Built-in Bonus Tools

Triune comes packed with handy standalone tools you can open right from the main window or via chat commands:

| Tool | Chat Command | What It Does |
|---|---|---|
| 🧙 **Spellbook Browser** | `/ac spellbook` | Browse and search all spells across all 3 of your character's classes, filter by level or type, and assign them to your loadout with one click. |
| 🖱️ **Cursor Manager** | `/ac cursorui` | Displays what's on your cursor and can automatically dump items into your bags (`/ac clearcursor`). |
| 🛡️ **Interactive Buffbot** | `/ac buffbot` | Run an automated buffing station! Listens for `/tell` requests from nearby players, hands out buffs, and sends a reply when done. |
| 📊 **DPS Parser** | `/dps` | Live combat parser tracking player damage, spell hits, DoTs, and pet DPS with historic fight logs. |
| 🎯 **Zone NPC Tracker** | `/ac track` | Lists all NPCs in the zone by distance and level. Double-click any mob (or click `[Nav]`) to run straight to it! |
| 🔄 **Release Updater** | `/ac update` | Checks GitHub for new Triune updates and lets you update your files with a single click. |

---

## Slash Commands

You can control almost everything using simple in-game chat commands:

| Command | Aliases | What It Does |
|---|---|---|
| `/ac` | | Start or pause autocombat |
| `/ac run` | `/ac start` | Start autocombat |
| `/ac pause` | `/ac stop` | Pause autocombat and stop moving |
| `/ac burn [on\|off]` | `/ac burnon`, `/ac burnoff` | Toggle Burn mode on/off |
| `/ac compact` | `/ac mini`, `/ac hud` | Toggle the compact Mini HUD |
| `/ac status` | | Print current status and mode to chat |
| `/ac help` | `/ac ?` | Show command help in chat |
| `/ac <mode> [submode]` | | Switch mode (e.g. `/ac manual`, `/ac puller camp`, `/ac assist chase`, `/ac backline`) |
| `/ac pullcon [preset]` | `/ac con` | Set faction filters (e.g. `/ac pullcon preset hostile`) |
| `/ac wp [add\|clear\|del\|on\|off\|list]` | `/ac waypoint` | Manage waypoint patrol routes |
| `/ac spellbook` | `/ac book` | Open the Spellbook Browser |
| `/ac cursorui` | `/ac cursormgr` | Open the Cursor Manager |
| `/ac clearcursor` | `/ac autoinv` | Dump cursor items to inventory |
| `/ac buffbot` | `/ac buff` | Open the Buffbot window |
| `/ac track` | `/ac zone` | Open the Zone NPC Tracker |
| `/ac update` | `/ac checkupdate` | Check for updates |
| `/dps` | `/triunedps` | Open/toggle the DPS parser |
| `/triunerun` | | Fast keybind command to toggle start/pause |

---

## File Structure

```
TriuneAutocombat/
├── mq2triune/
│   ├── triune_updater.py    # Python updater script
│   ├── update.bat           # Windows updater launcher
│   ├── update.sh            # Linux updater launcher
│   ├── lua/
│   │   ├── triune.lua           # Main autocombat engine & Mini HUD
│   │   ├── triune_track.lua     # Zone NPC tracker & navigation tool
│   │   ├── triune_updater.lua   # In-game updater window
│   │   ├── triune_spellbook.lua # Spellbook browser & loadout helper
│   │   ├── triune_cursor.lua    # Cursor item manager
│   │   ├── triune_buffbot.lua   # Automated tell buffbot
│   │   └── triune_dps.lua       # Standalone DPS parser
│   ├── config/
│   │   └── triune_data.lua      # Spell and ability database
├── README.md                # This guide!
└── CHANGELOG.md             # Detailed update and change history
```

> **Note:** Your personal character settings and loadouts are automatically saved to `triune_loadout.lua` in your MacroQuest config directory, so updates will never overwrite your setups.

---

## Helpful Links

- **GitHub Releases (Latest Downloads)**: [https://github.com/gennro/TriuneAutocombat/releases/latest](https://github.com/gennro/TriuneAutocombat/releases/latest)
- **Project Triune Website & Database (PTDex)**: [https://nms.bestemu.com/](https://nms.bestemu.com/)
- **MacroQuest**: [https://macroquest.org/](https://macroquest.org/)

---

## Version

Current version: **1.6**

See [CHANGELOG.md](CHANGELOG.md) for full release notes and update history.
