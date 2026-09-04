-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for Ruins of Lxanvom (codecayb)
-- Total Quests: 11
-- ============================================================================

return {
  zone = "codecayb",
  zone_name = "Ruins of Lxanvom",
  quests = {
    {
      id = "8071",
      title = "Apathy of Decay",
      exp = "22",
      exp_name = "The Broken Mirror",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Jerill the Enraged",
      loc = nil,
      triggers = {
        "Hail, Jerill the Enraged",
        "useful",
        "teach them",
        "TBM",
      },
      items_required = {
      },
      rewards = {
        { id = 127999, name = "Dread Poison", type = "item" },
        { id = 134906, name = "Scrawled Notes", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Ruins of Lxanvom [TBM]\n**Who:**\n- Jerill the Enraged [npc=50775]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Quest\n**Quest Goal:**\n- Experience\n- Money\n**Time Limit:** | 06:00:00\n**Quest Items:**\n- Dread Poison [item=127999]\n- Scrawled Notes [item=134906]\n**Related Creatures:**\n- Malinan Grobbsby - TBM [npc=54224]\n**Era:** | !The Broken Mirror\nRecommended:\n**Group Size:** | Group\n**Min. # of Players:** | 1\n**Max. # of Players:** | 6\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Thu Dec 3 01:01:23 2015\nModified: Fri Aug 16 13:43:54 2024 | | This shared task is given in in the Ruins of Lxanvom from Jerill the Enraged at the zone in (Bubonian looking NPC).\nYou say, 'Hail, Jerill the Enraged'\nJerill the Enraged says 'Look, I don't have time to deal with you. Just hang out here, if you'd like, until your body rots away. That's fine with me. You might be more [useful] as a pile of decayed slime than you are like that.'\nYou say, 'useful'\nJerill the Enraged says 'I guess I can't assume that you know what that word means. It means that you do something that isn't just breathing. Maybe you could deliver some important messages to my troops for me? That would be useful. Considering the quality of the people currently working for me, you couldn't be worse. Those lazy rotters have been ignoring my orders for too long. You could [teach them] a lesson or two.'\nYou say, 'teach them'\nJerill the Enraged says 'They will only learn by beating them up, a lot. I'd do it, but I have to stay here.'\nYou have been assigned the task 'Apathy of Decay'.\n\n---\n\nThere's a permanent spell: Decay that limits HP/Mana to 80%. It does not work on mercs so if you use mercs (at the moment, perhaps it will get nerfed), they have full health.\n1\\. Find that fool Malinan Grobbsby 0/1 (Ruins of Lxanvom)\nMalinan was up around the first corner with 5 mobs at the area of the small bridge with the Death Lords, has also been noted \"way back in the second big room with pews in it, in the undead magus/priest area\". If you kill him, he stops at about 15% and you lose aggro and task updates.\n2\\. Find that idiot Melferious Ronn 0/1 (Ruins of Lxanvom)\nDown via chair to the bottom of the crypt. Melferious Ronn is lying at the floor at the evil side, right area. take the ground spawn: Scrawled Notes.\n3\\. Resnak, that incompetent, has gone missing 0/1 (Ruins of Lxanvom)\nHe is at the good side, left area which leads to Ilsa Granger. Resnak attacks if close but de-aggroes fast after getting flask. He cannot be killed or really attacked (it seemed for us so). Ground spawn: Dread Poison. If you use Rogue/SOS, Ranger or DA then you should get the ground spawn safely.\nTask locks here\n4\\. Kick some of those on the death lords in the \\*\\*\\* 0/5 (Ruins of Lxanvom)\nOne side (good/dubious): unicorns/golems, other side (evil/kos): Bubonians/Deathlords. Deathlords: mez does not work. Didn't test if the Deathlords in the upper area count too.\n5\\. Hand the Scrawled Notes to Jerill 0/1 (Ruins of Lxanvom)\n6\\. Hand the Dread Poison to Jerill 0/1 (Ruins of Lxanvom)\nReward:\n\\- 750 Remnants of Tranquility\n\\- 337p, 5g\n\\- 3 AA, Experience\n**Submitted by:** Fayman",
    },
    {
      id = "8072",
      title = "Ask the Invaders",
      exp = "22",
      exp_name = "The Broken Mirror",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Jerill the Enraged",
      loc = nil,
      triggers = {
        "TBM",
      },
      items_required = {
      },
      rewards = {
        { id = 124742, name = "Gruesome Trophy", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Ruins of Lxanvom [TBM]\n**Who:**\n- Jerill the Enraged [npc=50775]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Time:** | 0\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Quest\n**Quest Goal:**\n- Advancement\n- Experience\n- Money\n**Time Limit:** | 06:00:00\n**Success Lockout Timer**: 03:00:00\n**Quest Items:**\n- Gruesome Trophy [item=124742]\n**Related Creatures:**\n- Ilsa Granger [npc=50695]\n**Era:** | !The Broken Mirror\nRecommended:\n**Group Size:** | Group\n**Min. # of Players:** | 1\n**Max. # of Players:** | 6\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Thu Dec 3 01:01:56 2015\nModified: Tue Dec 5 05:21:04 2023 | | **This is a shared task.**\nNPC is Jerill the Enraged in the Crypt of Decay.\nSay: \"crazy\" and after that: \"willing\" (last one is only really necessary)\nCorrupted Deathlords: mezzable\nDeathlords: not mezzable\nTask locks from beginning!\n1\\. Find someone among the invaders that will speak to you. 0/1 (Ruins of Lxanvom)\nHail Ilsa Granger down at the bottom of the crypt (via throne), she is at the good side, mobs normally don't attack (conned dubious)\n2\\. Kill denizens of the Crypt and gather trophies to prove you are trustworthy. 0/10 (Ruins of Lxanvom)\nLoot Gruesome Trophy from their corpses.\n3\\. Return the gruesome trophies to Ilsa. 0/10 (Ruins of Lxanvom)\n4\\. Allow Ilsa to cast magic on you to test your body and soul. 0/1 (Ruins of Lxanvom)\nSay \"cast\" to Ilsa Granger.\n5\\. Bring Ilsa's message to Jerill the Enraged. 0/1 (Ruins of Lxanvom)\nHe is at the first floor, go back via glowing object in the middle of the bottom crypt.\nTask gives:\n\\- 500 Remnants of Tranquility\n\\- 225pp\n\\- Exp/2 AA\nDifficulties:\n\\- Permanent spell: Decay HP/Mana Limit 80%\n\\- it does not work on mercs so if you use mercs (at the moment, perhaps it will get nerfed), they have full health\n**Submitted by:** Fayman, Veludeus\n- 500 Remnants of Tranquility, 225 PP, experience",
    },
    {
      id = "8073",
      title = "Ordering the Discordant",
      exp = "22",
      exp_name = "The Broken Mirror",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Jerill the Enraged",
      loc = { y = 245.0, x = 20.0, z = -90.0 },
      triggers = {
        "Hail, Jerill the Enraged",
        "orders",
        "can do",
        "TBM",
        "useful",
        "crazy",
      },
      items_required = {
      },
      rewards = {
        { id = 124747, name = "Disease Package", type = "item" },
        { id = 124746, name = "Jerill's Orders", type = "item" },
        { id = 124218, name = "Remnant of Tranquility", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Ruins of Lxanvom [TBM]\n**Who:**\n- Jerill the Enraged [npc=50775]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 95\n**Maximum Level:** | 130\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Quest\n**Quest Goal:**\n- Advancement\n- Experience\n- Loot\n- Money\n**Time Limit:** | 06:00:00\n**Success Lockout Timer**: 03:00:00\n**Quest Items:**\n- Disease Package [item=124747]\n- Jerill's Orders [item=124746]\n**Related Creatures:**\n- Archon Hekip [npc=51191]\n- Captain Korapan [npc=51234]\n- Eviscerator Frilis [npc=51175]\n- Witchdoctor Parawin [npc=51181]\n**Era:** | !The Broken Mirror\nRecommended:\n**Group Size:** | Group\n**Min. # of Players:** | 1\n**Max. # of Players:** | 6\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Thu Dec 3 01:02:34 2015\nModified: Mon Apr 6 06:56:35 2026 | | **This is a shared task.**\nYou say, 'Hail, Jerill the Enraged'\nJerill the Enraged says 'Well, your information may prove [useful]. And clearly you are [crazy]. It's time to put that information and lunacy to work. I have new orders for some of my people based on what you have learned. I would like you to deliver those [orders].'\nYou say, 'orders'\nJerill the Enraged says 'I have many uncooperative and incompetent subordinates. I need you to personally deliver my orders and make sure they are followed. I don't care if that means you do them yourself. If I can't get some things done around here, I can't work with you and that Ilsa thing to resolve this whole thing. You [can do] this, can't you?'\nYou say, 'can do'\nJerill the Enraged says 'Don't be afraid to discipline them, and I don't mean harsh language.'\nYou receive Jerill's Orders [item=124746].\nYou have been assigned the task 'Ordering the Discordant'.\n\n---\n\n01. Deliver Jerill's orders to Captain Korapan. 0/1 (Ruins of Lxanvom)\nGo down via throne to the bottom of the crypt.\nThere is a good and an evil side of this area.\nSearch at the Death Lord side, in the room where Abroan Drian spawns.\n08. Deliver Jerill's orders to Eviscerator Frilis. 0/1 (Ruins of Lxanvom)\nGo up at first floor.\nSearch at the north side in the first cave room of the bubonians.\n/loc 245, 20, -90\n15. Deliver Jerill's orders to Witchdoctor Parawin. 0/1 (Ruins of Lxanvom)\nUp at first floor:\nGo west side, after bridge turn right, 5 deathlords and small path leads to Witchdoctor.\nAfter the small path the witch doctor can be pulled solo.\n/loc -65, 375, -60\n23. Defeat the unreasonable witchdoctor. 0/1 (Ruins of Lxanvom)\nSimply kill him.\n28. Deliver Jerill's orders to Archon Hekip. 0/1 (Ruins of Lxanvom)\nStay at the first floor.\nSearch at the south end, take care, some see invis\na bit into the cave leading to the next cave a trap spawns a bunch of maggots which attack (trap)\n/loc -460, 135, -60.\n36. Find these Disease Packages and get rid of them by giving them to Jerill. 0/3 (Ruins of Lxanvom)\nDisease packages can be looted through the whole task. You will have all at the time you end it except you mezz/memblur or SOS your way through the task.\n41. Return Jerill's Orders. 0/1 (Ruins of Lxanvom)\n\n---\n\nReward(s):\n750 Remnants of Tranquility\n337pp 5gp\nExperience and 4AA's\n**Submitted by:** Fayman\n- Remnant of Tranquility [item=124218]",
    },
    {
      id = "8074",
      title = "Facilitate the Forceful",
      exp = "22",
      exp_name = "The Broken Mirror",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Erndal the Forceful",
      loc = { y = 110.0, x = 240.0, z = -260.0 },
      triggers = {
        "TBM",
      },
      items_required = {
        { name = "her more time to find a cure", count = 1 },
        { name = "it to Athurn", count = 1 },
      },
      rewards = {
        { id = 124602, name = "Restorative Potion", type = "item" },
        { id = 125084, name = "Rotting Mold", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Ruins of Lxanvom [TBM]\n**Who:**\n- Erndal the Forceful [npc=50774]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | No\n**Can Be Shrouded?:** | No\n**Quest Type:** | Quest\n**Quest Goal:**\n- Experience\n- Money\n**Quest Items:**\n- Restorative Potion [item=124602]\n- Rotting Mold [item=125084]\n**Related Creatures:**\n- Ilsa Granger [npc=50695]\n- Light Estrella [npc=51203]\n- Seraph Athurn [npc=51216]\n- Shine [npc=51200]\n**Era:** | !The Broken Mirror\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Thu Dec 3 01:03:08 2015\nModified: Tue Dec 5 05:21:04 2023 | | Quest is given by Erndal the Forceful in the Crypt of Decay. Say \"communication\" then \"can\".\nGo down to the bottom of the crypt via the throne, Right North side you find Erndal the Forceful.\n1\\. Speak with Light Estrella about her pacifistic offense. 0/1 (Ruins of Lxanvom)\n\\- bottom area, west room, good side, there is Light Estrella\n2\\. Reduce the number of enemy knights. 0/10 (Ruins of Lxanvom)\nSimply kill all Death Lord types at the evil side. Take care, they tend sometimes to run to their spawn point if they are pulled to far. Sometimes they add the fellows around the corner.\n3\\. Tell Light Estrella about your success. 0/1 (Ruins of Lxanvom)\n4\\. Speak with Shine about her lack of success finding a curative to the decay here. 0/1 (Ruins of Lxanvom)\nSearch west side, south way at the border of good to evil.\n5\\. Convince Erndal to slow his attacks to give her more time to find a cure. 0/1 (Ruins of Lxanvom)\n6\\. Speak with Seraph Athurn about increasing her potion production. 0/1 (Ruins of Lxanvom)\nWest room, north path, loc 110,240,-260 in a small corner.\n7\\. Find some of the Rotting Mold that only grows here and give it to Athurn. 0/4 (Ruins of Lxanvom)\nRotting Mold has the color of the floor, slight nearly not visible bulbs in the middle of the way mostly\n-103, 119, -260 Rotting Mold (SW)\n-221, 377, -260 Rotting Mold (SW)\n-190, -161, -260 Rotting Mold (SE)\nSeems each side has about 2-3 Rotting Mold, slowly respawning, is tradeable, pre-lootable.\n8\\. Give the potion to Ilsa Granger to help her with her illness. 0/1 (Ruins of Lxanvom)\n9\\. Return to Erndal to report your success. 0/1 (Ruins of Lxanvom)\nTask rewards:\n\\- 750 Remnants of Tranquility\n\\- 337,5pp\n\\- Exp/4 AA\n**Submitted by:** Fayman",
    },
    {
      id = "8075",
      title = "A Note of Hope",
      exp = "22",
      exp_name = "The Broken Mirror",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Ilsa Granger",
      loc = nil,
      triggers = {
        "TBM",
      },
      items_required = {
        { name = "Ilsa's message to Jerill", count = 1 },
        { name = "the text you found to Ilsa", count = 1 },
      },
      rewards = {
        { id = 124873, name = "Note of Hope", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Ruins of Lxanvom [TBM]\n**Who:**\n- Ilsa Granger [npc=50695]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | No\n**Can Be Shrouded?:** | No\n**Quest Type:** | Quest\n**Quest Items:**\n- Note of Hope [item=124873]\n**Related Creatures:**\n- Jerill the Enraged [npc=50775]\n**Era:** | !The Broken Mirror\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n**Appropriate Races:**\nEntered: Thu Dec 3 01:03:44 2015\nModified: Tue Dec 5 05:21:04 2023 | | [ ] A Note of Hope - Ilsa Granger in the Crypt of Decay\n\\- Ilsa Granger is in a relatively safe zone area at the bottom of the crypt, reachable via the throne.\n\\- sometimes the thrones does not work if you are shrinked, use an illusion or don't use shrink.\n\\- say: \"Helpful\" -> \"Find a Way\" to start the task.\n1\\. Discover who the leader of the forces of Decay is. 0/1 (Ruins of Lxanvom)\n\\- Say \"Who is the leader?\" to Jerill the Enraged, main floor.\n2\\. Defeat grumlings to attract Grummus' attention. 0/4 (Ruins of Lxanvom)\n\\- evil side consists of grumlings and death lord types\n\\- crawl through the dungeon and get them\n3\\. Speak again with Jerill. 0/1 (Ruins of Lxanvom)\n\\- go up again via the glowing quader in the middle of the bottom zone\n4\\. Give Ilsa's message to Jerill, there are no other real options. 0/1 (Ruins of Lxanvom)\n5\\. Convey Jerill's message to Ilsa. 0/1 (Ruins of Lxanvom)\n6\\. Find an underling of Decay that knows about Anashti Sul. 0/10 (Ruins of Lxanvom)\n\\- kill any Deathlord in the south area of bottom CoD2\n7\\. Give the text you found to Ilsa. 0/1 (Ruins of Lxanvom)\n\\- at moment there seems that every text/scroll which drops in TBM will get your update. This is perhaps a bug.\nQuest gives:\n\\- 667 Remnants of Tranquility\n\\- 300pp\n\\- Exp/4 AA\n**Submitted by:** Fayman",
    },
    {
      id = "8076",
      title = "Duplicity",
      exp = "22",
      exp_name = "The Broken Mirror",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Ilsa Granger",
      loc = nil,
      triggers = {
        "TBM",
      },
      items_required = {
        { name = "corpse to ritualist to spawn the monsters/mobs", count = 1 },
        { name = "Ilsa the shovel you acquired", count = 1 },
      },
      rewards = {
        { id = 124678, name = "Mortician's Shovel", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Ruins of Lxanvom [TBM]\n**Who:**\n- Ilsa Granger [npc=50695]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | No\n**Can Be Shrouded?:** | No\n**Quest Type:** | Quest\n**Quest Goal:**\n- Experience\n- Money\n**Quest Items:**\n- Mortician's Shovel [item=124678]\n**Related Zones:**\n- Sul Vius: Demiplane of Life [zone=1058]\n**Related Creatures:**\n- a respected mortician [npc=50282]\n**Era:** | !The Broken Mirror\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Thu Dec 3 01:04:20 2015\nModified: Tue Dec 5 05:21:04 2023 | | The quest is given by Ilsa Granger in the Crypt of Decay. Say \"seek\" then \"brave enough\".\n1\\. You will need a shovel 0/1 (Sul Vius: Demiplane of Life)\nKill mortician in the south grave area.\n2\\. Dig up one of the graves 0/1 (Sul Vius: Demiplane of Life)\nUse shovel on one of the graves.\nTask Locks Here\n3\\. Gather the body of one of Anashti Sul's servants. 0/1 (Sul Vius: Demiplane of Life)\nClick skeleton after using shovel to get the remains.\n4\\. Return to Ilsa and tell her that you have the corpse. 0/1 (Ruins of Lxanvom)\n5\\. Hand the corpse to the ritualist when you are ready to start the trial. 0/1 (Ruins of Lxanvom)\n\\- ritualist follows you, optional say \"follow\", go into the center where no mobs are present (safe zone)\n\\- optional: buff up ritualist with all single buffs to the max (necessary?)\n\\- give corpse to ritualist to spawn the monsters/mobs\n6\\. Protect the ritualist. 0/4 (Ruins of Lxanvom)\n2x2 mobs spawn, mezzable, kill them.\n7\\. Speak with the resurrected human. 0/1 (Ruins of Lxanvom)\n\\- buff up ressurected human to the max (necessary?)\n\\- hail resurrected human\n\\- 2x monster spawn\n8\\. Protect the resurrected human. 0/2 (Ruins of Lxanvom)\nKill 2x monster, not mezzable, slow/tash works.\n9\\. Return to Ilsa with the news. 0/1 (Ruins of Lxanvom)\n10\\. Give Ilsa the shovel you acquired. She may have need for it. 0/1 (Ruins of Lxanvom)\n\n---\n\nTask rewards:\n\\- 750 Remnants of Tranquility\n\\- 337,5pp\n\\- Exp/4 AA\n**Submitted by:** Fayman",
    },
    {
      id = "8078",
      title = "Force the Forceful",
      exp = "22",
      exp_name = "The Broken Mirror",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Karth Punox",
      loc = nil,
      triggers = {
        "TBM",
        "_Heroic Adventures_",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Ruins of Lxanvom [TBM]\n**Who:**\n- Karth Punox [ _Heroic Adventures_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Adventure\n**Quest Goal:**\n- Experience\n- Loot\n- Money\n**Success Lockout Timer**: 00:03:00\n**Related Zones:**\n- Ruins of Lxanvom: Force the Forceful [zone=1082]\n**Related Creatures:**\n- Erndal the Forceful [npc=50856]\n- Seraphina [npc=50685]\n- a chest - Ruins of Lxanvom: Force the Forceful [npc=54225]\n- a guardian of life [npc=50855]\n**Era:** | !The Broken Mirror\nRecommended:\n**Group Size:** | Group\n**Min. # of Players:** | 1\n**Max. # of Players:** | 6\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Thu Dec 3 01:05:41 2015\nModified: Tue Dec 5 05:21:04 2023 | | Phrase to request from Karth Punox is: \"up for the job\".\nKarth Punox is located in Sul Vius: Demiplane of Decay\n\n---\n\n**Task Steps**\nFind out exactly what Jerill wants you to do. (0/1) (Ruins of Lxanvom)\nDefeat Erndal's guards (0/10) (Ruins of Lxanvom)\nDefeat Erndal (0/1) (Ruins of Lxanvom)\nDefeat Erndal's guards (0/2) (Ruins of Lxanvom)\n**Task Locks Here. The named Seraphina [npc=50685] or its PH 'a seraph' will spawn near the central area where you fought the initial 8 guards.**\nOpen the chest (0/1) (Ruins of Lxanvom)\nChest is up stairs\n\n---\n\n**Erndal's Guards**\n_This is a very straight forward mission. You simply start off by hailing Jerill to get the task to update. Upon getting the task update, you need to kill 10 of Erndal's guards. They con red to a level 105 and hit for an average of 20k. They have a very low aggro range, so it is possible to split them if you don't want to deal with two at a time. After defeating the initial 8 guards, the final two are going to be up a ramp and standing relatively close to the location of where you will find Erndal. You may need to clear some trash mobs so you don't get any unwanted social aggro._\n8 Guards spawn in the middle of the zone\nBUG WARNING: If you proceed to this step and kill the guards without hailing Jerill first, you will not get any task updates! If this happens, you will simply have to kick everyone from the task and start over.\n\n---\n\n**Confronting Erndal**\n_Erndal is surprisingly a very tough encounter. He hits for an average of 25k, is fast, and will strike through your defenses regularly. What makes him exceptionally dangerous is his targeted AE Retributive Strike that hits everyone for nearly 90k. Additionally, he uses another obnoxious targeted AE called Repulsion of Life which not only does about 48k in damage to everyone, it also does both a toss up and knock back effect. The spell 'Recognition of Mortality' is also in his spell line up, to which causes a 6 second fear on the target._\n\n---\n\n**Best Strategy for Erndal**\n_It is best to pull Erndal into the corner at the top of the ramp, and fight him there. There are two reasons for this. The first reason is having your party planted in the corner with Erndal will help negate the effects of his targeted AE Repulsion of Life. The second reason you want to fight him there is the moment you get the task update suggesting he is ready to be confronted, that is when the named Seraphina [npc=50685] may spawn at the point you fought the 8 guards. You do not want your team caught off guard with that named popping right on top of your team._\n_While fighting Erndal, it is advisable to have a real player healer in the group with you that will splash your team regularly to help offset the damage caused by his massive 90k AE. When he hits 10%, be sure your tank starts doing any abilities that generates AE hatred - because those two guards will get loose and start attacking your DPS. His guards hit for an average of 20k, but will gang up on your team mates very quick. Get them under control as fast as possible, especially if you are going for a deathless run achievement._\n_Upon defeating Erndal and his guards, go back to where Jerill is and open the chest for the win!_\n\n---\n**Submitted by:** Aghinem",
    },
    {
      id = "8079",
      title = "Grannus of the Cleansing Steam",
      exp = "22",
      exp_name = "The Broken Mirror",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Karth Punox",
      loc = nil,
      triggers = {
        "TBM",
        "_Heroic Adventures_",
      },
      items_required = {
      },
      rewards = {
        { id = 124491, name = "Oscillating Band", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Ruins of Lxanvom [TBM]\n**Who:**\n- Karth Punox [ _Heroic Adventures_]\nRating:\n0/1**_\\*__\\*__\\*__\\*__\\*_**\n(From 1 rating)\nInformation:\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Adventure\n**Quest Goal:**\n- Advancement\n**Time Limit:** | 06:00:00\n**Related Creatures:**\n- a glowing chest - Ruins of Lxanvom - TBM [npc=54223]\n**Era:** | !The Broken Mirror\nRecommended:\n**Group Size:** | Group\n**Min. # of Players:** | 3\n**Max. # of Players:** | 6\n**Appropriate Classes:**\n**Appropriate Races:**\nEntered: Thu Dec 3 01:06:17 2015\nModified: Tue Dec 5 05:21:04 2023 | | The NPC you need to speak to to request this mission is Karth Punox, located in Sul Vius: Demiplane of Decay.\nThe request phrase to acquire the mission is 'work'.\n\n---\n\n**Task Steps**\nDefeat Grannus of the Cleansing Steam. 0/1 (Ruins of Lxanvom)\nDestroy the portal leading to the Plane of Health 0/1 (Ruins of Lxanvom)\nOpen the chest 0/1 (Ruins of Lxanvom)\n\n---\n\n**Task Summary**\n_To start the event, speak with Jerill in the basement in the Ruins of Lxanvom. He will be inside the room that you engage Grannus. After triggering the event, you will engage Grannus and his several add spawns. After defeating Grannus, you will need to locate the portal and destroy it. Once you have destroyed the portal, the chest will become available to open._\n\n---\n\n**Engaging Grannus**\n**1\\. The Basics.** _This is a very DPS oriented encounter. Grannus hits for an average of 30k, is fast, and strikes through defenses regularly. About midway through the fight, he will summon a litany of adds. One add in particular is a unicorn that will roam throughout the room you are fighting him in. This unicorn is not attackable and is simply there to be a nuisance by doing a knockback if he paths nearby. When you engage Grannus, just unleash everything you have in your arsenal._\n**2\\. The Adds.** _Depending on the DPS of your group, the adds will spawn on average around 50% of Grannus' health. Each add hits for an average of 20k and there are typically 4-5 of them by the end of the encounter. **DO NOT KILL THE ADDS**. If you kill just one add, even by accident - it will put Grannus into super regeneration mode and make him unbeatable. It is recommended you use a Warrior to offtank the adds, because a Shadowknight or Paladin riposte may inflict too much damage during the full burn and incidentally kill one of the adds. If you have no one to offtank the adds, just have your main tank grab all the mobs and keep aggro at all times while the others DPS Grannus hard! Once Grannus is defeated, the adds will despawn._\n\n---\n\n**The Portal**\n_The Portal is located around the north side of the instance, typically where you find Ilsa Granger in the non-instance for quests. Now the portal itself has a very odd hit box. You are going to have great difficulty targeting it using your mouse, so it is recommended you simply type /target portal to pull up a valid target ring for the portal and have people /assist you on the target. When you destroy the Portal, the the chest will pop and you are done!_\n_\n---\n_\n_**Special Mission Achievements**_\n_There are three special achievements that go with this mission:_\n_No Unity (Group)_\n_No Restoration (Group)_\n_Non Transferable (Group)_\n_These three achievements are purely based on how fast you can kill Grannus. The key to getting all three achievements is to defeat Grannus in under 45 seconds. The 45 second marker is the threshold for when the first heal will be cast by one of the healing oozes. If you cannot defeat Grannus in under 45 seconds, then you will not be able to get all the achievements._\n_\n---\n_\n**Submitted by:** Aghinem\n- Oscillating Band [item=124491]",
    },
    {
      id = "8106",
      title = "The Other Side",
      exp = "22",
      exp_name = "The Broken Mirror",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Ilsa Granger",
      loc = nil,
      triggers = {
        "TBM",
      },
      items_required = {
      },
      rewards = {
        { id = 124674, name = "Aged Scroll", type = "item" },
        { id = 124213, name = "Opened Scroll", type = "item" },
        { id = 124577, name = "Ornate Scroll", type = "item" },
        { id = 124573, name = "Plain-Looking Scroll", type = "item" },
        { id = 124212, name = "Rolled-Up Scroll", type = "item" },
        { id = 124673, name = "Tattered Scroll", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Ruins of Lxanvom [TBM]\n**Who:**\n- Ilsa Granger [npc=50695]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Time:** | 0\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Quest\n**Quest Goal:**\n- Advancement\n- Experience\n- Loot\n- Money\n**Time Limit:** | 06:00:00\n**Success Lockout Timer**: 03:00:00\n**Quest Items:**\n- Aged Scroll [item=124674]\n- Opened Scroll [item=124213]\n- Ornate Scroll [item=124577]\n- Plain-Looking Scroll [item=124573]\n- Rolled-Up Scroll [item=124212]\n- Tattered Scroll [item=124673]\n**Era:** | !The Broken Mirror\nRecommended:\n**Group Size:** | Group\n**Min. # of Players:** | 1\n**Max. # of Players:** | 6\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Mon Jul 4 19:36:26 2016\nModified: Tue Dec 5 05:21:04 2023 | | Prerequisite Tasks: Apathy of Decay [quest=8071], Ask the Invaders [quest=8072], Decay Decreased [quest=8077], Infect the Blessed [quest=8161], Ordering the Discordant [quest=8073], Proof of Health [quest=8166], The Vial Messenger [quest=8160]\nYou can Ilsa Granger in Ruins of Lxanvom and say _evidence_ to get the task.\n\n---\n\nQuest items are not prelootable.\nEnter the Crypt of Sul 0/1 Crypt of Sul\nLoot the Tenets of the Blessing - Writings of Anasht i0/1 Crypt of Sul\nKill Bokon's in the zone, they drop Plain-Looking Scroll [item=124573]'s. Loot and this will update this part of the task.\nLoot the Tenets of the Blessing - Writings of Anashti 0/1 Crypt of Sul\nKill Bokon's in the zone, they drop Rolled-Up Scroll [item=124212]'s. Loot and this will update this part of the task.\nLoot the Tenets of the Blessing - Writings of Anashti 0/1 Crypt of Sul\nKill Bokon's in the zone, they drop Opened Scroll [item=124213]'s. Loot and this will update this part of the task.\nLoot the Tenets of the Blessing - Writings of Anashti 0/1 Crypt of Sul\nKill Bokon's in the zone, they drop Tattered Scroll [item=124673]'s. Loot and this will update this part of the task.\nLoot the Tenets of the Blessing - Writings of Anashti 0/1 Crypt of Sul\nKill Bokon's in the zone, they drop Ornate Scroll [item=124577]'s. Loot and this will update this part of the task.\nLoot the Tenets of the Blessing - Writings of Anashti 0/1 Crypt of Sul\nKill Bokon's in the zone, they drop Aged Scroll [item=124674]'s. Loot and this will update this part of the task.\nReturn to Ilsa Granger, and speak to her about the scrolls 0/1 Ruins of Lxanvom\nReward:\nYou have gained experience!\n262 Platinum, 5 Gold\n583 Remnants of Tranquility\n- Remnant of Tranquility [item=124218]",
    },
    {
      id = "8166",
      title = "Proof of Health",
      exp = "22",
      exp_name = "The Broken Mirror",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Jerill the Enraged",
      loc = nil,
      triggers = {
        "TBM",
      },
      items_required = {
        { name = "you a Seraph Feather", count = 1 },
      },
      rewards = {
        { id = 127868, name = "Message from Jerill the Enraged", type = "item" },
        { id = 125058, name = "Seraph Feather", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Ruins of Lxanvom [TBM]\n**Who:**\n- Jerill the Enraged [npc=50775]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n- Experience\n- Loot\n- Money\n**Time Limit:** | 06:00:00\n**Success Lockout Timer**: 03:00:00\n**Quest Items:**\n- Message from Jerill the Enraged [item=127868]\n- Seraph Feather [item=125058]\n**Related Zones:**\n- Crypt of Sul [zone=1060]\n**Related Creatures:**\n- Ilsa Granger [npc=50695]\n- a bokon conduit [npc=50806]\n- a captured seraph [npc=50473]\n**Era:** | !The Broken Mirror\nRecommended:\n**Group Size:** | Group\n**Min. # of Players:** | 1\n**Max. # of Players:** | 6\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Thu Aug 4 19:41:02 2016\nModified: Tue Dec 5 05:21:04 2023 | | Speak to Jerill the Enrages in Ruins of Lxanvom. Say \"stop\" to him to get this task.\nHe will give you \"Message from Jerill the Enraged\" upon task start.\nDeliver Jerill's scroll to Ilsa Granger 0/1 (Ruins of Lxanvom)\nDeliver Message from Jerill the Enraged to Illsa Granger.\nFind evidence of the Plane of Health's power within the Crypt of Sul 0/1 (Crypt of Sul)\nIn the northwest room, there is a \"a captured seraph\". Clear the room and talk to it. Once you are done talking to it, a couple bokon spawn.\nKill the Bokon Conduits siphoning power from the Valkyrie 0/2 (Crypt of Sul)\nKill the bokons that just spawned.\nSpeak to the captured seraph 0/1 (Crypt of Sul)\nTalk to the \"a captured seraph\" again. It will give you a Seraph Feather.\nDeliver the captured seraph's feather to Ilsa Granger 0/1 (Ruins of Lxanvom)\nReward(s):\nExperience\n187pp,5gp\n417 Remnants of Tranquility\n**Submitted by:** Gidono, Veludeus",
    },
    {
      id = "8168",
      title = "Conduit of Decay",
      exp = "22",
      exp_name = "The Broken Mirror",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Ilsa Granger",
      loc = nil,
      triggers = {
        "TBM",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Ruins of Lxanvom [TBM]\n**Who:**\n- Ilsa Granger [npc=50695]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Quest\n**Quest Goal:**\n- Advancement\n- Experience\n- Loot\n- Money\n**Time Limit:** | 06:00:00\n**Success Lockout Timer**: 03:00:00\n**Related Zones:**\n- Crypt of Sul [zone=1060]\n**Related Creatures:**\n- a bokon conduit [npc=50806]\n**Era:** | !The Broken Mirror\nRecommended:\n**Group Size:** | Group\n**Min. # of Players:** | 1\n**Max. # of Players:** | 6\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Sat Aug 6 00:22:32 2016\nModified: Tue Dec 5 05:21:04 2023 | | Say **conduit** to Ilsa Granger to get the task.\nSearch for the conduit to the Plane of Health 0/1 (Crypt of Sul)\nVisit the northern most part of this zone. There is a throne looking thing in that area, get on top of it to get the update.\nDestroy the conduit to the Plane of Health 0/1 (Crypt of Sul)\nSee that crystal? DPS it down to 50%. At that point, 3 bokon's will spawn. Kill them for the update.\nReturn to Ilsa Granger and report on your discovery 0/1 (Ruins of Lxanvom)\nHail Illsa Granger.\nReward(s):\nExperience\n187pp,5gp\n417 Remnants of Tranquility\n**Submitted by:** Gidono, Veludeus",
    },
  },
}
