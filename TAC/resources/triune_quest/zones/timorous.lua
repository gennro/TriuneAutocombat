-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for Timorous (timorous)
-- Total Quests: 2
-- ============================================================================

return {
  zone = "timorous",
  zone_name = "Timorous",
  quests = {
    {
      id = "3755",
      title = "Kunark Spells: Cannibalize II, Evil Version",
      exp = "01",
      exp_name = "The Ruins of Kunark",
      min_lvl = 40,
      max_lvl = 125,
      quest_type = "Quest",
      repeatable = false,
      group_size = "Solo",
      npc = "The Great Oowomp",
      loc = { y = -8850.0, x = -6040.0, z = 0.0 },
      triggers = {
        "Hail, The Great Oowomp",
        "I want to see the dancing skeleton.",
        "Who are the McMerin clan?",
        "I will help gather components.",
        "see the dancing skeleton",
        "McMerin clan",
        "help gather components",
        "No Drop",
      },
      items_required = {
        { name = "of all the items", count = 1 },
      },
      rewards = {
        { id = 12941, name = "Item #12941", type = "item" },
      },
      factions = {
      },
      walkthrough = "**Level:** 40\n**Maximum Level:** 125\n**Monster Mission:** No\n**Repeatable:** No\n**Can Be Shrouded?:** No\n**Quest Type:** Quest\n**Group Size:** Solo\n\nYou say, 'Hail, The Great Oowomp'\nThe Great Oowomp gestures as if casting a powerful spell.  'Come forward, adventurer!  Come and [see the dancing skeleton].  I shall cast a powerful spell and bring forth this operatic, clattering jumble of bones and he shall do a fine dance for you.  From the nether regions and planes beyond, I call forth this bardic, magical, rhyming, tap-dancing hunk of undead!!  I am Oowomp the Great!!'\nYou say, 'I want to see the dancing skeleton.'\nThe Great Oowomp says 'Oh!!  You wish to see the great Oowomp perform his magic!!  I have studied with the grand mages and wise [McMerin clan] of Norrath, as my speech implies.  I can call forth the skeleton with but a twinkling of my power and five of your gold.'\nYou say, 'Who are the McMerin clan?'\nThe Great Oowomp says 'Clan McMerin were wise shamans from the North.  They allowed me to study with them.  I learned many spells while I communed with them.  From them, I sto.. I mean, I learned, the secret of McMerin's Feast.  If you want to know the secret, you could [help gather components] for future rituals.'\nYou say, 'I will help gather components.'\nThe Great Oowomp says 'Actually... Not so much help as do - ALL - of the gathering.  In the lands of Kunark are clay of Ghiosk, crushed dread diamond and powder of Yun.  A rare find would be the bones of one who touched the Bath of Obulus.  Find and return these to me and the shaman secret of McMerin's Feast is yours.'\n1. Clay of Ghiosk. Comes from Army Behemoths in the City of Mist - Called Strange Ochre Clay, and identifies as \"Clay of Ghiosk.\"\n2. Crushed Dread Diamonds. Go get a dufrenite (you can buy this at several cities). In the Dreadlands, in the area with all the wizard spires, there is a MOB called \"gem cutter skeleton\". He is inside one of the pyramids (there's an entrance on the ground), and is KOS to everyone. An Enchanter, Necro, or Bard is required to charm him so that you can hail him, and he talks about sparklies. Ask him \"what dread diamond,\" and he offers to trade a dufrenite for one. Give him a dufrenite (while he's charmed) and he gives you a \"Dread Diamond\" No Drop, and says how they are very valuable but more so in the crushed form, and that you would require high skill and a spectral pestle to crush it. The spectral pestles are found on spectral guardians in Kaesora and Trakanon's Teeth, and combining the dread diamond + spectral pestle to make Crushed Diamonds, which identifies as \"Crushed Dread Diamonds\" (trivializes at around 70 Alchemy skill, so make sure your skill is high enough - you lose the pestle, but get the diamond back). Alternately, you can find Crushed Diamonds as a ground spawn in the Timorous Deep on the Golra island at -8850, -6040.\n3. Powder of Yun. Come from Froglok Yun Shamans in Trakanon's Teeth. It is NO DROP, black and called Shaman Powder. Identifies as \"Powder of Yun.\"\n4. Bone chips from the bones of one who has touched the Bath of Obulus. These are called Greyish Bone Chips, and come from Skeleton Warlords in Karnor's Castle. People will often let you loot these from their kill. They identify as \"Obulus Bone Chips.\"\nUpon hand in of all the items.\nThe Great Oowomp begins to jump for joy. The ground trembles. 'Grand! Here is the secret of McMerin's Feast. Scribe it and you shall learn more of its power.'\nYou receive Spell: Cannibalize II.Submitted by: Sunclan, BristlebaneRewards:\n- Spell: Cannibalize II [item=8582]\n[",
    },
    {
      id = "8575",
      title = "Conqueror of Timorous Deep (10 Points)",
      exp = "01",
      exp_name = "The Ruins of Kunark",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "Achievement",
      repeatable = false,
      group_size = "Solo",
      npc = "Faydedar",
      loc = nil,
      triggers = {
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "**Level:** 1\n**Maximum Level:** 125\n**Monster Mission:** No\n**Repeatable:** No\n**Can Be Shrouded?:** No\n**Quest Type:** Achievement\n**Group Size:** Solo\n\nThis achievement is gained upon completing the following raid in Timorous Deep:\n[ ] FaydedarSubmitted by: GidonoRewards:\n[",
    },
  },
}
