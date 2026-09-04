-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for Sunderock Springs (sunderock)
-- Total Quests: 4
-- ============================================================================

return {
  zone = "sunderock",
  zone_name = "Sunderock Springs",
  quests = {
    {
      id = "3646",
      title = "Zheren \\#1: Scouting Sunderock",
      exp = "12",
      exp_name = "The Serpent's Spine",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Captain Zheren",
      loc = { y = -1225.0, x = 620.0, z = 0.0 },
      triggers = {
        "Hail, Captain Zheren",
        "What opposition?",
        "What cause?",
        "opposition",
        "cause",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Sunderock Springs [zone=435]\n**Who:**\n- Captain Zheren [npc=23292]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 60\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | No\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n- Experience\n- Faction\n**Factions Raised:**\n- Circle of the Crystalwing +?\n- Crusade of the Scale +?\n**Factions Lowered:**\n- Forces of Dyn'leth -?\n**Related Quests:**\n- Zheren #2: Dyn`leth's Artillery [quest=3692]\n- Zheren #3: The Ashengate Orders [quest=3693]\n- Zheren #4: Dyn`Leth's Mine [quest=3697]\n- Zheren #5: The Direwind Front [quest=3708]\n**Era:** | !Serpents Spine\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Mon Oct 2 01:56:42 2006\nModified: Tue Dec 5 05:21:04 2023 | | _This is the first in a series of five quests. Completing the first four will flag you so that you may request raids with Sergeant Kazzar._\n_Captain Zheren may be found at -1225, +620._\nYou say, 'Hail, Captain Zheren'\nCaptain Zheren says '\\_\\_\\_\\_\\_\\_! Aren't you a sight for sore eyes! We set up this camp a few weeks ago to scout the lands controlled by Dyn`leth. We expected [opposition], but nothing like this.'\nYou say, 'What opposition?'\nCaptain Zheren says 'Dyn`leth's armies control almost every piece of land between the mines to the east and the temple to the north. We are vastly outnumbered. Any strength you can lend to our [cause] would be much appreciated.'\nYou say, 'What cause?'\nCaptain Zheren says 'We are the Crusade of the Scale! We will not rest until Dyn`leth is dead and the Scale of Veeshan has been reclaimed!'\nYou have been assigned the task 'Scouting Sunderock'.\nThe Brotherhood of the Scale is busy fortifying their encampment. They need you to scout the rest of Sunderrock Valley while they prepare their defences. Explore the following areas and report back to Captain Zheran when you are succesful.\nThe Sulfur Bog\nThe Sulfur Bog to the northwest is a festering swamp created by the oozes. They leech nutrients from the earth and expel sulfur as a byproduct of their anatomy.\nThe Pass to Direwind\nA foul wind blows from the Direwind cliffs to the north. Get close, but not too close.\nUpdates at +3000, -150, +350.\nThe Vergalid Slave Quarry\nMany slaves keep Dyn`leth's mining operation running in the Vergalid Mines. You will find the quarry near the entrance to the mines.\nFiddleback's Hunting Grounds\nYou will recognize Fiddleback's vally by the strewn bodies of her drained victims. Tread lightly.\nStarshine Springs\nStarshine is a calm rock glade to the southeast where the faydrake Anaglass lives. You will find solace there.\nSunderock Geyser\nA great plume arises from the valley floor. Beware of Doomfount, the water elemental that originally created the waterspout.\nThe Chimera Caves\nThe chimeras are the largest remaining pack of predators in the valley. Their den lies deep in a cave to the southwest.\nBasilisk Valley\nThe basilisks of Sunderock gather in a great valley to the southeast where they breed and die. Be careful. It is their mating season and the basilisks of that great valley are sure to be more aggresive at this time of year.\n_Explore the following areas:_\n_The Sulfur Bog 2483.74, 1212.63 near Balloondabloop spawn_\n_The Pass to Direwind_\n_Vergalid Mines -912.38, -1549.83, 215_\n_Fiddleback's Hunting Ground 1043, -865.60, 375.58_\n_Starshine Hotsprings -2299.99, -602.58, 208 near Anaglass_\n_Sunderock Geyser -461.86, 910.14, 201.45_\n_The Chimera Caves -2427.96, 2009.22, 21.15 in caves towards Trideath_\n_Basilisk Valley -2694.07, -1520.36, 15.79 towards Komodokin_\nYou say `Hail, Captain Zheren'\nYour task `Scouting Sunderock' has been updated.\nZheren salutes you as you return, `Welcome back. Your scouting run has been a great service to our [cause].'\n_This is a lead-in to the next quest in the series \"Dyn`Leth's Artillery\"._\nYour faction standing with Crusade of the Scale got better.\nYour faction standing with Forces of Dyn'Leth got worse.\nYour faction standing with Circle of the Crystalwing got better.\nYou gain experience!!\n**Submitted by:** Haix Lucifuges, Machin Shin",
    },
    {
      id = "3668",
      title = "Vergalid Mines: Into the Leviathan's Lair",
      exp = "12",
      exp_name = "The Serpent's Spine",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Sergeant Kazzar",
      loc = { y = 1600.0, x = -1500.0, z = 0.0 },
      triggers = {
        "Hail, Sergeant Kazzar",
        "Vergalid Mines?",
        "I am willing",
        "Vergalid mines",
        "willing",
      },
      items_required = {
      },
      rewards = {
        { id = 52380, name = "Clouded Ring of Restoration", type = "item" },
        { id = 52379, name = "Electrified Bauble of Rigor", type = "item" },
        { id = 52381, name = "Kellak's Electrified Ring of Voracity", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Sunderock Springs [zone=435]\n**Who:**\n- Sergeant Kazzar [npc=23426]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 75\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Loot\n**Time Limit:** | 06:00:00\n**Success Lockout Timer**: 36:00:00\n**Related Zones:**\n- Vergalid Mines: Into the Leviathan's Lair [zone=445]\n**Related Creatures:**\n- Kellak the Serpent Lord [npc=23435]\n- Kellak`s offspring [npc=25353]\n**Related Quests:**\n- Access to Ashengate Raids [quest=4157]\n- Zheren #1: Scouting Sunderock [quest=3646]\n- Zheren #2: Dyn`leth's Artillery [quest=3692]\n- Zheren #3: The Ashengate Orders [quest=3693]\n- Zheren #4: Dyn`Leth's Mine [quest=3697]\n**Era:** | !Serpents Spine\nRecommended:\n**Group Size:** | Raid\n**Min. # of Players:** | 6\n**Max. # of Players:** | 24\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Thu Oct 5 16:32:18 2006\nModified: Tue Dec 5 05:21:04 2023 | | _This 24 person (max) raid task begins with Sergeant Kazzar in Sunderock Springs. You must have at least 6 people in your group in order to request this task, they all don't have to be in the zone and can even be offline._\n_Pre-requisites for requesting this task are tasks 1-4 of Captain Zheren's task arc. There are no pre-requisites for participating in the task._\n_Sergeant Kazzar stands next to the Captain._\nYou say, 'Hail, Sergeant Kazzar'\nSergeant Kazzar says 'Our Crusade struggles to hold a basecamp here on this mesa. The fight has not been easy. Our enemies still plot and wait within the [Vergalid mines] to the east.'\nYou say, 'Vergalid Mines?'\nSergeant Kazzar says 'You have fought long and hard against our enemies, \\_\\_\\_\\_. You are almost ready to lead a strike force against the Dragon Vergalid. First, you must take care of one of Vergalid's allies within the mines. Are you [willing] to do this?'\nYou say, 'I am willing'\n_If not in a raid with at least 18 members present in Sunderock Springs..._\nSergeant Kazzar says 'Your forces do not seem up to par for a task of this magnitude, \\_\\_\\_\\_\\_. Perhaps you should return after you regroup.'\n_If all pre-requisites are met, you are given a task selection dialog._\nYou have been assigned the task 'Vergalid Mines: Into the Leviathan's Lair'\nThe direction to the entry to your instanced zone(s) have been marked on your compass. It leads to a door in the rocks to the northeast behind Fiddleback at +1600, -1500.\nVenture into the Vergalid Mines and locate Kellak the Serpent Lord. Rain death down on the serpent. Do not return until the deed is done.\nEnter the Vergalid Mines 0/1 (Sunderock Springs)\n_The zone-in to the instance is at loc 1610, -1490, 390._\nSlay Kellak the Serpent Lord 0/1 (Vergalid Mines)\n_Trash mobs in this zone mostly see invis, so you'll have to kill your way to Kellak's lair._\n_Once engaged, Kellak the Serpent Lord seems to be rooted in place. He sits in the water but you have to damage him above the water so levitate will be needed. He spawns three adds called \"Kellak`s offspring\" which proc \"Serpent's Venom\":_\nSerpent's Venom: Single Target, Cold (-150)\n1: Decrease HP when cast by 500\n2: Decrease Hitpoints by 500 per tick\n3: Increase Poison Counter by 9\n4: Increase Poison Counter by 9\n5: Increase Poison Counter by 9\n_These adds are rootable. Best option is to offtank or root adds away from the raid while everyone burns down Kellak. Kellak himself hits for a max ~8,000 and casts \"Electrify\" and \"Serpent's Venom\":_\nElectrify: Unknown(32) 300', Magic (-400)\n1: Decrease Hitpoints by 6000\nSerpent's Venom: Single Target, Cold (-150)\n1: Decrease HP when cast by 500\n2: Decrease Hitpoints by 500 per tick\n3: Increase Poison Counter by 9\n4: Increase Poison Counter by 9\n5: Increase Poison Counter by 9\nKellak the Serpent Lord has been slain by \\_\\_\\_\\_\\_!\nYour task 'Vergalid Mines: Into the Leviathan's Lair' has been updated.\nYou have completed your task: 'Vergalid Mines: Slaying the Serpent'\n_Kellak drops one of three items:_\nClouded Ring of Restoration\nElectrified Bauble of Rigor\nKellak's Electrified Ring of Voracity\n\n---\n\n_Completion of this task (along with its pre-requisites) allows you to request the Vergalid's End [quest=3930] raid._\n- Clouded Ring of Restoration [item=52380]\n- Electrified Bauble of Rigor [item=52379]\n- Kellak's Electrified Ring of Voracity [item=52381]",
    },
    {
      id = "3692",
      title = "Zheren \\#2: Dyn\\`leth's Artillery",
      exp = "12",
      exp_name = "The Serpent's Spine",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Captain Zheren",
      loc = { y = -1225.0, x = 620.0, z = 0.0 },
      triggers = {
        "Hail, Captain Zheren",
        "What opposition?",
        "What cause?",
        "opposition",
        "cause",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
        { name = "Crusade of the Scale", change = 5 },
        { name = "Forces of Dyn'leth", change = -5 },
        { name = "Circle of the Crystalwing", change = 5 },
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Sunderock Springs [zone=435]\n**Who:**\n- Captain Zheren [npc=23292]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 60\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n- Experience\n- Faction\n**Factions Raised:**\n- Circle of the Crystalwing +5\n- Crusade of the Scale +5\n**Factions Lowered:**\n- Forces of Dyn'leth -5\n**Related Creatures:**\n- a catapult engineer [npc=22760]\n**Related Quests:**\n- Zheren #1: Scouting Sunderock [quest=3646]\n- Zheren #3: The Ashengate Orders [quest=3693]\n- Zheren #4: Dyn`Leth's Mine [quest=3697]\n- Zheren #5: The Direwind Front [quest=3708]\n**Era:** | !Serpents Spine\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Fri Oct 6 22:30:44 2006\nModified: Tue Dec 5 05:21:04 2023 | | _This is the second in a series of five tasks._\n_Captain Zheren may be found at -1225, +620._\nYou say, 'Hail, Captain Zheren'\nCaptain Zheren says '\\_\\_\\_\\_\\_\\_! Aren't you a sight for sore eyes! We set up this camp a few weeks ago to scout the lands controlled by Dyn`leth. We expected [opposition], but nothing like this.'\nYou say, 'What opposition?'\nCaptain Zheren says 'Dyn`leth's armies control almost every piece of land between the mines to the east and the temple to the north. We are vastly outnumbered. Any strength you can lend to our [cause] would be much appreciated.'\nYou say, 'What cause?'\nCaptain Zheren says 'We are the Crusade of the Scale! We will not rest until Dyn`leth is dead and the Scale of Veeshan has been reclaimed!'\n_If you have previously completed \"Scouting Sunderock\".._\nYou have been assigned the task 'Dyn`leth's Artillery'.\nWhile you were away on your scouting expedition, Dyn`Leth's forces stationed around the mines have positioned their catapults to fire on the Brotherhood of the Scale. Kill the artillerists and smash their catapults so the enemy will not be able to fire upon this position.\nKill 14 Engineers - Sunderock Springs\n_Dyn`Leth's artillery forces can be found on both sides of the river, a little to the north of the Crusade of the Scale camp. The engineers are a mix of melee and casters._\nDestroy 7 Catapults - Sunderock Springs /loc -400, 0. They are at the top of the ramp on the west side of the river just north of the Drakkin camp and Captain Zheren. There are more across the bridge above the river, to the east.\n_The catapults can be destroyed with one blow. Of course, nearby engineers will object..._\nReturn to Captain Zheren - Sunderock Springs\nYou say, 'Hail, Captain Zheren'\nYour task 'Dyn`Leth's Artillery' has been updated.\nExcellent. With his catapults out of commission, our camp should be able to continue its preparations for waging war. This will truly help our [cause]!\n_This is a lead-in to the next quest in the series \"The Ashengate Orders\"._\nYour faction standing with Crusade of the Scale has been adjusted by 5.\nYour faction standing with Forces of Dyn'leth has been adjusted by -5.\nYour faction standing with Circle of the Crystalwing has been adjusted by +5.\nYou gain experience!!\n**Submitted by:** Lias Roxx, Defiant, Zek",
    },
    {
      id = "3693",
      title = "Zheren \\#3: The Ashengate Orders",
      exp = "12",
      exp_name = "The Serpent's Spine",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Captain Zheren",
      loc = { y = -1225.0, x = 620.0, z = 0.0 },
      triggers = {
        "Hail, Captain Zheren",
        "What opposition?",
        "What cause?",
        "opposition",
        "cause",
      },
      items_required = {
      },
      rewards = {
        { id = 52485, name = "The Ashengate Orders", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Sunderock Springs [zone=435]\n**Who:**\n- Captain Zheren [npc=23292]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 70\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n- Experience\n- Faction\n**Factions Raised:**\n- Circle of the Crystalwing +?\n- Crusade of the Scale +?\n**Factions Lowered:**\n- Forces of Dyn'leth -?\n**Quest Items:**\n- The Ashengate Orders [item=52485]\n**Related Creatures:**\n- Dyn`Leth`s Courier [npc=22765]\n- a courier guard [npc=22766]\n**Related Quests:**\n- Zheren #1: Scouting Sunderock [quest=3646]\n- Zheren #2: Dyn`leth's Artillery [quest=3692]\n- Zheren #4: Dyn`Leth's Mine [quest=3697]\n- Zheren #5: The Direwind Front [quest=3708]\n**Era:** | !Serpents Spine\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Fri Oct 6 23:10:30 2006\nModified: Tue Dec 5 05:21:04 2023 | | _This is the third in a series of five tasks._\n_Captain Zheren may be found at -1225, +620._\nYou say, 'Hail, Captain Zheren'\nCaptain Zheren says '\\_\\_\\_\\_\\_\\_! Aren't you a sight for sore eyes! We set up this camp a few weeks ago to scout the lands controlled by Dyn`leth. We expected [opposition], but nothing like this.'\nYou say, 'What opposition?'\nCaptain Zheren says 'Dyn`leth's armies control almost every piece of land between the mines to the east and the temple to the north. We are vastly outnumbered. Any strength you can lend to our [cause] would be much appreciated.'\nYou say, 'What cause?'\nCaptain Zheren says 'We are the Crusade of the Scale! We will not rest until Dyn`leth is dead and the Scale of Veeshan has been reclaimed!'\n_If you have previously completed \"Dyn`leth's Artillery\".._\nYou have been assigned the task 'The Ashengate Orders'.\nDyn`Leth's messengers move back and forth from the mines to the cliffs north of here. They travel under heavy guard and carry valuable information on troop movements and force strength.\nCaptain Zheran wants you to intercept a messenger patrol and steal the Ashengate Orders. Return them to him when you have completed your mission.\nStop the Courier from Reaching the Mines 0/1 - Sunderock Springs\n_Dyn`Leth`s Courier is accompanied by four courier guards. All five are immune to changes in run speed so don't bother trying to snare. They walk from the Direwind zoneline to a spot just outside the Vergalid Mines and are easy to ambush (ie, no adds) at a couple of spots along their route._\nFinish the guards lest they warn the enemy 0/4 - Sunderock Springs\nReturn with the orders to Captain Zheren 0/1 - Sunderock Springs\nDeliver the Ashengate Orders to Captain Zheren 0/1 - Sunderock Springs\nYour task 'The Ashengate Orders' has been updated.\nZheren salutes you as you return, 'Welcome back. I will need a moment to review this document. Your deed has been a great service to our [cause]!'\n_This is a lead-in to the next quest in the series \"Dyn`Leth's Mine\"._\nYour faction standing with Crusade of the Scale got better.\nYour faction standing with Forces of Dyn'leth got worse.\nYour faction standing with Circle of the Crystalwing got better.\nYou gain experience!!\n**Submitted by:** Lias Roxx, Defiant, Zek",
    },
  },
}
