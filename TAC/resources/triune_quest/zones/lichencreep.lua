-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for Lichen Creep (lichencreep)
-- Total Quests: 2
-- ============================================================================

return {
  zone = "lichencreep",
  zone_name = "Lichen Creep",
  quests = {
    {
      id = "5001",
      title = "Biddlebokk \\#1: The Grand Experiment",
      exp = "16",
      exp_name = "Underfoot",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Inventor Biddlebokk",
      loc = { y = -395.0, x = 915.0, z = -16.0 },
      triggers = {
        "Hail, Inventor Biddlebokk",
        "Busy?",
        "I can help",
        "It won",
        "_Quests_",
        "busy",
        "help",
        "won't be so easy",
      },
      items_required = {
      },
      rewards = {
        { id = 87058, name = "Creation Seal of Approval", type = "item" },
        { id = 87004, name = "Form F-09383-4", type = "item" },
        { id = 87001, name = "Form G-99492-T", type = "item" },
        { id = 87005, name = "Form H-99499-6", type = "item" },
        { id = 86790, name = "Mephit Tongue", type = "item" },
        { id = 86970, name = "Royal Proclamation Form of Creation", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Lichen Creep [zone=714]\n**Who:**\n- Inventor Biddlebokk [ _Quests_]\nRating:\n0/3**_\\*__\\*__\\*__\\*__\\*_**\n(Average from 3 ratings)\nInformation:\n**Level:** | 85\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Experience\n- Money\n**Quest Items:**\n- Creation Seal of Approval [item=87058]\n- Form F-09383-4 [item=87004]\n- Form G-99492-T [item=87001]\n- Form H-99499-6 [item=87005]\n- Mephit Tongue [item=86790]\n- Royal Proclamation Form of Creation [item=86970]\n**Related Zones:**\n- Kernagir, the Shining City [zone=713]\n**Related Creatures:**\n- Assistant Huanir [npc=34654]\n- Assistant Jergis [npc=34685]\n- Bookkeeper Blanch [npc=34694]\n- a lava mephit guard [npc=34897]\n- a lava mephit worker [npc=34896]\n**Related Quests:**\n- Biddlebokk #2: The Experiment Begins [quest=5002]\n- Biddlebokk #3: What Could Go Wrong? [quest=5003]\n**Era:** | !Underfoot\nRecommended:\n**Group Size:** | Solo\n**Min. # of Players:** | 1\n**Max. # of Players:** | 6\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Wed Jan 6 18:56:20 2010\nModified: Tue Dec 5 05:21:04 2023 | | _This shared task begins with Inventor Biddlebokk in Lichen Creep. He is located at -395, 915, -16._\nYou say, 'Hail, Inventor Biddlebokk'\nInventor Biddlebokk says 'Stay back! Oh...hello. Sorry about that. I'm a little jumpy, but I think I've found a safe spot for now. Oh, heavens, why did I come here? With all that's going on, why didn't I just send an assistant? What am I going to do? And I still need my forms, and...well, you can see I am very [busy]!'\nYou say, 'Busy?'\nInventor Biddlebokk says 'I have been charged by Brell himself with researching the creation of a new race of humanoid. I just don't think I can do it! Not after the failure of project X-5. I am still under investigation for 300 test subjects that are missing. Not to mention the accidental polymorphs. It wasn't my fault! Enough about that, though. I need help! Your [help]!'\nYou say, 'I can help'\nInventor Biddlebokk says 'You'll really help me? Oh, this is such good news! There is much to be done, my friend. I forgot to secure the proper research forms before I came here. You just don't go about researching how to create a new race without the proper forms. All of the forms can be obtained from the Shining City. Getting them [won't be so easy] though.'\nYou have been assigned the task 'The Grand Experiment'.\nYou say, 'It won't be so easy?'\nInventor Biddlebokk says 'Well, let's just say the clerks that take care of such papers can be \"difficult\" to work with at times. I'm sure you will do just fine though. You should talk to Secretary Kilkin first. She can be found in the Council Chamber of the Shining City. She should have the right form for you so we can start our work.'\nInventor Biddlebokk has been tasked by Brell to research the creation of a new race of humanoid. Before the experiment can start, however, you need to secure the proper paperwork from officials in the Shining City.\nYou will need to turn in the Royal Proclamation Form of Creation to Secretary Kilkin. She can be found in the Council Chamber in the Shining City.\n\n---\n\nDeliver 1 Royal Proclamation Form of Creation to Secretary Kilkin 0/1 (Kernagir, the Shining City)\n_Kilkin can be found in a building northeast of the zone-in of Kernagir. (Location: 335, 15, -45)_\nDeliver 1 Form G-99492-T to Assistant Jergis 0/1 (Kernagir, the Shining City)\n_Jergis is found northwest of the zone-in in a tower. (Location: 1345, 1130, 254)_\nDeliver 1 Form F-09383-4 to Assistant Huanir 0/1 (Kernagir, the Shining City)\n_Huanir is found southwest of the zone-in. (Location: -80, 240, -45)_\nDeliver 1 Form H-99499-6 to Bookkeper Blanch 0/1 (Kernagir, the Shining City)\n_Blanch is found at the west end of the zone. (Location: 890, 1450, 222)_\nDeliver 1 Creation Seal of Approval to Inventor Biddlebokk 0/1 (Lichen Creep)\nDeliver 10 Mephit Tongue to Inventor Biddlebokk 0/1 (Lichen Creep)\n_The mephit tongues drop from lava mephits in Lichen Creep. These are pre-lootable._\n_Rewards:_\n315 platinum\nExperience (3.3 AAs at Level 85)\n~60 Brellium Tokens\n\n---\n\n_A second task, \"The Experiment Begins\", follows this one._\n- Brellium Token [item=88944]",
    },
    {
      id = "5002",
      title = "Biddlebokk \\#2: The Experiment Begins",
      exp = "16",
      exp_name = "Underfoot",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Inventor Biddlebokk",
      loc = { y = -395.0, x = 915.0, z = -16.0 },
      triggers = {
        "Hail, Inventor Biddlebokk",
        "Bub?",
        "I will find him",
        "_Quests_",
        "busy",
        "Bub",
        "Find",
        "lichen",
      },
      items_required = {
        { name = "him a kick in his metal butt for me!'", count = 1 },
      },
      rewards = {
        { id = 86793, name = "Lava Sample", type = "item" },
        { id = 86787, name = "Lava Tube Spore", type = "item" },
        { id = 86807, name = "Partially Digested Rock", type = "item" },
        { id = 86798, name = "Research Notes", type = "item" },
        { id = 88944, name = "Brellium Token", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Lichen Creep [zone=714]\n**Who:**\n- Inventor Biddlebokk [ _Quests_]\nRating:\n0/1**_\\*__\\*__\\*__\\*__\\*_**\n(From 1 rating)\nInformation:\n**Level:** | 85\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Experience\n- Money\n**Quest Items:**\n- Lava Sample [item=86793]\n- Lava Tube Spore [item=86787]\n- Partially Digested Rock [item=86807]\n- Research Notes [item=86798]\n**Related Zones:**\n- Kernagir, the Shining City [zone=713]\n**Related Creatures:**\n- Bub [npc=34681]\n- a hungry sessiloid [npc=34919]\n- a lava golem [npc=34908]\n- a lava mephit guard [npc=34897]\n- a lava mephit worker [npc=34896]\n- a magma golem [npc=34895]\n**Related Quests:**\n- Biddlebokk #1: The Grand Experiment [quest=5001]\n- Biddlebokk #3: What Could Go Wrong? [quest=5003]\n**Era:** | !Underfoot\nRecommended:\n**Group Size:** | Solo\n**Min. # of Players:** | 1\n**Max. # of Players:** | 6\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Wed Jan 6 18:56:24 2010\nModified: Tue Dec 5 05:21:04 2023 | | _This shared task (1-6 players) begins with Inventor Biddlebokk in Lichen Creep. He is located at -395, 915, -16._\n_To request this task, you must first have completed \"The Grand Experiment\"._\nYou say, 'Hail, Inventor Biddlebokk'\nInventor Biddlebokk says 'Yes, I'm still [busy]. Do you think you could get my assistant, [Bub], to help me with my experiment?'\nYou say, 'Bub?'\nInventor Biddlebokk says 'That worthless assistant of mine is probably falling off his barstool right now, blind drunk. He was always sneaking out of my workshop in the Shining City to slip in a few drinks at the bar. I wouldn't care if he drank himself to death, but he has my research notes, and I need him to do some analysis -- you know, his job. [Find] him and get the notes!'\nYou say, 'I will find him'\nInventor Biddlebokk says 'Thanks! And give him a kick in his metal butt for me!'\nYou have been assigned the task 'The Experiment Begins'.\n\n---\n\nSpeak with Bub 0/1 (Kernagir, the Shining City)\n_Bub is found drinking in the bar in western Kernagir (same house as Bookkeeper Blanch from previous task), at 690, 1430, 213._\nDeliver 1 Research Notes to Inventor Biddlebokk 0/1 (Lichen Creep)\nInventor Biddlebokk says 'Bub has agreed to work until his contract expires? I can't ask for much more. He really does need to stop hitting the oil though. Well, it seems the experiment can continue now. In Lichen Creep, plants known as Lava Tubes grow. Every so often, the will sprout spores which contain a magical, fire-based energy. The mephits collect these spores and eat them as nourishment. Retrieve some of these spores and bring them back so I can analyze them.'\nDeliver 4 Lava Tube Spore to Inventor Biddlebokk 0/1 (Lichen Creep)\nDeliver 6 Partially Digested Rock to Inventor Biddlebokk 0/1 (Lichen Creep)\nDeliver 5 Lava Sample to Inventor Biddlebokk 0/1 (Lichen Creep)\n_Lava Tube Spores come from mephit workers and guards. Partially Digested Rocks come from hungry sessiloids. Lava Samples come from magma golems and lava golems._\n_All items are pre-lootable. Upon hand-in:_\nYour task 'The Experiment Begins' has been updated.\nVery nice work. Much better than I could have done! I am not much of an adventurer. Oops. Looks like I need one more component. I need some [lichen] samples from the cliknar in Lichen Creep. I understand if you don't want to retrieve them for me, but if you do, I would be very grateful.\n_Rewards:_\n~70 Brellium Tokens\n365 platinum, 5 gold\nExperience (~4 AAs at Level 85)\n\n---\n\n_A third task, \"What Could Go Wrong?\", follows this one._\n- Brellium Token [item=88944]",
    },
  },
}
