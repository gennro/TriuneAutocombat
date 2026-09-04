-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for Burning Woods (burningwood)
-- Total Quests: 4
-- ============================================================================

return {
  zone = "burningwood",
  zone_name = "Burning Woods",
  quests = {
    {
      id = "2945",
      title = "Enchanter Epic 1.5: Oculus of Persuasion",
      exp = "08",
      exp_name = "Omens of War",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "a sarnak imitator",
      loc = { y = -1200.0, x = -4000.0, z = 0.0 },
      triggers = {
        "Hail, a sarnak imitator",
        "I am prepared.",
        "Jeb Lumsed sent me.",
        "Hail, Anthone Chapin",
        "Fungus Grove",
        "Cazic Thule",
        "Ocean of Tears",
        "Velketor",
      },
      items_required = {
        { name = "her the note", count = 1 },
        { name = "you an Ornate Staff Chest", count = 1 },
        { name = "him the filigree", count = 1 },
        { name = "you the 1st Piece of the Staff", count = 1 },
        { name = "this to Jeb", count = 1 },
      },
      rewards = {
        { id = 30893, name = "1st Piece of the Staff", type = "item" },
        { id = 30892, name = "2nd Piece of the Staff", type = "item" },
        { id = 30891, name = "3rd Piece of the Staff", type = "item" },
        { id = 30584, name = "4th Piece of the Staff", type = "item" },
        { id = 31005, name = "Abysmal Moonwater", type = "item" },
        { id = 30895, name = "All-Seeing Eye", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Burning Woods [zone=77]\n**Who:**\n- a sarnak imitator [npc=5231]\nRating:\n0/1**_\\*__\\*__\\*__\\*__\\*_**\n(From 1 rating)\nInformation:\n**Level:** | 70\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Quest\n**Quest Goal:**\n- Epic\n**Quest Items:**\n- 1st Piece of the Staff [item=30893]\n- 2nd Piece of the Staff [item=30892]\n- 3rd Piece of the Staff [item=30891]\n- 4th Piece of the Staff [item=30584]\n- Abysmal Moonwater [item=31005]\n- All-Seeing Eye [item=30895]\n- Assembling the Staff [item=31004]\n- Complete Illegible Tome [item=30885]\n- Cryptic Page [Fungus Grove]\n- Cryptic Page [Cazic Thule]\n- Cryptic Page [Ocean of Tears]\n- Cryptic Page [Velketor]\n- Cryptic Page [Skyshrine]\n- Cryptic Page [Crypt of Nadox]\n- Cryptic Page [Najena]\n- Cryptic Page [Sebilis]\n- Cryptic Page [Charasis]\n- Cryptic Page [Crystal Caverns]\n- Dragon Egg Oil [item=31051]\n- Essence of Sunlight [item=14890]\n- Glimmering Oil [item=30894]\n- Glow Lichen [item=6195]\n- Glowing Concoction [item=31009]\n- Incandescent Oil [item=31050]\n- Latched Ornate Chest [item=31183]\n- Note to Lobaen [item=30886]\n- Ornate Staff Chest [item=31008]\n- Ornate Staff Topper [item=31007]\n- Prismatic Dye [item=20151]\n- Purified Gold Filigree [item=30889]\n- Sealed Documents [item=30887]\n- Staff of the Serpent [item=136]\n- Sullied Gold Filigree [item=30888]\n- Taste of Enticement [item=30890]\n- Tattered Illegible Tome [item=30524]\n- Vial of Purified Mana [item=14360]\n**Related Zones:**\n- Castle Mistmoore [zone=63]\n- Cazic-Thule 3.0 [zone=46]\n- Crystal Caverns [zone=101]\n- Halls of Honor [zone=171]\n- Howling Stones 2.0 (Charasis) [zone=84]\n- Najena [zone=45]\n- Natimbi, the Broken Shores [zone=237]\n- Ocean of Tears 2.0 [zone=42]\n- Old Sebilis [zone=89]\n- Plane of Innovation [zone=160]\n- Plane of Justice [zone=162]\n- Plane of Mischief 2.0 [zone=104]\n- Siren's Grotto 3.0 [zone=122]\n- Skyshrine [zone=107]\n- The Bloodfields [zone=260]\n- The Crypt of Nadox [zone=182]\n- The Fungus Grove [zone=147]\n- The Plane of Knowledge [zone=158]\n- Tower of Frozen Shadow [zone=117]\n- Velketor's Labyrinth [zone=109]\n- Vxed, the Crumbling Caverns [zone=246]\n**Related Creatures:**\n- Advisor Svartmane [npc=16306]\n- All-Seeing Eye [npc=16058]\n- Anthone Chapin [npc=16068]\n- Faleniel of Darkwater [npc=15992]\n- Grand Librarian Maelin [npc=10635]\n- Illusionist Lobaen [ _Enchanter Spells 51-60_]\n- War Caller Kaavi [npc=16150]\n- a chest - All-Seeing Eye [npc=16762]\n- a chest - Faleniel of Darkwater [npc=16725]\n- a chest - a greasy clockwork [npc=29333]\n- a greasy clockwork [npc=16384]\n- an enticing potamide [npc=16178]\n- the yrendan scarab [npc=10811]\n**Related Quests:**\n- Enchanter Epic 1.5 Pre-Quest [quest=3340]\n- Enchanter Epic 2.0: Staff of Eternal Eloquence [quest=3341]\n- Enchanter Epic: Staff of the Serpent [quest=781]\n- Key to Charasis [quest=682]\n- Key to Sebilis [quest=86]\n**Era:** | !Omens of War\nRecommended:\n**Group Size:** | Solo\n**Min. # of Players:** | 1\n**Max. # of Players:** | 1\n**Appropriate Classes:**\n- Enchanter\n**Appropriate Races:**\n- Dark Elf\n- Drakkin\n- Erudite\n- Gnome\n- High Elf\n- Human\nEntered: Thu Sep 23 14:26:38 2004\nModified: Tue Dec 5 05:21:04 2023 | | _If you have the Staff of the Serpent (enchanter epic 1.0) or have completed the pre-quest, find \"a sarnak imitator,\" a.k.a. Jeb Lumsed, in the Burning Woods at -1200, -4000._\nYou say, 'Hail, a sarnak imitator'\na sarnak imitator says 'Much time has passed since the creation of the Staff of the Serpent. The power of discord is seeping into our fair world, and only the most powerful of us shall stand to force it back. The time has come for a new tool, and a new breed of enchanter. [Are you prepared] to meet this challenge?'\nYou say, 'I am prepared.'\na sarnak imitator says 'I have recently received this ancient tome; it contains knowledge that may prove invaluable to the construction of a new staff. Unfortunately, time has had its way with it. I need you to find the missing pages so we can get to work. There should be ten, unless they have been destroyed by time and decay.'\n_You receive a Tattered Illegible Tome, a 10-slot container. Now you must collect the ten Cryptic Pages (no unique item lore), which are all ground spawns that may be found as follows:_\n_1\\. In Charasis (Howling Stones) at -135, +245, -165._\n_2\\. In Old Sebilis in the Ilis jail at -260, +355, -176 (go down the water tube, turn right, and go into the jail cell near the Echo of Sebilis)._\n_3\\. In Cazic Thule at +430, -390 (just north of the wizard spire, in a room with lizards and pillars)._\n_4\\. In Crystal Caverns at -590, -940, -536 (in the queen's room, practically under her)._\n_5\\. In Skyshrine at +150, +385, +3 (the southwest tower)._\n_6\\. In Velketor's Labyrinth at +260, -425, +21 (at the first dog tent on the left)._\n_7\\. In the Crypt of Nadox at +785, +1745, -82 (near the broodmother)._\n_8\\. In Najena at -160, -120, -19 (near Rathyl in the basement)._\n_9\\. In Fungus Grove at +1135, +1275 (in the Lucid Shard camp in the Shik`Nar tunnels)._\n_10\\. In the Ocean of Tears at +945, +7860, -232 (between three sirens)._\n_If you miss a spawn, the Cryptic Pages respawn every few hours **(need a respawn timer on these)**. Combine the ten pages in the book to craft a Complete Illegible Tome. Bring this back to Jeb._\na sarnak imitator says 'As I suspected, this is something extraordinary. You must go speak to Maelin at once. It has been many moons since I have entered the Plane of Knowledge. He may well have some new information for me. Go at once and tell him I sent you.'\n_You receive an invisible flag for completing the previous step. Now go to the Plane of Knowledge and speak with Grand Librarian Maelin._\nYou say, 'Jeb Lumsed sent me.'\nGrand Librarian Maelin says 'This is from Jeb, you say? I will set my best researchers on it at once. We have recently made some discoveries that he should be aware of. Here, take this note down to Lobaen, she will retrieve them for you.'\n_You receive a Note to Lobaen. She's a dryad selling spells elsewhere in the Library at -85, +1060, -60. Give her the note._\nIllusionist Lobaen says 'It is not often that I receive a request from Maelin himself. Please, take these and be most careful.'\n_You receive Sealed Documents. Take these back to Jeb._\na sarnak imitator says 'Interesting indeed. I see that I was not wrong in my instinct to begin this as quickly as possible. I have created a list of the items that you will need to begin the construction of this tool. Mind you, it will not be a simple thing. When you have gathered them all return to me. Would you like a chest to carry them in?'\n_He gives you a book called Assembling the Staff, which lists the components required. If you say, \"I would like a chest,\" he will give you an Ornate Staff Chest. The text of the book is as follows:_\n`\nGold Filigree: This is needed to bind the staff. Last I heard a strange sort of mermaid made off with it. The hand of Marr may cleanse it.\nStaff Section: This was shattered by Mayong's rage. I do believe something from his castle may in fact entice the one who holds it into speaking.\nStaff Section: A strange scarab scampered off with this piece, seek him in the caves.\nStaff Section: This was broken in a mountain pass.\nStaff Section: The warcaller claimed this one long ago.\nStaff Crown: A misguided siren mistakes it for a crown.\nIncandescent Oil: This is needed to anoint the staff. First create a glowing concoction of moonwater, magic, light, and that which glows. Take this glowing concoction and brew it with a greasy sort of oil, oil of a dragon, and some dye.\nAll-Seeing Eye: You could also call him the eye of Bristlebane.\n`\nGold Filigree\n_Kill an enticing potameid at -845, +1560 in Natimbi and loot the Sullied Gold Filigree. Take this filigree to Anthone Chapin in the right basement of the Halls of Honor (top of the map), a.k.a. Rydda Dar's basement. Pacify or kill the two guards nearby._\nYou say, 'Hail, Anthone Chapin'\nAnthone Chapin says 'Mithaniel Marr himself has entrusted me with the power to purge taint from the most desecrated of objects.'\n_Give him the filigree._\nAnthone Chapin says 'This filigree now shines from within with the holy light of Marr.'\n_You receive a Purified Gold Filigree._\nStaff Section 1\n_Go to Mistmoore's Castle. Zone in invisible, and follow the tunnel around to the graveyard. Enter the graveyard and the building within. Fall through the floor at the front of the casket. Go up the ramp or stairs (can't remember which) to a room with four doors. Open the door to your right. It should open and be a fake wall. If it doesn't, it's the wrong door. If it is the correct door, directly to its left is a secret passage. Enter the secret passage and go up and up and up till you get as high as you can in the tower. If you have not seen the lift, you need to look up and click the piece of wood. A fruit called the Taste of Enticement spawns on the table in the same room as the Dark Huntress. It looks like a blue mushroom on the table. Take this fruit and go to the seventh floor of the Tower of Frozen Shadow, a.k.a. Tserrina's floor. If you use the master key, you'll be in a room full of mirrors. Just outside of this room is the Advisor Svartmane, whom you must charm. If you are careful, you can open the door without him aggroing, especially since he does not see invis. Charm him and hand him the fruit._\nAdvisor Svartmane says 'I can't . . I . . .of course, I do not think that Tserrina has any need for this. I can't imagine that she would miss it at all. Please, take it.'\n_He will give you the 1st Piece of the Staff. This part is soloable, but has killed many enchanters. Take along a pal for safety and stack runes on yourself._\nStaff Section 2\n_The 2nd Piece of the Staff drops from the yrendan scarab, a rare spawn in the Plane of Justice at approximately -1300, -850._\nStaff Section 3\n_The 3rd Piece of the Staff drops from any named in the Vxed trial._\nStaff Section 4\n_The 4th Piece of the Staff drops off of War Caller Kaavi in the Bloodfields. To get to her area, you jump off the bridge port in area and follow the wall south west. When I went to do her, someone had clearly failed her. She was already targetable. We pulled 2 of her guardians (Sentry of Kaavi), and killed them. They easily mez/slow and are very much overcons. Then we pulled her and two more of her guardians. Mezzed the guardians and killed her. Her aggro is a little awkward but killed her easily enough. I took the same raid force for all major mobs. So we killed this mob with about 19 people. It was easily overkill._\nStaff Crown\n_Faleniel of Darkwater spawns in Sirens Grotto. The easiest method to get to her is to teleport to Cobalt Scar, zone into Sirens Grotto, then evac/succor across the zone. Run to the well invised and drop down into her room. Nothing sees invis. You can get killed if your raid group can't stay invis._\n_She is perma-rooted, has many easily killed friends who may or may not heal her, and casts two AEs: Ice Rain and Drowning Panic. She can hit for 2k, and is difficult if not impossible to slow. She drops an Ornate Staff Topper. After you loot it, a chest may spawn with additional loot._\nIncandescent Oil\n_Combine Abysmal Moonwater (found on the bottom of the Abysmal Sea at +485, +70), a Vial of Purified Mana, Essence of Sunlight (dropped in various old world zones), and Glow Lichen (foraged in Nektulos Forest) in a brew barrel to craft a Glowing Concoction, < 103 trivial, trivial needed)._\n_Next kill the untrackable \"a greasy clockwork\" in the Plane of Innovation. From zone-in, turn left and follow the path to the four-way intersection. Turn left and you cannot miss it if it's up. It hits in the 1800's, AE rampages, and has an AE called Blinding Smog. The fight is apparently very similar to the one with the Junk Beast. It drops Glimmering Oil. After you loot the Glimmering Oil, a chest may spawn with additional loot._\n_Combine Glowing Concoction, Glimmering Oil, Dragon Egg Oil, and Prismatic Dye (not a Vial of Prismatic Dye) in a brew barrel to craft Incandescent Oil **(< 103 trivial, trivial needed)**._\nAll-Seeing Eye\n_This is literally the All-Seeing Eye that spawns in the middle of the Plane of Mischief hedge maze. It is not perma-rooted, looks like a giant beholder, and hits for around 2k. Bring a raid force. Slow is difficult but possible to land, while cripple and weakness are more difficult. Strangle landed fine. It has an estimated one million HPs. Has single-target rampage and procs Gaze of the All-Seeing Eye. Once it's dead, loot the All-Seeing Eye. A chest may spawn with additional loot._\nHand-in\n_Combine the Purified Gold Filigree, 1st-4th Pieces of the Staff, Ornate Staff Topper, Incandescent Oil, and All-Seeing Eye in the Ornate Staff Chest to craft a Latched Ornate Chest. Give this to Jeb._\na sarnak imitator says 'You have done well, my student. The staff is now complete. In order to stand up to the true fury of discord, it will need purifying, but even in this state it shall protect you well.'\n_You receive the Oculus of Persuasion, a.k.a. Enchanter Epic 1.5 and the title Coercer._\n**Submitted by:** Ashka Darkhope, Woland, Curufinwe\n- Oculus of Persuasion [item=31010]",
    },
    {
      id = "11009",
      title = "Cabilis Quests - The Restraining Order (5 Points)",
      exp = "01",
      exp_name = "The Ruins of Kunark",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "Achievement",
      repeatable = false,
      group_size = "Solo",
      npc = "Clerk Doval",
      loc = nil,
      triggers = {
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "**Level:** 1\n**Maximum Level:** 125\n**Monster Mission:** No\n**Repeatable:** No\n**Can Be Shrouded?:** No\n**Quest Type:** Achievement\n**Group Size:** Solo\n\nThis achievement is gained upon completing the following Cabilis quest.\n[ ] Complete Clerk Doval's quest \"The Restraining Order\" in Cabilis EastSubmitted by: GidonoRewards:\n[",
    },
    {
      id = "8525",
      title = "Hunter of Jaggedpine Forest",
      exp = "03",
      exp_name = "The Shadows of Luclin",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "Achievement",
      repeatable = false,
      group_size = "Solo",
      npc = "Entalon",
      loc = nil,
      triggers = {
        "hail",
        "quest",
      },
      items_required = {
        { id = 12990, name = "Scribblings", count = 1 },
        { id = 12755, name = "Stoneleer Emerald Plume", count = 1 },
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "**Level:** 1\n**Maximum Level:** 125\n**Monster Mission:** No\n**Repeatable:** No\n**Can Be Shrouded?:** No\n**Quest Type:** Achievement\n**Group Size:** Solo\n\nThis achievement is gained upon defeating the following rare monsters in Jaggedpine Forest.\nan ancient treant\nElishia Blackguard\nFierceWind\nGoldenTalon\na great kodiak\nJerg Oakenfist\nLameriae the Alluring\nMyraephe the Pure\nPotamide Dame\nPotamide Matriarch\nPotamide Matron\nReynold Blackguard\na savage pinewolf\nStormClaw\nVaurien Sticklebush\nZed Sticklebush\nSubmitted by: GidonoRewards:\n[",
    },
    {
      id = "8648",
      title = "Hunter of Jaggedpine Forest (Luclin)",
      exp = "03",
      exp_name = "The Shadows of Luclin",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "Achievement",
      repeatable = false,
      group_size = "Solo",
      npc = "Entalon",
      loc = nil,
      triggers = {
        "hail",
        "quest",
      },
      items_required = {
        { id = 12990, name = "Scribblings", count = 1 },
        { id = 12755, name = "Stoneleer Emerald Plume", count = 1 },
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "**Level:** 1\n**Maximum Level:** 125\n**Monster Mission:** No\n**Repeatable:** No\n**Can Be Shrouded?:** No\n**Quest Type:** Achievement\n**Group Size:** Solo\n\nThis achievement is gained upon defeating the following rare monsters in Jaggedpine Forest:\nan ancient treant\nElishia Blackguard\nFierceWind\nGoldenTalon\na great kodiak\nJerg Oakenfist\nLameriae the Alluring\nMyraephe the Pure\nA Potameid Dame\nA Potameid Matriarch\nA Potameid Matron\nReynold Blackguard\na savage pinewolf\nStormClaw\nVaurien Sticklebush\nZed Sticklebush\nSubmitted by: GidonoRewards:\n[",
    },
  },
}
