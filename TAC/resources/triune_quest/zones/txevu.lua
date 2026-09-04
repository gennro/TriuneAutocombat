-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for Txevu, Lair of the Elite (txevu)
-- Total Quests: 1
-- ============================================================================

return {
  zone = "txevu",
  zone_name = "Txevu, Lair of the Elite",
  quests = {
    {
      id = "7680",
      title = "Gates of Discord Progression \\#8: Txevu Keying & Tacvi",
      exp = "07",
      exp_name = "Gates of Discord",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Hamari Nedu",
      loc = nil,
      triggers = {
        "Hail, Hamari Nedu",
        "Help me",
        "Tkarish?",
        "What sacred constructs?",
        "Signet of Command?",
        "Txevu",
        "help you",
        "Tkarish",
      },
      items_required = {
      },
      rewards = {
        { id = 35216, name = "Jade Inlaid Key", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Txevu, Lair of the Elite [zone=251]\n**Who:**\n- Hamari Nedu [npc=17476]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 65\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | No\n**Can Be Shrouded?:** | No\n**Quest Type:** | Quest\n**Quest Goal:**\n- Advancement\n**Quest Items:**\n- Jade Inlaid Key [item=35216]\n- Polished Stone Key [Txevu]\n**Related Zones:**\n- Tacvi, Seat of the Slaver [zone=257]\n**Related Creatures:**\n- High Priest Nkosi Bakari [npc=15398]\n- Ixt Hsek Syat [npc=15525]\n- Mastruq Champion [npc=15403]\n- Zun`Muram Tkarish Zyk [npc=15405]\n- restless wraith [npc=19561]\n**Related Quests:**\n- Raid Expedition: Tacvi, Seat of the Slaver [quest=3035]\n- Txevu Raid Event: High Priest Nkosi Bakari (Key #2) [quest=7682]\n- Txevu Raid Event: The Gladiator Pit (Key #1) [quest=7681]\n- Txevu Raid Event: Zun`Muram Tkarish Zyk [quest=7683]\n**Era:** | !Gates of Discord\nRecommended:\n**Group Size:** | Solo\n**Min. # of Players:** | 1\n**Max. # of Players:** | 1\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Wed Aug 13 18:00:13 2014\nModified: Tue Dec 5 05:21:04 2023 |\n---\n\n**_Note: If all you're interested in is participating in Txevu and Tacvi raids, then you don't need to worry about this quest. If you want the keys to the locked doors within Txevu and want to be able to request the Tacvi raid, then this quest is for you._**\n_This part of Gates of Discord progression follows your **having accessed Txevu** [quest=2917]._\n\n---\n\n!\n\n---\n\n**Hamari Nedu**\n_At the zone-in of Txevu is a Nihil named Hamari Nedu:_\nYou say, 'Hail, Hamari Nedu'\nHamari Nedu says 'Aaaaahh! You frightened me! I've spent days hiding in the rubble here waiting for someone to come. Thank Trushar it's you and not one of those monsters! I didn't know how much longer I could hold out, but I have information that may [help you] rid our island of those vile Muramites and help me get out of this cursed place.'\nYou say, 'Help me'\nHamari Nedu says 'I know the monster that guards this place. He calls himself [Tkarish]. I was held captive by the two-headed beast. I don't know exactly what fate awaited me, but the cries of my fellow prisoners were enough to know that it wouldn't have been pleasant.'\nYou say, 'Tkarish?'\nHamari Nedu says 'I believe the full title he demanded his servants use is Zun'Muram Tkarish Zyk. Fortunately, he's as arrogant as he is strong and I was able to slip away when he thought me secure. Unfortunately, he has gained control over the sacred [constructs] in the temple so I haven't been able to leave.'\nYou say, 'What sacred constructs?'\nHamari Nedu says 'There are special constructs within this temple that allow access to other areas. The one next to us would normally allow me to leave the temple entirely, but it is under the sway of the Muramites. I overheard Tkarish speaking of a Tunat'Muram, a kind of commander as far as I could tell, that resides within the upper levels of the temple only reachable via the constructs. But Tkarish holds a [Signet of Command] which gives him control over the constructs. As long as he has that Signet, the way to the Tunat'Muram is closed to you and the way out is closed to me.'\nYou say, 'Signet of Command?'\nHamari Nedu says 'If you can wrest the signet from Tkarish's grasp, the constructs will allow you passage to the upper levels of the temple. Should you claim a Signet of Command for yourself, I can use it to activate a nearby construct. From here, the influence of your signet would be stronger than the one Tkarish wields in the chapel above and I should be able to convince the construct to grant you passage to the upper levels of the temple.'\n_He speaks of Zun`Muram Tkarish Zyk... To get to him, you'll need to do some keying within the zone first._\n\n---\n\n**Entering the High Priest's Caverns**\n_To unlock the door to the High Priest's caverns, you'll need a **Polished Stone Key** [item=32891]._\n_Trigger the **Gladiator Pit event** [quest=7681] whose main encounter is **Ixt Hsek Syat** [npc=15525]. She drops one key per kill. (Only one person in a raid needs this key.)_\n\n---\n\n**Entering the Zun`Muram's Chamber**\n_To unlock the door to the Zun`Muram's chamber, you'll need a **Jade Inlaid Key** [item=35216]._\n_Trigger the **High Priest event** [quest=7682] whose main encounter is **High Priest Nkosi Bakari** [npc=15398]. He drops one key per kill. (Only one person in a raid needs this key, although the more you have, the less burden on the keyholders.)_\n\n---\n\n**Signet of Command & Requesting the Tacvi Raid**\n_Complete the **Zun`Muram's raid event** [quest=7683], culminating in the death of **Zun`Muram Tkarish Zyk** [npc=15405], who drops 1x \" **Zun'Muram's Signet of Command** [item=33843] per kill._\n_Upon the Zun`Muram's death, your raid is automatically assigned the Tacvi raid expedition which you can enter by clicking on the golem statue in his chamber. You don't have do this, though._\n_With the Signet of Command on you, speak with Hamari Nedu again, and you can request the **Tacvi raid expedition** [quest=3035] at any time._\n\n---\n\n**Finished**\n_Now, you're done with Gates of Discord progression. All that is left is the final raid zone of the expansion, Tacvi (and lots of loot to be had)._",
    },
  },
}
