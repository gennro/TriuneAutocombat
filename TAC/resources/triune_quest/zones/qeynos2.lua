-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for Plane of Health (qeynos2)
-- Total Quests: 1
-- ============================================================================

return {
  zone = "qeynos2",
  zone_name = "Plane of Health",
  quests = {
    {
      id = "8063",
      title = "Anashti Sul, Damsel of Decay",
      exp = "22",
      exp_name = "The Broken Mirror",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Lashun Novashine - Plane of Health - 1",
      loc = nil,
      triggers = {
      },
      items_required = {
      },
      rewards = {
        { id = 124530, name = "Pauldrons of the Dark Side", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Plane of Health [zone=1057]\n**Who:**\n- Lashun Novashine - Plane of Health - 1 [npc=50221]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 75\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Adventure\n**Quest Goal:**\n- Advancement\n- Experience\n- Loot\n- Money\n**Time Limit:** | 00:20:00\n**Success Lockout Timer**: 00:03:00\n**Related Creatures:**\n- Anashti Sul, Damsel of Decay [npc=50358]\n- a chest - Anashti Sul, Damsel of Decay [npc=50769]\n**Era:** | !The Broken Mirror\nRecommended:\n**Group Size:** | Group\n**Min. # of Players:** | 1\n**Max. # of Players:** | 6\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Thu Dec 3 00:55:05 2015\nModified: Sat Jan 27 08:53:04 2024 | | Speak with Lashun Novashine in Plane of Health to get this quest. Keyword is \"try\".\n\n---\n\n**Task Steps**\nKill Anashti Sul 0/1 (Sul Vius: Demiplane of Decay)\nTalk to Anashti to start the event.\nOpen the chest. 0/1 (Sul Vius: Demiplane of Decay)\n\n---\n\n**The Phases**\nThe Starting Phase\nFrom 100% - 75% it will be standard fight. Anashti hits hard and fast. Averaging about 30k a hit, she will strike through defenses regularly. It is recommended to have someone that can slow her. Around 95% the bokons will spawn in the southern tunnel.\nThe Gifts Phase\nAround 75% - Anashti Sul will enter her 'Gifts' phase in which she will put two different gifts on a random target. She will either use Gifts of Endless Life which is a heal over time, or Gifts of Living Death which is a damage over time. There is a special achievement for not curing either of these.\nThe Porting Phase\nAround 56% - Anashti Sul will port herself downstairs with the main tank. It is recommend that you have your party start moving down to the bottom around 57% because there is a likelihood that some may be afflicted with enfeeblement which has a snare debuff attached to it. When she does her port, you have 60 seconds to do as much DPS as you can before she ports back upstairs. She will port up and down every 60 seconds.\nThe Withering Phase\nThe final and most frustrating phase is the Withering Phase. At 36% she will start her withering curse cycle on the entire group. There are three different curses; Withering Limbs XIII which affects all DPS based classes negatively, Withering Faith XIII which affects all healers negatively, including Shadowknights attempting to do lifetap abilities, and Withering Physicality XIII which is a nightmare for tanks. Unless you are a healer, it is ideal for DPS & tanks to have the Withering Faith effect - as it will be less crippling. It is absolutely not recommended to do this without a real player healer, because if you use a mercenary healer - he/she will continually cast a curse cure which will potentially cycle you into a curse you do not want to have for your specific class. Each curse respectfully lasts for about 2 minutes. It is recommended that tanks use any form of deflection about 3 seconds before the curse fades due to the likelihood you may fade into the physicality curse. Using a deflection type ability if hit with physicality will give you enough time to use a potion or get a curse cure to cycle you into a more favorable curse.\n**_NOTE: She will continue to port every 60 seconds up and down during the Withering Phase. If you are unable to defeat her by the time she ports a 3rd time, there is a chance you likely will not win._**\nThe Bokons & Ooze\nIt is good to have a Knight class off tank the bokons and oozies. The bokons spawn in the southern tunnel around 95% and make their way to fight. It is recommended to keep a player in opening to that tunnel to intercept while keeping an eye out for the oozies. The oozies spawn at the lower level, but due to pathing issues, they rarely actually work their way up the tunnel - so they simply just \"port\" into the fight. The bokons only hit for about 3-4k, but the oozes will hit for about 20k and backstab. This is not a good thing if a ooze gets on your main tank. Just kite the bokons into the oozes and they will die instantly. Be advised bokons will regularly use the Enfeeblement spell, which does both a snare and halves the target's cast timer (very bad for healers).\n**_NOTE: It is recommended that your main healer puts down healing wards because the bokons will cast use the enfeeblement spell; which not only has a snare effect but it slows your cast timers down as well. This can spell trouble for the healer attempting to throw out quick heals to the tank._**\nFailure Mechanics\nThere are three mechanics that will lead to instant death.\n**1\\. Tank swapping.** If you attempt to swap out a tank for a pet, or another tank and that main tank is still on her most hated list, she will start a mechanic called _'Internal Rot'_ that will do DoT damage between 80-100k a tick! The only way to counteract this is to get back within range of her to fight.\n**2\\. 20 Minute Timer Fail.** You have 20 minutes to beat her. She even tells you this. If you do not stop her in under 20 minutes, the event fails and you will get death touched.\n**3\\. Withering Physicality.** If you are unfortunate to have this effect and do not get a cure in time, you will end up getting one-shot by either Anashti Sul, the bokons, or the oozes. This effect is not an effect anyone should have on at any time.\n**4\\. Disease or Corruption.** Either one of these types of spells or procs will power Anashti Sul up. She will recover 5% of her overall health and hit a bit harder.\n\n---\n\nReward(s):\nExperience\n150pp\n333 Remnants of Tranquility\n**Submitted by:** Aghinem\n- Pauldrons of the Dark Side [item=124530]",
    },
  },
}
