-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for Moors of Nokk (moorsofnokk)
-- Total Quests: 4
-- ============================================================================

return {
  zone = "moorsofnokk",
  zone_name = "Moors of Nokk",
  quests = {
    {
      id = "12614",
      title = "Material Gatherer",
      exp = "30",
      exp_name = "Laurion's Song",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Taskmaster Grawh",
      loc = nil,
      triggers = {
        "Hail, Taskmaster Grawh",
        "I need work.",
        "I will gather some materials.",
        "I",
        "_Quests_",
        "work",
        "rodents",
        "materials",
      },
      items_required = {
      },
      rewards = {
        { id = 148179, name = "Perfect Spider Silk", type = "item" },
        { id = 148178, name = "Perfect Venom Sac", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Moors of Nokk [zone=1330]\n**Who:**\n- Taskmaster Grawh [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 110\n**Maximum Level:** | 130\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n**Quest Items:**\n- Perfect Spider Silk [item=148179]\n- Perfect Venom Sac [item=148178]\n**Related Creatures:**\n- a crevice spider [npc=59227]\n- a mature spider [npc=59234]\n- a moors snake [npc=59237]\n- a small spiderling [npc=59261]\n**Era:** | !Laurion's Song\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Fri Nov 3 02:59:16 2023\nModified: Sat Apr 18 07:09:21 2026 | | **Laurion's Song Info & Guides: Overview \\| Progression & Task List \\| Raiding \\| Visible Armor**\n\n---\n\nYou can obtain this solo task from Taskmaster Grawh [npc=59276] in the Moors of Nokk. You can find him at /way 1395, -488, -99. He is on the Find tool (Ctrl+F).\nYou say, 'Hail, Taskmaster Grawh'\nTaskmaster Grawh says, 'Hey! What are you doing out here? Get back to the camp and get to [work]!'\nYou say, 'I need work.'\nTaskmaster Grawh seems to ignore the fact you're not Rallosian, or simply doesn't care. 'Well, if you needed a task, why didn't you say so? On priority, we have a few needs to get rid of some pesky annoyances. We have a need to get rid of some [rodents], as well as to gather some [materials] from other pests.'\nYou say, 'I will gather some materials.'\nTaskmaster Grawh says, 'I'm going to need you to gather a few snake venom sacs and a few spider silks. Both are valuable commodities, but it's far too mundane a task for our guard to take up. So that's where you come in. Are you [up to] the task?'\nYou say, 'I'm up to it.'\nYou have been assigned the task 'Material Gatherer'.\n\n---\n\nTaskmaster Grawh thinks you're a Rallosian! It's either that or fodder for whatever task he has need for today. He has requested a number of materials from various pests around. Specifically he is requesting intact venom sacs from snakes, and intact spider silk from local spiders.\n1\\. Loot 4 Perfect Venom from Snakes 0/4 Moors of Nokk\nSnakes can be found about mid zone to the northern half. Loot 4 Perfect Venom Sac [item=148178] from them.\n2\\. Loot 4 Perfect Spider Silk from Spiders 0/4 Moors of Nokk\nSpiders can be found in the far southern part of the zone, scattered through out that area. Loot 4 Perfect Spider Silk [item=148179] from them.\n3\\. Deliver 4 Perfect Venom Sacs to Taskmaster Grawh 0/4 Moors of Nokk\nYou offered 1 Perfect Venom Sac to Taskmaster Grawh.\nYou offered 1 Perfect Venom Sac to Taskmaster Grawh.\nYou offered 1 Perfect Venom Sac to Taskmaster Grawh.\nYou offered 1 Perfect Venom Sac to Taskmaster Grawh.\nYour task 'Material Gatherer' has been updated.\nYour task 'Material Gatherer' has been updated.\nYour task 'Material Gatherer' has been updated.\nYour task 'Material Gatherer' has been updated.\nYou complete the trade with Taskmaster Grawh.\n4\\. Deliver 4 Perfect Spider Silk to Taskmaster Grawh 0/4 Moors of Nokk\nYou offered 1 Perfect Spider Silk to Taskmaster Grawh.\nYou offered 1 Perfect Spider Silk to Taskmaster Grawh.\nYou offered 1 Perfect Spider Silk to Taskmaster Grawh.\nYou offered 1 Perfect Spider Silk to Taskmaster Grawh.\nYour task 'Material Gatherer' has been updated.\nYour task 'Material Gatherer' has been updated.\nYour task 'Material Gatherer' has been updated.\nYour task 'Material Gatherer' has been updated.\nTaskmaster Grawh has taken posession of the trade goods, but what the Rallosians will do with them is unknown. Maybe you helped their cause, but maybe it's immaterial in the end.\nYou complete the trade with Taskmaster Grawh.\n\n---\n\nReward(s):\n141 platinum 6 gold 6 silver 7 copper\nYou gain experience!\n**Submitted by:** Gidono",
    },
    {
      id = "12613",
      title = "How Does the Grass Grow?",
      exp = "30",
      exp_name = "Laurion's Song",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Dhakka Nogg - Moors of Nokk",
      loc = nil,
      triggers = {
        "Hail, Dhakka Nogg",
        "I am not a slave.",
        "I bother because I care.",
        "I won",
        "grass?",
        "Kaleste says the grass is dry and patchy.",
        "I will do more. What shall you have me do?",
        "_Quests_",
      },
      items_required = {
      },
      rewards = {
        { id = 148181, name = "Dried Meat", type = "item" },
        { id = 148180, name = "Hardened Dregcheese", type = "item" },
        { id = 148182, name = "Jug of Water", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Moors of Nokk [zone=1330]\n**Who:**\n- Dhakka Nogg - Moors of Nokk [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 120\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n**Quest Items:**\n- Dried Meat [item=148181]\n- Hardened Dregcheese [item=148180]\n- Jug of Water [item=148182]\n**Related Creatures:**\n- Kaleste [npc=59270]\n- Mystic Eoreg [npc=59722]\n- a Nokk attacker [npc=59718]\n**Related Quests:**\n- Partisan of Moors of Nokk (15 Points) [quest=12657]\n**Era:** | !Laurion's Song\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Fri Nov 3 02:56:51 2023\nModified: Tue Jan 30 20:54:51 2024 | | **Laurion's Song Info & Guides: Overview \\| Progression & Task List \\| Raiding \\| Visible Armor**\n\n---\n\nYou can obtain this solo task from Dhakka Nogg [npc=59199] in the Moors of Nokk. You can find Dhakka at /waypoint 1058,-522,-59. She is on the find tool as well CTRL F.\nYou say, 'Hail, Dhakka Nogg'\nDhakka Nogg says, 'What are you doing here? I would recommend getting back to the [slave] caves before your handler finds you.'\nYou say, 'I am not a slave.'\nDhakka Nogg says, 'You are no Rallosian, and you are no slave. I won't dare ask why you [bother] to tread so close to our city then.'\nYou say, 'I bother because I care.'\nDhakka Nogg says, 'Do you now? Do you care? And what are you going to do with that care? Are you going to rage against the leadership and get yourself killed? No, be a good little non-believer and [leave] back into the Elddar or wherever you came from.'\nYou say, 'I won't leave. Not yet. I'm here to find out what you do with your care.'\nYou have been assigned the task 'How Does the Grass Grow?'.\nDhakka Nogg narrows her eyes. 'Do not presume, stranger.' There's a momentary look of discomfort on her face. Her voice lowers, commenting, 'You will speak nothing of this. However, if care is your concern, find the slave who goes by Kaleste. Ask her about the grass, and then return here.'\n\n---\n\nShakka Nogg is curious about you and your interest in the goings on of the Moors. The ogre wizard sets out to test your empathy with certain inhabitants of the Moors.\nDhakka has requested you reach out to an elven slave named Kaleste. Ask her about the grass.\n1\\. Ask the elven slave Kaleste about the grass 0/1 Moors of Nokk\n_You can find Kaleste [npc=59270] in the southern part of the zone at /way -536,-524,-165._\nYou say, 'grass?'\nKaleste looks upon the adventurer with wide eyes. 'The grass is dry,' her voice comes, soft and quiet. 'And patchy.' She disengages with a downward gaze.\n2\\. Let Dhakka know what Kaleste has said 0/1 Moors of Nokk\nYou say, 'Hail, Dhakka Nogg'\nDhakka Nogg says, 'You return. Have you spoken with [Kaleste]?'\nYou say, 'Kaleste says the grass is dry and patchy.'\nDhakka Nogg sets her jaw, her face contorting. 'Well.' There's only the briefest glances across the immediate area before asking, 'If you care, I have [more] for you to do on behalf of another who cares. I cannot guarantee safety, for you are not ours, or theirs, but in that same breath... that may very well be your shield.'\nYou say, 'I will do more. What shall you have me do?'\nDhakka Nogg says, 'I need you to go to the stores in the outer city. Be stealthy if you can, for we do not want to raise suspicion. Gather some hardened dregcheese, and dried meat. Gather some fresh water from the pools.' The corner of her mouth curls up. 'Let's water the grass.'\n3\\. Gather some Hardened Dregcheese 0/1 Moors of Nokk\n_Dhakka Nogg has requested some hardened dregcheese, some dried meat, and a jug of water from the pool near the entrance to the city of Nokk._\nYou can find Hardened Dregcheese [item=148180] as a ground spawn on boxes and such as ground spawns in the far south part of the zone. They are a light orange color.\nOne location is at /way -692,-33,-146.\n4\\. Gather some Dried Meat 0/1 Moor of Nokk\nIn the same area of the zone you can find Dried Meat [item=148181] on tables.\nOne location is at /way -819,+331,-138 looks like a drumstick.\n5\\. Obtain a Jug of Water from the pool near the entrance to the city 0/1 Moors of Nokk\nIn the far southeast corner of the zone there is a waterfall, go to /way -314,-1550,-240 and float or swim around until you get the update for this step. You will receive a Jug of Water [item=148182] on your cursor.\n6\\. Hail Dhakka to let her know you got the items 0/1 Moors of Nokk\nYou say, 'Hail, Dhakka Nogg'\nDhakka Nogg says, 'I will trust that you have what was requested.' Her words remain vague as to the details. 'If everything looks in order, go take it to our mutual friend.'\n7\\. Deliver the Hardened Dregcheese to Kaleste 0/1 Moors of Nokk\nYou offered 1 Hardened Dregcheese to Kaleste.\n8\\. Deliver the Dried Meat to Kaleste 0/1 Moors of Nokk\nYou offered 1 Dried Meat to Kaleste.\n9\\. Deliver the Jug of Water to Kaleste 0/1 Moors of Nokk\nYou offered 1 Jug of Water to Kaleste.\n10\\. Hail Dhakka with the update 0/1 Moors of Nokk\nBe ready for this, it will spawn 3 a Nokk attacker [npc=59718] that you have to kill, they are rootable, mezzable and slowable, and don't see through invis. Position yourself to where you are away from the road because there are soldiers walking up and down that road and rats are not far away either.\nIf you have multiple people in the group that have this step, have 1 person hail and then kill those mobs. Then next person hail and kill mobs. Since this is a solo task and not a shared task it will spawn multiples with each hail. Also, that person could lose aggro somehow and wait for them to despawn.\nYou say, 'Hail, Dhakka Nogg'\nDhakka Nogg says, 'I can see now that you do care. I ask that you keep this between us. Empathy is a weakness I cannot afford to show. Not if I wish to continue to be in a position to help.'\nMystic Eoreg growls. \"Dhakka. You pathetic fool. Do you think you weren't noticed?'\nMystic Eoreg throws a punch at Dhakka, landing squarely in her jaw.\nMystic Eoreg growls. \"Dhakka. You pathetic fool. Do you think you weren't noticed?'\nMystic Eoreg says, 'That's only a warning, Dhakka. Stay away from the slave filth and get back to your studies. If I see you interfere again, I will rain Rallos' anger upon you and yours.' Each of his next words are punctuated with spit as he speaks. 'Do. You. Understand?'\nDhakka Nogg mutters, 'Yes, Mystic Eoreg.'\nMystic Eoreg says, 'Good.' He waves over some friends. 'As for the outsider...' With a nod to them, he walks off again to leave them to their business. You'd best defend yourself.'\nThis is where the attackers spawn.\n11\\. Kill the Nokk Attackers! 0/3 Moors of Nokk\n12\\. Hail Dhaka Nogg to check in with her 0/1 Moors of Nokk\nYou say, 'Hail, Dhakka Nogg'\nOpening up about her empathy regarding the plight of the slaves of Nokk, Dhakka Nogg put a lot on the line to ensure they were fed. However, her work isn't done yet.\nDhakka Nogg says, 'You held your own against them. Daresay, your actions have been their own encouragement of my \"care\". It is of no concern to you, being an outsider, but if you do wish to [continue], let me know. We have work to do.'\nThis leads into the next task, The Next Targets [quest=12842].\n\n---\n\nReward(s):\nNothing\n**Submitted by:** Gidono",
    },
    {
      id = "12842",
      title = "The Next Targets",
      exp = "30",
      exp_name = "Laurion's Song",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Dhakka Nogg - Moors of Nokk",
      loc = nil,
      triggers = {
        "I wish to continue helping with the cause.",
        "I can look into it.",
        "But you are Rallosian.",
        "What is your goal?",
        "I agree that it",
        "I will seek the information.",
        "_Quests_",
        "continue",
      },
      items_required = {
      },
      rewards = {
        { id = 148456, name = "Consolidated Rallosian Missives", type = "item" },
        { id = 148455, name = "Rallosian Missive - Conscription Orders", type = "item" },
        { id = 147832, name = "Rallosian Missive - Elddar", type = "item" },
        { id = 148192, name = "Rallosian Missive - Pal'lomen", type = "item" },
        { id = 147834, name = "Rallosian Missive - Plane of Earth", type = "item" },
        { id = 148191, name = "Rallosian Missive - Plane of Fire", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Moors of Nokk [zone=1330]\n**Who:**\n- Dhakka Nogg - Moors of Nokk [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 120\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n- Experience\n- Money\n**Quest Items:**\n- Consolidated Rallosian Missives [item=148456]\n- Rallosian Missive - Conscription Orders [item=148455]\n- Rallosian Missive - Elddar [item=147832]\n- Rallosian Missive - Pal'lomen [item=148192]\n- Rallosian Missive - Plane of Earth [item=147834]\n- Rallosian Missive - Plane of Fire [item=148191]\n- Rallosian Missive - Unkempt Woods [item=147833]\n**Related Creatures:**\n- a Nokk adjutant [npc=59239]\n- a Nokk bloodblade [npc=59242]\n- a Nokk cutthroat [npc=59246]\n- a Nokk fireblade [npc=59737]\n- a Nokk lieutenant [npc=59251]\n- a Nokk militant [npc=59723]\n**Era:** | !Laurion's Song\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Sun Nov 26 03:15:47 2023\nModified: Mon Aug 25 18:47:17 2025 | | **Laurion's Song Info & Guides: Overview \\| Progression & Task List \\| Raiding \\| Visible Armor**\n\n---\n\n**Prerequisite Task: How Does the Grass Grow? [quest=12613]**\n\n---\n\nYou can obtain this solo task from Dhakka Nogg [npc=59199] in the Moors of Nokk. You can find Dhakka at /waypoint 1058, -522, -59. She is on the find tool as well CTRL F.\nDhakka Nogg says, 'You held your own against them. Daresay, your actions have been their own encouragement of my \"care\". It is of no concern to you, being an outsider, but if you do wish to [continue], let me know. We have work to do.'\nYou say, 'I wish to continue helping with the cause.'\nDhakka Nogg says, 'Good.' She looks around the area again for any sign of Eoreg or another, and her voice is kept low. 'There is something disconcerting that I hope you can [look into]. That is, if you don't mind.'\nYou say, 'I can look into it.'\nDhakka Nogg says, 'Also good. You've stumbled upon two years worth of work for me. Two years of sneaking, of gathering information, of building trust with the slaves. It may be for naught, for although we are stretching thin, the [Rallosians] have grand desires, and their thirst for blood will not be quenched.'\nYou say, 'But you are Rallosian.'\nDhakka Nogg says, 'I am. By culture? By heritage? By acknowledgement of our creation?' She gives one soft shake of her head. 'But do I want to terrorize every other living thing in this blasted land, and the lands beyond? What did they do to deserve it? What does it do beyond expanding our resources to go and do it again, and again, and again? Is there no end [goal]? Is there no respite?'\nYou say, 'What is your goal?'\nDhakka Nogg says, 'I want us to expand our knowledge, to learn, to grow. We should approach these peoples with a mutual understanding, and be able to share our knowledge openly between us.' She sadly smiles. 'How much more efficient would our path to enlightenment and magical exploration be if we didn't have to kill them and then spend years translating and decyphering their texts? My people only care for the destructive power of the arcane, and care not about the intricacies of mana and planar sources. It is a [waste] of our intellectual gifts.'\nYou say, 'I agree that it's a waste.'\nDhakka Nogg says, 'Thank you. Thanks for your understanding. So, that leads me to those \"grand desires\" that I am so concerned about. I worry that we're on the brink of multiple offensives. I'd like you to see if there's any additional [information] while I try to meet up with a few of my contacts. Are you willing to do that?'\nYou say, 'I will seek the information.'\nYou have been assigned the task 'The Next Targets'.\nDhakka Nogg says, 'Please search the base and the tower for any missives you might find. You'll find some of the higher ranked personnel are more likely to have them on them, if you don't mind getting your hands dirty.' She grits her teeth. 'I suppose it is very beneficial we have an outsider assisting.'\n\n---\n\nDhakka Nogg has begun to trust you. There's rumors that there's more targets to come for the Rallosian army, and Dhakka Nogg has requested that you gather any intelligence you can find amongst the military areas and ranking personnel.\nThe Rallosian Missives can be picked up from the ground spawns ahead of time.\n1\\. Obtain one of six unique Rallosian Missives 0/1 Moors of Nokk\nKill Ranked Nokk's to get the item to drop for this step and the below steps.\nThis step updates when you loot a Rallosian Missive - Eldarr. [item=147832]. This can drop from either a Nokk lieutenant, Nokk bloodblade, or a Nokk militant.\n2\\. Obtain one of six unique Rallosian Missives 0/1 Moors of Nokk\nThis step updates when you loot a Rallosian Missive - Unkempt Woods [item=147833]. This can drop from a Nokk Adjutant, a Nokk sentinal, or a Nokk tactician.\n3\\. Obtain one of six unique Rallosian Missives 0/1 Moors of Nokk\nThis step updates when you loot a Rallosian Missive - Plane of Earth [item=147834]. This can drop from a Nokk lieutenant, a Nokk bloodblade, a Nokk militant, a Nokk tactician, a Nokk Fireblade, a Nokk Adjutant or a Nokk cutthroat.\n4\\. Obtain one of six unique Rallosian Missives 0/1 Moors of Nokk\nFor this step, you will need Rallosian Missive - Plane of Fire [item=148191], a ground spawn at /way +819,+940,+146 in the Tower on the 3rd floor in the room on the table.\n5\\. Obtain one of six unique Rallosian Missives 0/1 Moors of Nokk\nFor this step, you will need Rallosian Missive - Pal'lomen [item=148192], a ground spawn at /way +823,+992,+36 in the Tower on the table on the east side as you come into the Tower on the 1st floor.\n6\\. Obtain one of six unique Rallosian Missives 0/1 Moors of Nokk\nFor this step, you will need Rallosian Missive - Conscription Orders [item=148455], a ground spawn at /way +450,+50 on a table in the fort south of the lake.\n7\\. Consolidate the missives for Dhakka Nogg 0/1 ALL\nRight click any of the Rallosian Missives to transform them into a Consolidated Rallosian Missives [item=148456].\n8\\. Give Dhakka Nogg the consolidated missives 0/1 Moors of Nokk\n9\\. Check in with Dhakka Nogg 0/1 Moors of Nokk\nHail Dhakka Nogg.\n\n---\n\nReward(s):\n141 platinum 6 gold 6 silver 7 copper\nYou gain experience!\n**Submitted by:** Gidono",
    },
    {
      id = "12855",
      title = "Slow Down the March",
      exp = "30",
      exp_name = "Laurion's Song",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Dhakka Nogg - Moors of Nokk",
      loc = nil,
      triggers = {
        "What",
        "I agree, it is sick and twisted. What can we do?",
        "You only want me to incapacitate them?",
        "_Quests_",
        "again",
        "incapacitate",
        "not all",
        "sick",
      },
      items_required = {
      },
      rewards = {
        { id = 148458, name = "Compiled Rallosian Intelligence", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Moors of Nokk [zone=1330]\n**Who:**\n- Dhakka Nogg - Moors of Nokk [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 120\n**Maximum Level:** | 130\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Experience\n- Money\n**Quest Items:**\n- Compiled Rallosian Intelligence [item=148458]\n**Related Creatures:**\n- Armorer Marat [npc=59266]\n- Elistyl Kanghammer - Moors of Nokk [npc=59202]\n- Firemage Omor [npc=59279]\n- Shalowain - Moors of Nokk [npc=59770]\n- Slavekeeper Zagun [npc=59274]\n- Trainer Torkh [npc=59277]\n**Era:** | !Laurion's Song\nRecommended:\n**Group Size:** | Solo\n**Min. # of Players:** | 1\n**Max. # of Players:** | 1\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Sun Dec 17 08:49:45 2023\nModified: Tue Feb 6 16:29:26 2024 | | **Laurion's Song Info & Guides: Overview \\| Progression & Task List \\| Raiding \\| Visible Armor**\n\n---\n\n**Prerequisite Task: The Next Targets [quest=12842]**\n\n---\n\nYou can obtain this solo task from Dhakka Nogg [npc=59199] in Moors of Nokk. You can find Dhakka Nogg at /waypoint 1058,-522,-59. She is on the find tool as well CTRL F.\nDhakka Nogg says, 'We no longer have time, friend. Would you be up for helping me [again]?\nDhakka Nogg says, 'Thank you. If they're conscripting people, then there is little time. I need you to [incapacitate] several key personnel which should delay any marching orders, to buy us some time.'\nDrakka Nogg's time is running out, with the conscription orders implying a very swift rollout to the next targets planned by the Rallosian war machine. She's like to make her stance known by incapacitating some key figures in and around Nokk.\n\n---\n\n1\\. Get additional information from Dhakka Nogg 0/1 Moors of Nokk\nMystic Eoreg passes a scroll over to Dhakka, a smirk upon his face and humor in his eyes. 'You're up, bookworm! Get your tomes ready, you're going to the frontlines.'\nDrakka Nogg says, 'It figures that Mystic Eoreg would deliver General Terok's orders. I need to report to Master Trablic sooner rather than later. But, that's [not all].\nMystic Eoreg doesn't bother sticking around to see her reaction. The Mystic laughs to himself as he walks off.\nYou say, 'What's not all?'\nDhakka Nogg says, 'Those wretches will be using the captives as living shields! They plan to put the slaves on the frontlines, and they plan for me to be there to watch them all die fighting for a war they, themselves, are victims of. It's [sick], twisted!\n2\\. Check in with Dhakka Nogg following Eoreg's departure 0/1 Moors of Nokk\nYou say, 'I agree, it is sick and twisted. What can we do?'\nDhakka Nogg says, 'It just means we need to start now. Right this moment. Let's not dally. I can only delay reporting in so long before they come for me.'\nYou say, 'You only want me to incapacitate them?'\nDhakka Nogg says,'If you kill them, it goes against the message we're trying to send. Some deaths are inevitable as you will no doubt find confrontation, but do whatever in your power to ensure that these personnel stay alive. They must know the power of mercy.'\n3\\. Incapacitate Trainer Torkh 0/1 Moors of Nokk\n4\\. Incapacitate Armorer Marat 0/1 Moors of Nokk\n5\\. Incapacitate Firemage Omor 0/1 Moors of Nokk\n6\\. Incapacitate Slavekeeper Zagun 0/1 Moors of Nokk\n7\\. Defend yourself against 6 Rallosians 0/6 Moors of Nokk\n8\\. Update Dhakka Nogg with what you find 0/1 Moors of Nokk\nCheck in with Dhakka Nogg and let her know that you have taken down the notable figures.\nDhakka Nogg gives you Compiled Rallosian Intelligence [item=148458].\n9\\. Take the Compiled Rallosian Intelligence to a contact 0/1 Moors of Nokk\nWith the Compiled Rallosian Intelligence in-hand, take it to Shalowain or Elistyl Kanghammer to the north of Dhakka Nogg.\nIt's only a matter of time before Dhakka Nogg must face her superiors, but the intelligence was able to make it to the party before it was too late.\nShalowain says, 'This is the intelligence we were promised? Good. We can use this.'\nElistyl Kanghammer says, 'This is the intelligence we were promised? Good. We can use this.'\n\n---\n\nReward(s):\n141 platinum 6 gold 6 silver 7 copper\nYou gain experience!",
    },
  },
}
