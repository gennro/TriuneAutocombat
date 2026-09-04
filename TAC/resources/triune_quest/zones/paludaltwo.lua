-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for Paludal Depths (paludaltwo)
-- Total Quests: 5
-- ============================================================================

return {
  zone = "paludaltwo",
  zone_name = "Paludal Depths",
  quests = {
    {
      id = "11156",
      title = "The New Sheriffs in Town",
      exp = "29",
      exp_name = "Night of Shadows",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Diojb Waksom",
      loc = nil,
      triggers = {
        "Hail, Diojb Waksom",
        "Are you in need of rescuing?",
        "What can you tell me about this Bellweather?",
        "What is her scheme?",
        "How desperate are they getting?",
        "I assume these adventurers will need help?",
        "I can do that.",
        "Hail, Bellweather",
      },
      items_required = {
        { name = "him Diojb's Requisition", count = 1 },
        { name = "the commission to Bellweather 0/1 Paludal Depths", count = 1 },
        { name = "Diojb Bellweather's Assurance", count = 1 },
      },
      rewards = {
        { id = 145506, name = "Bellweather's Assurance", type = "item" },
        { id = 145273, name = "Diojb's Requisition", type = "item" },
        { id = 144974, name = "Diojb's Commission", type = "item" },
      },
      factions = {
      },
      walkthrough = "**Status: Incomplete**\n\nQuest Started By: | Description:\n**Where:**\n- Paludal Depths [zone=1307]\n**Who:**\n- Diojb Waksom [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 120\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n**Quest Items:**\n- Bellweather's Assurance [item=145506]\n- Diojb's Requisition [item=145273]\n**Related Creatures:**\n- Bellweather [npc=58430]\n- Weapons Master Wygans [ _Quests_]\n**Related Quests:**\n- Partisan of Paludal Depths (10 Points) [quest=12239]\n**Era:** | !Night of Shadows\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Sat Oct 29 12:03:25 2022\nModified: Tue Dec 5 05:21:04 2023 | | **Night of Shadows Info & Guides: Overview \\| Progression & Task List \\| Raiding \\| Visible Armor**\n\n---\n\nYou can obtain this task from Diojb Waksom in Paludal Depths. He is located at /waypoint -1317, -1141, -176 in the far eastern part of the zone. He is on the find tool CTRL F.\nYou say, 'Hail, Diojb Waksom'\nDiojb Waksom gives you a nod as you approach him. 'Hail and well met, adventurer. You are brave to remain in these caves as we have. Tell me, are you here for [adventurin]' reasons or for [rescuin]' reasons?'\nYou say, 'Are you in need of rescuing?'\nDiojb Waksom lifts and adjusts his belt, 'No, we will not be in need of rescuin'. At one time we were, but that time has since passed. I will have to warn you however, rescuin' in these parts can get you in a load of trouble with the recondite bandits that roam these caves. Our camp was well out of their way for the most part, but they have gotten desperate since they have ousted their old leader, Maricella Slithra. A new bandit has emerged as a leader and they call her \"[Bellweather].\" She has been calling the shots as of late.'\nYou say, 'What can you tell me about this Bellweather?'\nDiojb Waksom winces a bit as you mention her name. 'Aye, Bellweather.' he says with a spit of venom to his voice. 'She has been doing that thing that new leaders try to do. You know the thing.' Diojb pauses to think of the next words carefully. 'Tries too hard. Is aiming to impress and needs to prove herself to the rest of the bandits if she is to be taken seriously. Her [scheme] needs to be stopped.'\nYou say, 'What is her scheme?'\nDiojb Waksom's brow furrows. This is something that has been bothering him for a while now. 'Aye, she has laid a trap for unsuspecting adventurers over at Overslo's Grave.' Diojb looks around for a moment before continuing. 'That's why Noppta and I are stuck in here in this dank corner of the caves. The families of the other miners are looking for them. Some of the families have already received their loved one's badges, while others grow more [desperate] by the day.'\nYou say, 'How desperate are they getting?'\nDiojb Waksom says, 'The loved ones of the miners who used to work in these mines have been sending unsuspecting [adventurers] right into Bellweather's arms. She has her bandits snatch up the unknowing adventurers and then get their family to pay a ransom for their return. I have to admit though, it's a solid scam, but one that cannot continue anymore. The problem here is that the scam is working and she is making a lot of money from the ransoms.'\nYou say, 'I assume these adventurers will need help?'\nDiojb Waksom says, 'Currently, they do not have any in custody, though they are still trying. I'm hoping to prevent that. Before we can help the grieving families, we have to get them to stop sending unsuspecting adventurers to be captured. Before we can do that, we need to resolve this Bellweather situation. I need you to find her in these caves and try to convince her to end this scam. Can you do [that] for us?'\nYou say, 'I can do that.'\nYou have been assigned the task 'The New Sheriffs in Town'.\nDiojb Waksom says, 'You will have to do that adventuring thing that you do in order to find her. She will most likely be with her bandits at their camps. Good luck finding them without being killed, or captured first. When you see her, tell her I sent you and see how her reaction changes. It should be a fun moment.'\n\n---\n\nDiojb Waksom has become the de facto leader of what is left of the miners in the Paludal Depths. The miner's work ended after a cave-in took the lives of their leader. The recondite bandits who were using the caverns as a safe haven have also been under the new leadership of one name \"Bellweather.\" The bandits have come up with a scam for exploiting novice adventurers for ransom money. Djojb wants the skulduggery to stop before he and Noppta egress the mines.\n1\\. Speak with Bellweather 0/1 Paludal Depths\nBellweather is not far from the Ruins of Shadow Haven zone line at /waypoint -1647, 852, -245. She is on the find tool CTRL F.\nYou say, 'Hail, Bellweather'\nBellweather glares as you approach, 'Listen, I got a lot of problems trying to whip these bandits into something useful. It's bad enough Marciella keeps showing up at my camps, trying to convince others to join her cause. She still has some sympathizers who will listen. It is why I have to keep my distance at times, I don't know who is still on her side or not. Being seen speaking with you will cause more issues than you will understand.'\nYou say, 'Diojb sent me'\nYour task 'The New Sheriffs in Town' has been updated.\nBellweather's eyes go wide for a moment before clearing her throat. 'Well, of course that sod will have sent one of your kind here to talk with me.' She picks at the dirt under her fingernails as she continues. 'Me and the gang have been making a lot of money as of late and he wants to put the kibosh to that? I'd like to see his proposal. Tell him that I'm interested in what he has to say, but money talks louder than words. He had better make it worth our while. Tell him that I'm willing to parlay.'\n2\\. Speak with Diojb 0/1 Paludal Depths\n> **Quest Text:** Bellweather appears to have some connection with Diojb already. She has asked you to return to him to tell him that she wishes to \"parlay.\"\nYou say, 'Hail, Diojb Waksom'\nDiojb Waksom says, 'I wish there was more we could have done for the miners who lost their lives here. Personally, I don't want my final resting place to be where I did grueling work, but that's dwarves for ya. Ain't happy unless we are surrounded by dirt.'\nYou say, 'Bellweather wishes to parlay'\nYour task 'The New Sheriffs in Town' has been updated.\nDiojb Waksom frowns and nods as you tell him that Bellweather wants to parlay. 'Ok, well, she's open to listening to reason, I'll take what I can get at this moment. She must want something other than money?' He takes a moment to think before reluctantly answering himself. 'Respect? I'm sure as a new leader to the bandits she will need to prove herself without looking soft. I'm going to need some time to come up with a plan. In the meantime, go back and speak with her about what options we might have. She should have told you this sooner, but it seems she's still getting the hang of this 'leadership' thing.'\n3\\. Speak with Bellweather 0/1 Paludal Depths\n> **Quest Text:** Diojb needs more time to come up with a plan in order to help Bellweather gain favor in the eyes of the recondite bandits. He asked you to return to Bellweather and see what else she wants in lieu of the ransom money they have been collecting.\nYou say, 'Hail, Bellweather'\nYour task 'The New Sheriffs in Town' has been updated.\nBellweather looks impressed that you returned to her. 'I'm impressed you returned to me. Truth be told I thought you were already dead.' She snorts loudly and spits to her side. 'Tell you what, I have a bit of a problem with some of my gang not falling in line. If that do-gooder, Diojb wants us to change our ways, he can help me get these sods in line. I'll stop snatching up novice adventurers if he can pull that off for me.'\n4\\. Speak with Diojb 0/1 Paludal Depths\n> **Quest Text:** Return to Diojb and let him know that he was correct about Bellweather's need for a claim to leadership.\nYou say, 'Hail, Diojb Waksom'\nYou have been given: Diojb's Requisition\nYour task 'The New Sheriffs in Town' has been updated.\nDiojb Waksom claps his hands with glee and pumps his fist in the air before exclaiming, 'Yes! I was right! So I have a plan and its going to need some execution, luckily that is where you come in. First things first is that we need some object to prove her status.' He reaches into his pocket and pulls out a sealed envelope. He stares at it with a sad look in his eyes before continuing. 'Take this to the weapons master, Wygans. He can be found in Shar Vahl. He will know what it is. After that, show her you mean business by dispatching some of her bandits before delivering it.'\n_You are given: Diojb's Requisition_\n5\\. Deliver the requisition to Weapons Master Wygans 0/1 Shar Vahl, Divided\n> **Quest Text:** Deliver Diojb's requisition to the weapons master, Wygans in Shar Vahl.\n_Weapons Master Wygans is located in Shar Vahl, Divided down in the arena tunnels at /waypoint -35, -630, -212. He is on the find tool CTRL F. Give him Diojb's Requisition._\nYou offered 1 Diojb's Requisition to Weapons Master Wygans.\nYou have been given: Diojb's Comission\nYour task 'The New Sheriffs in Town' has been updated.\nWeapons Master Wygans opens the envelope with a smile and a flourish. 'Well met friend! What do we have here?' he cheerfully asks. His smile fades as he reads the note. 'Oh, this is unfortunate. Diojb had commissioned a pickax in honor of Overslo. He was having me hold it until his return, but he wants you to have it. Here adventurer, I'm not sure what you need it for, but do be careful. It's more for show than it is for work.'\nYou complete the trade with Weapons Master Wygans.\n6\\. Remind the bandits who is in charge 0/6 Paludal Depths\n> **Quest Text:** Diojb has asked you to dispatch a few of the bandits before returning to Bellweather. This will help seal the fact that he isn't afraid to have dirty work done to prove his point. This will also scare the rest of the bandits to fall in line.\n7\\. Give the commission to Bellweather 0/1 Paludal Depths\n_Give Diojb's Commission to Bellweather in Paludal Depths._\n8\\. Deliver the assurance to Diojb 0/1 Paludal Depths\n_Give Diojb Bellweather's Assurance._\n\n---\n\nReward(s):\n141pp 6g 6s 7cp at Level 120\n**Submitted by:** Gidono\n- Diojb's Commission [item=144974]",
    },
    {
      id = "11175",
      title = "Aberrantly, This is a Big Deal",
      exp = "29",
      exp_name = "Night of Shadows",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Scout Aliid",
      loc = nil,
      triggers = {
        "Hail, Scout Aliid",
        "creatures",
        "combat",
        "fiends",
        "_Quests_",
        "underbulks",
        "shriekers",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "**Status: Incomplete**\n\nQuest Started By: | Description:\n**Where:**\n- Paludal Depths [zone=1307]\n**Who:**\n- Scout Aliid [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 120\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n- Money\n**Related Creatures:**\n- a patog flarg fiend [npc=58403]\n- a toughened flarg fiend [npc=58426]\n**Related Quests:**\n- Mercenary of Paludal Depths (10 Points) [quest=12238]\n**Era:** | !Night of Shadows\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Sun Nov 20 17:23:13 2022\nModified: Tue Dec 5 05:21:04 2023 | | **Night of Shadows Info & Guides: Overview \\| Progression & Task List \\| Raiding \\| Visible Armor**\n\n---\n\nYou can obtain this task from Scout Aliid [npc=58436] in Paludal Depths. You can find Scout Aliid at /waypoint +624,+13,+212. He is on the Find tool as well (Ctrl+F).\nYou say, 'Hail, Scout Aliid'\nScout Aliid looks at the armor you are wearing before speaking, 'You are either brave or foolish to enter these caverns wearing those garments. These caves, as you have undoubtedly noticed, have been home to these creatures for a long time. As followers of Sahteb Mahlni, we believe it is our duty to understand what drives every living creature to flourish, even in places such as this. The cycle of life and death requires a force to keep the cycle turning.' He bows his head in reverence before continuing. 'One of the tasks we have given ourselves is to document how these [creatures] live, die, and survive.'\nYou say, 'creatures'\nScout Aliid says, 'Sahteb Mahlni teaches us the importance of finding a force that drives you. With people such as you or I, this driving force can be in the form of legacy, spoils of conquest, or even simply for a better future. However, these creatures run on pure instinct, something else drives them to continue their existence. Something primal that we have to understand. There is a small problem with that. While we, as explorers, are equipped for traversing caves like this, many of us are not skilled in [combat], such as yourself.'\nYou say, 'combat'\nScout Aliid says, 'Indeed, as you can tell we are trying to find a way to commune with these creatures without destroying them. Unfortunately, it seems that Ehayae has decided to bless these caverns with an abundance of life, where Drinal has decided to slack on their end of the deal. In order for us to continue our research, we will ask you to help clear out some of the more aggressive creatures here in these caves. Some of them have been infected with a strange fungal growth that has appeared when the caverns below shook. We could use your help removing the infected [underbulks], [shriekers], or [fiends]. Which would you prefer to help us with?'\nYou say, 'fiends'\nYou have been assigned the task 'Aberrantly, This is a Big Deal'.\nScout Aliid says, 'Excellent. These fiends are found all over the caves. Clear them out so that we can continue our work.'\n\n---\n\nScout Aliid of the Guardians of Shar Vahl is visiting the explorer's camp wants to understand the creatures within the Paludal Depths. He wishes to note how they have changed over the years. Unfortunately, the Reishen have infested the cave and has caused the creatures who dwell in the cave to become rabid. They must be cleared out in order for the explorers to continue their work unhindered.\n1\\. Flush out the fiends 0/15 Paludal Depths\n_Kill creatures with fiend in their name._\n\n---\n\nReward(s):\n141pp 6g 6s 7cp at Level 120\n**Submitted by:** Gidono",
    },
    {
      id = "11176",
      title = "No Room for Mushrooms",
      exp = "29",
      exp_name = "Night of Shadows",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Scout Aliid",
      loc = nil,
      triggers = {
        "Hail, Scout Aliid",
        "creatures",
        "combat",
        "shriekers",
        "_Quests_",
        "underbulks",
        "fiends",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "**Status: Incomplete**\n\nQuest Started By: | Description:\n**Where:**\n- Paludal Depths [zone=1307]\n**Who:**\n- Scout Aliid [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 120\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n- Money\n**Related Creatures:**\n- a mature sensate reishi [npc=58400]\n**Related Quests:**\n- Mercenary of Paludal Depths (10 Points) [quest=12238]\n**Era:** | !Night of Shadows\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Sun Nov 20 17:42:56 2022\nModified: Tue Dec 5 05:21:04 2023 | | **Night of Shadows Info & Guides: Overview \\| Progression & Task List \\| Raiding \\| Visible Armor**\n\n---\n\nYou can obtain this task from Scout Aliid [npc=58436] in Darklight Caverns. You can find Scout Aliid at /waypoint 624, 13, 212. He is on the find tool as well CTRL F.\nYou say, 'Hail, Scout Aliid'\nScout Aliid looks at the armor you are wearing before speaking, 'You are either brave or foolish to enter these caverns wearing those garments. These caves, as you have undoubtedly noticed, have been home to these creatures for a long time. As followers of Sahteb Mahlni, we believe it is our duty to understand what drives every living creature to flourish, even in places such as this. The cycle of life and death requires a force to keep the cycle turning.' He bows his head in reverence before continuing. 'One of the tasks we have given ourselves is to document how these [creatures] live, die, and survive.'\nYou say, 'creatures'\nScout Aliid says, 'Sahteb Mahlni teaches us the importance of finding a force that drives you. With people such as you or I, this driving force can be in the form of legacy, spoils of conquest, or even simply for a better future. However, these creatures run on pure instinct, something else drives them to continue their existence. Something primal that we have to understand. There is a small problem with that. While we, as explorers, are equipped for traversing caves like this, many of us are not skilled in [combat], such as yourself.'\nYou say, 'combat'\nScout Aliid says, 'Indeed, as you can tell we are trying to find a way to commune with these creatures without destroying them. Unfortunately, it seems that Ehayae has decided to bless these caverns with an abundance of life, where Drinal has decided to slack on their end of the deal. In order for us to continue our research, we will ask you to help clear out some of the more aggressive creatures here in these caves. Some of them have been infected with a strange fungal growth that has appeared when the caverns below shook. We could use your help removing the infected [underbulks], [shriekers], or [fiends]. Which would you prefer to help us with?'\nYou say, 'shriekers'\nYou have been assigned the task 'No Room for Mushrooms'.\nScout Aliid says, 'Nasty little buggers already, but adding the extra aggression from being infected by that fungus makes them intolerable. Normally we can handle them on their own. Many of them are in the early stages of the infestation. Just to be safe, cull them all.'\n\n---\n\nScout Aliid of the Guardians of Shar Vahl is visiting the explorer's camp wants to understand the creatures within the Paludal Depths. He wishes to note how they have changed over the years. Unfortunately, the Reishen have infested the cave and has caused the creatures who dwell in the cave to become rabid. They must be cleared out in order for the explorers to continue their work unhindered.\n1\\. Remove Reishen Shriekers 0/14 Paludal Depths\n\n---\n\nReward(s):\n141pp 6g 6s 7cp at Level 120\n**Submitted by:** Gidono",
    },
    {
      id = "11177",
      title = "Ophiocoryceps ate my Neighbors",
      exp = "29",
      exp_name = "Night of Shadows",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Scout Aliid",
      loc = nil,
      triggers = {
        "Hail, Scout Aliid",
        "creatures",
        "combat",
        "underbulks",
        "_Quests_",
        "shriekers",
        "fiends",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "**Status: Incomplete**\n\nQuest Started By: | Description:\n**Where:**\n- Paludal Depths [zone=1307]\n**Who:**\n- Scout Aliid [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 120\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n- Money\n**Related Creatures:**\n- a grim tunneler [npc=58398]\n- a sediment delver [npc=58422]\n**Era:** | !Night of Shadows\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Sun Nov 20 17:46:19 2022\nModified: Tue Dec 5 05:21:04 2023 | | **Night of Shadows Info & Guides: Overview \\| Progression & Task List \\| Raiding \\| Visible Armor**\n\n---\n\nYou can obtain this task from Scout Aliid [npc=58436] in Darklight Caverns. You can find Scout Aliid at /waypoint 624, 13, 212. He is on the find tool as well CTRL F.\nYou say, 'Hail, Scout Aliid'\nScout Aliid looks at the armor you are wearing before speaking, 'You are either brave or foolish to enter these caverns wearing those garments. These caves, as you have undoubtedly noticed, have been home to these creatures for a long time. As followers of Sahteb Mahlni, we believe it is our duty to understand what drives every living creature to flourish, even in places such as this. The cycle of life and death requires a force to keep the cycle turning.' He bows his head in reverence before continuing. 'One of the tasks we have given ourselves is to document how these [creatures] live, die, and survive.'\nYou say, 'creatures'\nScout Aliid says, 'Sahteb Mahlni teaches us the importance of finding a force that drives you. With people such as you or I, this driving force can be in the form of legacy, spoils of conquest, or even simply for a better future. However, these creatures run on pure instinct, something else drives them to continue their existence. Something primal that we have to understand. There is a small problem with that. While we, as explorers, are equipped for traversing caves like this, many of us are not skilled in [combat], such as yourself.'\nYou say, 'combat'\nScout Aliid says, 'Indeed, as you can tell we are trying to find a way to commune with these creatures without destroying them. Unfortunately, it seems that Ehayae has decided to bless these caverns with an abundance of life, where Drinal has decided to slack on their end of the deal. In order for us to continue our research, we will ask you to help clear out some of the more aggressive creatures here in these caves. Some of them have been infected with a strange fungal growth that has appeared when the caverns below shook. We could use your help removing the infected [underbulks], [shriekers], or [fiends]. Which would you prefer to help us with?'\nYou say, 'underbulks'\nYou have been assigned the task 'Ophiocordyceps ate my Neighbors'.\nScout Aliid says, 'Their cold, dead eyes stare through you now. There is nothing left of these creature's minds at this point. It will be a blessing to see them removed.'\n\n---\n\nScout Aliid of the Guardians of Shar Vahl is visiting the explorer's camp wants to understand the creatures within the Paludal Depths. He wishes to note how they have changed over the years. Unfortunately, the Reishen have infested the cave and has caused the creatures who dwell in the cave to become rabid. They must be cleared out in order for the explorers to continue their work unhindered.\n1\\. Undermine the underbulks 0/13 Paludal Depths\nKill creatures like a grim tunneler [npc=58398] and a sedimen delver [npc=58422].\n\n---\n\nReward(s):\n?\n**Submitted by:** Gidono",
    },
    {
      id = "12483",
      title = "Big Claim Hunter",
      exp = "29",
      exp_name = "Night of Shadows",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Trent Dapplesworth III",
      loc = nil,
      triggers = {
        "Hail, Trent Dapplesworth III",
        "Oh I love a good hunt.",
        "I",
        "What kind of problem?",
        "_Quests_",
        "_Oresco Hunters_",
        "hunt",
        "Reishicyben",
      },
      items_required = {
      },
      rewards = {
        { id = 145279, name = "Head of the Reishicyben", type = "item" },
        { id = 145277, name = "Reishicyben Sample", type = "item" },
        { id = 145278, name = "Reishicyben Stool Softener", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Paludal Depths [zone=1307]\n**Who:**\n- Trent Dapplesworth III [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 120\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n- Experience\n- Money\n**Quest Items:**\n- Head of the Reishicyben [item=145279]\n- Reishicyben Sample [item=145277]\n- Reishicyben Stool Softener [item=145278]\n**Related Zones:**\n- Shadeweaver's Tangle [zone=1309]\n- Shar Vahl, Divided [zone=1310]\n**Related Creatures:**\n- Colwell Emtray - NoS [ _Oresco Hunters_]\n- The Neverending Reishicyben [npc=58439]\n**Related Quests:**\n- Partisan of Paludal Depths (10 Points) [quest=12239]\n**Era:** | !Night of Shadows\nRecommended:\n**Group Size:** | Solo\n**Min. # of Players:** | 1\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Tue Dec 6 19:48:44 2022\nModified: Tue Dec 5 05:21:04 2023 | | **Night of Shadows Info & Guides: Overview \\| Progression & Task List \\| Raiding \\| Visible Armor**\n\n---\n\nYou can obtain this task from Trent Dapplesworth III [npc=58392] in Shadeweaver's Tangle. He is located at /waypoint 3469, -61, -301. He is on the find tool CTRL F.\nYou say, 'Hail, Trent Dapplesworth III'\nTrent Dapplesworth III shocks you with how abrupt and spirited his greeting is. 'Well HOW-DEE! You look like the type of adventurer who loves themselves a good [hunt]. Aren'tchya?'\nYou say, 'Oh I love a good hunt.'\nTrent Dapplesworth III points at you with both hands, his index fingers extended outward while his thumbs are pointing upward. 'Ha-cha! I knew it! You got that look in your eye, that warrior's gaze, that certain special something that separates the apex predators from the rest of the chaff. How about you and I go on a little hunt? Have you heard of the \"[Reishicyben]\"?'\nYou say, 'I've heard of the Reishicyben in passing'\nTrent Dapplesworth III jumps and swings his fist in the air in celebration. 'Hot-DANG do we got a live one here! Whoo-wee! Did you know that it has made its home within the Paludal Depths? I want that thing's head above my hearth! But there is a pretty big [problem] with this plan.'\nYou say, 'What kind of problem?'\nYou have been assigned the task 'Big Claim Hunter'.\nTrent Dapplesworth III bends his knees and addresses you with open palms. He is trying to convey seriousness, but his demeanor is far too grandiose to take him seriously. 'Right! Ok! So, first things first. You gotta find the beast. Yes, you! I'm the idea guy here and I need your very capable boots on the ground. Head into the caverns and see if you can locate the beast. Whatever you do, do NOT engage it. Trying to subdue this beast without the proper tools will only end in yet another adventurer not returning to continue the hunt. You gotta be like, the tenth person I've sent in there that hasn't come back. Who knows? Maybe you will run into them on the way. If they aren't already dead, that is. Report back once you find it.'\n\n---\n\n1\\. Find the Reishicyben 0/1 Paludal Depths\n2\\. Return to Trent 0/1 Shadeweaver's Tangle\n3\\. Speak with Colwell Emtray 0/1 Shar Vahl, Divided\n4\\. Collect Reishicyben samples from creatures near the beast 0/6 Paludal Depths\n5\\. Deliver the samples to Colwell 0/6 Shar Vahl, Divided\n6\\. Defeat the Reishicyben 0/1 Paludal Depths\n7\\. Collect the Reishicyben's Head 0/1 Paludal Depths\n8\\. Deliver the tincture to Colwell 0/1 Shar Vahl, Divided\n9\\. Deliver the Reishicyben's head to Trent 0/1 Shadeweaver's Tangle\n\n---\n\nReward(s):\n141pp 6g 6s 7cp\nExperience",
    },
  },
}
