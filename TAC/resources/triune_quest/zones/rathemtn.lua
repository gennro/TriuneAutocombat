-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for The Gilded Spire (rathemtn)
-- Total Quests: 4
-- ============================================================================

return {
  zone = "rathemtn",
  zone_name = "The Gilded Spire",
  quests = {
    {
      id = "13012",
      title = "Every Little Thing She Does Is Magic",
      exp = "31",
      exp_name = "The Outer Brood",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Fipnoc Birribit",
      loc = nil,
      triggers = {
        "Hail, Fipnoc Birribit",
        "Who is her?",
        "I can help gather knowledge.",
        "Where did you get that tool?",
        "How is this safer?",
        "Where can I find their studies?",
        "_Quests_",
        "her",
      },
      items_required = {
      },
      rewards = {
        { id = 151042, name = "Fresh Voidcrab Meat", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- The Gilded Spire [zone=1363]\n**Who:**\n- Fipnoc Birribit [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 110\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Experience\n- Money\n**Quest Items:**\n- Fresh Voidcrab Meat [item=151042]\n**Related Zones:**\n- The Harbinger's Cradle [zone=1361]\n**Related Quests:**\n- Far Flung Flora [quest=13014]\n- Partisan of The Gilded Spire (15 Points) [quest=13050]\n**Era:** | !The Outer Brood\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Mon Oct 28 01:43:35 2024\nModified: Sun Dec 22 20:22:02 2024 | | This task can be obtained from Fipnoc Birribit in The Guilded Spire at /way 148, 264, 3. Fipnoc is on the find tool CTRL F.\nYou say, 'Hail, Fipnoc Birribit'\nFipnoc Birribit is startled by your greeting. He clearly did not anticipate anybody speaking with him, let alone a hero of your magnitude. 'Oh thank the gods, I am glad to hear a word that I understand!' He turns and his gaze meets yours. He looks you over and blinks a few times when he sees that it is you who is speaking to him. You realize only too late that it wasn't so much a bunch of blinking but a gulp. 'I remember you, Gebb. I know of your work and of course you'd be the one who shows up here.' He looks toward the giant statue in the room next to him. 'It's like they worship... themselves? No, that's not correct. Oh, that's supposed to be her! They see her as a deity, they worship her. Everything they do, they do in [her] name.'\nYou say, 'Who is her?'\nFipnoc Birribit exclaims, 'Veeshan, of course!' He calms himself before continuing. 'Though to many I suppose this is pretty obvious.' He looks around the interior of the giant room you are in. 'Can you feel it in the air in this chamber, Gebb?' A feeling of pins prickling on the back of your neck has been growing since you entered this room. Now that Fipnoc has mentioned it, the feeling is even more intense to the point of almost unbearable. 'You feel it, I can see it in your eyes. I made it all the way to this chamber before I could sneak no further. This is where I need to ask for your help in gathering [knowledge] about the Aurelians.'\nYou say, 'I can help gather knowledge.'\nFipnoc Birribit says, 'My task is with the Wayfarers Brotherhood. Big surprise, I know. This time I am trying to learn two things. One being how they developed their magic, and the other is how they survived the voyage to Norrath. This is how I ended up in this room. The magical interference in this room can't be ignored. Somewhere in this chamber, there is magic being made. I suspect each of these rooms within this one house that information, but I cannot fight as well as you, and surely I would be found out if I was snooping around. The last time I was tasked with something like this, we just had a notebook to collect our findings. This time we have constructed a [tool] for documenting this sort of thing.'\nYou say, 'Where did you get that tool?'\nFipnoc Birribit says, 'You're not going to believe this, but it was the Ring of Scale that created this mystical tool for gathering information on how these invaders are able to manipulate magic to their benefit. Being dragons, they have the luxury of time on their side to learn and understand their spells. We do not have that kind of time. This device can record all of their records and store it. This is a [safer] way to gather the information than the classic 'Put it in your head and keep it there' system we use.'\nYou say, 'How is this safer?'\nFipnoc Birribit says, 'Well, we cannot tell how long they have been perfecting their magics. If one attempts to absorb all of it without any protection, it could both physically and metaphorically cause your head to explode. To avoid that violent reaction, the Ring of Scale created this... thing to gather the information we need to understand how they have been casting their magic. I need you to take this to their [studies] and collect as much information as it will allow.'\nYou say, 'Where can I find their studies?'\nYou have been assigned the task 'Every Little Thing She Does Is Magic'.\nYou have been given: Aureate Spell Scribe\nFipnoc Birribit says, 'This level feels like it will have all of the different schools of magic the Aureate have employed. Bring this device to each of the rooms and it will gather their records. You will notice they don't typically use tomes for their storage, but something else entirely. We will have to look into that later, but for now, let us gather as much as we can about their magic so we can increase our chances of victory. I'll remain here. As I said, I'm not much of a fighter. Good luck Gebb!'\n\n---\n\nFipnoc Blrrtblt has been tasked with collecting information about the magics that are employed by the Aurelian forces. He has given you a device for gathering this information for the Wayfarers Brotherhood as well as the Ring of Scale.\nTake the device to one of the magic studies rooms in this area and gather information on how the Aurelians perform their magics.\n1\\. Document how the invaders' healing magics work 0/1 The Gilded Spire\nThis step updates at /way 265, 164, 3 which is the room right near Fipnoc which is the big disco ball constellation room.\n2\\. Document how the invaders' controlling magics 0/1 The Gilded Spire\nThis step updates at /way 265, -165, 3 which is the room east of the first step.\n3\\. Document how the invaders' destruction magics 0/1 The Gilded Spire\nThis step updates at /way 604, 154, 4\n4\\. Document how the invaders' beneficial magics 0/1 The Gilded Spire\nThis step updates at /way 603, -170, 4\n5\\. Return the device to Fipnoc 0/1 The Gilded Spire\nYou offered 1 Aureate Spell Scribe to Fipnoc Birribit.\nYour task 'Every Little Thing She Does Is Magic' has been updated.\nFipnoc Birribit takes the device and his hand drops a bit, as he wasn't anticipating the weight of it. 'Wow, it's much heavier now! I bet this was a harrowing experience, but I am grateful for your help.' He stashes the device into a satchel that's strapped on his side. I'll bring this to the Wayfarers Brotherhood as soon as possible. I'm sure the Ring of Scale will also be interested in its contents, but they will get their turn after we take a look. Now, it's time for the next part. I was able to learn, as perhaps you already have, that the Aurelians use critters not so different from Norrathian crabs as one of their food sources. They seem to harvest these creatures in the area that they keep their transports. Head back to the Cradle and collect some meat from one of these crabs. I have a plan.'\nYou complete the trade with Fipnoc Birribit.\n6\\. Collect some voidcrab meat from The Harbinger's Cradle 0/1 The Harbinger's Cradle\nFresh Voidcrab Meat drops from the crabs in The Harbinger's Cradle.\n7\\. Deliver the crabmeat to Fipnoc 0/1 The Gilded Spire\nYou offered 1 Fresh Voidcrab Meat to Fipnoc Birribit.\nYou have been given: Tainted Voidcrab Meat\nYour task 'Every Little Thing She Does Is Magic' has been updated.\nFipnoc Birribit takes the meat you hand him and places it in a sack and begins to shake it. 'This is not the finest work I've done, certainly not my proudest. I have created a concoction that will poison anybody who eats it. Luckily, here seems to be the place where the invaders eat, but not their servants, so we don't have to worry about affecting those who are being oppressed by these monsters. Take this to the table that you noticed when you first entered. There is a pile of these crabs in the middle of the table. Sneak this in and it will begin to taint the rest of the meat. Then come back and let me know the job has been finished.' He looks sullen with what he just asked you to do.\nYou complete the trade with Fipnoc Birribit.\n8\\. Put the tainted meat in the food meant to the invaders 0/1 The Gilded Spire\nThis is the large pile of crab meat on the table. /target pile\nGet up underneath the table right under the pile, stand on the table leg that doesn't have a crystal on it, put the Tainted Voidcrab Meat on your cursor and type /usetarget\nIt should open up a trade window with it.\nYou offered 1 Tainted Voidcrab Meat to pile of crab.\npile of crab\nYou squeeze the wet meat out of the pouch and into the pile of crabs on the table. You notice the liquid inside is purple at first and then runs clear when it touches the fresh meat. The tainted meat appears to have done its job in tainting the meat around it. Head back to Fipnoc and let him know what you have done.\nYour task 'Every Little Thing She Does Is Magic' has been updated.\nYou complete the trade with pile of crab.\n9\\. Return to Fipnoc 0/1 The Gilded Spire\nYou say, 'Hail, Fipnoc Birribit'\nYour task 'Every Little Thing She Does Is Magic' has been updated.\nYou have helped Fipnoc document how the invaders have sculpted their magics so he can compare it with Norrath's magical studies. He also helped with the understanding of how the invaders fed themselves during their trip. This information is very useful in order to produce a counterattack.\nYou receive 2 silver .\nYou receive 1 gold .\nYou receive 267 platinum .\nYou have gained 1 mercenary ability point(s)! You now have 39 mercenary ability point(s).\nYou have gained 12 ability point(s)! You now have 250 ability point(s).\nYou must spend some of your ability points. You will no longer gain ability points.\nYou gain experience!\nFipnoc Birribit's expression is still dour, but he perks up a bit when he sees you. 'Thank you for that, Gebb. I'm not a fan of this strategy, but I had a job to do and it involves weakening the invading forces. I'll be able to sneak out of here on my own, but thank you for being able to do this for me today. I look forward to working with you again in the future. I have seen other Norrathians skulking around this area. Seek them out and they will more than likely also need your help. Again, thank you and see you around, Gebb.'\n\n---\n\nReward(s):\n267 platinum 1 gold 2 silver\nExperience\n**Submitted by:** Gidono",
    },
    {
      id = "13014",
      title = "Far Flung Flora",
      exp = "31",
      exp_name = "The Outer Brood",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Fipnoc Birribit",
      loc = nil,
      triggers = {
        "Hail, Fipnoc Birribit",
        "I",
        "_Quests_",
        "_Quests_",
        "gardens",
        "hail",
        "information",
        "deal with",
      },
      items_required = {
      },
      rewards = {
        { id = 149440, name = "Aureate Plant Pouch", type = "item" },
        { id = 149441, name = "Exotic Aureate Fungi", type = "item" },
        { id = 151046, name = "Fipnoc's Escape", type = "item" },
        { id = 151045, name = "Indexed Aureate Spell Scribe", type = "item" },
        { id = 151038, name = "Secured Aureate Plant Pouch", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- The Gilded Spire [zone=1363]\n**Who:**\n- Fipnoc Birribit [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 110\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Experience\n- Money\n**Quest Items:**\n- Aureate Plant Pouch [item=149440]\n- Exotic Aureate Fungi [item=149441]\n- Fipnoc's Escape [item=151046]\n- Indexed Aureate Spell Scribe [item=151045]\n- Secured Aureate Plant Pouch [item=151038]\n**Related Zones:**\n- The Theater of Eternity [zone=1359]\n**Related Creatures:**\n- Mokolin [ _Quests_]\n**Related Quests:**\n- Every Little Thing She Does Is Magic [quest=13012]\n- Eye Eye, Captain! [quest=13015]\n- Partisan of The Gilded Spire (15 Points) [quest=13050]\n**Era:** | !The Outer Brood\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Tue Oct 29 02:20:00 2024\nModified: Thu Feb 27 21:33:06 2025 | | **Prerequisite Task:** Every Little Thing She Does Is Magic [quest=13012]\n\n---\n\nThis task can be obtained from Fipnoc Birribit in The Guilded Spire at /way 148, 264, 3. Fipnoc is on the find tool CTRL F.\nYou say, 'Hail, Fipnoc Birribit'\nFipnoc Birribit clearly has something on his mind. His demeanor shows that he's dealing with the morality of his actions. You notice he perks up a bit when you speak to him, but not enough to remove the look of guilt he has. 'Oh, hey \\_\\_\\_\\_, I'm very glad you're still here. I have an extra task I could certainly use your expertise with. Now that we have an opportunity to gather more information about these invaders, I say we take it. Tell me \\_\\_\\_\\_, have you noticed that there are [gardens] inside this spire?'\nYou say, 'I've seen some of the gardens.'\nYou have been assigned the task 'Far Flung Flora'.\nFipnoc Birribit says, 'Excellent. You really can't miss them if you've been to the upper levels. I would like to ask you for a favor. Can you collect some of the plants that grow in different parts of the gardens? There are three different plants that you need to collect in order for us to get enough information about the flora that the Aurelians used for their journey. It makes sense that they would bring some of their plants with them. They appear to filter and clean the air similar to the trees on Norrath. To further understand their culture, take this sack and collect three different plants that are growing from the gardens here. Once you collect them, secure the sack and bring it back to me. I'll await your return.'\n\n---\n\nFipnoc Birribit has another task he has asked of you. He wants to collect some of the flora that the Aurelians brought with them. This information will be valuable in further understanding the invaders and how they traveled as far as they have.\nCollect three different plants from the garden areas.\n1\\. Locate the first plant in a garden area 0/1 The Gilded Spire\nExotic Aureate Fungi can be found up the ramp in a room with plants at the following locations\n/way 426, -298, 284\n/way 439, -266, 280\n/way 425, 317, 288\n/way 432, 292, 285\nIt is a ground spawn that looks like a white mushroom.\n2\\. Locate the second plant in a garden area 0/1 The Gilded Spire\nThis one looks like a bamboo. You can find these at\n/way 772, -354, 651\n/way 661, -491, 654\n/way 79, -392, 704\n/way 198, -508, 706\n/way 233, -598, 717\n3\\. Locate the third plant in a garden 0/1 The Gilded Spire\nThis one looks like a pumpkin. You can find these at\n/way 247, 548, 699\n/way 182, 495, 706\n/way 25, 335, 700\n/way 37, 417, 702\n/way 101, 482, 706\n4\\. Secure the exotic plants in the pouch Fipnoc gave you 0/1 The Gilded Spire\nTake the pouch Fipnoc gave you and put all 3 plants in it and combine to make Secured Aureate Plant Pouch.\nYou have fashioned the items together to create something new: Secured Aureate Plant Pouch.\nYour task 'Far Flung Flora' has been updated.\n5\\. Deliver the pouch to Fipnoc 0/1 The Gilded Spire\nYou offered 1 Secured Aureate Plant Pouch to Fipnoc Birribit.\nYou have been given: Indexed Aureate Spell Scribe\nYour task 'Far Flung Flora' has been updated.\nFipnoc Birribit carefully takes the sack from you when you hand it to him. 'Thank you for this, \\_\\_\\_\\_! We will be able to learn more about where the invaders hail from. It appears they come from a place that is very similar to Norrath in flora at least.' He looks a little embarrassed. 'I have one last task to ask of you. I need to get out of here and the Aurelians are on to the fact that we are in here. I know you are a capable fighter able to take care of yourself, but I'm not. I need you to meet with Mokolin. She's still on the tail of this beast we are in. Head back to her and bring her this device.' He pulls out the device you used to collect the magical studies of the Aurelians. 'She will have a teleportation device I can use to get to safety. Please hurry, \\_\\_\\_\\_. I don't know how much longer we can hide before getting caught.'\nYou complete the trade with Fipnoc Birribit.\n6\\. Deliver the spell scribe to Mokolin 0/1 The Theater of Eternity\nYou offered 1 Indexed Aureate Spell Scribe to Mokolin.\nYou have been given: Fipnoc's Escape\nYour task 'Far Flung Flora' has been updated.\nMokolin accepts the box that you hand her. She raises her eyebrows as her expression changes to amusement. 'I see. So you found one of our agents inside. Fipnoc does great work and this further proves how useful he is.' She smiles warmly as she holds the box under one arm. With her free hand, she reaches into a pocket in her robe. She produces a key that would hint that the pocket on this robe is much bigger on the inside. She hands it to you. 'This will help Fipnoc get out safely. Bring this to him as fast as you can. Thank you again, \\_\\_\\_\\_.'\nYou complete the trade with Mokolin.\n7\\. Return to Fipnoc with the key 0/1 The Gilded Spire\nYou offered 1 Fipnoc's Escape to Fipnoc Birribit.\nYour task 'Far Flung Flora' has been updated.\nYou were able to help Fipnoc gather extra intel about the invaders in the form of their flora that they kept inside the Gilded Spire. He is also safer because of you now that he has a way to leave the spire undetected with a teleportation device given to him by the Ring of Scale.\nYou receive 2 silver .\nYou receive 1 gold .\nYou receive 267 platinum .\nYou gain experience!\nFipnoc Birribit greedily takes the key from you and clutches it to his chest with both hands. He looses a sigh of relief before speaking to you. \"Thank you, thank you, thank you, \\_\\_\\_\\_! I can safely get out of here and put this nonsense behind me.' He regains his composure and stares at you for a moment before realizing that you have to find your own way out. 'Sorry, I'm just not built for this kind of work. I need to get my feet back on the ground as soon as possible. I thank you for all of your help today, \\_\\_\\_\\_'\nYou complete the trade with Fipnoc Birribit.\n\n---\n\nReward(s):\n267 platinum 1 gold 2 silver\nExperience\n**Submitted by:** Gidono",
    },
    {
      id = "10306",
      title = "Barracks and Books",
      exp = "02",
      exp_name = "The Scars of Velious",
      min_lvl = 35,
      max_lvl = 40,
      quest_type = "Quest",
      repeatable = true,
      group_size = "Solo",
      npc = "Delila",
      loc = { y = 4342.0, x = 844.0, z = 0.0 },
      triggers = {
        "Hail, Delila",
        "tasks",
        "task",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "**Level:** 35\n**Maximum Level:** 40\n**Monster Mission:** No\n**Repeatable:** Yes\n**Can Be Shrouded?:** No\n**Quest Type:** Quest\n**Group Size:** Solo\n\nThis starts with Delila in The Rathe Mountains. She is located in the Northwest part of the zone at /loc 4342, 844 inside of an inn. She is on the find tool CTRL F.\nYou say, 'Hail, Delila'\nDelila says, 'Do you see where we are? There's not a lot for a girl to do way out here other than keep herself busy by handing out [tasks] to the passersby. I just hope someone will take me up on some of them so I don't get overworked!'\nYou say, 'tasks'\nYou have been assigned the task 'Barracks and Books'.\nThey might as well call you a scout, because you'll be going out and doing some scouting on some very high-profile sites. These sites are rumored to be burial grounds for priests of an ancient civilization, but ther's not much more information on them than that. Enough delay, get going and explore the pillars where you find the undead lair.\n- 1. Explore the Kejek town barracks 0/1 The Stonebrunt Mountains\n- 2. ??? ???\n- 3. ??? ???\nReward(s):\nAt level 39,\n14pp 8g, 9s, 6cp\nExperienceSubmitted by: GidonoRewards:\n[",
    },
    {
      id = "10308",
      title = "Bold, Bold Kobolds",
      exp = "02",
      exp_name = "The Scars of Velious",
      min_lvl = 35,
      max_lvl = 40,
      quest_type = "Quest",
      repeatable = true,
      group_size = "Solo",
      npc = "Delila",
      loc = { y = 4342.0, x = 844.0, z = 0.0 },
      triggers = {
        "Hail, Delila",
        "tasks",
        "task",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "**Level:** 35\n**Maximum Level:** 40\n**Monster Mission:** No\n**Repeatable:** Yes\n**Can Be Shrouded?:** No\n**Quest Type:** Quest\n**Group Size:** Solo\n\nThis starts with Delila in The Rathe Mountains. She is located in the Northwest part of the zone at /loc 4342, 844 inside of an inn. She is on the find tool CTRL F.\nYou say, 'Hail, Delila'\nDelila says, 'Do you see where we are? There's not a lot for a girl to do way out here other than keep herself busy by handing out [tasks] to the passersby. I just hope someone will take me up on some of them so I don't get overworked!'\nYou say, 'tasks'\nYou have been assigned the task 'Bold, Bold Kobolds'.\nThe only road left for someone like you is the road less traveled. It's high time you extended your reach, which is why you should take this opportunity to explore the kobold camp east and north of the Warrens. Heck, you might even enjoy the adventure.\n- 1. Explore the kobold camp east and north of the Warrens 0/1 The Stonebrunt Mountains\n- 2. ??? ???\n- 3. ??? ???\nReward(s):\nAt level 39,\n14pp 8g 9s 6cp\nExperienceSubmitted by: GidonoRewards:\n[",
    },
  },
}
