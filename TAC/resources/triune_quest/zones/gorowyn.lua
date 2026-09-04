-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for Gorowyn (gorowyn)
-- Total Quests: 3
-- ============================================================================

return {
  zone = "gorowyn",
  zone_name = "Gorowyn",
  quests = {
    {
      id = "8916",
      title = "Chokidai Unbound",
      exp = "24",
      exp_name = "Ring of Scale",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "a sickly chokidai",
      loc = { y = -1240.0, x = -890.0, z = 0.0 },
      triggers = {
      },
      items_required = {
      },
      rewards = {
        { id = 132000, name = "Chokidai Egg", type = "item" },
        { id = 132300, name = "Simple Key", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Gorowyn [zone=1189]\n**Who:**\n- a sickly chokidai [npc=53506]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Quest\n**Quest Goal:**\n- Advancement\n- Experience\n- Loot\n- Money\n**Success Lockout Timer**: 01:00:00\n**Quest Items:**\n- Chokidai Egg [item=132000]\n- Simple Key [item=132300]\n**Related Quests:**\n- For My Information [quest=8852]\n- Partisan of Gorowyn [quest=8930]\n- State of the Sarnak [quest=8907]\n- Testing the Waters [quest=8843]\n- The Dragons' Graveyard [quest=8849]\n- The Fereth [quest=8908]\n- The Orb of Fire [quest=8898]\n- The Orb of Luclin [quest=8893]\n- What Makes a Scorpiki? [quest=8853]\n**Era:** | !Ring of Scale\nRecommended:\n**Group Size:** | Solo\n**Min. # of Players:** | 1\n**Max. # of Players:** | 6\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Fri Dec 1 23:07:05 2017\nModified: Tue Dec 5 05:21:04 2023 | | **Prerequisite Quests:** Testing the Waters [quest=8843], For My Information [quest=8852], What Makes a Scorpiki? [quest=8853], The Dragons' Graveyard [quest=8849], The Orb of Luclin [quest=8893], The Orb of Fire [quest=8898], State of the Sarnak [quest=8907] and The Fereth [quest=8908].\nFind a sickly chokidai [npc=53506] in Gorowyn to request this. It is in the back room of the building where the meat broiler [npc=53501] NPCs are at. (South Room, /loc -1240, -890)\nRequest Phrase: Hail the chokidai.\n\n---\n\n**We need detail on each quest step.**\n1\\. Find a key that will unlock the chains. 0/1 (Gorowyn)\nKill a Krellnakor beastmaster [npc=53479], on a kill you will get a Simple Key [item=132300] on your cursor.\n2\\. Unlock the chains binding the sickly chokidai. 0/1 (Gorowyn)\nFor this step, make sure the person freeing the sickly chokidai doesn't have a pet/familiar, and never goes invis. Target the chokidai and right click the Key.\n3\\. Find food for the poor beast. 0/1 (Gorowyn)\nKill another sarnak in the area, this will update upon killing\n4\\. Lead the chokidai out of Gorowyn. 0/1 (Gorowyn)\nLead the chokidai to the zone in, if you invis the chokidai will bug out and stop following you, it will stop and update this step\n5\\. Find out why the beast hesitates to obtain its freedom. 0/1 (Gorowyn)\nHail the chokidai where it stops. It stops at this map file location.\nP 426.3247, 863.3971, -184.5856, 240, 0, 0, 1, Chokidai\\_Unbound\\_update\\_spot\n6\\. Guard the chokidai while it seeks what it desires. 0/1 (Gorowyn)\nLead the chokidai to the ramp outside and hail it, then go back to kill boilers, broilers & chokidai until Chokidai Egg [item=132000] shows up on your cursor.\n7\\. Get the chokidai out of Gorowyn with its egg. 0/1 (Gorowyn)\nLead the chokidai back to the update spot for step 5 where it stopped. This will update the task and spawn 3 basilisks that will attack.\nEasiest way is to levitate back to the update spot from a high building, the chokidai pet will follow.\n8\\. Protect the pup from the ravenous basilisks. 0/1 (Gorowyn)\nKill the 3 basilisks, they all 3 come at the same time and are the same strength as zone trash.\n9\\. Get the chokidai safely out of Gorowyn with its pup. 0/1 (Gorowyn)\nThis will update at the Skyfire zone line area\n\n---\n\nAchievement(s):\nPartisan of Gorowyn [quest=8930]\n\n---\n\nReward(s):\n425 Platinum\n**Submitted by:** Gidono",
    },
    {
      id = "8929",
      title = "Mercenary of Gorowyn",
      exp = "24",
      exp_name = "Ring of Scale",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Unknown",
      loc = nil,
      triggers = {
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Gorowyn [zone=1189]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | No\n**Can Be Shrouded?:** | No\n**Quest Type:** | Achievement\n**Quest Goal:**\n- Advancement\n**Related Quests:**\n- Chop Chokidai [quest=8906]\n- Kill Krellnakor [quest=8890]\n- Stop the Support [quest=8905]\n**Era:** | !Ring of Scale\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Sat Dec 2 05:30:31 2017\nModified: Mon May 6 02:11:32 2024 | | This achievement is gained upon completing the following quests in Gorowyn.\nPraetor Jerok in The Skyfire Mountains - Kill Krellnakor\nPraetor Jerok in The Skyfire Mountains - Stop the Support\nPraetor Jerok in The Skyfire Mountains - Chop Chokidai\n**Submitted by:** Gidono",
    },
    {
      id = "8930",
      title = "Partisan of Gorowyn",
      exp = "24",
      exp_name = "Ring of Scale",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Unknown",
      loc = nil,
      triggers = {
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Gorowyn [zone=1189]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | No\n**Can Be Shrouded?:** | No\n**Quest Type:** | Achievement\n**Quest Goal:**\n- Advancement\n**Related Quests:**\n- Chokidai Unbound [quest=8916]\n- State of the Sarnak [quest=8907]\n- The Fereth [quest=8908]\n**Era:** | !Ring of Scale\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Sat Dec 2 05:33:52 2017\nModified: Mon May 6 02:11:32 2024 | | This achievement is gained upon completing the following quests in Gorowyn.\nPraetor Maestra in The Skyfire Mountains - State of the Sarnak\nPraetor Maestra in The Skyfire Mountains - The Fereth\na sickly chokidai - Chokidai Unbound\n**Submitted by:** Gidono",
    },
  },
}
