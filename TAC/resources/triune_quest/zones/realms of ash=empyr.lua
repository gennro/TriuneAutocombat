-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for Empyr: Realms of Ash (realms of ash=empyr)
-- Total Quests: 6
-- ============================================================================

return {
  zone = "realms of ash=empyr",
  zone_name = "Empyr: Realms of Ash",
  quests = {
    {
      id = "9238",
      title = "Partisan of Empyr: Realms of Ash (10 Points)",
      exp = "25",
      exp_name = "The Burning Lands",
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
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Empyr: Realms of Ash [zone=1210]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | No\n**Can Be Shrouded?:** | No\n**Quest Type:** | Achievement\n**Quest Goal:**\n- Advancement\n**Related Quests:**\n- Champion of The Burning Lands (30 Points) [quest=9255]\n- Fire and Fury [quest=9274]\n- Palace of Embers [quest=9433]\n- Prisoner's Dilemma [quest=9265]\n**Era:** | !The Burning Lands\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Wed Oct 31 00:11:32 2018\nModified: Tue Dec 5 05:21:04 2023 | | This achievement is gained upon completing the following quests in Empyr: Realms of Ash\nStar Stealing Sage - Prisoner's Dilemma\nStar Stealing Sage - Palace of Embers\nHorizon Blighted Sage - Fire and Fury\nReward(s):\nNone\n**Submitted by:** Gidono",
    },
    {
      id = "9265",
      title = "Prisoner's Dilemma",
      exp = "25",
      exp_name = "The Burning Lands",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Star Stealing Sage",
      loc = nil,
      triggers = {
        "Hail, Star Stealing Sage",
        "prisoner",
        "why",
        "could",
        "Hail, Blazing Battleworn Eyes",
        "reckoning",
        "if you agree to tell us more we will let you go",
        "Hail, Great Sky Ocean",
      },
      items_required = {
        { name = "some information about what is going on", count = 1 },
        { name = "the 3 messages to Star Stealing Sage", count = 1 },
      },
      rewards = {
        { id = 134788, name = "Leather Messenger Case", type = "item" },
        { id = 134787, name = "Leather Messenger Case", type = "item" },
        { id = 134786, name = "Leather Messenger Case", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Empyr: Realms of Ash [zone=1210]\n**Who:**\n- Star Stealing Sage [npc=54116]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Quest\n**Quest Goal:**\n- Advancement\n**Quest Items:**\n- Leather Messenger Case [item=134788]\n- Leather Messenger Case [item=134787]\n- Leather Messenger Case [item=134786]\n**Related Creatures:**\n- Blazing Battleworn Eyes [npc=54210]\n- Great Sky Ocean [ _Quests and Mission_]\n- a djinn messenger [npc=54097]\n- a fertive messenger [npc=54100]\n**Related Quests:**\n- Fight Fire [quest=9263]\n- Partisan of Empyr: Realms of Ash (10 Points) [quest=9238]\n- Soldier of Air [quest=9225]\n- Trial of Three (Trial of Smoke) [quest=9281]\n- Trial of the Ashes of Rusted Cliff's Glory (Trial of Smoke) [quest=9335]\n- Trial of the Eternal Cyclone (Trial of Smoke) [quest=9336]\n- Trial of the Speaker's Amphitheater (Trial of Smoke) [quest=9282]\n- Trial of the Wending Ways (Trial of Smoke) [quest=9337]\n**Era:** | !The Burning Lands\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Mon Nov 5 03:15:52 2018\nModified: Mon Feb 16 00:08:25 2026 | | **Prerequisite Quests:** Soldier of Air, Fight Fire, and anyone one of the Trial of Smoke tasks.\nYou can get this quest from Star Stealing Sage on the east side of the zone, almost due east of the entrance of Aalishai.\nYou say, 'Hail, Star Stealing Sage'\nStar Stealing Sage shakes his head, glancing at his guards.\n3 guards are around this NPC and once killed Star Stealing Sage can talk to you.\nYou say, 'Hail, Star Stealing Sage'\nStar Stealing Sage says, 'Hello, mortal. Do not harm me, I am already a [prisoner] here. You gain nothing by killing me.'\nYou say, 'prisoner'\nStar Stealing Sage says, 'I fell in battle and was captured. Though I am a failure, I have been pondering the reason for my failure. Why is it that we battle? All know the risks. What is there to gain that is so valuable when compared to that risk? I must wonder [why] it is that we battle.'\nYou say, 'why'\nStar Stealing Sage says, 'There must have been a reason to form such a contract. I would know the reason. You, who have passed the Trails of Smoke, must understand how things are done. Perhaps you [could] discover this for me. Why is it that we fight?'\nYou say, 'could'\nYou have been assigned the task 'Prisoner's Dilemma'.\nStar Stealing Sage says, 'That would be a great thing, such knowledge. Perhaps that would make my [imprisonment] more tolerable.'\n\n---\n\n- 1\\. Intercept messenger going to the warfront. Find any information you can. 0/1 Empyr: Realms of Ash\n- 2\\. Intercept messenger coming from the warfront. Find any information you can. 0/1 Empyr: Realms of Ash\n- 3\\. Intercept messenger that travels the towers. Find any information you can. 0/1 Empyr: Realms of Ash\n**Task Window:** There are messengers that fly between the front and the castle of Aalishai. Kill them and take their messages. These may give some information about what is going on.\nKill \"a furtive messenger\" roaming and loot a Leather Messenger Case from each of them. Sometimes they have no drops and there are only so many of them. They do respawn. The drop counts for everyone in the group.\n- 4\\. Question, if you can, Blazing Battleworn Eyes. 0/1 Empyr: Realms of Ash\n**Task Window:** One of the messages was written by someone called Blazing Battleworn Eyes. Seek this being out and learn what you can, however you can.\nYou say, 'Hail, Blazing Battleworn Eyes'\nBlazing Battleworn Eyes says, 'Be gone, mortal. I have nothing to discuss with you. Go or there shall be a [reckoning] between us.'\nYou say, 'reckoning'\nBlazing Battleworn Eyes says, 'Well, then die!'\nBlazing Battleworn Eyes says, 'Trespass on our claim means death!'\nBring him down to 9%.\nYou say, 'if you agree to tell us more we will let you go'\nYour task 'Prisoner's Dilemma' has been updated.\nBlazing Battleworn Eyes says, 'Acceptable. I do not know much, unfortunately for you. I have instructions about when and where each battle is to occur, but this is fairly common knowledge. All my soldiers know this. There is, however, one order that I have been given. I have been told to ensure the death of one called Great Sky Ocean, should she appear on the battlefield. This is stipulated as acceptable in the contract. I also know that the contract has been countersigned by both Moon Serf of the Harmonious Heavens and Heart of Flawless Brass, as that must be true for something like a war to be executed. How or why they did so, I do not know.'\n- 5\\. Bring the message to the warfront to Star Stealing Sage. 0/1 Empyr: Realms of Ash\n- 6\\. Bring the message from the warfront to Star Stealing Sage. 0/1 Empyr: Realms of Ash\n- 7\\. Bring the message from the Empyr towers to Star Stealing Sage. Tell ??? 0/1 Empyr: Realms of Ash\n**Task Window:** Star Stealing Sage may be able to glean some information from the message being sent to the warfront. It seems the most promising.\nGive the 3 messages to Star Stealing Sage.\nStar Stealing Sage peers at the notes you have given him. 'Fascinating. These messages appear to indicate that the war was decreed by a contract between two powerful beings and that the leaders of the djinn and efreeti armies have to honor it. What this Blazing Battleworn Eyes said indicates little, but did name Great Sky Ocean. I do not know her personally, but it seems that she should be warned. It may also be true that she knows something useful.'\n- 8\\. Speak with Great Sky Ocean about the war. 0/1 Stratos: Zephyr's Flight\n**Task Window:** Blazing Battleworn Eyes mentioned someone called Great Sky Ocean. Speak with her about the war. Perhaps she knows something. Star Stealing Sage knows that she frequents Stratos. You may find her there.\nYou say, 'Hail, Great Sky Ocean'\nGreat Sky Ocean says, 'What? Well, I am unsurprised. Heart of Flawless Brass has never forgiven me for proving to her that I am a far better singer and poet than she. It was a formal contest and the Udex showed no doubt that I proved the better that day. The question is, is she petty enough to begin a war to get revenge upon me. I believe so, though why she would think that I would volunteer for battle, or be ordered to it, I do not know. War is not a skill I have ever tried to be good at. I do thank you for your information, mortal. I will certainly avoid the battle now. However, if you seek to end this war as this Star Stealing Sage wishes, well, I may have good [news].'\n\n---\n\nReward(s):\n283 platinum 3 gold 3 silver 3 copper\nYoi gain experience!\n**Submitted by:** Gidono",
    },
    {
      id = "9271",
      title = "Scalding Webs We Weave",
      exp = "25",
      exp_name = "The Burning Lands",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Charred Forest",
      loc = { y = 1496.0, x = 1314.0, z = -47.0 },
      triggers = {
        "Hail, Charred Forest",
        "What was your title?",
        "tasks",
        "Giant Lava Spiders",
        "_Quests_",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "**Status: Incomplete**\n\nQuest Started By: | Description:\n**Where:**\n- Empyr: Realms of Ash [zone=1210]\n**Who:**\n- Charred Forest [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Quest\n**Quest Goal:**\n- Advancement\n**Related Creatures:**\n- a giant lapillus lava spider [npc=54106]\n**Related Quests:**\n- Fight Fire [quest=9263]\n- Mercenary of Empyr: Realms of Ash (10 Points) [quest=9237]\n- Soldier of Air [quest=9225]\n- Trial of Three (Trial of Smoke) [quest=9281]\n- Trial of the Ashes of Rusted Cliff's Glory (Trial of Smoke) [quest=9335]\n- Trial of the Eternal Cyclone (Trial of Smoke) [quest=9336]\n- Trial of the Speaker's Amphitheater (Trial of Smoke) [quest=9282]\n- Trial of the Wending Ways (Trial of Smoke) [quest=9337]\n**Era:** | !The Burning Lands\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Tue Nov 6 03:28:32 2018\nModified: Tue Dec 5 05:21:04 2023 | | **Prerequisite Quests:** Soldier of Air, Fight Fire, and anyone of the Trial of Smoke tasks.\nYou can get this quest from Charred Forest at +1496, +1314, -47 in the northwest corner of the zone. She is on the find tool.\nYou say, 'Hail, Charred Forest'\nCharred Forest says, 'Good good! A mortal, you can help me out! The efreeti took from me my life, my memories, my [title: What was your title?], all that I worked tirelessly on for ages. I want to show them what happens when they mess with a being capable of such revenge! I want to show them what happens when they try to cross paths with me!'\nYou say, ' What was your title?'\nCharred Forest says, 'I was a commander of the Efreeti royal guard! However a scheme was crafted by the current rulers that cast me down the ranks to being exiled out here in Empyr. I have a plan in place in order to climb back up the ranks in order to get my revenge, but for that plan to start bearing fruit, I would like someone to... consider the positive effects they could have should they do a certain set of...[tasks].'\nYou say, 'tasks'\nYou say, 'Giant Lava Spiders'\nYou have been assigned the task 'Scalding Webs We Weave'.\nCharred Forest says, 'The efreeti use the giant lava spiders as beasts of burden, and some even use them as pets to keep them company. Our rules dictate that none of us can keep such creatures within the walls of our establishments, so most efreeti will let them roam here in Empyr and come and visit them from time to time. Kill them.'\n\n---\n\n2. Kill Giant Lava Spiders 0/5 Empyr: Realms of Ash\n\n\n---\n\nReward(s):\nNone\n**We need all dialogue, NPC's involved, faction hits and etc....**\n**Submitted by:** Gidono",
    },
    {
      id = "9273",
      title = "Slimy, Yet Sizzling",
      exp = "25",
      exp_name = "The Burning Lands",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Charred Forest",
      loc = { y = 1496.0, x = 1314.0, z = -47.0 },
      triggers = {
        "Hail, Charred Forest",
        "What was your title?",
        "tasks",
        "snails",
        "_Quests_",
        "Giant Lava Spiders",
        "Slag Golems",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
        { name = "Servants of Aalishai", change = -3 },
        { name = "Servants of Esianti", change = 3 },
        { name = "Servants of Mearatas", change = 3 },
        { name = "Servants of Loruella", change = 3 },
        { name = "Servants of Aalishai", change = -3 },
        { name = "Servants of Esianti", change = 3 },
      },
      walkthrough = "**Status: Incomplete**\n\nQuest Started By: | Description:\n**Where:**\n- Empyr: Realms of Ash [zone=1210]\n**Who:**\n- Charred Forest [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Quest\n**Quest Goal:**\n- Advancement\n- Experience\n- Money\n**Factions Raised:**\n- Servants of Esianti +3, +3, +3, +3\n- Servants of Loruella +3, +3, +3, +3\n- Servants of Mearatas +3, +3, +3, +3\n**Factions Lowered:**\n- Servants of Aalishai -3, -3, -3, -3\n**Related Creatures:**\n- a fire snail [npc=54373]\n- a flame snail [npc=54111]\n**Related Quests:**\n- Fight Fire [quest=9263]\n- Mercenary of Empyr: Realms of Ash (10 Points) [quest=9237]\n- Soldier of Air [quest=9225]\n- Trial of Three (Trial of Smoke) [quest=9281]\n- Trial of the Ashes of Rusted Cliff's Glory (Trial of Smoke) [quest=9335]\n- Trial of the Eternal Cyclone (Trial of Smoke) [quest=9336]\n- Trial of the Speaker's Amphitheater (Trial of Smoke) [quest=9282]\n- Trial of the Wending Ways (Trial of Smoke) [quest=9337]\n**Era:** | !The Burning Lands\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Tue Nov 6 03:32:08 2018\nModified: Tue Dec 5 05:21:04 2023 | | Prerequisite Quests: Soldier of Air, Fight Fire, and any of the Trial of Smoke tasks.\nYou can get this quest from Charred Forest at +1496, +1314, -47 in the northwest corner of the zone. She is on the find tool.\nYou say, 'Hail, Charred Forest'\nCharred Forest says, 'Good good! A mortal, you can help me out! The efreeti took from me my life, my memories, my [title: What was your title?], all that I worked tirelessly on for ages. I want to show them what happens when they mess with a being capable of such revenge! I want to show them what happens when they try to cross paths with me!'\nYou say, ' What was your title?'\nCharred Forest says, 'I was a commander of the Efreeti royal guard! However a scheme was crafted by the current rulers that cast me down the ranks to being exiled out here in Empyr. I have a plan in place in order to climb back up the ranks in order to get my revenge, but for that plan to start bearing fruit, I would like someone to... consider the positive effects they could have should they do a certain set of...[tasks].'\nYou say, 'tasks'\nCharred Forest says, 'Not that I would implore any mortal to do such tasks! Wouldn't suggest one to ever harm any efreeti directly. No, I could never ever ask a mortal to investigate [Giant Lava Spiders]. Or perhaps look into the amount of [Slag Golems] that have been showing up in Empyr. I CERTAINLY wouldn't ask a mortal to slay some [snails].'\nYou say, 'snails'\nYou have been assigned the task 'Slimy, Yet Sizzling'.\nCharred Forest says, 'The efreeti like to indulge every once in a while with a delicacy, flame snails and fire snails. While we don't need to eat for sustenance, we eat for enjoyment. Flavors and textures are more important than whether or not they make us feel, as you mortals put it, \"full\". Ruin their supply of these morsels.'\n\n---\n\n3. Kill Fire Snails or Flame Snails 0/4 Empyr: Realms of Ash\n\n\n\n**Task Window:** The flame snails and fire snails farmed by the efreeti as a delicacy. Removing them will cause a shortage of this indulgence they like to partake in.\n\n\n\n\na flame snail can be found in the southern part of the zone.\n\n\n\n\nA flame snail says, `You approach too close, mortal!\n\n\nA flame snail's corpse bursts into flame and heat.\n\n\nYour faction standing with Servants of Aalishai has been adjusted by -3.\n\n\nYour faction standing with Servants of Esianti has been adjusted by 3.\n\n\nYour faction standing with Servants of Mearatas has been adjusted by 3.\n\n\nYour faction standing with Servants of Loruella has been adjusted by 3.\n\n\nYour task 'Slimy, Yet Sizzling' has been updated.\n\n\n\n\nA flame snail says, `You approach too close, mortal!\n\n\nA flame snail's corpse bursts into flame and heat.\n\n\nYour faction standing with Servants of Aalishai has been adjusted by -3.\n\n\nYour faction standing with Servants of Esianti has been adjusted by 3.\n\n\nYour faction standing with Servants of Mearatas has been adjusted by 3.\n\n\nYour faction standing with Servants of Loruella has been adjusted by 3.\n\n\nYour task 'Slimy, Yet Sizzling' has been updated.\n\n\n\n\nA flame snail says, `You approach too close, mortal!\n\n\nA flame snail's corpse bursts into flame and heat.\n\n\nYour faction standing with Servants of Aalishai has been adjusted by -3.\n\n\nYour faction standing with Servants of Esianti has been adjusted by 3.\n\n\nYour faction standing with Servants of Mearatas has been adjusted by 3.\n\n\nYour faction standing with Servants of Loruella has been adjusted by 3.\n\n\nYour task 'Slimy, Yet Sizzling' has been updated.\n\n\n\n\nA flame snail says, `You approach too close, mortal!\n\n\nA flame snail's corpse bursts into flame and heat.\n\n\nYour faction standing with Servants of Aalishai has been adjusted by -3.\n\n\nYour faction standing with Servants of Esianti has been adjusted by 3.\n\n\nYour faction standing with Servants of Mearatas has been adjusted by 3.\n\n\nYour faction standing with Servants of Loruella has been adjusted by 3.\n\n\n\n\nUpon the last kill,\n\n\n\n\nYour task 'Slimy, Yet Sizzling' has been updated.\n\n\nYou have received a replay timer for 'Slimy, Yet Sizzling': 0d:0h:30m remaining.\n\n\nHow the efreeti consume these creatures if far beyond your understanding.\n\n\nYou receive 5 gold.\n\n\nYou receive 212 platinum .\n\n\nYou gain party experience!\n\n\n---\n\nReward(s):\n212 plat, 5 gold\nExperience\n**Submitted by:** Gidono",
    },
    {
      id = "9274",
      title = "Fire and Fury",
      exp = "25",
      exp_name = "The Burning Lands",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Horizon Blighted Sage",
      loc = nil,
      triggers = {
        "Hail, Horizon Blighted Sage",
        "interesting",
        "curious",
        "dire",
        "Prince Ralaifin",
        "_Quest and Raid_",
        "truth",
        "deal with",
      },
      items_required = {
        { name = "the wand back to Horizon Blighted Sage", count = 1 },
      },
      rewards = {
        { id = 134825, name = "Rebirth of Heaven's Truth Wand", type = "item" },
      },
      factions = {
      },
      walkthrough = "**Status: Incomplete**\n\nQuest Started By: | Description:\n**Where:**\n- Empyr: Realms of Ash [zone=1210]\n**Who:**\n- Horizon Blighted Sage [ _Quest and Raid_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Quest\n**Quest Goal:**\n- Advancement\n- Experience\n- Money\n**Quest Items:**\n- Rebirth of Heaven's Truth Wand [item=134825]\n**Related Creatures:**\n- a wildfire phoenix [npc=54093]\n- an enraged lava elemental [npc=54616]\n**Related Quests:**\n- Fight Fire [quest=9263]\n- Partisan of Empyr: Realms of Ash (10 Points) [quest=9238]\n- Soldier of Air [quest=9225]\n- Trial of Three (Trial of Smoke) [quest=9281]\n- Trial of the Ashes of Rusted Cliff's Glory (Trial of Smoke) [quest=9335]\n- Trial of the Eternal Cyclone (Trial of Smoke) [quest=9336]\n- Trial of the Speaker's Amphitheater (Trial of Smoke) [quest=9282]\n- Trial of the Wending Ways (Trial of Smoke) [quest=9337]\n**Era:** | !The Burning Lands\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Tue Nov 6 03:57:49 2018\nModified: Sun Mar 1 02:18:44 2026 | | Prerequisite Quests: Soldier of Air, Fight Fire, and anyone of the Trial of Smoke tasks.\nYou can get this quest from Horizon Blighted Sage +421, +971, +65 on the west side of the zone.\nYou say, 'Hail, Horizon Blighted Sage'\nHorizon Blighted Sage says, 'Ah. Invaders, you are most interesting beings. You do things for paltry trinkets and without the appropriate laws to govern you. Maybe you will find what I say [interesting].'\nYou say, 'interesting'\nHorizon Blighted Sage says, 'Over there, those phoenixes. They are majestic, their fire a comfort, their blaze a thing of beauty. But. Something is wrong with them. I know not what. Some do not fly with the joy of the flame, but linger to the earth, colored by their obvious despair. Perhaps one like you would be [curious] enough to investigate. I, of course, do not ask you to do this. That is not my place. My place is here. On this bridge where I must stay.'\nYou say, 'curious'\nYou have been assigned the task 'Fire and Fury'.\nYou receive Rebirth of Heaven's Truth Wand [quest=9274].\nHorizon Blighted Sage says, 'Splendid. The curiosity of you mortals is amazing. To properly reveal the truth of these phoenixes you might use this wand. As everyone knows, a phoenix will rise from the ashes of its death. If you choose to use this wand on them, it will reveal the truth. However, their binding of truth will not last long and if they are not bound to the truth on death, then their death will be only for a comparison. For the full truth you will need this comparison by watching the death of three, but you need not be wasteful and destroy more than three.'\n\n---\n\n1\\. KIll 3 Wildfire Phoenix 0/3 Empyr: Realms of Ash\n2\\. Reveal the Truth 0/1 Empyr: Realms of Ash\n> **Task Window:** Horizon Blighted Sage has suggested that the phoenixes nearby are wrong and you might be interested in investigating them. He has given you a wand that should force the truth from any being of flames that you use it on.\n>\n> Reveal the truth of the phoenixes. Use the wand to force the truth from them, then kill them if you must.\nKill a phoenix. This will randomly, can take a while spawn an enraged lava elemental. When it's low health (20%?), click the wand on it, it will land a debuff on it, then kill it. This will only need to be done once for the entire group.\n3\\. Deliver 1 Rebirth of Heaven's Truth Wand to Horizon Blighted Sage 0/1 Empyr: Realms of Ash\nGive the wand back to Horizon Blighted Sage.\nYou offered 1 Rebirth of Heaven's Truth Wand to Horizon Blighted Sage.\nYour task 'Fire and Fury' has been updated.\nYou complete the trade with Horizon Blighted Sage.\n4\\. Speak with Horizon Blighted Sage about the [truth] 0/1 Empyr: Realms of Ash\n> **Task Window:** Go to Horizon Blighted Sage, return the wand, and speak with him about the truth.\nYou say, 'Hail, Horizon Blighted Sage'\nHorizon Blighted Sage says, 'Ah. It is as I feared. The circumstances are most [dire].'\nYou say, 'dire'\nHorizon Blighted Sage says, 'Yes. The truth is that worship has power. Those elementals are worshiping [Prince Ralaifin], the Fallen Prince.'\nYou say, 'Prince Ralaifin'\nYour task 'Fire and Fury' has been updated.\nIt's worse than Horizon Blighted Sage thought! Prince Ralaifin is about to rise again. Horizon Blighted Sage most fervently suggests you gather a large force and [deal with]him forthwith!\nYou receive 5 gold .\nYou receive 212 platinum .\nYou have gained an ability point!\nYou gain experience! (0.077%)\nHorizon Blighted Sage says, 'Prince Ralaifin felt cheated by a deal made with the help of the efreeti and decided to destroy Aalishai. He got as far as the edges of Empyr before being destroyed. But the worship of the lava elementals gives him power. This is dire for Aalishai, since he is already so near. Anyone who wishes to access Aalishai in the future may wish to gather a large force of allies to ensure its survival and do [something] about the elementals. Of course if you do not have allies, one such as I will not think less of you. The truth has been revealed, but perhaps you invaders are thirsty for fire and wish to repeat what you have done for yourself. This is [curious] behavior, but satisfactory to me.'\n\n---\n\nReward(s):\n212 platinum 5 gold\nYou gain experience!\n**Submitted by:** Gidono",
    },
    {
      id = "9472",
      title = "Prince Ralaifin",
      exp = "25",
      exp_name = "The Burning Lands",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Horizon Blighted Sage",
      loc = { y = 421.0, x = 971.0, z = 65.0 },
      triggers = {
        "_Quest and Raid_",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "**Status: Incomplete**\n\nQuest Started By: | Description:\n**Where:**\n- Empyr: Realms of Ash [zone=1210]\n**Who:**\n- Horizon Blighted Sage [ _Quest and Raid_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 95\n**Maximum Level:** | 110\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Quest\n**Quest Goal:**\n- Advancement\n- Experience\n**Related Zones:**\n- Empyr: Realms of Ash: Prince Ralaifin [zone=1219]\n**Related Creatures:**\n- Ralaifin Ecclesiastic - Empyr: Realms of Ash - 1 [npc=54473]\n- Ralaifin Oblate - Empyr: Realms of Ash - 1 [npc=54436]\n- Ralaifin Sacerdot - Empyr: Realms of Ash - 1 [npc=54474]\n- Ralaifin Theologist - Empyr: Realms of Ash - 1 [npc=54552]\n- a giant lapillus lava spiderling [npc=54437]\n- a smoldering chest [npc=54435]\n**Related Quests:**\n- All In Its Place (10 Points) [quest=9374]\n- All Safe From the Fire (10 Points) [quest=9306]\n- Partisan of Empyr: Realms of Ash (10 Points) [quest=9238]\n- Prince Ralaifin - Time Trial (10 Points) [quest=9305]\n**Era:** | !The Burning Lands\nRecommended:\n**Group Size:** | Solo\n**Min. # of Players:** | 1\n**Max. # of Players:** | 6\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Mon Dec 17 21:48:38 2018\nModified: Sun Mar 1 20:46:11 2026 | | **Prerequisite Quests:** Partisan of Empyr: Realms of Ash [quest=9238]\nQuest Giver: Horizon Blighted Sage can be found at +421, +971, +65 on the west side of the zone.\nRequest Phrase: gathered\nZone In Phrase: ready\n\n---\n\n1\\. Kill 4 Ralaifin Ecclesiastic 0/4 Empyr: Realms of Ash\n**Task Window:** The Ralaifin Ecclesiastic will raise Prince Ralaifin if you don't stop them. It would benefit all if you choose to undertake the task of ending the threat. It is suggested that you end the threat in the most efficacious way possible. Death.\nKill 4 Ralaifin named mobs where they are, pulling them away from where they are they won't take damage.\nRalaifin Ecclesiastic - (Casts Volcanic Explosion: Unresistable, PBAE 200' 212k dmg, 4.5s stun.)\nRalaifin Oblate - (Casts Volcanic Explosion: Unresistable, PBAE 200' 212k dmg, 4.5s stun.)\nRalaifin Sacerdot - (Casts Prince Ralaifin's Softening: Unresistable, Directional AE 200', Decrease AC by 2700.)\nRalaifin Theologist - (Casts Prince Ralaifin's Ease: Spell Blocker but allows their detrimental spell to land on you. Also casts Prince Ralaifin's Wrath: Unresistable, Directional AE 100', 75000 mana drain.)\nSpider adds in between the named. Hit for less than 1750 damage. Kill spiders first before killing a Ralaifin.\n2\\. Open the chest 0/1 Empyr: Realms of Ash\nOpen \"a smoldering chest\" at the zone in.\n\n---\n\nReward(s):\n212 platinum 5 gold\nYou gain experience!\n96 Fettered Ifrit Coins\n**Submitted by:** Larth",
    },
  },
}
