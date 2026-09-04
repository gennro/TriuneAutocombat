-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for Stoneroot Falls (westkorlach)
-- Total Quests: 1
-- ============================================================================

return {
  zone = "westkorlach",
  zone_name = "Stoneroot Falls",
  quests = {
    {
      id = "3186",
      title = "DoD Level 68 Spell \\#1: A Rogue's Trust",
      exp = "10",
      exp_name = "Depths of Darkhollow",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Kelliad",
      loc = { y = 705.0, x = -1830.0, z = 0.0 },
      triggers = {
        "Hail, Kelliad",
        "Gone?",
        "You can trust me",
        "I am willing to do this job",
        "Hail, Meldrek",
        "Where is the alternate entrance to Xill?",
        "We wish to continue.",
        "We are ready to go.",
      },
      items_required = {
        { name = "the four hearts to Kalliad to finish the task", count = 1 },
      },
      rewards = {
        { id = 45828, name = "Drachnid Heart", type = "item" },
        { id = 45164, name = "Corroded Infantry Boots", type = "item" },
        { id = 45166, name = "Drachnid Empath Stone", type = "item" },
        { id = 45075, name = "Greater Spiked Staff", type = "item" },
        { id = 44678, name = "Loose Weave Legs", type = "item" },
        { id = 45167, name = "Mail of the Xillian Scout", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Stoneroot Falls [zone=297]\n**Who:**\n- Kelliad [npc=19190]\nRating:\n0/1**_\\*__\\*__\\*__\\*__\\*_**\n(From 1 rating)\nInformation:\n**Level:** | 65\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | Yes\n**Can Be Shrouded?:** | No\n**Quest Type:** | Task\n**Quest Goal:**\n- Loot\n- Spell\n**Time Limit:** | 06:00:00\n**Faction Required:**\nFree Traders of Malgrinnor (Min: Apprehensive)\n**Quest Items:**\n- Drachnid Heart [item=45828]\n**Related Zones:**\n- Stoneroot Falls: A Rogue's Trust [zone=307]\n**Related Creatures:**\n- Meldrek [npc=19228]\n- Meldrek [npc=19229]\n- a dark mystical chest - A Rogue's Trust [npc=19417]\n- a drachnid [npc=19230]\n**Related Quests:**\n- DoD Level 68 Spell #2: Scouting the City [quest=3213]\n- DoD Level 68 Spell #3: Building the Disguise [quest=3202]\n- DoD Level 68 Spell #4: The Search for Ilsuras [quest=3229]\n- DoD Level 68 Spell #5: The Rage of Kelliad [quest=3230]\n**Era:** | !Depths of Darkhollow\nRecommended:\n**Group Size:** | Group\n**Min. # of Players:** | 3\n**Max. # of Players:** | 6\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Mon Sep 19 20:49:57 2005\nModified: Tue Dec 5 05:21:04 2023 | | _This is the first task in a series of five (the end result being your 68th level spell/tome). It begins with Kelliad in the Stoneroot Falls at location +705, -1830 (northeastern part of the zone)._\nYou say, 'Hail, Kelliad'\nKelliad looks around confused before saying, 'Ilsuras? Is that you?\"\nKellaid looks closer at you and says, 'You're not Ilsuras. I thought you might have been him. He was one of our trusty scounts and he has been [gone] awhile now and the longer that he is missing the more worried I get.'\nYou say, 'Gone?'\nKelliad says, 'I'm not sure that I aan [trust you]. Perhaps in tiem I might be able to trust one such as yourself but you have done nothing to allow me to trust you.'\nYou say, 'You can trust me'\nKelliad says 'I want you to prove that you are what you appear to be. Outside the city of Xill you will find a great scout that goes by the name of Meldrek. Speak with him and he will show you a way into Xill. When you enter Xill, the wall will be protected by guards. Kill them and bring me back 4 of their hearts. Are you willing to [do this job] for me?'\nYou say, 'I am willing to do this job'\nYou have been assigned the task 'A Rogue's Trust'.\nYou have come across a strange being in Kelliad. He does not trust many of his own kind, let alone strangers. You must complete this task to gain his trust.\n\n---\n\nSeek out Meldrek and ask him about an alternate entrance into Xill 0/1 (Stoneroot Falls)\n_Go south along the shore to +210, -1845._\nYou say, 'Hail, Meldrek'\nMeldrek says 'Duck down \\_\\_\\_\\_\\_, before you are seen. This area is crawling with drachnids. What can I help you with?'\nYou say, 'Where is the alternate entrance to Xill?'\nMeldrek pauses for a second then turns and says, 'How can I put this, Kelliad has lost touch of reality. I will help you enter Xill but I can't be responsible for you after you enter. Do you [wish to continue] with this adventure?'\nYou say, 'We wish to continue.'\nLOADING, PLEASE WAIT...\nYou have entered Stoneroot Falls: The City of Xill.\n_You enter an instanced version of Stoneroot Falls. You appear before Meldrek, who will send you out of the zone if you ask him._\nExplore the front gates of Xill 0/1 (Stoneroot Falls)\n_If you have a map, it's pretty obvious where this is: To the south and west (as you would head to The Hive)._\nLay waste to twenty-five drachnids 0/25 (Stoneroot Falls)\n_Simple enough: Kill any 25 drachnids in the zone. They come in several classes (including shaman) and are charmable. Some have an AE called Dark Venom Spray, can proc Puncture and Vile Web, and can hit for up to ~1,200 (average of 600). They are \"mostly\" slowable._\nTear out four drachnid hearts for proof of their deaths 0/4 (Stoneroot Falls)\n_You'll come across plenty of these. Keep four of them to update the last step in the task._\nReturn to Kelliad with the drachnid hearts 0/1 (Stoneroot Falls)\nYou say, 'Hail, Meldrek'\nMeldrek says 'This is as far as I go. When you complete your objective for Kelliad return to me and when you're [ready to go] I will make sure you have a safe return back to Kelliad.'\nYou say, 'We are ready to go.'\n_Hand in the four hearts to Kalliad to finish the task. Priest and caster archetypes receive a Pain-Infused Mask. Melee and hybrid archetypes receive a Warped Mask._\nYou have completed the task for Kelliad. Speak with him to explore the city of Xill further.\n\n---\n\n_Near the gates of Xill at -785, -700 is \"a dark mystical chest\". This can be opened after you've killed the 25 drachnids and contains one loot item._\n_Completion of this task leads into the next task in the series, \"Scouting the City\"._\n**Submitted by:** Henora, Drunken Tsunami\n- Corroded Infantry Boots [item=45164]\n- Drachnid Empath Stone [item=45166]\n- Greater Spiked Staff [item=45075]\n- Loose Weave Legs [item=44678]\n- Mail of the Xillian Scout [item=45167]\n- Pain-Suffused Mask [item=44676]\n- Shiliskin Flesh Gloves [item=45165]\n- Warped Mask [item=44677]",
    },
  },
}
