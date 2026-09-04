-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for Lavastorm Mountains 3.0 (thegrey)
-- Total Quests: 2
-- ============================================================================

return {
  zone = "thegrey",
  zone_name = "Lavastorm Mountains 3.0",
  quests = {
    {
      id = "3058",
      title = "Norrath's Keepers Tier 4a: Guardian of the Sands",
      exp = "09",
      exp_name = "Dragons of Norrath",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Lieutenant Ekiltu Verlor",
      loc = nil,
      triggers = {
        "Hail, Lieutenant Ekiltu Verlor",
      },
      items_required = {
      },
      rewards = {
        { id = 34890, name = "Cape of Serenity", type = "item" },
        { id = 34954, name = "Fired Glass Bracelet", type = "item" },
        { id = 35147, name = "Necklace of Sandstorms", type = "item" },
        { id = 34991, name = "Norrath's Keepers Token", type = "item" },
        { id = 36689, name = "Polished Sunsword", type = "item" },
        { id = 34891, name = "Quintessence of Sand", type = "item" },
      },
      factions = {
        { name = "Stillmoon Acolytes", change = -1 },
        { name = "Kessdona", change = -1 },
        { name = "Rikkukin", change = -1 },
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Lavastorm Mountains 3.0 [zone=31]\n**Who:**\n- Lieutenant Ekiltu Verlor [npc=17798]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 70\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n- Faction\n- Loot\n**Time Limit:** | 06:00:00\n**Success Lockout Timer**: 200:00:00\n**Faction Required:**\nNorrath's Keepers (Min: Kindly)\n**Related Zones:**\n- Stillmoon Temple: Guardian of the Sands [zone=392]\n**Related Creatures:**\n- Shogurei, Guardian of the Sands [npc=17725]\n**Related Quests:**\n- Dragons of Norrath Progression (Norrath's Keepers) [quest=3061]\n- Norrath's Keepers Tokens [quest=3134]\n**Era:** | !Dragons of Norrath\nRecommended:\n**Group Size:** | Raid\n**Min. # of Players:** | 6\n**Max. # of Players:** | 42\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Mon Mar 7 21:22:46 2005\nModified: Tue Dec 5 05:21:04 2023 |\n---\n\n**For an overview of the Dragons of Norrath expansion, see this wiki article.**\n**For an overview of progression, see quest entries for Norrath's Keepers [quest=3061] and the Dark Reign [quest=3062].**\n\n---\n\n_This raid task is of Planes of Power Elemental-to-Time difficulty. It begins with Lieutenant Ekiltu Verlor ( **click for map image**) in the Norrath's Keepers camp of the Lavastorm Mountains. This task has a 3-day, 20-hour lockout timer._\n_Pre-requisites for requesting this task:_\n\\- Minimum 6 players; maximum 42 players\n\\- Must be kindly faction with Norrath's Keepers\n\\- Completion of all Tier 3 tasks and flags\nYou say, 'Hail, Lieutenant Ekiltu Verlor'\nLieutenant Ekiltu Verlor says 'Those faithful to the way of Norrath's Keepers may take on the greatest challenges and prove their worth to Firiona Vie.'\nYou have been assigned the task 'Guardian of the Sands'.\nThere have been several sightings of a massive guardian that has risen in the sand gardens of Stillmoon Temple. This guardian has been very protective of the area and we have lost contact with several scouts that were sent to gather more information. The scouts that have survived the attacks report that the guardian is allied with the sand goblins of the region. It is simply too dangerous to continue our exploration of the temple as long as that guardian is around. We need you to remove it.\n\n---\n\n**Task Steps**\nTouch the portal to Stillmoon Temple 0/1 (The Broodlands)\nConfront the Guardian 0/1 (Stillmoon Temple)\n**TASK LOCKS HERE**\nKill Shogurei 0/1 (Stillmoon Temple)\n\n---\n\n**The Event**\n_Warning! While in this zone, keep off the sand. Stepping on the sand causes multiple goblin spawns that aggro your party (additional to static spawns already found in the zone's base population)._\n_Clear your way to \"Shogurei, Guardian of the Sands\" (far northeastern part of the zone), and engage him (he is NOT rooted in place, so can be pulled - unknown if any leash range), and kill him. This is a fairly straightforward encounter._\nShogurei, Guardian of the Sands says 'You have defiled this place with your murderous presence. As life bleeds out of you and you gasp your final breath, know that you have met your end at the hands of Shogurei, guardian of these sacred sands.'\n_He hits for a max ~2,300; has ~775,000 hitpoints; flurries; single-target rampages; and casts a few spells:_\nDenial of Flight: Targeted AE 150', Magic (-300)\n1: Decrease HP when cast by 7500\n2: Root\nExplosion of Sand: PB AE 500', Magic (-250)\n1: Decrease HP when cast by 1500\n2: Decrease Attack Speed by 30%\n3: Decrease Movement by 30%\nHammer of Absolution: AE PC 250', Magic (-300)\n1: Decrease Hitpoints by 3000\n2: Stun (5.00 sec)\n\n---\n\n**Completion & Loot**\n_The task completes upon his death._\nShogurei, Guardian of the Sands has been slain by \\_\\_\\_\\_\\_!\nShogurei, Guardian of the Sands's corpse says 'The garden stands defiled, but you have brought me honor in defeat.'\nYour faction standing with Stillmoon Acolytes has been adjusted by -1.\nYour faction standing with Kessdona has been adjusted by -1.\nYour faction standing with Rikkukin has been adjusted by -1.\nWith the guardian out of the way, exploration of the temple can continue.\n_He drops 9x \"Quintessence of Sand\" + 2 items from this loot table:_\nCape of Serenity\nFired Glass Bracelet\nNecklace of Sandstorms\nPolished Sunsword\nSand-Molded Leather Bracer\nWrapped Glass Shard\n_Task Rewards:_\n9x \"Radiant Crystal\"\n1x \"Norrath's Keepers Token\" (faction **turn-in** [quest=3134] item)\n_Note: If doing this raid as part of progression, you'll want to check in with some NPCs to make sure your flags are up to date. See **this quest entry** [quest=3061] for more details._\n**Submitted by:** Saraban of Darkwind\n- Cape of Serenity [item=34890]\n- Fired Glass Bracelet [item=34954]\n- Necklace of Sandstorms [item=35147]\n- Norrath's Keepers Token [item=34991]\n- Polished Sunsword [item=36689]\n- Quintessence of Sand [item=34891]\n- Radiant Crystal [item=34988]\n- Wrapped Glass Shard [item=34889]",
    },
    {
      id = "3561",
      title = "High and Low",
      exp = "01",
      exp_name = "The Ruins of Kunark",
      min_lvl = 40,
      max_lvl = 55,
      quest_type = "Task",
      repeatable = true,
      group_size = "Solo",
      npc = "a creature",
      loc = { y = 3290.0, x = 2140.0, z = 0.0 },
      triggers = {
        "Hail, Matranius Slad",
        "Matranisu Slad",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "**Level:** 40\n**Maximum Level:** 55\n**Monster Mission:** No\n**Repeatable:** Yes\n**Can Be Shrouded?:** No\n**Quest Type:** Task\n**Group Size:** Solo\n\nThis is a Short task.\nTask stage needed.\nThis isn't like any journey you've ever taken before. This time you're on a serious mission to find the one they call Morticalidon. No one knows what it looks like, or if it even really exists, but legend says that a creature of sinister power roams the lands in search of prey once every hundred years. It's time the search started for this mythical creature and you're the one who's going to be at the forefront. The search has already begun, but there are plenty of places to search. You should explore [the ruins in the northwest, near the Skyfire Mountains], to start. Do you think you can handle that?\nEnter the ruins at +3290, +2140 near the Skyfire zone-line.\nTask stage needed.\nDon't worry about it too much, there are plenty of other places to explore, and there is no doubt in anyone's mind that this creature is real, but highly elusive. Why don't you take a torch and explore [the entrance to Veeshan's Peak,]? This seems like the next best place to look for it.\nHead to Skyfire Mountains and visit the area in front of the hallway leading to Veeshan's Peak, at around +2320, +2925.  You don't actually need a torch.\nTask stage needed.\nNo luck there either, but don't fret. There will be plenty of chances to find the beast before your time on Norrath is done. Go find and speak with [Matranisu Slad], just to let them know that you've begun to search.\nMatranius Slad is at +300, -1810 in the Dreadlands, near the entrance to Karnor's Castle.  The direction will be marked on your compass as you zone in.\nYou say, 'Hail, Matranius Slad'\nMatranisu Slad says 'Thanks for contacting me, ______.  Your information on this matter has been most useful.'\nYour task 'High and Low' has been updated.\nThe search for the Morticalidon won't end, not as long as intrepid explorers like you are on the trail.  With this type of creature, you never know when or where you'll find it, but one thing is for sure -- finding this creature will be the most rewarding experience you'll ever have.  In the meantime, here's payment for the time you spent searching.\nReward is 47p 2g 6s 6c and experience.Submitted by: SukrasisxRewards:\n[",
    },
  },
}
