-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for Jewel of Atiiki (atiiki)
-- Total Quests: 1
-- ============================================================================

return {
  zone = "atiiki",
  zone_name = "Jewel of Atiiki",
  quests = {
    {
      id = "4142",
      title = "Efreeti Death Visage",
      exp = "13",
      exp_name = "The Buried Sea",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "",
      repeatable = false,
      group_size = "",
      npc = "Noble Sivrn",
      loc = nil,
      triggers = {
        "Hail, Noble Sivrn",
        "Hail, Noble Phren",
        "It is Platinum Efreeti armor",
        "Hail, Paza",
        "D`nik Belm J`cof Ghap",
        "armor",
      },
      items_required = {
        { name = "him the Breastplate:_", count = 1 },
        { name = "him the Greaves:_", count = 1 },
        { name = "him the Vambraces:_", count = 1 },
        { name = "him the Gauntlets:_", count = 1 },
        { name = "him the Bracer:_", count = 1 },
        { name = "him the Boots:_", count = 1 },
      },
      rewards = {
        { id = 66477, name = "Platinum Efreeti Boots", type = "item" },
        { id = 65964, name = "Platinum Efreeti Bracer", type = "item" },
        { id = 65725, name = "Platinum Efreeti Chestplate", type = "item" },
        { id = 66194, name = "Platinum Efreeti Gauntlets", type = "item" },
        { id = 65841, name = "Platinum Efreeti Greaves", type = "item" },
        { id = 66149, name = "Platinum Efreeti Helm", type = "item" },
      },
      factions = {
      },
      walkthrough = "Quest Started By: | Description:\n**Where:**\n- Jewel of Atiiki [zone=475]\n**Who:**\n- Noble Sivrn [npc=24728]\nRating:\n0/6**_\\*__\\*__\\*__\\*__\\*_**\n(Average from 6 ratings)\nInformation:\n**Level:** | 75\n**Maximum Level:** | 125\n**Monster Mission:** | No\n**Repeatable:** | No\n**Can Be Shrouded?:** | No\n**Quest Type:** | Quest\n**Quest Goal:**\n- Loot\n**Quest Items:**\n- Platinum Efreeti Boots [item=66477]\n- Platinum Efreeti Bracer [item=65964]\n- Platinum Efreeti Chestplate [item=65725]\n- Platinum Efreeti Gauntlets [item=66194]\n- Platinum Efreeti Greaves [item=65841]\n- Platinum Efreeti Helm [item=66149]\n- Platinum Efreeti Mask [item=67316]\n- Platinum Efreeti Vambraces [item=66396]\n- Token of Order [item=65863]\n**Related Creatures:**\n- Azia [npc=24921]\n- Beza [npc=24922]\n- Caza [npc=24923]\n- Dena [npc=24924]\n- Ena [npc=24925]\n- Fana [npc=24926]\n- Geza [npc=24927]\n- Heda [npc=24928]\n- Izah [npc=24933]\n- Jaka [npc=24930]\n- Kala [npc=24931]\n- Lena [npc=24932]\n- Mahatototarit [npc=24796]\n- Meda [npc=24934]\n- Neza [npc=24935]\n- Noble Phren [npc=24949]\n- Ozah [npc=24929]\n- Paza [npc=25303]\n- Xanxionusus [npc=24939]\n**Related Quests:**\n- Sivrn #1: Names of the Sphinx [quest=4100]\n- Sivrn #2: Atiiki Tongue Twisting [quest=4111]\n- Sivrn #3: Order Squared [quest=4112]\n- Sivrn #4: Realign the Lines [quest=4124]\n- Sivrn #5: Broken Lines [quest=4125]\n**Era:** | !The Buried Sea\nRecommended:\n**Group Size:** | Solo\n**Min. # of Players:** | 1\n**Max. # of Players:** | 1\n**Appropriate Classes:**\n- All\n**Appropriate Races:**\n- All\nEntered: Mon Mar 19 19:47:49 2007\nModified: Tue Dec 5 05:21:04 2023 | | _You may do this quest once you have completed Noble Sivrn's task arc (starting with \"Names of the Sphinx\" [quest=4100] and ending with \"Broken Lines\")._\n_Hail Noble Sivrn again._\nYou say, 'Hail, Noble Sivrn'\nNoble Sivrn says 'Forgive me, I seem to have forgotten my promise to honor you with a token of respect for your ability to solve the puzzles that have confounded the most intelligent amongst us... Take this mask. It may seem common to the mortal eye, but for the efreeti, each mask reveals the soul of the being from whom it was created.'\n_Receive Platinum Efreeti Mask._\n_Now you will need a set of Platinum Efreeti armor, which drops off efreeti NPCs in both the static and instanced Jewel of Atiiki zones._\n_Once you have done so, see Noble Phren who is located right beside Sivrn in the Nobles' tower._\nYou say, 'Hail, Noble Phren'\nNoble Phren looks at you curiously, 'Is that Platinum Efreeti [armor] that you are carrying there with you?'\nYou say, 'It is Platinum Efreeti armor'\nNoble Phren says 'It may interest you to learn that Efreeti are not all equal in intellect. That armor you carry is a type of identifier that allows the more simple of my kind to identify one another... Although the armor you carry seems to bear odd markings, would you mind if I examined it more closely?'\n_Give him the Breastplate:_\nNoble Phren touches the strange symbols and reads, 'Azia looks to the west, and sees Izah in the far distance.'\n_Give him the Greaves:_\nNoble Phren says 'The inscription on this piece reads, 'From his corner, Kala opposes Geza in his corner.''\n_Give him the Vambraces:_\nNoble Phren tilts the armor to view it in better light, 'Caza is surrounded by seven mutual allies, and one mutual enemy directly North, while Ozah is surrounded by enemies on all sides and corners.'\n_Give him the Gauntlets:_\nNoble Phren says 'Odd, there is an inscription on this piece... 'Lena avoids the board perimeter while Jaka does not, and the Northeast remains vacant.''\n_Give him the Bracer:_\nNoble Phren reads quietly as he studies the armor, 'Meda stands neither in the East or the West, Heda stands neither in the North or the South.'\n_Give him the Boots:_\nNoble Phren says 'It seems as though someone has scribed these words into the armor itself, 'As Ena faces from North to West to South, he sees Lena, Neza, and Beza.''\n_Give him the Helm:_\nNoble Phren says 'This armor mentions our missing brother, Paza, how strange as he is believed to be dead... 'Geza stands directly East of Jaka, while Fana stands watch, awaiting the return of Paza.''\n_Give him the Mask:_\nNoble Phren studies the mask for a moment, 'The wisdom of Ateleka guides those who seek knowledge.'\n_Get a Token of Order (random Atiiki drop), equip ALL the pieces of armor including the mask, and go play a game of order from Mahatototarit. Disregard his text about the normal game setting and play it out according to what Phren had to say about each inscription. When you have reached the proper order, go to Mahatototarit and say, \"Done.\"_\nMahatototarit says 'A very interesting configuration, you have not exactly solved the puzzle, but you have managed to unlock a pattern that summons our lost Paza from the realm of the dead...'\n_Paza spawns by the game board. Hail him._\nYou say, 'Hail, Paza'\nPaza blinks for a moment as he studies you, 'Brother, my time is short, I have done as Xanxionusus commanded... I return from the other side with this message, D`nik Belm J`cof Ghap... Etch those words into your memory, and repeat them to Xanxionusus... Aaarrraaaaahhhh... I feel the pull of the other side once again, I beg you, take my mask so that my soul is released from this torment before I am drawn over once again...'\n_You receive the Efreeti Death Visage mask on your cursor._\nEfreeti Death Visage\nMagic Item, No Trade\nAC 32\nEffect: Illusion: Spectre (Casting Time: 5.0)\nSTR +15, Dex +15, CHA +20, WIS +15, INT +15, AGI +15\nHP +255, Mana +255, Endurance +255\nSV Disease +20, SV Cold +12, SV Magic +12, SV Poison +20\nRegeneration -2\nMana Regeneration -2\nShielding +2%, Spell Shield +2%, Accuracy +10%\nStun Resist +2%\nDoT Shielding +2%\nWeight 0.9, Size: Medium\nClass: All\nRace: ALL\nIllusion Spectre\nSpell Effect: Cloaks you in a chilling illusion that makes you appear to be a Spectre. This spell also grants infravision and see invis.\nItem Lore:\nThis is covered in strange symbols.\n_Necromancers take note. If you repeat Paza's phrase to Xanxionusus, you will see:_\nYou say, 'D`nik Belm J`cof Ghap'\nXanxionusus peers at you intently for a moment, then looks away and begins to whisper quietly in a strange voice, 'Paza has upheld the bargin, the recompense is granted as agreed... D`nik Belm J`cof Ghap!' the words fade as Xanxionusus fixes his gaze on you, 'I sense the darkness of your soul... These bones are no longer of any use to me; take them as compensation for your assistance in this matter... Leave quickly, and speak of this to no one.'\n_..and receive Paza's Cursed Remains_\nPaza's Cursed Remains\nMAGIC ITEM LORE ITEM NO TRADE\nCharges: Unlimited\nRequired level of 65.\nEffect: Form of Rotting Flesh (Any Slot/Can Equip, Casting Time: 5.0) at Level 75\nWT: 0.0 Size: TINY\nClass: ALL\nRace: ALL\n_If you repeat Paza's phrase to Xanxionusus as a non-necromancer, you will see this:_\nXanxionusus peers at you intently for a moment, then looks away and begins to whisper quietly in a strange voice, \"Paza has upheld the bargain, the recompense is granted as agreed... D`nik Belm J`cof Ghap!\" the words fade as Xanxionusus fixes his gaze on you, \"Although I am sure you acted out of ignorance, your assistance was useful... It would be best if you left now, I have many thoughts upon which to contemplate.\"\n_It is not known if there is anything further._\n**Submitted by:** LordAdam (Amberdina of Povar)\n- Efreeti Death Visage [item=67317]\n- Paza's Cursed Remains [item=67303]",
    },
  },
}
