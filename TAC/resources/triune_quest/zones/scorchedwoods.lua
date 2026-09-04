-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for Scorched Woods (scorchedwoods)
-- Total Quests: 12
-- ============================================================================

return {
  zone = "scorchedwoods",
  zone_name = "Scorched Woods",
  quests = {
    {
      id = "8266",
      title = "Bad Horses",
      exp = "23",
      exp_name = "Empires of Kunark",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Taskmaster Errgh",
      loc = { y = -861.17, x = -2836.79, z = -374.59 },
      triggers = {
        "Hail, Taskmaster Errgh",
        "horses",
        "_Quests_",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Scorched Woods [zone=1087]\n**Who:**\n- Taskmaster Errgh [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Quest\n**Quest Goal:**\n- Advancement\n- Experience\n- Money\n**Success Lockout Timer**: 00:30:00\n**Faction Required:**\nThe Clawdigger Clan (Min: Indifferent)\n**Factions Raised:**\n- The Clawdigger Clan +100\n**Factions Lowered:**\n- Majestic Centurion Alliance -47\n**Era:** | !Empires of Kunark\nRecommended:\n**Group Size:** | Solo\n**Min. # of Players:** | 1\n**Max. # of Players:** | 1\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Sat Oct 15 22:41:11 2016\nModified: Tue Dec 5 05:21:04 2023 | | If you have faction issues getting this quest, illusion yourself and then try again.\nYou say, 'Hail, Taskmaster Errgh'\nTaskmaster Errgh proffers some assorted gemstones and polished coins, 'Need dig. Kill [horses]?!'\nYou say, 'horses'\nTaskmaster Errgh glances eastwards pensively, nodding as he lifts a thick claw, 'Bad horses. Mmmm,' squinting his eyes into a determined glare.\nYou have been assigned the task 'Bad Horses'.\n\n---\n\nFend off the centaurs. 0/7 (Scorched Woods)\nKill centaurs around quest givers Guardian Limnos and Orrin Dracos. /Loc -861.17, -2836.79, -374.59\nReward(s):\n106pp 5gp\nExperience\n- 106pp 5gp, Experience",
    },
    {
      id = "8263",
      title = "The Roaming Scourge",
      exp = "23",
      exp_name = "Empires of Kunark",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Strategus Pommori",
      loc = { y = -2702.0, x = -1497.0, z = -369.0 },
      triggers = {
        "use",
        "_Quests_",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
        { name = "New Combine", change = 10 },
        { name = "Legion of the Overking", change = -1 },
        { name = "Flamescale Legion", change = -1 },
        { name = "New Combine Guards", change = 1 },
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Scorched Woods [zone=1087]\n**Who:**\n- Strategus Pommori [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n- Experience\n- Money\n**Factions Raised:**\n- New Combine +10\n- New Combine Guards +1\n**Factions Lowered:**\n- Empire of the Di`Zok -1\n- Flamescale Legion -1\n- Kar`zok -1\n- Legion of the Overking -1\n**Related Creatures:**\n- a moldering gorilla [npc=51571]\n- a tatterback gorilla [npc=51606]\n- a tottering gorilla [npc=51570]\n- a wurm-scorched skeleton [npc=51596]\n- greater barbed skeleton [npc=51567]\n- greater plague skeleton [npc=51572]\n- greater war boned skeleton [npc=51569]\n- plaguebone skeleton - Scorched Woods [npc=51568]\n**Era:** | !Empires of Kunark\nRecommended:\n**Group Size:** | Solo\n**Min. # of Players:** | 1\n**Max. # of Players:** | 1\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Fri Oct 14 23:17:24 2016\nModified: Tue Dec 5 05:21:04 2023 | | Find Strategus Pommori in Scorched Woods near the Lceanium zone line at location -2702, -1497, -369.\nSay \"use\" to him to get a listing of tasks.\nYou say, 'use'\nStrategus Pommori says 'Drive back the indigenous chaff. We'll need to secure our flanks if we're going to hold the area.'\nYou have been assigned the task 'The Roaming Scourge'.\n\n---\n\nClear out the skeletons and gorillas 0/6 (Scorched Woods)\nReward(s):\n106 platinum 5 gold\nYou gain experience!\nIncreases your faction with New Combine.\nYour faction standing with New Combine has been adjusted by 10.\nYour faction standing with Legion of the Overking has been adjusted by -1.\nYour faction standing with Empire of the Di`Zok has been adjusted by -1.\nYour faction standing with Kar`Zok has been adjusted by -1.\nYour faction standing with Flamescale Legion has been adjusted by -1.\nYour faction standing with New Combine Guards has been adjusted by 1.\n**Submitted by:** Gidono\n- 106pp 5gp, Experience",
    },
    {
      id = "8264",
      title = "Dousing the Flames",
      exp = "23",
      exp_name = "Empires of Kunark",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Strategus Pommori",
      loc = { y = -2702.0, x = -1497.0, z = -369.0 },
      triggers = {
        "use",
        "_Quests_",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
        { name = "New Combine", change = 10 },
        { name = "Legion of the Overking", change = -1 },
        { name = "Flamescale Legion", change = -1 },
        { name = "New Combine Guards", change = 1 },
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Scorched Woods [zone=1087]\n**Who:**\n- Strategus Pommori [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n- Experience\n- Money\n**Factions Raised:**\n- New Combine +10\n- New Combine Guards +1\n**Factions Lowered:**\n- Empire of the Di`Zok -1\n- Flamescale Legion -1\n- Kar`zok -1\n- Legion of the Overking -1\n**Related Creatures:**\n- a blaze elemental [npc=51162]\n- a cinder elemental [npc=51163]\n**Era:** | !Empires of Kunark\nRecommended:\n**Group Size:** | Solo\n**Min. # of Players:** | 1\n**Max. # of Players:** | 1\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Sat Oct 15 22:08:00 2016\nModified: Tue Dec 5 05:21:04 2023 | | Find Strategus Pommori in Scorched Woods near the Lceanium zone line at location -2702, -1497, -369.\nSay \"use\" to him to get a listing of tasks.\nYou say, 'use'\nStrategus Pommori says 'Drive back the indigenous chaff. We'll need to secure our flanks if we're going to hold the area.'\nYou have been assigned the task 'Dousing the Flames'.\n\n---\n\nExtinguish the elementals. 0/6 Scorched Woods\nKill blaze elementals [npc=51162] and cinder elementals [npc=51163] in the central north part of the zone.\nReward(s):\n106 platinum 5 gold\nYou gain experience!\nIncreases your faction with New Combine.\nYour faction standing with New Combine has been adjusted by 10.\nYour faction standing with Legion of the Overking has been adjusted by -1.\nYour faction standing with Empire of the Di`Zok has been adjusted by -1.\nYour faction standing with Kar`Zok has been adjusted by -1.\nYour faction standing with Flamescale Legion has been adjusted by -1.\nYour faction standing with New Combine Guards has been adjusted by 1.\n- 106pp 5gp, Experience",
    },
    {
      id = "8265",
      title = "Death from Above",
      exp = "23",
      exp_name = "Empires of Kunark",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Strategus Pommori",
      loc = { y = -2702.0, x = -1497.0, z = -369.0 },
      triggers = {
        "use",
        "_Quests_",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Scorched Woods [zone=1087]\n**Who:**\n- Strategus Pommori [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Time:** | Unlimited\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n- Experience\n- Money\n**Era:** | !Empires of Kunark\nRecommended:\n**Group Size:** | Solo\n**Min. # of Players:** | 1\n**Max. # of Players:** | 1\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Sat Oct 15 22:15:41 2016\nModified: Tue Dec 5 05:21:04 2023 | | Find Strategus Pommori in Scorched Woods near the Lceanium zone line at location -2702, -1497, -369.\nSay \"use\" to him to get a listing of tasks.\nYou say, 'use'\nStrategus Pommori says 'Drive back the indigenous chaff. We'll need to secure our flanks if we're going to hold the area.'\nYou have been assigned the task 'Death from Above'.\n\n---\n\nExterminate the ember and cinder daubers. 0/6 Scorched Woods\nReward(s):\n106pp 5gp\nExperience\n**Need more info on this quest.**\n- 106pp 5gp, Experience",
    },
    {
      id = "8267",
      title = "Clearing Loose Fodder",
      exp = "23",
      exp_name = "Empires of Kunark",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Tactician Orlexa",
      loc = nil,
      triggers = {
        "strategy",
        "EoK",
        "Empires of Kunark",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Scorched Woods [zone=1087]\n**Who:**\n- Tactician Orlexa [npc=51059]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Time:** | Unlimited\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n- Experience\n- Money\n**Related Zones:**\n- Chardok [EoK]\n**Related Creatures:**\n- a reanimated berserker [npc=51503]\n- a reanimated champion [npc=51469]\n- a reanimated dragoon [npc=51443]\n- a reanimated partisan [npc=51471]\n**Era:** | !Empires of Kunark\nRecommended:\n**Group Size:** | Solo\n**Min. # of Players:** | 1\n**Max. # of Players:** | 1\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Sun Oct 16 00:33:11 2016\nModified: Tue Dec 5 05:21:04 2023 | | Clearing Loose Fodder\nFind Tactician Orlexa in Scorched Woods\nSay \"strategy\" to her to get a listing of tasks.\nYou say, 'strategy'\nTactician Orlexa says 'Their beasts and battle-fodder are poorly guarded and should prove easy targets. If we can disrupt their leadership, their rigid hierarchy will be slow to adapt.'\nYou have been assigned the task 'Clearing Loose Fodder'.\n\n---\n\nDestroy the reanimated undead. 0/8 Chardok [Empires of Kunark]\na reanimated partisan [npc=51471]\na reanimated berserker [npc=51503]\na reanimated champion [npc=51469]\na reanimated dragoon [npc=51443]\nReward(s):\n106pp 5gp\nExperience\n**Need more info on this quest.**\n- 106pp 5gp, Experience",
    },
    {
      id = "8268",
      title = "Friends of the Enemy",
      exp = "23",
      exp_name = "Empires of Kunark",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Tactician Orlexa",
      loc = nil,
      triggers = {
        "strategy",
        "EoK",
        "Empires of Kunark",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Scorched Woods [zone=1087]\n**Who:**\n- Tactician Orlexa [npc=51059]\nRating:\n0/1**_\\*__\\*__\\*__\\*__\\*_**\n(From 1 rating)\nInformation:\n**Time:** | Unlimited\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n- Experience\n- Money\n**Related Zones:**\n- Chardok [EoK]\n**Related Creatures:**\n- a chokidai fleshripper [npc=51070]\n**Era:** | !Empires of Kunark\nRecommended:\n**Group Size:** | Solo\n**Min. # of Players:** | 1\n**Max. # of Players:** | 1\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Sun Oct 16 00:50:59 2016\nModified: Mon Nov 18 22:46:30 2024 | | Find Tactician Orlexa in Scorched Woods\nSay \"strategy\" to her to get a listing of tasks.\nYou say, 'strategy'\nTactician Orlexa says 'Their beasts and battle-fodder are poorly guarded and should prove easy targets. If we can disrupt their leadership, their rigid hierarchy will be slow to adapt.'\nYou have been assigned the task 'Friends of the Enemy'.\n\n---\n\nPut down the chaokidai fleshrippers. 0/6 Chardok[Empires of Kunark]\nReward(s):\n106pp 5gp\nExperience\n**Need more info on this quest.**\n- 106pp 5gp, Experience",
    },
    {
      id = "8347",
      title = "Mercenary of The Scorched Woods",
      exp = "23",
      exp_name = "Empires of Kunark",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Unknown",
      loc = nil,
      triggers = {
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Scorched Woods [zone=1087]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | No\n**Can Be Shrouded?:** | No\n**Quest Type:** | Achievement\n**Quest Goal:**\n- Experience\n**Related Quests:**\n- Bad Horses [quest=8266]\n- Burrowing Desecrators [quest=8394]\n- Death from Above [quest=8265]\n- Dousing the Flames [quest=8264]\n- The Roaming Scourge [quest=8263]\n**Era:** | !Empires of Kunark\nRecommended:\n**Group Size:** | Solo\n**Min. # of Players:** | 1\n**Max. # of Players:** | 1\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Wed Nov 2 21:14:40 2016\nModified: Mon May 6 02:11:32 2024 | | This achievement is gained upon completing the following quests in The Scorched Woods.\nStrategus Pommori - Dousing the Flames\nStrategus Pommori - Death from Above\nStrategus Pommori - The Roaming Scourge\nTaskmaster Errgh - Bad Horses\nGuardian Limnos - Burrowing Desecrators\n**Submitted by:** Gidono\n- 20 AA's",
    },
    {
      id = "8363",
      title = "The Last Grove",
      exp = "23",
      exp_name = "Empires of Kunark",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Orrin Dracos",
      loc = { y = -791.0, x = -2912.0, z = -372.0 },
      triggers = {
        "_Quests_",
      },
      items_required = {
      },
      rewards = {
        { id = 127541, name = "Clawdigger Clan Overseer's Plans", type = "item" },
        { id = 127538, name = "Clearcutter's Axe", type = "item" },
        { id = 127536, name = "Glob of Living Clay", type = "item" },
        { id = 127533, name = "Majestic Water Bucket", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Scorched Woods [zone=1087]\n**Who:**\n- Orrin Dracos [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | No\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n- Experience\n- Money\n**Faction Required:**\nMajestic Centurion Alliance (Min: Kindly)\n**Factions Raised:**\n- Majestic Centurion Alliance +200\n**Factions Lowered:**\n- The Clawdigger Clan -200\n**Quest Items:**\n- Clawdigger Clan Overseer's Plans [item=127541]\n- Clearcutter's Axe [item=127538]\n- Glob of Living Clay [item=127536]\n- Majestic Water Bucket [item=127533]\n**Related Creatures:**\n- Overseer Hani [npc=51182]\n- a greater mudmonster [npc=51603]\n- a mudmonster [npc=51154]\n- a murky ooze [npc=51152]\n- a sureshot scout [npc=51056]\n- a wounded centaur [npc=51131]\n**Era:** | !Empires of Kunark\nRecommended:\n**Group Size:** | Solo\n**Min. # of Players:** | 1\n**Max. # of Players:** | 1\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Wed Nov 9 22:51:07 2016\nModified: Tue Dec 5 05:21:04 2023 | | Orrin Dracos is located in Scorched Woods along the eastern wall at -791, -2912, -372.\nSay \"help us defend\" to get the task.\n\n---\n\n03. Talk to a wounded Centaur (0/1)\n\n\n\na wounded centaur [npc=51131] is in the center of the camp. Hail him, he sends you to ...\n\n04. Talk to Orrin Dracos (0/1)\n\n\n\nHe tells you that the smoke from all the fires is making things worse for the wounded, and gives you three things to do, and hands you a Majestic Water Bucket [item=127533] for doing one of them.\n\n05. Kill constructs of magma or coal (0/3)\n\n06. Kill fire elementals (0/8)\n\n\n\nCenter of the North part of the zone.\n\n\n\n\na blaze elemenal [npc=51162] counts\n\n\na cinder elemental [npc=51163] counts.\n\n\na spirit of flame [npc=51164] counts\n\n07. Extinguish wild fire elementals (0/12)\n\n\n\nWhen you kill the fire elementals, 1-4 \"a wild fire\" will spawn, low level range, does not attack and cannot be attacked. Target them and click the Majestic Water Bucket [item=127533] on them. It has a short range, typical to run slightly ahead of them and come to a complete stop before clicking.\n\n08. Return the Majestic Water Bucket to Orrin Dracos\n\n09. Collect Living Clay (0/4)\n\n\n\nGlob of Living Clay [item=127536] drops off a mudmonster [npc=51154], a greater mudmonster [npc=51603] or a murky ooze [npc=51152] found in the southwest corner of zone with daubers.\n\n10. Deliver the Living Clay to the wounded centaurs (0/4)\n\n\n\nI gave all four to the same centaur one at a time and got credit.\n\n11. Talk to Orrin Dracos\n\n12. Kill Kromdul giants (0/12)\n\n13. Collect Clearcutter Axes (0/5)\n\n\n\nClearcutter's Axe [item=127538] drops off a forest giant clearcutter [npc=51156] and a forest giant madcutter [npc=51157].\n\n14. Deliver Clearcutter Axes to Orrin Draccos (0/5)\n\n15. Talk to Orrin Dracos\n\n16. Accompany sureshot scouts (0/3)\n\n\n\nI got three updates following two sureshot scouts [npc=51056]. Each time they stopped I got an update.\n\n17. Talk to Orrin Dracos\n\n18. Kill Burynai (0/8)\n\n19. Kill Overseer Hani (0/1)\n\n20. Collect Clawdigger Clan Overseerâ€™s Plans\n\n21. Deliver Clawdigger Clan Overseerâ€™s Plans to Orrin Dracos (0/1)\n\n22. Talk to Orrin Dracos\n\n\n---\n\nReward(s):\nFaction: +200 to Majestic Centurion Alliance, -200 to The Clawdigger Clan.\n**Need info on the reward and more info on quest steps**.\n**Submitted by:** Deloehne\n- 638 PP, Experience",
    },
    {
      id = "8381",
      title = "On Nobody's Side",
      exp = "23",
      exp_name = "Empires of Kunark",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Domina Caelestis",
      loc = { y = -1490.0, x = -2561.0, z = 0.0 },
      triggers = {
        "EoK",
        "_Combine Kromdul Liaison_",
        "_Sneekee Spie_",
        "_Combine Analyst_",
        "_Representative of Tsaph_",
        "_Lost and Confused_",
        "ready",
      },
      items_required = {
        { name = "you 4", count = 1 },
        { name = "the Scorched Thoraxes to Domina Caelestis (0/4)", count = 1 },
      },
      rewards = {
        { id = 127771, name = "Meteorite Mining Pick", type = "item" },
        { id = 127527, name = "Scorched Meteorite Chunk", type = "item" },
        { id = 127529, name = "Scorched Thorax", type = "item" },
        { id = 127526, name = "Scorched Watcher Log", type = "item" },
        { id = 127530, name = "Seismo Scepter", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Scorched Woods [zone=1087]\n**Who:**\n- Domina Caelestis [npc=51045]\nRating:\n0/1**_\\*__\\*__\\*__\\*__\\*_**\n(From 1 rating)\nInformation:\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | No\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n- Experience\n- Money\n**Faction Required:**\nMajestic Centurion Alliance (Min: Amiable)\n**Quest Items:**\n- Meteorite Mining Pick [item=127771]\n- Scorched Meteorite Chunk [item=127527]\n- Scorched Thorax [item=127529]\n- Scorched Watcher Log [item=127526]\n- Seismo Scepter [item=127530]\n**Related Zones:**\n- Frontier Mountains [EoK]\n**Related Creatures:**\n- Ambassador Gruds [ _Combine Kromdul Liaison_]\n- Gorga Golo [ _Sneekee Spie_]\n- Grazen Aeliubi [ _Combine Analyst_]\n- Helenus Politi [npc=51052]\n- High Praetor Lcea Katta [ _Representative of Tsaph_]\n- Opp Feelsick [ _Lost and Confused_]\n- a Chardok Gnomeslaver [npc=51759]\n- a disturbed ancestor [npc=51668]\n**Era:** | !Empires of Kunark\nRecommended:\n**Group Size:** | Group\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Fri Nov 11 23:04:53 2016\nModified: Sat Nov 9 09:37:18 2024 | | Pre Requisite Quests: Concerned Citizens, Contacting the Leadership, Disappearing Dragons, Sneaky Sarnak, and Where is Burning Woods?\nFind Domina Caelestis in Scorched Woods, she is near the Lceanium zone line.\nSay \"Leverage\" to get the task.\n\n---\n\n1.Collect Scorched Meteorite Chunks (0/4)\nâ€œThe Combine wants to research the meteorite further. Collect Scorched Meteorite Chunks from burynai near the crash site. Head Taskmaster Geddis may be willing to help friends acquire chunks of the meteorite peacefully as well.â€\nEither kill burynais and loot Scorched Meteorite Chunks, or buy a Meteorite Mining Pick from Head Taskmaster Geddis and use it.\n2.Collect Scorched Watcher Logs (0/4)\nâ€œThe centaur in the region keep rigorous notes of the local animals and flora. Their logs will provide a lot of data for Combine scientists to use when analyzing the effects of the meteorite here. Collect Scorched Watcher Logs from centaur East of the crash site. Helenus Politi may be willing to help friends acquire the logs peacefully.â€\nEither kill centaurs and loot Scorched Watcher Logs, or hail Helenus Politi and he will give you 4. Amiable faction with Majestic Centurion Alliance should be enough to get him to talk to you.\n**Killing Burynai and doing the merc quest by the centaurs will raise Majestic Centurion Alliance faction.**\n3.Collect Scorched Thoraxes (0/4)\nKill insects.\n4.Give the Scorched Meteorite Chunks to Domina Caelestis (0/4)\n5.Give the Scorched Watcher Logs to Domina Caelestis (0/4)\n6.Give the Scorched Thoraxes to Domina Caelestis (0/4)\n7.Ask Domina Caelestis what to do next. (0/1)\nHail her.\n8.Meet Grazen Aeliubi at the Ancient Iksar (0/1)\nSheâ€™s at the statue of an Iksar straight in from the FM zone line at -1490, -2561. Hail her.\nHe tells you he is about to be attacked and that you should tell him when you are [ready].\n9.Defend Grazen while she monitors seismic activity (0/1)\nThree waves of iksar skeletons -â€a disturbed ancestorâ€ (2/2/4) - spawn. They are dark blue at 105 and can be mezzed. Kill the waves.\n10.Meet Opp Feelsick at the Chardok Fortress (0/1)\nInside the outer wall of the fortress at loc 6344, -4326.\nHail him, and say â€œWho are you?â€. Go through the dialogue until you get to [ready].\n11.Defend Opp while he monitors magical activity\nThree waves of Chardok Gnomeslaver's (1/2/3) attack. Dark blue. Enchanter mezzable. Can be snared and punted.\n12.Meet Gorga Golo at the base of Fort Kromdolâ€™s East Tower\nHail her.\n13.Use Gorgaâ€™s Seismo Scepter near her.\nHail and follow dialog. Two rounds of giants attack. First round, one giant. Second round, 4 giants. On the last wave a Combine pally shows up and kicks ass.\nYou do not have to deal with all four giants. You can buff Gorga as you like, and let them beat on her, while you kill just one of the giants. At that point Lcea will arrive and kill the rest of them in an instant.\nClick the scepter now in your inventory for the update.\n14.Meet Ambassador Gruds near Fort Kromdulâ€™s Southern tower\nThis is on the elevated walkway between the main fort and the Southern tower.\nHail and dialog. Lcea shows up and the two of them walk to the Southern tower.\n15.Witness Lceaâ€™s negotiations\nFollow her to the tower, she will â€˜negotiateâ€™ with the giants there with a lengthy discussion that ends with her killing two of them.\n16.Kill the last King of Kromdul\nHeâ€™s the only one of the three left standing. Scholar Greagor is dark blue and has 13 - 14 million HP. Somehow Lcea has lost her dps ability, so it is all up to you.\n17.Report back to Domina Caelestis\n**Submitted by:** Deloehne\n- 567 Platinum, Experience",
    },
    {
      id = "8394",
      title = "Burrowing Desecrators",
      exp = "23",
      exp_name = "Empires of Kunark",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Guardian Limnos",
      loc = nil,
      triggers = {
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Scorched Woods [zone=1087]\n**Who:**\n- Guardian Limnos [npc=51049]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n- Experience\n- Money\n**Success Lockout Timer**: 00:30:00\n**Factions Raised:**\n- Majestic Centurion Alliance +100\n**Factions Lowered:**\n- The Clawdigger Clan -100\n**Related Creatures:**\n- a burynai taskmaster [npc=51046]\n**Era:** | !Empires of Kunark\nRecommended:\n**Group Size:** | Solo\n**Min. # of Players:** | 1\n**Max. # of Players:** | 1\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Mon Nov 21 20:29:56 2016\nModified: Tue Dec 5 05:21:04 2023 | | Pre requisite: Indifferent faction with Majestic Centurion Alliance.\nFind Guardian Limnos at the centaur camp near the east wall.\nSay mining to him to get the task.\n\n---\n\nStrike at the burynai taskmasters. 0/9 Scorched Woods\nKill 9 Burynai taskmasters at the dig site in the middle of the zone.\n\n---\n\nReward(s):\n106 platinum 5 gold\nYou gain experience!\nFactions Raised at level 110:\nMajestic Centurion Alliance +100\nFactions Lowered:\nThe Clawdigger Clan -100\n**Submitted by:** Gidono\n- 106pp 5gp, Experience",
    },
    {
      id = "8411",
      title = "Others' Things",
      exp = "23",
      exp_name = "Empires of Kunark",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Arbitrator Kelliar",
      loc = nil,
      triggers = {
        "Hail, Arbitrator Kelliar",
        "do things",
        "others",
        "liberate",
        "_Heroic Adventures_",
        "for the Combine",
        "ready",
      },
      items_required = {
        { name = "you directions when you are [ready]", count = 1 },
      },
      rewards = {
        { id = 127783, name = "Ancient Golden Bracelet", type = "item" },
        { id = 132660, name = "Fungus Spores", type = "item" },
        { id = 128290, name = "Sarnak Stout", type = "item" },
        { id = 127780, name = "Shimmering Shell", type = "item" },
        { id = 127782, name = "Viable Chokidai Egg", type = "item" },
        { id = 126749, name = "Sathir Trade Gem", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Scorched Woods [zone=1087]\n**Who:**\n- Arbitrator Kelliar [ _Heroic Adventures_]\nRating:\n0/1**_\\*__\\*__\\*__\\*__\\*_**\n(From 1 rating)\nInformation:\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Adventure\n**Quest Goal:**\n- Advancement\n- Experience\n- Money\n**Success Lockout Timer**: 00:03:00\n**Quest Items:**\n- Ancient Golden Bracelet [item=127783]\n- Di`Zok Signet Ring [item=127784]\n- Fungus Spores [item=132660]\n- Sarnak Stout [item=128290]\n- Shimmering Shell [item=127780]\n- Viable Chokidai Egg [item=127782]\n**Related Zones:**\n- Chardok: Other's Things [zone=1099]\n**Related Creatures:**\n- Dread Overseer Akalod [npc=51002]\n- a chokidai egg sac [npc=54615]\n- a chokidai fleshripper [npc=53918]\n- a frantic beetle [npc=54650]\n- a hungry beetle [npc=54651]\n- a magic fracture [npc=54649]\n- a magic shard [npc=53761]\n- a moldering fungusman [npc=54653]\n- a twisted fungusman [npc=54654]\n- a weary overseer [npc=52481]\n- a wild fungusman [npc=54655]\n**Era:** | !Empires of Kunark\nRecommended:\n**Group Size:** | Solo\n**Min. # of Players:** | 1\n**Max. # of Players:** | 6\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Fri Dec 2 21:02:12 2016\nModified: Tue Nov 19 03:36:02 2024 | | This HA can be gotten from Arbitrator Kelliar [npc=51062] in Scorched Woods. He is located in the northwestern part of the zone, northeast of the giant fort. 2426, 1971, -364.\nThere is a 1 hour lockout between requesting different missions.\nYou say, 'Hail, Arbitrator Kelliar'\nArbitrator Kelliar says 'Hello, friend. These are challenging times, but the Combine grows. I am pleased to see that you are choosing to be part of that. I, of course, have a small part to play in this as well. I seek those willing to do more than chat about important deeds. I need people that are ready to [do things].'\nYou say, 'do things'\nArbitrator Kelliar says 'I have the honor of representing a few agencies at this time. Of course my primary duty is to getting tasks [for the Combine] accomplished, but there are always [others] that have needs and desires.'\nYou say, 'others'\nArbitrator Kelliar says 'Others such as allies, friends, associates. I'm sure you know the sort. These others are looking for more, um, eccentric items. Nothing official, mind you, I just need someone to [liberate] a few meaningless trinkets.'\nYou say, 'liberate' <--- keyword to get task.\nArbitrator Kelliar says 'Ah, wonderful. Here is a list of what those others are looking for. I can give you directions when you are [ready].'\nSay ready to zone in.\n**This HA locks on request.**\nThis task has many different versions. Please post your versions in the comments.\n\n---\n\nThis task takes place in Chardok.\n2. Certainly the sarnak wear some sort of jewelry, right? See if you can find some.\n\n\n\nKill lower level Di'zok sarnak and loot off them. Look on the east side. Look for a big room full of sarnaks marked 'night garden water supply'? on your map, near the big pool of water & buncha fungus guys nearby as well for the fungus.\n\n\n\n\nLoot Di'Zok Signet Ring\n\n\n\n\nP 990.7554, 169.5216, -423.0159, 240, 0, 0, 1, Jewelry\\_area\n\n3. Collect some chokadai eggs. There are some people that would like to try to breed them.\n\n\n\nViable Chokidai Egg's are found in NE area. Find a chokidai egg sac, beat them down, and then loot the eggs.\n\n\n\n\nP 1395.6283, -179.8114, -414.4752, 240, 0, 0, 1, Egg\n\n\nP 1739.0844, 214.9650, -360.1393, 240, 0, 0, 1, Egg\n\n\nP 1738.3234, 171.2867, -362.8181, 240, 0, 0, 1, Egg\n\n\nP 1846.2144, 206.2096, -362.1161, 240, 0, 0, 1, Egg\n\n\nP 1883.9369, -12.6891, -397.2339, 240, 0, 0, 1, Egg\n\n\nP 1758.9602, -66.0496, -414.7031, 240, 0, 0, 1, Egg\n\n\nP 1693.3336, -8.7594, -414.3121, 240, 0, 0, 1, Egg\n\n\nP 1755.1814, -167.9519, -421.6051, 240, 0, 0, 1, Egg\n\n\nP 1736.3792, -179.1865, -422.7024, 240, 0, 0, 1, Egg\n\n\nP 1620.2678, -277.0259, -414.3043, 240, 0, 0, 1, Egg\n\n\nP 1404.1398, -266.3790, -414.7024, 240, 0, 0, 1, Egg\n\n\nP 1573.6221, 124.1245, -405.1925, 240, 0, 0, 1, Egg\n\n\nP 1517.9443, 10.0404, -414.8255, 240, 0, 0, 1, Egg\n\n4. Rumor has it that there are some colorful beetles in Chardok. Bring some of their shells.\n\n\n\nKill beetles to the East and loot 10 Shimmering Shell. They are hard to find enough. I also found some in the upper north tunnels.\n\n5. Dread Overseer Akalod or its PH will spawn.\n\n6. Most importantly, there are rumors of a vault in the basement. Go there, get things.\n\n\n\nKill Magic fractures and loot Ancient Golden Bracelet's. Note fractures are not mezzable, but they can be snared or rooted.\n\n\n---\n\n**Version #2**\n2. Certainly the sarnak wear some sort of jewelry, right? See if you can find some.\n\n\n\nKill lower level Di'zok sarnak and loot off them. Look on the east side.\n\n\n\n\nP 990.7554, 169.5216, -423.0159, 240, 0, 0, 1, Jewelry\\_area\n\n3. Crystals of all sorts can be found in Chardok, gather some.\n\n\n\nFind the color crystals and click on them. You can be invis when clicking and invis doesn't drop.\n\n4. There are some odd folks that like odd fungus parts in their food. See if you can find any.\n\n\n\nKill the mushrooms and click on the drops. They aren't mezzable but, are rootable.\n\n5. Dread Overseer Akalod or its PH will spawn.\n\n6. Most importantly, there are rumors of a vault in the basement. Go there, get things.\n\n\n\nKill Magic fractures and loot Ancient Golden Bracelet's. Note fractures are not mezzable, but they can be snared or rooted.\n\n\n---\n\n**Version #3**\n2. Some scouts have found some sort of ale on the Sarnak. If they are brewing their own, there are people that will want it.\n\n\n\nLoot 10 \"sarnak stout\" from sarnaks\n\n\n\n\nBrewery is found at /loc neg160 neg1400 neg400 in the blue building complex.\n\n3. Crystals of all sorts can be found in Chardok, gather some. 0/10\n\n\n\nFind the color crystals and click on them. You can be invis when clicking and invis doesn't drop. Click on 10 of them.\n\n4. There are some odd folks that like odd fungus parts in their food. See if you can find any. 0/5\n\n\n\nLoot 5 \" fungus spores\" they drop from the mushrooms.\n\n5. Most importantly there are rumors of a vault in the basement. Go there, get things.\n\n\n\nLoot 3 \"Ancient Golden Bracelet\" from \"a magic shard\" or \"a magic fracture\" mobs.These monsters look like the standard rock whirlwinds. These were found in the far north part of the zone, 2 large square rooms.\n\n---\n\n**Version #4**\n3. Some scouts have found some sort of ale on the Sarnak. If they are brewing their own, there are people that will want it.\n\n\n\nLoot 10 \"sarnak stout\" from sarnaks\n\n\n\n\nBrewery is found at /loc neg160 neg1400 neg400 in the blue building complex.\n\n4. Collect some chokadai eggs. There are some people that would like to try to breed them.\n\n\n\nViable Chokidai Egg's are found in NE area. Find a chokidai egg sac, beat them down, and then loot the eggs.\n\n\n\n\nP 1395.6283, -179.8114, -414.4752, 240, 0, 0, 1, Egg\n\n\nP 1739.0844, 214.9650, -360.1393, 240, 0, 0, 1, Egg\n\n\nP 1738.3234, 171.2867, -362.8181, 240, 0, 0, 1, Egg\n\n\nP 1846.2144, 206.2096, -362.1161, 240, 0, 0, 1, Egg\n\n\nP 1883.9369, -12.6891, -397.2339, 240, 0, 0, 1, Egg\n\n\nP 1758.9602, -66.0496, -414.7031, 240, 0, 0, 1, Egg\n\n\nP 1693.3336, -8.7594, -414.3121, 240, 0, 0, 1, Egg\n\n\nP 1755.1814, -167.9519, -421.6051, 240, 0, 0, 1, Egg\n\n\nP 1736.3792, -179.1865, -422.7024, 240, 0, 0, 1, Egg\n\n\nP 1620.2678, -277.0259, -414.3043, 240, 0, 0, 1, Egg\n\n\nP 1404.1398, -266.3790, -414.7024, 240, 0, 0, 1, Egg\n\n\nP 1573.6221, 124.1245, -405.1925, 240, 0, 0, 1, Egg\n\n\nP 1517.9443, 10.0404, -414.8255, 240, 0, 0, 1, Egg\n\n5. Rumor has it that there are some colorful beetles in Chardok. Bring some of their shells.\n\n\n\nKill beetles to the East and loot 10 Shimmering Shell. They are hard to find enough. I also found some in the upper north tunnels.\n\n6. Most importantly, there are rumors of a vault in the basement. Go there, get things.\n\n\n\nKill Magic fractures and loot Ancient Golden Bracelet's. Note fractures are not mezzable, but they can be snared or rooted.\n\n---\n\nReward(s):\nRandom Cash\nExperience\nRandom amount of Sathir Trade Gems [item=126749]\n**Submitted by:** Fianb\n- Sathir Trade Gem [item=126749]",
    },
    {
      id = "8413",
      title = "Atrebe's Vault",
      exp = "23",
      exp_name = "Empires of Kunark",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Praetor Garont",
      loc = nil,
      triggers = {
        "_Raids_",
      },
      items_required = {
      },
      rewards = {
        { id = 127754, name = "Orb of Meekness", type = "item" },
        { id = 128030, name = "Orb of Meekness", type = "item" },
        { id = 128215, name = "Orb of Reverence", type = "item" },
        { id = 127753, name = "Orb of Reverence", type = "item" },
        { id = 134933, name = "Orb of Submission", type = "item" },
        { id = 127752, name = "Orb of Submission", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Scorched Woods [zone=1087]\n**Who:**\n- Praetor Garont [ _Raids_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Time:** | 360\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Experience\n- Loot\n- Money\n**Success Lockout Timer**: 06:00:00\n**Quest Items:**\n- Orb of Meekness [item=127754]\n- Orb of Meekness [item=128030]\n- Orb of Reverence [item=128215]\n- Orb of Reverence [item=127753]\n- Orb of Submission [item=134933]\n- Orb of Submission [item=127752]\n**Related Zones:**\n- Chardok: Atrebe's Vault (group) [zone=1101]\n**Related Creatures:**\n- Ancient Guardian of the Vault [npc=51714]\n- a fancy chest [npc=51715]\n- a living tome [npc=51713]\n- a lorenado [npc=51712]\n- a magical siphon [npc=51711]\n- an essence hammer [npc=51710]\n- an executioner's axe [npc=51716]\n- an imperial construct [npc=51709]\n**Related Quests:**\n- Hero of Chardok [quest=8345]\n**Era:** | !Empires of Kunark\nRecommended:\n**Group Size:** | Group\n**Min. # of Players:** | 3\n**Max. # of Players:** | 6\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Sat Dec 3 09:52:49 2016\nModified: Sun Sep 7 01:44:42 2025 | | _There is a 1 hour lockout between different missions._\n_This is a group mission. Say **smaller group** to Praetor Garont in Scorched Woods to trigger the mission. The person triggering must have the Partisan of Lceanium [quest=8274], Partisan of The Scorched Woods [quest=8348] and Partisan of Chardok [quest=8354] achievements_\n_Say **go** to enter the instance._\nDiscover what the sarnak have found, if anything, deep in the heart of Chardok. 0/1\nThe Praetor suggests that you sneak into Chardok and look for an ancient vault that the sarnak are rumored to have discovered.\nThis event starts as soon as you go into the next room.\n4 waves of mobs spawn in pairs.\n1. an essence hammer\n\n2. an executioner`s axe\n\n3. a magical siphon\n\n4. a lorenado\nAs soon as you kill them, the next pair spawns. Once you get to the lorenado, it will spawn adds. Make sure to kill those adds before you kill the lorenado or else you'll end up with more adds from the next lorenado.\nWhen all 4 waves are dead Ancient Guardian of the Vault spawns. Take its health down to 45% and then it will spawn a totem in the north room which spawns adds.\nIn that same room, there are items you can use to stop the totem. They are ground spawns. Orb of Meekness [item=127754], Orb of Reverence [item=127753], and Orb of Submission [item=127752].\nChest is in the North ROOM its not on find and not a step on the task but their is loot if you open it .\nReward(s):\n212 platinum 5 gold\nYou gain experience!!\nAchievement: Hero of Chardok",
    },
  },
}
