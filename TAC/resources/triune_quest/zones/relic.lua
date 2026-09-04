-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for Relic, the Artifact City (relic)
-- Total Quests: 4
-- ============================================================================

return {
  zone = "relic",
  zone_name = "Relic, the Artifact City",
  quests = {
    {
      id = "3396",
      title = "A Shop Keeper's Delight",
      exp = "11",
      exp_name = "Prophecy of Ro",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Borso",
      loc = { y = 1090.0, x = 620.0, z = -275.0 },
      triggers = {
        "Hail, Borso",
        "Quality?",
        "Tellen?",
        "What lesson?",
        "quality",
        "offerings",
        "Tellen",
        "lesson",
      },
      items_required = {
      },
      rewards = {
        { id = 47241, name = "Supply Crate for Tellen", type = "item" },
        { id = 51356, name = "Tellen's Trinket Chest", type = "item" },
        { id = 47409, name = "Borso's Prized Earring", type = "item" },
        { id = 47410, name = "Borso's Prized Ring", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Relic, the Artifact City [zone=343]\n**Who:**\n- Borso [npc=20399]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 70\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Experience\n- Loot\n**Quest Items:**\n- Supply Crate for Tellen [item=47241]\n- Tellen's Trinket Chest [item=51356]\n**Related Creatures:**\n- a Tellengard [npc=20711]\n- a supply runner - Air Elemental [npc=24402]\n- a supply runner - Earth Elemental [npc=20712]\n- a supply runner - Fire Elemental [npc=24403]\n- a supply runner - Water Elemental [npc=24404]\n**Era:** | !Prophecy of Ro\nRecommended:\n**Group Size:** | Solo\n**Min. # of Players:** | 1\n**Max. # of Players:** | 1\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Tue Mar 7 17:34:12 2006\nModified: Tue Dec 5 05:21:04 2023 | | Borso may be found at +1090, +620, -275.\nYou say, 'Hail, Borso'\nBorso says 'Hello dear customer. What can Borso do for you today? I have many fine and exquisite objects that I am sure will delight you. Obviously a creature with refined tastes such as yours can easily see the [quality] of the goods I offer.'\nYou say, 'Quality?'\nBorso says 'Yes, yes. All of my offerings are of the highest quality. Why look at this sarken pelt obtained from the outer planes. Though long extinct, you would not guess this by the color and texture of the hide. Why it looks like it was just taken from the sarken this morning! I guarantee that all of my [offerings] are of the highest quality! Not at all like that scoundrel [Tellen] who hawks goods not fit for the trash heap.'\nYou say, 'Tellen?'\nBorso says 'Yes, Tellen, the knave who owns the large center stall. He is always working to steal my customers or malign my reputation. Why he's even gone so far as to claim that I deal in stolen goods! The fool! It's past time I taught him a [lesson] in manners.'\nYou say, 'What lesson?'\nHelp me beat Tellen at his own game.\nI don't want his supplies to be replenished. The less he has to sell, the happier I'll be. You can do this by stopping his runners from resupplying his stall.\nWhile you're at it, I want you to `borrow' some of the goods on display at his tent. The chests that I want are sitting on top of his counter. But beware, do not pilfer tyhem if a guard is close!\nYou have been assigned the task 'A Shop Keeper's Delight'.\nKill 20 Supply Runners 0/20 - Relic\nLoot 4 Supply Crate for Tellen from Supply Runners 0/4 - Relic\nSteal from Tellen 0/10 - Relic\nDeliver 4 Supply Crate for Tellen to Borso 0/4 - Relic\nDeliver 10 Tellen's Trinket Chest to Borso 0/10 - Relic\nYour task 'A Shop Keeper's Delight' has been updated.\nI can't wait for the look on his face when he finds his merchandise for sale at my stall! Why I'm feeling so good I might even offer it to him at a discount! Hahahaha!\nYou gain party experience!!\nRewards are Borso's Prized Earring for melees and hybrids and Borso's Prized Ring for casters and priests.\n**Submitted by:** Gthany Sa'angreal, Cognatus, Xegony\n- Borso's Prized Earring [item=47409]\n- Borso's Prized Ring [item=47410]",
    },
    {
      id = "3410",
      title = "Challenge of the Circle",
      exp = "11",
      exp_name = "Prophecy of Ro",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Arena Overseer",
      loc = { y = 160.0, x = 550.0, z = -275.0 },
      triggers = {
        "Hail, Arena Overseer",
        "I wish to challenge the champions",
        "Hail, Arkon of the Sixth Circle",
        "I will challenge you.",
        "challenge",
      },
      items_required = {
      },
      rewards = {
        { id = 48009, name = "Necklace of the Circle Champion", type = "item" },
        { id = 48010, name = "Veil of the Circle Champion", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Relic, the Artifact City [zone=343]\n**Who:**\n- Arena Overseer [npc=20401]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 70\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Loot\n**Related Creatures:**\n- Arkon of the Sixth Circle [npc=20407]\n- Hurlinor of the Fifth Circle [npc=20406]\n- Ka`Chnt of the Fourth Circle [npc=20405]\n- Kraglin of the First Circle [npc=20402]\n- Lowrin of the Third Circle [npc=20404]\n- Vashlor of the Second Circle [npc=20403]\n**Era:** | !Prophecy of Ro\nRecommended:\n**Group Size:** | Group\n**Min. # of Players:** | 3\n**Max. # of Players:** | 6\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Tue Mar 28 01:13:34 2006\nModified: Tue Dec 5 05:21:04 2023 | | _Find the Arena Overseer at +160, +550, -275 in Relic._\nYou say, 'Hail, Arena Overseer'\nArena Overseer says 'Hello traveler. Have you come to prove yourself or merely watch? You see this arena is used by the various schools to settle their differences. But when not used for this, the various inhabitants use this to try to earn favor from the lords above. If you wish to [challenge] the champions, you simply have to tell me.'\nYou say, 'I wish to challenge the champions'\nArena Overseer says 'Very well. I have notified the champions of your desire to fight them. Your first fight lies with the Champion of the Sixth circle. Only after you have bested him will you be able to challenge, Hurlinor, he of the Fifth Circle. And so on. Please note that the Champions are not prepared for combat all day. In fact, the top three return to their circles only upon the call of the night. Good luck to you mortal!'\n_Find Arkon of the Sixth Circle and hail it. To find it: Walk to the three circles in the \"arena\" area (SW corner). They stand around in one of the three circles._\nYou say, 'Hail, Arkon of the Sixth Circle'\nArkon of the Sixth Circle says 'Are you brave enough to [challenge] me mortal?'\nYou say, 'I will challenge you.'\n_Arkon will aggro. Kill it and move on to the next one._\n_Do the same with Hurlinor of the Fifth Circle, KaChnt of the Fourth Circle, Lowrin of the Third Circle, Vashlor of the Second Circle, and Kraglin of the First Circle._\n_Upon killing these six mobs, everyone in your group will be rewarded with a Necklace or Veil of the Champion, depending on your class._\n- Necklace of the Circle Champion [item=48009]\n- Veil of the Circle Champion [item=48010]",
    },
    {
      id = "3412",
      title = "The Needy",
      exp = "11",
      exp_name = "Prophecy of Ro",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Borso",
      loc = { y = 1086.0, x = -614.0, z = 0.0 },
      triggers = {
        "Hail, Borso",
        "What quality?",
        "What offerings?",
        "What suppliers?",
        "I am willing.",
        "quality",
        "offerings",
        "Tellen",
      },
      items_required = {
      },
      rewards = {
        { id = 47044, name = "Glowing Ember Heart", type = "item" },
        { id = 48057, name = "Heartseed Pod", type = "item" },
        { id = 48058, name = "Vial of Arcstone Water", type = "item" },
        { id = 48059, name = "Relic Shopkeeper's Earring", type = "item" },
        { id = 48060, name = "Relic Shopkeeper's Ring", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Relic, the Artifact City [zone=343]\n**Who:**\n- Borso [npc=20399]\nRating:\n0/1**_\\*__\\*__\\*__\\*__\\*_**\n(From 1 rating)\nInformation:\n**Level:** | 70\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Loot\n**Quest Items:**\n- Glowing Ember Heart [item=47044]\n- Heartseed Pod [item=48057]\n- Vial of Arcstone Water [item=48058]\n**Related Zones:**\n- Arcstone, Isle of Spirits [zone=333]\n**Related Creatures:**\n- a riverbank mistwalker [npc=20385]\n**Era:** | !Prophecy of Ro\nRecommended:\n**Group Size:** | Solo\n**Min. # of Players:** | 1\n**Max. # of Players:** | 1\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Thu Mar 30 21:54:53 2006\nModified: Tue Dec 5 05:21:04 2023 | | _Find Borso in Relic at location +1086, -614._\nYou say, 'Hail, Borso'\nBorso says 'Hello dear customer. What can Borso do for you today? I have many fine and exquisite objects that I am sure will delight you. Obviously a creature with refined tastes such as yours can easily see the [quality] of the goods I offer.'\nYou say, 'What quality?'\nBorso says 'Yes, yes. All of my offerings are of the highest quality. Why look at this sarken pelt obtained from the outer planes. Though long extinct, you would not guess this by the color and texture of the hide. Why it looks like it was just taken from the sarken this morning! I guarantee that all of my [offerings] are of the highest quality! Not at all like that scoundrel [Tellen] who hawks goods not fit for the trash heap.'\nYou say, 'What offerings?'\nBorso says 'I have many unique and interesting items from all manner of creatures through out the planes. Here is a charm from a tiny creature known as a leprechaun that is supposed to bring the wearer great luck. And here is the fiery heart from a greater magma spirit. Not interested in those? Well it seems you have caught me at a bad time for my [suppliers] have been slow to reach me.'\nYou say, 'What suppliers?'\nBorso says 'Yes, they are several days late and I'm afraid that Tellen may have bought their loyalty. But I won't let him defeat me this easily. I have a venture for you if you are [willing].'\nYou say, 'I am willing.'\nBorso says 'Yes, as I mentioned earlier, the stocks of my usual wares has run nearly dry so I will pay you handsomely for your assistance in replenishing my supplies. Upon the mysterious and shrouded hills of Arcstone will you find all that I seek.'\nYou have been assigned the task 'The Needy'.\nKill 10 Tanglefoots - Arcstone\nLoot 4 Heartseed Pod from Tanglefoots - Arcstone\nKill 10 Riverbank Mistwalkers - Arcstone\nLoot 4 Vial of Arcstone Water from Riverbank Mistwalkers - Arcstone\nKill 10 Firetails - Arcstone\nLoot 4 Glowing Ember Hearts from Firetails - Arcstone\nDeliver 4 Heartseed Pod to Borso - Relic\nDeliver 4 Vial of Arcstone Water to Borso - Relic\nDeliver 4 Glowing Ember Heart to Borso - Relic\n_Casters receive Relic Shopkeeper's Earring._\n_Melees receive Relic Shopkeeper's Ring._\n**Need hand-in dialogues, faction hits if any, task description(s) if any.**\n**Submitted by:** Corstin, Sword of Fate, Prexus Server\n- Relic Shopkeeper's Earring [item=48059]\n- Relic Shopkeeper's Ring [item=48060]",
    },
    {
      id = "9468",
      title = "Strange Magic",
      exp = "25",
      exp_name = "The Burning Lands",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "A Door",
      loc = { y = 533.0, x = 230.0, z = 0.0 },
      triggers = {
      },
      items_required = {
      },
      rewards = {
        { id = 134611, name = "Infused Sandstone Siphon", type = "item" },
        { id = 134462, name = "Battleworn Stalwart Moon Binding Hands Muhbis", type = "item" },
        { id = 134015, name = "Ear Stud of Ethereal Wisps", type = "item" },
        { id = 133885, name = "Enraptured Bludgeon", type = "item" },
        { id = 134362, name = "Fettered Ifrit Coin", type = "item" },
        { id = 134305, name = "Glowing Spellbound Lamp", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Relic, the Artifact City [zone=343]\n**Who:**\n- A Door [npc=54401]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Advancement\n- Experience\n- Money\n**Quest Items:**\n- Infused Sandstone Siphon [item=134611]\n**Related Zones:**\n- The Chamber of Tears [zone=1213]\n**Related Creatures:**\n- a bane fragment [npc=54541]\n- a glowing chest - The Chamber of Tears [npc=54543]\n- a hex fragment [npc=54539]\n- a hex golem [npc=54536]\n- a lifebane golem [npc=54537]\n- a spellbinder fragment [npc=54540]\n- a spellbinder golem [npc=54535]\n- an arcane fragment [npc=54542]\n- an arcane golem [npc=54538]\n**Related Quests:**\n- All Hail the King [quest=9267]\n- Brass Palace [quest=9445]\n- Contract of War [quest=9446]\n- Delivery [quest=9466]\n- Earthen Dirge [quest=9454]\n- Enter Mearatas [quest=9444]\n- Fight Fire [quest=9263]\n- Key to the Kingdom [quest=9264]\n- Mold Seeker [quest=9465]\n- Palace of Embers [quest=9433]\n- Prisoner's Dilemma [quest=9265]\n- Relic Raider [quest=9462]\n- Royal Visits [quest=9448]\n- Serving Another Master [quest=9453]\n- Soldier of Air [quest=9225]\n- Trial of Three (Trial of Smoke) [quest=9281]\n- Trial of the Ashes of Rusted Cliff's Glory (Trial of Smoke) [quest=9335]\n- Trial of the Eternal Cyclone (Trial of Smoke) [quest=9336]\n- Trial of the Speaker's Amphitheater (Trial of Smoke) [quest=9282]\n- Trial of the Wending Ways (Trial of Smoke) [quest=9337]\n- Tyrant of Fire [quest=9463]\n**Era:** | !The Burning Lands\nRecommended:\n**Group Size:** | Solo\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Wed Dec 5 23:35:49 2018\nModified: Tue Dec 5 05:21:04 2023 | | **Prerequisite Quests:** Soldier of Air, Fight Fire, and any one Trail of Smoke, Prisoner's Dilemma, Palace of Embers, Brass Palace, Key to the Kingdom, Contract of War, All Hail the King, Royal Visits, Tyrant of Fire, Enter Mearatas, Serving Another Master, Earthen Dirge, Mold Seeker, Relic Raider, and Delivery.\nYou get this quest upon clicking the round portal in Relic at +533, +230 in the corridor to the east from zone in.\n\n---\n\n1\\. Use the Infused Sandstone Siphon to gather magic from the room. 0/1 Chamber of Tears\nTo enter the instance, click on the round portal in Relic at +533, +230 in the corridor to the east from zone in. Someone has to right click his/her Infused Sandstone Siphon [item=134611].\n2\\. Defeat the guardians. 0/4 Chamber of Tears\n4 golems stand in the room. After each golem dies, adds spawn. They can be mezzed and despawn after each golem dies. You still have to kill the adds after the last golem dies though.\nThere are 2 kind of emotes :\n\\- a lifebane golem casts Spark of Life. There is an emote : **\\_\\_\\_\\_\\_ is cursed with life, \\_\\_\\_\\_\\_ is cursed by death.** Both named players have to get close to each other to counteract it : \"The curses of life and death fade into each other.\"\n\\- a hex golem casts Static Hex. it shows as a red icon in the song window. There is also an emote : **\\_\\_\\_\\_\\_ and \\_\\_\\_\\_\\_ are hexed. Static gathers around them, reaching tendrils of electricity toward each other.** Both named players have to get far from each other. If they don't, after some time: \"The static between \\_\\_\\_\\_\\_ and \\_\\_\\_\\_\\_ grows strong. At such close range it can only explode.\" then it triggers Static Explosion : Decrease Hitpoints by 166666, Stun (1.00 sec).\n3\\. Use the Infused Sandstone Siphon to gather magic from the room. 0/1 Chamber of Tears\nSomeone has to right click his/her Infused Sandstone Siphon.\n4\\. Open the chest 0/1 Chamber of Tears\nChest loot may include :\nBattleworn Stalwart Moon Binding \\_\\_\\_\\_\\_ Muhbis\nBelt of the Last Light\nEar stud of Ethereal Wisps\nEmpyrean Cinder of the Agile\nEnraptured Bludgeon\nHoled Pebble\nMortal Celestial \\_\\_\\_\\_\\_ Spark\n\\_\\_\\_\\_\\_ Spellbound Lamp\n\n---\n\nReward(s)\n212 platinum, 5 gold\nYou gain experience!\n96 Fettered Ifrit Coins\n**Submitted by:** Larth\n- Battleworn Stalwart Moon Binding Hands Muhbis [item=134462]\n- Ear Stud of Ethereal Wisps [item=134015]\n- Enraptured Bludgeon [item=133885]\n- Fettered Ifrit Coin [item=134362]\n- Glowing Spellbound Lamp [item=134305]\n- Greater Spellbound Lamp [item=134304]\n- Lesser Spellbound Lamp [item=134302]\n- Median Spellbound Lamp [item=134303]\n- Minor Spellbound Lamp [item=134301]\n- Mortal Celestial Brawny Spark [item=133896]\n- Mortal Celestial Deft Spark [item=133897]\n- Mortal Celestial Equilibrium Spark [item=133895]\n- Mortal Celestial Incisive Spark [item=133900]\n- Mortal Celestial Nimble Spark [item=133898]\n- Mortal Celestial Shrewd Spark [item=133901]\n- Mortal Celestial Vigorous Spark [item=133899]",
    },
  },
}
