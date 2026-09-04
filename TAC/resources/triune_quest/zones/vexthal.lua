-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for Vex Thal (vexthal)
-- Total Quests: 7
-- ============================================================================

return {
  zone = "vexthal",
  zone_name = "Vex Thal",
  quests = {
    {
      id = "10498",
      title = "Sincerely, Cissela",
      exp = "28",
      exp_name = "Terror of Luclin",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Cissela Regnar",
      loc = { y = -571.0, x = 64.0, z = 1.0 },
      triggers = {
        "Hail, Cissela Regnar",
        "I will.",
        "I",
        "Is there something else I can help you with?",
        "_Quests_",
        "Will",
        "paper and ink",
        "something",
      },
      items_required = {
        { name = "the ink to Cissela 0/1 Vex Thal", count = 1 },
        { name = "the parchment to Cissela 0/1 Vex Thal", count = 1 },
      },
      rewards = {
        { id = 142901, name = "Scroll of Akhevan Parchment", type = "item" },
        { id = 142976, name = "Vial of Akhevan Ink", type = "item" },
      },
      factions = {
      },
      walkthrough = "**Status: Incomplete**\n\nQuest Started By: | Description:\n**Where:**\n- Vex Thal [ToL]\n**Who:**\n- Cissela Regnar [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 115\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n- Experience\n- Money\n**Quest Items:**\n- Scroll of Akhevan Parchment [item=142901]\n- Vial of Akhevan Ink [item=142976]\n**Era:** | !Terror of Luclin\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Sun Oct 17 15:35:42 2021\nModified: Tue Dec 5 05:21:04 2023 | | **Terror of Luclin Info & Guides: Overview \\| Progression & Task List \\| Raiding \\| Visible Armor**\n\n---\n\nYou can obtain this quest from Cissela Regnar in Vex Thal at -571, 64, 1 in the southeast room on the first floor. Cissela Regnar is on the Find tool (CTRL F).\nYou say, 'Hail, Cissela Regnar'\nCissela Regnar's body lies battered and bloodied on the floor. You'd think she was dead if it weren't for faint, shuddering breaths that cause her chest to rise and fall. Her tired eyes meet yours. '[Will] you hear me out?'\nYou say, 'I will.'\nCissela Regnar speaks to you in a raspy voice. 'I might not make it. I'm a mercenary through and through--' she pauses to let out a wheezing cough. 'So I knew it was bound to happen.' She closes her eyes for a moment. 'I'm afraid talking in this state is quite difficult. Could you find me some [paper and ink]? Surely the Akheva have some on them.'\nYou say, 'I'll find some paper and ink.'\nYou have been assigned the task 'Sincerely, Cissela'.\nCissela Regnar coughs more violently. Flecks of blood scatter across the floor. 'Thank you.'\n\n---\n\n- 1\\. Kill Akheva to find ink 0/1 Vex Thal\n> **Quest Text:** Cissela Regnar is grievously injured from her and Samuel's fight against the Akheva and shades of Vex Thal. She believes that she doesn't have much time left left and has one request some ink and paper. It is difficult for her to speak through the injuries she's sustained, but she is hopeful that she can leave a tangible message for Samuel and the mercenary company.\n>\n> Defat Akheva and check their bodies for ink or parchment that Cissela could use.\nLoot 1 Vial of Akhevan Ink [item=142976] dropping off Akheva.\n- 2\\. Kill Akheva to find paper 0/1 Vex Thal\nLoot 1 Scroll of Akhevan Parchment [item=142901] dropping off Akheva.\n- 3\\. Give the ink to Cissela 0/1 Vex Thal\n- 4\\. Give the parchment to Cissela 0/1 Vex Thal\n- 5\\. Listen to what Cissela has to say about her letter 0/1 Vex Thal\n> **Quest Text:** Speak with Cissela to see if there's anything else she needs.\nYou say, 'Hail, Cissela Regnar'\nCissela Regnar writes slowly, her hand shaking with effort. She slides the written note to Samuel. 'Here,' she rasps. 'Consider it a 'thank you' for all that you've done for me.' Cissela coughs violently. 'Something to remember me by. I have so much to say but not the breath to say it.' Samuel accepts the letter with a deep sadness in his eyes. Cissela meets your gaze. It looks like she has [something] to say.\nSamuel opens the letter and reads quietly. A faint smile dances across his face. He tucks the note into his armor.\nYou say, 'Is there something else I can help you with?'\nCissela Regnar says, 'There's nothing more that can be done for me, but I'm grateful for your help. I'm able to leave behind a sincere letter for Samuel and the other mercenaries, telling them how much they mean to me. Not everyone gets the same privilege.'\n\n---\n\nReward(s):\n354 platinum 1 gold 6 silver 7 copper\nYou gain experience!\n**Submitted by:** Gidono",
    },
    {
      id = "10499",
      title = "Thanks for the Memories",
      exp = "28",
      exp_name = "Terror of Luclin",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Samuel Jezra",
      loc = { y = -572.0, x = 71.0, z = 1.0 },
      triggers = {
        "Hail, Samuel Jezra",
        "I am not on their side.",
        "Who is Cissela?",
        "What is your mission?",
        "Why didn",
        "So you came here to stop the ritual?",
        "Then we could change the future again.",
        "I",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "**Status: Incomplete**\n\nQuest Started By: | Description:\n**Where:**\n- Vex Thal [ToL]\n**Who:**\n- Samuel Jezra [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 115\n**Maximum Level:** | 130\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n- Experience\n- Money\n**Era:** | !Terror of Luclin\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Sun Oct 17 16:36:25 2021\nModified: Thu Jun 4 02:15:35 2026 | | **Terror of Luclin Info & Guides: Overview \\| Progression & Task List \\| Raiding \\| Visible Armor**\n\n---\n\nYou can obtain this quest by speaking with Samuel Jezra which can be found at -572, 71, 1 in Vex Thal in the southeast room on the first floor in the southern wing of rooms as you come into the complex of Vex Thal. Samuel is on the find tool (CTRL F).\nYou say, 'Hail, Samuel Jezra'\nSamuel Jezra's eyes are wary and tired. 'If yer here to kill us, get it over with. We won't fight back -- we can't. But considerin' you have a corporeal body and only two arms, I take it that you aren't on the [side] of the Akehva.'\nYou say, 'I am not on their side.'\nSamuel Jezra looks solemnly at the mess of corpses lying around the room. 'That's a small relief. [Cissela] and I have accepted death, but I won't complain about havin' a living, breathing body for a while longer. I only wish I could have finished our [mission] and given our companions' deaths purpose.'\nYou say, 'Who is Cissela?'\nSamuel Jezra looks to his right. 'Cissela is my friend lying next to me. I don't know how much longer she's got, but she's clingin' on to life. Always a stubborn one.' Samuel laughs bitterly. 'I met her when she was still young. I don't know if she was lost or abandoned, but we gave her a home in our mercenary company. I've never met a Vah Shir who relies on a bow, but she's a deadeye.' He pauses, a pained expression on his face. 'She's like a daughter to me, and I've let her down.... Just hold on, Cissela. There might be hope for you yet.'\nYou say, 'What is your mission?'\nSamuel Jezra says, 'S'pose there's no use in keeping it a secret. We are a small mercenary group. Maybe 'were' is more appropriate now. Sometimes our soldiers didn't [return home]; it isn't uncommon in our line of work, but it started happening more frequently. I treat every one of these folks as if they were my own flesh and blood, so I decided to investigate.'\nYou say, 'Why didn't they return home?'\nSamuel Jezra says, 'The Akheva nabbed 'em. Saw it with my own eyes. They took my man alive, so I wondered if all my soldiers might be still livin' somewhere. I started listening to local rumors, and it seemed like mine was not an isolated incident. Someone finally mentioned that the Akheva seemed to be planning a [ritual].'\nYou say, 'So you came here to stop the ritual?'\nSamuel Jezra says, 'That was the plan. We arrived and found one of those four-armed freaks staring into a bowl of water. Killed 'em, but we looked into the bowl and saw... well, ourselves. In the past. They were spyin' on us and knew our plan all along, so we devised a new strategy. Seems like they don't adapt well to the [future] changing. We snuck past the guards when we could, killed when we needed. They got the best of us in this room, but we managed to kill all guards who saw us.'\nYou say, 'Then we could change the future again.'\nSamuel Jezra says, 'I won't say 'no' if yer offering to [help]. Doesn't take a genius to see that our time here is ticking. We need to figure out what this Akhevan ritual is, then hopefully we can learn how to stop it. These scrying bowls seem to show snapshots of time: the recent past, present, and even future. I noticed 'em in all these side rooms, plus the rooms in the left wing of the building. We might be able to learn what the Akheva are plotting if we can see what they're spying on.'\nYou say, 'I'll help.'\nSamuel Jezra says, 'Look into the scrying bowls and report back what you see. I'm sure some of it will be helpful.'\nYou have been assigned the task 'Thanks for the Memories'.\n\n---\n\n1\\. Learn more about the kidnappings 0/1 Vex Thal\n> **Quest Text:** Samuel Jezra came to Vex Thal on a mission. For weeks, men and women from his mercenary company were going missing with worrying frequency. As their leader, Samuel took it upon himself to figure out what was happening. He learned that his fighters were being kidnapped by the Akheva and heard rumors that they were planning a nefarious ritual. Unfortunately, Samuel has been backed into a corner and mos of his companions have been killed. He has asked you to investigate the scrying bowls around Vex Thal and see what the Akheva are spying on. Samuel mentioned that the scrying bowls are in these side hallways --- there are six scrying rooms in the west wing, and you can surmise that there are another six in the east. If you can discover some key information, perhaps the two of you can piece together what the Akheva are plotting. There might still be hope to save Samuel's mercenaries, or stop the mysterious ritual.\n>\n> Before Samuel can plan his next course of action, he need to know what the Akhevan ritual is. Where do they take their prisoners? What do they do to them? And is it possible they they --- and his mercenaries --- are still somewhere? You may be able to learn more by looking into the scrying bowls around Vex Thal and finding the pertinent information.\nClick on the scrying bowl in a room at /waypoint +215, -109, +1.89. Beware of the see invis mob inside!\nThe water looks crystal clear. You see a woman clad in armor accompanied by a young man in a robe. They're walking down a dark path surrounded by woods. From your vantage point, you can see Akheva striding silently behind them through the trees. The woman motions for the man to stop and looks around with apprehension. The Akheva dart out from the woods and quickly overpower the two. Before you can process what happened, you see the Akheva pulling the duos' unconcious bodies into the woods.\n2\\. Learn where the prisoners are taken 0/1 Vex Thal\nClick on the scrying bowl in a room at /waypoint -400, -109, +1.89. Beware of the see invis mob inside!\n3\\. Learn what the Akhevan ritual entails 0/1 Vex Thal\nClick on the scrying bowl in a room at /waypoint +564, +212, +1.89. Beware of the see invis mob inside!\nThe water calms as you look into it. You see a Vah Shir man tied up and kneeling in front of an Akheva. They appear to be indoors, but you aren't sure where. The Akheva places a dagger to the man's throat and makes quick, clean slash. The body falls to the floor, blood pooling around it. Next to it, a pile of robes begins to move, then float. It takes the same form as the shades you've seen guarding Vex Thal, as if it were brought into existence by the life force of the Vah Shir sacrificed next to it.\n4\\. Learn the prisoner's fates 0/1 Vex Thal\nClick on the scrying bowl in a room at /waypoint +395, +222, +1.89. Beware of the see invis mob inside!\nThe water is placid. You find yourself looking at the moat around Vex Thal. Corpses are lined up along the bank; you see women and men of all races and ages. Three Akheva speak to each other in their mysterious language, then begin pushing the bodies one-by-one into the moat. You watch the bodies float, face down, further into the water. Farther down, you see bodies partially submerged as they begin to sink to the bottom.\n5\\. Return to Samuel with your new information 0/1 Vex Thal\n\n---\n\nReward(s):\n354 platinum 1 gold 6 silver 7 copper\nYou gain experience!\n**Submitted by:** Gidono",
    },
    {
      id = "10626",
      title = "First Vision of the Unknown",
      exp = "28",
      exp_name = "Terror of Luclin",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Akhevan Scrying Bowl",
      loc = { y = 278.0, x = -1237.0, z = -38.0 },
      triggers = {
        "_Quests_",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Vex Thal [ToL]\n**Who:**\n- Akhevan Scrying Bowl [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 115\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n- Money\n**Era:** | !Terror of Luclin\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Sun Nov 21 16:56:34 2021\nModified: Tue Dec 5 05:21:04 2023 | | **Terror of Luclin Info & Guides: Overview \\| Progression & Task List \\| Raiding \\| Visible Armor**\n\n---\n\nYou can get this task from Akhevan Scrying Bowl from the entrance of Vex Thal. You can find the bowl at 278, -1237, -38.\nThere is no dialogue, just click on the bowl to get the task.\n\n---\n\n1\\. Slay the stonegrabber guards 0/4 Vex Thal\n> **Quest Text:** Upon peering closely at the basin, the water's surface begins to ripple. Hazy images flicker before you: laughing people, serene mountains, violent battlefields. These are but snippets of the world that the Akheva peer into in the name of their goddess.\n>\n> The images slow and focus. A grizzled man stands at the head of a table, a crudely drawn map unfurled before him. He is surrounded by warriors, swords strapped to their backs. Pointing near the edge of the map, his voice rings in your mind: 'We must get rid of the guards first. The stone golems they've animated.'\n\n---\n\nReward(s):\nMoney for your level\n**Submitted by:** Gidono",
    },
    {
      id = "10627",
      title = "Second Vision of the Unknown",
      exp = "28",
      exp_name = "Terror of Luclin",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Akhevan Scrying Bowl",
      loc = { y = 278.0, x = -1237.0, z = -38.0 },
      triggers = {
        "_Quests_",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Vex Thal [ToL]\n**Who:**\n- Akhevan Scrying Bowl [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 115\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n- Money\n**Era:** | !Terror of Luclin\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Sun Nov 21 17:04:39 2021\nModified: Tue Dec 5 05:21:04 2023 | | **Terror of Luclin Info & Guides: Overview \\| Progression & Task List \\| Raiding \\| Visible Armor**\n\n---\n\nYou can get this task from Akhevan Scrying Bowl from the entrance of Vex Thal. You can find the bowl at 278, -1237, -38.\nThere is no dialogue, just click on the bowl to get the task.\n\n---\n\n1\\. Rid Vex Thal of shades 0/8 Vex Thal\n> **Quest Text:** More disconcerting images dance across the water's surface, stitched together with no clear meaning. Robed figures bowing in front of a statue, a fisherman in a boat, a splendid feast. The water becomes a hazy rainbow of colors and shapes. The small waves hit the edges of the basin, threatening to spill over.\n>\n> The murkiness clears and once again you see the group of warriors surrounding the table. A Vah Shir woman leans forward and, with a claw, circles a spot further down the map. 'The shades tend to congregate here. We have to thin their numbers to make any sort of impact. What do you think, Samuel?' The man at the head of the table looks pensive.\n>\n> 'It will be dangerous.... but necessary. We have to stop the Akhevan ritual at all costs.'\n\n---\n\nReward(s):\nMoney for your level\n**Submitted by:** Gidono",
    },
    {
      id = "10628",
      title = "Third Vision of the Unknown",
      exp = "28",
      exp_name = "Terror of Luclin",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Akhevan Scrying Bowl",
      loc = { y = 278.0, x = -1237.0, z = -38.0 },
      triggers = {
        "_Quests_",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Vex Thal [ToL]\n**Who:**\n- Akhevan Scrying Bowl [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 115\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n- Money\n**Related Creatures:**\n- Qua Thall - ToL [npc=57028]\n- Visus Zethon [npc=57042]\n- Zov Thall - ToL [npc=57048]\n**Era:** | !Terror of Luclin\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Sun Nov 21 17:20:21 2021\nModified: Tue Dec 5 05:21:04 2023 | | **Terror of Luclin Info & Guides: Overview \\| Progression & Task List \\| Raiding \\| Visible Armor**\n\n---\n\nYou can get this task from Akhevan Scrying Bowl from the entrance of Vex Thal. You can find the bowl at 278, -1237, -38.\nThere is no dialogue, just click on the bowl to get the task.\n\n---\n\n1\\. Eliminate Akhevan spell-casters 0/5 Vex Thal\n> **Quest Text:** The colors in the water become more vibrant. The sounds of the vision ring more clearly in your mind. You realize you're gripping tightly to both edges of the scrying bowl, but you don't recall moving to this position. You find yourself utterly fascinated by the churning waters, unable to move away. Is this the kinf of powerful magic Luclin trusts her subjects with?\n>\n> Your attention snaps back to the images before you when you hear the voice of the older warrior, Samuel. He is rolling the map up and addressing his companions. 'We take it room by room. Quickly, quietly, efficiently. If you run into any red-robed Akheva, kill'em. They're the magic users, and we can't have them making our prescense obvious.' The man unsheathes his sword and holds it straight in front of him. The warriors follow suit, creating a ring of blades around their circular table. The metal glints under the light. 'We need to stop this ritual at all costs The Akheva has made it clear that they intend to wipe out every other living thing on Luclin. We can't let them become more powerful. We might die trying, but we will try.' Loud cheers ring through your mind as the party lifts their blades up with terror.\n>\n> As the warriors march out of the room, you feel as though you've been released from your captivation with the scrying bowl. Your head spins. The water in the basin swirls lazily, no more images in its waves. What did you just watch? Who were those warriors? Whatever they were trying to stop, you have a feeling that they're on the same side as you.\n<\\-\\-\\- Killing Related Creatures update this step.\n\n---\n\nReward(s):\nMoney for your level\n**Submitted by:** Gidono",
    },
    {
      id = "10692",
      title = "Even If They Weren't So Great",
      exp = "28",
      exp_name = "Terror of Luclin",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Samuel Jezra",
      loc = nil,
      triggers = {
        "Hail, Samuel Jezra",
        "_Quests_",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Vex Thal [ToL]\n**Who:**\n- Samuel Jezra [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 110\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Experience\n- Money\n**Related Creatures:**\n- Prisoner Remains [npc=57020]\n**Related Quests:**\n- Thanks for the Memories [quest=10499]\n**Era:** | !Terror of Luclin\nRecommended:\n**Group Size:** | Solo\n**Min. # of Players:** | 1\n**Max. # of Players:** | 1\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Sun Dec 12 22:51:44 2021\nModified: Tue Dec 5 05:21:04 2023 | | Prerequisite: Thanks for the Memories [quest=10499], also from Samuel Jezra\n> Thanks to the visions you observed in the scrying bowls, you and Samuel are able to deduce what the Akheva have been doing to their prisoners. Through dark magic, it appears that each prisoner sacrificed by an Akheva returns as a shade. You also saw corpses being disposed of in the moat around Vex Thal. Unfortunately, the visions were brief and left many lingering questions. Foremost to Samuel is whether or not his kidnapped mercenaries are still alive.\n- 1\\. Locate the bodies of the sacrificed prisoners 0/1 Vex Thal\n> The Akheva you saw in the scrying bowl pushed the bodies into the moat around Vex Thal. Samuel suggested swimming through it to check for corpses.\nThis updates around /waypoint 700, -100 in the water in the north part of the zone, where many Prisoner Remains are found.\n- 2\\. Examine each skeleton closely for a golden tooth 0/1 Vex Thal\n> Samuel mentioned that one pf his kidnapped men, Desmond, has a gold tooth. He suggested that no matter what state you might find the bodies in, you should be able to recognize Desmond by examining his teeth.\nThis step updates at /waypoint 878, -1, -82\n- 3\\. Return to Samuel and report you've discovered Desmond's remains 0/1 Vex Thal\nYou say, 'Hail, Samuel Jezra'\nSamuel Jezra's brow furrows. 'You found him down there?' In a matter of seconds, a mix emotions dance across his face; he looks confused, enraged, pleading, then finally settles into a cold, dispassionate stare. 'Kill them.' He locks eyes with you. 'Kill those Akhevan curs. While you're at it, the shades too. Those prisoners didn't want that existence. It's time to let their souls pass on.' His fury is palpable. 'Grant me this last wish.'\n- 4\\. Carry out Samuel's revenge by killing Akheva 0/5 Vex Thal\n- 5\\. Release prisoners' captured souls by killing shades 0/5 Vex Thal\nKill 5 akhevan and 5 shades anywhere in Vex Thal.\n- 6\\. Tell Samuel that you've finished his task 0/1 Vex Thal\nYou say, 'Hail, Samuel Jezra'\nSamuel Jezra says, 'You're back.' The fearsome, bloodthirsty look in his eyes from earlier has dimmed to a smoldering anger. 'Thank you. I know that killing a few Akheva is just a drop in the bucket compared to their full forces, but you've helped put my mind at ease. I hope the souls used to animate those shades have moved on to a better place.''\nReward(s):\n354 platinun 1 gold 6 silver 7 copper\nYoui gain experience!\n- Platinum, Experience",
    },
    {
      id = "8671",
      title = "Hunter of Vex Thal",
      exp = "03",
      exp_name = "The Shadows of Luclin",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "Achievement",
      repeatable = false,
      group_size = "Solo",
      npc = "Eom Centien",
      loc = nil,
      triggers = {
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "**Level:** 1\n**Maximum Level:** 125\n**Monster Mission:** No\n**Repeatable:** No\n**Can Be Shrouded?:** No\n**Quest Type:** Achievement\n**Group Size:** Solo\n\nThis achievement is gained upon defeating the following rare monsters in Vex Thal:\nEom Centien Xakra Dat\nEom Centien Xakra Kel\nEom Centien Xakra Set\nEom Liako Xakra Dat\nEom Liako Xakra Kel\nEom Liako Xakra Set\nEom Senshali Xakra Dat\nEom Senshali Xakra Kel\nEom Senshali Xakra Set\nEom Thall Xakra Dat\nEom Thall Xakra Kel\nEom Thall Xakra Set\nEom Va Liako Xakra Dat\nEom Va Liako Xakra Kel\nEom Va Liako Xakra Set\nEom Zethon Xakra Dat\nEom Zethon Xakra Kel\nEom Zethon Xakra Set\nSubmitted by: GidonoRewards:\n[",
    },
  },
}
