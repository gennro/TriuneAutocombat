-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for Temple of Veeshan (tofs)
-- Total Quests: 6
-- ============================================================================

return {
  zone = "tofs",
  zone_name = "Temple of Veeshan",
  quests = {
    {
      id = "10132",
      title = "Better Than Ezra",
      exp = "27",
      exp_name = "Claws of Veeshan",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "The Great Hero Ezra - CoV",
      loc = nil,
      triggers = {
        "Hail, The Great Hero Ezra",
        "But I",
        "I",
        "_Quests_",
        "_Quests_",
        "apprentice",
        "ice",
        "interrupt",
      },
      items_required = {
      },
      rewards = {
        { id = 140318, name = "Ezra's Certificate of Completion", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Temple of Veeshan [CoV]\n**Who:**\n- The Great Hero Ezra - CoV [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 113\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Quest\n**Quest Goal:**\n- Advancement\n- Money\n**Quest Items:**\n- Ezra's Certificate of Completion [item=140318]\n**Related Creatures:**\n- Fipnoc Birribit - CoV [ _Quests_]\n- a flame disciple - CoV [npc=56183]\n- a nervous fanatic - CoV [npc=56184]\n**Related Quests:**\n- Partisan of The Temple of Veeshan (10 Points) [quest=10279]\n**Era:** | !Claws of Veeshan\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Wed Oct 28 18:03:04 2020\nModified: Tue Dec 5 05:21:04 2023 | | **Claws of Veeshan Info & Guides: Overview \\| Progression & Task List \\| Raiding \\| Visible Armor**\n\n---\n\n**Prerequisite Quests:** None.\nYou can obtain this quest from The Great Hero Ezra at the zone in of Temple of Veeshan.\nYou say, 'Hail, The Great Hero Ezra'\nThe Great Hero Ezra looks at you in complete shock, 'You're a long way from home my friend, and you really should not be here right now.' They look you over a bit, 'Well, armor is not too banged up, you made it this far and are still alive. You seem to be able to handle yourself in here. Very well, I shall take you on as an [apprentice]!\nYou say, ' But I'm not looking to be an apprentice at this ti...'\nThe Great Hero Ezra interrupts you, 'That's right and you are welcome! Now, I'm here because well, you may not know it but, this [ice] is messing with Velious, and I'm intent on finding out what exactly is going on! Nobody else but me, and well, now you, have gotten this far in their research! Look at us! Blazing trails and forming alliances early! That's what heroes do right? Get together and talk about how pretty their armor looks after a long day of hunting bad guys?'\nYou say, ' I'm well aware of the ice tha...'\nThe Great Hero Ezra interrupts you again, 'I know what you're thinking, \"How did I get so lucky to get a prestigious position such as being the apprentice to the world's greatest hero, Ezra?!\". Well let me tell you how...' Ezra starts telling their life story, it may be a good time to [interrupt] them.\nYou say, ' I'm sorry to interrupt, but...'\nYou have been assigned the task 'Better Than Ezra'.\nThe Great Hero Ezra says, 'Right! Sorry, you know back in my day, apprentices were seen but not heard, luckily you have me, the almighty Ezra to mentor you in the ways of being an adventurer. Well, I have the perfect job for you to do. Go get rid of some of these wurms however you wish, ignore that, just kill them then come back to me'\n\n---\n\n**Task Window Text:** Ezra seems to be a bit confused about who you are or what you have done for Norrath. Your ego may be bruised, but a job is still a job and helping her may save her life. Remove some of the wurms from the Temple\n1\\. Kill Wurms for Ezra 0/5 The Temple of Veeshan\nWhich wurms does this update on?\na nervous fanatic counts as a kill.\n2\\. Tell Ezra that the task has been completed 0/1 The Temple of Veeshan\n3\\. Kill even more Wurms for Ezra 0/5 The Temple of Veeshan\na nervous fanatic counts as a kill.\n4\\. Return to the Magnificent Ezra 0/1 The Temple of Veeshan\nThe Great Hero Ezra looks eager to continue your mentorship, 'Thanks! That was something I needed to do, but didn't want to. With less of them around it should be a bit easier to navigate this maze. However, now we have another issue. The drakes you see around here have been participating in the strange ritual that has something to do with the ice. Even though I am the greatest adventurer in the world with the greatest apprentice in the world, even we need to go in blindly at times. I'll start on the other drakes; you just focus on the red ones. I'm not leaving this spot until you leave so you don't follow me and take my glory!' She stares at you intently until you leave.\n5\\. Remove Flame Disciples from the Temple of Veeshan 0/6 The Temple of Veeshan\n6\\. Return to the Greatest Hero Ever, Ezra 0/1 The Temple of Veeshan\n7\\. Deliver the certificate to Fipnoc 0/1 The Temple of Veeshan\nEzra will be fine; she has the passion needed to strive in this harsh environment and the determination needed to take on any task, so long as she has a steady stream of apprentices under her tutelage.\nFipnoc Birribit greets you warmly as you approach, 'What do we have...' Fipnoc looks at the certificate and lets out a sigh, 'Thanks for helping out Ezra, she means well but I'm fairly certain she wasn't ready for an assignment in this place.' Fipnoc scans the area outside of the cave with a worried expression. 'Well, hopefully I'm just worrying for nothing. Anyway, congratulations on being a hero?' Fipnoc lets out a chuckle at the idea.\n\n---\n\nReward(s):\n425 platinum\nYou gain experience!\n**Submitted by:** Gidono",
    },
    {
      id = "10133",
      title = "Go Eat Wurms",
      exp = "27",
      exp_name = "Claws of Veeshan",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Barlo Aleslay - CoV",
      loc = nil,
      triggers = {
        "Hail, Barlo Aleslay",
        "what kind of work does your brother do?",
        "I have no idea what we are talking about.",
        "wurms",
        "_Quests_",
        "work",
        "talking",
        "clear drakes",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Temple of Veeshan [CoV]\n**Who:**\n- Barlo Aleslay - CoV [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 113\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Quest\n**Quest Goal:**\n- Advancement\n**Related Quests:**\n- Mercenary of The Temple of Veeshan (10 Points) [quest=10278]\n**Era:** | !Claws of Veeshan\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Wed Oct 28 18:09:58 2020\nModified: Tue Dec 5 05:21:04 2023 | | **Claws of Veeshan Info & Guides: Overview \\| Progression & Task List \\| Raiding \\| Visible Armor**\n\n---\n\n**Prerequisite Quests:** None.\nYou can obtain this quest from Barlo Aleslay in Temple of Veeshan. He can be found just inside the first set of doors at the zone in, take a hard right and there he is.\nYou say, 'Hail, Barlo Aleslay'\nBarlo Aleslay says, 'Awright mah fellow compatriot. It looks that amurnay th' ainlie yin in thae bits attempting tae clear oot th' evil that is comin' fae wi`in th' temple. Hings certainly hae gotten ferr dreadful sin th' restless ice teuk ower. A'm glad tae hae fun anither body wha kin hulp me wi' mah brother's [work]. If ye ask me, a dinnae ken how come folk lik' ye 'n' me mist dae this wirk, bit someone haes tae! Ah mean, we cuid baith be swallyin in a tavern in a'maist ony ither neuk o' Norrath bit 'ere we ur, chankin' tae death in this steid 'n' th' ainlie ale ah hae oan me is awready frozen. Looks lik' we git oor wirk cut oot fur baith o' us, huh?'\nYou say, ' what kind of work does your brother do?'\nBarlo Aleslay says, 'Aye, mah brother's wirk consists o' trying tae save Velious, 'n' we a' ken th' ainlie wey tae dae that is tae murdurr anythin' that moves whin it shouldn't be. That shuid be oor 'amily slogan noo that ah think aboot it. This yin time, mah sister led an expedition deep wi`in th' wastes 'n' cam o'er a camp o' orcs. Thay didnae tak' tae kindly tae bein' encroached upon sae thay attacked th' expedition. Laddie awright did th' orcs git a beating though. Ah wis tellt sis jumpt in th' moment th' rammy stairted 'n' teuk oot three o' th' orcs afore th' rest o' thaim realized whit wis happening! By then 'twas tae late, 'n' th' orcs wur na langer aff tae fash a' body else. Noo that ah think aboot it, ah dinnae think they orcs whaur daein' anythin' nefarious. Mibbie mah sister is juist a jerk? whit wur we [talking] aboot again?'\nYou say, 'I have no idea what we are talking about.'\nBarlo Aleslay says, 'Richt, ah apologize, whiles whin ah blether tae mah fowk, ah git a bawherr carried awa'. Ah juist loue thaim a'! A'richt sae a'm 'ere tae dae th' identical thing Brolo wis daein' 'cept in th' temple. Dae yi'll waant tae hunt [wurms], [clear drakes], or [wyvern]?'\nYou say, 'wurms'\nYou have been assigned the task 'Go Eat Wurms'.\nBarlo Aleslay says, 'Th' muckle ones? Ye mist hae some trick up yer sleeve tae surviving that! gud luck.'\n\n---\n\n**Task Window Text:** Barlo Aleslay is continuing his brother's work in the Temple of Veeshan. Clear out the wurms that are inhabiting the Temple of Veeshan.\n1\\. Kill Wurms 0/10 The Temple of Veeshan\n\n---\n\nReward(s):\nExperience\nMoney\n**Submitted by:** Gidono",
    },
    {
      id = "10134",
      title = "As Clear as Mud",
      exp = "27",
      exp_name = "Claws of Veeshan",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Barlo Aleslay - CoV",
      loc = nil,
      triggers = {
        "Hail, Barlo Aleslay",
        "what kind of work does your brother do?",
        "I have no idea what we are talking about.",
        "clear drakes",
        "_Quests_",
        "work",
        "talking",
        "wurms",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Temple of Veeshan [CoV]\n**Who:**\n- Barlo Aleslay - CoV [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 113\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Quest\n**Quest Goal:**\n- Advancement\n**Related Creatures:**\n- a pious devotee - CoV [npc=56185]\n- an evangelical adherent - CoV [npc=56194]\n**Related Quests:**\n- Mercenary of The Temple of Veeshan (10 Points) [quest=10278]\n**Era:** | !Claws of Veeshan\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Wed Oct 28 18:22:19 2020\nModified: Tue Dec 5 05:21:04 2023 | | **Claws of Veeshan Info & Guides: Overview \\| Progression & Task List \\| Raiding \\| Visible Armor**\n\n---\n\n**Prerequisite Quests:** None.\nYou can obtain this quest from Barlo Aleslay in Temple of Veeshan. He can be found just inside the first set of doors at the zone in, take a hard right and there he is.\nYou say, 'Hail, Barlo Aleslay'\nBarlo Aleslay says, 'Awright mah fellow compatriot. It looks that amurnay th' ainlie yin in thae bits attempting tae clear oot th' evil that is comin' fae wi`in th' temple. Hings certainly hae gotten ferr dreadful sin th' restless ice teuk ower. A'm glad tae hae fun anither body wha kin hulp me wi' mah brother's [work]. If ye ask me, a dinnae ken how come folk lik' ye 'n' me mist dae this wirk, bit someone haes tae! Ah mean, we cuid baith be swallyin in a tavern in a'maist ony ither neuk o' Norrath bit 'ere we ur, chankin' tae death in this steid 'n' th' ainlie ale ah hae oan me is awready frozen. Looks lik' we git oor wirk cut oot fur baith o' us, huh?'\nYou say, ' what kind of work does your brother do?'\nBarlo Aleslay says, 'Aye, mah brother's wirk consists o' trying tae save Velious, 'n' we a' ken th' ainlie wey tae dae that is tae murdurr anythin' that moves whin it shouldn't be. That shuid be oor 'amily slogan noo that ah think aboot it. This yin time, mah sister led an expedition deep wi`in th' wastes 'n' cam o'er a camp o' orcs. Thay didnae tak' tae kindly tae bein' encroached upon sae thay attacked th' expedition. Laddie awright did th' orcs git a beating though. Ah wis tellt sis jumpt in th' moment th' rammy stairted 'n' teuk oot three o' th' orcs afore th' rest o' thaim realized whit wis happening! By then 'twas tae late, 'n' th' orcs wur na langer aff tae fash a' body else. Noo that ah think aboot it, ah dinnae think they orcs whaur daein' anythin' nefarious. Mibbie mah sister is juist a jerk? whit wur we [talking] aboot again?'\nYou say, 'I have no idea what we are talking about.'\nBarlo Aleslay says, 'Richt, ah apologize, whiles whin ah blether tae mah fowk, ah git a bawherr carried awa'. Ah juist loue thaim a'! A'richt sae a'm 'ere tae dae th' identical thing Brolo wis daein' 'cept in th' temple. Dae yi'll waant tae hunt [wurms], [clear drakes], or [wyvern]?'\nYou say, 'clear drakes'\nYou have been assigned the task 'As Clear as Mud'.\nBarlo Aleslay says, 'Nae tae be doilt wi' ony ither drakes, thare ur a lot o' drakes 'ere. Juist be sure tae murdurr thae whin yer oot killing. '\n\n---\n\n**Task Window Text:** Barlo Aleslay is continuing his brother's work in the Temple of Veeshan. Kill the clear drakes that are making the Temple of Veeshan their home.\n1\\. Slay Clear Drakes 0/10 The Temple of Veeshan\nThis updates from a pious devotee and any evangelical drakes.\n\n---\n\nReward(s):\n106 platinum 2 gold 5 silver\n**Submitted by:** Gidono",
    },
    {
      id = "10135",
      title = "While You're at It",
      exp = "27",
      exp_name = "Claws of Veeshan",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Barlo Aleslay - CoV",
      loc = nil,
      triggers = {
        "Hail, Barlo Aleslay",
        "what kind of work does your brother do?",
        "I have no idea what we are talking about.",
        "wyvern",
        "_Quests_",
        "work",
        "talking",
        "wurms",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Temple of Veeshan [CoV]\n**Who:**\n- Barlo Aleslay - CoV [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 113\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Quest\n**Quest Goal:**\n- Advancement\n**Related Quests:**\n- Mercenary of The Temple of Veeshan (10 Points) [quest=10278]\n**Era:** | !Claws of Veeshan\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Wed Oct 28 19:11:58 2020\nModified: Tue Dec 5 05:21:04 2023 | | **Claws of Veeshan Info & Guides: Overview \\| Progression & Task List \\| Raiding \\| Visible Armor**\n\n---\n\n**Prerequisite Quests:** None.\nYou can obtain this quest from Barlo Aleslay in Temple of Veeshan. He can be found just inside the first set of doors at the zone in, take a hard right and there he is.\nYou say, 'Hail, Barlo Aleslay'\nBarlo Aleslay says, 'Awright mah fellow compatriot. It looks that amurnay th' ainlie yin in thae bits attempting tae clear oot th' evil that is comin' fae wi`in th' temple. Hings certainly hae gotten ferr dreadful sin th' restless ice teuk ower. A'm glad tae hae fun anither body wha kin hulp me wi' mah brother's [work]. If ye ask me, a dinnae ken how come folk lik' ye 'n' me mist dae this wirk, bit someone haes tae! Ah mean, we cuid baith be swallyin in a tavern in a'maist ony ither neuk o' Norrath bit 'ere we ur, chankin' tae death in this steid 'n' th' ainlie ale ah hae oan me is awready frozen. Looks lik' we git oor wirk cut oot fur baith o' us, huh?'\nYou say, ' what kind of work does your brother do?'\nBarlo Aleslay says, 'Aye, mah brother's wirk consists o' trying tae save Velious, 'n' we a' ken th' ainlie wey tae dae that is tae murdurr anythin' that moves whin it shouldn't be. That shuid be oor 'amily slogan noo that ah think aboot it. This yin time, mah sister led an expedition deep wi`in th' wastes 'n' cam o'er a camp o' orcs. Thay didnae tak' tae kindly tae bein' encroached upon sae thay attacked th' expedition. Laddie awright did th' orcs git a beating though. Ah wis tellt sis jumpt in th' moment th' rammy stairted 'n' teuk oot three o' th' orcs afore th' rest o' thaim realized whit wis happening! By then 'twas tae late, 'n' th' orcs wur na langer aff tae fash a' body else. Noo that ah think aboot it, ah dinnae think they orcs whaur daein' anythin' nefarious. Mibbie mah sister is juist a jerk? whit wur we [talking] aboot again?'\nYou say, 'I have no idea what we are talking about.'\nBarlo Aleslay says, 'Richt, ah apologize, whiles whin ah blether tae mah fowk, ah git a bawherr carried awa'. Ah juist loue thaim a'! A'richt sae a'm 'ere tae dae th' identical thing Brolo wis daein' 'cept in th' temple. Dae yi'll waant tae hunt [wurms], [clear drakes], or [wyvern]?'\nYou say, 'wyvern'\nYou have been assigned the task 'While You're at It'.\nBarlo Aleslay says, 'Ah mean, yer awready in 'ere killing ither hings, micht as weel murdurr some o' thaim while ye'r at it. It isnae lik' ye weren't awready aff tae dae that anyways.'\n\n---\n\n**Task Window Text:** Barlo Aleslay is continuing his brother's work in the Temple of Veeshan. Kill some of the wyverns who have been hiding within the temple.\n1\\. Kill Wyverns 0/10 The Temple of Veeshan\n\n---\n\nReward(s):\n?\n**Submitted by:** Gidono",
    },
    {
      id = "10136",
      title = "Should have been a Gemologist",
      exp = "27",
      exp_name = "Claws of Veeshan",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Kebsis - CoV",
      loc = { y = 338.0, x = 761.21, z = 0.0 },
      triggers = {
        "Hail, Kebsis",
        "Something",
        "surprising",
        "gem",
        "potential",
        "god",
        "_Quests_",
        "_Quests_",
      },
      items_required = {
        { name = "the gem to Siremth 0/1 Western Wastes", count = 1 },
      },
      rewards = {
        { id = 140319, name = "Kebsis' Gem of Terror", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Temple of Veeshan [CoV]\n**Who:**\n- Kebsis - CoV [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 113\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Quest\n**Quest Goal:**\n- Advancement\n- Experience\n- Money\n**Quest Items:**\n- Kebsis' Gem of Terror [item=140319]\n**Related Zones:**\n- Western Wastes [CoV]\n**Related Creatures:**\n- Siremth - CoV [ _Quests_]\n- a pious devotee - CoV [npc=56185]\n- a shimmering sycophant - CoV [npc=56189]\n- a shimmering sycophant - CoV [npc=56350]\n- a shimmering worshiper - CoV [npc=56331]\n**Related Quests:**\n- Partisan of The Temple of Veeshan (10 Points) [quest=10279]\n**Era:** | !Claws of Veeshan\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Wed Oct 28 19:32:32 2020\nModified: Tue Dec 5 05:21:04 2023 | | **Claws of Veeshan Info & Guides: Overview \\| Progression & Task List \\| Raiding \\| Visible Armor**\n\n---\n\n**Prerequisite Quests:** None.\nYou can obtain this quest from Kebsis in Temple of Veeshan. He can be found right at the zone in.\nYou say, 'Hail, Kebsis'\nKebsis seems confused but excited to see you, 'Adventurer! I was not expecting your kind here so soon! I was just able to sneak into here just as the dracholiches outside started appearing and haven't been able to leave since. Well, not that I can leave at this moment. I came here because I, well, this is going to be hard to explain but...' Kebsis takes a moment to consider his words, '[Something] is here that shouldn't be.\nYou say, 'Something'\nKebsis says, 'I can't explain it, I too consider myself a bit of an adventurer myself, in that I get lost in places I shouldn't, but since nobody has stopped me yet, I think I'm doing well. Back to the matter at hand, after roaming the Western Wastes and befriending the Oresco Hunters, I was introduced to a dragon that was stranded outside the temple, expressing concerns. So, I figured I would try my luck and see what I can find. What I found, was not only [surprising] but also very sinister.'\nYou say, 'surprising'\nKebsis says, 'Yes, you see, in my travels, I've been hunting a sort of nefarious spirit. I can't quite explain what it is, but it has something to do with this [gem] I found in the Siren's Grotto. It appears that one of the sirens may have stumbled upon the very thing I need to track this spirit. This gem seemed to align itself with this spirit as every time I get close to it, the gem glows, and then it slips through my fingers.'\nYou say, 'gem'\nKebsis says, 'The longer I hold onto this gem, the more it calls out to me, as if it is telling whomever I'm trying to find exactly where it am. I am not about to let this spirit slip through my fingers again, so I have come up with a plan. Help me utilize this gem to its fullest [potential] and maybe we can be done with this monster once and for all.'\nYou say, 'potential'\nKebsis says, 'I suggest that instead of going and trying to capture this spirit myself, you help me with this endeavor, and together we can rid the world of this being. So how about that? Want to help me probably kill a dark [god]?'\nYou say, 'god'\nYou have been assigned the task 'Should have been a Gemologist'.\nKebsis says, 'Excellent! I thought you had demon slaying on that already impressive resume of yours! Ok, the first thing I noticed was that whenever one of the fae drakes comes close to me, the gem gets warmer. Perhaps the key to unlocking this tool is within the fae drakes? Let's kill a few and see what happens. What's the worst that could happen?'\n\n---\n\n**Task Window Text:** Kebsis has discovered some terrible energies emanating from within the Temple for the Mother of all Wurms. He needs your help to track it down and possibly destroy whatever is causing it.\n1\\. Kill Fae Drakes 0/8 The Temple of Veeshan\n> **Task Window Text:** Kebsis has a gem that can gather the strange energy in the Temple, kill fae drakes so he can further examine what happens with the gem.\nThis step updates upon killing shimmering drakes.\n2\\. Return to Kebsis and see what happened to the gem 0/1 The Temple of Veeshan\n> **Task Window Text:** Deliver the gem to Kebsis, he is waiting for you near the entrance of the temple.\nYou have been given: Kebsis' Gem of Terror [item=140319]\nKebsis is bursting with excitement as you approach, 'I can tell that you return to me victorious, look at the gem now!' Kebsis shows the gem in his hand, it's glowing bright and vibrant, \"You sure have done something now \\_\\_\\_\\_\\_! Perhaps this information would be more useful to Siremth in the Western Wastes? Bring this to her and see if she can glean anything out of this revelation. Oh and, if you could, omit the part about you killing her brethren, that would be in our best interest.'\n3\\. Give the gem to Siremth 0/1 Western Wastes\n> **Task Window Text:** Bring the gem to Siremth in the Western Wastes and seek her wisdom.\nYou have been given: Kebsis' Gem of Terror\nSiremth straightens herself as you approach, \"Hello mortal, from what I can surmise, you are working with Kebsis. That must mean he successfully got inside, as did you! So you say that this is what happened when the gem was around fae dragons? I can't say for certain what this gem is for, but I can advise you that this has nothing to do with the current plight of Velious. Return to Kebsis and let them know this information. Hopefully this will help him with whatever he is hunting.'\n4\\. Bring the gem back to Kebsis 0/1 The Temple of Veeshan\n> **Task Window Text:** Return the gem to Kebsis, they will be able to determine what to do next.\nKebsis looks more determined as ever and eager to hear what you learned. 'So Siremth also thinks this has nothing to do with the ice! Ha! I knew it! I'm better at this than I thought! Okay, so the next step, let's see,' Kebsis pulls out a leaflet and marks a few things on it, 'Ok, according to my calculations...' Kebsis pauses for a long moment before giving another response, 'this is bad.' Kebsis puts the leaflet away. 'Okay, now it appears to have something to do with the devotees here. They may be trying to summon some dark lord, which may explain why they are so pious. Perhaps giving them the same treatment as you did with the fae drakes is in order?'\n5\\. Kill pious devotees 0/6 The Temple of Veeshan\n> **Task Window Text:** Slay the pious devotees, they are a part of this plot.\n6\\. Check back in with Kebsis 0/1 The Temple of Veeshan\n> **Task Window Text:** Return to Kebsis.\nYou have been given: Kebsis' Gem of Terror\nKebsis looks terrified and is having a hard time speaking as you approach. 'Adventurer! You. You. You...' Kebsis takes a moment to recollect themselves, 'Won't believe this! With every devotee killed, this gem started vibrating and humming, I think it's fully charged with,' Kebsis looks in abject horror at the gem, 'We got it! We captured whatever it is! Quick! Do something heroic! That's what you do! Throw it in the lava pit! Head into the northern section of the Temple where the cavern of lava is and throw it over the ledge! Hurry!'\n7\\. Throw the gem over the ledge into the lavapit 0/1 The Temple of Veeshan\nGo to the ledge in the north part around +338, +761.21.\nYour task 'Should have been a Gemologist' has been updated.\nYou lose track of the gem as it falls into the cavern below. You don't even get to hear the satisfying \"plink\" it would have made if you were closer. Here's to hoping that whatever that was, it is gone for good. You are reminded that Kebsis seems easily excitable. Perhaps a gem, was just a gem.\n\n---\n\nReward(s):\n425 platinum\nYou gain experience!\n**Submitted by:** Gidono",
    },
    {
      id = "10137",
      title = "Beyond the Threshold",
      exp = "27",
      exp_name = "Claws of Veeshan",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Fipnoc Birribit - CoV",
      loc = { y = -121.0, x = -1390.0, z = 76.0 },
      triggers = {
        "Hail, Fipnoc Birribit",
        "Wayfarer",
        "interested",
        "_Quests_",
        "Wayfarer's Brotherhood",
      },
      items_required = {
      },
      rewards = {
        { id = 140268, name = "Fipnoc's Travel Guide Volume 3", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Temple of Veeshan [CoV]\n**Who:**\n- Fipnoc Birribit - CoV [ _Quests_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 113\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Quest\n**Quest Goal:**\n- Advancement\n- Money\n**Quest Items:**\n- Fipnoc's Travel Guide Volume 3 [item=140268]\n**Related Creatures:**\n- a cerulean sexton - CoV [npc=56181]\n**Related Quests:**\n- Partisan of The Temple of Veeshan (10 Points) [quest=10279]\n**Era:** | !Claws of Veeshan\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Wed Oct 28 19:47:06 2020\nModified: Tue Dec 5 05:21:04 2023 | | **Claws of Veeshan Info & Guides: Overview \\| Progression & Task List \\| Raiding \\| Visible Armor**\n\n---\n\n**Prerequisite Quests:** None.\nYou can obtain this quest from Fipnoc Birribit in Temple of Veeshan. He can be found at /loc -121, -1390, 76 take a right in North ToV and he is in the first den you get to. He is on the find tool CTRL F.\nYou say, 'Hail, Fipnoc Birribit'\nFipnoc Birribit says, 'Hail fellow adventurer! I am not surprised to see you in a place like this. You also seem to have a penchant for danger! I like that! I'm here on assignment for the [Wayfarer's Brotherhood]. The restless ice has altered the interior of this place and we were asked to document the changes. There is one problem however, I can't seem to get to the places that I need to in order to finish my work. Willing to help me out?'\nYou say, 'Wayfarer's Brotherhood'\nFipnoc Birribit says, 'Correct, and while we typically are particular about our clientele, the simple fact that you were able to stand here with me and talk shows your gumption, and that's good enough for me at this moment. I need some reliefs gathered. There are 3 areas of the Temple that I have yet to get to and maybe one such as yourself can reach them, are you [interested]?'\nYou say, 'interested'\nYou have been assigned the task 'Beyond the Threshold'.\nFipnoc Birribit says, 'Splendid. During my research, I discovered that there are 3 rooms that I need to catalogue in this book but cannot get to. One is found in the northernmost room from within the temple, one is the room that is the furthest east, and finally one is in the center area of the room with the huge crystal. That thing is magnificent, but the room is too crowded for even someone like me to sneak through. Please go to these rooms and document what you see, then bring the book back to me for review.'\nYou are given: Fipnoc's Travel Guide Volume 3 [item=140268]\n\n---\n\n**Task Window Text:** Fipnoc Birribit is on an assignment for the Wayfarer's Brotherhood. He needs your help to make sure he had the best documentation for the Temple of Veeshan. Bring the book to the center chamber of the temple. Bring the book to the center of the northernmost chamber within the temple. Bring the book to the center of the westernmost room in the temple.\n1\\. Bring the book to the first room 0/1 The Temple of Veeshan\n_This step updates at the big room straight north of the zone in where it branches off to the north, east, and west._\nYou take a moment and jot down what the room looks like in Fipnoc's Book\nYour task 'Beyond the Threshold' has been updated.\n2\\. Bring the book to the second room 0/1 The Temple of Veeshan\n_This step updates at the northern most room in NToV with the 3 rooms facing north, south and east._\nYou take a moment and jot down what the room looks like in Fipnoc's Book\nYour task 'Beyond the Threshold' has been updated.\n3\\. Bring the book to the third room 0/1 The Temple of Veeshan\n_This step updates at the most far west room not far from the Western Wastes zone out._\nYou take a moment and jot down what the room looks like in Fipnoc's Book\nYour task 'Beyond the Threshold' has been updated.\n4\\. Return the book to Fipnoc 0/1 The Temple of Veeshan\n_Give Fipnoc back Fipnoc's Travel Guide Volume 3 (153926)_\nUpon Hand In:\nYour task 'Beyond the Threshold' has been updated.\nFipnoc Birribit says, 'Wonderful! These etchings will do but I need to continue documenting what these rooms are. While I do that, I need to get out of here eventually. I noticed an increased number of cerulean sextons that make these halls their home. Help clear me a path out of here by dispatching a few. Let me know when it's safe.'\n5\\. Clear out cerulean sextons 0/6 The Temple of Veeshan\n> **Task Window Text** The cerulean sextons are making it difficult for Fipnoc Birribit to complete his work, remove some from the temple to the Mother of all Wurms.\n6\\. Report back to Fipnoc 0/1 The Temple of Veeshan\nYou say, 'Hail, Fipnoc Birribit'\nYou have been given: Fipnoc's Travel Guide Volume 3\nFipnoc Birribit smiles warmly as you approach, 'Good, nobody likes those sextons and they are everywhere. Unfortunately, while you were gone, I realized that I still have much more work to do here, so I won't be able to leave quite yet. At least there are less sextons to deal with. This created another issue that I require help with. I reviewed your findings and they are perfect for what I needed, but I must return this book to where it belongs.' Fipnoc pauses for a moment, 'This is going to be awkward, but could you return it to one of the libraries in Skyshrine? It belongs on a specific shelf, but I was not told where, as this part of the process has also changed without anybody telling me. Just look at the books and you should be able to determine where it must go. I truly appreciate it.'\n7\\. Bring the book to a library shelf in Skyshrine 0/1 Skyshrine\nThis will autoupdate at /waypoint 350, 750, 43\n8\\. Return to Fipnoc 0/1 The Temple of Veeshan\nYou look at the temple with a more refined understanding of its intricacies. You leave today with a renewed admiration of the architecture.\nFipnoc Birribit says, 'Well, that was a bit of an ordeal. I'm going to continue my work here for the time being, such is the life of those in the Wayfarer's Brotherhood. It's a good thing this is exactly what I signed up for! Be safe friend, I look forward to working with you again in the future.'\n\n---\n\nReward(s):\n425 platinum\nYou gain experience!\n**Submitted by:** Gidono",
    },
  },
}
