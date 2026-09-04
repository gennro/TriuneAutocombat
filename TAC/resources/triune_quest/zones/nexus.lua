-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for Nexus (nexus)
-- Total Quests: 1
-- ============================================================================

return {
  zone = "nexus",
  zone_name = "Nexus",
  quests = {
    {
      id = "8259",
      title = "Access to Empires of Kunark (The Nexus Portal)",
      exp = "03",
      exp_name = "The Shadows of Luclin",
      min_lvl = 1,
      max_lvl = 130,
      quest_type = "Quest",
      repeatable = false,
      group_size = "Solo",
      npc = "Fani Dertrimas",
      loc = nil,
      triggers = {
        "power",
      },
      items_required = {
        { name = "you the stone", count = 1 },
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "**Level:** 1\n**Maximum Level:** 130\n**Monster Mission:** No\n**Repeatable:** No\n**Can Be Shrouded?:** No\n**Quest Type:** Quest\n**Group Size:** Solo\n\nInformation on how to access The Nexus Portal to Empires of Kunark.\nSpeak to any of the 4 NPC's in the center of The Nexus.\nFani Dertrimas\nJayson Bri`Tian\nKardador Tarsinian\nPersy Clutches\nJayson Bri`Tian says 'Ahh, welcome {name]. It is good to see more and more people visiting now that the portals are functional. It took us many, many years to understand the magical powers of Luclin. Whether through dumb luck or divine intervention, we have succeeded in opening the gate back to Norrath. How long it will stay open, no one knows. I hope you know the importance of the stone that lies beneath our feet and the power that the Combine have been able to harvest from it? Even if you do not, we are willing to allow you to use that  'power'. My colleagues and I are here to maintain and watch for changes in the Nexus- should anything happen, you will be notified. Safe travels.'\nYou say, 'power'\nHe hands you a Spire Stone of Lceanium [item=126769]. Stand in the center near the NPC's that give you the stone. Soon you will be ported.\nJayson Bri`Tian says 'We, of course, have tapped into the power of transportation, as I'm sure you realize. With the restoration of our great Emperor... I mean Lord Katta, we have been asked to help those that wish to visit his new seat of power. If you wish to go there, this very spire will take you. All you need is a Spire Stone of Lceanium and you will be safely transported to the city. We have set up this great spire to transport anyone holding such a stone every few minutes, as the cycle of power peaks. It is no minor magical feat to send a large group of creatures safely from Luclin to Kunark! But feel assured that we can do so, and we almost never lose any transportees.'\nJayson Bri`Tian says 'Here is your Spire Stone. Remember, if you are holding that stone and remain in the area of the spire, you will be transported. The stone is fragile and will be consumed if you travel by the spire or just about any other means. Not to worry, we can provide you another if needed.'\n-\nA Mystic Voice says, 'The portal to Lceanium will become active in 20 seconds. Please gather in the portal area and make sure you have your Spire Stone of Lceanium on your person.\nA Mystic Voice says, 'The portal to Lceanium will become active in 10 seconds. Please gather in the portal area and make sure you have your Spire Stone of Lceanium on your person.\nA Mystic Voice says, 'The portal to Lceanium is now active. Please stand on the pad and you will be teleported shortly. Enjoy your time in the city.'Rewards:\n[",
    },
  },
}
