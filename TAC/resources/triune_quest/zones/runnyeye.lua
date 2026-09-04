-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for Runnyeye (runnyeye)
-- Total Quests: 6
-- ============================================================================

return {
  zone = "runnyeye",
  zone_name = "Runnyeye",
  quests = {
    {
      id = "13292",
      title = "Erollisi Day: Only Fools Fall In",
      exp = "01",
      exp_name = "The Ruins of Kunark",
      min_lvl = 1,
      max_lvl = 130,
      quest_type = "Task",
      repeatable = true,
      group_size = "Solo",
      npc = "You are",
      loc = nil,
      triggers = {
        "Hail, Darenne K`Reil",
        "What do you mean not done?",
        "Side effects? That sounds dangerous.",
        "I am interested.",
        "I will get them back.",
        "done",
        "side effects",
        "interested",
      },
      items_required = {
        { name = "the Frisky Fudge Brownie to Darenne K`Reil", count = 1 },
        { name = "you the Nut Your Day Cookie", count = 1 },
        { name = "the Nut Your Day Cookie to Darenne K`Reil", count = 1 },
        { name = "the Squeezed Glee to Darenne K`Reil", count = 1 },
      },
      rewards = {
        { id = 151184, name = "Lovely Gumdrop Familiar", type = "item" },
      },
      factions = {
      },
      walkthrough = "**Level:** 1\n**Maximum Level:** 130\n**Monster Mission:** No\n**Repeatable:** Yes\n**Can Be Shrouded?:** No\n**Quest Type:** Task\n**Group Size:** Solo\n\nThis Erollisi Day task starts with Darenne K`Reil [npc=60448] in The Overthere (the original Kunark zone) at /way 2634, 1889, -48 outside the city against the east wall.\nYou say, 'Hail, Darenne K`Reil'\nDarenne K`Reil  sighs, 'Greetings, ______. If you are looking for Erollisi Day treats, I am all out. Someone stole all my new treats for the holiday before they were [done].'\nYou say, 'What do you mean not done?'\nDarenne K`Reil says, 'I was testing new recipes, and they weren't quite right yet. The cookies and brownies were still cooling when they went missing. And I was still adjusting the amount of magic to lime juice in the punch. Who knows what kind of [side effects] they will have.'\nYou say, 'Side effects? That sounds dangerous.'\nDarenne K`Reil says, 'Yes, well I might know who took them if you are [interested] in getting them for me?'\nYou say, 'I am interested.'\nYou have been assigned the task 'Only Fools Fall In'.\nDarenne K`Reil wants to know who has been stealing her Erollisi Day treats before they have really set. She thinks that Muku Wolfeetz, Toxon Frennor and Lithxn are the thieves. Befriend them and learn if they stole the missing treats.\nSpeak with Darenne about what has ruined her Erollisi Day Celebration.\n- 1. Talk with Darenne about her missing treats 0/1 The Overthere\nYou say, 'Hail, Darenne K`Reil'\nDarenne K`Reil says, 'Those fools hanging out over there keep pestering me for new goodies. I told them that they weren't ready yet, but they were so impatient. I chased them off, but I have a feeling they are still hanging around. Could you check with them and see if you can get the unready treats [back]?'\nYou say, 'I will get them back.'\nYour task 'Only Fools Fall In' has been updated.\nBefriend Lithxn and return the missing treat.\nBefriend Toxon Frennor and return the missing treat.\nBefriend Muku Wolfeetz and return the missing treat.\n- 2. Return the stolen Frisky Fudge Brownie 0/1 The Overthere\nLithxn (an Iksar) gives you \"I Think I Love You\" and rewards you with the Frisky Fudge Brownie\nGive the Frisky Fudge Brownie to Darenne K`Reil\nYou offered 1 Frisky Fudge Brownie to Darenne K`Reil.\nYour task 'Only Fools Fall In' has been updated.\nDarenne K`Reil says, 'Thank you, _____. That's one of them. '\n- 3. Return the stolen Nut Your Day Cookie 0/1 The Overthere\nToxon Frennor (a gnome) gives you the quest \"Crazy Little Thing\" and will give you the Nut Your Day Cookie\nGive the Nut Your Day Cookie to Darenne K`Reil\nYou offered 1 Nut Your Day Cookie to Darenne K`Reil.\nYour task 'Only Fools Fall In' has been updated.\nDarenne K`Reil says, 'Thank you, _____. That's one of them. '\n- 4. Return the stolen Squeezed Glee 0/1 The Overthere\nMuku Wolfeetz (an ogre) asks you to do the quest \"Lures Hurt\", which rewards you with the Squeezed Glee\nGive the Squeezed Glee to Darenne K`Reil\nYou offered 1 Squeezed Glee to Darenne K`Reil.\nYour task 'Only Fools Fall In' has been updated.\nDarenne K`Reil says, 'Thank you, _____. That's one of them. '\n- 5. Check in with Darenne to see if that's all the missing treats 0/1 The Overthere\nYou say, 'Hail, Darenne K`Reil'\nYour task 'Only Fools Fall In' has been updated.\nYou have recovered Darenne K`Reil's half-baked Erollisi Day treats and saved some misinformed lovestuck fool from making a mess of the celebration.\nYou have been given: Lovely Gumdrop Familiar\nDarenne K`Reil says, 'Thank you for returning my imperfect treats. I would hate for my reputation to be besmirched by such a product. So who do you think stole them: [Muku], [Toxon], [Lithxn]?'\nYou have completed achievement: Erollisi Day: Why Do We Fall\nYou have successfully been granted your reward for: Only Fools Fall In\nReward(s):\n3624 platinum 5 gold\nYou gain experience!\nLovely Gumdrop Familiar [item=151184]Submitted by: GidonoRewards:\n- Lovely Gumdrop Familiar [item=151184]\n[",
    },
    {
      id = "4582",
      title = "Cabilis Guild Summons: Warrior",
      exp = "01",
      exp_name = "The Ruins of Kunark",
      min_lvl = 1,
      max_lvl = 130,
      quest_type = "Quest",
      repeatable = false,
      group_size = "Solo",
      npc = "You are",
      loc = nil,
      triggers = {
        "a partisan of Cabilis",
        "militia pike",
      },
      items_required = {
        { name = "this summons to Drill Master Vygan", count = 1 },
      },
      rewards = {
        { id = 704, name = "Partisan's Pike", type = "item" },
      },
      factions = {
        { name = "Legion of Cabilis", change = 100 },
        { name = "Cabilis Residents", change = 25 },
        { name = "Scaled Mystics", change = 25 },
        { name = "Crusaders Of Greenmist", change = 25 },
        { name = "Swift Tails", change = 25 },
      },
      walkthrough = "**Level:** 1\n**Maximum Level:** 130\n**Monster Mission:** No\n**Repeatable:** No\n**Can Be Shrouded?:** No\n**Quest Type:** Quest\n**Group Size:** Solo\n\nWhen your new character enters Norrath for the first time, you might receive this message:\nMissing message\nYour new character spawns with a \"Guild Summons\" in its inventory. Right-clicking this item opens a window showing the following text:\nBy Order of Emperor Vekin You are hereby ordered to report to Fortress Talishan for training and discipline in the art of the warrior. Should you survive you will join the ranks of the Legion of Cabilis. Report to the fortress and give this summons to Drill Master Vygan. Failure to do so is a federal offense and punishable by impalement.\nDrill Master Vygan is located at the top of Fortress Talishan in Cabilis East at /waypoint -455, +28, +60 . He stands in front of your new character when it enters Norrath for the first time.\nUpon giving him the Guild Summons:\nDrill Master Vygan says 'I see they have begun to draft younger broodlings? Hmmph!! No matter. We Drill Masters shall make a warrior of you. Here is your partisan's pike and some coin as your wages. Be sure that you begin your training in blacksmithing and report to the other Drill Masters for any tasks they may have for you. Let them know you are [a partisan of Cabilis]. Perhaps soon you shall be rewarded the [militia pike].'\nYour faction standing with Legion of Cabilis has been adjusted by 100.\nYour faction standing with Cabilis Residents has been adjusted by 25.\nYour faction standing with Scaled Mystics has been adjusted by 25.\nYour faction standing with Crusaders Of Greenmist has been adjusted by 25.\nYour faction standing with Swift Tails has been adjusted by 25.\nYou gain experience!!\nYou receive 10 copper from Drill Master Vygan.\nYou receive Partisan's Pike.\nSubmitted by: iventheassassinRewards:\n- Partisan's Pike [item=704]\n[",
    },
    {
      id = "5977",
      title = "The Bazaar: Tricks of the Trade",
      exp = "03",
      exp_name = "The Shadows of Luclin",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "Task",
      repeatable = true,
      group_size = "Solo",
      npc = "You are",
      loc = { y = 114.0, x = -80.0, z = -157.0 },
      triggers = {
        "Hail, Secalna Galnor",
        "Hail, Nebbo Watzet",
        "Nermin?",
        "What happened?",
        "What favor?",
        "The bazaar?",
        "Hail, Nermin",
        "Business?",
      },
      items_required = {
        { name = "you a fair price", count = 1 },
      },
      rewards = {
        { id = 103902, name = "Sturdy Traveler's Pack", type = "item" },
        { id = 8748, name = "Trader's Satchel", type = "item" },
      },
      factions = {
      },
      walkthrough = "**Level:** 1\n**Maximum Level:** 125\n**Monster Mission:** No\n**Repeatable:** Yes\n**Can Be Shrouded?:** No\n**Quest Type:** Task\n**Group Size:** Solo\n\nSecalna Galnor is located at +114, -80, -157.\nYou say, 'Hail, Secalna Galnor'\nSecalna Galnor says 'Hello, ______. I hear you are an up-and-coming new adventurer. Your future looks bright. Won't you stay a moment and learn what I have to teach?  If you miss your friends in the Mines of Gloomingdeep it might be possible for me to [send] you back there.'\nA task window appears with a number of tutorial tasks.\nYou have been assigned the task 'The Bazaar: Tricks of the Trade'.\nSpeak to Nebbo Watzet near the entrance to the bazaar 0/1 (Plane of Knowledge)\nNebbo is just outside the Bazaar to the left of the ramp going up to the door at /loc 259.41, 1428.41, -125.25.\nYou say, 'Hail, Nebbo Watzet'\nNebbo Watzet says 'Why what a pleasure to meet you, ______. It's been quite some time since I've seen such an honest face around here. I can tell from your demeanor that you would never, ever, under any circumstances enter into business with your dear friend, only to cast him aside in an effort to line your own pockets with platinum!' The tense gnome takes a moment to suck in a deep, calming breath before continuing with a forced smile, 'But I can trust you, can't I? You're nothing like that no-good [Nermin]...'\nYou say, 'Nermin?'\nNebbo Watzet says 'Nermin and I were grand adventurers, collecting treasures from the far reaches of Norrath. We grew tired of merchants in town offering us insulting sums for our hard-earned trinkets, so we decided to set up shop as traders in the bazaar. We were a powerhouse from the beginning! Adventurers from all over came to the bazaar to browse our wares. No one could beat our prices! But then something unexpected [happened]...'\nYou say, 'What happened?'\nNebbo Watzet says 'Nermin got greedy, you see. He didn't like having to split the profits, so he started trading on his own in the bazaar. My business began to slow the moment he set up shop, and has been suffering ever since. I'm not sure what tricky tactics he's using, but I just know that gnome is up to no good! I don't suppose, as my new friend, you'd be willing to do me a [favor]?'\nYou say, 'What favor?'\nNebbo Watzet says 'My former business partner has instructed all of his employees to not speak or sell to me. I need an unfamiliar face to head into the [bazaar] and see what Nermin is up to. You're interested in a little industrial espionage, right?'\nYou say, 'The bazaar?'\nYour task 'The Bazaar: Tricks of the Trade' has been updated.\nNebbo Watzet says 'Splendid! The entrance to the bazaar is right behind me. Nermin conducts his business in the main hall. He shouldn't be hard to find.'\nTalk to Nermin within the bazaar 0/1 (The Bazaar)\nLOADING, PLEASE WAIT...\nYou have entered The Bazaar.\nNermin is straight from zone in, next to the center pillar in the center room, at /loc 12.41, -13.71, 2.28.\nYou say, 'Hail, Nermin'\nNermin says 'Welcome to the bazaar, ______. Here you'll find the largest selection of buyers and traders, including my own thriving [business], Nermin's Novelties.'\nYou say, 'Business?'\nYour task 'The Bazaar: Tricks of the Trade' has been updated.\nNermin says 'I buy and sell a wide variety of goods at a bargain price. If you're looking to sell your goods, be sure to visit my [buyer], EIan, in Blue Griffin Hall. He'll always give you a fair price. If you're looking to [purchase] items, my [trader] Helena in Red Dragon Hall won't be undersold!'\nYou say, 'Buyer?'\nNermin says 'Sometimes the bazaar may not have the item you want, or it may be listed for a price that's out of your budget. In this case, it's a good idea to barter. Buyers set up their stalls in the Blue Griffin Hall with a list of items they'd like to purchase, and the price they're willing to pay. Anyone can use the barter system to sell their items to a buyer.'\nA pop up window titled Bartering appears with more details.\nYou say, 'Trader?'\nNermin says 'Setting yourself up as a trader is simple, but first you'll need to purchase a Trader's Satchel from Merchant Tekrama. Place all the items you wish to sell inside a trader's satchel, but don't forget to set your prices before you begin trading!'\nA pop up window titled Becoming a Trader appears with more details.\nYou say, 'Purchase?'\nNermin says 'Traders set up their stalls in the Red Dragon Hall, selling everything from hand-crafted potions, to items they've found during their adventures. You can sort through all the items placed for sale, and when you've found an item you want to buy, you can head directly to the trader within the bazaar to make your purchase.'\nA pop up window titled Buying Items in the Bazaar appears with more details.\nFind the teleporter to Blue Griffin Hall 0/1 (The Bazaar)\nGo up the hallway marked with the blue griffin flags and onto the teleport pad.\nYour task 'The Bazaar: Tricks of the Trade' has been updated.\nFind and speak to Elan 0/1 (The Bazaar)\nElan is found up the first hall on the right after teleporting, at /loc 1390.47, 1099.58, 33.16 in the (blue) Diamond room as marked on map.\nYou say, 'Hail, Elan'\nElan says 'Greetings, ______. My name is Elan, and I'm a [buyer].'\nYou say, 'What's a buyer?'\nElan says 'What's a buyer you ask? Well, it's pretty simple actually. If there are items I am looking to purchase, I set up a buyer stall within the bazaar. Here, I can list what items I am looking to purchase and set the price I am willing to pay for them. People can then sell me those [items] by visiting my stall.'\nYou say, 'Items?'\nYour task 'The Bazaar: Tricks of the Trade' has been updated.\nElan says 'Nermin currently has me buying up as many bone chips as I can get my hands on for 3 silver each, and not a copper more! I'm on my break right now though, but you should browse through the other buyers here, using the [barter] system. They may be looking to purchase an item you have.'\nYou say, 'Barter?'\nElan says 'The barter system allows you to search through all the buyers within the bazaar who are looking to buy goods. You can see if anyone is buying items you have in your inventory. It's a great way to earn a few coins.'\nA pop up window titled Bartering appears with more details.\nFind the teleporter to Red Dragon Hall 0/1 (The Bazaar)\nGo down the hallway marked with the red dragon flags and onto the teleport pad.\nYour task 'The Bazaar: Tricks of the Trade' has been updated.\nFind and speak with Helena 0/1 (The Bazaar)\nHelena is found up the first hall on the right after teleporting, /loc 1390.83, -714.13, 33.16, in the (red) Diamond room as marked on the map.\nYou say, 'Hail, Helena'\nHelena says 'Hello, ______. My name is Helena, and I'm a [trader].'\nYou say, 'Trader?'\nHelena says 'As a trader, I fill up my trader [satchels] with items that I want to sell. I then set the price for each item, and begin trading once I am in Red Dragon Hall. Nermin has me selling bone chips for 3 platinum each, but I recently ran out of stock! I'm waiting on Elan to deliver another stack.'\nYour task 'The Bazaar: Tricks of the Trade' has been updated.\nYou say, 'satchels'\nHelena says 'In order to sell items, they have to be placed in trader satchels. You can buy a satchel from Merchant Tekrama in the main room of the bazaar.'\nA pop up window titled Bartering appears with more details.\nReturn to Nebbo Watzet in the Plane of Knowledge 0/1 (Plane of Knowledge)\nLOADING, PLEASE WAIT...\nYou have entered The Plane of Knowledge.\nYou say, 'Hail, Nebbo Watzet'\nNebbo Watzet says 'Finally, you've returned! So tell me, what did you [find] out about Nermin's business tactics?'\nYou say, 'What did I find?'\nYour task 'The Bazaar: Tricks of the Trade' has been updated.\nYou have helped Nebbo Watzet discover his rival's business tactics while learning how the bazaar works.\nNebbo Watzet says 'He has his buyer acquiring bone chips at a low price, and his trader reselling them for a hefty profit? What a brilliant idea! Why didn't I think of that? Oh well, two can play at this game. Here's a token of my appreciation for all your help.'\n- Sturdy Traveller's Pack\n- Trader's Satchel (unless you're using a Free-to-Play account, as they can't be used to set up traders)Rewards:\n- Sturdy Traveler's Pack [item=103902]\n- Trader's Satchel [item=8748]\n[",
    },
    {
      id = "6779",
      title = "Time for Bed",
      exp = "05",
      exp_name = "The Legacy of Ykesha",
      min_lvl = 40,
      max_lvl = 125,
      quest_type = "Task",
      repeatable = false,
      group_size = "Solo",
      npc = "You are",
      loc = nil,
      triggers = {
        "Hail, Cadale Brohat",
        "Tasks?",
        "tasks",
        "This task begins in Torgiran Mines",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "**Level:** 40\n**Maximum Level:** 125\n**Monster Mission:** No\n**Repeatable:** No\n**Can Be Shrouded?:** No\n**Quest Type:** Task\n**Group Size:** Solo\n\nYou say, 'Hail, Cadale Brohat'\nCadale Brohat smiles widely at you. 'Welcome. You are brave to venture to Broken Skull Rock. Don't mind the others. Everyone is a bit touchy around here. If you are interested in dyes, feel free to peruse what I have to offer. Playing with them has given me hours of entertainment! Just be careful on this rock, and watch your back. Oh, before I forget, I'm looking for someone to help me with some [tasks] that I need to get done. All my time with the dyes has kelp me from some of the more important things I need to take care of..'\nYou say, 'Tasks?'\nYou have been assigned the task 'Time for Bed'.\nDescription : The world is growing at an alarming rate and there aren't enough plots af land available for everyone and their livestock to live in. That's why it's up tp you tp find some new plot of land. Your first target is going to be nearly, which is why you need to explore the sleeping quarters in the southern mines,. You'll know once you arrive if it's a good place of property or not.\n[This task begins in Torgiran Mines]\nExplore the sleeping quarters in the southern mines - 0/1 - Torgiran Mines\n???\n???\nThis is just a placeholder as we have almost no information about this quest. We need all dialogues; task stages and descriptions; upper and lower level limits to receive task; any other missing information.Submitted by: BeuarhRewards:\n[",
    },
    {
      id = "6780",
      title = "Underhanded Exploration",
      exp = "05",
      exp_name = "The Legacy of Ykesha",
      min_lvl = 40,
      max_lvl = 125,
      quest_type = "Task",
      repeatable = false,
      group_size = "Solo",
      npc = "You are",
      loc = nil,
      triggers = {
        "Hail, Cadale Brohat",
        "Tasks?",
        "Hail, Calambra",
        "tasks",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "**Level:** 40\n**Maximum Level:** 125\n**Monster Mission:** No\n**Repeatable:** No\n**Can Be Shrouded?:** No\n**Quest Type:** Task\n**Group Size:** Solo\n\nYou say, 'Hail, Cadale Brohat'\nCadale Brohat smiles widely at you. 'Welcome. You are brave to venture to Broken Skull Rock. Don't mind the others. Everyone is a bit touchy around here. If you are interested in dyes, feel free to peruse what I have to offer. Playing with them has given me hours of entertainment! Just be careful on this rock, and watch your back. Oh, before I forget, I'm looking for someone to help me with some [tasks] that I need to get done. All my time with the dyes has kelp me from some of the more important things I need to take care of..'\nYou say, 'Tasks?'\nYou have been assigned the task 'Underhanded Exploration'.\nHave you ever felt the power rushing through your body as you slam down a sword on a slavering mongel? Perhaps you've wanted to feel the surge of excitement as a burst of magic explodes from your fingertips and eviscerates a worthless bag of bones? Now is your chance. You've been entered in the Go Anywhere, Kill Anything contest being held by the Wayfarer's Brotherhood! To guarantee your entry into the event, your going to need to kill 10 subverted miners, and loot 4 Ornate Miner's Pick. A Wayfarer's Brotherhood representative will use these as your proof of entry. Good Luck!\nKill 10 subverted miners - 0/10 - Torgiran Mines\nLoot 4 Ornate Miner's Pick - 0/4 - Torgiran Mines\nYour task 'Underhanded Exploration' has been updated\nThe next stage of the contest is to explore the pier in the southwest section of the crypt. This is your chance to fulfill the main portion of the 'Go Anywhere' part of the contest. Have fun with this one.\nExplore the pier in the southwest section of the crypt - 0/1 - Crypt of Nadox\nThe task updates when you get close to  -1126, 1449, -129.\nYou're almost halfway done with the contest and your odds of winning are quite good. All you need to do now to remain an active participant is to kill 10 shady treasure sorters. Get out there and Kill Anything!\nKill 10 shady treasure sorters - 0/10 - Dulak's Harbor\nYour task 'Underhanded Exploration' has been updated.\nThe second part of the 'Go Anywhere' portion of the event will require you to deliver 4 Ornate Miner's Pick to Fellgandran. Keep up the pace, you're past the halfway point.\nExplore the western courtyard door in the temple - 0/1 - Gulf of Gunthak\nThis updates near -2807, 3035, 479.\nYou're in the homestretch now, just one last thing to do! You need to get moving and speak with Calambra. They're waiting for you!\nSpeak with Calambra - 0/1 - Gulf of Gunthak\nYou can find Calambra at /waypoint 1492, -1053, 44 on the top deck of the ship in The Gulf of Gunthak.\nYou say, 'Hail, Calambra'\nYour task 'Underhanded Exploration' has been updated.\nWell, unfortunately, you didn't come in first, but you were close! You did an excellent job and nearly beat all the competition. Don't give up. You'll do much better next time! You did do quite well though, so here's your prize money. Better luck next time!\nYou receive 3 copper\nYou receive 7 silver\nYou receive 1 gold\nYou receive 176 platinum\nYou gain experience!!\nSubmitted by: DaldaryRewards:\n[",
    },
    {
      id = "7165",
      title = "Roboboar Conversions",
      exp = "03",
      exp_name = "The Shadows of Luclin",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "Quest",
      repeatable = false,
      group_size = "Solo",
      npc = "You are",
      loc = nil,
      triggers = {
        "Hail, Tindle Clinksworth",
        "Free?",
        "What contraption?",
        "I want one.",
        "free",
        "contraption",
        "want",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "**Level:** 1\n**Maximum Level:** 125\n**Monster Mission:** No\n**Repeatable:** No\n**Can Be Shrouded?:** No\n**Quest Type:** Quest\n**Group Size:** Solo\n\n/loc of Tindle Clinksworth?\nYou say, 'Hail, Tindle Clinksworth'\nTindle Clinksworth says 'Well hello there! I hope you are well and that your day has been pleasant. As for myself, I'm feeling wonderful and excited. It's so great to have something so neat to offer to people. And for [free]!'\nYou say, 'Free?'\nTindle Clinksworth says 'Surely you've seen the shiny new roboboars! Gifts from the gods, they say. All us gnomes though, we know just which god. We were all so proud to see some work direct from the Underfoot that we've figured out a way to make them faster! All you need is the bridle of one of those ugly horses, your shiny collapsible roboboar and our special conversion [contraption] and you're all set! I can supply you with one any time you need it!'\nYou say, 'What contraption?'\nTindle Clinksworth says 'I can't tell you how they work, that's still a trade secret you know. But I can give you one! All you have to do is ask! Do you [want] one?'\nYou say, 'I want one.'\nTindle Clinksworth says 'Here you go!'\nYou receive a 2-slot Conversion Contraption.  Combine a Shiny Roboboar and a Horse Bridle (depending on the speed you want).\nWe need all recipes that work and their products.\nSubmitted by: Fizen DirtnapRewards:\n[",
    },
  },
}
