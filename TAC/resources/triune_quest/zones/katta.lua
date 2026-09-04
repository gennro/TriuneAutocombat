-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for Windsong Sanctuary (katta)
-- Total Quests: 4
-- ============================================================================

return {
  zone = "katta",
  zone_name = "Windsong Sanctuary",
  quests = {
    {
      id = "5499",
      title = "Windsong \\#1: Stranger in a Strange Land",
      exp = "18",
      exp_name = "Veil of Alaris",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Gibbledon Cogboggle",
      loc = nil,
      triggers = {
        "Hail, Gibbledon Cogboggle",
        "Help?",
        "What kind of food?",
        "I",
        "What intrigues you?",
        "Hail, a sentry stone",
        "help",
        "food",
      },
      items_required = {
        { name = "you some information you would be interested in", count = 1 },
      },
      rewards = {
        { id = 101003, name = "Gibbledon's Tools", type = "item" },
        { id = 101272, name = "Harmonic Recording Device", type = "item" },
        { id = 101142, name = "Kangon Ribs", type = "item" },
        { id = 99795, name = "Music of the Mind\n- Eltarki's Diary - Music of the Mind", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Windsong Sanctuary [zone=813]\n**Who:**\n- Gibbledon Cogboggle [ _Quests, Mission_]\nRating:\n0/0**_\\*__\\*__\\*__\\*__\\*_**\nInformation:\n**Level:** | 95\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Alaran Language:** | 81\n**Quest Goal:**\n- Experience\n- Money\n**Time Limit:** | 06:00:00\n**Success Lockout Timer**: 06:00:00\n**Quest Items:**\n- Gibbledon's Tools [item=101003]\n- Harmonic Recording Device [item=101272]\n- Kangon Ribs [item=101142]\n**Related Creatures:**\n- a breezerunner [npc=39249]\n- a fluttering kangon [npc=39251]\n- a sentry stone [npc=39232]\n- a soundless devotee [npc=39254]\n- a wind strider [npc=39240]\n**Related Quests:**\n- Windsong #2: Getting Down to Business [quest=5500]\n- Windsong #3: Making Music [quest=5501]\n**Era:** | !Veil of Alaris\nRecommended:\n**Group Size:** | Solo\n**Min. # of Players:** | 1\n**Max. # of Players:** | 6\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Thu Dec 1 22:19:47 2011\nModified: Tue Dec 5 05:21:04 2023 | | **Veil of Alaris Information & Guides: An Overview \\| Group Progression & Task List \\| Raid Progression \\| Visible Armor**\n\n---\n\n_This task is the first in a series of three; a shared task (1-6 players) that begins with Gibbledon Cogboggle in Windsong Sanctuary, located at about 20, -185, -32 (due west of the zone-in -- the southern entrance to the inner grassy area)._\n_Pre-requisites for requesting the task:_\n\\- No tasks\n\\- 81 Skill Level in Alaran\nYou say, 'Hail, Gibbledon Cogboggle'\nGibbledon Cogboggle says 'Psst! Hey you. Come here. Can you [help] a poor gnome out?'\nYou say, 'Help?'\nGibbledon Cogboggle says 'Seems I have gotten myself into quite a pickle. Mmm. Pickles. I sure would love one of those right about now. Anyway, I am kind of stranded here and was wondering if you could find me some [food]. I haven't eaten in at least an hour or two and I am famished.'\nYou say, 'What kind of food?'\nGibbledon Cogboggle says 'Hmm. I don't know. Those kangon creatures look kinda tasty. Think you could bring me some of their [meat]?'\nYou say, 'I'll make some meat out of them...'\nGibbledon Cogboggle says 'You're a lifesaver. Bring me some kangon ribs and perhaps I can give you some information you would be interested in.'\nYou have been assigned the task 'Stranger in a Strange Land'.\nYou have met a gnome in Windsong Sanctuary who needs some help to complete his research. Intrigued, you have agreed to help him.\nGet some Kangon Ribs from the Wind Striders, Fluttering Kangons, or Breezerunners.\n\n---\n\nObtain some Kangon Ribs 0/1 (Windsong Sanctuary)\n_These are a common drop from Kangons in the inner area of the zone. Note: These are NOT pre-lootable (nor are any other items in the task)._\nDeliver the Kangon Ribs to Gibbledon Cogboggle 0/1 (Windsong Sanctuary)\nSpeak with Gibbledon Cogboggle 0/1 (Windsong Sanctuary)\nYou say, 'Hail, Gibbledon Cogboggle'\nGibbledon Cogboggle says 'Some pickles would have been better, but this should do. Thanks. Now I will hold up my end of the bargain and tell you what I am doing here. I came to investigate the link between the Alarans and their god Ryken. It appears that they share a link, and Ryken can communicate to them and through them whenever Ryken so desires. Ryken can even use stones and other inanimate objects to communicate to the Alarans and others. This [intrigues] me.'\nYou say, 'What intrigues you?'\nGibbledon Cogboggle says 'I love challenges and figuring out how this link works is my next one. I think you can help me. There are a couple of problems though. Someone or something appears to have stolen my tools while I dozed off the other day. I bet it was those worshippers! Get my tools back and perhaps we can investigate this link that Ryken shares with the Alarans further.'\nFind Gibbledon' Tools 0/1 (Windsong Sanctuary)\n_Task Window Says:_ Find Gibbledon's tools somewhere in Windsong. He thinks the worshippers might have them.\n_The tools are a common drop from Alarans (any part of the zone) and golems (center of the zone)._\nDeliver Gibbledon's Tools to Gibbledon Cogboggle 0/1 (Windsong Sanctuary)\nSpeak with Gibbledon Cogboggle 0/1 (Windsong Sanctuary)\nYou say, 'Hail, Gibbledon Cogboggle'\nGibbledon Cogboggle says 'These are definitely my tools. I am lost without them. Thanks. Now we can get down to business. Perhaps you have seen the strange totem-like stones around Windsong? They are called Sentry Stones. Take this Harmonic Recording Device and investigate some of the stones. Perhaps they hold some clue about how Ryken can communicate to the Alarans here.'\nWith the Harmonic Recording Device in your inventory, speak with a sentry stone 0/1 (Windsong Sanctuary)\n_There are 3-4 sentry stones located throughout the inner area of the zone._\nYou say, 'Hail, a sentry stone'\na sentry stone says, in Alaran, 'A series of beautiful notes dance through your mind. For a moment, you feel connected to all the beings that inhabit Windsong.'\nReturn the Harmonic Recording Device to Gibbledon Cogboggle 0/1 (Windsong Sanctuary)\nSpeak with Gibbledon Cogboggle 0/1 (Windsong Sanctuary)\nYou say, 'Hail, Gibbledon Cogboggle'\nGibbledon Cogboggle says 'Musical notes you say? This should have been obvious. The Alarans that live here appear to communicate with musical instruments. I would love to examine some of these instruments first hand. First however, I am going to take a break and eat those kangon ribs you brought to me. Just talk to me again when you are ready to help me with my research.'\n_Rewards:_\n225 platinum\nEltarki's Diary - Music of the Mind\n- Eltarki's Diary - Music of the Mind [item=99795]",
    },
    {
      id = "13361",
      title = "Stone Cold Summer: Blood for Stone",
      exp = "01",
      exp_name = "The Ruins of Kunark",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "Task",
      repeatable = false,
      group_size = "Solo",
      npc = "Strange",
      loc = nil,
      triggers = {
        "Hail, Inis Zidas",
        "Yes, I did notice some bones out of place.",
        "I can help with fieldwork",
        "notice",
        "fieldwork",
        "Ink Stained Hand",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "**Level:** 1\n**Maximum Level:** 125\n**Monster Mission:** No\n**Repeatable:** No\n**Can Be Shrouded?:** No\n**Quest Type:** Task\n**Group Size:** Solo\n\nThis seasonal task is given to you by Inis Zidas [npc=60694] in Field of Bone at /way -1952, 2719, 7 in front of the ruins that lead to East Cabilis in the south western part of the zone\nYou say, 'Hail, Inis Zidas'\nInis Zidas says, 'Hail, ______. Watch your step. Strange things are afoot. Did you [notice] the bones rising from their final resting places?'\nYou say, 'Yes, I did notice some bones out of place.'\nInis Zidas says, 'There is so much lore and history to this land. It's hard to know what is causing this upheaval. I have a few theories, but I am not much for [fieldwork].'\nYou say, 'I can help with fieldwork'\nInis Zidas says, 'That is very helpful. Let me think. I think we will go with one of the more well-known lore to investigate. You need to gather a few ingredients and then offer them to the unsettled spirits.'\nSomething has disturbed the long dead In the Field of Bone. Piles of bones are surfacing from their long rest. Inis Zidas Is worried that some long forgotten monster of yore is causing the bones to become restless.\nShe has asked that you make an offering to the spirits to see If you can learn more.\nHarvest blood from scaled wolves\nHarvest bone chips from Iksar skeletons\nTask Steps:\n- 1. Harvest blood from scaled wolves 0/1 The Field of Bone\na scaled wolf pup count for this step. Note: these update upon kill, no actual item to collect.\nIf successful: A scaled wolf pup bleeds just enough blood onto its scales that can be collected.\nOn failure: A scaled wolf pup is obliterated with your final attack. There's no way you're getting a usable piece of blood from this one.\n- 2. Harvest bone chips from iksar skeletons 0/1 The Field of Bone\nKilling skeletons updates this step. a decaying skeleton counts.\nSame as above, there is a success and failure on getting the update.\n- 3. Harvest scorpion chitin 0/1 The Field of Bone\nKilling scorpions updates this step. a scorpion or a large scorpion counts for this step.\nSame success and failure system.\n- 4. Enter the southwestern ruined tower 0/1 The Field of Bone\nGround level the solo building most middle west of the zone\n/way -1032, 2187, -52\n- 5. Wait for the spirits to accept your offering 0/1 The Field of Bone\nWait at the spot.\nYour offerings have been accepted by the spirits. You have received a vial of the Blood of Chosooth.\nYour task 'Blood for Stone' has been updated.\n- 6. Pour the blood of Chosooth on pile of bones 0/6 The Field of Bone\nTarget the Pile of Bones (its on Find) at the same spot and click the item you were given Blood of Chosoot.\nYou have received Ink Stained Hand.\nClicking on the same pile gives you this message: The blood of Chosooth soaks these bones. Best to find a different pile.\nYou can find other piles at these locations.\n/way +596.74, +863.17, -51.60\n/way +2086.83 ,+140.47, -42.16\n/way -1839.33, -300.22, -51.63\n/way 1953.63, +146.75, -51.64\n/way -861.22, +1174.62, -73.99\n/way +1143.99, +1641.17, +51.94\n/way +1376.34, +1384.42, +46.49\n/way +1154.35, +1641.08, -51.07\n/way -2174.11, +1582.42, -50.19\n- 7. Find a relic in the pile of bones 0/1 The Field of Bone\nYou pour the Blood of Chosooth on a pile of bones.\nYou have received a Forgotten Talisman.\n- 8. Find a relic in the pile of bones 0/1 The Field of Bone\nYou pour the blood of Chosooth on a pile of bones.\nYou receive a Ink Stained Hand.\n- 9. Deliver the Forgotten Talisman to Inis 0/1 The Field of Bone\nYou offered 1 Forgotten Talisman to Inis Zidas.\n- 10. Deliver the Ink Stained Hand to Inis 0/1 The Field of Bone\nYou offered 1 Ink Stained Hand to Inis Zidas.\n- 11. Hail Inis Zidas after delivering the relics 0/1 The Field of Bone\nYou say, 'Hail, Inis Zidas'\nYour task 'Blood for Stone' has been updated.\nYou have helped Inis Zidas lay the risen piles of bone to rest.\nInis Zidas says, 'Those relics you found out of those remains are just fascinating. I just can't imagine we can possibly learn more about them. Too much time has passed and there are no real distinguishing marks on them.  This [Ink Stained Hand] being so close to the Kaesora library makes me think it belongs there.'\nReward(s):\nYou have successfully been granted your reward for: Blood for Stone\n'Sanguine Seltzer'  x5 Drink\nSubmitted by: larthRewards:\n[",
    },
    {
      id = "7076",
      title = "Gravedigging",
      exp = "03",
      exp_name = "The Shadows of Luclin",
      min_lvl = 30,
      max_lvl = 125,
      quest_type = "Quest",
      repeatable = false,
      group_size = "Solo",
      npc = "a glyph covered corpse",
      loc = { y = -750.0, x = -1540.0, z = 3.75 },
      triggers = {
        "Hail Tvan Gurrish",
        "I am interested.",
        "What fellow?",
        "What item?",
        "What words?",
        "I want the scroll.",
      },
      items_required = {
        { name = "them to you", count = 1 },
      },
      rewards = {
        { id = 102894, name = "Sara's Porcelain Mask", type = "item" },
      },
      factions = {
      },
      walkthrough = "**Level:** 30\n**Maximum Level:** 125\n**Monster Mission:** No\n**Repeatable:** No\n**Can Be Shrouded?:** No\n**Quest Type:** Quest\n**Group Size:** Solo\n\nTvan Gurrish may be found along the short path behind the chapel in the graveyard area at -750, -1540, +3.75.  He tends to get attacked and killed by \"a glyph covered corpse.\"\nYou say, 'Hail Tvan Gurrish'\nTvan Gurrish says 'Bah, this is insane. We can't go through with this. Maybe you'd like to pick up some coin, eh? Are you interested?\nYou say, 'I am interested.'\nTvan Gurrish says 'We were supposed to go up to the graveyard and do a bit of digging, if you know what I mean. There's a fellow that we met up with in a tavern in Shadowhaven that hired us to do this.'\nYou say, 'What fellow?'\nTvan Gurrish says 'He was odd looking, but he seemed normal enough and he paid us half up front. He said that we'd get the rest when we brought the item back to him.'\nYou say, 'What item?'\nTvan Gurrish says 'We're not sure. He said we'd know when we saw it. He said to find a grave with black flowers on it and dig it up. Also, we said that we'd need to say a few words before digging. Just in case it was trapped. Here's the scary part. He wrote the words down for us.'\nYou say, 'What words?'\nTvan Gurrish says 'It looks like a bunch of gibberish to me. If you want them. I'll give them to you. The second that you take the scroll, this is your deal. We don't want no part of this mess. Do you want the Scroll?'\nYou say, 'I want the scroll.'\nYou receive an Ale Stained Note and Tvan despawns.  The note reads:\nSpeak these words\nonce you\nget to the grave\nDal Mar Resh\nGo to the graveyard and you'll find a grave to the left of Guard Lennon with an item on top of it which is a Dried Floral Bouquet.  Once you're in front of the grave say the words \"Dal Mar Resh\".\nA tortured abomination will spawn and start attacking you.\nIt drops an item called Sara's Porcelain Mask.Submitted by: WizorbRewards:\n- Sara's Porcelain Mask [item=102894]\n[",
    },
    {
      id = "8643",
      title = "Conqueror of Katta Castellum",
      exp = "03",
      exp_name = "The Shadows of Luclin",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "Achievement",
      repeatable = false,
      group_size = "Solo",
      npc = "Lcea Katta",
      loc = nil,
      triggers = {
        "arx key",
      },
      items_required = {
        { id = 7000, name = "Item #7000", count = 1 },
        { id = 29860, name = "Item #29860", count = 1 },
        { id = 7810, name = "Item #7810", count = 1 },
      },
      rewards = {
        { id = 17613, name = "Item #17613", type = "item" },
        { id = 29860, name = "Item #29860", type = "item" },
        { id = 29861, name = "Item #29861", type = "item" },
      },
      factions = {
      },
      walkthrough = "**Level:** 1\n**Maximum Level:** 125\n**Monster Mission:** No\n**Repeatable:** No\n**Can Be Shrouded?:** No\n**Quest Type:** Achievement\n**Group Size:** Solo\n\nThis achievement is gained upon defeating the following raids in Katta Castellum:\nLcea Katta\nNathyn IllumniousSubmitted by: GidonoRewards:\n[",
    },
  },
}
