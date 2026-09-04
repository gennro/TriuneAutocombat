-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for Commonlands (commonlands)
-- Total Quests: 2
-- ============================================================================

return {
  zone = "commonlands",
  zone_name = "Commonlands",
  quests = {
    {
      id = "3783",
      title = "LDoN Raid: Rujarkian Hills: Hidden Vale of Deceit",
      exp = "06",
      exp_name = "Lost Dungeons of Norrath",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Chaenz Abella",
      loc = { y = 5.0, x = -205.0, z = 0.0 },
      triggers = {
        "Hail, Chaenz Abella",
        "problem",
        "interested",
        "Hail, Crispen Koloff",
        "news",
        "worst of it",
        "There",
        "last of it",
      },
      items_required = {
        { id = 41000, name = "Wayfarers Brotherhood Emblem", count = 1 },
      },
      rewards = {
        { id = 53372, name = "Anomalous Rock of Alteration", type = "item" },
        { id = 24870, name = "Archaic Shield of Stone", type = "item" },
        { id = 61185, name = "Enchanted Stone of Research", type = "item" },
        { id = 68787, name = "Experimental Gem of Enhanced Protection", type = "item" },
        { id = 25755, name = "Experimental Gem of Haste", type = "item" },
        { id = 53371, name = "Experimental Smoldering Stone", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Commonlands [zone=463]\n**Who:**\n- Chaenz Abella [ _Raid Recruiter_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 65\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Expedition\n**Quest Goal:**\n- Loot\n**Related Zones:**\n- Rujarkian Hills: Hidden Vale of Deceit (Raid) [zone=450]\n**Related Creatures:**\n- Flawed Experimental Brute [npc=25916]\n- Flawed Mutation [npc=25919]\n- Flawless Experimental Battlelord [npc=52035]\n- Flawless Experimental Brute [npc=52034]\n- Researcher`s Box of Supplies [npc=36863]\n- Steelslave Research Assistant [npc=25918]\n- Steelslave Researcher [npc=25920]\n- The Bloody Barrel [npc=36864]\n- The Splintering Barrel [npc=36865]\n- Violent Research Subject [npc=25917]\n**Era:** | !Lost Dungeons of Norrath\nRecommended:\n**Group Size:** | Raid\n**Min. # of Players:** | 6\n**Max. # of Players:** | 54\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Fri Oct 27 17:34:29 2006\nModified: Tue Dec 5 05:21:04 2023 | | _This raid expedition begins with Chaenz Abella in the Commonlands tunnel (keyword: \"interested\")._\nYou say, 'Hail, Chaenz Abella'\nChaenz Abella gleams at you eagerly. 'Greetings, Bobbybick! Such hustle and bustle about, it's amazing how far the Wayfarer's Brotherhood has come in such a short time! I've been charged with welcoming new recruits while Morden is off exploring. In the meantime, I've got to focus on my duties. As always we could use stalwart lads and lasses to help us with our adventuring! If you can rally the call of your friends perhaps you can help us with a serious [problem].'\nYou say, 'problem'\nChaenz Abella says, 'Our scout, Nevlen, just got back from the Rujarkian Hills after looking into a rumor of a huge stockpile of ill-gotten orcish treasure. He and his companion Crispen discovered that the rumor was true! We want to go back in and search for more of the treasure, but we have been told the orcs may be waiting for our arrival. We need to you get down there quickly to gather more samples from their stores before they move them! Are you [interested]?'\nYou say, 'interested'\nChaenz Abella says, 'Splendid! You should begin right away, but keep on your guard while searching for the treasure. They may be waiting for you.'\n_The Rujarkian Hills: Hidden Vale of Deceit is now available to you._\nHead to South Ro to location +5, -205 to zone into the instance.\n_Optional: Speak to Crispen Koloff inside of the expedition to learn more about what is going on._\nYou say, 'Hail, Crispen Koloff'\nCrispen Koloff says, 'At last the raiding party has arrived! I feared that Nevlen might not have made it back with the treasure samples. We were lucky to escape with our lives with those orcs bearing down on us like they were. In any case, it's good that you're finally here. Since Nevlen left I've been skulking about in the shadows hiding from any patrols that wander by. I've found out some disturbing [news] that will make your journey to the treasure that much more difficult.'\nYou say, 'news'\nCrispen Koloff says, 'It started with an increase in the number of orcs all through the caves here. I think they caught on that someone might be trying to steal their treasure so they sent reinforcements to protect it. But that's not the [worst of it].'\nYou say, 'worst of it'\nCrispen Koloff says, 'Some of the orcs here are... different. They've been experimenting on some of their own kind and turning them into something awful. I overheard one of the patrols talking about samples being extracted from local fauna. From what I could gather, when the samples are combined by some researchers and given to these orcs, they turn into ferocious beasts more powerful than any orc they'd ever seen. [There's more] though.'\nYou say, 'There's more'\nCrispen Koloff says, 'Indeed there is. The beasts are being held separate from each other so none of the samples can get contaminated before they're combined by the researchers. You're going to need to find the creatures they're extracting the samples from and destroy them. Hopefully, at least for now, that will stop them from creating any more of these orc mutations. That's not the [last of it], though.'\nYou say, 'last of it'\nCrispen Koloff says, 'The last of it requires you to find the researchers and destroy them before they can proceed any further with these creations. Who knows what kind of problems they could cause if let loose on the outside world. Hopefully, once that's done, you'll be able to make your way to the treasure unhindered.'\n\n---\n\n!\n_NOTE: Trash mobs in \"Fancy\" looking armor are considered \"named\" and will drop one of many common Rujarkan-Themed loots that are also found in most regular group LDoN tasks._\n_Each room consists of a dozen or more trash NPCs. Pulls rooms are tightly packed and mobs have a pretty large social aggro radius._\n_Trash hits for around 800 max but many will backstab for a few thousand if given the opportunity. Trash mobs do not summon and are susceptible to crowd control methods._\n_To progress in the mission and receive all possible chests the raid will need to defeat four \"Violent Research Subject\" found in multiple rooms throughout the zone, requiring quite a bit of trash clearing or some very amazing pulling. Each Violent Research Subject has a \"Steelslave Research Assistant\" who will not engage in combat and will run off towards the northeastern most room when the subject is defeated then promptly despawn. Research Subjects hit for around 2700 damage and will summon when damaged, they also single target rampage._\n_Once all four Violent Research Subjects are defeated the raid should move towards the northeastern section of the map, where three \"Steelslave Researcher\" can be found. These three can be split from eachother and should be as they each hit for around 2650 damage and cast basic cleric spells. Kill all three to unlock one of the potential chests and spawn the final encounter._\nYour victory has weakened a shroud of magic cloaking the dungeon's treasure.\n_Now the raid should backtrack a bit and head to the far west part of the map where you will encounter the boss of the expedition along with some mini \"Flawless Experimental Brutes\". The Brutes are quite strong and should be properly split pulled, each hitting for 2650, Single Rampaging, and have the ability to Backstab._\n_Once the Brutes are dead across the bridge you will see the \"Flawless Experimental Battlelord\", the boss of the expedition, flanked by two Research Assistants. These three mobs are aggro linked. In order to get all three chests at the end of the expedition, the two Research Assistants must be killed before the Battlelord._\n_The Battlelord hits for around 3650, can backstab for 13000 (ouch) and has a single target knockback/memblur \"Throw\" which also does 3000 damage to his current target. After a period of time (how long?) he will summon 6 \"Flawed Mutation\" adds which hit for around 1000._\n_Multiple chests and barrels spawn with loot once this event is complete. The final chests can be found surrounding/inside the wagon south of the bridge in the same room as the final boss._\n\n---\n\n_Known raid loot from this event (Two items per chest, can receive duplicates):_\nThe Splintering Barrel\nWeighted Stone of Prowess\nOrcish Tattered Shroud\nAnomalous Rock of Alteration\nResearcher's Exacting Ore\nResearcher's Stone of Power\nThe Bloody Barrel\nLight Stone of Life\nVelrek's Enchanted Prism\nEnchanted Stone of Research\nTorn Robe of the Tormented\nPolished Gemstone of Aggression\nSinging Stone Bracer\nResearcher's Box of Supplies\nExperimental Smoldering Stone\nSmooth Stone of Blissful Tranquility\nExperimental Gem of Haste\nRinged Stone of Advantage\nExperimental Gem of Enhanced Protection\n**Submitted by:** Bobbybick\n- Anomalous Rock of Alteration [item=53372]\n- Archaic Shield of Stone [item=24870]\n- Enchanted Stone of Research [item=61185]\n- Experimental Gem of Enhanced Protection [item=68787]\n- Experimental Gem of Haste [item=25755]\n- Experimental Smoldering Stone [item=53371]\n- Girdle of Bloodstained Stones [item=24152]\n- Light Stone of Life [item=68790]\n- Necklace of the Troglodyte [item=24002]\n- Orcish Tattered Shroud [item=75427]\n- Polished Gemstone of Aggression [item=25756]\n- Researcher's Exacting Ore [item=60254]\n- Researcher's Stone of Power [item=68788]\n- Ringed Stone of Advantage [item=25757]\n- Singing Stone Bracer [item=53373]\n- Smooth Stone of Blissful Tranquility [item=60255]\n- Stone Bracelet of Battle Mastery [item=24649]\n- Torn Robe of the Tormented [item=64769]\n- Velrek's Enchanted Prism [item=68786]\n- Weighted Stone of Prowess [item=25760]",
    },
    {
      id = "4229",
      title = "LDoN Raid: Rujarkian Hills: War March of Imal Ojun",
      exp = "06",
      exp_name = "Lost Dungeons of Norrath",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Uzmanya Zsiksta",
      loc = nil,
      triggers = {
        "Hail, Uzmanya Zsiksta",
        "What problem?",
        "We are interested",
        "_Raid Recruiter_",
        "problem",
        "interested",
        "hail",
      },
      items_required = {
      },
      rewards = {
        { id = 25792, name = "Battle Fervor Stone", type = "item" },
        { id = 25258, name = "Boots of the Rujarkian Arena", type = "item" },
        { id = 27782, name = "Cap of the Elite Orcs", type = "item" },
        { id = 27783, name = "Cloak of the Fleeting Foot", type = "item" },
        { id = 57936, name = "Dented Gauntlets of Victory", type = "item" },
        { id = 63448, name = "Earring of Spirited Mind", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Commonlands [zone=463]\n**Who:**\n- Uzmanya Zsiksta [ _Raid Recruiter_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 65\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Expedition\n**Quest Goal:**\n- Loot\n**Success Lockout Timer**: 108:00:00\n**Related Zones:**\n- Rujarkian Hills: War March of Imal Ojun (Raid) [zone=521]\n**Related Creatures:**\n- Captain Grelnik [npc=25854]\n- Captain Hurklin [npc=25862]\n- Captain Kalin [npc=25858]\n- Ojun`s Splintered Chest [npc=25866]\n- Ojun`s Weapon Rack [npc=25868]\n- Ojun`s Wooden Chest [npc=25867]\n- Warlord Imal Ojun [npc=15098]\n**Era:** | !Lost Dungeons of Norrath\nRecommended:\n**Group Size:** | Raid\n**Min. # of Players:** | 6\n**Max. # of Players:** | 54\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Mon Jun 11 18:06:58 2007\nModified: Sat Aug 2 06:52:42 2025 | | _This raid expedition begins with Uzmanya Zsiksta in the Wayfarer camp in the Commonlands. It has a lockout timer of 4 days, 12 hours._\nYou say, 'Hail, Uzmanya Zsiksta'\nUzmanya Zsiksta says 'Hail, \\_\\_\\_\\_\\_. Those Rujarkian orcs are mighty beasts, indeed! I've felt the blade of a few of them myself. We have many tasks that we need to address in those hills. If you are brave and strong enough, I'm sure we can find some work you could help us with. If you can rally the call of your friends perhaps you can help us with a serious [problem].'\nYou say, 'What problem?'\nUzmanya Zsiksta says 'We have learned that Warlord Imal Ojun is organizing a great army in the Rujarkian Hills. Should he complete his army, the orcs will prove to be an even greater threat. The Warlord must be stopped. We need you to disrupt his activities. Our scouts report that the Warlord has appointed three captains. If you slay them, much of the army will crumble. Are you [interested]?'\nYou say, 'We are interested'\nUzmanya Zsiksta says 'The captains will not lay down without a fight, \\_\\_\\_\\_\\_. Be ready for anything.'\nThe Rujarkian Hills: War March of Imal Ojun is now available to you.\n_This instance entrance is in South Ro._\nYou have entered The Rujarkian Hills: War March of Imal Ojun.\n_Here you will need ot kill three captains and a warlord:_\n_Captain Grelnik_\n_Captain Kalin_\n_Captain Hurklin_\n_Warlord Imal Ojun_\n( **encounter information needed**)\nCaptain Grelnik's corpse draws a final breath while clawing at its fatal wounds.\nYour victory has weakened a shroud of magic cloaking the dungeon's treasure.\nCaptain Kalin's corpse draws a final breath while clawing at its fatal wounds.\nYour victory has weakened a shroud of magic cloaking the dungeon's treasure.\nCaptain Hurklin's corpse draws a final breath while clawing at its fatal wounds.\nYour victory has weakened a shroud of magic cloaking the dungeon's treasure.\nWarlord Imal Ojun's corpse draws a final breath while clawing at its fatal wounds.\nYour victory has shattered the shroud of magic surrounding the dungeon's treasure.\n_Upon the warlord's death, up to three chests spawn with loot:_ /open or melee them open.\n\n---\n\n_Known raid loot from this event (Two items from each chest, can have duplicates from the same chest and there is a weapon rack as well with loot):_\nOjun`s Wooden Chest\nCap of the Elite Orcs\nCloak of the Fleeting Foot\nEarring of Spirited Mind\nLeggings of Rejuvenation\nSpaulders of Battle Rage\nSteel Leggings of Old Wars\nOjun`s Weapon Rack\nBattle Fervor Stone\nBoots of the Rujarkian Arena\nRing of Battle Readiness\nRujarkian Ring of Strategy\nWristguard of Battle Rage\nOjun`s Splintered Chest\nDented Gauntlets of Victory\nElite Steelslave Surgeon's Ring\nHoop of Fighting Focus\nRujarkian Meditation Gloves\nRuned Helm of Strategy\nSteel Leggings of Old Wars\n- Battle Fervor Stone [item=25792]\n- Boots of the Rujarkian Arena [item=25258]\n- Cap of the Elite Orcs [item=27782]\n- Cloak of the Fleeting Foot [item=27783]\n- Dented Gauntlets of Victory [item=57936]\n- Earring of Spirited Mind [item=63448]\n- Elite Steelslave Surgeon's Ring [item=55673]\n- Hoop of Fighting Focus [item=64768]\n- Leggings of Rejuvenation [item=25150]\n- Ring of Battle Readiness [item=24179]\n- Rujarkian Meditation Gloves [item=64285]\n- Rujarkian Ring of Strategy [item=57933]\n- Runed Helm of Strategy [item=61215]\n- Spaulders of Battle Rage [item=64174]\n- Steel Leggings of Old Wars [item=24989]\n- Wristguard of Battle Rage [item=27784]",
    },
  },
}
