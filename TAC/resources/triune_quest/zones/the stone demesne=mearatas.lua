-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for Mearatas: The Stone Demesne (the stone demesne=mearatas)
-- Total Quests: 7
-- ============================================================================

return {
  zone = "the stone demesne=mearatas",
  zone_name = "Mearatas: The Stone Demesne",
  quests = {
    {
      id = "9243",
      title = "Mercenary of Mearatas: The Stone Demesne (10 Points)",
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
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Mearatas: The Stone Demesne [zone=1212]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | No\n**Can Be Shrouded?:** | No\n**Quest Type:** | Achievement\n**Quest Goal:**\n- Advancement\n**Related Quests:**\n- Champion of The Burning Lands (30 Points) [quest=9255]\n- Free the Wardens [quest=9459]\n- Lost Missives [quest=9460]\n- Thin out the Mephits [quest=9458]\n**Era:** | !The Burning Lands\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Wed Oct 31 01:07:49 2018\nModified: Tue Dec 5 05:21:04 2023 | | This achievement is gained upon completing the following quests in Mearatas: The Stone\nEmli Widgetton - Thin out the Mephits\nEmli Widgetton - Free the Wardens\nEmli Widgetton - Lost Missives\nReward(s):\nNone\n**Submitted by:** Gidono",
    },
    {
      id = "9244",
      title = "Partisan of Mearatas: The Stone Demesne (10 Points)",
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
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Mearatas: The Stone Demesne [zone=1212]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | No\n**Can Be Shrouded?:** | No\n**Quest Type:** | Achievement\n**Quest Goal:**\n- Advancement\n**Related Quests:**\n- Champion of The Burning Lands (30 Points) [quest=9255]\n- Earthen Dirge [quest=9454]\n- Mold Seeker [quest=9465]\n- Slippery Slope [quest=9461]\n**Era:** | !The Burning Lands\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Wed Oct 31 01:10:38 2018\nModified: Tue Dec 5 05:21:04 2023 | | This achievement is gained upon completing the following quests in Partisan of Mearatas: The Stone Demesne\nObsidian Sundering Master in Esianti - Earthen Dirge\nObsidian Sundering Master in Esianti - Mold Seeker\nFlexing Devout Purpose - Slippery Slope\nReward(s):\nNone\n**Submitted by:** Gidono",
    },
    {
      id = "9458",
      title = "Thin out the Mephits",
      exp = "25",
      exp_name = "The Burning Lands",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Emli Widgetton",
      loc = { y = 298.0, x = 60.0, z = 3.0 },
      triggers = {
        "Hail, Emli Widgetton",
        "mischief",
        "mephits",
        "nasty",
        "Hail, Emli",
        "_Quests_",
        "wardens",
        "envoys",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Mearatas: The Stone Demesne [zone=1212]\n**Who:**\n- Emli Widgetton [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n**Success Lockout Timer**: 00:30:00\n**Related Creatures:**\n- a gust mephit [npc=54348]\n- a jopal scholar [npc=54345]\n- a triloun guardian - Mearatas [npc=54334]\n- a vekerchiki warrior - Mearatas [npc=54329]\n**Era:** | !The Burning Lands\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Wed Dec 5 22:18:18 2018\nModified: Tue Dec 5 05:21:04 2023 | | **Prerequisite Quests:** Soldier of Air, Fight Fire, any one Trial of Smoke, Prisoner's Dilemma, Palace of Embers, Brass Palace, Key to the Kingdom, Contract of War, All Hail the King, Royal Visits, Tyrant of Fire, Enter Mearatas, and Serving Another Master.\nYou get this task from Emil Widgetton in Meratas at +298, +60, +3 not far from the center of the zone to the southwest. She is on the find tool.\nYou say, 'Hail, Emli Widgetton'\nEmli Widgetton says, 'Greetings \\_\\_\\_\\_\\_\\_\\_\\_, I came to Mearatas to be a diplomat for the mortal races, but I would love to know more about the jann and how they work when under stress. You know what they say, 'You don't really know someone unless you see them lose their cool'. Since I have arrived, the janns tensions seem to be cooling off, so to say. I think it's about time we cause a little [mischief] shall we?'\nYou say, 'mischief'\nEmli Widgetton says, 'What kind of mischief you ask? Well, not only am I glad you asked, but already have a few ideas in mind for what we can do. Let us see here, as I understand, there are [wardens] that roam the halls, as well as [envoys] and filthy little [mephits].'\nYou say, 'mephits'\nEmli Widgetton says, 'It seems that no matter where we end up, we can never be rid of these [nasty] little creatures. Please do the realm a favor and thin out a few of them from this plane of existence.'\nYou say, 'nasty'\nYou have been assigned the task 'Thin out the Mephits'.\nEmli Widgetton says, 'Great, I can't wait to see less of those little monsters here.'\n\n---\n\n1\\. Dispatch Mephits 0/6 Mearatas: The Stone Demesne\n> **Task Window:** The mephiit's foul existence needs to be culled. They are too... icky to continue living. There's really no other reason to get rid of them other than the fact that they are a nuisance.\nKill any mephits found in Mearatas.\n2\\. Return to Emli 0/1 Mearatas: The Stone Demesne\nYou say, 'Hail, Emli'\nYour task 'Thin out the Mephits' has been updated.\nYou have received a replay timer for 'Thin out the Mephits': 0d:0h:30m remaining.\nYou are not quite sure if your actions towards the mephits today were worth it.\nYou receive 5 gold .\nYou receive 212 platinum .\n\n---\n\nReward(s):\n212 platinum 5 gold\n**Submitted by:** Gidono\n- Platinum",
    },
    {
      id = "9459",
      title = "Free the Wardens",
      exp = "25",
      exp_name = "The Burning Lands",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Emli Widgetton",
      loc = { y = 298.0, x = 60.0, z = 3.0 },
      triggers = {
        "Hail, Emli Widgetton",
        "mischief",
        "wardens",
        "servitude",
        "_Quests_",
        "envoys",
        "mephits",
      },
      items_required = {
        { name = "life to the suits of armor", count = 1 },
      },
      rewards = {
      },
      factions = {
        { name = "Servants of Mearatas", change = -3 },
        { name = "Servants of Aalishai", change = -3 },
      },
      walkthrough = "**Status: Incomplete**\n\nQuest Started By: | Description:\n**Where:**\n- Mearatas: The Stone Demesne [zone=1212]\n**Who:**\n- Emli Widgetton [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Quest\n**Quest Goal:**\n- Advancement\n**Related Quests:**\n- All Hail the King [quest=9267]\n- Brass Palace [quest=9445]\n- Contract of War [quest=9446]\n- Enter Mearatas [quest=9444]\n- Fight Fire [quest=9263]\n- Key to the Kingdom [quest=9264]\n- Palace of Embers [quest=9433]\n- Prisoner's Dilemma [quest=9265]\n- Royal Visits [quest=9448]\n- Serving Another Master [quest=9453]\n- Soldier of Air [quest=9225]\n- Trial of Three (Trial of Smoke) [quest=9281]\n- Trial of the Ashes of Rusted Cliff's Glory (Trial of Smoke) [quest=9335]\n- Trial of the Eternal Cyclone (Trial of Smoke) [quest=9336]\n- Trial of the Speaker's Amphitheater (Trial of Smoke) [quest=9282]\n- Trial of the Wending Ways (Trial of Smoke) [quest=9337]\n- Tyrant of Fire [quest=9463]\n**Era:** | !The Burning Lands\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Wed Dec 5 22:34:29 2018\nModified: Tue Dec 5 05:21:04 2023 | | **Prerequisite Quests:** Soldier of Air, Fight Fire, any one Trial of Smoke, Prisoner's Dilemma, Palace of Embers, Brass Palace, Key to the Kingdom, Contract of War, All Hail the King, Royal Visits, Tyrant of Fire, Enter Mearatas, and Serving Another Master.\nYou get this task from Emil Widgetton in Meratas at +298, +60, +3 not far from the center of the zone to the southwest. She is on the find tool.\nYou say, 'Hail, Emli Widgetton'\nEmli Widgetton says, 'Greetings \\_\\_\\_\\_\\_\\_\\_\\_, I came to Mearatas to be a diplomat for the mortal races, but I would love to know more about the jann and how they work when under stress. You know what they say, 'You don't really know someone unless you see them lose their cool'. Since I have arrived, the janns tensions seem to be cooling off, so to say. I think it's about time we cause a little [mischief] shall we?'\nYou say, 'mischief'\nEmli Widgetton says, 'What kind of mischief you ask? Well, not only am I glad you asked, but already have a few ideas in mind for what we can do. Let us see here, as I understand, there are [wardens] that roam the halls, as well as [envoys] and filthy little [mephits].'\nYou say, 'wardens'\nEmli Widgetton says, 'It is said that within each of the jann's wardens that roam the halls, there are elementals trapped in order to give life to the suits of armor. Why don't we go ahead and release some of them from their [servitude].'\nYou say, 'servitude'\nYou have been assigned the task 'Free the Wardens'.\nEmli Widgetton says, 'Excellent! With the wardens free, there will be fewer guards roaming the halls, which will increase tensions within the jann.'\n\n---\n\n1\\. Destroy the jann's wardens to free the elementals 0/6 Mearatas: The Stone Demense\n**Task Window:** The wardens roaming these halls have been said to have been created by forging the metal in the armors with elementals through the means of rituals. However, as part of the process, the elemental's free will is torn from them, leaving them mindless husks that obey only the jann. Help free the elementals trapped inside the armors, and with less guards patrolling, the tensions will surely increase.\nYour task 'Free the Warden's has been updated.\nAn animated warden's corpse says, 'I have... Failed... Mearatas...'\nYour faction standing with Servants of Mearatas has been adjusted by -3.\nYour faction standing with Servants of Esianti could not possibly get any better.\nYour faction standing with Servants of Aalishai has been adjusted by -3.\nYour faction standing with Servants of Loruella could not possibly get any better.\n2\\. Return to Emli\nYou severely doubt that Emli is correct in her assumption of the wardens being enslaved.\nYou gained experience!\nYou receive 5 gold.\nYou receive 212 platnium.\n\n---\n\nReward(s):\nYou gained experience!\nYou receive 5 gold.\nYou receive 212 platnium.\n**Submitted by:** Gidono",
    },
    {
      id = "9460",
      title = "Lost Missives",
      exp = "25",
      exp_name = "The Burning Lands",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Emli Widgetton",
      loc = { y = 298.0, x = 60.0, z = 3.0 },
      triggers = {
        "Hail, Emli Widgetton",
        "mischief",
        "envoys",
        "messengers",
        "Hail, Emli",
        "_Quests_",
        "wardens",
        "mephits",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Mearatas: The Stone Demesne [zone=1212]\n**Who:**\n- Emli Widgetton [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n**Success Lockout Timer**: 00:30:00\n**Related Creatures:**\n- a flameling envoy [npc=54346]\n- a gale envoy [npc=54323]\n- a granite envoy [npc=54354]\n- an aqua envoy [npc=54338]\n**Era:** | !The Burning Lands\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Wed Dec 5 22:48:23 2018\nModified: Tue Dec 5 05:21:04 2023 | | **Prerequisite Quests:** Soldier of Air, Fight Fire, any one Trial of Smoke, Prisoner's Dilemma, Palace of Embers, Brass Palace, Key to the Kingdom, Contract of War, All Hail the King, Royal Visits, Tyrant of Fire, Enter Mearatas, and Serving Another Master.\nYou get this task from Emil Widgetton in Meratas at +298, +60, +3 not far from the center of the zone to the southwest. She is on the find tool.\nYou say, 'Hail, Emli Widgetton'\nEmli Widgetton says, 'Greetings \\_\\_\\_\\_\\_\\_\\_\\_, I came to Mearatas to be a diplomat for the mortal races, but I would love to know more about the jann and how they work when under stress. You know what they say, 'You don't really know someone unless you see them lose their cool'. Since I have arrived, the janns tensions seem to be cooling off, so to say. I think it's about time we cause a little [mischief] shall we?'\nYou say, 'mischief'\nEmli Widgetton says, 'What kind of mischief you ask? Well, not only am I glad you asked, but already have a few ideas in mind for what we can do. Let us see here, as I understand, there are [wardens] that roam the halls, as well as [envoys] and filthy little [mephits].'\nYou say, 'envoys'\nEmli Widgetton says, 'The jann use envoys to discuss events and politics between the factions. Let's say we disrupt some of their communications by killing a few of their [messengers].'\nYou say, 'messengers'\nYou have been assigned the task 'Lost Missives'.\nEmli Widgetton says, 'Wonderful! The envoys are a key tool in communications between the jann. Less envoys means more chances for the jann's plans to fall through.'\n\n---\n\n1\\. Kill Envoys 0/6 Mearatas: The Stone Demesne\n> **Task Window:** The jann use envoys to pass messages back and forth between each of the factions in order to obfuscate their inner workings. Clear out some of them envoys in order to help create more chaos amongst the jann. Without these lines of communication, the shady deals will fall apart, and the factions will lay blame on one and other.\nKill any envoy found in Mearatas : a flameling envoy, a gale envoy, a granite envoy, an aqua envoy.\n2\\. Return to Emli 0/6 Mearatas: The Stone Demesne\nYou say, 'Hail, Emli'\nYour task 'Lost Missives' has been updated.\nYou have received a replay timer for 'Lost Missives': 0d:0h:30m remaining.\nYou hope that your actions today will help keep the jann's powers balanced.\nYou receive 5 gold .\nYou receive 212 platinum .\n\n---\n\nReward(s):\n212 platinum 5 gold\n**Submitted by:** Gidono\n- Platinum",
    },
    {
      id = "9461",
      title = "Slippery Slope",
      exp = "25",
      exp_name = "The Burning Lands",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Flexing Devout Purpose",
      loc = { y = 777.0, x = -1.0, z = 14.0 },
      triggers = {
        "Hail, Flexing Devout Purpose",
        "clues",
        "_Quests_",
        "_Quests_",
      },
      items_required = {
        { name = "the Damp Missive to Flexing Devout Purpose", count = 1 },
        { name = "the Intriguing Missive to Emli Widgetton", count = 1 },
        { name = "her the missive", count = 1 },
        { name = "BEFORE killing so they all get a Soggy Journal", count = 1 },
      },
      rewards = {
        { id = 135797, name = "Cryptic Damp Missive", type = "item" },
        { id = 135794, name = "Damp Missive", type = "item" },
        { id = 135795, name = "Intriguing Damp Missive", type = "item" },
        { id = 135798, name = "Soggy Journal", type = "item" },
        { id = 135796, name = "Translated Damp Missive", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Mearatas: The Stone Demesne [zone=1212]\n**Who:**\n- Flexing Devout Purpose [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n- Experience\n- Money\n**Quest Items:**\n- Cryptic Damp Missive [item=135797]\n- Damp Missive [item=135794]\n- Intriguing Damp Missive [item=135795]\n- Soggy Journal [item=135798]\n- Translated Damp Missive [item=135796]\n**Related Creatures:**\n- Emli Widgetton [ _Quests_]\n- Unrepentant Bronze Temper [npc=54344]\n- an aqua envoy [npc=54338]\n**Era:** | !The Burning Lands\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Wed Dec 5 22:52:04 2018\nModified: Sun Aug 17 06:48:11 2025 | | **Prerequisite Quests:** Soldier of Air, Fight Fire, any one Trial of Smoke, Prisoner's Dilemma, Palace of Embers, Brass Palace, Key to the Kingdom, Contract of War, All Hail the King, Royal Visits, Tyrant of Fire, Enter Mearatas, and Serving Another Master.\nThis task can be obtained from Flexing Devout Purpose in Mearatas at /loc +777, -1, +14 in the very northern hallway of the zone. He is on the find tool.\nYou say, 'Hail, Flexing Devout Purpose'\nFlexing Devout Purpose says, 'Go away mortal-I-do-not-know-or-ever-have-met-before! Or I will report you to the guards! 'Flexing Devout Purpose lowers his voice' Actually, if you happen to find any more [clues] please bring them to me.'\nYou say, 'clues'\nYou have been assigned the task 'Slippery Slope'.\nFlexing Devout Purpose says, 'Excellent! Bring whatever you find back to me.'\n\n---\n\n1\\. Convince' aqua envoys to give up any information they may have about the ondine's schemes 0/1 Mearatas: The Stone Demesne\n> **Task Window:** You found Flexing Devout Purpose on the north side of Mearatas. He is willing to overlook the fact that you should not be there, but only if you help him uncover a plot that he believes is happening. He insists that the ondine in Mearatas are planning some trickery, but cannot get close to sources he needs to confirm his suspicions. He has asked you investigate for him.\nKill 'an aqua envoy' until one drops a Damp Missive. Loot one.\n2\\. Deliver the Damp Missive to Flexing Devout Purpose to confirm his suspicions 0/1 Mearatas: The Stone Demesne\nGive the Damp Missive to Flexing Devout Purpose, and receive Intriguing Damp Missive.\nYou have been given: Intriguing Damp Missive [item=135795]\nYour task 'Slippery Slope' has been updated.\nFlexing Devout Purpose says, 'This is what you found? This is nothing, just a list of supplies needed for Loruella, requested by the Djinn. Wait, what do we have here \\_\\_\\_\\_\\_, there is something odd about this missive, something isn`t right here... Interesting, there appears to be another layer to this note. Perhaps one of my more recently acquired acquaintances could shed some light on this. There is a newcomer to Mearatas whom I recall asking about an odd lens she found while visiting the ondines. I saw the miniscule mortal hiding around within their area. She may be able to assist more with decoding the message. Just follow the cackling, she seems like one who enjoys drama.'\n3\\. Locate Emli Widgetton and give her the Intriguing Damp Missive 0/1 Mearatas: The Stone Demesne\nGive the Intriguing Missive to Emli Widgetton, and receive Translated Damp Missive.\nYou have been given: Translated Damp Missive [item=135796]\nYour task 'Slippery Slope' has been updated.\nEmli Widgetton looks absolutely elated to see you approach her. 'Interest! Intrigue! Scandal! Now this is the kind of ...dirt... I'm here for! It is true that I found a small lens when I visited the Ondines in Loruella. I knew better than to return it, so I did what anybody else would do, held onto it for safe keeping! Let's see here \\_\\_\\_\\_\\_...' Emli looks at the missive with the lens. 'It says here to meet someone named Unrepentant Bronze Temper in a place 'where flames kiss flesh'. I see a map also on here with a few X marks on it.' Emli Scribbles on the missive. 'Here, I drew what I'm seeing with the lens. Bring this back to the duende, and maybe he will be able to use that for his investigation. As for the lens, I think I'm going to keep it for a bit longer, it has proven useful so far.'\n4\\. Bring the Translated Damp Missive back to Flexing Devour Purpose 0/1 Mearatas: The Stone Demesne\nGive the Translated Damp Missive to Flexing Devout Purpose, and receive Cryptic Damp Missive.\nYou have been given: Cryptic Damp Missive [item=135797]\nYour task 'Slippery Slope' has been updated.\nFlexing Devout Purpose says, 'Emli is really a terrible diplomat, but she still serves her purpose to us in other ways. So this is what she found? This ties in well with the information that I have been able to find on my own. Unrepentant Bronze Temper has been employing envoys to slip through cracks found in Mearatas in order to sow discord amongst the other factions. Whether it be stealing valuable information or planting evidence, she wishes to cause more bickering amongst the other jann so she can solidify power for herself. Meet up with her 'where flames kiss flesh', and give her the missive, she will have to answer for her crimes against the jann.'\n5\\. Confront Unrepentant Bronze Temper with evidence from the Cryptic Damp Missive and get her to confess 0/1 Mearatas: The Stone Demesne\nGive the Cryptic Damp Missive to Unrepentant Bronze Temper.\nUnrepentant Bronze Temper says, 'Where did you get that? It matters not, I will just have to kill you.'\nUnrepentant Bronze Temper says, 'I regret your intrusion and imminent destruction.'\nUnrepentant Bronze Temper attacks, kill her. She drops a Soggy Journal [item=135798]. Each group member should turn in BEFORE killing so they all get a Soggy Journal.\n6\\. Find evidence of Unrepentant Bronze Temper's scheme 0/1 Mearatas: The Stone Demesne\nLoot a Soggy Journal from Unrepentant Bronze Temper's corpse.\n7\\. Take the Soggy Journal to Flexing Devout Purpose 0/1 Mearatas: The Stone Demesne\nGive the Soggy Journal to Flexing Devout Purpose in order to complete the task. Trying to turn in the looted Soggy Journal to Flexing Devout Purpose without the kill update above in step 5 results in an \"i am not interested in this\" response.\nFlexing Devout Purpose says, 'Keep searching \\_\\_\\_\\_\\_! I know the deeper we dig, the more dirt we will be able to find.'\nYour task 'Slippery Slope' has been updated.\nYou receive 7 copper .\nYou receive 6 silver .\nYou receive 6 gold .\nYou receive 141 platinum .\nYou gain experience!\nFlexing Devout Purpose says, 'I have to apologize to you \\_\\_\\_\\_\\_, I knew she would lash out like she did but I was afraid you would be too frightened to continue. However, you finding this Soggy Journal will certainly prove useful in making sure Unrepentant Bronze Temper gets what's coming to her. It cannot be known that I asked for the help of an outside in this matter. I will not report you to the guards, but I will also not vouch for you in Mearatas. I'll bring this to the attention of our leaders and be sure she will get the punishment deserving of her treachery. Thank you again \\_\\_\\_\\_\\_, now go away before we are seen together.'\n\n---\n\nReward(s):\n141 platinum 6 gold 6 silver 7 copper\nYou gain experience!\n**Submitted by:** Gidono\n- Platinum, Experience",
    },
    {
      id = "9462",
      title = "Relic Raider",
      exp = "25",
      exp_name = "The Burning Lands",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Key of the Relic Keeper",
      loc = nil,
      triggers = {
      },
      items_required = {
      },
      rewards = {
        { id = 134790, name = "Duende Female Mold", type = "item" },
        { id = 134031, name = "Empyrean Cloak of the Stalwart", type = "item" },
        { id = 134305, name = "Glowing Spellbound Lamp", type = "item" },
        { id = 134304, name = "Greater Spellbound Lamp", type = "item" },
        { id = 134302, name = "Lesser Spellbound Lamp", type = "item" },
        { id = 134303, name = "Median Spellbound Lamp", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Mearatas: The Stone Demesne [zone=1212]\n**Who:**\n- Key of the Relic Keeper [npc=54396]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 95\n**Maximum Level:** | 130\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n- Experience\n- Money\n**Quest Items:**\n- Duende Female Mold [item=134790]\n**Related Zones:**\n- Mearatas: The Stone Demesne: Relic Raider [zone=1226]\n**Related Creatures:**\n- Iron Heart [npc=54581]\n- a boulder [npc=54582]\n- a jewel encrusted chest [npc=54583]\n- a vekerchiki soldier [npc=54579]\n- an elemental deep earth [npc=54580]\n- relic guardian [npc=54578]\n**Related Quests:**\n- Earthen Dirge [quest=9454]\n- Keep on Rollin` (10 Points) [quest=9328]\n- Legend of The Burning Lands (Group) (10 Points) [quest=9347]\n- Mold Seeker [quest=9465]\n- Perfect Timing (10 Points) [quest=9327]\n- Rock Steady (10 Points) [quest=9326]\n**Era:** | !The Burning Lands\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Wed Dec 5 22:55:48 2018\nModified: Sat Feb 3 16:44:16 2024 | | Prerequisite quests: Achievement: Legend of the Burning Lands (Group), Earthen Dirge, and Mold Seeker.\nAt the end of the Mold Seeker quest, you get Key of the Relic Keeper [item=134609] that is clicked from within Mearatas to both obtain the mission and then port the GROUP into the instance. So only one group member actually needs the key, but a group member without their own key has no way to get themselves into the instance. This is significant if anyone dies.\nThe instance itself is a small, bowl-shaped room with several cubbies along the outer perimeter, including one where you zone in. There are four waves of mobs you will have to deal with, however you do have time between waves to regroup so long as you aren't close enough to proximity aggro the mobs. Since the room is small, there's very little margin for error.\n\n---\n\n1\\. Defeat the relic guardians. 0/1 Mearatas: The Stone Demesne\nWave 1 has two level 114 \"relic guardian\" on the other side of the room.\nWave 2 has three mephits a vekerchiki soldier - in the center of the room. They will aggro unless you are in one of the cubbies, tightly hugging the outer wall. While they are yellow cons and seemingly have fewer HP than the golems. They do see-invis but do not see through rogue SOS. They can be mezzed, snared, and rooted.\nWave 3 is an earth elemental - elemental deep earth. There are emotes to be aware of:\n**An elemental deep earth shouts, '\\_\\_\\_\\_\\_ offends! You are too high above the earth!**'\nNote: this emote may also affect pets, not only players.\nAt this point you are go to the center of the room, which is lower than the outer ring area where you should be engaging the mob. If you miss this emote, you will get:\nAn elemental deep earth shouts, '\\_\\_\\_\\_\\_ remains too high above the earth!'\nIf you fight the elemental in the center you get a different message:\nAn elemental deep earth shouts, '\\_\\_\\_\\_\\_ offends! You are too low upon the earth!'\nAn elemental deep earth shouts, '\\_\\_\\_\\_\\_ remains too low to the earth!'\nJust need to run up on ledge instead.\nAn elemental deep earth begins to cast a spell. Crushing Stone (Decrease Hitpoints by 156156, single target);\nThe elemental deep earth was offended and threw a rock at \\_\\_\\_\\_\\_. You have failed the Achievement: Rock Steady\nThe final mob Iron Heart - casts Specific Gravity (Decrease Hitpoints by 126866 per tick, Decrease Movement by 90%) and has one emote:\n**The boulder begins to roll, seeking \\_\\_\\_\\_\\_.** A boulder will start chasing the named player, which simply needs to be avoided. Note that the boulder does not despawn until the quest item is looted from the chest.\nThe final mob spawns directly at the zone-in, so if you are fighting there you will not have time to regroup before engaging. One way or another you should get out of that initial cubby. Best bet is probably to do it during the first wave, or immediately afterwards, although you'll have to be quick. Aim for the cubby that is roughly at 3 o'clock from where you zone-in; that should be far enough from all the other spawns so that you don't aggro mobs until you are ready.\n2\\. Steal the duende female mold. 0/1 Mearatas: The Stone Demesne\n3\\. Open the chest. 0/1 Mearatas: The Stone Demesne\n\"a jewel encrusted chest\" spawns. Open it and loot \"Duende Female Mold\" to complete the mission.\nYou have completed achievement: Hero of Mearatas: The Stone Demesne.\nOptional achievements that may be completed during this mission :\n\\- Perfect Timing: Defeat the Relic Guardians at the same time and Vekerchiki Soldiers at the same time.\n\\- Rock Steady : Do not allow anyone in your party to offend the elemental deep earth and get hit with a rock.\n\\- Keep on Rolling: Do not get hit by the rolling boulder (player specific).\n\n---\n\nReward(s):\n212 platinum 5 gold\nYou gain experience!\n96 Fettered Ifrit Coins\n\n---\n\nRelic Raider - Perfect Timing - YouTube\nTap to unmute\nRelic Raider - Perfect Timing jimmyw404\njimmyw404219 subscribers\nWatch on\n**Submitted by:** Larth\n- Empyrean Cloak of the Stalwart [item=134031]\n- Glowing Spellbound Lamp [item=134305]\n- Greater Spellbound Lamp [item=134304]\n- Lesser Spellbound Lamp [item=134302]\n- Median Spellbound Lamp [item=134303]\n- Minor Spellbound Lamp [item=134301]\n- Mortal Celestial Brawny Spark [item=133896]\n- Mortal Celestial Deft Spark [item=133897]\n- Mortal Celestial Equilibrium Spark [item=133895]\n- Mortal Celestial Incisive Spark [item=133900]\n- Mortal Celestial Nimble Spark [item=133898]\n- Mortal Celestial Shrewd Spark [item=133901]\n- Mortal Celestial Vigorous Spark [item=133899]",
    },
  },
}
