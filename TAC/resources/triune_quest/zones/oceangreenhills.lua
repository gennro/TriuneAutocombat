-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for Oceangreen Hills (oceangreenhills)
-- Total Quests: 1
-- ============================================================================

return {
  zone = "oceangreenhills",
  zone_name = "Oceangreen Hills",
  quests = {
    {
      id = "4669",
      title = "Summary Execution",
      exp = "15",
      exp_name = "Seeds of Destruction",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Bracka Darkpaw",
      loc = nil,
      triggers = {
        "Hail, Bracka Darkpaw",
        "Home?",
        "Monsters?",
        "I",
        "home",
        "monsters",
        "hunt",
      },
      items_required = {
      },
      rewards = {
        { id = 76893, name = "Chronobine", type = "item" },
        { id = 77574, name = "Crest Right Upper Field Plate", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Oceangreen Hills [zone=611]\n**Who:**\n- Bracka Darkpaw [ _Quest 65+_]\nRating:\n0/1**_\\*__\\*__\\*__\\*__\\*_**\n(From 1 rating)\nInformation:\n**Level:** | 70\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Experience\n- Faction\n- Loot\n**Factions Raised:**\n- Cirtan, Bayle's Herald +34\n**Factions Lowered:**\n**Related Zones:**\n- Old Blackburrow [zone=614]\n**Era:** | !Seeds of Destruction\nRecommended:\n**Group Size:** | Solo\n**Min. # of Players:** | 1\n**Max. # of Players:** | 1\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Thu Oct 30 16:32:11 2008\nModified: Tue Dec 5 05:21:04 2023 | | _Bracka Darkpaw is located at the Darkpaw camp in Oceangreen Hills (far southwestern corner of the zone)._\nYou say, 'Hail, Bracka Darkpaw'\nBracka Darkpaw says 'Bark! I am strongest gnoll in Darkpaw clan! Stronger even than Raxtor! Him smarter, though. Yip! Bracka fight hard to defend Darkpaw [home], but the Blackburrow beasties too many.'\nYou say, 'Home?'\nBracka Darkpaw growls sadly. 'Burrow to the northeast was our home until nasty Blackburrow gnolls and their [monsters] kicked us out. Bracka smashed some of them, though! They not so tough with head bashed in, Bracka always say.'\nYou say, 'Monsters?'\nBracka Darkpaw says 'Bark! Blackburrow gnolls have some gnoll-shape monsters with them. They look like gnolls but also not like gnolls, yip! They are twisted, evil! The evil make them strong, stronger even than Bracka! Will you [hunt] these gnoll-monsters for Bracka? Me want revenge and Darkpaw clan will be grateful!'\nYou say, 'I'll hunt them'\nYou have been assigned the task 'Summary Execution'.\nBracka Darkpaw growls appreciatively. 'Bracka thank you, adventurer!'\n\n---\n\nDestroy 3 of the dangerous Wrext Mal elite 0/3 (Blackburrow)\n_These gnolls are found deeper within Blackburrow and are a little stronger than their regular counterparts (hit for ~2,200 and vary between single-target rampage, AE rampage, and flurry)._\nDestroy 10 of the twisted Blackburrow gnolls 0/10 (Blackburrow)\n_Most gnolls count towards this step (whether \"enraged\" or not). Some do not - the difference is unknown._\nReport back to Bracka 0/1 (Oceangreen Hills)\nYou say, 'Hail, Bracka Darkpaw'\nWhile it seems that there's certainly more where those came from, you have struck a decisive blow against the Wrext Mal gnarls. Bracka also told you how to unlock the doors to Blackburrow.\nYour faction standing with Cirtan, Bayle's Herald got better.\n_Reward:_\nCrest Right Upper Field Plate\n45 Chronobines\nExperience\nFaction\n- Chronobine [item=76893]\n- Crest Right Upper Field Plate [item=77574]",
    },
  },
}
