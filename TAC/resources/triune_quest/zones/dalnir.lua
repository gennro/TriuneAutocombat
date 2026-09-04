-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for Dalnir (dalnir)
-- Total Quests: 1
-- ============================================================================

return {
  zone = "dalnir",
  zone_name = "Dalnir",
  quests = {
    {
      id = "8598",
      title = "Hunter of The Crypt of Dalnir",
      exp = "01",
      exp_name = "The Ruins of Kunark",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "Achievement",
      repeatable = false,
      group_size = "Solo",
      npc = "a spectral crusader",
      loc = nil,
      triggers = {
        "greenmist",
        "golin",
        "visceral dagger",
        "grand forge",
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "**Level:** 1\n**Maximum Level:** 125\n**Monster Mission:** No\n**Repeatable:** No\n**Can Be Shrouded?:** No\n**Quest Type:** Achievement\n**Group Size:** Solo\n\nThis achievement is gained upon defeating the following rare monsters in The Crypt of Dalnir.\na coerced crusader\na coerced penkeeper\na coerced revenant\na shy kly imprecator\na sly kly imprecator\na spectral crusader\na wry kly imprecator\nan undead blacksmith\nlumpy goo\nThe Kly\nAdd the following points to the dalnir_1.txt file:\nP 77.4226, 320.3235, -181.9354,    0, 127, 0,  3,      Warsliks_Woods\nP -95.0000, 6.0000, 0.0030,        0, 127, 0,  3,      Warsliks_Woods\nP 734.8867, -294.0582, -83.9667,   0, 127, 0,  3,      Warsliks_Woods\nP 546.1126, -10.2247, -195.9042,   240, 240, 240,  2,  1_Way_Tunnel\nP 731.1360, -97.1830, 0.0020,      240, 240, 240,  2,  1_Way_Crypt_Entrance_to_Sublevel_2\nP 414.5617, 6.9124, -196.9042,     240, 240, 240,  2,  Ramp_To_Sublevel_3\nP 748.6304, -3.6808, -96.2103,     240, 240, 240,  2,  Floor_trap_to_Sublevel_4\nP -30.6805, 229.5394, -181.9354,   127, 64, 0,  2,     Grand_Forge_of_Dalnir_(Forge)\nP -54.0358, 17.5478, -180.4101,    0, 0, 240,  2,      Lost_Scroll_Enchanter_Epic_1.0_(ground_spawn)\nP 195.5580, 217.4890, -179.9697,   0, 0, 240,  2,      Sarnak_Hide_(ground_spawn)\nP 449.4919, -156.8183, 1.5301,     0, 0, 240,  2,      Journal_Entry_(ground_spawn)\nP 684.8544, 47.6895, -194.3727,    0, 0, 240,  2,      Journal_Entry_(ground_spawn)\nP 337.4526, -120.7924, -181.9354,  0, 0, 240,  2,      Journal_Entry_(ground_spawn)\nP 63.6416, 297.5723, -180.4055,    0, 0, 240,  2,      Journal_Entry_(ground_spawn)\nP 754.3751, 51.0468, -96.4320,     0, 0, 240,  2,      Artisan's_Arrowhead_(ground_spawn)\nP 746.7036, 11.5859, -95.1343,     127, 0, 0,  2,      Pit\nAdd the following points to the dalnir_2.txt file:\nP 915.7758, -275.2486, -82.4320,   240, 0, 0,  3,  a_coerced_crusader\nP 692.7144, 46.3299, -194.3095,    240, 0, 0,  3,  a_coerced_penkeeper\nP 340.7253, -150.3004, -180.4070,  240, 0, 0,  3,  a_coerced_revenant\nP 78.3344, 305.4262, -179.9582,    240, 0, 0,  3,  The_Kly\nP 903.0922, -95.5478, -81.4407,    240, 0, 0,  3,  lumpy_goo\nP 608.9127, -214.5916, -191.8108,  240, 0, 0,  3,  a_shy_kly_imprecator\nP 149.0560, -7.8649, -179.9061,    240, 0, 0,  3,  a_sly_kly_imprecator\nP 340.7253, -150.3004, -180.4070,  240, 0, 0,  3,  a_spectral_crusader\nP 692.7144, 46.3299, -194.3095,    240, 0, 0,  3,  an_undead_blacksmith\nP 889.0955, -257.5009, -80.8446,   240, 0, 0,  3,  a_wry_kly_imprecator\nP 732.3141, -159.2019, -81.9845,   240, 0, 0,  3,  an_iksar_prisoner\nAdd the following points to the dalnir_3.txt file:\nP 0.0000, 0.0000, 0.0000,        127, 64, 0,  2,  0\nP 0.0000, -575.0000, 0.0000,     127, 64, 0,  2,  0\nP 500.0000, -575.0000, 0.0000,   127, 64, 0,  2,  -500\nP 1000.0000, -575.0000, 0.0000,  127, 64, 0,  2,  -1000\nP -128.0000, -510.0000, 0.0000,  127, 64, 0,  2,  500\nP -128.0000, -260.0000, 0.0000,  127, 64, 0,  2,  250\nP -128.0000, 0.0000, 0.0000,     127, 64, 0,  2,  0\nP -128.0000, 240.0000, 0.0000,   127, 64, 0,  2,  250\nP -128.0000, 490.0000, 0.0000,   127, 64, 0,  2,  -500\nP 510.0000, 240.0000, 0.0000,    127, 64, 0,  2,  File_Set_=_dalnir.txt\nP 510.0000, 300.0000, 0.0000,    0, 0, 0,  2,     Progression\nP 510.0000, 350.0000, 0.0000,    0, 0, 0,  2,      1._Main_Level\nP 510.0000, 400.0000, 0.0000,    0, 240, 240,  2,  2._Crypt_Entrance_to_Sublevel_2\nP 510.0000, 450.0000, 0.0000,    240, 127, 0,  2,  3._Floor_Trap_to_Sublevel_4\nP 510.0000, 500.0000, 0.0000,    0, 240, 0,  2,    4._Ramp_To_Sublevel_3 Submitted by: GidonoRewards:\n[",
    },
  },
}
