-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for Al'Kabor's Nightmare (misty)
-- Total Quests: 1
-- ============================================================================

return {
  zone = "misty",
  zone_name = "Al'Kabor's Nightmare",
  quests = {
    {
      id = "5219",
      title = "Defend What?",
      exp = "17",
      exp_name = "House of Thule",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Deputy Asler",
      loc = nil,
      triggers = {
        "Hail, Deputy Asler",
        "Defense against what?",
        "I",
        "_Quests_",
        "defense",
        "protect",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Al'Kabor's Nightmare [zone=754]\n**Who:**\n- Deputy Asler [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 90\n**Maximum Level:** | 90\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Experience\n- Faction\n**Factions Raised:**\n- Dream Delvers +?\n**Factions Lowered:**\n**Related Creatures:**\n- a Runnyeye guard [npc=36431]\n- a Runnyeye raider - Al'Kabor's Nightmare - 1 [npc=36425]\n- a Runnyeye thief [npc=36426]\n- a giant rat - Al'Kabor's Nightmare [npc=36414]\n- a klaknak beetle [npc=36412]\n**Era:** | !House of Thule\nRecommended:\n**Group Size:** | Solo\n**Min. # of Players:** | 1\n**Max. # of Players:** | 1\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Fri Nov 12 07:34:50 2010\nModified: Thu Nov 18 18:00:52 2010 | | _This is a solo kill task that begins with Deputy Asler in Al'Kabor's Nightmare. He's located on the wall right at the zone-in (just climb up the log)._\nYou say, 'Hail, Deputy Asler'\nDeputy Asler says 'Defense! Get on [defense]! We must protect what's left of the wall!'\nYou say, 'Defense against what?'\nDeputy Asler says 'There's enough encroaching on our area. We must [protect] ourselves.'\nYou say, 'I'll protect you!'\nDeputy Asler says 'Oh, please let you not be a trick of Bristlebane. Come back with your report when you've slaughtered the lot of them. I may be the only Deputy left in defense, but that's still an order!'\nYou have been assigned the task 'Defend What?'.\nDeputy Asler is the only remaining Rivervale deputy guarding the wall, and as one of the first adventurers he's seen for days, he has ordered you to protect the wall from intruders. Intruders to which direction is unknown, but there seems to be a lot enemies around nonetheless.\n\n---\n\nKill any Runnyeye fighters, raiders, or guards nearby 0/3 (Al'Kabor's Nightmare)\nKill any giant rats nearby 0/3 (Al'Kabor's Nightmare)\nKill any klaknak beetles nearby 0/4 (Al'Kabor's Nightmare)\n_NOTE: The giant rats and klaknak beetles don't summon. However, the Runnyeye goblins do._\nReport back to Deputy Asler 0/1 (Al'Kabor's Nightmare)\n_Rewards:_\nExperience\nMinor Faction with Dream Delvers",
    },
  },
}
