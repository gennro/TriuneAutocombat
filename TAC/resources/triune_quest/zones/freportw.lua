-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for Freportw (freportw)
-- Total Quests: 1
-- ============================================================================

return {
  zone = "freportw",
  zone_name = "Freportw",
  quests = {
    {
      id = "577",
      title = "Hogcaller's Inn",
      exp = "03",
      exp_name = "The Shadows of Luclin",
      min_lvl = 14,
      max_lvl = 125,
      quest_type = "Quest",
      repeatable = true,
      group_size = "Solo",
      npc = "Plagus Ladeson",
      loc = nil,
      triggers = {
        "Hail, Plagus Ladeson",
        "new warrior",
        "seek deeds",
        "The Steel Warriors sent me",
        "I need the mail for room two",
        "veteran",
        "crave battle",
        "Steel Warriors sent you",
      },
      items_required = {
        { name = "the key to Swin Blackeye", count = 1 },
        { name = "it to Lady Shae", count = 1 },
        { name = "her the box", count = 1 },
      },
      rewards = {
        { id = 1964, name = "Leather Tunic", type = "item" },
        { id = 1079, name = "Round Shield", type = "item" },
      },
      factions = {
        { name = "Emerald Warriors", change = 1 },
        { name = "Indigo Brotherhood", change = -1 },
        { name = "Merchants of Felwithe", change = 1 },
        { name = "Kelethin Merchants", change = 1 },
        { name = "Steel Warriors", change = 10 },
        { name = "Guards of Qeynos", change = 2 },
      },
      walkthrough = "**Time:** 0\n**Level:** 14\n**Maximum Level:** 125\n**Monster Mission:** No\n**Repeatable:** Yes\n**Can Be Shrouded?:** No\n**Quest Type:** Quest\n**Group Size:** Solo\n\nPlagus Ladeson is located in the warrior's guild, below the Arena.\nYou say, 'Hail, Plagus Ladeson'\nPlagus Ladeson says 'Greetings, your name, and welcome to the bunker.  Are you a [new warrior] or a [veteran]?'\nYou say, 'new warrior'\nPlagus Ladeson says 'Good to know you chose the bunker to train you.  It is the home of the Steel Warriors.  We find our inner strengths grow through battles and other noble deeds.  Do you [seek deeds] or [crave battle] ?'\nYou say, 'seek deeds'\nPlagus Ladeson says 'It may not be a fray, but who ever said we Steel Warriors are nothing but brawn? Recently, there have been reports of frequent visits by dark elves to the Hog Caller's Inn here in Freeport. Go speak with Lady Shae. Tell her the [Steel Warriors sent you]. We cannot rely on the Freeport Militia to look into such matters. They are probably involved.  Bring me any clues you find.'\nLady Shae is inside Hogcaller's inn in West Freeport.\nYou say, 'The Steel Warriors sent me'\nLady Shae says 'Thank you for checking into this matter. I told the militia, but they just ignored me. It appears the dark elves keep coming in and leaving mail for Shintl Lowbrew. Before I tell you more, could you please buy me a white wine?'\nLady Shae says, 'Thank you.  Pandos has been telling me to try white wine forever.  I mostly only drink red wine. Pardon me for getting off track.  Anyway, it is a good thing you showed up.  The lady in room two has been receiving mail from a dark elf.  You [need the mail for room two].  The innkeeper usually holds it for the guests.'\nYour faction standing with Emerald Warriors has been adjusted by 1.\nYour faction standing with Indigo Brotherhood has been adjusted by -1.\nYour faction standing with Merchants of Felwithe has been adjusted by 1.\nYour faction standing with Kelethin Merchants has been adjusted by 1.\nThe innkeeper is Swin Blackeye who just sold you the wine.\nYou say, 'I need the mail for room two'\nSwin Blackeye says 'Hmmph !  If you're here to get the mail for room two, you'll need to show me the room key.'\nShintl Lowbrew, a female halfling, is usually inside room #2 on the second floor of the inn. Once in a while, she gets down to check her mail, leaving her room key on the floor. Pick the key. In case she doesn't; you may also kill her to get her key (then don't forget to loot her head too).\nGive the key to Swin Blackeye .\nSwin Blackeye says 'Here you go, then...'\nYou get a Sealed Letter.\nGo back to Plagus Ladeson in East Freeport and hand him the letter.\nPlagus Ladeson says 'Oh my!  Opal?  She is providing these agents of Neriak with information regarding the academy's secrets?!  I cannot tell Cain about this.  He will be furious.  Show this to Toala.  She will know what to do.'\nToala is located inside another room of the warrior's guild.\nToala Nehron says 'Why, that little trollop!  What is she up to?  Cain will never believe this!  She must be in league with some faction of the dark elves, but why?  Neither the Academy of Arcane Science nor Cain will believe this note.  I will see what I can do.  As for you, I command you to kill this Shintl and her dark elf courier!  Put their heads into this box and combine them.  We shall cut the link.  Bring me her head.'\nYou receive Toala's Box for Heads.\nGo back to the Hogcaller's Inn in West Freeport.\nKill Shintl Lowbrew and loot her head.\nBuy another white wine and give it to Lady Shae. This spawns Hollish T'noops, the dark elf courier. He walks from the West Freeport entrance to the inn in about 1 minute.\nKill Hollish T'noops and loot his head.\nCombine the two heads in Toala's Box for Heads to create Box with Two Heads.\nGo back to Toala Nehron in East Freeport and give her the box.\nToala Nehron says 'Good work!  We will soon catch Opal.  I have started to formulate a plan to stop her.  When I complete it, I shall notify you.  Here.  Take this small reward.  I am sure killing Shintl was no trouble.  She was just a halfling.'\nToala Nehron gives you a random piece of armor.\nYour faction standing with Steel Warriors has been adjusted by 10.\nYour faction standing with Guards of Qeynos has been adjusted by 2.\nYour faction standing with Corrupt Qeynos Guards has been adjusted by -1.\nYour faction standing with The Freeport Militia has been adjusted by -1.\nYour faction standing with Knights of Truth has been adjusted by 2.\nYou gain experience!!\nYou receive 2 silver from Toala Nehron.\nYou receive 1 platinum from Toala Nehron.Submitted by: AerykRewards:\n- Leather Tunic [item=1964]\n- Round Shield [item=1079]\n[",
    },
  },
}
