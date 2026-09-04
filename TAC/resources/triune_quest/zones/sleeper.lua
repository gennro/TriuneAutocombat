-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for Sleeper's Tomb (sleeper)
-- Total Quests: 6
-- ============================================================================

return {
  zone = "sleeper",
  zone_name = "Sleeper's Tomb",
  quests = {
    {
      id = "10150",
      title = "Drakes! Why'd it Have to be Drakes?",
      exp = "27",
      exp_name = "Claws of Veeshan",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Qabruh - CoV",
      loc = nil,
      triggers = {
        "Hail, Qabruh",
        "something",
        "confusing",
        "device",
        "strange",
        "_Quests_",
      },
      items_required = {
        { name = "me stranger", count = 1 },
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Sleeper's Tomb [CoV]\n**Who:**\n- Qabruh - CoV [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 100\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Quest\n**Quest Goal:**\n- Advancement\n**Related Quests:**\n- Mercenary of The Sleeper's Tomb (10 Points) [quest=10284]\n**Era:** | !Claws of Veeshan\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Fri Oct 30 03:52:55 2020\nModified: Tue Dec 5 05:21:04 2023 | | **Claws of Veeshan Info & Guides: Overview \\| Progression & Task List \\| Raiding \\| Visible Armor**\n\n---\n\n**Prerequisite Quests:** None.\nYou can obtain this quest from NPC in Zone. You can find him/her at /loc lochere and is on the find tool CTRL F.\nYou say, 'Hail, Qabruh'\nQabruh says, 'H...Hail? Yes, yes that is how we greet each other, that feels correct, that feels right. Forgive me stranger, I'm...new? No, that isn't right either. I must thank you for taking the time to speak to me, the others who have entered would take one look at me and run in the other directions. I needed to talk to someone before I leave this place, but [something] is telling me that I cannot leave.'\nYou say, 'something'\nQabruh says, 'This place has immense power, I can feel it within my core, my body almost feels as if it is vibrating. It feels as if it is being pulled in a specific direction. Something very powerful wants me to be here, or was it to send a message? Everything is still very [confusing] right now'\nYou say, 'confusing'\nQabruh says, 'Yes, the last thing I remember was being in that accursed tower. Then, in the next moment, all I could hear was a constant voice telling me to 'come home', except it spoke a language I don't understand. I just, felt that I needed to return to this place, and then I woke up within the chamber of a strange [device].'\nYou say, 'device'\nQabruh says, 'Correct, I woke up there, well my mind did, and then I was put into the body you see before you now. Something [strange] is happening here and I feel as though we must investigate it.'\nYou say, 'strange'\nYou have been assigned the task 'Drakes! Why'd it Have to be Drakes?'.\n\n---\n\n**Task Window Text:** The drakes have been pouring back into Sleeper's Tomb. Qabruh has a dire request.\n1\\. Clear out the Drakes 0/7 The Sleeper's Tomb\n\n---\n\nReward(s):\n?\n**Submitted by:** Gidono",
    },
    {
      id = "10151",
      title = "Wipe Your Feet",
      exp = "27",
      exp_name = "Claws of Veeshan",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Glorifying Saffron Ash - CoV",
      loc = { y = -2375.0, x = -730.0, z = -990.0 },
      triggers = {
        "Hail, Glorifying Saffron Ash",
        "goals",
        "door",
        "companion",
        "_Quests_",
      },
      items_required = {
      },
      rewards = {
        { id = 140131, name = "Badly Needed Supplies", type = "item" },
        { id = 140295, name = "Burrower Excrement", type = "item" },
        { id = 140299, name = "Foul Smelling Paste", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Sleeper's Tomb [CoV]\n**Who:**\n- Glorifying Saffron Ash - CoV [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 100\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Quest\n**Quest Goal:**\n- Advancement\n- Experience\n- Money\n**Quest Items:**\n- Badly Needed Supplies [item=140131]\n- Burrower Excrement [item=140295]\n- Foul Smelling Paste [item=140299]\n**Related Zones:**\n- Western Wastes [CoV]\n**Related Creatures:**\n- a tunnel burrower - CoV [npc=56161]\n**Related Quests:**\n- Partisan of The Sleeper's Tomb (10 Points) [quest=10285]\n**Era:** | !Claws of Veeshan\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Fri Oct 30 04:44:08 2020\nModified: Tue May 20 14:22:40 2025 | | **Claws of Veeshan Info & Guides: Overview \\| Progression & Task List \\| Raiding \\| Visible Armor**\n\n---\n\n**Prerequisite Quests:** None.\nYou can obtain this quest from NPC in Zone. You can find him/her at /loc lochere and is on the find tool CTRL F.\nYou say, 'Hail, Glorifying Saffron Ash'\nGlorifying Saffron Ash says, 'You there, adventurer, how fares your quests in this sanctuary? Mayhap we can work together to achieve our [goals].'\nYou say, 'goals'\nGlorifying Saffron Ash says, 'Indeed. As you know, this place is being protected by some terrible magic, and I want to figure out what that magic is. I know that it is emanating from the chamber deep within the tomb, but the [door] that is barring us from getting inside has been sealed and we can't get past it. We know that there is something in there that needs to be destroyed. '\nYou say, 'door'\nGlorifying Saffron Ash says, 'The door in the basement of this tomb has been sealed shut by the dragons who are a part of some ritual. We need to figure out how to get past it so that we can destroy whatever is happening inside. My [companion] and I have been trying to get past the monsters here to get to the door, but it has proven more difficult than originally anticipated.'\nYou say, 'companion'\nYou have been assigned the task 'Wipe Your Feet'.\nGlorifying Saffron Ash continues with a concerned look, 'Their name is Smirnoth Icemir and they are already trying to find a safe way to get to the door, but they have yet to report back. I have faith in their abilities, but I would be a liar if I didn't say I was worried. Try to find them and make sure they are safe. Here,' he pulls out a satchel, 'they may need some extra supplies to get them to a safe place. Bring this to them and see what they have found. The last I heard; they were going to attempt to sneak down using a stairwell. That might be a good place to start.'\n\n---\n\n**Task Window Text:** Glorifying Saffron Ash is trying their luck at getting the door open to the chamber where the Sleeper once stood. It is apparent to them that this is the epicenter of the plague that is haunting Velious. They will need some research before they can enact their plan.\n1\\. Bring the supplies to Smirnoth Icemir 0/1 The Sleeper's Tomb\n> **Task Window Text:** Smirmoth Icemir is working with Glorifying Saffron Ash to attempt to get access tot he chamber but has lost contact along the way. Locate them somewhere in the Sleeper's Tomb and bring them the bag of supplies.\nSmirnoth Icemir gives you a look of relief as you approach them, 'Are you a sight for sore eyes you magnificent person! Praise the gods!' They snatch the satchel from you and immediately start eating rations. They indulge in the rations in a way that suggests that they have been down here for a while. With food still in their mouth, they being to speak to you again, 'Right, sorry about that,' they finish their last bite and wipe the crumbs from their lips before they continue. 'As you can see, I've been down here for a bit trying to find a way to the chamber where the Sleeper once was. I have enough to get back out of here now, but you will need to inspect the door in my stead. I'm just simply in over my head on this task. Thank you again stranger.'\n2\\. Examine the door to the Sleeper's Chamber 0/1 The Sleeper's Tomb\nAuto update at -2375, -730, -990. Drop levi if the quest doesn't update.\n3\\. Return to Glorifying Saffron Ash 0/1 The Sleeper's Tomb\n> **Task Window Text:** Return to Glorifying Saffron Ash and inform them of what you found on the door.\nGlorifying Saffron Ash is relieved to see you, 'Because of you, Smirnoth is safe again and I can't be happier about this news, but that doesn't get us any closer to figuring out what is inside that door.' they pause and think for a moment, 'So you say that the ice is holding the door shut, so that means we need to find something that can handle the ice...' They take a moment to think further before snapping their fingers with realization. 'I got it! The Western Wastes are home to burrowers. These creatures can move through the velium infused ground and even use it as a food source, of sorts. Which means that they also,' they take a moment to find the right words but after a moment of defeat, they settle on, 'excrete. This isn't going to be pretty, nor fun, but can you collect a few samples of burrower excrement for my studies? Bring me the samples and I will continue my research.'\n4\\. Collect excrement from burrowers 0/5 The Western Wastes\n> **Task Window Text:** You have been given the less than glamourous role of excrement collector. The burrowers in the Western Wastes have what you need.\nBurrower Excrement [item=140295] drops off a tunnel burrower [npc=56161] in The Western Wastes as long as someone in group is at this step.\n5\\. Deliver the excrement to Glorifying Saffron Ash 0/5 The Sleeper's Tomb\n> **Task Window Text:** The foul-smelling excrement needs to be brought to Glorifying Saffron Ash in The Sleeper's Tomb. The quicker you get rid of this stuff, the quicker your appetite will return.\nYou have been given: Foul Smelling Paste [item=140299]\nGlorifying Saffron Ash has a less than pleasant look on his face as you return. 'Yes, perfect,' He fights the urge to get sick, but you can still see him in discomfort. 'Ok, so all we need to do is take some of this and mix it with some of...' He trails off as he continues mixing his concoctions using vials and bottles that he keeps stored on him. As soon as he finishes mixing something, he somehow pulls yet another vial out and mixes that, intently watching the reaction. 'Ok, here we are.' He hands you a vial of strangely colored liquid. 'See how the ice reacts to smearing this on the ground where the ice is holding the door.'\n6\\. Bring the concoction to the door 0/1 The Sleeper's Tomb\n> **Task Window Text:** The concoction that Glorifying Saffron Ash needs to be spread upon the frame of the door where the ice meets metal. You just wish they gave you a paintbrush or something to apply it.\nYour task 'Wipe Your Feet' has been updated.\n7\\. Return to Glorifying Saffron Ash 0/1 The Sleeper's Tomb\n> **Task Window Text:** The concoction had an interesting reaction, but ultimately it did not provide the outcome desired. Meet back up with Glorifying Saffron Ash and let them know what happened.\nYou are going to have to find another way into the chamber. Perhaps Glorifying Saffron Ash needs to do more research. Either way, your work here is finished.\nGlorifying Saffron Ash looks deflated, you approaching him now means the concoction did not work as intended, 'Well that is very much not the outcome I was going for. It appears that we have made it somehow more difficult to get beyond that door. I will have to rethink our approach. Perhaps there is a different way to get in there. Thank you for your help adventurer. Oh and...' he look you up and down for a moment, 'wash your hands.'\nBerglok is mad! She is mad with passion and drive to prove herself to everyone! You know you should not get in her way in the future.\nBerglok takes the tusk in a way that can only be described as aggressively happy. 'You stoopid Human! You give me tusk of power! I will fight gooder! Rallos Zek will notice me! You warned! Go away!'\n\n---\n\nReward(s):\n425 platinum\nYou gain experience!\n**Submitted by:** Gidono, Veludeus",
    },
    {
      id = "10152",
      title = "Witness Me!",
      exp = "27",
      exp_name = "Claws of Veeshan",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Berglok - CoV",
      loc = nil,
      triggers = {
        "Hail, Berglok",
        "_Quests_",
        "_Quests_",
        "_Quests_",
      },
      items_required = {
        { name = "it to her", count = 1 },
        { name = "it to her", count = 1 },
      },
      rewards = {
        { id = 140311, name = "Blessed Tusk of Rallos Zek", type = "item" },
        { id = 140297, name = "Pouch of Ash", type = "item" },
        { id = 140300, name = "Pristine Walrus Tusk", type = "item" },
        { id = 140293, name = "Uncracked Wyvern Tooth", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Sleeper's Tomb [CoV]\n**Who:**\n- Berglok - CoV [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 100\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Quest\n**Quest Goal:**\n- Advancement\n**Quest Items:**\n- Blessed Tusk of Rallos Zek [item=140311]\n- Pouch of Ash [item=140297]\n- Pristine Walrus Tusk [item=140300]\n- Uncracked Wyvern Tooth [item=140293]\n**Related Zones:**\n- Temple of Veeshan [CoV]\n- Western Wastes [CoV]\n**Related Creatures:**\n- Crusader Vraket [ _Quests_]\n- The Great Hero Ezra - CoV [ _Quests_]\n- a velious walrus - CoV [npc=56167]\n**Related Quests:**\n- Partisan of The Sleeper's Tomb (10 Points) [quest=10285]\n**Era:** | !Claws of Veeshan\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Fri Oct 30 14:03:24 2020\nModified: Tue Dec 5 05:21:04 2023 | | **Claws of Veeshan Info & Guides: Overview \\| Progression & Task List \\| Raiding \\| Visible Armor**\n\n---\n\n**Prerequisite Quests:** None.\nYou can obtain this quest from NPC in Zone. You can find him/her at /loc lochere and is on the find tool CTRL F.\nYou say, 'Hail, Berglok'\nBerglok squares up as you approach, she gets into an aggressive stance. Instead of being scared, you get the feeling that this is how she greets people. 'You! Fight me!' she takes a moment to think, 'No! You fight big lizards! Not the big ones, you die. Not small ones either! Medium lizards! Rallos Zek demands it! Yes! Then bring teeth to Ezra! She my friend! She know what to do!' she finishes with a battle cry. You get the feeling you should do as she asks.\nYou have been assigned the task 'Witness Me!'.\n\n---\n\n**Task Window Text:** Berglok is angry! She is angry about something! Does it really matter when it comes to ogres?\n1\\. Smash wyverns and get their teeth! 0/7 The Sleeper's Tomb\n> **Task Window Text:** She sounds serious about this, the raptors who need to be smashed are in the Sleeper's Tomb. Kill them and collect their teeth!\n2\\. Bring the Teeth to Ezra 0/7 The Temple of Veeshan\n> **Task Window Text:** The teeth were for Ezra, deliver the teeth to her in the Temple of Veeshan.\nThe Great Hero Ezra is flexing as you approach, 'Ah, adventurer! You approach me, the greatest hero alive for my autograph? I'll be happy to sign your,' she pauses for a moment, 'wyvern teeth?' After a small moment to think about what she is holding, she remembers why she wanted the teeth. 'Ah, you've met one of my many apprentices, Berglok! Yes, she said she needed this pouch. I told her I would simply give it to her, but she insisted she had to earn them, which I respect in an adventurer! Here you are, she will be angry once she gets it, but she's happiest when she is angry.\nYou have been given: Pouch of Ash [item=140297]\nThe Great Hero Ezra is flexing as you approach, 'Ah, adventurer! You approach me, the greatest hero alive for my autograph? I'll be happy to sign your,' she pauses for a moment, 'wyvern teeth?' After a small moment to think about what she is holding, she remembers why she wanted the teeth. 'Ah, you've met one of my many apprentices, Berglok! Yes, she said she needed this pouch. I told her I would simply give it to her, but she insisted she had to earn them, which I respect in an adventurer! Here you are, she will be angry once she gets it, but she's happiest when she is angry.\n3\\. Return to Berglok with the pouch 0/1 The Sleeper's Tomb\n> **Task Window Text:** Bring the teeth to Berglok before she takes yours instead!\nBerglok roars with delight, or what you would expect delight to be for someone who wants to happily punch you. 'You bring pouch! Good pouch! Full of power! Has ashes of shaman inside, they keep me safe!' She puts the pouch in her pocket and continues speaking to you. 'Now smash walrus! Nobody like stoopid walrus where it cold! Get tusk and bring to Vraket in other cold place, he bless tusk, I use to beat up bad guys!'\n4\\. Smash Walruses! Get Tusk! 0/6 The Western Wastes\n> **Task Window Text:** The walruses in the Western Wastes appear to have been causing some issues for Berglok. Kill them until you get an intact tusk.\nAfter killing 6 a velious walrus [npc=56167] in The Western Wastes, a Pristine Walrus Tusk [item=140300] appears on your cursor.\n5\\. Have Crusader Vraket 'bless' the tusk 0/1 The Eastern Wastes\n> **Task Window Text:** Now that you have the tusk, bring it to Crusader Vraket for it to be blessed.\nYou have been given: Blessed Tusk of Rallos Zek [item=140311]\nCrusader Vraket looks at the tusk you handed him; a moment of understanding washes over his already soured face as he etches a rune into the side of the tusk and just screams a rage-filled scream at the rune. After he finishes yelling, he hands you the tusk with a look of satisfaction of a job well done.\n6\\. Deliver the blessed tusk to Berglok\n> **Task Window Text:** Bring the 'blessed' tusk back to Berglok and let her declare victory over her enemies.\n\n---\n\nReward(s):\n425 platinum\nYou gain experience!\n**Submitted by:** Gidono",
    },
    {
      id = "10153",
      title = "A Little Bit of Everything",
      exp = "27",
      exp_name = "Claws of Veeshan",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Kolvthnyr - CoV",
      loc = { y = 36.0, x = 46.0, z = 3.0 },
      triggers = {
        "Hail, Kolvthnyr",
        "heroic",
        "task",
        "What items?",
        "_Quests_",
        "_Quests_",
        "_Quests_",
        "_Quests_",
      },
      items_required = {
      },
      rewards = {
        { id = 140292, name = "Clump of Velium", type = "item" },
        { id = 140291, name = "Intact Golem Core", type = "item" },
        { id = 140289, name = "Unbroken Gargoyle Tooth", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Sleeper's Tomb [CoV]\n**Who:**\n- Kolvthnyr - CoV [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 100\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Quest\n**Quest Goal:**\n- Advancement\n**Quest Items:**\n- Clump of Velium [item=140292]\n- Intact Golem Core [item=140291]\n- Unbroken Gargoyle Tooth [item=140289]\n**Related Zones:**\n- Dragon Necropolis [CoV]\n- Skyshrine [CoV]\n- Temple of Veeshan [CoV]\n**Related Creatures:**\n- Fipnoc Birribit - CoV [ _Quests_]\n- Manuel Gaoler - CoV [ _Quests_]\n- Researcher Robin - CoV [ _Quests_]\n**Related Quests:**\n- Partisan of The Sleeper's Tomb (10 Points) [quest=10285]\n**Era:** | !Claws of Veeshan\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Fri Oct 30 14:28:41 2020\nModified: Tue Dec 5 05:21:04 2023 | | **Claws of Veeshan Info & Guides:** Overview \\| Progression & Task List \\| Raiding \\| Visible Armor\n\n---\n\n**Prerequisite Quests:** None.\nYou can obtain this quest from Kolvthnyr in Sleeper's Tomb. You can find him at /loc 36, 46, 3 located right at the zone in and he is on the find tool CTRL F.\nYou say, 'Hail, Kolvthnyr'\nKolvthnyr's brow is covered in sweat and you can tell that they are suffering exhaustion as they labor to speak to you, 'It's the adventurer that I keep hearing about, doing errands and helping people all over Velious! Well met adventurer! Would you be willing to take a moment from your [heroic] duties to help me out?'\nYou say, 'heroic'\nKolvthnyr coughs into his glove, you notice that there is no blood, he seems like he went through a lot recently, 'Glorious day indeed my friend!' he says through a wince, trying to get up from kneeling, then falling back down onto his knee. 'I'm fine, I just need a moment. I never expected the amount of work it takes to get into a place like this for those of us who are not regular adventurers, I have no idea how you do this every day.' He takes a moment to compose himself. 'I have a [task] for you.'\nYou say, 'task'\nKolvthnyr says, 'Aye, I was sent here by a few different people to gather up some reagents for them but having spent all my energy just getting to this point, you can see I am in no shape to fight. Trust me, the spirit is willing, but I'm going to need to ask for a favor. Will you collect these [items] for me?'\nYou say, ' What items?'\nYou have been assigned the task 'A Little Bit of Everything'.\nKolvthnyr says, 'One of the items is the core of a crystal golem, basically the 'heart'. You will have to kill a few to get one that is undamaged. The next item is the tooth of a crystal gargoyle, just as the heart, you will have to probably check a few until you can find an unbroken one. They sure enjoy chewing on adventurers, huh? Lastly, the last item is basically a collection of velium that has gathered in the waters somewhere in here. You will have to find the chamber and search for it on the bottom of the pool. Unfortunately, I don't know where exactly to find the last one, the other two are easy enough, I look forward to seeing you return, friend.'\n\n---\n\n> **Task Window Text:** Kovthnyr has overtaxed himself attempting to collect items for other researchers and has asked you to help gather them in his stead.\nFind an intact golem core by slaying golems from within the Sleeper's Tomb. Dead gargoyles will have teeth you may be able to extract, so long as they are unbroken. Finally, the last piece needed is in the \"bottom of a pool\" somewhere within the tomb.\n1\\. Locate an intact golem core in the Sleeper's Tomb 0/1 The Sleeper's Tomb\n2\\. Locate an unbroken gargoyle tooth in the Sleeper's Tomb 0/1 The Sleeper's Tomb\n3\\. Locate a clump of velium from the pool in the Sleeper's Tomb 0/1 The Sleeper's Tomb\n4\\. Bring the intact golem core to Kolvthnyr for inspection 0/1 The Sleeper's Tomb\n> **Task Window Text:** He will be able to make sure that the items are correct.\nYou have been given: Intact Golem Core\nKolvthnyr wipes his brow of sweat, 'See! That was easy for someone like you! It would have taken me probably weeks to do what you just did! Since that was so easy for you, would you be a true hero and deliver the items to where they need to go? The core goes to Fipnoc Birribit, he found his way into the Temple of Veeshan.'\n5\\. Bring the unbroken gargoyle tooth to Kolvthnyr for inspection 0/1 The Sleeper's Tomb\n> **Task Window Text:** He will be able to make sure that the items are correct.\nYou have been given: Unbroken Gargoyle Tooth\nKolvthnyr wipes his brow of sweat, 'See! That was easy for someone like you! It would have taken me probably weeks to do what you just did! Since that was so easy for you, would you be a true hero and deliver the items to where they need to go? The tooth goes to Researcher Robin, who is currently investigating the Dragon Necropolis and what the ice is doing to that place. '\n6\\. Bring the clump of velium to Kolvthnyr for inspection 0/1 The Sleeper's Tomb\n> **Task Window Text:** He will be able to make sure that the items are correct.\nYou have been given: Clump of Velium\nKolvthnyr wipes his brow of sweat, 'See! That was easy for someone like you! It would have taken me probably weeks to do what you just did! Since that was so easy for you, would you be a true hero and deliver the items to where they need to go? The clump can be brought to Manuel Gaoler in Skyshrine. I cannot recall why he is there, but that is where you will find him. Come back to me once all this is finished.'\n7\\. Deliver the core to Fipnoc Birribit in the Temple of Veeshan 0/1 The Temple of Veeshan\nFipnoc Birribit looks at you, then back at the core, then back at you. He has a moment of realization as he remembers why you are there. 'Thanks adventurer, that order I put in finally is able to be delivered! I take it Kolvthnyr is busy? No matter, tell him thank you from me, and thank you as well!\n8\\. Deliver the tooth to Researcher Robin in the Dragon Necropolis 0/1 Dragon Necropolis\nResearcher Robin is happy to see you approach, but even happier when they discover why you are there. 'Delightful! Thank you! Tell Kolvthnyr that we are even and adventurer, stay safe!'\n9\\. Deliver the clump to Manuel Gaoler in Skyshrine 0/1 Skyshrine\nManuel Gaoler says, 'There you are, I've been waiting a bit for this delivery. This chunk of velium will be useful for my research into the restless ice. Be safe my friend, and make sure Kolvthnyr is ok.'\n10\\. Return to Kolvthnyr and make sure he is alright 0/1 The Sleeper's Tomb\n> **Task Window Text:** Check back in with Kolvthnyr to make sure he is still well enough to leave the tomb.\nKovthnyr isn't as afraid for his life that you might suspect he should be. Nonetheless, he was happy to have your help.\nKolvthnyr winces in pain again but gives a smile that comforts you about his condition, 'Thank you so much adventurer, I certainly wouldn't be able to have gotten this far without your help. I think I'll be able to get out on my own. I just need a few more moments. No need to worry about me, you'll see me again!'\n\n---\n\nReward(s):\n425 platinum\nYou gain experience!\n**Submitted by:** Gidono",
    },
    {
      id = "12948",
      title = "Good, Now Stay Dead!",
      exp = "27",
      exp_name = "Claws of Veeshan",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Qabruh - CoV",
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
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Sleeper's Tomb [CoV]\n**Who:**\n- Qabruh - CoV [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 100\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n- Money\n**Related Quests:**\n- Mercenary of The Sleeper's Tomb (10 Points) [quest=10284]\n**Era:** | !Claws of Veeshan\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Sat May 25 20:06:43 2024\nModified: Mon Jul 21 18:20:12 2025 | | **Claws of Veeshan Info & Guides: Overview \\| Progression & Task List \\| Raiding \\| Visible Armor**\n\n---\n\n**Prerequisite Quests:** None\nSay \"haunting\" to Qabruh [npc=56284] to get the task.\n\n---\n\nReturn the Spectres from whence they came! 0/7 The Sleeper's Tomb\nKill Spectres.\n\n---\n\nReward(s):\n141 platinum 6 gold 6 silver 7 copper\n**Submitted by:** Gidono",
    },
    {
      id = "12949",
      title = "Superstition and the Sword",
      exp = "27",
      exp_name = "Claws of Veeshan",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Qabruh - CoV",
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
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Sleeper's Tomb [CoV]\n**Who:**\n- Qabruh - CoV [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 100\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Money\n**Related Quests:**\n- Mercenary of The Sleeper's Tomb (10 Points) [quest=10284]\n**Era:** | !Claws of Veeshan\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Sat May 25 20:13:01 2024\nModified: Sat May 25 20:16:28 2024 | | **Claws of Veeshan Info & Guides: Overview \\| Progression & Task List \\| Raiding \\| Visible Armor**\n\n---\n\n**Prerequisite Quests:** None\n\n---\n\nDefeat Gargoyles 0/7 The Sleeper's Tomb\nKill Gargoyles.\n\n---\n\nReward(s):\n141pp 6g 6s 7cp\n**Submitted by:** Gidono",
    },
  },
}
