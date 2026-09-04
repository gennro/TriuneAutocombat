-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for Vergalid Mines (vergalid)
-- Total Quests: 3
-- ============================================================================

return {
  zone = "vergalid",
  zone_name = "Vergalid Mines",
  quests = {
    {
      id = "3612",
      title = "The Disk of Kings",
      exp = "12",
      exp_name = "The Serpent's Spine",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Rokiln the Hunter",
      loc = nil,
      triggers = {
        "Hail, Rokiln the Hunter",
        "What tale?",
        "tale",
      },
      items_required = {
      },
      rewards = {
        { id = 51951, name = "Fifth Fragment of the Kings' Disk", type = "item" },
        { id = 51947, name = "First Fragment of the Kings' Disk", type = "item" },
        { id = 51950, name = "Fourth Fragment of the Kings' Disk", type = "item" },
        { id = 51948, name = "Second Fragment of the Kings' Disk", type = "item" },
        { id = 51952, name = "Sixth Fragment of the Kings' Disk", type = "item" },
        { id = 51949, name = "Third Fragment of the Kings' Disk", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Vergalid Mines [zone=440]\n**Who:**\n- Rokiln the Hunter [ _Quests 65+_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 70\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n- Loot\n**Quest Items:**\n- Fifth Fragment of the Kings' Disk [item=51951]\n- First Fragment of the Kings' Disk [item=51947]\n- Fourth Fragment of the Kings' Disk [item=51950]\n- Second Fragment of the Kings' Disk [item=51948]\n- Sixth Fragment of the Kings' Disk [item=51952]\n- Third Fragment of the Kings' Disk [item=51949]\n**Related Zones:**\n- Ashengate, Reliquary of the Scale [zone=442]\n**Related Creatures:**\n- Advisor Neezin D`rahl [npc=22821]\n- Attendant Jin`zhu [npc=23671]\n- Captain of the Guard [npc=23607]\n- Griffon Trainer Ahrendes [npc=23719]\n- Quartermaster Ilzjinn [npc=23450]\n- Scale Guardian Oriam [npc=23470]\n**Related Quests:**\n- Shield of the Otherworld [quest=4117]\n- The Disk of Heroes [quest=3613]\n- The Disk of Warriors [quest=3611]\n**Era:** | !Serpents Spine\nRecommended:\n**Group Size:** | Solo\n**Min. # of Players:** | 1\n**Max. # of Players:** | 1\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Tue Sep 26 02:31:21 2006\nModified: Tue Dec 5 05:21:04 2023 | | _This solo task does not have a time limit._\n_This task begins with Rokiln the Hunter in Vergalid Mines._\nYou say, 'Hail, Rokiln the Hunter'\nThe spirit speaks slowly, 'Greeetinnngs. . . Though you be not my kindred, you have proven your worth by delivering these noble hunting trophies to honor my grave. In return for this great service, Troll, I will tell you the [tale] of this tomb.'\nYou say, 'What tale?'\nRokiln the Hunter says 'For many years, my ancestors held these mines, until the dragon men came. . .'\n_Rokiln now offer his four different tasks..._\nRokiln's tomb was once a vestibule for storing artifacts of the giants. The tomb has since been raided and looted by drakkin who have overrun the mines. Among the objects stolen by Dyn'leth's armies was an old giant artifact known as the Shield of the Otherworld. The artifact held special spiritual significance to the giants as it contained the names of all their fallen warriors, heroes, and kings on three interlocking disks. Dyn'leth, realizing this significance, smashed the disk and awarded the broken shards to his various captains and commanders as trophies.\nThe Disk of Kings was given to followers of Dyn'Leth assigned to the Ashengate.\nReturn the remnants of the Disk of the Kings to Rokiln at his tomb.\nReturn the First Fragment of the King's Disk to Rokiln's Tomb 0/1 (Vergalid Mines)\nThis is dropped by Attendant Jin`zhu in Ashengate, Reliquary of the Scale.\nReturn the Second Fragment of the King's Disk to Rokiln's Tomb 0/1 (Vergalid Mines)\nThis is dropped by the Captain of the Guard in Ashengate, Reliquary of the Scale.\nReturn the Third Fragment of the King's Disk to Rokiln's Tomb 0/1 (Vergalid Mines)\nThis is dropped by Quartermaster Ilzjinn in Ashengate, Reliquary of the Scale.\nReturn the Fourth Fragment of the King's Disk to Rokiln's Tomb 0/1 (Vergalid Mines)\nThis is dropped by Advisor Neezin D`rahl in Ashengate, Reliquary of the Scale.\nReturn the Fifth Fragment of the King's Disk to Rokiln's Tomb 0/1 (Vergalid Mines)\nThis is dropped by Griffon Trainer Ahrendes in Ashengate, Reliquary of the Scale.\nReturn the Sixth Fragment of the King's Disk to Rokiln's Tomb 0/1 (Vergalid Mines)\nThis is dropped by Scale Guardian Oriam in Ashengate, Reliquary of the Scale.\nReward: Disk of Kings (used in the \"Shield of the Otherworld\" task)\n**Map Locations:**\nWhat you need for your ashengate\\_2 (or 3) map file:\nP 1025, -1568, -109, 127, 0, 0, 3, Attendant\\_Jin'Zhu\nP -64.8338, -653.6124, -0.5749, 127, 0, 0, 3, Captain\\_of\\_the\\_Guard\nP 435.8338, -1090.6124, 0.0000, 127, 0, 0, 3, Quartermaster\\_Ilzjinn\nP 745.0770, -2075.8391, -184.8740, 127, 0, 0, 3, Advisor\\_Neezin\\_D`rahl\nP 1021, -422, -109, 127, 0, 0, 3, Griffon\\_Trainer\\_Ahrendes\nP -110.0000, -1300.0000, -157.0000, 127, 0, 0, 3, Scale\\_Guard\\_Oriam\nRespawn time is about 20 minutes.\n- Disk of Kings [item=51946]",
    },
    {
      id = "3613",
      title = "The Disk of Heroes",
      exp = "12",
      exp_name = "The Serpent's Spine",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Rokiln the Hunter",
      loc = { y = 1556.0, x = 582.0, z = 400.0 },
      triggers = {
        "Hail, Rokiln the Hunter",
        "What tale?",
        "tale",
      },
      items_required = {
      },
      rewards = {
        { id = 51501, name = "Fifth Fragment of the Heroes' Disk", type = "item" },
        { id = 51497, name = "First Fragment of the Heroes' Disk", type = "item" },
        { id = 51500, name = "Fourth Fragment of the Heroes' Disk", type = "item" },
        { id = 51498, name = "Second Fragment of the Heroes' Disk", type = "item" },
        { id = 51502, name = "Sixth Fragment of the Heroes' Disk", type = "item" },
        { id = 51499, name = "Third Fragment of the Heroes' Disk", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Vergalid Mines [zone=440]\n**Who:**\n- Rokiln the Hunter [ _Quests 65+_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 70\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Loot\n**Quest Items:**\n- Fifth Fragment of the Heroes' Disk [item=51501]\n- First Fragment of the Heroes' Disk [item=51497]\n- Fourth Fragment of the Heroes' Disk [item=51500]\n- Second Fragment of the Heroes' Disk [item=51498]\n- Sixth Fragment of the Heroes' Disk [item=51502]\n- Third Fragment of the Heroes' Disk [item=51499]\n**Related Zones:**\n- Direwind Cliffs [zone=441]\n**Related Creatures:**\n- Carrionmancer Marrowrot [npc=22700]\n- Chaplain Rourke [npc=23728]\n- Hammerfist the Champion [npc=22670]\n- Kendra the Archer [npc=22671]\n- Legionnaire Shylock [npc=22707]\n- Shadowpaw [npc=22659]\n- The Ashengate Ambassador [npc=22768]\n**Related Quests:**\n- Shield of the Otherworld [quest=4117]\n- The Disk of Kings [quest=3612]\n- The Disk of Warriors [quest=3611]\n**Era:** | !Serpents Spine\nRecommended:\n**Group Size:** | Solo\n**Min. # of Players:** | 1\n**Max. # of Players:** | 1\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Tue Sep 26 02:39:23 2006\nModified: Tue Dec 5 05:21:04 2023 | | _This solo task does not have a time limit._\n_This task begins with Rokiln the Hunter in Vergalid Mines._\nYou say, 'Hail, Rokiln the Hunter'\nThe spirit speaks slowly, 'Greeetinnngs. . . Though you be not my kindred, you have proven your worth by delivering these noble hunting trophies to honor my grave. In return for this great service, Troll, I will tell you the [tale] of this tomb.'\nYou say, 'What tale?'\nRokiln the Hunter says 'For many years, my ancestors held these mines, until the dragon men came. . .'\n_Rokiln now offer his four different tasks..._\nRokiln's tomb was once a vestibule for storing artifacts of the giants. The tomb has since been raided and looted by drakkin who have overrun the mines. Among the objects stolen by Dyn'leth's armies was an old giant artifact known as the Shield of the Otherworld. The artifact held special spiritual significance to the giants as it contained the names of all their fallen warriors, heroes, and kings on three interlocking disks. Dyn'leth, realizing this significance, smashed the disk and awarded the broken shards to his various captains and commanders as trophies.\nThe Disk of Heroes was sent with Dyn`Leth's followers who were assigned to Direwind Cliffs.\nReturn the remnants of the Disk of the Heroes to Rokiln at his tomb.\n_All Fragments of the Heroes' Disk can be found in Direwind Cliffs._\n1\\. Return the First Fragment of the Heroes' Disk to Rokiln's Tomb 0/1 (Vergalid Mines)\n_Drop off The Ashengate Ambassador [npc=22768] which is at Location 1556, 582,400_\n2\\. Return the Second Fragment of the Heroes' Disk to Rokiln's Tomb 0/1 (Vergalid Mines)\n_Drop off Carrionmancer Marrowrot [npc=22700] and Shadowpaw [npc=22659]_\n3\\. Return the Third Fragment of the Heroes' Disk to Rokiln's Tomb 0/1 (Vergalid Mines)\n_Drop off Hammerfist the Champion [npc=22670]_\n4\\. Return the Fourth Fragment of the Heroes' Disk to Rokiln's Tomb 0/1 (Vergalid Mines)\n_Drop off Kendra the Archer [npc=22671]_\n5\\. Return the Fifth Fragment of the Heroes' Disk to Rokiln's Tomb 0/1 (Vergalid Mines)\n_Drop off Chaplain Rourke [npc=23728]. He spawns in the same camp (Grey Legion) as Legionnaire Shylock [npc=22707]._\n6\\. Return the Sixth Fragment of the Heroes' Disk to Rokiln's Tomb 0/1 (Vergalid Mines)\n_Drop off Legionnaire Shylock [npc=22707]_\n\n---\n\n_Reward:_\nDisk of Heroes [item=51953] ( _used in the Shield of the Otherworld [quest=4117] task_)\nLORE ITEM NO TRADE AUGMENTATION\nAugmentation type: 7 8\nSlot: HEAD FACE EAR NECK SHOULDERS ARMS BACK WRIST RANGE HANDS PRIMARY SECONDARY FINGER CHEST LEGS FEET WAIST\nMANA: +50 ENDUR: +50\nAvoidance: +5 Accuracy: +5\nRecommended level of 60. Required level of 53.\nWT: 0.0 Size: TINY\nClass: ALL\nRace: ALL\n- Disk of Heroes [item=51953]",
    },
    {
      id = "3707",
      title = "Access to the Ancient Ruins (Inner Vergalid)",
      exp = "12",
      exp_name = "The Serpent's Spine",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Unknown",
      loc = { y = 898.0, x = -1486.0, z = 0.0 },
      triggers = {
      },
      items_required = {
      },
      rewards = {
        { id = 52549, name = "Arid Indicolite Shard", type = "item" },
        { id = 52550, name = "Flawless Indicolite Shard", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Vergalid Mines [zone=440]\nRating:\n0/1**_\\*__\\*__\\*__\\*__\\*_**\n(From 1 rating)\nInformation:\n**Level:** | 70\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | No\n**Can Be Shrouded?:** | No\n**Quest Type:** | Guide\n**Quest Goal:**\n- Advancement\n**Quest Items:**\n- Arid Indicolite Shard [item=52549]\n**Era:** | !Serpents Spine\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Sun Oct 8 21:30:15 2006\nModified: Tue Dec 5 05:21:04 2023 | | Several Vergalid Mines quests require that you explore the \"Ancient Ruins\".\nThe loc for these ruins is 583, -2010. This is in an area reachable only by using a key.\n1) Loot an Arid Indicolite Shard. This drops off Kickpick and Skullcrush mobs in the zone.\nThe Shard is flagged temporary, so don't camp before putting it to use.\n2) Go to the Shrine of Zek, blue crystals in the NE of the zone that are also explored as part of the Wanderlust quest. They can be found at 898, -1486.\n3) Stand on/at the crystals and right-click your Arid Indicolite Shard. This will give you message \"You infuse the crystal's power into Vergalid's life stream.\"\n4) You receive a Flawless Indicolite Shard and can now click on the statue just to your east to reach the inner area of Vergalid Mines.\nOne person is keyed by this. Just you. However, /corpse can drag people through, and CoH works as well.\n**Submitted by:** Lias Roxx, Defiant, Zek\n- Flawless Indicolite Shard [item=52550]",
    },
  },
}
