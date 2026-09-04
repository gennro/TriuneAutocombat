-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for Skyshrine (skyshrine)
-- Total Quests: 4
-- ============================================================================

return {
  zone = "skyshrine",
  zone_name = "Skyshrine",
  quests = {
    {
      id = "10147",
      title = "Operation: Can of Wurms",
      exp = "27",
      exp_name = "Claws of Veeshan",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Kalla Mordant - CoV",
      loc = nil,
      triggers = {
        "Hail, Kalla Mordant",
        "guildmates",
        "crowded",
        "wurms",
        "_Quests_",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Skyshrine [CoV]\n**Who:**\n- Kalla Mordant - CoV [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 115\n**Maximum Level:** | 130\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Quest\n**Quest Goal:**\n- Advancement\n- Experience\n**Related Quests:**\n- Mercenary of Skyshrine (10 Points) [quest=10282]\n**Era:** | !Claws of Veeshan\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Thu Oct 29 18:37:23 2020\nModified: Wed Jul 29 02:03:39 2026 | | **Claws of Veeshan Info & Guides: Overview \\| Progression & Task List \\| Raiding \\| Visible Armor**\n\n---\n\n_**Kalla Mordant is located near the zone-in from Cobalt Scar in Skyshrine. She is on find (CTRL-F).**_\n_**/waypoint -24, +517, +2**_\nYou say, 'Hail, Kalla Mordant'\nKalla Mordant sizes you up as you approach her, her words are curt as she judges you. She stands upright and stoic, 'You there, how did you get here? How did you slip past the sentries and traps to get to this spot? That's impressive, even for me so I could use your help. I'm here on a very important task for my guild. Several [ **guildmates**] are holed up somewhere in Skyshrine and I am having a difficult time trying to access them.'\nYou say, 'guildmates'\nKalla Mordant continues to speak, sounding similar to a commander briefing a soldier on a mission, 'The reason I was sent and not say, a full expedition is because we believe that they did not survive this place and trying to locate their bodies by more conventional means has been proven inept by whatever dark magic is happening inside this wretched place. Reconnaissance has determined that the ice has gotten hold of the bodies and that is what is stopping me from simply summoning them. It's my job to find their corpses and return them, I enjoy my job and will not ask you to do that part for me. What I'm having issues with is how [ **crowded**] these halls are.'\nYou say, 'crowded'\nKalla Mordant relaxes her pose and stands at ease while she speaks, 'Yes, you have already seen how full of danger this place is. Clear out the [ **rats**], [ **raptors**], and [ **wurms**]. Those are the creatures who are in the way of me finding the corpses.'\nYou say, 'wurms'\nYou have been assigned the task 'Operation: Can of Wurms'.\nKalla Mordant stiffens her pose like a general, 'Dismissed!'\n\n---\n\n**Destroy Wurms - 0/5 - Skyshrine**\n> **Task Description:**\n>\n> Kalla Mordant is having a difficult time trying to retrieve the bodies of her guildmates from within Skyshrine. The ice is making it difficult to get the bodies by conventional means. She is going to need some help with clearing out the overcrowding of these halls so she can continue her work.\n_**Location?**_\n\n---\n\n_**Rewards:**_\nExperience\n106 pp\n**Submitted by:** Gidono ; Revamped by iventheassassin\n- Experience, Money",
    },
    {
      id = "10148",
      title = "Bibliotheca Antiqua",
      exp = "27",
      exp_name = "Claws of Veeshan",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Manuel Gaoler - CoV",
      loc = { y = 1505.0, x = 1957.0, z = -35.0 },
      triggers = {
        "Hail, Manuel Gaoler",
        "We should be saving the libraries",
        "Why can",
        "_Quests_",
        "libraries",
        "relocate",
      },
      items_required = {
      },
      rewards = {
        { id = 140280, name = "Manuel's Lucky Canteen", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Skyshrine [CoV]\n**Who:**\n- Manuel Gaoler - CoV [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 100\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Quest\n**Quest Goal:**\n- Advancement\n**Quest Items:**\n- Manuel's Lucky Canteen [item=140280]\n**Related Quests:**\n- Partisan of Skyshrine (10 Points) [quest=10283]\n**Era:** | !Claws of Veeshan\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Fri Oct 30 01:22:27 2020\nModified: Tue Dec 5 05:21:04 2023 | | **Claws of Veeshan Info & Guides: Overview \\| Progression & Task List \\| Raiding \\| Visible Armor**\n\n---\n\n**Prerequisite Quests:** None.\nYou can obtain this quest from Manuel Gaoler in Skyshrine. You can find him at /loc 1505, 1957, -35 is in the 2nd section of the zone from clicking on the globe at the top near Black Scar. He is on the find tool CTRL F.\nYou say, 'Hail, Manuel Gaoler'\nManuel Gaoler says, 'It speaks! Well it sure is good to see another adventurer down here who isn't just out to stab everything. The name is Manuel Gaoler and I'm here on behalf of the dragons who have been stuck outside of the Skyshrine to determine what their brethren are up to. As you can guess, the restless ice has also crept into this place too. Now all of the knowledge that was stored in the [libraries] here are being threatened.'\nYou say, ' We should be saving the libraries'\nManuel Gaoler says, 'I agree, the libraries here are a valuable resource to all, even if the dragons try to hide it. However, with the restless ice taking over, those tomes are even more threatened than before. We must try to deduce how to stop the ice from destroying the wisdom and philosophy that has been recorded through history. Too bad we simply cannot [relocate] the books.'\nYou say, ' Why can't they be relocated?'\nYou have been assigned the task 'Bibliotheca Antiqua'.\nManuel Gaoler says, 'Simply put, there are too many of them. Even if we had a million hands, many of the books are currently stuck and moving them would destroy them outright, losing everything. I have noticed an influx of onyx drakes and how they have congregated in certain rooms. Perhaps they might hold an answer. Dispatch a few and get back to me, let us see what we can discover.'\n\n---\n\n**Task Window Text:** Skyshrine has become a far more dangerous place than it once was since the adventurers have been here. Much of the shrine has been blocked off by the ice, making it hard to get to the bottom of what is happening within. Help Manuel Gaoler figure out how far the ice will flow into the shrine and determine how to properly save the knowledge within.\n1\\. Kill Onyx Drakes 0/8 Skyshrine\n> **Task Window Text:** Slay the onyx drakes that call the shrine their home, they seem to be a part of the plot with the restless ice in the shrine.\n2\\. Return to Manuel 0/1 Skyshrine\n> **Task Window Text:** Return to Manuel, he will want to know what you discovered. Or rather, what you didn't discover.\nYou have been given: Manuel's Lucky Canteen [item=140280]\nManuel Gaoler says, 'So, the drakes were not the key huh? That is a shame, I was hoping they would help us glean what is happening. I have noticed that they congregate mainly in select rooms. In one of the rooms there are two waterfalls. These seem to be the only source of water for the shrine that we can access at this moment. Here, take this canteen and collect some of the water from those waterfalls. Perhaps that might be what we are looking for.'\n3\\. Bring the Canteen to the Western Waterfall 0/1 Skyshrine\n4\\. Bring the Canteen to the Eastern Waterfall 0/1 Skyshrine\nWhere is this located?\n5\\. Deliver the Canteen to Manuel 0/1 Skyshrine\nManuel Gaoler looks confusingly at the canteen you just handed them, 'Well this is an interesting development. So you found out that the water coming from the east has velium in it, while the water from the west does not? Then it is safe to assume that something is pulling the velium to the west, is that right?' They continue to ponder for a moment, 'While I consider our options, I have noticed that the rats here have gotten pretty huge. I wonder if the velium in the water or the magic here is causing that. Can you dispatch a few of those rodents, they keep getting in the way anyways and I'm surprised they are even here.'\n6\\. Clear out some of the Rats 0/10 Skyshrine\n7\\. Reconvene with Manuel 0/1 Skyshrine\n> **Task Window Text:** Let Manuel know that the rats have been cleared out.\n8\\. Deliver the canteen to the ice pyramid 0/1 Skyshrine\n> **Task Window Text:** Bring the canteen to the pyramid of ice located somewhere in Skyshrine and gauge how the velium reacts from within the canteen.\nYou have been given: Manuel's Lucky Canteen\nManuel Gaoler says, 'Thank you for that, it's a little easier to concentrate now that some of the scurrying and squeaking has been dulled. After doing further research, there is one last thing I wanted to try. One of the rooms in this place has what I like to call a pyramid of ice that has built up within. This pyramid of ice is something I've been meaning to study and knowing what we know about the velium in the ice, I wanted to see what would happen if you brought the canteen to that pyramid. Here, take it, and bring it back to me once you finish your test.'\n9\\. Return to Manuel with your findings 0/1 Skyshrine\nManuel Gaoler takes the canteen from you and swirls it a bit, you can hear the velium scraping on the inside as they do this, 'Very interesting. It appears that the velium is converging, possibly to someplace in the east. This is an unexpected turn of events, adventurer. I will need to continue my research to get a better grasp as to where it is going, but thank you. I do know if we can stop whatever is happening to the velium, but it is our only shot at saving these tomes. I do hope our paths cross again adventurer, maybe next time in a tavern over a few drinks.\nNow that Manuel has a better understanding as to how the restless ice is being controlled within Skyshrine, they will be able to determine a better way to save the libraries.\n\n---\n\nReward(s):\n425 platinum\nYou gain experience!\n**Submitted by:** Gidono",
    },
    {
      id = "10155",
      title = "Crystallin for Time",
      exp = "27",
      exp_name = "Claws of Veeshan",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Black Scar - CoV",
      loc = nil,
      triggers = {
        "Hail, Black Scar",
        "Why can",
        "Sure, but where is the book?",
        "Hail, Emli Widgetton",
        "_Quests_",
        "tome",
        "book",
        "research",
      },
      items_required = {
        { name = "them up without this", count = 1 },
        { name = "it to me", count = 1 },
      },
      rewards = {
        { id = 140278, name = "Advanced Crystalline Rituals", type = "item" },
        { id = 140282, name = "Bag of Mixed Reagents", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Skyshrine [CoV]\n**Who:**\n- Black Scar - CoV [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 100\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Quest\n**Quest Goal:**\n- Advancement\n**Quest Items:**\n- Advanced Crystalline Rituals [item=140278]\n- Bag of Mixed Reagents [item=140282]\n**Related Creatures:**\n- Emli Widgetton [npc=54985]\n- a convincing doomsayer - CoV [npc=56248]\n**Related Quests:**\n- Partisan of Skyshrine (10 Points) [quest=10283]\n**Era:** | !Claws of Veeshan\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Fri Oct 30 18:45:58 2020\nModified: Sat Nov 29 09:33:09 2025 | | **Claws of Veeshan Info & Guides: Overview \\| Progression & Task List \\| Raiding \\| Visible Armor**\n\n---\n\n**Prerequisite Quests:** None.\nYou can obtain this quest from Black Scar [npc=56267] in Skyshrine at /way +740,+692,+342.95 on the top floor. He's on the Find tool (Ctrl+F).\nYou say, 'Hail, Black Scar'\nBlack Scar looks enraged to see you approach them, 'Mortal, you sure do have either a lot of courage or very little intelligence to be speaking to me in this sacred place.' Black Scar interrupts themselves with a moment of reflection, 'Actually, your bravery is what I will be needing. I'm sure you can fetch me a simple [tome] from our library?\nYou say, ' Why can't you get your own tome?'\nBlack Scar rubs the bridge of his nose in a moment of annoyance, 'Because, mortal...' they place a strong emphasis on calling you that, 'Do you think that if I could get it, I would be asking someone like you for help? I swear, your kind could use a little more critical thinking.' Black Scar composes themselves before continuing, 'Unfortunately, you aren't the only person I'm trying to help here. In order to keep it brief, are you, or are you not, able to just go get a [book]?\nYou say, ' Sure, but where is the book?'\nYou have been assigned the task 'Crystallin for Time'.\nBlack Scar loses themselves in frustration for a moment, 'Oh for the love of Ve...' They again compose themselves. 'I'm sure with your adventures, you have come across the many libraries in Skyshrine. Have you tried starting in one of those? The book I'm looking for is about rituals involving crystals; go find that shelf and start from there.'\n\n---\n\n**Task Window Text:** Black Scar needs help in performing a ritual in Skyshrine, they have asked you for assistance in this ritual.\n1\\. Search various bookshelves and find Black Scar's Book 0/1 Skyshrine\n> **Task Window Text:** Locate the book within one of the libraries in Skyshrine.\nThis update is on the green level up from the zone in at /way +695,+131,+196.95 with the big ice table in the middle of the room, the book case is on the east wall. The far right section is where the update happens, no clicking necessary.\nAfter searching the shelves, there is an empty space where the tome should be. This revelation would be best told to Black Scar for further assistance.\n2\\. Tell Black Scar that the book is missing\n> **Task Window Text:** Return to Black Scar and let them know that the book couldn't be found\nYou say, 'Hail, Black Scar'\nYour task 'Crystallin for Time' has been updated.\nBlack Scar changes their demeanor when you let them know of the missing book. 'Well, this certainly isn't your fault, but this does put a wrinkle in the project that I am working on. I'm going to need that book in order to continue the ritual that I am trying to perform here. I know the doomsayers have been doing research on the same subject am and are probably trying to stop me from completing my mission. I need you to get that book back by any means necessary. Whatever you do, do not tell me how you got that book, just...' they pause to show emphasis. 'Get it.'\n3\\. Slay Doomsayers to find the book 0/5 Skyshrine\n> **Task Window Text:** Convincing Doomsayers can be found all around Skyshrine.\nClick on the globe next to Black Scar to be ported to the raptors room.\nAdvanced Crystalline Rituals [item=140278] appears on your cursor after killing the last raptor.\n4\\. Return the book to Black Scar 0/1 Skyshrine\n> **Task Window Text:** Now that the book was discovered, return it back to Black Scar.\nClick the red gem at /way +2004,+1259,+2.95 to get back to the first floor, then run back to Black Scar.\nBlack Scar looks relieved and is far less annoyed than when you first met them, 'Excellent mortal. It's a wonderful thing that you are so good at your job! I have another issue with this ritual that could use your expertise. As I understand it, you are not tied to this place like many of us are, meaning you can leave and fetch me some reagents for my work. I know of a curious student of the arcane arts in the Eastern Wastes that is a collector of rare reagents. She will not give them up without this.' Black Scar retrieves a book from the ledge next to them. 'I believe her name is Emli. Find her and get me my reagents.'\nYou receive Catalogue of Ancient Reagents [item=140279]. Blackscar sends you to Emli Widgetton [npc=54985] who is found in the southeast camp in Eastern Wastes at approximately -2500, -2383, -241. She is on Find.\n5\\. Deliver the tome to Emli Widgetton 0/1 The Eastern Wastes\nYou say, 'Hail, Emli Widgetton'\nEmli Widgetton says, 'Thanks for those samples, if you have any more I can certainly take them off your hands for more [research].\nAny further donations of vampire blood would certainly [help] our cause. Of course, I will not turn a blind eye to any extra [shards] you may have!'\nYou have been given: Bag of Mixed Reagents [item=140282]\nYour task 'Crystallin for Time' has been updated.\nEmli Widgetton is elated to see you approach.\n'Hey! How did you know I needed...' Emli pauses for a moment to collect her thoughts, 'Oh, oh my. It appears that the dragons in Skyshrine are getting desperate, especially if they are willing to give up such knowledge for exchange for some of my reagents. I assume Black Scar sent you. I have proposed an offer for this book but they told me that there was no way they would give it to me. Well, it seems it's my lucky day at last! Here, bring this back to Black Scar as per our agreement! Be safe though, Skyshrine is no place for the weary.\nEmli Widgetton says, 'The scholars who once inhabited this tower have long passed, but there is one thing that I know about most scholars, and that is their inability to move on. Their spirits are tenacious and that can be vexing to those of us who draw breath. However, that doesn't mean we cannot still use them to learn what they know...erm, to [study] what it was they were researching in order to better understand how to defeat their creations.'\n6\\. Bring the bag of reagents to Black Scar 0/1 Skyshrine\nYou say, 'Hail, Black Scar'\nBlack Scar says, 'Your kind may be slow to understand, but at least you are all willing to learn. Whether you want to or not. That must be commendable to someone.'\nYour task 'Crystallin for Time' has been updated.\nYou realize only too late that you are unaware what the ritual is supposed to be for. You hope that there aren't any large crystals in your near future.\nBlack Scar looks almost humbled by your return, 'For being such short-sighted fools, you adventurers can still serve a purpose. Thanks for your help today, I can continue my work in peace and you will get to continue existing, for now. Leave me, I have preparations to make before the ritual. Hopefully, someday you will be able to see the fruits of your labor. Today is not that day.'\n\n---\n\nReward(s):\n425 platinum\nYou gain 1 mercenary ability point\nYou gain 24 ability points\nYou gain experience!\n**Submitted by:** Gidono, Veludeus\n- Experience, AA xp, coin",
    },
    {
      id = "8615",
      title = "Conqueror of Skyshrine",
      exp = "02",
      exp_name = "The Scars of Velious",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "Achievement",
      repeatable = false,
      group_size = "Solo",
      npc = "Charayan the Crusader",
      loc = nil,
      triggers = {
        "hail",
        "champions",
        "keep it at bay",
        "new role",
        "ancients",
        "names",
        "greatest danger",
        "hinder",
      },
      items_required = {
        { id = 9347, name = "Primal Black Dragon Claw", count = 1 },
        { id = 9349, name = "Primal Gold Dragon Claw", count = 1 },
        { id = 9348, name = "Primal Storm Dragon Claw", count = 1 },
        { id = 9409, name = "Primal Silver Dragon Claw", count = 1 },
        { id = 9329, name = "Item #9329", count = 1 },
        { id = 9330, name = "Item #9330", count = 1 },
      },
      rewards = {
        { id = 30388, name = "Rluas's Chromatic Ring", type = "item" },
        { id = 30393, name = "Chromatic Gauntlets of the Ages", type = "item" },
      },
      factions = {
      },
      walkthrough = "**Level:** 1\n**Maximum Level:** 125\n**Monster Mission:** No\n**Repeatable:** No\n**Can Be Shrouded?:** No\n**Quest Type:** Achievement\n**Group Size:** Solo\n\nThis achievement is gained upon completing the following raids in Skyshrine:\nCharayan the Crusader\nGrendish the Crusader\nJortreva the Crusader\nLord Yelinak\nSusarrak the CrusaderSubmitted by: GidonoRewards:\n[",
    },
  },
}
