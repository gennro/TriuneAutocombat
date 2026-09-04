-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for Butcherblock Mountains (butcher)
-- Total Quests: 2
-- ============================================================================

return {
  zone = "butcher",
  zone_name = "Butcherblock Mountains",
  quests = {
    {
      id = "4168",
      title = "LDoN Raid: Mistmoore Catacombs: Scion Lair of Fury",
      exp = "06",
      exp_name = "Lost Dungeons of Norrath",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Glopruk Tigglum",
      loc = { y = -1145.0, x = -2505.0, z = 0.0 },
      triggers = {
        "Hail, Glopruk Tigglum",
        "What problem?",
        "I am interested.",
        "_Raid Recruiter_",
        "problem",
        "interested",
        "hail",
      },
      items_required = {
        { name = "a lockout", count = 1 },
      },
      rewards = {
        { id = 25944, name = "Bloodied Gravestone Fragment", type = "item" },
        { id = 24828, name = "Bloodied Scion Wristband", type = "item" },
        { id = 25591, name = "Bloodstone of Enhanced Protection", type = "item" },
        { id = 24903, name = "Enchanted Chunk of Graying Flesh", type = "item" },
        { id = 25000, name = "Gargoyle's Stone of Vitality", type = "item" },
        { id = 24993, name = "Gem of Burning Rage", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Butcherblock Mountains [zone=57]\n**Who:**\n- Glopruk Tigglum [ _Raid Recruiter_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 65\n**Maximum Level:** | 130\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Expedition\n**Quest Goal:**\n- Loot\n**Success Lockout Timer**: 108:00:00\n**Related Zones:**\n- Mistmoore Catacombs: Scion Lair of Fury (Raid) [zone=511]\n**Related Creatures:**\n- Elite Scion Guardian [npc=15219]\n- Grortrakien the Mutilator [npc=25530]\n- Grortrakien`s Preserved Chest [npc=33950]\n- Halusant the Nightblood [npc=17038]\n- Halusent`s Clawed Chest [npc=33947]\n- Sfisithik the Light Devourer [npc=15609]\n- Sfisithik`s Shadowy Chest [npc=33948]\n- The Chest of the Scions [npc=33949]\n**Era:** | !Lost Dungeons of Norrath\nRecommended:\n**Group Size:** | Raid\n**Min. # of Players:** | 6\n**Max. # of Players:** | 54\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Tue Apr 10 04:00:51 2007\nModified: Tue Jun 23 19:54:30 2026 | | Glopruk Tigglum may be found at the Wayfarers Camp at -1145, -2505.\nYou say, 'Hail, Glopruk Tigglum'\nGlopruk Tigglum says 'Me hate dem vampires over in doze dark catacombs. They do have some of de shiny tings though. Me seen lots of dem come through here. I mean shiny tings, not vampires. My new friends have lots of work to do. If youz can rally de call of your friend perhaps youz can help us wit a serious [problem].'\nYou say, 'What problem?'\nGlopruk Tigglum says 'One of de rogues heard dat Valdoon Kel'Novar, a Trueborn, was on his way to de rocky summoning place to make an army of gargoyles to do de Trueborn's biddin'. If he make dat stony army, de Trueborn can rule over de rest of Mayong Mistmoore's Progeny. We can't let dat happen, see? You gonna need lots of help. Are youz [interested]?'\nYou say, 'I am interested.'\nGlopruk Tigglum says 'Bring back de shiny tings for me!'\nHead to the Lesser Faydark and zone in from there.\nYou have entered Mistmoore's Catacombs: Scion Lair of Fury.\nClear the zone as you go in. Kill all trash, particularly the ones named Elite Scion Guardian, which are mini-bosses and have much more HP than regular trash. You should end up with only Sfisithik the Light Devourer (in the southeast-most room) and Halusant the Nightblood (in the southmost room).\nSplit your raid force and engage both; if you only kill one at a time, the mob will heal itself to full. As the fight progresses, several Hissing Shadow Lurker appear in Sfisithik's room and add; these must be controlled or killed. There were no adds in Halusant's room.\nAfter the two bosses (and the Hissing adds) are dead, head to the square room just north of Halusant. You will find four chests. Break them open (melee them) and get your loot inside.\nThis expedition does not give a lockout.\nGetting all 4 chests will net you the following\n1 Item from Sfisithik's Shadowy Chest\nGem of Burning Rage\nHelm of Bloodlust\nShield of Restlessness\nSharp Gravestone Shard\n2 Items from Grortrakien's Preserved Chest (can be duplicate)\nBloodied Gravestone Fragment\nGlowing Ring of Eternal Slumber\nMummy's Stone of Fury\nRuby of Bloody Vengeance\n2 Items from Halusent's Clawed Chest (can be duplicate)\nEnchanted Chunk of Graying Flesh\nGargoyle's Stone of Vitality\nMummy's Bone Earring\nTranslucent Orb of Trapped Mana\n1 Item from The Chest of the Scions\nBloodstone of Enhanced Protection\nGravestone Fragment of Protection\nScion's Shard of Death Chants\nBloodied Scion Wristband\n**Submitted by:** KyrosKrane\n- Bloodied Gravestone Fragment [item=25944]\n- Bloodied Scion Wristband [item=24828]\n- Bloodstone of Enhanced Protection [item=25591]\n- Enchanted Chunk of Graying Flesh [item=24903]\n- Gargoyle's Stone of Vitality [item=25000]\n- Gem of Burning Rage [item=24993]\n- Glowing Ring of Eternal Slumber [item=24902]\n- Gravestone Fragment of Protection [item=24904]\n- Helm of Bloodlust [item=24901]\n- Mummy's Bone Earring [item=24992]\n- Mummy's Stone of Fury [item=25096]\n- Ruby of Bloody Vengeance [item=25947]\n- Scion's Shard of Death Chants [item=25095]\n- Sharp Gravestone Shard [item=63210]\n- Shield of Restlessness [item=25683]\n- Translucent Orb of Trapped Mana [item=25386]",
    },
    {
      id = "8215",
      title = "Reading is Fundamental",
      exp = "01",
      exp_name = "The Ruins of Kunark",
      min_lvl = 12,
      max_lvl = 125,
      quest_type = "Task",
      repeatable = false,
      group_size = "Solo",
      npc = "Atwin Keladryn",
      loc = nil,
      triggers = {
        "Hail, Atwin Keladryn",
        "tasks",
        "Hail, Mallagan Vergoo",
        "task",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "**Level:** 12\n**Maximum Level:** 125\n**Monster Mission:** No\n**Repeatable:** No\n**Can Be Shrouded?:** No\n**Quest Type:** Task\n**Group Size:** Solo\n\nYou say, 'Hail, Atwin Keladryn'\nAtwin Keladryn says 'What are you looking at? Yeah, I'm a half elf, so what? I'm only here because my father is off gallivanting around looking for treasure off in some hidden dungeons somewhere. I wish I could have gone. It sounds like more fun than 'holding down the fort,' as he called it. He asked me to keep some of the local ruffians busy with some [tasks], but I don't see any reason why you can't help, that is, if you're interested.'\nYou say, 'tasks'\nYou have been assigned the task 'Reading is Fundamental'.\n- Explore the goblin camp to the south - Butcherblock Mountains\nYour task 'Reading is Fundamental' has been updated.\nYour Location is -2024.16, -179.24, 0.66\n- Explore the North side of the library basement - Plane of Knowledge\nYour task 'Reading is Fundamental' has been updated.\nYour Location is 73.97, 804.35, -59.94\n- Speak with Mallagan Vergoo - The Field of Bone\nYour Location is -1869.18, 1366.26, -12.90\nYou say, 'Hail, Mallagan Vergoo'\nYour task 'Reading is Fundamental' has been updated.\nSadly, you couldn't find any plots of land that were suitable for living, but don't fret. It wasn't your fault, just the fault of overused land that hasn't been taken care of nearly well enough. In any case, here's your finder's fee, even though you didn't exactly find anything. Your services may be called upon again soon, and if they are, try not to disappoint, okay?\nYou receive 3 copper .\nYou receive 3 silver .\nYou receive 4 gold .\nYou receive 1 platinum .\nYou have gained a level! Welcome to level 14!\nYou gain experience!!\nMallagan Vergoo says 'Thanks for contacting me, Bamfusara. Your information on this matter has been most useful.'Submitted by: bamfeakRewards:\n[",
    },
  },
}
