-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for Stonebrunt (stonebrunt)
-- Total Quests: 1
-- ============================================================================

return {
  zone = "stonebrunt",
  zone_name = "Stonebrunt",
  quests = {
    {
      id = "8559",
      title = "Hunter of The Stonebrunt Mountains (Original)",
      exp = "02",
      exp_name = "The Scars of Velious",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "Achievement",
      repeatable = false,
      group_size = "Solo",
      npc = "Giang Yin",
      loc = nil,
      triggers = {
        "Hail",
      },
      items_required = {
        { id = 6981, name = "Item #6981", count = 1 },
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "**Level:** 1\n**Maximum Level:** 125\n**Monster Mission:** No\n**Repeatable:** No\n**Can Be Shrouded?:** No\n**Quest Type:** Achievement\n**Group Size:** Solo\n\nThis achievement is gained upon defeating the following monsters in The Stonebrunt Mountains:\nRognarog the Infuriated\nSlyder the Ancient\nGiang Yin\nSnowbeast\nJelquar the Soulslayer\nGirgak the Bloody\nRendolr the Maimer\nArglar the Tormentor\nHurglak the DestroyerSubmitted by: GidonoRewards:\n[",
    },
  },
}
