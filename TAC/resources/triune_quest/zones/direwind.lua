-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for Direwind Cliffs (direwind)
-- Total Quests: 2
-- ============================================================================

return {
  zone = "direwind",
  zone_name = "Direwind Cliffs",
  quests = {
    {
      id = "3900",
      title = "Ashengate Access: The Pretender",
      exp = "12",
      exp_name = "The Serpent's Spine",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Zhubis the Griffon Tamer",
      loc = { y = 960.0, x = -1045.0, z = 0.0 },
      triggers = {
        "Hail, Zhubis the Griffon Tamer",
        "What essential tasks?",
        "What information?",
        "Hail, Zhubis the Griffin Tamer",
        "challenge him",
        "essential tasks",
        "information",
      },
      items_required = {
        { name = "you that", count = 1 },
      },
      rewards = {
        { id = 55135, name = "Box of Everburning Flame", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Direwind Cliffs [zone=441]\n**Who:**\n- Zhubis the Griffon Tamer [npc=23340]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 75\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | No\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n- Experience\n**Faction Required:**\nInfiltrators and Traitors of Ashengate (Min: Kindly)\n**Factions Raised:**\n- Infiltrators and Traitors of Ashengate +250\n**Factions Lowered:**\n**Quest Items:**\n- Box of Everburning Flame [item=55135]\n**Related Zones:**\n- Vergalid Mines: Vergalid's End [zone=444]\n**Related Creatures:**\n- Nurtha Frazzlesprocket [npc=23836]\n**Related Quests:**\n- Access to Ashengate Raids [quest=4157]\n- Raid Expedition: Vergalid Mines: Vergalid's End [quest=3930]\n- Vergalid Mines: Into the Leviathan's Lair [quest=3668]\n- Zheren #1: Scouting Sunderock [quest=3646]\n- Zheren #2: Dyn`leth's Artillery [quest=3692]\n- Zheren #3: The Ashengate Orders [quest=3693]\n- Zheren #4: Dyn`Leth's Mine [quest=3697]\n**Era:** | !Serpents Spine\nRecommended:\n**Group Size:** | Solo\n**Min. # of Players:** | 1\n**Max. # of Players:** | 1\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Wed Nov 22 00:28:31 2006\nModified: Tue Dec 5 05:21:04 2023 | | _This task begins with Zhubis the Griffin Tamer at location +960, -1045 in Direwind (this is south of Gatekeeper Kor, on the other side of the valley)._\n_In order to request it, you must have at least kindly faction with \"Infiltrators and Traitors of Ashengate\". You must have completed Captain Zheren's first four tasks. And you must have completed the Into the Leviathan's Lair [quest=3668] 24-player raid task._\n_To complete this task, you will need to have both this task and the \"Vergalid's End\" raid task, as the updates you need here come from that raid instance._\nYou say, 'Hail, Zhubis the Griffon Tamer'\nZhubis the Griffon Tamer glances from side to side, to ensure no one is watching, 'You've got a lot of nerve coming here, Lanadenae. I'll give you that. There's something different about you, isn't there? It's the hatred in your eyes.. I find it quite unmistakable. You have been yearning for more than sticking it to Dyn`leth, you look as if you are ready to [challenge him] yourself. If your desire to see him fall is not yet as great as mine, I welcome you to continue aiding me in more of my menial but [essential tasks] to whittle away at the empire he has grown.'\nYou say, 'What essential tasks?'\nZhubis the Griffon Tamer nods, 'Then we are of the same mind, and this meeting is a fortuitous one. I'm not sure how you knew that I wished to speak to an outsider. I told no one. If I had it would have meant my execution. What I do understand is that I was born into a world for someone else's cause, meant to die for someone else's flawed beliefs. Though this has afforded me some interesting [information] that I could share.'\nYou say, 'What information?'\nZhubis the Griffon Tamer says 'With my inside knowledge of Dyn`leth's army and the temple, I'm sure we could wreak some havoc on the inner workings of Ashengate.'\nYou have been assigned the task 'The Pretender'.\nAfter all you have done for our cause, I think I can trust you enough to confide this information: We had one of our members leave the camp in the dead of the night, and she took an artifact of great import when she disappeared. She spirited away the Box of Everburning Flame, a divine gift from Solusek himself. We tracked Nurtha down easily enough. She's got herself a makeshift workshop deep in the Vergalid Mines. It seems she's holed herself up there for the privacy she needs to construct metal contraptions, using the box as a simple source of power for her mechanical monstrosities. My assistant Hidagaard was right; we should have known better than to trust a Gnome. The allure of tinkering was more important to her than faith in the one true god, an unforgivable blaspheme for which she will pay dearly. Yet, and I find this most embarassing to admit, she's repeatedly repelled every attempt we have made to recover the artifact, regardless of whether we use force, coercion, or subterfuge. Since coercion and subterfuge aren't our strong points, you might have more luck.\nEnter Vergalid Mines 0/1 (Sunderock Springs)\n_This updates when you enter the raid task \"Vergalid's End\"._\nSpeak to Nurtha Frazzlesprocket 0/1 (Vergalid Mines)\n_This gnome NPC is in the raid instance for \"Vergalid's End\". Hailing her updates the task. (Doing so is of no consequence - you will not trigger the event until you attack her.)_\nDefeat Nurtha Frazzlesprocket 0/1 (Vergalid Mines)\n_This is one of three raid events in the **\"Vergalid's End\"** [quest=3930] raid expedition._\nReturn to Zhubis 0/1 (Direwind Cliffs)\n_Return to Zhubis and hail him._\nYou say, 'Hail, Zhubis the Griffin Tamer'\nYour task 'The Pretender' has been updated.\nYour faction standing with Infiltrators and Traitors of Ashengate got better.\nYou gain experience!!\n_Completion of this task allows you to request the task \"A Complex Diversion\"._",
    },
    {
      id = "3911",
      title = "Ashengate Access: Severing the Strings",
      exp = "12",
      exp_name = "The Serpent's Spine",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Jenray, Envoy of Ro",
      loc = nil,
      triggers = {
        "Hail, Jenray, Envoy of Ro",
        "what gifts?",
        "superiority?",
        "gifts",
        "superiority",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Direwind Cliffs [zone=441]\n**Who:**\n- Jenray, Envoy of Ro [ _Quests 70+_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 75\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | No\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n- Experience\n**Faction Required:**\nScholars of Solusek (Min: Kindly)\n**Factions Raised:**\n- Scholars of Solusek +250\n**Factions Lowered:**\n**Related Zones:**\n- Vergalid Mines: Vergalid's End [zone=444]\n**Related Creatures:**\n- Goru Uldrock, the Reincarnate [npc=23681]\n- Vergalid [npc=22718]\n**Related Quests:**\n- Access to Ashengate Raids [quest=4157]\n- Ashengate Access: Ghosts from the Past [quest=4159]\n- Raid Expedition: Vergalid Mines: Vergalid's End [quest=3930]\n- Vergalid Mines: Into the Leviathan's Lair [quest=3668]\n- Zheren #1: Scouting Sunderock [quest=3646]\n- Zheren #2: Dyn`leth's Artillery [quest=3692]\n- Zheren #3: The Ashengate Orders [quest=3693]\n- Zheren #4: Dyn`Leth's Mine [quest=3697]\n**Era:** | !Serpents Spine\nRecommended:\n**Group Size:** | Solo\n**Min. # of Players:** | 1\n**Max. # of Players:** | 1\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Tue Nov 28 19:44:02 2006\nModified: Tue Dec 5 05:21:04 2023 | | _This task begins with Jenray, Envoy of Ro, who is found in the Direwind Cliffs in a tent just outside the lava moat to the right of the Ashengate zone._\n_In order to request it, you must have at least kindly faction with \"Scholars of Solusek\". You must have completed Captain Zheren's first four tasks. And you must have completed the Into the Leviathan's Lair [quest=3668] 24-player raid task._\n_To complete this task, you will need to have both this task and the \"Vergalid's End\" raid task, as the updates you need here come from that raid instance._\nYou say, 'Hail, Jenray, Envoy of Ro'\nJenray, Envoy of Ro peers down at your weapons with a glaring eye, 'You had best sheath those weapons before I take them from you, \\_\\_\\_\\_.'\n_If you hail again without unequipping your weapon, Jenray will attack. And don't expect assistance... who wants to ruin their Scholars of Solusek faction?_\n_After sheathing your weapons..._\nYou say, 'Hail, Jenray, Envoy of Ro'\nJenray, Envoy of Ro says 'Welcome, Troll, to our humble encampment. Warm yourselves by our flame and rejoice in the many [gifts] that Solusek Ro bestows upon his faithful.'\nYou say, 'what gifts?'\nIf still needing to complete `Into the Leviathan's Lair'..\nJenray, Envoy of Ro says 'You may have been blinded, as I once was, by the mundane powers of Norrath's pantheon. Evidence of Solusek's influence and omnipotence abound. Now consider the earth upon which you are standing. This extended mountain range exists because HE WILLS IT SO. One might pose the question to you of what other deity can claim that kind of [superiority], but you already know the answer to that, don't you, \\_\\_\\_? From the looks of things, you may want to seek out Sergeant Kazzar. Last I heard, he was leading an expedition into the Vergalid Mines.'\nYou say, 'superiority?'\nJenray, Envoy of Ro smiles, 'Ah, \\_\\_\\_\\_. You deserve to see for yourself. Allow me to show you the miracles so you will understand.'\n_You are now presented with a task selection dialog. It will contain a task from Jenray #1 to #3 and (if you meet all requirements) \"Severing the Strings\"._\nYou have been assigned the task 'Severing the Strings'.\nThere's a problem that needs to be addressed before you can make any further progress towards shutting down Dyn`Leth's plans. If Dyn`Leth were to feel threatened, his first course of action would be to pull the strings of his faithful puppet, Vergalid. Within moments, the formidable dragon would scream from the skies to protect his master. Any fight against both Dyn`Leth and his watchdog is a futile one, therefore our only logical course of action is to strike first and elmininate Vergalid. He rests deep within the mines that bear his name. That's where you must go. The mazelike caverns have made his personal lair difficult to pinpoint, sbut slave workers I have spoken to suggested that he is likely in one of two places...\nEnter the Vergalid Mines - Sunderock Springs\n_This updates when you enter the raid task \"Vergalid's End\"._\nKill Goru Uldrock, the Reincarnate - Vergalid Mines\n_This giant is found within the \"Vergalid's End\" raid instance._\nPower the life force feeding Vergalid - Vergalid Mines\n_Kill the six Stone Protectors in the shrine room._\nDestroy Vergalid - Vergalid Mines\n_Vergalid is found within the \"Vergalid's End\" raid instance._\n\n---\n\n_Upon completion of this task, you will receive a faction gain with Scholars of Solusek. You will also be able to request the task \"Ghosts of the Past\" from Jenray._\n**Submitted by:** Lias Roxx, Defiant, Zek",
    },
  },
}
