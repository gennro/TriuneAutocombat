-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for Chardok (chardok)
-- Total Quests: 4
-- ============================================================================

return {
  zone = "chardok",
  zone_name = "Chardok",
  quests = {
    {
      id = "8270",
      title = "A Lost Chokadai",
      exp = "23",
      exp_name = "Empires of Kunark",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "an undead chokidai",
      loc = { y = 289.0, x = -390.0, z = -14.0 },
      triggers = {
        "Do you need help?",
        "EoK",
        "help",
      },
      items_required = {
        { name = "Verrin the Oversized Ulna bone 0/1 (Chardok)", count = 1 },
        { name = "the Oversized Ulna to Verrin Di`mure", count = 1 },
      },
      rewards = {
        { id = 127756, name = "Chokidai Treat", type = "item" },
        { id = 127632, name = "Oversized Ulna", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Chardok [EoK]\n**Who:**\n- an undead chokidai [npc=51074]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | No\n**Can Be Shrouded?:** | No\n**Quest Type:** | Quest\n**Quest Goal:**\n- Experience\n- Money\n**Quest Items:**\n- Chokidai Treat [item=127756]\n- Oversized Ulna [item=127632]\n**Related Creatures:**\n- Dal`krook the cruel [npc=51859]\n- Verrin Di`mure [npc=51479]\n- a crossroads wraith [npc=57610]\n- a laughing crossroads wraith [npc=57611]\n- a sadistic tormenter [npc=51858]\n**Related Quests:**\n- Partisan of Chardok [quest=8354]\n**Era:** | !Empires of Kunark\nRecommended:\n**Group Size:** | Group\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Sun Oct 16 02:23:10 2016\nModified: Tue Dec 5 05:21:04 2023 | | This is a shared task.\nFind an undead chokidai [npc=51074] in Chardok This mob spawns at 289, -390, -14 in front of the tunnel on the map.\nan undead chokidai lowers its head and looks timidly up at you. It looks like it needs [help].\nYou say, 'Do you need help?'\nYou have been assigned the task 'A Lost Chokadai'.\nan undead chokidai roars in approval.\n\n---\n\n03. Find a way to communicate with the chokidai 0/1 (Chardok)\n\n\n\nSay 'hungry' to the chokidai, you should get a yellow message and a Chokidai Treat in your inventory. If the chokidai despawns you can use this to re-summon it. You can hail the start NPC for a new treat, or to respawn your chokidai.\n\n04. Follow the chokidai into the narrow tunnel 0/1 (Chardok)\n\n\n\nMove down the tunnel.\n\n05. Lead the chokidai deeper into the tunnel 0/1 (Chardok)\n\n\n\nMove down the tunnel to the next location update.\n\n06. Battle the Crossroads Wraiths 0/3 (Chardok)\n\n\n\n3 \"a crossroads wraith\" spawn on you, kill them.\n\n07. Travel down the North tunnel to find the Undergrotto 0/1 (Chardok)\n\n\n\nTravel down the North tunnel.\n\n08. Kill creatures to feed the chokidai 0/5 (Chardok)\n\n\n\nKill 5 monsters in the area.\n\n09. Get revenge on the Crossroads Wraiths 0/3 (Chardok)\n\n\n\nGo back south to the crossroads and kill the 3 \"a laughing crossroads wraith\" that spawn.\n\n10. Travel down the East tunnel to the edge of the city 0/1 (Chardok)\n\n\n\nHead east to the next update.\n\n11. Kill Risen Abusers and Risen Hecklers 0/6 (Chardok)\n\n\n\nKill the skeletons that ambushed you. They are all mezzable. The come two at a time. The chokidai pet following you kills the ambush mobs after they pass 50 percent health.\n\n12. Collect Oversized Ulna from Dal'krook the Cruel's corpse 0/1 (Chardok)\n\n\n\nAfter a moment Dal'krook the cruel spawns, kill him and loot Oversized Ulna. (one for each Toon on quest)\n\n13. Play fetch with the chokidai 0/1 (Chardok)\n\n\n\nTarget a lost chokidai and click the Oversized Ulna.\n\n14. Travel down the East tunnel to the slave camps 0/1 (Chardok)\n\n\n\nHead east down the tunnel.\n\n15. Find Verrin in the slave mining camps 0/1 (Chardok)\n\n\n\nHead north down the tunnel to Verrin Di`mure.\n\n16. Kill Sadistic Tormentors 0/3 (Chardok)\n\n\n\nKill the 3 \"a sadistic tormenter\" which spawn.\n\n17. Speak with Verrin 0/1 (Chardok)\n\n\n\nHail Verrin Di`mure.\n\n18. Say goodbye to your chokidai friend 0/1 (Chardok)\n\n\n\nTarget a lost chokidai and say 'goodbye'.\n\n19. Give Verrin the Oversized Ulna bone 0/1 (Chardok)\n\n\n\nTurn in the Oversized Ulna to Verrin Di`mure. .\n\n\n---\n\nReward(s):\n319pp\nExperience\n- 319 pp, Experience",
    },
    {
      id = "8454",
      title = "Hermit's Paradise",
      exp = "23",
      exp_name = "Empires of Kunark",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Gwizilwerkz Cogswin",
      loc = { y = -585.0, x = -164.0, z = -204.0 },
      triggers = {
        "EoK",
        "_The Lost Cogswin_",
      },
      items_required = {
        { name = "the Stones to Gwizilwerkz", count = 1 },
        { name = "the book to Gwizilwerkz Cogswin", count = 1 },
        { name = "the Indigestible Crystals", count = 1 },
        { name = "the Spirit Shrooms", count = 1 },
      },
      rewards = {
        { id = 127641, name = "Indigestible Crystal", type = "item" },
        { id = 127759, name = "Mind Wipinator", type = "item" },
        { id = 127761, name = "Mushy Stones", type = "item" },
        { id = 127764, name = "Page of Shroom 'n' Shackles", type = "item" },
        { id = 127766, name = "Shrooms 'n' Shackles", type = "item" },
        { id = 127640, name = "Spirit Shroom", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Chardok [EoK]\n**Who:**\n- Gwizilwerkz Cogswin [ _The Lost Cogswin_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n- Experience\n- Money\n**Quest Items:**\n- Indigestible Crystal [item=127641]\n- Mind Wipinator [item=127759]\n- Mushy Stones [item=127761]\n- Page of Shroom 'n' Shackles [item=127764]\n- Shrooms 'n' Shackles [item=127766]\n- Spirit Shroom [item=127640]\n**Related Creatures:**\n- a fleeing witness [npc=54879]\n- an imperial construct [npc=51451]\n**Related Quests:**\n- Partisan of Chardok [quest=8354]\n**Era:** | !Empires of Kunark\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n**Appropriate Races:**\nEntered: Tue Feb 7 19:27:11 2017\nModified: Tue Dec 5 05:21:04 2023 | | Pre Req: The following tasks must be completed before requesting this task.\nunknown? none\nFind Gwizilwerkz Cogswin [npc=51856] (Click Switch to Spawn) in CHARDOK located at -585, -164, -204.\nThis is a shared task.\nRequest Phrase: help\n\n---\n\nWARNING One person should loot all items\nTalk with Gwizilwerkz Cogswin 0/1 (Chardok)\nHail Gwizilwerkz Cogswin.\nKill the Fleeing Witness before he escapes 0/1 (Chardok)\nKill the fleeing witness that spawns, it's snareable and rootable.\nTell Gwizilwerkz Cogswin you killed the fleeing witness 0/1 (Chardok)\nReturn to and Hail Gwizilwerkz Cogswin. (get Clicky item)\nKill or wipe the memory of Sarnak near the camp 0/6 (Chardok)\nKill nearby sarnak. (click Mind Wipinator under 50% on mob)\nCollect Mushy Stones from sarnak golems 0/12 (Chardok)\nKill sarnak golems and loot Mushy Stones. (Golems in the room drop the Mushy Stone)\nGive Mushy Stones to Gwizilwerkz Cogswin 0/12 (Chardok)\nReturn to and Turn in the Stones to Gwizilwerkz.\nFind the Night Garden 0/1 (Chardok)\nHead down to the herbalist part of the zone. (North, West and South areas by the lake)\nCollect Spirit Shrooms 0/10 (Chardok)\nLoot Spirit Shrooms from mushrooms. They are immune to mez and have a small aggro radius. (not sure if One peep should be looting all items)\nCollect Indigestible Crystals 0/10 (Chardok)\nLoot Indigestible Crystals from beetles and chokidai. (not sure if One peep should be looting all items)\nCollect Pages of Shrooms 'n' Shackles 0/10 (Chardok)\nLoot Pages of Shrooms 'n' Shackles, from sarnak in the herbalist area. (not sure if One peep should be looting all items)\nEat Spirit Shroom 0/1 (Chardok)\nRight Click the Spirit Shroom, it will spawn a mob.\nKill your evil mushroom twin 0/1 (Chardok)\nKill the immaterial nemesis which spawns.\nRub a crystal on your forehead to sober up 0/1 (Chardok)\nRight Click an Indigestible Crystal.\nCombine the Shroom 'n' Shackles pages into a book 0/1 (Chardok)\nRight click one of the Pages of Shroom 'n' Shackles to combine them. (why i think one person should have all the pages??)\nGive Shrooms 'n' Shackles to Gwizilwerkz Cogswin 0/1 (Chardok)\nReturn to and Turn in the book to Gwizilwerkz Cogswin.\nGive Indigestible Crystals to Gwizilwerkz Cogswin 0/9 (Chardok)\nTurn in the Indigestible Crystals.\nGive Spirit Shrooms to Gwizilwerkz Cogswin 0/9 (Chardok)\nTurn in the Spirit Shrooms.\nExplain why you're missing some of the crystals and shrooms 0/1 (Chardok)\nHail Gwizilwerkz and say 'Spirit Shrooms'..\nReward(s):\n106pp\nExperience\n- 106 pp, 5 g, Experience",
    },
    {
      id = "8455",
      title = "Their Own Medicine",
      exp = "23",
      exp_name = "Empires of Kunark",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Ralla Merow`shu",
      loc = { y = -422.0, x = -274.0, z = -254.0 },
      triggers = {
        "EoK",
        "_Quests_",
        "Sokokarrr have been neutrrralized",
      },
      items_required = {
      },
      rewards = {
        { id = 127779, name = "Nightshade", type = "item" },
        { id = 127629, name = "Noxious Fish Bile", type = "item" },
        { id = 127633, name = "Repellinator", type = "item" },
        { id = 127631, name = "Waterborne Deliriant", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Chardok [EoK]\n**Who:**\n- Ralla Merow`shu [ _Quests_]\nRating:\n0/1**_\\*__\\*__\\*__\\*__\\*_**\n(From 1 rating)\nInformation:\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n- Experience\n- Money\n**Quest Items:**\n- Nightshade [item=127779]\n- Noxious Fish Bile [item=127629]\n- Repellinator [item=127633]\n- Waterborne Deliriant [item=127631]\n**Related Quests:**\n- Destabilizing Chardok [quest=8457]\n**Era:** | !Empires of Kunark\nRecommended:\n**Group Size:** | Solo\n**Min. # of Players:** | 1\n**Max. # of Players:** | 6\n**Appropriate Classes:**\n**Appropriate Races:**\nEntered: Thu Feb 9 20:09:29 2017\nModified: Tue Nov 26 06:22:25 2024 | | Pre Req:\n\\- Achievement: Partisan of Lceanium (Concerned Citizens, Contacting the Leadership, Disappearing Dragons, Sneaky Sarnak)\n\\- Achievement: Partisan of The Scorched Woods (Digging Yourself Deeper, The Last Grove, Where is Burning Woods?, On Nobody's Side)\n\\- Probing the Fortress\nTalk to Ralla Merow`shu [npc=51855] in CHARDOK to get this task.(by lake)\nSay stage 2 to get the task.\n\n---\n\n1\\. Travel to Chardok 0/1 (Chardok)\nZone in to Chardok\n2\\. Collect a Nightshade 0/1 (Chardok)\nKill herbalists in the Night Garden nearby and loot a nightshade.\n3\\. Use Noxious Fish Bile to create a poison 0/1 (Chardok)\nRight click the Noxious Fish Bile Ralla gave you, you can hail her for another if you lost it .\n4\\. Find the Night Garden's water supply 0/1 (Chardok)\nGo into the room near Ralla .\n5\\. Use Waterborne Deliriant to poison water barrels 0/3 (Chardok)\nUse the Waterborne Deliriant on barrels of pure water in the room.\n6\\. Find the Royal Palace Foyer 0/1 (Chardok)\nGo to the palace foyer, where the hidden gnome camp is.\nThe foyer is located at -422, -274, -254.\n7\\. Reveal Cogswin's hidden camp 0/1 Chardok\nRight click on the floating mechanical yellow thing at -576, -166, -234 to make the hidden camp appear.\n8\\. Steal a Repellinator from Cogswin's hidden camp 0/1 (Chardok)\n(click the floating item to spawn the hidden camp)\nSteal the Repellinator sitting on the ledge.\nRight click on the floating mechanical yellow thing at -576, -166, -234 to make the hidden camp appear.\nClick the various items in the hidden camp to see interesting comments from Cogswin. The quest trigger is the green potion at -560, -180, -235.\n9\\. Find the Sokokar Breeding Grounds 0/1 (Chardok)\nFind the Sokokar Breeding Grounds in the southeast corner of Chardok.\n10\\. Use the Repellinator to scare off Sokokar 0/6 (Chardok)\nFight sokokar to below 50% and click the Repellinator on them.\n11\\. Discuss your mission with Ralla 0/1 (Chardok)\nHail Ralla and say or click on [Sokokarrr have been neutrrralized] in the dialog to finish the quest.\nSay \"Final Phase\" to get the next quest, Destabilizing Chardok.\n\n---\n\nReward(s): ?\n- 425 PP, 5 G, Experience",
    },
    {
      id = "8458",
      title = "Violence for Silence",
      exp = "23",
      exp_name = "Empires of Kunark",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Royal Historian Fio`ra",
      loc = nil,
      triggers = {
        "EoK",
        "_Quests_",
      },
      items_required = {
        { name = "the books to the historian", count = 1 },
        { name = "the baubles to Royal Historian Fio'ra", count = 1 },
        { name = "the locked tomes to Royal Historian Fio'ra", count = 1 },
      },
      rewards = {
        { id = 127790, name = "Bauble of Atrebe", type = "item" },
        { id = 127786, name = "Chardok Historical Records", type = "item" },
        { id = 127789, name = "Locked Tomes of Atrebe", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Chardok [EoK]\n**Who:**\n- Royal Historian Fio`ra [ _Quests_]\nRating:\n0/1**_\\*__\\*__\\*__\\*__\\*_**\n(From 1 rating)\nInformation:\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n- Experience\n- Money\n**Quest Items:**\n- Bauble of Atrebe [item=127790]\n- Chardok Historical Records [item=127786]\n- Eye of Nik`ro [item=127787]\n- Locked Tomes of Atrebe [item=127789]\n**Related Creatures:**\n- Prince Selrach Di`zok [npc=51005]\n**Era:** | !Empires of Kunark\nRecommended:\n**Group Size:** | Solo\n**Min. # of Players:** | 1\n**Max. # of Players:** | 6\n**Appropriate Classes:**\n**Appropriate Races:**\nEntered: Fri Feb 10 22:29:39 2017\nModified: Wed Nov 27 11:16:36 2024 | | Pre Req:\n\\- Achievement: Partisan of Lceanium (Concerned Citizens, Contacting the Leadership, Disappearing Dragons, Sneaky Sarnak)\n\\- Achievement: Partisan of The Scorched Woods (Digging Yourself Deeper, The Last Grove, Where is Burning Woods?, On Nobody's Side)\n\\- Probing the Fortress, Their Own Medicine and Destabilizing Chardok.\nTalk to Royal Historian Fio`ra [npc=51460] in CHARDOK\nSay help to get the task.\n\n---\n\n02. Collect Chardok Historical Records 0/5 (Chardok)\n\n\n\nPick up blue open-face books off of shelves, or stacks of books from tables.\n\n03. Give Chardok Historical Records to Royal Historian Fio'ra 0/5 (Chardok)\n\n\n\nTurn in the books to the historian .\n\n04. Collect the Eye of Nik'ro 0/1 (Chardok)\n\n\n\nNik'ro the rowdy spawns, kill him and loot his eye.\n\n05. Interrogate undead sarnak with the Eye of Nik'ro 0/3 (Chardok)\n\n\n\nGo outside the library and click the eye on undead sarnak after fighting them to 50%.\n\n06. Summon Nik'ro at the bridge in front of the royal palace 0/1 (Chardok)\n\n\n\nClick the eye at the bridge with the waterfall.\n\n07. Talk with Nik'ro the cyclops 0/1 (Chardok)\n\n\n\nHail Nik'ro the cyclops.\n\n08. Go to the Night Garden below the bridges 0/1 (Chardok)\n\n\n\nGo to the Night Garden.\n\n09. Get answers from ancient dead 0/7 (Chardok)\n\n\n\nClick the Eye of Nik'ro and kill the mob that spawns.\n\n10. Summon Nik'ro and discuss what you learned 0/1 (Chardok)\n\n\n\nClick the Eye of Nik'ro.\n\n11. Request permission from Prince Selrach Di`zok 0/1 (Chardok)\n\n\n\nTravel to the Prince's room, inside two mobs will spawn and attack.\n\n12. Return to Royal Historian Fio'ra in the library 0/1 (Chardok)\n\n\n\nHail Historian Fio'ra in the library.\n\n13. Find the Vault of Atrebe 0/1 (Chardok)\n\n\n\nTravel to the Vault of Atrebe in the northeast corner.\n\n14. Collect Baubles of Atrebe 0/10 (Chardok)\n\n\n\nLoot Baubles of Atrebe from dervishes.\n\n15. Collect Locked Tomes of Atrebe 0/30 (Chardok)\n\n\n\nPick up piles of books in the area.\n\n16. Give Baubles of Atrebe to Royal Historian Fio'ra 0/10 (Chardok)\n\n\n\nTurn in the baubles to Royal Historian Fio'ra .\n\n17. Give Locked Tomes of Atrebe to Royal Historian Fio'ra 0/30 (Chardok)\n\n\n\nTurn in the locked tomes to Royal Historian Fio'ra.\n\n18. Ask Royal Historian Fio'ra what to do next 0/1 (Chardok)\n\n\n\nSay 'What can I do for you?' to the historian..\n\n19. Get out of Fio'ra's sight... quietly 0/1 (Chardok)\n\n\n\nLeave the library.\n\n---\n\nReward(s):\n106pp, 5g\nExperience\n- 106 PP, 5 G, Experience",
    },
  },
}
