-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for Basilica of Adumbration (basilica)
-- Total Quests: 4
-- ============================================================================

return {
  zone = "basilica",
  zone_name = "Basilica of Adumbration",
  quests = {
    {
      id = "10507",
      title = "Seek and Ye Shale Find",
      exp = "28",
      exp_name = "Terror of Luclin",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Ceesil Ahdai",
      loc = nil,
      triggers = {
        "Hail, Ceesil Ahdai",
        "Why have you come to such a dangerous place?",
        "What is that supposed to mean?",
        "Slip through to get...?",
        "I can help smash a few stonegrabbers.",
        "_Quests_",
        "place",
        "What",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Basilica of Adumbration [zone=1280]\n**Who:**\n- Ceesil Ahdai [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 115\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n- Money\n**Related Creatures:**\n- an onyx stonegrabber [npc=56810]\n**Related Quests:**\n- Mercenary of Basilica of Adumbration (10 Points) [quest=10585]\n**Era:** | !Terror of Luclin\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Fri Oct 22 01:43:24 2021\nModified: Tue Dec 5 05:21:04 2023 | | **Terror of Luclin Info & Guides: Overview \\| Progression & Task List \\| Raiding \\| Visible Armor**\n\n---\n\nYou can obtain this quest from Ceesil Ahdai in Basilica of Adumbration near the zone out to Shadow Valley. He is on the Find tool (Ctrl+F).\nYou say, 'Hail, Ceesil Ahdai'\nCeesil Ahdai stiffens and flattens his ears when he notices you. 'Gods, you can't just waltz in and say hello to everyone you see.' He crooks a claw at you, beckoning you closer, and lowers his voice to a whisper. 'Stay quiet lest the gargoyles notice you and alert everything in this wretched [place]. It's hard to keep a low profile in here, especially when you can't even trust the shadows to hide you.'\nYou say, 'Why have you come to such a dangerous place?'\nCeesil Ahdai narrows his eyes and lets out a soft, hissing sigh. 'Just my luck, I run into a chatterbox like you in one of the most perilous places on Luclin.' He taps a claw against his chin, deep in thought. 'Though, perhaps there's a way we could work together. [What] with your talent for... attracting attention.'\nYou say, 'What is that supposed to mean?'\nCeesil Ahdai says, 'It was a compliment, wasn't it? There are many guards and servants roaming the Basilica and you're the perfect person to start a little mayhem. You rough up a few of Luclin's denizens while I [slip] through the cracks, get what I want, and get out. There's some coin in it for you if you're willing to help.'\nYou say, 'Slip through to get...?'\nCeesil Ahdai says, 'Secrets. I'm in the business of being in other people's business. Everyone has something to hide, and there is always someone willing to pay for that information. There's no finer place to gather secrets than from Luclin's servants themselves, or better yet: her prisoners. While you distract some of the [stonegrabbers], I'll make my rounds and gather what information I can.'\nYou say, 'I can help smash a few stonegrabbers.'\nCeesil Ahdai says, 'Excellent. The main hall, to my right and through the doors, is crawling with them. You can probably find them by listening for the sounds of their clumsy, lumbering footsteps. I have the utmost confidence that you'll be able to shatter them into pebbles. Let's meet back here when you've finished.'\nYou have been assigned the task 'Seek and Ye Shale Find'.\n\n---\n\n1\\. Rid the basilica of stonegrabbers 0/8 Basilica of Adumbration\n> **Quest Text:** Ceesil Ahdai is a somewhat shady and impatient rogue who makes his living off selling secrets. He seeks to learn something new and tantalizing by eavesdropping on the private affairs of Luclin's denizens. Ceesil needs help slipping by the servants and guards in his way.\n>\n> The stonegrabbers make up the first line of defense for the Basilica. Eliminate stonegrabbers so that Ceesil can prowl through the halls unseen\n\n---\n\nReward(s):\nMoney for your level\n**Submitted by:** Gidono",
    },
    {
      id = "10508",
      title = "When Soul Meets Soul",
      exp = "28",
      exp_name = "Terror of Luclin",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "The Anchored Spirit",
      loc = { y = -311.0, x = 51.0, z = -118.0 },
      triggers = {
        "Hail, The Anchored Spirit",
        "I don",
        "It could be.",
        "I",
        "What did you do when you found the wizard?",
        "What did you see?",
        "Let",
        "Do you know which of the oubliettes is correct?",
      },
      items_required = {
        { name = "him a small bit of strength during this ordeal", count = 1 },
        { name = "back Sefra's Necklace to The Anchored Spirit", count = 1 },
      },
      rewards = {
        { id = 142629, name = "Sefra's Necklace", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Basilica of Adumbration [zone=1280]\n**Who:**\n- The Anchored Spirit [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 115\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n- Experience\n- Money\n**Success Lockout Timer**: 01:00:00\n**Quest Items:**\n- Sefra's Necklace [item=142629]\n**Related Creatures:**\n- Olyam Banock [npc=56846]\n**Related Quests:**\n- Partisan of Basilica of Adumbration (10 Points) [quest=10586]\n**Era:** | !Terror of Luclin\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Fri Oct 22 02:17:01 2021\nModified: Thu Jun 5 09:20:21 2025 | | **Terror of Luclin Info & Guides: Overview \\| Progression & Task List \\| Raiding \\| Visible Armor**\n\n---\n\nYou can obtain this quest from The Anchored Spirit in Basilica of Adumbration one floor down from the base floor at -311, 51, -118. You can find it on the Find tool (Ctrl+F).\nYou say, 'Hail, The Anchored Spirit'\nThe Anchored Spirit glitters and floats above the table. Upon hearing your voice, it glows more strongly. It drifts toward you and bobs up and down, as though in greeting. It seems to be straining to get closer, but is unable to. A weak magical aura seems to be compelling you to [touch] the spirit.\nYou say, 'I don't know if this is the best idea, but I'll touch the spirit.'\nThe Anchored Spirit feels warm against your hand and silently throbs like the beating of a heart. A deluge of emotions seizes you at once; fear, pain, grief, confusion. As it ebbs, you hear a woman's voice echo in your mind. It is taut and raspy, as though she has not spoken in some time. 'You are not a tekuel, and you are not an akheva.... [could] it be that someone brave enough and strong enough has finally managed to infiltrate this prison? Not only that, but you can feel my emotions and hear my voice?'\nYou say, 'It could be.'\nThe Anchored Spirit seems to pulse with more vigor than before. 'My name is Sefra Terrilon and I've been stuck in this abysmal place for... I'm not sure how long. I was killed and, as luck would have it, the necklace I was wearing is a spirit anchor. My essence has been tethered to this piece of jewelry, discarded here, and forgotten about. How ironic that although I was murdered rather than captured, I'm still a prisoner in Luclin's Basilica. I've been able to perceive the world around me this entire time, but too weak to move away from the proximity of this necklace. Would you [humor] me and hear my story? Or shall I [cut to the chase]? I have a somewhat selfish request, if you are willing to help.'\nYou say, 'I'll humor you.'\nThe Anchored Spirit warms once again against your palm. 'I'm grateful. It's been a long time since I've had a conversation with anything outside of my imagination. Originally, I travelled here on a rescue mission. My lover, Olyam Banock, and his companions were seeking new adventures. They sought the help of a wizard who could teleport them to Luclin. That disgraceful wizard teleported the group but stayed behind on Norrath, stranding my friends here.' You can feel Sefra's anger like flames licking at your consciousness. 'I gathered members of both our families, and found the [wizard] myself.'\nYou say, 'What did you do when you found the wizard?'\nThe Anchored Spirit feels almost hot to the touch. 'Let's just say I persuaded him to teleport all of us to Luclin. Him included. Not long after arriving, we were beset by vicious creatures. We put up a good fight; even the wizard pulled his weight. But, tired of our battles, Luclin herself sent the tekuel to hunt us. The tekuel are merciless and sadistic creatures. All of us were slaughtered. Torn into by the tekuel's claws, I remember feeling pain and a creeping darkness... Then suddenly, the feeling was gone. I could [see] again, but not from my body. I could see from the perspective of this necklace.'\nYou say, 'What did you see?'\nThe Anchored Spirit throbs, oscillating between a bright and dim aura. 'The tekuel took the necklace from my body and brought it here. I saw Olyam trapped in a prison cell made of pure light. The tekuel taunted Olyam by showing him this necklace and recounting the details of my death.' Sefra's voice falters. 'Any pride or defiance left in my dear Olyam extinguished instantly. He was utterly broken. The tekuel hoard trophies of their conquests, and eventually my necklace was tossed into this room and forgotten about. If I may [cut to the chase], I have a request for you.'\nYou say, 'Let's cut to the chase, then.'\nThe Anchored Spirit says, 'My beloved Olyam is here, in one of the [oubliettes] that hold Luclin's prisoners. Please help me find which one. If you can bring this necklace close enough to his cell, I think I'll be able to communicate with him the same way I am communicating with you. I just want closure for both of us. I hope that a final goodbye will help put Olyam's mind at ease and give him a small bit of strength during this ordeal. Perhaps I will be able to pass on once my soul is at peace. It would be a lot better than being stuck here for eternity.'\nYou say, 'Do you know which of the oubliettes is correct?'\nThe Anchored Spirit surrounds your hand with a bright, sparkling light. 'You'll have to do a little exploring. The oubliettes surround platforms made of pure shadow, located at the back of each floor. I believe Olyam is either on the first or second level. If you take my necklace across the threshold of these platforms, I can tell you whether I sense his presence nearby. You will undoubtedly have to fight your way through some guards, but I feel like I can count on you.'\nYou have been assigned the task 'When Soul Meets Soul'.\nYou are given: Sefra's Necklace [item=142629]\nYour task 'When Soul Meets Soul' has been updated.\n\n---\n\n1\\. Carry Sefra's necklace in your bag 0/1 Basilica of Adumbration\nThis step updates as it gives you the Necklace when given this quest.\n> **Quest Text:** You've found a spirit anchor that tethers Sefra Terrilon's soul to a necklace she was wearing before she was killed. She feels that she cannot peacefully pass on until she has said a final, proper farewell to her lover Olyam Banock. Sefra has enlisted you in helping her find Olyam and bring her spirit to rest.\n>\n> Olyam is being held in a oubliette surrounding one of the three shadow platforms in the Basilica. Sefra's necklace will be able to sense which platform is correct once you cross into the threshold.\n2\\. Search for Olyam at the shadow platforms 0/1 Basilica of Adumbration\nOlyam Banock [npc=56846] is found on the topmost floor. Take the stairs next to Ceesil and go up one floor. Then east out to the platforms, up to the north platform and then the first to the east.\nTrying to walk from the central platform to the outer platforms keeps porting you back to the center. You can levitate and run OR if you move your camera right in 3rd person you can see below the side of the platform there's a Shadow Rectangle shape there, click on that, wait and it will extend a barely visible bridge out, on the other side there's a Gem that will pull out and in the bridge. The mobs on the pedestals are KOS and see through invis, respawn timer roughly 10 min.\nAs soon as you get near him, the step updates.\n3\\. Find Olyam's oubiiette 0/1 Basilica of Adumbration\n4\\. Speak to Olyam so that he can commune with Sefra's necklace 0/1 Basilica of Adumbration\nYou say, 'Hail, Olyam Banock'\nYour task 'When Soul Meets Soul' has been updated.\nOlyam Banock looks at you in disbelief. 'Is that really Sefra's voice I hear? She's speaking to me through her necklace?' He closes his eyes and a fond smile lights up his face. You can feel Sefra's necklace nearly buzzing with excitement. Though it is silent, you know the two are speaking telepathically.\n5\\. Return the necklace to the Sefra's anchored spirit 0/1 Bascilica of Adumbration\nGive back Sefra's Necklace to The Anchored Spirit.\nYour task 'When Soul Meets Soul' has been updated.\nThe spirit once again seems to be straining toward you. It appears that Sefra has more to speak with you about.\nYou receive 2 platinum .\nYou gain experience!\nYou light a firework.\n\n---\n\nReward(s):\nMoney\nExperience based on your level\n**Submitted by:** Gidono, Veludeus",
    },
    {
      id = "10703",
      title = "All Right Then, Keep Your Secrets",
      exp = "28",
      exp_name = "Terror of Luclin",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Ceesil Ahdai",
      loc = nil,
      triggers = {
        "_Quests_",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "**Status: Incomplete**\n\nQuest Started By: | Description:\n**Where:**\n- Basilica of Adumbration [zone=1280]\n**Who:**\n- Ceesil Ahdai [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 115\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n**Related Creatures:**\n- a shrewd abettor of Luclin [npc=56811]\n- a tireless attendant of Luclin [npc=56823]\n- an obedient servant of Luclin [npc=56837]\n**Related Quests:**\n- Mercenary of Basilica of Adumbration (10 Points) [quest=10585]\n**Era:** | !Terror of Luclin\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Sat Dec 18 21:10:09 2021\nModified: Tue Dec 5 05:21:04 2023 | | **Terror of Luclin Info & Guides: Overview \\| Progression & Task List \\| Raiding \\| Visible Armor**\n\n---\n\nThis is the second Mercenary task for Basilica of Adumbration. You can obtain this quest from Ceesil Ahdai in Basilica of Adumbration near the zone out to Shadow Valley. He is on the Find tool (Ctrl+F).\nPrerequisite: Seek and Ye Shale Find [quest=10507] (first Mercenary task)\n- 1\\. Rid the basilica of servants of shadow 0/8 Basilica of Adumbration\nKill any of these:\n\\- a shrewd abettor of Luclin [npc=56811]\n\\- a tireless attendant of Luclin [npc=56823]\n\\- an obedient servant of Luclin [npc=56837]\n( **any others ?**)\nReward(s):\n141 platinum 6 gold 6 silver 7 copper\n**Submitted by:** Gidono",
    },
    {
      id = "10705",
      title = "Hope May Vanish But Cannot Die",
      exp = "28",
      exp_name = "Terror of Luclin",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "The Anchored Spirit",
      loc = { y = -310.0, x = 55.0, z = -124.0 },
      triggers = {
        "_Quests_",
      },
      items_required = {
      },
      rewards = {
        { id = 143032, name = "Bundle of Votive Offerings", type = "item" },
        { id = 142629, name = "Sefra's Necklace", type = "item" },
      },
      factions = {
      },
      walkthrough = "**Status: Incomplete**\n\nQuest Started By: | Description:\n**Where:**\n- Basilica of Adumbration [zone=1280]\n**Who:**\n- The Anchored Spirit [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 115\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n- Experience\n- Money\n**Success Lockout Timer**: 01:00:00\n**Quest Items:**\n- Bundle of Votive Offerings [item=143032]\n- Sefra's Necklace [item=142629]\n**Related Quests:**\n- Partisan of Basilica of Adumbration (10 Points) [quest=10586]\n**Era:** | !Terror of Luclin\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Sat Dec 18 21:24:34 2021\nModified: Sun Sep 14 07:48:49 2025 | | **Terror of Luclin Info & Guides: Overview \\| Progression & Task List \\| Raiding \\| Visible Armor**\n\n---\n\nThis task starts with The Anchored Spirit [npc=56847] which can be found at -310,+55,-124 from the zone in from Shadow Valley go south until stairs lead you down. Go down the stairs, this NPC is up against the stairs on the floor below.\nRequest phrase is **reunite**.\nYou receive Sefra's Necklace [item=142629] and Bundle of Votive Offerings [item=143032].\n\n---\n\n1\\. Take the possessions of Sefra's companions 0/1 Basilica of Adumbration\n2\\. Carry Sefra's necklace in your bag 0/1 Basilica of Adumbration\n3\\. Locate the cave where Sefra's body is hidden 0/1 Shadow Valley\nThe cave is in Shadow Valley a bit east-southeast of the center of zone.\n4\\. Find Sefra's Body 0/1 Shadow Valley\n5\\. Place Sefra's necklace on her body 0/1 Shadow Valley\n6\\. Place the votive offerings around Sefra's body 0/1 Shadow Valley\n\n---\n\nReward(s):\n354 platinum 1 gold 6 silver 7 copper\nYou gain experience!\n**Submitted by:** Gidono",
    },
  },
}
