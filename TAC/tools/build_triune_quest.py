#!/usr/bin/env python3
"""build_triune_quest.py

Compiles EverQuest quest data from:
  1. eqexp packed markdown files (2,600+ walkthroughs across 32 expansions)
  2. eqexp/exp_quests.json & expansion_meta.json
  3. NMS-Release/Release-NMS-Quests (Perl & Lua server ground-truth for 220 zones)
  4. TAC/resources/Zones.ini (Zone display name <-> MacroQuest shortname mapping)

Outputs partitioned Lua files into TAC/resources/triune_quest/:
  - catalog.lua (Lightweight global quest lookup)
  - expansions.lua (Expansion index and metadata)
  - zones/<zone_shortname>.lua (Rich per-zone quest details, dialogues, turn-ins, coordinates, walkthroughs)
"""

import os
import sys
import re
import json
import glob
import configparser

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
EQEXP_DIR = "/home/gennro/Documents/github/eqexp"
NMS_DIR = "/home/gennro/Documents/github/NMS-Release/Release-NMS-Quests"
ZONES_INI = os.path.join(BASE_DIR, "resources", "Zones.ini")
OUT_DIR = os.path.join(BASE_DIR, "resources", "triune_quest")
OUT_ZONES_DIR = os.path.join(OUT_DIR, "zones")

os.makedirs(OUT_ZONES_DIR, exist_ok=True)

# ---------------------------------------------------------------------------
# 1. Load Zones.ini and build normalization map
# ---------------------------------------------------------------------------
print("[1/5] Loading Zones.ini mappings...")
zone_map = {}
ini = configparser.ConfigParser(interpolation=None, strict=False)
if os.path.exists(ZONES_INI):
    ini.read(ZONES_INI)
    for sec in ini.sections():
        for k, v in ini.items(sec):
            clean_k = k.lower().strip()
            short = v.strip().lower()
            zone_map[clean_k] = short

# Manual aliases for modern / variant names
ZONE_ALIASES = {
    "cabilis east": "cabeast",
    "east cabilis": "cabeast",
    "cabilis west": "cabwest",
    "west cabilis": "cabwest",
    "greater faydark": "gfaydark",
    "lesser faydark": "lfaydark",
    "the feerrott": "feerrott",
    "feerrott, the dream": "feerrott2",
    "east freeport": "freeporteast",
    "west freeport": "freeportwest",
    "north freeport": "freportn",
    "east freeport 2.0": "freeporteast",
    "west freeport 2.0": "freeportwest",
    "plane of knowledge": "poknowledge",
    "the plane of knowledge": "poknowledge",
    "the bazaar": "bazaar",
    "the nexus": "nexus",
    "shadowrest": "shadowrest",
    "guild lobby": "guildlobby",
    "guild hall": "guildhall",
    "crescent reach": "crescent",
    "blightfire moors": "blightfire",
    "stone hive": "stonehive",
    "gorukar mesa": "mesa",
    "blackburrow": "blackburrow",
    "highpass hold": "highpass",
    "highkeep": "highkeep",
    "lake rathetear": "lakerathe",
    "rathe mountains": "rathemtn",
    "mountains of rathe": "rathemtn",
    "lake of ill omen": "lakeofillomen",
    "the overthere": "overthere",
    "warsliks woods": "warslikswood",
    "warsliks wood": "warslikswood",
    "timorous deep": "timorous",
    "field of bone": "fieldofbone",
    "swamp of no hope": "swampofnohope",
    "kurn's tower": "kurn",
    "kurns tower": "kurn",
    "dreadlands": "dreadlands",
    "firiona vie": "firiona",
    "frontier mountains": "frontiermtn",
    "skyfire mountains": "skyfire",
    "burning wood": "burningwood",
    "kaesora": "kaesora",
    "dalnir": "dalnir",
    "city of mist": "citymist",
    "charasis": "charasis",
    "howling stones": "charasis",
    "chardok": "chardok",
    "sebilis": "sebilis",
    "old sebilis": "sebilis",
    "cobalt scar": "cobaltscar",
    "western wastes": "westwastes",
    "siren's grotto": "sirens",
    "sirens grotto": "sirens",
    "dragon necropolis": "necropolis",
    "skyshrine": "skyshrine",
    "temple of veeshan": "tofs",
    "sleeper's tomb": "sleeper",
    "sleepers tomb": "sleeper",
    "eastern wastes": "eastwastes",
    "great divide": "greatdivide",
    "the great divide": "greatdivide",
    "icewell keep": "icewell",
    "thurgadin": "thurgadina",
    "kael drakkal": "kael",
    "tower of frozen shadow": "frozenshadow",
    "crystal caverns": "crystal",
    "shadow haven": "shadowhaven",
    "shar vahl": "sharvahl",
    "hollowshade moor": "hollowshade",
    "grimling forest": "grimling",
    "marus seru": "marus",
    "netherbian lair": "netherbian",
    "paludal caverns": "paludal",
    "sanctus seru": "sseru",
    "katta castellum": "katta",
    "the deep": "thedeep",
    "the grey": "thegrey",
    "the maiden's eye": "maiden",
    "maidens eye": "maiden",
    "umbral plains": "umbral",
    "akheva ruins": "akheva",
    "vex thal": "vexthal",
    "ssraeshza temple": "ssratemple",
    "plane of tranquility": "potranquility",
    "plane of disease": "podisease",
    "plane of innovation": "poinnovation",
    "plane of justice": "pojustice",
    "plane of nightmare": "ponightmare",
    "plane of valor": "povalor",
    "plane of storms": "postorms",
    "plane of torment": "potorment",
    "crypt of decay": "codecay",
    "bastion of thunder": "bothunder",
    "halls of honor": "hohonora",
    "plane of tactics": "potactics",
    "plane of air": "poair",
    "plane of water": "powater",
    "plane of fire": "pofire",
    "plane of earth": "poeartha",
    "plane of time": "potimeb",
}

for k, v in ZONE_ALIASES.items():
    zone_map[k] = v

def normalize_zone_name(raw_name):
    if not raw_name:
        return None
    # Strip brackets like [CoV], [ToL], etc.
    cleaned = re.sub(r"\[.*?\]", "", raw_name).strip().lower()
    cleaned = re.sub(r"[^\w\s]", "", cleaned)  # remove apostrophes/punctuation
    cleaned = re.sub(r"\s+", " ", cleaned).strip()
    
    # Check direct
    if cleaned in zone_map:
        return zone_map[cleaned]
    if cleaned.startswith("the "):
        without_the = cleaned[4:].strip()
        if without_the in zone_map:
            return zone_map[without_the]
            
    # Remove subzone/subtitle after comma or colon (e.g. "Argath, Bastion of Illdaera" -> "Argath")
    for sep in [",", ":", "-"]:
        if sep in raw_name:
            part = raw_name.split(sep)[0]
            p_clean = re.sub(r"\[.*?\]", "", part).strip().lower()
            p_clean = re.sub(r"[^\w\s]", "", p_clean).strip()
            if p_clean in zone_map:
                return zone_map[p_clean]
            if p_clean.startswith("the ") and p_clean[4:] in zone_map:
                return zone_map[p_clean[4:]]
                
    return None

# ---------------------------------------------------------------------------
# 2. Index NMS Server Quest Directory
# ---------------------------------------------------------------------------
print("[2/5] Indexing NMS Server Quest Directory...")
nms_npc_index = {}
nms_zone_npcs = {} # { zone_short: [npc_info, ...] }

if os.path.exists(NMS_DIR):
    for zentry in os.listdir(NMS_DIR):
        zpath = os.path.join(NMS_DIR, zentry)
        if not os.path.isdir(zpath):
            continue
        zshort = zentry.lower()
        if zshort not in nms_zone_npcs:
            nms_zone_npcs[zshort] = []
            
        for fname in os.listdir(zpath):
            if fname.endswith(".lua") or fname.endswith(".pl"):
                name_clean = os.path.splitext(fname)[0].replace("_", " ").strip()
                name_lower = name_clean.lower()
                fpath = os.path.join(zpath, fname)
                is_lua = fname.endswith(".lua")
                
                info = {
                    "npc_name": name_clean,
                    "zone": zshort,
                    "fpath": fpath,
                    "is_lua": is_lua
                }
                if name_lower not in nms_npc_index:
                    nms_npc_index[name_lower] = info
                nms_zone_npcs[zshort].append(info)

print(f"      Indexed {len(nms_npc_index)} unique NPCs across {len(nms_zone_npcs)} NMS zones.")

def extract_nms_dialogue_and_items(info):
    """Parse NMS Lua/Perl file for say triggers, hand-ins, and rewards."""
    try:
        content = open(info["fpath"], "r", encoding="utf-8", errors="ignore").read()
    except Exception:
        return [], [], []
        
    triggers = []
    items_required = []
    rewards = []
    
    if info["is_lua"]:
        # Extract say triggers: findi("phrase") or find("phrase")
        say_matches = re.findall(r"find[i]?\([\"\x27]([^\"\x27]+)[\"\x27]\)", content)
        for sm in say_matches:
            if sm not in ["%d", ""] and len(sm) > 1:
                triggers.append(sm.strip())
                
        # Bracketed words in emote/say: [ready to patrol]
        brackets = re.findall(r"\[([A-Za-z0-9\s_\-\x27]{2,30})\]", content)
        for b in brackets:
            if b.lower() not in ["item", "quest", "npc", "zone"] and b not in triggers:
                triggers.append(b.strip())
                
        # Turn in items: item1 = 1234
        trade_items = re.findall(r"item\d+\s*=\s*(\d+)", content)
        comment_items = re.findall(r"--\s*Items?:\s*([^\n\r]+)", content)
        item_names = []
        if comment_items:
            for ci in comment_items[0].split(","):
                item_names.append(ci.strip())
        for idx, tid in enumerate(trade_items):
            iname = item_names[idx] if idx < len(item_names) else f"Item #{tid}"
            items_required.append({"id": int(tid), "name": iname, "count": 1})
            
        # SummonItem(1234)
        summons = re.findall(r"SummonItem\((\d+)\)", content)
        sum_comments = re.findall(r"--\s*Item:\s*([^\n\r]+)", content)
        for idx, sid in enumerate(summons):
            sname = sum_comments[idx].strip() if idx < len(sum_comments) else f"Item #{sid}"
            rewards.append({"id": int(sid), "name": sname, "type": "item"})
            
    else: # Perl (.pl)
        say_matches = re.findall(r"\$text\s*=\s*~/\s*([^/]+)\s*/[i]?", content)
        for sm in say_matches:
            clean_p = re.sub(r"[\^\$\\]", "", sm).strip()
            if len(clean_p) > 1 and clean_p.lower() not in ["hail", ""]:
                triggers.append(clean_p)
                
        brackets = re.findall(r"\[([A-Za-z0-9\s_\-\x27]{2,30})\]", content)
        for b in brackets:
            if b.lower() not in ["item", "quest", "npc", "zone"] and b not in triggers:
                triggers.append(b.strip())
                
        handins = re.findall(r"(\d+)\s*=>\s*(\d+)", content)
        for hid, hcnt in handins:
            items_required.append({"id": int(hid), "name": f"Item #{hid}", "count": int(hcnt)})
            
        summons = re.findall(r"quest::summonitem\((\d+)\)", content)
        for sid in summons:
            rewards.append({"id": int(sid), "name": f"Item #{sid}", "type": "item"})

    unique_triggers = []
    seen = set()
    for t in triggers:
        tl = t.lower()
        if tl not in seen:
            seen.add(tl)
            unique_triggers.append(t)
            
    return unique_triggers, items_required, rewards

# ---------------------------------------------------------------------------
# 3. Load Expansions & Quests from eqexp
# ---------------------------------------------------------------------------
print("[3/5] Loading Expansion Metadata and eqexp Quest Catalog...")
exp_meta = {}
exp_meta_path = os.path.join(EQEXP_DIR, "expansion_meta.json")
if os.path.exists(exp_meta_path):
    exp_meta = json.load(open(exp_meta_path, "r", encoding="utf-8"))

exp_quests = {}
exp_quests_path = os.path.join(EQEXP_DIR, "exp_quests.json")
if os.path.exists(exp_quests_path):
    exp_quests = json.load(open(exp_quests_path, "r", encoding="utf-8"))

quest_to_exp = {}
for exp_num, data in exp_quests.items():
    for qid in data.get("quest_ids", []):
        quest_to_exp[str(qid)] = exp_num

packed_files = glob.glob(os.path.join(EQEXP_DIR, "packed", "*.md"))
print(f"      Found {len(packed_files)} packed quest markdown files.")

re_title = re.compile(r"^#\s+([^\n\r]+)", re.M)
re_meta_line = re.compile(r"\*\*([A-Za-z0-9#\.\s\?]+):\*\*\s*([^\n\r\|]+)")
re_where = re.compile(r"\*\*Where:\*\*\s*\n\s*-\s*\[?(.*?)(?:\]\(http|\[zone=|\n)")
re_who = re.compile(r"\*\*Who:\*\*\s*\n\s*-\s*\[?(.*?)(?:\]\(http|\[npc=|\n)")
re_coords = re.compile(r"(?:at|loc|location|around)\s+([+-]?\d+(?:\.\d+)?)\s*,\s*([+-]?\d+(?:\.\d+)?)(?:\s*,\s*([+-]?\d+(?:\.\d+)?))?", re.I)
re_turn_in = re.compile(r"(?:Hand in|give|turn in)\s+(\d+)?\s*x?\s*([^,\.\n\r]+)", re.I)
re_reward_item = re.compile(r"(?:receive|rewarded with|gives you a[n]?)\s+([A-Z][A-Za-z0-9\s\x27\-]+?)(?:\[item=(\d+)\]|\.|\n)", re.I)

quests_by_zone = {} # { zone_shortname: [quest_data, ...] }
catalog = []

for pfile in packed_files:
    qid = os.path.splitext(os.path.basename(pfile))[0]
    txt = open(pfile, "r", encoding="utf-8", errors="ignore").read()
    
    # Title
    mt = re_title.search(txt)
    title = mt.group(1).strip() if mt else f"Quest {qid}"
    
    # Metadata
    meta = {}
    for mm in re_meta_line.finditer(txt):
        k = mm.group(1).strip()
        v = mm.group(2).strip()
        meta[k] = v
        
    min_lvl = int(meta["Level"]) if meta.get("Level", "").isdigit() else 1
    max_lvl = int(meta["Maximum Level"]) if meta.get("Maximum Level", "").isdigit() else 125
    q_type = meta.get("Quest Type", "Quest")
    repeatable = meta.get("Repeatable", "No").lower().startswith("y")
    group_size = meta.get("Group Size", "Solo")
    
    # Expansion
    exp_num = quest_to_exp.get(qid, "01")
    exp_name = exp_meta.get(exp_num, {}).get("name", f"Expansion {exp_num}")
    
    # Where & Who
    zone_name = None
    mw = re_where.search(txt)
    if mw:
        raw_z = mw.group(1).strip()
        zone_name = re.sub(r"\[.*?\]", "", raw_z).strip()
        
    npc_name = None
    mn = re_who.search(txt)
    if mn:
        raw_n = mn.group(1).strip()
        npc_name = re.sub(r"\[.*?\]", "", raw_n).replace(" _Quests_", "").strip()
        
    # Resolve zone shortname
    zone_short = None
    if zone_name:
        zone_short = normalize_zone_name(zone_name)
        
    if not zone_short and npc_name:
        nl = npc_name.lower().strip()
        if nl in nms_npc_index:
            zone_short = nms_npc_index[nl]["zone"]
            if not zone_name:
                zone_name = nms_npc_index[nl]["zone"].title()
                
    if not zone_short:
        head = txt[:600].lower()
        for nl, ninfo in nms_npc_index.items():
            if len(nl) > 5 and nl in head:
                zone_short = ninfo["zone"]
                if not npc_name:
                    npc_name = ninfo["npc_name"]
                if not zone_name:
                    zone_name = zone_short.title()
                break
                
    if not zone_short:
        zone_short = "global"
        if not zone_name:
            zone_name = "Norrath (Global)"
            
    # Coordinates
    coords = None
    mc = re_coords.search(txt)
    if mc:
        y_val = float(mc.group(1))
        x_val = float(mc.group(2))
        z_val = float(mc.group(3)) if mc.group(3) else 0.0
        coords = {"y": y_val, "x": x_val, "z": z_val}
        
    # Dialogue Triggers
    triggers = []
    says = re.findall(r"You say,\s*[\x27\"]([^\x27\"]+)[\x27\"]", txt)
    for s in says:
        clean_s = s.strip()
        if clean_s and clean_s not in triggers:
            triggers.append(clean_s)
            
    brackets = re.findall(r"\[([A-Za-z0-9\s_\-\x27]{3,40})\]", txt)
    for b in brackets:
        if b.lower() not in ["quest", "item", "npc", "zone", "cov", "tol", "ros", "tov", "nos"] and b not in triggers:
            triggers.append(b.strip())
            
    # Required Items
    items_required = []
    for mti in re_turn_in.finditer(txt):
        cnt_str = mti.group(1)
        cnt = int(cnt_str) if cnt_str and cnt_str.isdigit() else 1
        iname = mti.group(2).strip()
        iname = re.sub(r"\[item=\d+\]", "", iname).strip()
        if len(iname) > 2 and len(iname) < 50:
            items_required.append({"name": iname, "count": cnt})
            
    # Rewards
    rewards = []
    item_links = re.findall(r"-\s*([A-Za-z0-9\s\x27\-]+?)\s*\[item=(\d+)\]", txt)
    for iname, iid in item_links:
        rewards.append({"id": int(iid), "name": iname.strip(), "type": "item"})
        
    faction_hits = []
    fh_matches = re.findall(r"standing with\s+([A-Za-z0-9\s\x27\-]+?)\s+has been adjusted by\s+([+-]?\d+)", txt)
    for fname, fadj in fh_matches:
        faction_hits.append({"name": fname.strip(), "change": int(fadj)})
        
    # Enrich with NMS
    if npc_name and npc_name.lower() in nms_npc_index:
        nms_info = nms_npc_index[npc_name.lower()]
        nms_trigs, nms_items, nms_rewards = extract_nms_dialogue_and_items(nms_info)
        for nt in nms_trigs:
            if nt not in triggers:
                triggers.append(nt)
        if not items_required and nms_items:
            items_required = nms_items
        if not rewards and nms_rewards:
            rewards = nms_rewards

    walkthrough = txt
    w_idx = txt.find("## Quest Text / Walkthrough")
    if w_idx != -1:
        walkthrough = txt[w_idx + len("## Quest Text / Walkthrough"):].strip()
    walkthrough = re.sub(r"!\[.*?\]\(.*?\)", "", walkthrough)
    walkthrough = re.sub(r"\[(.*?)\]\(.*?\)", r"\1", walkthrough)
    walkthrough = walkthrough.replace("&nbsp;", " ").strip()
    
    quest_entry = {
        "id": qid,
        "title": title,
        "zone": zone_short,
        "zone_name": zone_name or zone_short.title(),
        "exp": exp_num,
        "exp_name": exp_name,
        "min_lvl": min_lvl,
        "max_lvl": max_lvl,
        "quest_type": q_type,
        "repeatable": repeatable,
        "group_size": group_size,
        "npc": npc_name or "Unknown",
        "loc": coords,
        "triggers": triggers[:8],
        "items_required": items_required[:6],
        "rewards": rewards[:6],
        "factions": faction_hits[:6],
        "walkthrough": walkthrough
    }
    
    if zone_short not in quests_by_zone:
        quests_by_zone[zone_short] = []
    quests_by_zone[zone_short].append(quest_entry)
    
    catalog.append({
        "id": qid,
        "title": title,
        "zone": zone_short,
        "zone_name": zone_name or zone_short.title(),
        "exp": exp_num,
        "exp_name": exp_name,
        "min_lvl": min_lvl,
        "max_lvl": max_lvl,
        "quest_type": q_type,
        "repeatable": repeatable,
        "npc": npc_name or "",
        "has_loc": coords is not None
    })

print(f"      Mapped {len(catalog)} quests across {len(quests_by_zone)} zones.")

# ---------------------------------------------------------------------------
# 4. Generate Lua Files
# ---------------------------------------------------------------------------
print("[4/5] Emitting partitioned Lua database files...")

def lua_escape(s):
    if s is None:
        return '""'
    s = str(s).replace("\u2014", "--").replace("\u2013", "-").replace("\u2019", "'").replace("\u2018", "'").replace("\u201c", '"').replace("\u201d", '"')
    out = []
    for ch in s:
        if ch == '\\':
            out.append('\\\\')
        elif ch == '"':
            out.append('\\"')
        elif ch == '\n':
            out.append('\\n')
        elif ch == '\r':
            out.append('\\r')
        elif ch == '\t':
            out.append('\\t')
        elif ord(ch) < 32:
            out.append(f"\\{ord(ch):03d}")
        else:
            out.append(ch)
    return '"' + "".join(out) + '"'

catalog_path = os.path.join(OUT_DIR, "catalog.lua")
with open(catalog_path, "w", encoding="utf-8") as f:
    f.write("-- ============================================================================\n")
    f.write("-- TRIUNE QUEST GUIDE: Master Catalog Index (Lightweight Search Table)\n")
    f.write("-- Generated automatically by build_triune_quest.py\n")
    f.write("-- ============================================================================\n\n")
    f.write("return {\n")
    for q in catalog:
        f.write("  {\n")
        f.write(f"    id = {lua_escape(q['id'])},\n")
        f.write(f"    title = {lua_escape(q['title'])},\n")
        f.write(f"    zone = {lua_escape(q['zone'])},\n")
        f.write(f"    zone_name = {lua_escape(q['zone_name'])},\n")
        f.write(f"    exp = {lua_escape(q['exp'])},\n")
        f.write(f"    exp_name = {lua_escape(q['exp_name'])},\n")
        f.write(f"    min_lvl = {q['min_lvl']},\n")
        f.write(f"    max_lvl = {q['max_lvl']},\n")
        f.write(f"    quest_type = {lua_escape(q['quest_type'])},\n")
        f.write(f"    repeatable = {'true' if q['repeatable'] else 'false'},\n")
        f.write(f"    npc = {lua_escape(q['npc'])},\n")
        f.write(f"    has_loc = {'true' if q['has_loc'] else 'false'},\n")
        f.write("  },\n")
    f.write("}\n")

expansions_path = os.path.join(OUT_DIR, "expansions.lua")
with open(expansions_path, "w", encoding="utf-8") as f:
    f.write("-- ============================================================================\n")
    f.write("-- TRIUNE QUEST GUIDE: Expansion Index (00 - 32)\n")
    f.write("-- ============================================================================\n\n")
    f.write("return {\n")
    for exp_id in sorted(exp_meta.keys(), key=lambda x: int(x)):
        info = exp_meta[exp_id]
        qcount = len(exp_quests.get(exp_id, {}).get("quest_ids", []))
        f.write("  {\n")
        f.write(f"    id = {lua_escape(exp_id)},\n")
        f.write(f"    name = {lua_escape(info.get('name', 'Unknown'))},\n")
        f.write(f"    release = {lua_escape(info.get('release', ''))},\n")
        f.write(f"    level_cap = {lua_escape(info.get('level_cap', '125'))},\n")
        f.write(f"    quest_count = {qcount},\n")
        f.write("  },\n")
    f.write("}\n")

for zshort, qlist in quests_by_zone.items():
    zfile = os.path.join(OUT_ZONES_DIR, f"{zshort}.lua")
    zdisplay = qlist[0]["zone_name"] if qlist else zshort.title()
    with open(zfile, "w", encoding="utf-8") as f:
        f.write("-- ============================================================================\n")
        f.write(f"-- TRIUNE QUEST GUIDE: Zone Package for {zdisplay} ({zshort})\n")
        f.write(f"-- Total Quests: {len(qlist)}\n")
        f.write("-- ============================================================================\n\n")
        f.write("return {\n")
        f.write(f"  zone = {lua_escape(zshort)},\n")
        f.write(f"  zone_name = {lua_escape(zdisplay)},\n")
        f.write("  quests = {\n")
        for q in qlist:
            f.write("    {\n")
            f.write(f"      id = {lua_escape(q['id'])},\n")
            f.write(f"      title = {lua_escape(q['title'])},\n")
            f.write(f"      exp = {lua_escape(q['exp'])},\n")
            f.write(f"      exp_name = {lua_escape(q['exp_name'])},\n")
            f.write(f"      min_lvl = {q['min_lvl']},\n")
            f.write(f"      max_lvl = {q['max_lvl']},\n")
            f.write(f"      quest_type = {lua_escape(q['quest_type'])},\n")
            f.write(f"      repeatable = {'true' if q['repeatable'] else 'false'},\n")
            f.write(f"      group_size = {lua_escape(q['group_size'])},\n")
            f.write(f"      npc = {lua_escape(q['npc'])},\n")
            
            if q["loc"]:
                f.write(f"      loc = {{ y = {q['loc']['y']}, x = {q['loc']['x']}, z = {q['loc']['z']} }},\n")
            else:
                f.write("      loc = nil,\n")
                
            f.write("      triggers = {\n")
            for tr in q["triggers"]:
                f.write(f"        {lua_escape(tr)},\n")
            f.write("      },\n")
            
            f.write("      items_required = {\n")
            for item in q["items_required"]:
                iid = item.get("id")
                iid_str = f"id = {iid}, " if iid else ""
                f.write(f"        {{ {iid_str}name = {lua_escape(item['name'])}, count = {item.get('count', 1)} }},\n")
            f.write("      },\n")
            
            f.write("      rewards = {\n")
            for rw in q["rewards"]:
                f.write(f"        {{ id = {rw.get('id', 0)}, name = {lua_escape(rw['name'])}, type = {lua_escape(rw.get('type', 'item'))} }},\n")
            f.write("      },\n")
            
            f.write("      factions = {\n")
            for fc in q["factions"]:
                f.write(f"        {{ name = {lua_escape(fc['name'])}, change = {fc['change']} }},\n")
            f.write("      },\n")
            
            wt = q["walkthrough"]
            if len(wt) > 25000:
                wt = wt[:25000] + "\n\n...[Walkthrough truncated for in-game performance]..."
            f.write(f"      walkthrough = {lua_escape(wt)},\n")
            
            f.write("    },\n")
        f.write("  },\n")
        f.write("}\n")

print(f"[5/5] Done! Wrote {len(quests_by_zone)} zone files, catalog.lua, and expansions.lua.")
print(f"      Output directory: {OUT_DIR}")
