#!/usr/bin/env python3
"""
tools/build_gamedb.py - build the offline Triune game database (items, NPCs,
spells) that the `gamedb` plugin reads in game.

Inputs
  --sql     a mysqldump of the Project Triune (EQEmu) server database
  --quests  the server's quest script tree (Perl / Lua, one folder per zone)
  --out     the output folder (default: TAC/resources/gamedb)

Outputs (all plain text, no runtime dependencies in Lua)
  <kind>.idx        one line per searchable entry; loaded in game in chunks
  <kind>.<n>.dat    one line per record ("key=value|key=value|..."), chunked
                    so no single file passes GitHub's size limits; the index
                    carries "chunk:offset" so a lookup is one seek + one read
  manifest.txt      build date and record counts

Encoding: every text value has these characters escaped before it is written,
so the Lua side can split on the raw separators and unescape only the leaves:
  \\ -> \\\\   | -> \\p   ; -> \\s   ~ -> \\t   , -> \\c   : -> \\k   newline -> \\n
List fields use ';' between entries, '~' between an entry's fields, ',' between
items of a nested list and ':' between a nested item's fields.

The script streams the dump (a row is one line in mysqldump output) and only
keeps the columns it needs, so the 500 MB dump never sits in memory.
"""
import argparse
import os
import re
import sys
import time
from collections import defaultdict

# ---------------------------------------------------------------------------
# SQL dump reading
# ---------------------------------------------------------------------------
VALUE_RE = re.compile(r"'((?:[^'\\]|\\.)*)'|(NULL)|(-?[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)")
UNESC_RE = re.compile(r"\\(.)")
UNESC_MAP = {'n': '\n', 'r': '\r', 't': '\t', '0': '\0', 'Z': '\x1a'}


def _unescape_sql(s):
    return UNESC_RE.sub(lambda m: UNESC_MAP.get(m.group(1), m.group(1)), s)


def read_table_columns(path, table):
    """Column names of `table` from its CREATE TABLE block."""
    cols = []
    marker = 'CREATE TABLE `%s` (' % table
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
            if line.startswith(marker):
                for line in f:
                    s = line.strip()
                    if s.startswith('`'):
                        cols.append(s[1:s.index('`', 1)])
                    elif s.startswith(')'):
                        return cols
                break
    raise SystemExit('table %s not found in %s' % (table, path))


class TableReader:
    """Streams INSERT rows for one or more tables out of a mysqldump file.

    handlers: {table: callback(values_list)} - values are str / int / float /
    None in column order. Rows failing the column-count sanity check are
    reported and skipped.
    """

    def __init__(self, path):
        self.path = path
        self._cols = {}

    def columns(self, table):
        if table not in self._cols:
            self._cols[table] = read_table_columns(self.path, table)
        return self._cols[table]

    def run(self, handlers):
        want = {t: len(self.columns(t)) for t in handlers}
        bad = defaultdict(int)
        cur = None
        ncols = 0
        with open(self.path, 'r', encoding='utf-8', errors='replace') as f:
            for line in f:
                if cur is not None:
                    if line.startswith('('):
                        vals = self._parse_row(line)
                        if len(vals) == ncols:
                            handlers[cur](vals)
                        else:
                            bad[cur] += 1
                        continue
                    cur = None
                if line.startswith('INSERT INTO `'):
                    t = line[13:line.index('`', 13)]
                    if t in want:
                        cur = t
                        ncols = want[t]
                        rest = line[line.index('VALUES') + 6:].lstrip()
                        if rest.startswith('('):
                            # single-line statement: rows follow on this line
                            for vals in self._split_rows(rest, ncols):
                                handlers[cur](vals)
                            cur = None
        for t, n in bad.items():
            print('  ! %d rows of %s skipped (column count mismatch)' % (n, t))

    @staticmethod
    def _parse_row(line):
        out = []
        for s, null, num in VALUE_RE.findall(line):
            if null:
                out.append(None)
            elif num:
                out.append(float(num) if ('.' in num or 'e' in num or 'E' in num) else int(num))
            else:
                out.append(_unescape_sql(s) if '\\' in s else s)
        return out

    @classmethod
    def _split_rows(cls, text, ncols):
        vals = cls._parse_row(text)
        for i in range(0, len(vals) - len(vals) % ncols, ncols):
            yield vals[i:i + ncols]


# ---------------------------------------------------------------------------
# Output encoding
# ---------------------------------------------------------------------------
ESC_TABLE = str.maketrans({'\\': '\\\\', '|': '\\p', ';': '\\s', '~': '\\t', ',': '\\c', ':': '\\k', '\n': '\\n', '\r': ''})


def esc(v):
    return str(v).translate(ESC_TABLE)


def fmt_num(v):
    if isinstance(v, float):
        if v == int(v):
            return str(int(v))
        return ('%.3f' % v).rstrip('0').rstrip('.')
    return str(v)


class ChunkWriter:
    """Writes .dat lines into numbered chunk files under a size cap and hands
    back (chunk, offset) for the index. `group_start()` guarantees that the
    lines written until the next group_start land in the same chunk."""

    def __init__(self, out_dir, kind, cap_bytes):
        self.out_dir, self.kind, self.cap = out_dir, kind, cap_bytes
        self.chunk = 0
        self.f = None
        self.pos = 0
        self.count = 0
        self._open()

    def _open(self):
        if self.f:
            self.f.close()
        self.chunk += 1
        self.f = open(os.path.join(self.out_dir, '%s.%d.dat' % (self.kind, self.chunk)), 'w', encoding='utf-8', newline='\n')
        self.pos = 0

    def group_start(self, approx_bytes=0):
        if self.pos > 0 and self.pos + approx_bytes > self.cap:
            self._open()

    def write(self, line):
        data = line + '\n'
        at = (self.chunk, self.pos)
        self.f.write(data)
        self.pos += len(data.encode('utf-8'))
        self.count += 1
        return at

    def close(self):
        if self.f:
            self.f.close()
            self.f = None


class Raw(str):
    """A value that is already encoded (a list field) - written as is."""


def kv(fields):
    """fields: list of (key, value) - None / '' / 0 values are omitted."""
    parts = []
    for k, v in fields:
        if v is None or v == '' or v == 0 or v == '0':
            continue
        if isinstance(v, Raw):
            parts.append('%s=%s' % (k, v))
        else:
            parts.append('%s=%s' % (k, esc(v) if isinstance(v, str) else fmt_num(v)))
    return '|'.join(parts)


# ---------------------------------------------------------------------------
# Static decode tables shared with the Lua side (kept here for names only)
# ---------------------------------------------------------------------------
CONTAINER_TYPES = {
    10: 'Toolbox', 11: 'Research Table', 12: 'Mortar and Pestle', 13: 'Self-Dusting Container', 14: 'Oven', 15: 'Oven', 16: 'Loom', 17: 'Forge',
    18: 'Fletching Kit', 19: 'Brew Barrel', 20: 'Jeweler\'s Kit', 21: 'Pottery Wheel', 22: 'Kiln', 24: 'Wizard Research Table',
    25: 'Magician Research Table', 26: 'Necromancer Research Table', 27: 'Enchanter Research Table', 30: 'Experimental Table',
    31: 'High Elf Forge', 32: 'Dark Elf Forge', 33: 'Ogre Forge', 34: 'Dwarf Forge', 35: 'Gnome Forge', 36: 'Barbarian Forge',
    38: 'Iksar Forge', 39: 'Human Forge', 41: 'Halfling Loom', 42: 'Erudite Loom', 43: 'Wood Elf Loom', 44: 'Wood Elf Fletching Kit',
    45: 'Iksar Pottery Wheel', 47: 'Troll Forge', 48: 'Wood Elf Forge', 49: 'Halfling Forge', 50: 'Erudite Forge', 53: 'Augmentation Pool',
}

# tradeskill_recipe.tradeskill uses skill ids; 75 is the "quest combine"
# pseudo-skill in the EQEmu data (it is Remove Traps in the client's skill
# enum, which no item references). The Lua side decodes recipe tradeskills
# through D.tradeskillName(), which maps 75 (and the legacy 100) to
# 'Quest Combine' - keep the two in step when editing either.
TRADESKILLS = {
    55: 'Fishing', 56: 'Make Poison', 57: 'Tinkering', 58: 'Research', 59: 'Alchemy', 60: 'Baking', 61: 'Tailoring',
    63: 'Blacksmithing', 64: 'Fletching', 65: 'Brewing', 68: 'Jewelry Making', 69: 'Pottery', 75: 'Quest Combine',
    100: 'Quest Combine',
}

# ---------------------------------------------------------------------------
# Column selections
# ---------------------------------------------------------------------------
ITEM_COLS = [
    'name', 'lore', 'itemtype', 'icon', 'weight', 'size', 'slots', 'classes', 'races', 'deity',
    'ac', 'hp', 'mana', 'endur', 'astr', 'asta', 'aagi', 'adex', 'acha', 'aint', 'awis',
    'heroic_str', 'heroic_sta', 'heroic_agi', 'heroic_dex', 'heroic_cha', 'heroic_int', 'heroic_wis',
    'mr', 'cr', 'dr', 'fr', 'pr', 'svcorruption', 'heroic_mr', 'heroic_cr', 'heroic_dr', 'heroic_fr', 'heroic_pr', 'heroic_svcorrup',
    'attack', 'haste', 'regen', 'manaregen', 'enduranceregen', 'damage', 'delay', 'range',
    'elemdmgtype', 'elemdmgamt', 'banedmgbody', 'banedmgrace', 'banedmgamt', 'banedmgraceamt', 'backstabdmg',
    'skillmodtype', 'skillmodvalue', 'skillmodmax', 'accuracy', 'avoidance', 'shielding', 'spellshield', 'strikethrough',
    'stunresist', 'dotshielding', 'dsmitigation', 'damageshield', 'combateffects', 'healamt', 'spelldmg', 'clairvoyance',
    'reqlevel', 'reclevel', 'recskill', 'magic', 'nodrop', 'norent', 'loregroup', 'artifactflag', 'attuneable', 'questitemflag',
    'heirloom', 'placeable', 'fvnodrop', 'notransfer', 'nopet', 'epicitem', 'stackable', 'stacksize',
    'bagtype', 'bagslots', 'bagsize', 'bagwr', 'book', 'booktype', 'filename', 'maxcharges',
    'clickeffect', 'clicktype', 'clicklevel', 'clicklevel2', 'clickname', 'casttime', 'recastdelay', 'recasttype',
    'proceffect', 'proctype', 'proclevel', 'proclevel2', 'procrate', 'procname',
    'worneffect', 'worntype', 'wornlevel', 'wornlevel2', 'wornname',
    'focuseffect', 'focustype', 'focuslevel', 'focuslevel2', 'focusname',
    'scrolleffect', 'scrolltype', 'scrolllevel', 'scrolllevel2', 'scrollname',
    'bardeffect', 'bardeffecttype', 'bardlevel', 'bardlevel2', 'bardname',
    'augtype', 'augrestrict', 'augslot1type', 'augslot2type', 'augslot3type', 'augslot4type', 'augslot5type', 'augslot6type',
    'augslot1visible', 'augslot2visible', 'augslot3visible', 'augslot4visible', 'augslot5visible', 'augslot6visible', 'augdistiller',
    'price', 'ldontheme', 'ldonprice', 'pointtype', 'tradeskills', 'benefitflag',
    'evoitem', 'evoid', 'evolvinglevel', 'evomax', 'expendablearrow', 'powersourcecapacity', 'light',
]

NPC_COLS = [
    'name', 'lastname', 'level', 'maxlevel', 'race', 'class', 'bodytype', 'gender', 'texture', 'size', 'hp', 'mana', 'AC',
    'mindmg', 'maxdmg', 'attack_count', 'attack_delay', 'attack_speed', 'runspeed', 'hp_regen_rate', 'mana_regen_rate',
    'MR', 'CR', 'DR', 'FR', 'PR', 'Corrup', 'PhR', 'STR', 'STA', 'DEX', 'AGI', '_INT', 'WIS', 'CHA', 'ATK', 'Accuracy', 'Avoidance',
    'special_abilities', 'npcspecialattks', 'see_invis', 'see_invis_undead', 'see_hide', 'see_improved_hide',
    'aggroradius', 'assistradius', 'npc_aggro', 'rare_spawn', 'raid_target', 'isquest', 'trackable', 'findable',
    'merchant_id', 'loottable_id', 'npc_spells_id', 'npc_faction_id', 'exp_mod', 'slow_mitigation', 'spawn_limit',
    'unique_spawn_by_name', 'version', 'skip_global_loot', 'always_aggro', 'untargetable', 'heroic_strikethrough',
]

SPELL_COLS = [
    'name', 'mana', 'cast_time', 'recast_time', 'recovery_time', 'range', 'aoerange', 'pushback', 'pushup',
    'targettype', 'resisttype', 'basediff', 'skill', 'buffduration', 'buffdurationformula', 'spell_category',
    'teleport_zone',
    'components1', 'components2', 'components3', 'components4', 'component_counts1', 'component_counts2', 'component_counts3', 'component_counts4',
    'icon', 'new_icon', 'descnum', 'typedescnum', 'effectdescnum', 'zonetype', 'numhits', 'numhitstype', 'aemaxtargets', 'maxtargets',
    'spellgroup', 'rank', 'viral_targets', 'viral_timer', 'can_mgb', 'nodispell', 'uninterruptable', 'disallow_sit', 'short_buff_box',
    'min_dist', 'max_dist', 'min_range', 'songcap', 'npc_no_los', 'reflectable', 'bonushate', 'pcnpc_only_flag', 'cast_not_standing',
    'persistdeath', 'not_extendable', 'no_partial_resist', 'dot_stacking_exempt', 'EndurCost', 'EndurTimerIndex', 'IsDiscipline',
    'HateAdded', 'EndurUpkeep', 'goodEffect',
]

# Same order EQEmu uses for classes1..classes16
CLASS_ABBR = ['WAR', 'CLR', 'PAL', 'RNG', 'SHD', 'DRU', 'MNK', 'BRD', 'ROG', 'SHM', 'NEC', 'WIZ', 'MAG', 'ENC', 'BST', 'BER']


def npc_display_name(raw):
    return raw.lstrip('#').replace('_', ' ').replace('-', '-').strip() if raw else ''


def norm_npc_key(raw):
    return raw.lstrip('#').replace(' ', '_').lower() if raw else ''


# ---------------------------------------------------------------------------
# Quest script index
# ---------------------------------------------------------------------------
SUMMON_RE = re.compile(r'(?:quest::summonitem|SummonItem)\s*\(')
HANDIN_RE = re.compile(r'(?:check_handin|check_turn_in)\s*\(')
NUM_RE = re.compile(r'\b(\d{3,7})\b')


def _call_args(text, start):
    """Text inside the parens of a call whose '(' is at text[start-1]."""
    depth, i = 1, start
    while i < len(text) and depth:
        c = text[i]
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
        i += 1
    return text[start:i - 1]


def scan_quests(root):
    """Returns {(zone, npckey): {'rewards': set(ids), 'handins': set(ids)}}.
    npckey is a lowercased underscore name, or an int NPC id for numeric
    file names. zone is the folder name ('global' for global scripts)."""
    out = {}
    if not root or not os.path.isdir(root):
        return out
    files = 0
    for zone in sorted(os.listdir(root)):
        zdir = os.path.join(root, zone)
        if not os.path.isdir(zdir):
            continue
        for fname in os.listdir(zdir):
            if not (fname.endswith('.pl') or fname.endswith('.lua')):
                continue
            stem = fname[:fname.rindex('.')]
            if stem in ('script_init', 'default', 'player', 'global_player', 'global_npc', 'zone'):
                continue
            key = int(stem) if stem.isdigit() else norm_npc_key(stem)
            try:
                with open(os.path.join(zdir, fname), 'r', encoding='utf-8', errors='replace') as f:
                    text = f.read()
            except OSError:
                continue
            files += 1
            rewards, handins = set(), set()
            for m in SUMMON_RE.finditer(text):
                for n in NUM_RE.findall(_call_args(text, m.end())):
                    rewards.add(int(n))
            for m in HANDIN_RE.finditer(text):
                for n in NUM_RE.findall(_call_args(text, m.end())):
                    handins.add(int(n))
            if rewards or handins:
                entry = out.setdefault((zone, key), {'rewards': set(), 'handins': set()})
                entry['rewards'] |= rewards
                entry['handins'] |= handins
    print('  quest scripts scanned: %d, NPCs with item refs: %d' % (files, len(out)))
    return out


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--sql', required=True, help='mysqldump .sql of the server database')
    ap.add_argument('--quests', default=None, help='quest script root (one folder per zone)')
    ap.add_argument('--out', default=os.path.join(os.path.dirname(__file__), '..', 'TAC', 'resources', 'gamedb'))
    ap.add_argument('--chunk-mb', type=int, default=40, help='max size of one .dat chunk')
    ap.add_argument('--max-list', type=int, default=60, help='cap for per-record cross-reference lists')
    args = ap.parse_args()

    out_dir = os.path.abspath(args.out)
    os.makedirs(out_dir, exist_ok=True)
    for old in os.listdir(out_dir):
        if old.endswith('.dat') or old.endswith('.idx') or old == 'manifest.txt':
            os.remove(os.path.join(out_dir, old))
    cap = args.chunk_mb * 1024 * 1024
    MAXL = args.max_list
    t0 = time.time()
    rd = TableReader(args.sql)

    def col_index(table, names):
        # column names are matched case-insensitively (items.Name, npc_types.AC)
        cols = [c.lower() for c in rd.columns(table)]
        idx = {}
        for n in names:
            if n.lower() in cols:
                idx[n] = cols.index(n.lower())
        missing = [n for n in names if n not in idx]
        if missing:
            print('  note: %s lacks columns %s' % (table, ', '.join(missing)))
        return idx

    # ---- pass 1: names + small reference tables --------------------------
    print('pass 1: reference tables')
    item_name = {}
    item_icon = {}
    npc_rows = {}          # id -> dict of NPC_COLS
    zone_long = {}
    zone_id_short = {}
    lootdrop_entries = defaultdict(list)   # lootdrop_id -> [(item_id, chance, multiplier, minlvl, maxlvl)]
    loottable_entries = defaultdict(list)  # loottable_id -> [(lootdrop_id, multiplier, droplimit, mindrop, probability)]
    merchant_items = defaultdict(list)     # merchant_id -> [item_id]
    recipes = {}                           # recipe_id -> dict
    recipe_entries = defaultdict(list)     # recipe_id -> [(item_id, successcount, componentcount, iscontainer)]
    spawnentry = defaultdict(list)         # npcID -> [(spawngroupID, chance)]
    spawn2 = defaultdict(list)             # spawngroupID -> [(zone, respawntime, enabled)]
    npc_spell_lists = defaultdict(list)    # npc_spells_id -> [(spellid, type, minlevel, maxlevel)]
    npc_spells_parent = {}                 # npc_spells_id -> parent_list
    npc_faction = {}                       # id -> (name, primaryfaction)
    npc_faction_hits = defaultdict(list)   # id -> [(faction_id, value)]
    faction_name = {}
    forage = defaultdict(list)             # item_id -> [(zoneid, chance)]
    fishing = defaultdict(list)
    ground = defaultdict(list)             # item_id -> [zoneid]

    ic = col_index('items', ['id', 'name', 'icon'])
    nc = col_index('npc_types', ['id'] + NPC_COLS)
    zc = col_index('zone', ['zoneidnumber', 'short_name', 'long_name', 'version'])
    lde = col_index('lootdrop_entries', ['lootdrop_id', 'item_id', 'chance', 'multiplier', 'npc_min_level', 'npc_max_level'])
    lte = col_index('loottable_entries', ['loottable_id', 'lootdrop_id', 'multiplier', 'droplimit', 'mindrop', 'probability'])
    mc = col_index('merchantlist', ['merchantid', 'item', 'slot'])
    trc = col_index('tradeskill_recipe', ['id', 'name', 'tradeskill', 'skillneeded', 'trivial', 'nofail', 'must_learn', 'learned_by_item_id', 'quest', 'enabled', 'notes'])
    tre = col_index('tradeskill_recipe_entries', ['recipe_id', 'item_id', 'successcount', 'componentcount', 'iscontainer', 'failcount', 'salvagecount'])
    sec = col_index('spawnentry', ['spawngroupID', 'npcID', 'chance'])
    s2c = col_index('spawn2', ['spawngroupID', 'zone', 'respawntime', 'enabled'])
    nsc = col_index('npc_spells', ['id', 'parent_list'])
    nsec = col_index('npc_spells_entries', ['npc_spells_id', 'spellid', 'type', 'minlevel', 'maxlevel'])
    nfc = col_index('npc_faction', ['id', 'name', 'primaryfaction'])
    nfec = col_index('npc_faction_entries', ['npc_faction_id', 'faction_id', 'value'])
    flc = col_index('faction_list', ['id', 'name'])
    foc = col_index('forage', ['zoneid', 'Itemid', 'chance'])
    fic = col_index('fishing', ['zoneid', 'Itemid', 'chance'])
    gsc = col_index('ground_spawns', ['zoneid', 'item'])

    def h_items_names(v):
        item_name[v[ic['id']]] = v[ic['name']] or ''
        item_icon[v[ic['id']]] = v[ic['icon']] or 0

    def h_npc(v):
        npc_rows[v[nc['id']]] = {k: v[i] for k, i in nc.items() if k != 'id'}

    def h_zone(v):
        short = v[zc['short_name']]
        if short and (short not in zone_long or (v[zc.get('version', 0)] or 0) == 0):
            zone_long[short] = v[zc['long_name']] or short
            zone_id_short[v[zc['zoneidnumber']]] = short

    def h_lde(v):
        lootdrop_entries[v[lde['lootdrop_id']]].append((v[lde['item_id']], float(v[lde['chance']] or 0), int(v[lde['multiplier']] or 1),
                                                       int(v[lde['npc_min_level']] or 0), int(v[lde['npc_max_level']] or 0)))

    def h_lte(v):
        loottable_entries[v[lte['loottable_id']]].append((v[lte['lootdrop_id']], int(v[lte['multiplier']] or 1), int(v[lte['droplimit']] or 0),
                                                         int(v[lte['mindrop']] or 0), float(v[lte['probability']] or 0)))

    def h_merch(v):
        merchant_items[v[mc['merchantid']]].append((v[mc['slot']] or 0, v[mc['item']]))

    def h_recipe(v):
        if trc.get('enabled') is not None and not v[trc['enabled']]:
            return
        recipes[v[trc['id']]] = {k: v[i] for k, i in trc.items()}

    def h_recipe_entry(v):
        recipe_entries[v[tre['recipe_id']]].append((v[tre['item_id']], int(v[tre['successcount']] or 0), int(v[tre['componentcount']] or 0),
                                                   int(v[tre['iscontainer']] or 0)))

    def h_spawnentry(v):
        spawnentry[v[sec['npcID']]].append((v[sec['spawngroupID']], float(v[sec['chance']] or 0)))

    def h_spawn2(v):
        enabled = v[s2c['enabled']] if 'enabled' in s2c else 1
        spawn2[v[s2c['spawngroupID']]].append((v[s2c['zone']], int(v[s2c['respawntime']] or 0), int(enabled if enabled is not None else 1)))

    def h_npc_spells(v):
        npc_spells_parent[v[nsc['id']]] = v[nsc['parent_list']] or 0

    def h_npc_spells_entries(v):
        npc_spell_lists[v[nsec['npc_spells_id']]].append((v[nsec['spellid']], int(v[nsec['type']] or 0), int(v[nsec['minlevel']] or 0), int(v[nsec['maxlevel']] or 0)))

    def h_npc_faction(v):
        npc_faction[v[nfc['id']]] = (v[nfc['name']] or '', v[nfc['primaryfaction']] or 0)

    def h_npc_faction_entries(v):
        npc_faction_hits[v[nfec['npc_faction_id']]].append((v[nfec['faction_id']], int(v[nfec['value']] or 0)))

    def h_faction_list(v):
        faction_name[v[flc['id']]] = v[flc['name']] or ''

    def h_forage(v):
        forage[v[foc['Itemid']]].append((v[foc['zoneid']], float(v[foc['chance']] or 0)))

    def h_fishing(v):
        fishing[v[fic['Itemid']]].append((v[fic['zoneid']], float(v[fic['chance']] or 0)))

    def h_ground(v):
        # one entry per zone: a zone with several ground spawn points of the
        # same item must not list that zone repeatedly
        zones = ground[v[gsc['item']]]
        zid = v[gsc['zoneid']]
        if zid not in zones:
            zones.append(zid)

    rd.run({
        'items': h_items_names, 'npc_types': h_npc, 'zone': h_zone, 'lootdrop_entries': h_lde, 'loottable_entries': h_lte,
        'merchantlist': h_merch, 'tradeskill_recipe': h_recipe, 'tradeskill_recipe_entries': h_recipe_entry,
        'spawnentry': h_spawnentry, 'spawn2': h_spawn2, 'npc_spells': h_npc_spells, 'npc_spells_entries': h_npc_spells_entries,
        'npc_faction': h_npc_faction, 'npc_faction_entries': h_npc_faction_entries, 'faction_list': h_faction_list,
        'forage': h_forage, 'fishing': h_fishing, 'ground_spawns': h_ground,
    })
    print('  items %d, npcs %d, zones %d, lootdrops %d, loottables %d, recipes %d  (%.0fs)' % (
        len(item_name), len(npc_rows), len(zone_long), len(lootdrop_entries), len(loottable_entries), len(recipes), time.time() - t0))

    # ---- derived structures ------------------------------------------------
    print('deriving cross references')

    def npc_name(nid):
        r = npc_rows.get(nid)
        return npc_display_name(r['name']) if r else ('NPC %d' % nid)

    # NPC -> zones: {zone: [count, min_respawn, max_chance]}
    npc_zones = {}
    for nid, groups in spawnentry.items():
        zones = {}
        for gid, chance in groups:
            for zone, respawn, enabled in spawn2.get(gid, ()):
                if not enabled or not zone:
                    continue
                z = zones.setdefault(zone, [0, respawn, chance])
                z[0] += 1
                z[1] = min(z[1], respawn) if z[1] else respawn
                z[2] = max(z[2], chance)
        if zones:
            npc_zones[nid] = zones

    def npc_zone_short(nid):
        zones = npc_zones.get(nid)
        if not zones:
            return ''
        return max(zones.items(), key=lambda kv_: (kv_[1][0], kv_[1][2]))[0]

    # loottable -> NPCs (a loottable is shared by many NPCs)
    loottable_npcs = defaultdict(list)
    for nid, r in npc_rows.items():
        if r.get('loottable_id'):
            loottable_npcs[r['loottable_id']].append(nid)

    # lootdrop -> item -> effective chance, mirroring NPC::AddLootDropTable.
    # Per (lootdrop, item): P(item | this loottable entry fires). Then the
    # loottable entry's probability and multiplier scale it.
    def lootdrop_item_chances(ld_id, droplimit, mindrop):
        entries = lootdrop_entries.get(ld_id, ())
        if not entries:
            return {}
        out = {}
        if droplimit == 0 and mindrop == 0:
            for item_id, chance, mult, _, _ in entries:
                p = 1.0 - (1.0 - min(chance, 100.0) / 100.0) ** max(mult, 1)
                out[item_id] = max(out.get(item_id, 0.0), p)
            return out
        if len(entries) > 100 and droplimit == 0:
            droplimit = 10
        droplimit = max(droplimit, mindrop)
        roll_t = sum(e[1] for e in entries)
        bypass = any(e[1] >= 100 for e in entries)
        no_loot = 1.0
        for e in entries:
            if e[1] < 100:
                no_loot *= (100.0 - e[1]) / 100.0
        p_iter_drops = 1.0 if bypass else (1.0 - no_loot)
        if roll_t <= 0:
            return {}
        for item_id, chance, mult, _, _ in entries:
            share = chance / roll_t
            expected = mindrop * share + (droplimit - mindrop) * p_iter_drops * share
            p = min(1.0, expected)
            out[item_id] = max(out.get(item_id, 0.0), p)
        return out

    # item -> [(npc_id, pct)]   and   npc -> [(item_id, pct)]
    item_drops = defaultdict(dict)
    npc_drops = {}
    loottable_item_pct = {}
    for lt_id, entries in loottable_entries.items():
        pct = {}
        for ld_id, mult, droplimit, mindrop, prob in entries:
            base = lootdrop_item_chances(ld_id, droplimit, mindrop)
            scale = (prob / 100.0) if 0 < prob < 100 else (1.0 if prob >= 100 else 0.0)
            if scale <= 0:
                continue
            for item_id, p in base.items():
                pe = 1.0 - (1.0 - min(1.0, p * scale)) ** max(mult, 1)
                pct[item_id] = 1.0 - (1.0 - pct.get(item_id, 0.0)) * (1.0 - pe)
        loottable_item_pct[lt_id] = pct
    for lt_id, pct in loottable_item_pct.items():
        npcs = loottable_npcs.get(lt_id)
        if not npcs:
            continue
        for nid in npcs:
            npc_drops[nid] = pct
        for item_id, p in pct.items():
            d = item_drops[item_id]
            for nid in npcs:
                d[nid] = max(d.get(nid, 0.0), p)

    # merchants: merchant_id -> NPCs
    merchant_npcs = defaultdict(list)
    for nid, r in npc_rows.items():
        if r.get('merchant_id'):
            merchant_npcs[r['merchant_id']].append(nid)
    item_vendors = defaultdict(set)
    for mid, items_ in merchant_items.items():
        for _, item_id in items_:
            for nid in merchant_npcs.get(mid, ()):
                item_vendors[item_id].add(nid)

    # recipes: item -> made by / used in
    item_made_by = defaultdict(list)
    item_used_in = defaultdict(list)
    recipe_parts = {}
    for rid, entries in recipe_entries.items():
        if rid not in recipes:
            continue
        results, comps, containers = [], [], []
        for item_id, succ, compc, iscont in entries:
            if iscont:
                containers.append(item_id)
            elif succ > 0:
                results.append((item_id, succ))
            if compc > 0 and not iscont:
                comps.append((item_id, compc))
        recipe_parts[rid] = (results, comps, containers)
        for item_id, _ in results:
            item_made_by[item_id].append(rid)
        for item_id, _ in comps:
            item_used_in[item_id].append(rid)

    # spells cast by NPCs: spell -> NPCs (through parent lists too)
    def spell_list_ids(ns_id, seen=None):
        seen = seen or set()
        ids = []
        while ns_id and ns_id not in seen:
            seen.add(ns_id)
            ids.append(ns_id)
            ns_id = npc_spells_parent.get(ns_id, 0)
        return ids

    spell_npcs = defaultdict(set)
    npc_casts = {}
    for nid, r in npc_rows.items():
        ns = r.get('npc_spells_id')
        if not ns:
            continue
        spells = []
        for lid in spell_list_ids(ns):
            for spellid, typ, minl, maxl in npc_spell_lists.get(lid, ()):
                spells.append((spellid, typ))
                spell_npcs[spellid].add(nid)
        if spells:
            npc_casts[nid] = spells

    # quests
    print('scanning quest scripts')
    quest_index = scan_quests(args.quests)
    npc_by_zone_name = defaultdict(list)   # (zone, key) -> [npc ids]
    npc_by_name = defaultdict(list)
    for nid, r in npc_rows.items():
        key = norm_npc_key(r['name'])
        npc_by_name[key].append(nid)
        for zone in npc_zones.get(nid, {}):
            npc_by_zone_name[(zone, key)].append(nid)
    npc_quest = {}                          # npc id -> {'rewards','handins'}
    item_quests = defaultdict(list)         # item -> [(npc_id, name, zone, kind)]
    unresolved = 0
    for (zone, key), refs in quest_index.items():
        if isinstance(key, int):
            nids = [key] if key in npc_rows else []
        elif zone == 'global':
            nids = npc_by_name.get(key, [])[:50]
        else:
            nids = npc_by_zone_name.get((zone, key), []) or npc_by_name.get(key, [])[:5]
        if not nids:
            unresolved += 1
            label = key if isinstance(key, str) else str(key)
            for item_id in refs['rewards']:
                item_quests[item_id].append((0, npc_display_name(label), zone, 'R'))
            for item_id in refs['handins']:
                item_quests[item_id].append((0, npc_display_name(label), zone, 'H'))
            continue
        for nid in nids:
            q = npc_quest.setdefault(nid, {'rewards': set(), 'handins': set()})
            q['rewards'] |= refs['rewards']
            q['handins'] |= refs['handins']
        nid = nids[0]
        for item_id in refs['rewards']:
            item_quests[item_id].append((nid, npc_name(nid), zone, 'R'))
        for item_id in refs['handins']:
            item_quests[item_id].append((nid, npc_name(nid), zone, 'H'))
    print('  quest NPCs resolved: %d, unresolved scripts: %d' % (len(npc_quest), unresolved))

    def zname(short):
        return zone_long.get(short, short)

    def zid_name(zid):
        short = zone_id_short.get(zid)
        return zname(short) if short else ('zone %s' % zid)

    # ---- pass 2: items -----------------------------------------------------
    print('pass 2: items')
    spell_items = defaultdict(list)   # spell id -> [(kind, item id)]
    icol = col_index('items', ['id'] + ITEM_COLS)
    items_w = ChunkWriter(out_dir, 'items', cap)
    item_at = {}                      # id -> (chunk, off)
    tiers_of = defaultdict(str)       # base id -> 'BEL' letters present
    n_items = 0

    def tier_of(item_id):
        if item_id >= 2000000:
            return 'L', item_id - 2000000
        if item_id >= 1000000:
            return 'E', item_id - 1000000
        return 'B', item_id

    def drops_text(item_id):
        d = item_drops.get(item_id)
        if not d:
            return ''
        rows = sorted(d.items(), key=lambda kv_: -kv_[1])
        parts = ['%d~%s' % (nid, fmt_num(round(p * 100, 1))) for nid, p in rows[:MAXL] if nid in npc_rows]
        more = len(rows) - MAXL
        return ';'.join(parts) + ((';+%d' % more) if more > 0 else '')

    def sources_text(item_id):
        f = []
        for zid, chance in forage.get(item_id, ())[:20]:
            f.append('F~%s~%s' % (esc(zone_id_short.get(zid, str(zid))), fmt_num(chance)))
        for zid, chance in fishing.get(item_id, ())[:20]:
            f.append('W~%s~%s' % (esc(zone_id_short.get(zid, str(zid))), fmt_num(chance)))
        for zid in ground.get(item_id, ())[:20]:
            f.append('G~%s~' % esc(zone_id_short.get(zid, str(zid))))
        return ';'.join(f)

    def vendors_text(item_id):
        v = item_vendors.get(item_id)
        if not v:
            return ''
        rows = sorted(v)[:MAXL]
        parts = [str(nid) for nid in rows]
        more = len(v) - MAXL
        return ';'.join(parts) + ((';+%d' % more) if more > 0 else '')

    def recipe_text(rid, with_parts):
        r = recipes.get(rid)
        if not r:
            return ''
        results, comps, containers = recipe_parts.get(rid, ([], [], []))
        fields = [str(rid), esc(r.get('name') or ''), str(r.get('tradeskill') or 0), str(r.get('skillneeded') or 0),
                  str(r.get('trivial') or 0), '1' if r.get('nofail') else '', '1' if r.get('must_learn') else '',
                  str(r.get('learned_by_item_id') or 0), '1' if r.get('quest') else '']
        if with_parts:
            fields.append(','.join('%d:%d' % (iid, c) for iid, c in comps))
            conts = []
            for cid in containers:
                if cid in item_name:
                    conts.append('%d:' % cid)
                else:
                    conts.append('0:%s' % esc(CONTAINER_TYPES.get(cid, 'container %s' % cid)))
            fields.append(','.join(conts))
            fields.append(','.join('%d:%d' % (iid, c) for iid, c in results))
        return '~'.join(fields)

    def made_text(item_id):
        rids = item_made_by.get(item_id)
        if not rids:
            return ''
        return ';'.join(t for t in (recipe_text(rid, True) for rid in rids[:12]) if t)

    def usedin_text(item_id):
        rids = item_used_in.get(item_id)
        if not rids:
            return ''
        parts = []
        for rid in rids[:MAXL]:
            results = recipe_parts.get(rid, ([], [], []))[0]
            res_id = results[0][0] if results else 0
            r = recipes.get(rid)
            if not r:
                continue
            parts.append('%d~%d~%d~%d' % (rid, r.get('tradeskill') or 0, r.get('trivial') or 0, res_id))
        more = len(rids) - MAXL
        return ';'.join(parts) + ((';+%d' % more) if more > 0 else '')

    def quests_text(item_id):
        q = item_quests.get(item_id)
        if not q:
            return ''
        seen, parts = set(), []
        for nid, name, zone, kind in q:
            k = (nid, name, zone, kind)
            if k in seen:
                continue
            seen.add(k)
            parts.append('%d~%s~%s~%s' % (nid, esc(name) if nid == 0 else '', esc(zone), kind))
            if len(parts) >= MAXL:
                break
        return ';'.join(parts)

    def h_item(v):
        nonlocal n_items
        item_id = v[icol['id']]
        fields = [('id', item_id)]
        for k in ITEM_COLS:
            i = icol.get(k)
            if i is None:
                continue
            val = v[i]
            if k in ('clickeffect', 'proceffect', 'worneffect', 'focuseffect', 'scrolleffect', 'bardeffect'):
                if val is None or val <= 0:
                    continue
                kind = k[:-6] if k != 'bardeffect' else 'bard'
                spell_items[val].append((kind, item_id))
            elif k == 'nodrop':
                fields.append(('NODROP', 1 if val == 0 else 0))
                continue
            elif k == 'norent':
                fields.append(('NORENT', 1 if val == 0 else 0))
                continue
            elif k == 'lore':
                if isinstance(val, str) and val.startswith('*'):
                    val = val[1:]
                if val == v[icol['name']] or (item_id >= 1000000 and val == item_name.get(item_id % 1000000)):
                    continue
            elif k == 'name' and item_id >= 1000000 and (item_id % 1000000) in item_name:
                continue
            elif k == 'stacksize' and val == 1:
                continue
            elif k in ('skillmodtype', 'skillmodmax', 'augrestrict', 'recskill') and (val or 0) < 0:
                continue
            fields.append((k, val))
        tier, base_id = tier_of(item_id)
        tiers_of[base_id] += tier
        # E/L rows carry stats only; the reader takes sources (and the name)
        # from the base row. E/L-only items keep everything.
        if tier == 'B' or base_id not in item_name:
            fields.append(('drops', Raw(drops_text(item_id))))
            fields.append(('src', Raw(sources_text(item_id))))
            fields.append(('sold', Raw(vendors_text(item_id))))
            fields.append(('made', Raw(made_text(item_id))))
            fields.append(('usedin', Raw(usedin_text(item_id))))
            fields.append(('quests', Raw(quests_text(item_id))))
        line = kv(fields)
        items_w.group_start(len(line) + 2)
        item_at[item_id] = items_w.write(line)
        n_items += 1
        if n_items % 50000 == 0:
            print('  %d items (%.0fs)' % (n_items, time.time() - t0))

    rd.run({'items': h_item})
    items_w.close()

    # items index: one line per base item (plus E/L items with no base)
    with open(os.path.join(out_dir, 'items.idx'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('#gamedb items v1 count=%d\n' % len(tiers_of))
        for base_id in sorted(tiers_of):
            tiers = tiers_of[base_id]
            if 'B' in tiers:
                ref = base_id
            elif 'E' in tiers:
                ref = base_id + 1000000
            else:
                ref = base_id + 2000000
            refs = []
            for letter, off in (('B', 0), ('E', 1000000), ('L', 2000000)):
                at = item_at.get(base_id + off)
                refs.append('%d:%d' % at if at else '')
            name = item_name.get(ref, '')
            f.write('%d|%s|%s|%s|%s|%s\n' % (base_id, tiers, refs[0], refs[1], refs[2], esc(name)))
    print('  items written: %d records, %d index lines, %d chunks (%.0fs)' % (n_items, len(tiers_of), items_w.chunk, time.time() - t0))

    # ---- NPCs ----------------------------------------------------------------
    print('npcs')
    npcs_w = ChunkWriter(out_dir, 'npcs', cap)
    npc_at = {}
    for nid in sorted(npc_rows):
        r = npc_rows[nid]
        fields = [('id', nid)]
        for k in NPC_COLS:
            val = r.get(k)
            if k == 'attack_count' and (val or 0) < 0:
                continue
            if k == 'name':
                val = npc_display_name(val)
            elif k == 'lastname' and val:
                val = val.strip()
            fields.append((k, val))
        zones = npc_zones.get(nid, {})
        fields.append(('spawns', Raw(';'.join('%s~%d~%d~%s' % (esc(z), c, resp, fmt_num(ch))
                                               for z, (c, resp, ch) in sorted(zones.items(), key=lambda kv_: -kv_[1][0])[:MAXL]))))
        drops = npc_drops.get(nid)
        if drops:
            rows = sorted(drops.items(), key=lambda kv_: -kv_[1])
            txt = ';'.join('%d~%s' % (iid, fmt_num(round(p * 100, 1))) for iid, p in rows[:MAXL * 2] if iid in item_name)
            if len(rows) > MAXL * 2:
                txt += ';+%d' % (len(rows) - MAXL * 2)
            fields.append(('drops', Raw(txt)))
        mid = r.get('merchant_id')
        if mid and merchant_items.get(mid):
            rows = sorted(merchant_items[mid])
            fields.append(('sells', Raw(';'.join(str(iid) for _, iid in rows[:MAXL * 2] if iid in item_name)
                                        + ((';+%d' % (len(rows) - MAXL * 2)) if len(rows) > MAXL * 2 else ''))))
        casts = npc_casts.get(nid)
        if casts:
            fields.append(('casts', Raw(';'.join('%d~%d' % (sid, typ) for sid, typ in casts[:MAXL]))))
        fid = r.get('npc_faction_id')
        if fid and fid in npc_faction:
            fname_, primary = npc_faction[fid]
            fields.append(('faction', faction_name.get(primary, fname_)))
            hits = npc_faction_hits.get(fid)
            if hits:
                fields.append(('fachits', Raw(';'.join('%s~%d' % (esc(faction_name.get(f_id, 'faction %d' % f_id)), val) for f_id, val in hits if val))))
        q = npc_quest.get(nid)
        if q:
            fields.append(('quest', 1))
            fields.append(('qrewards', Raw(';'.join(str(iid) for iid in sorted(q['rewards']) if iid in item_name))))
            fields.append(('qhandins', Raw(';'.join(str(iid) for iid in sorted(q['handins']) if iid in item_name))))
        line = kv(fields)
        npcs_w.group_start(len(line) + 2)
        npc_at[nid] = npcs_w.write(line)
    npcs_w.close()
    with open(os.path.join(out_dir, 'npcs.idx'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('#gamedb npcs v1 count=%d\n' % len(npc_at))
        for nid in sorted(npc_at):
            r = npc_rows[nid]
            ch, off = npc_at[nid]
            f.write('%d|%d:%d|%d|%s|%s\n' % (nid, ch, off, r.get('level') or 0, esc(npc_zone_short(nid)), esc(npc_display_name(r['name']))))
    print('  npcs written: %d, %d chunks (%.0fs)' % (len(npc_at), npcs_w.chunk, time.time() - t0))

    # ---- spells --------------------------------------------------------------
    print('spells')
    scol = col_index('spells_new', ['id'] + SPELL_COLS + ['classes%d' % i for i in range(1, 17)]
                     + ['effectid%d' % i for i in range(1, 13)] + ['effect_base_value%d' % i for i in range(1, 13)]
                     + ['effect_limit_value%d' % i for i in range(1, 13)] + ['max%d' % i for i in range(1, 13)]
                     + ['formula%d' % i for i in range(1, 13)])
    spells_w = ChunkWriter(out_dir, 'spells', cap)
    spell_idx_lines = []

    def h_spell(v):
        sid = v[scol['id']]
        fields = [('id', sid)]
        for k in SPELL_COLS:
            i = scol.get(k)
            if i is not None:
                fields.append((k, v[i]))
        classes = []
        for ci in range(1, 17):
            i = scol.get('classes%d' % ci)
            lvl = v[i] if i is not None else 255
            if lvl is not None and 0 < lvl < 255:
                classes.append('%d:%d' % (ci, lvl))
        fields.append(('classes', Raw(','.join(classes))))
        effects = []
        for ei in range(1, 13):
            eid = v[scol.get('effectid%d' % ei)]
            if eid is None or eid == 254:
                continue
            effects.append('%d~%s~%s~%s~%s' % (ei, fmt_num(eid), fmt_num(v[scol.get('effect_base_value%d' % ei)] or 0),
                                                fmt_num(v[scol.get('effect_limit_value%d' % ei)] or 0), fmt_num(v[scol.get('max%d' % ei)] or 0))
                           + '~' + fmt_num(v[scol.get('formula%d' % ei)] or 0))
        fields.append(('effects', Raw(';'.join(effects))))
        its = spell_items.get(sid)
        if its:
            fields.append(('items', Raw(';'.join('%s~%d' % (kind, iid) for kind, iid in its[:MAXL * 2])
                                        + ((';+%d' % (len(its) - MAXL * 2)) if len(its) > MAXL * 2 else ''))))
        nps = spell_npcs.get(sid)
        if nps:
            rows = sorted(nps)[:MAXL]
            fields.append(('npcs', Raw(';'.join(str(nid) for nid in rows) + ((';+%d' % (len(nps) - MAXL)) if len(nps) > MAXL else ''))))
        line = kv(fields)
        spells_w.group_start(len(line) + 2)
        ch, off = spells_w.write(line)
        spell_idx_lines.append('%d|%d:%d|%s|%s' % (sid, ch, off, ','.join(classes), esc(v[scol['name']] or '')))

    rd.run({'spells_new': h_spell})
    spells_w.close()
    with open(os.path.join(out_dir, 'spells.idx'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('#gamedb spells v1 count=%d\n' % len(spell_idx_lines))
        f.write('\n'.join(spell_idx_lines) + '\n')
    print('  spells written: %d, %d chunks (%.0fs)' % (len(spell_idx_lines), spells_w.chunk, time.time() - t0))

    with open(os.path.join(out_dir, 'zones.idx'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('#gamedb zones v1 count=%d\n' % len(zone_long))
        for short in sorted(zone_long):
            f.write('%s|%s\n' % (esc(short), esc(zone_long[short])))

    with open(os.path.join(out_dir, 'manifest.txt'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('built=%s\nsource=%s\nitems=%d\nitem_index=%d\nnpcs=%d\nspells=%d\nformat=1\n' % (
            time.strftime('%Y-%m-%d'), os.path.basename(args.sql), n_items, len(tiers_of), len(npc_at), len(spell_idx_lines)))
    total = sum(os.path.getsize(os.path.join(out_dir, fn)) for fn in os.listdir(out_dir))
    print('done: %s (%.1f MB) in %.0fs' % (out_dir, total / 1048576.0, time.time() - t0))


if __name__ == '__main__':
    sys.exit(main())
