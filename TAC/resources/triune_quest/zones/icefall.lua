-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for Icefall Glacier (icefall)
-- Total Quests: 2
-- ============================================================================

return {
  zone = "icefall",
  zone_name = "Icefall Glacier",
  quests = {
    {
      id = "3610",
      title = "Thinning the Pack",
      exp = "12",
      exp_name = "The Serpent's Spine",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Malgen",
      loc = nil,
      triggers = {
        "Hail, Malgen",
        "Talk good",
        "I will do that",
        "talk good",
        "do that",
      },
      items_required = {
      },
      rewards = {
        { id = 51937, name = "Direwolf Totem of Spirit", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Icefall Glacier [zone=438]\n**Who:**\n- Malgen [npc=22467]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 70\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Loot\n**Faction Required:**\nNightmoon Kobolds (Min: Dubious)\n**Related Creatures:**\n- a Coldeye wolf tender [npc=22491]\n- a dire wolf - Icefall Glacier [npc=22490]\n- an elder dire wolf [npc=22854]\n**Era:** | !Serpents Spine\nRecommended:\n**Group Size:** | Solo\n**Min. # of Players:** | 1\n**Max. # of Players:** | 1\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Tue Sep 26 02:04:13 2006\nModified: Tue Dec 5 05:21:04 2023 | | _This solo task starts in Icefall Glacier with an NPC named Malgen, who is located in the caves closest to the port in area._\nYou say, 'Hail, Malgen'\nMalgen says, 'Me say hail you. Me not [talk good] at you. but me try.'\nYou say, 'Talk good'\nMalgen says, 'Me need to talk so you do things for mer. Me need you to go kill orc wolves. You [do that]?'\nYou say, 'I will do that'\n_You have been assigned the task, Thinning the Pack._\n\n---\n\n1\\. Locate the haven of the Dire Wolf Elders\n2\\. Locate the haven of the Dire Wolves\n3\\. Kill 3 Elder Dire Wolves\n4\\. Kill 5 Dire Wolves\n5\\. Kill 2 Coldeye wolf tenders\n6\\. Speak with Malgen\nThe Dire Wolf Elders and the Dire wolves havens are both up near the\nValdeholm zone. Invised, you can run around and trigger the first 2 parts.\nThe wolves don't summon; nor do the wolf tenders. Kill them and return to\nMalgen for your reward which is a familiar that looks like a shaman pet.\n_Your task 'Thinning the Pack' has been updated._\nThe loss of these wolves will put a damper on the orcish raids. The Kobold\nlivestock should be much safer with the dismantling of the pack.\nYou gain experience!\n\n---\n\n_Rewards:_\n\\- Direwolf Totem of Spirit\nYou have successfully been granted your reward for: Thinning the Pack\n- Direwolf Totem of Spirit [item=51937]",
    },
    {
      id = "3614",
      title = "Free the Wolves",
      exp = "12",
      exp_name = "The Serpent's Spine",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Pack Leader Orgak",
      loc = nil,
      triggers = {
        "Hail, Pack Leader Orgak",
        "Wolves?",
        "Take care?",
        "I go get",
        "What meat?",
        "wolves",
        "take care",
        "go get",
      },
      items_required = {
        { name = "meat to wolf", count = 1 },
      },
      rewards = {
        { id = 52577, name = "Meat for Orgak's Wolves", type = "item" },
        { id = 51938, name = "Direwolf Totem of Battle\n- Direwolf Totem of Battle", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Icefall Glacier [zone=438]\n**Who:**\n- Pack Leader Orgak [npc=22468]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 70\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Loot\n**Faction Required:**\nColdeye Clan (Min: Dubious)\n**Quest Items:**\n- Meat for Orgak's Wolves [item=52577]\n**Era:** | !Serpents Spine\nRecommended:\n**Group Size:** | Solo\n**Min. # of Players:** | 1\n**Max. # of Players:** | 1\n**Appropriate Classes:**\n- Bard\n- Beastlord\n- Berserker\n- Monk\n- Paladin\n- Ranger\n- Rogue\n- Shadowknight\n- Warrior\n**Appropriate Races:**\n- All\nEntered: Tue Sep 26 05:38:36 2006\nModified: Tue Dec 5 05:21:04 2023 | | _Find Pack Leader Orgak in the orc fort (located in the northeastern corner of the zone)._\n_Unless you have sufficient faction from killing kobolds, you will have to clear the fort to safely talk to him. He is KOS, but won't attack. The kobolds (that you have to kill to raise your orc faction) in the NW caves of the zone are in the same caves as the cages and pups you will have to feed. Might make a label on your map._\nYou say, 'Hail, Pack Leader Orgak'\nPack Leader Orgak says 'What! Why you here? What you want with master of [wolves]?'\nYou say, 'Wolves?'\nPack Leader Orgak says 'Wolves! My wolves! Orgak the packer leader, Orgak [take care] of the wolves.'\nYou say, 'Take care?'\nPack Leader Orgak says 'Not Orgak's fault! Kobolds take wolves when Orgak out behind tree! Stupid kobolds eat wolves. You! You [go get] wolves for Orgak!'\nYou say, 'I go get'\n_You have been assigned the task 'Free the Wolves'._\nPack Leader Orgak says 'Yes! Yes! Go now. But you need [meat] for wolf! Give meat to wolf. Wolf then know you friend!'\nYou say, 'What meat?'\nPack Leader Orgak says 'Yes! Yes! Here is meat!'\n_You receive 3 x Meat for Orgak's Wolves. You need to travel to the far west side of the zone, and enter the western kobold caves. In the northern rooms are three cages with one wolf in each cage. Break open the cage, and hand each wolf a piece of meat. If there are no cages there, the task should update anyways._\nCages must be open in order to feed the meat to the wolves.\n_Once the cage is open:_\na captured dire wolf pup sniffs at the meat for a moment, then wolfs it down. It immediately looks to you for more. Realizing suddenly that it is free, the wolf bolts away at blinding speed.\nAfter all 3 wolves are freed, you need to kill 10 Nightmoon kobolds. When finished, head back to Orgak.\nYou say, 'Hail, Pack Leader Orgak'\nThe kobolds will think twice before stealing from Orgak again. With the return of his missing wolves, the pack should be back to full strength again.\n_Reward for the quest:_\n\\- Direwolf Totem of Battle\n- Direwolf Totem of Battle [item=51938]",
    },
  },
}
