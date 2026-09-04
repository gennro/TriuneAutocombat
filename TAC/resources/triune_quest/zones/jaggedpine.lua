-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for Jaggedpine (jaggedpine)
-- Total Quests: 2
-- ============================================================================

return {
  zone = "jaggedpine",
  zone_name = "Jaggedpine",
  quests = {
    {
      id = "13327",
      title = "Tempest Festival: Wander For the Wind",
      exp = "05",
      exp_name = "The Legacy of Ykesha",
      min_lvl = 95,
      max_lvl = 125,
      quest_type = "Task",
      repeatable = true,
      group_size = "Solo",
      npc = "The wind",
      loc = nil,
      triggers = {
        "Hail, Ulorin Galestrider",
        "Thank you Ulorin. My steps have guided me to you.",
        "I have heard that.",
        "I can take a look.",
        "steps",
        "heard",
        "can take",
      },
      items_required = {
      },
      rewards = {
        { id = 151430, name = "Rainy Day Ration", type = "item" },
      },
      factions = {
      },
      walkthrough = "**Level:** 95\n**Maximum Level:** 125\n**Monster Mission:** No\n**Repeatable:** Yes\n**Can Be Shrouded?:** No\n**Quest Type:** Task\n**Group Size:** Solo\n\nThis Tempest Festival task can be obtained from Ulorin Galestrider in Plane of Knowledge on the far west side of the zone near the pool at  /way -18, 1478, -123, next to Roslaind Mischeva. He is on the Find Tool.\nYou say, 'Hail, Ulorin Galestrider'\nUlorin Galestrider says, 'May the wind guide your [steps] to spread Karana's message far and wide.'\nYou say, 'Thank you Ulorin. My steps have guided me to you.'\nUlorin Galestrider says, 'Then you've [heard] the same news as I. The rain sings to Rosalind, but to me it warns of a rot that needs to be cleansed from the land. '\nYou say, 'I have heard that.'\nUlorin Galestrider says, 'I believe that this news has come to me because I like to wander by ship and stream. I was going to head to the Gulf of Gunthak by the Stonebrunt Mountains. Perhaps you [can take] a look while I finish up visiting with my friend?'\nYou say, 'I can take a look.'\nYou have been assigned the task 'Wander For the Wind'.\nUlorin Galestrider says, 'May the Tempest guide your steps.\nUlonn Galestnder, apprentice to the Herald of Karana, has heard tales from the rain. The storms speak of rot leaking out into the Gulf of Gunthak. He has asked for your help to investigate these tales and report back to him with your findings.\nInvestigate Dulak's Harbor for signs of this rotten stain. Check the tunnels filled with hate and gather evidence.\nInvestigate the Stonebrunt Mountains for signs of the stain of rot. Check the kobold camps near the warrens and gather evidence.\nInvestigate the Gulf of Gunthak for signs of the stain of corruption. Check the shacks near Dulak's Harbor and gather evidence.\n- 1. Find and collect the Stain of Rot in Dulak's Harbor 0/1 Dulak's Harbor\nFirst go through the fake wall at /way 511, -41, 3. Then go to /way 899, -162, -76 in the tunnels. There you will see a stain of rot on the ground as a green pile of ooze. Target it and /open, loot Dulak Stain of Rot.\n- 2. Find and collect the Stain of Rot in the Stonebrunt Mountains 0/1 The Stonebrunt Mountains\nThis one is found at /way -4305, 3395, -42 in a Kobold camp on the far west side of the zone up against the wall. Target it and /open, loot Stonebrunt Stain of Rot\n- 3. Find and collect the Stain of Rot in the Gulf of Gunthak 0/1 The Gulf of Gunthak\nYou can find this one at /way -527, 2504, 69 in a shack not far from the Dulak's Harbor zoneline. Same, target and /open and loot Gunthak Stain of Rot\n- 4. Deliver the Stonebrunt Stain of Rot to Ulorin 0/1 Plane of Knowledge\nYou offered 1 Stonebrunt Stain of Rot to Ulorin Galestrider.\nYour task 'Wander For the Wind' has been updated.\n- 5. Deliver the Dulak Stain of Rot to Ulorin 0/1 Plane of Knowledge\nYou offered 1 Dulak Stain of Rot to Ulorin Galestrider.\nYour task 'Wander For the Wind' has been updated.\n- 6. Deliver the Gunthak Stain of Rot to Ulorin 0/1 Plane of Knowledge\nYou offered 1 Gunthak Stain of Rot to Ulorin Galestrider.\nYour task 'Wander For the Wind' has been updated.\nYou have wandered the gulf and returned the stain of rot evidence to Ulorin Galestrider.\nYou complete the trade with Ulorin Galestrider.\nYou have successfully been granted your reward for: Wander For the Wind\nReward(s):\n5 - Rainy Day Ration (AC: 2, HP: 250, Mana: 325, End: 150, 13 to all base stats.\nSubmitted by: GidonoRewards:\n- Rainy Day Ration [item=151430]\n[",
    },
    {
      id = "5802",
      title = "Jaggedpine Recipes",
      exp = "03",
      exp_name = "The Shadows of Luclin",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "Quest",
      repeatable = false,
      group_size = "Solo",
      npc = "Pergan Darkcloud",
      loc = { y = 1071.0, x = 2086.0, z = 0.0 },
      triggers = {
        "Hail, Pergan Darkcloud",
        "What noodles?",
        "How can I use the noodles?",
        "What pastas?",
        "What casseroles?",
        "Hail, Nerdala Darkcloud",
        "I want pasta recipes.",
        "I am willing to run a small errand.",
      },
      items_required = {
        { name = "him the Lunch Bag", count = 1 },
        { name = "you a copy of those recipes", count = 1 },
        { name = "you my recipe now", count = 1 },
        { name = "Nerdala's Secret Stir Fry to Pergan", count = 1 },
      },
      rewards = {
        { id = 142685, name = "Hearty Casserole Dishes", type = "item" },
        { id = 142686, name = "Nerdala's Secret Stir Fry", type = "item" },
        { id = 50570, name = "Pasta for All", type = "item" },
        { id = 142721, name = "Pergan's Favorite Omelets", type = "item" },
      },
      factions = {
      },
      walkthrough = "**Level:** 1\n**Maximum Level:** 125\n**Monster Mission:** No\n**Repeatable:** No\n**Can Be Shrouded?:** No\n**Quest Type:** Quest\n**Group Size:** Solo\n\nPergan Darkcloud is a merchant located at +1071, +2086 inside a building in the NW corner.\nYou say, 'Hail, Pergan Darkcloud'\nPergan Darkcloud says 'Hello there ______. My wife Nerdala and I have been in the business of making delicacies from the fresh ingredients available locally in our forest. Well, really my wife is the better cook but I'm pretty good at making [Noodles].'\nYou say, 'What noodles?'\nPergan Darkcloud says 'Noodles are pretty easy. They are just Flour, Egg and Water. It's [how you use the Noodles] after you make them that is important.'\nYou say, 'How can I use the noodles?'\nPergan Darkcloud says 'There's a whole bunch of things you can do with Noodles but the best thing you can do with them are to make [pastas] and [casseroles].'\nYou say, 'What pastas?'\nPergan Darkcloud says 'Well, you're going to need to talk to my wife about those recipes. She guards them pretty closely though so you may have to do some prying. Now what I am really good at is making Omelets!'\nYou say, 'What casseroles?'\nPergan Darkcloud says 'Well, you're going to need to talk to my wife about those recipes. She guards them pretty closely though so you may have to do some prying. Now what I am really good at is making Omelets!'\nNerdala Darkcloud is located next to her husband Pergan.\nYou say, 'Hail, Nerdala Darkcloud'\nNerdala Darkcloud says 'Hello ______, what can I help you with today?'\nYou say, 'I want pasta recipes.'\nNerdala Darkcloud says 'So it's pasta recipes you're looking for, huh? Well, I'm going to have to put you to work then. Are you [willing to run a small errand] for me?'\nYou say, 'I am willing to run a small errand.'\nNerdala Darkcloud says 'Well, that's nice of you. Here, take this Lunch Bag and bring it to Waldo Pinemyer. He is the steward of the Shrine of Karana on the far edge of forest. Take his lunch to him and bring the empty bag back to me and I'll let you have my pasta recipes.'\nYou receive a Lunch Bag [item=57033]. Go to Waldo Pinemyer [npc=9474] who's located +1290, -1552 by a tree in the northeast corner, just SW of the druid ring.\nYou say, 'Hail, Waldo Pinemyer'\nWaldo Pinemyer says 'Eh... Huh... What do you want? Can't you just leave an old man to meditate in peace. Now go away.'\nGive him the Lunch Bag.\nWaldo Pinemyer says 'Huh... Who are you? Oh, you have my lunch. Thank you. Mmmm... This is great. Nerdala sure is an amazing cook.'\nYou receive an Empty Lunch Bag [item=57034]. Take this back to Nerdala.\nNerdala Darkcloud says 'Oh why thank you dear. Here's the pasta recipes as I promised.'\nYou receive Pasta For All [item=50570], a book giving out the recipes for Pasta with Cheese [item=15494], Pinemyer Pasta [item=15496], Vegetable Pasta [item=15501] and Pasta with Meat Sauce [item=15493].\nYou say, 'I want casserole recipes.'\nNerdala Darkcloud says 'Oh! You want to know my casserole recipes do you? Well I don't get the chance to get out much. A traveler from Faydwer came by and gave me this wonderful variety of sweet basil that grows wild in the Forest of Faydark some time ago. These recipes have been in my family for generations and I won't let just anyone have them but if you can bring me some more Faydwer Basil, I'll give you a copy of those recipes.'\nFaydwer Basil [item=142684] is a ground spawn in Lesser Faydark, just north of the skeleton / undead monument. Hand one to Nerdala.\nNerdala Darkcloud says, 'Oh my, this smells wonderful! Here are the recipes I promised you. You seem to have a great love for cooking like myself. I have another set of recipes you may be interested in having. Have you ever tried a Stir Fry? They are so wonderfully light and refreshing. If you're [willing to do one more favor] for me, I'd be happy to share the recipe with you.'\nYou receive Hearty Casserole Dishes, a book giving out recipes for Anaconda Casserole [item=46657], Griffon Casserole [item=55071], Vegetable Casserole [item=54031] and Cheesy Anaconda Casserole [item=15474].\nYou say, 'willing to do one more favor'\nNerdala Darkcloud says, 'That's the spirit! Anything for a good recipe, I always say. I've heard tales of a very rare variety of mushroom that grows only in the deepest depths on the continent of Odus. I'd love to try to make something with those. If you happen run across any Deep Odus Mushrooms I'd happily trade them for the secret of making Stir Frys.'\nDeep Odus Mushroom [item=109792] is a ground spawn in Toxxulia Forest west of the druid ring. Hand one to Nerdala.\nNerdala Darkcloud says, 'You did it! Wow, they're so large I can't wait to make something with these! Well, I suppose I have to give you my recipe now. Don't share this recipe with anyone else though!'\nYou gain party experience!\nYou receive Nerdala's Secret Stir Fry [item=142686], a book giving out recipes for Jaggedpine Stir Fry [item=29570], Griffon Stir Fry [item=15486] and Anaconda Stir Fry [item=29569].\nIf you give Nerdala's Secret Stir Fry to Pergan, he takes it :\nPergan Darkcloud says, 'Amazing, you managed to pry it out of her! Ok, here are the secrets to making my special Omelets. Don't tell her you gave me the recipe or she'll kill me.'\nYou receive Pergan's Favorite Omelets [item=142721], a book giving out recipes for Omelette du Fromage [item=15491], Meat Lover's Omelet [item=142720] and Ranger's Omelet [item=15500].Submitted by: TobynnRewards:\n- Hearty Casserole Dishes [item=142685]\n- Nerdala's Secret Stir Fry [item=142686]\n- Pasta for All [item=50570]\n- Pergan's Favorite Omelets [item=142721]\n[",
    },
  },
}
