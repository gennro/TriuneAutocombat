-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for North Ro 2.0 (nro)
-- Total Quests: 2
-- ============================================================================

return {
  zone = "nro",
  zone_name = "North Ro 2.0",
  quests = {
    {
      id = "3782",
      title = "LDoN Raid: Takish-Hiz: Within the Compact",
      exp = "06",
      exp_name = "Lost Dungeons of Norrath",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Efrelle Treiui",
      loc = nil,
      triggers = {
        "Hail, Efrelle Treiui",
        "A problem?",
        "I",
        "_Raid Recruiter_",
        "problem",
        "interested",
        "hail",
      },
      items_required = {
      },
      rewards = {
        { id = 56429, name = "Tweyne the Sandcaller's Report", type = "item" },
        { id = 55531, name = "Unala the Avenger's Scribbled Proposal", type = "item" },
        { id = 64201, name = "Flowkeeper's Gem of Replenishment", type = "item" },
        { id = 25081, name = "Geomantic Compact Chanting Stone", type = "item" },
        { id = 25082, name = "Ledanne's Jewel of Cessation", type = "item" },
        { id = 56167, name = "Quintessence Gem of Enhanced Agression", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- North Ro 2.0 [zone=24]\n**Who:**\n- Efrelle Treiui [ _Raid Recruiter_]\nRating:\n0/1**_\\*__\\*__\\*__\\*__\\*_**\n(From 1 rating)\nInformation:\n**Level:** | 65\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Expedition\n**Quest Goal:**\n- Loot\n**Quest Items:**\n- Tweyne the Sandcaller's Report [item=56429]\n- Unala the Avenger's Scribbled Proposal [item=55531]\n**Related Zones:**\n- Takish-Hiz: Within the Compact (Raid) [zone=449]\n**Related Creatures:**\n- Kamoj the Protector [npc=52770]\n- Ledanne the Rejuvenator [npc=52771]\n- Quintessence of Sand [npc=24447]\n- Ritana the Convoker [npc=28480]\n- Ritanas Ornate Chest [npc=28481]\n- The Earthen Chest [npc=26447]\n- The Gem Encrusted Chest [npc=28484]\n- Thosan the Manipulator [npc=28479]\n- Tweyne the Sandcaller [npc=28485]\n- Unala the Avenger [npc=28482]\n**Era:** | !Lost Dungeons of Norrath\nRecommended:\n**Group Size:** | Raid\n**Min. # of Players:** | 6\n**Max. # of Players:** | 54\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Thu Oct 26 17:03:45 2006\nModified: Tue Dec 5 05:21:04 2023 | | _This raid expedition (6-54 players) begins with Efrelle Treiui in the North Ro Wayfarer camp._\nYou say, 'Hail, Efrelle Treiui'\nEfrelle Treiui says 'To have seen shades of my former ancestors in the broken city of Takish-Hiz has brought a darkness to my heart that I've never known. If I knew a way to restore the sand elves to their former beauty I would. For now though, there is much to learn from them. You look to be well-versed in the ways of the sand elves and Takish-Hiz. If you can rally the call of your friends perhaps you can help us with a serious [problem].'\nYou say, 'A problem?'\nEfrelle Treiui says 'Our presence in Takish-Hiz has given the aimless Jeweled Guard a purpose after so many years. Each day, more of them recall how to organize themselves in battle and they are forming armies with one purpose, to put an end to any intruder. That's us, friend. You will need your own army to put a stop to that growing force so it is safer for the rest of us. Are you [interested]?\nYou say, 'I'm interested'\nEfrelle Treiui says 'Do what is necessary, \\_\\_\\_\\_\\_. We cannot afford to allow the Jeweled Guard to impede our progress.\nThe direction to the entry to your instanced zone(s) have been marked on your compass.\nTakish-Hiz: Within the Compact is now available to you.\n\n---\n\n_Trash mobs in this zone hit for a max ~800. The first four nameds hit for a max ~1,400. The final named hits for a max ~2,100._\n_You'll need to clear your way to the circular room in the southwestern part of the zone._\n_In this room, you'll find five nameds:_\nQuintessence of Sand - is rooted until Ritana dies.\nRitana the Convoker - Casts Mana Spectrum [npc=28480] (PBAE 400', Prismatic -200. Increase Curse Counter by 24).\nAfter she repops she casts Curse of Takish-Hiz (PBAE 100' Prismatic -200. Decrease ATK by 300, Increase Curse Counter by 24, Decrease Hitpoints by 400 per tick)\nThosan the Manipulator - Casts Clinging Clay [npc=28479] (PBAE 400', Disease -300. Decrease ATK by 150, Increase Disease Counter by 24)\nTweyne the Sandcaller\nUnala the Avenger\n_The nameds are leashed to the room, so you can pull trash mobs out of there without a problem._\n_If you kill Thosan, Tweyne, and Unala but are out of range of the Quintessence of Sand, regardless of his health he begin summoning his current target. Its not a normal summon as it puts you right on top of him._\n_When you kill Thosan, Tweyne, and Unala, 2 mezzable elementals will spawn in their position. At level 70, their agro range was small enough that after killing the first two that were in the way, I was able to kill Ritana and the Quintessence without them agroing._\n_Then get the Quintessence of Sand down to 20% health at which point it gains a massive regeneration ability. Once the Quintessence is at 20%, you'll want to kill Ritana the Convoker. Once Ritana dies, you can kill the Quintessence._\n_Up to three chests spawn with loot following the death of the Quintessence._\n\n---\n\n_Known raid loot from this event (Two items from each chest, can have duplicates from the same chest):_\nRitanas Ornate Chest\nLedanne's Jewel of Cessation\nRitana's Refracting Prism\nRitana's Sandstone of Prowess\nUnala's Stone of Enhanced Protection\nFlowkeeper's Gem of Replenishment\nThe Gem Encrusted Chest\nGeomantic Compact Chanting Stone\nQuintessence Jewel of Fiery Pain\nTarnished Vambraces of Dark Magic\nTunic of Coalesced Sand\nThosan's Geomantic Compact Jewel\nQuintessence Gem of Enhanced Agression\nThe Earthen Chest\nGeomantic Compact's Healing Gem\nSparkling Bracer of the Jeweled Hero\nTweyne's Stone of Evocation\nUnala's Jewel of Life\nTweyne's Condensed Tidal Sands\n\n---\n\nEp59 Within the Compact LDoN Raid EverQuest TLP Mangler - YouTube\nTap to unmute\nEp59 Within the Compact LDoN Raid EverQuest TLP Mangler Ion Blaze Gaming\nIon Blaze Gaming11.5K subscribers\nWatch on\n- Flowkeeper's Gem of Replenishment [item=64201]\n- Geomantic Compact Chanting Stone [item=25081]\n- Ledanne's Jewel of Cessation [item=25082]\n- Quintessence Gem of Enhanced Agression [item=56167]\n- Quintessence Jewel of Fiery Pain [item=56168]\n- Ritana's Refracting Prism [item=63246]\n- Ritana's Sandstone of Prowess [item=64447]\n- Tarnished Vambraces of Dark Magic [item=53357]\n- Thosan's Geomantic Compact Jewel [item=56675]\n- Tunic of Coalesced Sand [item=56676]\n- Unala's Stone of Enhanced Protection [item=53359]",
    },
    {
      id = "4409",
      title = "LDoN Raid: Takish-Hiz: The Palace Grounds",
      exp = "06",
      exp_name = "Lost Dungeons of Norrath",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Dizzl Nulzik",
      loc = nil,
      triggers = {
        "Hail, Dizzl Nulzik",
        "Problem?",
        "I am interested",
        "_Raid Recruiter_",
        "problem",
        "interested",
        "hail",
      },
      items_required = {
      },
      rewards = {
        { id = 23410, name = "Battle-Worn Circlet of Sickness", type = "item" },
        { id = 57935, name = "Gemmed Sand Elf Leggings", type = "item" },
        { id = 57435, name = "Gemmed Sand Elf Slippers", type = "item" },
        { id = 64711, name = "Geomancer's Crown of Reformation", type = "item" },
        { id = 63108, name = "Geomancer's Gloves of Celerity", type = "item" },
        { id = 64710, name = "Geomancer's Ritual Drape", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- North Ro 2.0 [zone=24]\n**Who:**\n- Dizzl Nulzik [ _Raid Recruiter_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 65\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Expedition\n**Quest Goal:**\n- Loot\n**Time Limit:** | 03:00:00\n**Related Zones:**\n- Takish-Hiz: The Palace Grounds (Raid) [zone=558]\n**Related Creatures:**\n- Champion of the Guard [npc=52113]\n- Master of the Guard [npc=52112]\n- Tactician of the Guard [npc=52114]\n- The Diamond Etched Chest [npc=27682]\n- The Sand Covered Chest [npc=43769]\n- The Smoldering Chest [npc=43770]\n- a delinquent defender [npc=52109]\n- a wayward defender [npc=29674]\n- an aberrant defender [npc=52110]\n- an enraged jeweled guard [npc=52111]\n**Era:** | !Lost Dungeons of Norrath\nRecommended:\n**Group Size:** | Raid\n**Min. # of Players:** | 6\n**Max. # of Players:** | 54\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Mon Dec 17 17:17:36 2007\nModified: Tue Dec 5 05:21:04 2023 | | _This raid expedition begins with Dizzl Nulzik at the Wayfarer camp in North Ro and takes place in an instance called The River of Recollection._\nYou say, 'Hail, Dizzl Nulzik'\nDizzl Nulzik bows to you. 'These are most exciting times for us! Exploring the world with such great companions, there can be no greater occupation. Well, maybe tinkering, but this is great. There are so many surprises around the bends of time, aren't there? Much to do, much to do! In fact, I can see that you'd like to get involved, eh? If you can rally the call of your friends perhaps you can help us with a serious [problem].'\nYou say, 'Problem?'\nDizzl Nulzik says 'It seems the sand elves of Takish-Hiz are very disturbed by our presence. Now our scouts report that some Geomantic Compact masters aim to create a beast of sand to unleash on all who enter Takish-Hiz. This would impede our gathering of information and such, so we need you to stop them. You will need your best and bravest for this task. Are you [interested]?'\nYou say, 'I am interested'\nDizzl Nulzik says 'Put the beast of sand to sleep if you must, \\_\\_\\_\\_\\_. We're counting on you.'\n\n---\n\nYou have entered Takish-Hiz: The Palace Grounds\n!\n_There are three non-targetable earth elementals at the entrance area: \"a wayward defender\", \"a delinquent defender\", and \"an aberrant defender\" . After a short time from zoning in the wayward defender will head north while the other two head southeast (aberrant defender) and northeast (delinquent defender)._\n_In order to progress through the instance each of these three elementals must reach the guard event rooms at the end of their path. They will stop moving whenever a hostile NPC is near them but the defenders themselves cannot be killed. There is no timer involved with this event so the raid may choose to either stay in 1 big group and clear a single path at a time or to split up and assign a few groups to each elemental if they feel they are up to it._\n_Each path will have a modest amount of zone trash which hits from around 700-900 but mobs are spaced out enough that pulls should never be more than two mobs at a time. The biggest danger are the Insect Traps that will spawn 15 Ravenous Insects which will all attack simultaneously. These insects are weaker than normal zone trash, hitting for roughly 300 damage, but can be quite lethal as a swarm if caught unprepared._\n_Once all three of the \"defender\" elementals have reached their respective rooms the enraged guards will begin spawning. Each of the three rooms will have 5 \"an enraged jeweled guard\" spawn and will charge the raid if you are close enough. These each hit for around 800 damage and do not summon. To proceed, each wave of 5 guards must be killed in all 3 rooms, and there are 4 waves total. The raid will have a period of about 4 minutes between each wave from the time the final guard dies but if you need more time you can simply move further back to avoid aggroing when they spawn._\n_Once 4 waves of guards have been killed in each of the 3 guard rooms, a named NPC will spawn in each: \"Master of the Guard\" in the Northwest, \"Tactician of the Guard\" in the southwest, and \"Champion of the Guard\" in the northeast. These all function the same, hitting for about 1400 damage and can single target ramp, are rootable and are mezzable. They also leash to their rooms if pulled out and will clear all debuffs and fully heal if they do leash. Defeat them all to receive your chests._\n**NOTE: You need to defeat the Tactician and the Champion prior to killing the Master of the Guard in order to get all 3 chests.**\n_Three Chests with loot will spawn in the room just south of \"Master of the Guard\"._\n\n---\n\n_Known raid loot from this event (Two items from each chest, can have duplicates from the same chest):_\nThe Smoldering Chest\nBattle-Worn Circlet of Sickness\nGemmed Sand Elf Slippers\nGirdle of the Sandy Grove\nRoyal Gem of Alacrity\nTakish-Hiz Ring of Vengeance\nThe Sand Covered Chest\nGeomancer's Crown of Reformation\nGeomancer's Ritual Drape\nSparkling Sand-Covered Helm\nTakish-Hiz Architect's Leggings\nThe Diamond Etched Chest\nGemmed Sand Elf Leggings\nGeomancer's Gloves of Celerity\nGloves of the Jeweled Guard\nSpiritstorm Mask\nThick Jeweled Belt\n**Unknown which chest drops these:**\nGeomancer's Crown of Reformation\nJeweled Bracelet of the Champion\nShawl of Trapped Memories\nGloves of the Jeweled Guard\n**Submitted by:** Bobbybick\n- Battle-Worn Circlet of Sickness [item=23410]\n- Gemmed Sand Elf Leggings [item=57935]\n- Gemmed Sand Elf Slippers [item=57435]\n- Geomancer's Crown of Reformation [item=64711]\n- Geomancer's Gloves of Celerity [item=63108]\n- Geomancer's Ritual Drape [item=64710]\n- Girdle of the Sandy Grove [item=57934]\n- Gloves of the Jeweled Guard [item=64773]\n- Jeweled Bracelet of the Champion [item=23412]\n- Royal Gem of Alacrity [item=63124]\n- Shawl of Trapped Memories [item=64772]\n- Sparkling Sand-Covered Helm [item=59862]\n- Spiritstorm Mask [item=59077]\n- Takish-Hiz Architect's Leggings [item=23413]\n- Takish-Hiz Ring of Vengeance [item=64189]\n- Thick Jeweled Belt [item=57937]",
    },
  },
}
