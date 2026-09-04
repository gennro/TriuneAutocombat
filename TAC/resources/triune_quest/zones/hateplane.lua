-- ============================================================================
-- TRIUNE QUEST GUIDE: Zone Package for Hateplane (hateplane)
-- Total Quests: 5
-- ============================================================================

return {
  zone = "hateplane",
  zone_name = "Hateplane",
  quests = {
    {
      id = "8600",
      title = "Hunter of The Mines of Nurga",
      exp = "05",
      exp_name = "The Legacy of Ykesha",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "Achievement",
      repeatable = false,
      group_size = "Solo",
      npc = "A blood",
      loc = nil,
      triggers = {
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "**Level:** 1\n**Maximum Level:** 125\n**Monster Mission:** No\n**Repeatable:** No\n**Can Be Shrouded?:** No\n**Quest Type:** Achievement\n**Group Size:** Solo\n\nThis achievement is gained upon defeating the following rare monster in The Mines of Nurga:\na blood thirsty mine rat\nBlackguard Thabis\nDeath Caller Joepla\nDeath Knight Donkot\nFlame Chanter Breplish\nFrost Caller Ollikaz\nLife Drinker Krador\nMiner Gribok\nOverseer Henxsa\nOverseer Malam\nSlave Keeper Davirg\nSpirit Chanter Bibodik\nSpirit Weaver Tramix\nStabber Remmy\nTaskmaster Crizz\nTaskmaster Huflam\nTraitor Efuin\nTribal Elder\nAdd the following points to the nurga_1.txt file:\nP 919.5120, 836.4390, -175.9370,     0, 127, 0,  3,  Temple_of_Droga\nP -98.0000, 1034.0000, 0.0000,       0, 127, 0,  3,  Temple_of_Droga\nP 1799.1990, 2237.7661, 0.0010,      0, 127, 0,  3,  Frontier_Mountains\nP 1640.7893, 1959.7372, -46.9333,    0, 0, 240,  1,  sealed_journal\nP 926.8590, 2116.9211, -222.3053,    0, 0, 240,  2,  Rinnala_Sweetsong\nAdd the following points to the nurga_2.txt file:\nP 72.5490, 1265.4730, -191.9370,      240, 0, 0,  3,  Blackguard_Thabis\nP 614.3420, 1475.9310, -191.9370,     240, 0, 0,  3,  a_blood_thirsty_mine_rat\nP 377.0240, 1315.6300, -175.9370,     240, 0, 0,  3,  Death_Caller_Joepla\nP -1350.2650, 1643.3250, -276.6470,   240, 0, 0,  3,  Death_Knight_Donkot\nP -1160.5150, 1217.3440, -287.8740,   240, 0, 0,  3,  Flame_Chanter_Breplish\nP 904.4530, 1519.1350, -223.9050,     240, 0, 0,  3,  Frost_Caller_Ollikaz\nP 951.4240, 2066.8250, -175.9370,     240, 0, 0,  3,  Life_Drinker_Krador\nP 1268.9690, 2077.7271, -175.9370,    240, 0, 0,  3,  Miner_Gribok\nP -202.7580, 1127.1930, -191.9370,    240, 0, 0,  3,  Overseer_Henxsa\nP -625.9150, 1166.4490, -191.9370,    240, 0, 0,  3,  Overseer_Malam\nP 795.3400, 2261.0320, -223.9050,     240, 0, 0,  3,  Slave_Keeper_Davirg\nP -1351.4070, 1998.8850, -310.4900,   240, 0, 0,  3,  Spirit_Chanter_Bibodik\nP 1233.7740, 1782.5680, -175.9370,    240, 0, 0,  3,  Spirit_Weaver_Tramix\nP 1882.4850, 2052.4939, 14.7530,      240, 0, 0,  3,  Stabber_Remmy\nP 533.8440, 1155.4250, -175.9370,     240, 0, 0,  3,  Taskmaster_Crizz\nP 1250.1230, 1132.0380, -175.9370,    240, 0, 0,  3,  Taskmaster_Huflam\nP 618.4970, 1938.5470, -223.9050,     240, 0, 0,  3,  Traitor_Efuin\nP -1201.7784, 1413.8424, -270.3611,   240, 0, 0,  3,  Tribal_Elder\nP -151.5680, 1153.5190, -191.9370,    240, 0, 0,  3,  Overseer_Pruckib\nP 938.3440, 2132.3191, -223.9050,     240, 0, 0,  3,  Slave_Du_Jour\nP -1327.8740, 1960.6591, -322.3540,   240, 0, 0,  3,  Slave_Driver_Nimol\nP 69.5410, 1491.8060, -191.9370,      240, 0, 0,  3,  a_sleeping_ogre\nP -1426.5150, 1703.3040, -279.8740,   240, 0, 0,  3,  Taskmaster_Yajo\nP -1345.2543, 1287.2512, -286.2935,   240, 0, 0,  3,  The_Bone_Seer\nP -609.3956, 1693.1078, -221.7581,    240, 0, 0,  3,  The_Rockchanter\nP -369.4305, 1106.8206, -190.3001,    240, 0, 0,  3,  Tribal_Mineralist\nP -1323.6097, 1999.7797, -307.7020,   240, 0, 0,  3,  Zusuu\nAdd the following points to the nurga_3.txt file:\nP -2500.0000, 0.0000, 0.0000,      127, 64, 0,  2,  2500\nP -2000.0000, 0.0000, 0.0000,      127, 64, 0,  2,  2000\nP -1500.0000, 0.0000, 0.0000,      127, 64, 0,  2,  1500\nP -1000.0000, 0.0000, 0.0000,      127, 64, 0,  2,  1000\nP -500.0000, 0.0000, 0.0000,       127, 64, 0,  2,  500\nP 0.0000, 0.0000, 0.0000,          127, 64, 0,  2,  0\nP 500.0000, 0.0000, 0.0000,        127, 64, 0,  2,  -500\nP 1000.0000, 0.0000, 0.0000,       127, 64, 0,  2,  -1000\nP 1500.0000, 0.0000, 0.0000,       127, 64, 0,  2,  -1500\nP 2000.0000, 0.0000, 0.0000,       127, 64, 0,  2,  -2000\nP -2703.0000, 490.0000, 0.0000,    127, 64, 0,  2,  -500\nP -2703.0000, 990.0000, 0.0000,    127, 64, 0,  2,  -1000\nP -2703.0000, 1490.0000, 0.0000,   127, 64, 0,  2,  -1500\nP -2703.0000, 1990.0000, 0.0000,   127, 64, 0,  2,  -2000\nP -2703.0000, 2490.0000, 0.0000,   127, 64, 0,  2,  -2500\nP 0.0000, 2990.0000, 0.0000,       127, 64, 0,  2,  File_Set_=_nurga.txtSubmitted by: GidonoRewards:\n[",
    },
    {
      id = "8602",
      title = "Hunter of Veksar",
      exp = "05",
      exp_name = "The Legacy of Ykesha",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "Achievement",
      repeatable = false,
      group_size = "Solo",
      npc = "A blood",
      loc = nil,
      triggers = {
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "**Level:** 1\n**Maximum Level:** 125\n**Monster Mission:** No\n**Repeatable:** No\n**Can Be Shrouded?:** No\n**Quest Type:** Achievement\n**Group Size:** Solo\n\nThis achievement is gained upon defeating the following rare monsters in Veksar.\na bloodgill soothsayer\na bloodgill warlord\na decaying slavemaster\na Kylong crusader\na Kylong lich\na plagued slave\na rotting shopkeeper\na sad slave\nan Iksar behemoth\nan Iksar highborn\nan undead chef\nan undead thief\nan undying blacksmith\nBrother Eruk\nChampion Kamak\nFeral Lord Gulok\nHierophant Ginai\nHierophant Vradik\nLord Sasil\nLuminary Salox\nremains of Sythrax\nTrooper Muruk\nWarlock Dirloz\nWarlock Gurag\nAdd the following points to the ZONE_1.txt file:\nP -608.9220, 307.3690, -30.2780,  240, 240, 240,  2,  Underwater_tunnel\nAdd the following points to the ZONE_2.txt file:\nP 254.6700, 98.6200, -5.1300,      240, 0, 0,  2,  Garudon\nP 122.9700, 372.6100, -27.8700,    240, 0, 0,  2,  a_bloodgill_soothsayer\nP -271.2310, 364.5790, -13.9990,   240, 0, 0,  2,  a_bloodgill_soothsayer\nP 157.2860, 392.3260, -30.2250,    240, 0, 0,  2,  a_bloodgill_warlord\nP -70.1500, 361.1000, -27.1900,    240, 0, 0,  2,  a_bloodgill_warlord\nP 219.4739, -343.3400, -25.9980,   240, 0, 0,  2,  Brother_Eruk\nP -476.3880, 497.8420, 34.0010,    240, 0, 0,  2,  Champion_Karmak\nP 480.9870, -171.5110, -22.1670,   240, 0, 0,  2,  a_decaying_slavemaster\nP -595.8030, 171.0980, -36.4040,   240, 0, 0,  2,  Feral_Lord_Gulok\nP -271.8298, 136.5892, -16.9980,   240, 0, 0,  2,  Hierophant_Ginai\nP -244.7221, -245.0266, -27.9980,  240, 0, 0,  2,  Heirophant_Vradik\nP 7.8647, 96.1081, -29.9980,       240, 0, 0,  2,  an_iksar_behemoth\nP 228.2500, 400.2500, 37.1300,     240, 0, 0,  2,  an_iksar_highborn\nP 524.1600, 275.8800, -26.8700,    240, 0, 0,  2,  a_Kylong_crusader\nP 308.1520, 393.7110, 22.0010,     240, 0, 0,  2,  remains_of_Sythrax\nP 58.1431, 243.0997, -29.9980,     240, 0, 0,  2,  a_rotting_shopkeeper\nP 196.9561, 116.1135, -1.9980,     240, 0, 0,  2,  a_Kylong_lich\nP 147.4484, 187.6156, 78.0020,     240, 0, 0,  2,  a_Kylong_lich\nP -619.9810, 513.9370, -11.9990,   240, 0, 0,  2,  Lord_Sasil\nP -160.6987, -278.8077, -27.9980,  240, 0, 0,  2,  Luminary_Salox\nP 492.5300, -730.7200, -44.8700,   240, 0, 0,  2,  a_plagued_slave\nP 570.4700, -199.4800, 45.1300,    240, 0, 0,  2,  a_sad_slave\nP 199.5810, -262.9950, 42.0010,    240, 0, 0,  2,  Trooper_Muruk\nP 507.7540, 41.7100, 8.0010,       240, 0, 0,  2,  an_undead_chef\nP 775.5900, -415.0600, -44.8700,   240, 0, 0,  2,  an_undead_thief\nP 166.9543, 242.9133, 8.0020,      240, 0, 0,  2,  an_undying_blacksmith\nP -617.3860, -291.9170, -27.9990,  240, 0, 0,  2,  Worlock_Dirloz\nP -94.6077, -343.5147, -21.9980,   240, 0, 0,  2,  Warlock_Gurag\nP 385.1500, -346.4850, -29.9990,   240, 0, 0,  2,  Wanderer\nP 83.0022, 199.8408, -15.9852,     240, 0, 0,  2,  Spirit_of_Garudon\nP -498.8154, 452.5395, 21.0020,    240, 0, 0,  2,  Explore_Gamus\nAdd the following points to the ZONE_3.txt file:\nP 0.0000, 0.0000, 0.0000,         127, 64, 0,  2,  0\nP -1000.0000, -775.0000, 0.0000,  127, 64, 0,  2,  1000\nP -500.0000, -775.0000, 0.0000,   127, 64, 0,  2,  500\nP 0.0000, -775.0000, 0.0000,      127, 64, 0,  2,  0\nP 500.0000, -775.0000, 0.0000,    127, 64, 0,  2,  -500\nP 1000.0000, -775.0000, 0.0000,   127, 64, 0,  2,  -1000\nP -1203.0000, -510.0000, 0.0000,  127, 64, 0,  2,  500\nP -1203.0000, 0.0000, 0.0000,     127, 64, 0,  2,  0\nP -1203.0000, 490.0000, 0.0000,   127, 64, 0,  2,  -500\nP 0.0000, 690.0000, 0.0000,       127, 64, 0,  2,  File_Set_=_veksar.txtSubmitted by: GidonoRewards:\n[",
    },
    {
      id = "8626",
      title = "Hunter of Dragon Necropolis",
      exp = "02",
      exp_name = "The Scars of Velious",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "Achievement",
      repeatable = false,
      group_size = "Solo",
      npc = "A blood",
      loc = nil,
      triggers = {
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "**Level:** 1\n**Maximum Level:** 125\n**Monster Mission:** No\n**Repeatable:** No\n**Can Be Shrouded?:** No\n**Quest Type:** Achievement\n**Group Size:** Solo\n\nThis achievement is gained upon defeating the following rare monsters in Dragon Necropolis:\na bloodthirsty carrion bat\na Chetari Darkling\na Chetari Warlord\na crazed Chelaki\na deadly phase spider\nDominator Yisaki\na fierce entropy serpent\na great green slime\na masterful dragon construct\nPierre\nQueen Raltaas\nSlani Veekilaleeki\nVaniki\na venemous phase spider\nAdd the following points to the necroplis_3.txt file:\nP -2034.0000, 44.0000, 0.0000,        255, 255, 0,  2,  Western_Wastes\nP 2711.2241, 92.0882, 20.1308,        255, 255, 0,  3,  Breeding_Grounds\nP 119.2189, -1586.0951, 151.4663,     0, 0, 240,  3,  Jaled_Dar`s_Shade\nP 1279.1725, -1239.9709, 0.0020,      0, 0, 240,  1,  dragon_rib_bone\nP 1320.6208, -624.7770, 0.0020,       0, 0, 240,  1,  dragon_rib_bone\nP 642.7018, -911.5883, 0.0020,        0, 0, 240,  1,  dragon_rib_bone\nP 1279.0300, -1259.7520, 1.3383,      127, 0, 0,  1,  dragon_bones_trap\nP 1962.8400, -216.9066, -258.0326,    127, 0, 0,  1,  dragon_bones_trap\nP 2587.7939, -462.5546, 0.0020,       127, 0, 0,  1,  dragon_bones_trap\nP 1327.5531, -624.9977, 0.0020,       127, 0, 0,  1,  dragon_bones_trap\nP 571.8000, -1176.2128, 0.0020,       127, 0, 0,  1,  dragon_bones_trap\nP 27.1319, -1202.4465, 15.7342,       127, 0, 0,  1,  beetle_trap\nP 1200.3715, -222.9442, -191.4170,    127, 0, 0,  1,  beetle_trap\nP -574.2734, -1292.4731, -158.3688,   127, 0, 0,  1,  Trap\nP 2199.1755, -417.1460, -258.3396,    127, 0, 0,  1,  Trap\nP 2180.7156, -587.7269, -258.3240,    127, 0, 0,  1,  Trap\nP -1018.4462, -1374.7087, -116.0866,  127, 0, 0,  1,  Trap\nP 1880.9664, 162.7519, -258.3655,     127, 0, 0,  1,  Trap\nP -110.1196, -1287.1443, -158.3895,   127, 0, 0,  1,  Trap\nP -154.4299, -658.3262, -189.7740,    127, 0, 0,  1,  Trap\nP 1379.5605, -461.4072, -258.2241,    127, 0, 0,  1,  Trap\nP 1826.9150, -260.8068, -258.3118,    127, 0, 0,  1,  Trap\nP -346.7809, -441.6519, -163.2926,    127, 0, 0,  1,  Trap\nP -449.5071, -1142.4292, -159.7702,   127, 0, 0,  1,  Trap\nP -584.3288, -1408.1190, -157.4865,   127, 0, 0,  1,  Trap\nP -685.8602, -1115.5723, -30.4944,    127, 0, 0,  1,  Trap\nP -153.0588, -815.7319, -187.5192,    127, 0, 0,  1,  Trap\nP -770.1721, -1502.5646, -158.3589,   127, 0, 0,  1,  Trap\nP -668.4446, -1473.4756, -158.1949,   127, 0, 0,  1,  Trap\nAdd the following points to the necroplis_2.txt file:\nP 241.1740, 260.6033, -249.6975,    240, 0, 0,  3,  Zlandicar\nP 1768.3746, -138.8298, -255.5770,  240, 0, 0,  3,  a_bloodthirsty_carrion_bat\nP 2842.8262, -75.0936, 11.5596,     240, 0, 0,  3,  a_Chetari_Darkling\nP 2270.6824, -40.5889, -248.3625,   240, 0, 0,  3,  a_Chetari_Warlord\nP 505.1873, -349.4221, -258.2934,   240, 0, 0,  3,  a_crazed_Chelaki\nP -636.7504, -623.4626, 6.5553,     240, 0, 0,  3,  a_deadly_phase_spider\nP 370.6239, -253.4469, -218.3297,   240, 0, 0,  3,  Dominator_Yisaki\nP 404.1476, -1419.1931, -287.2270,  240, 0, 0,  3,  a_fierce_entropy_serpent\nP 183.7256, -1446.5004, -158.3934,  240, 0, 0,  3,  a_great_green_slime\nP 2009.0000, -970.0000, 0.0000,     240, 0, 0,  3,  a_masterful_dragon_construct\nP -578.2232, -347.4140, -163.4055,  240, 0, 0,  3,  Pierre\nP 1687.0000, -847.0000, 0.0000,     240, 0, 0,  3,  Queen_Raitaas\nP -736.9619, -507.6707, -163.4069,  240, 0, 0,  3,  Slani_Veekilaleeki\nP 560.0000, -497.0000, 0.0000,      240, 0, 0,  3,  Vaniki\nP 909.1083, -1544.5874, 1.5372,     240, 0, 0,  3,  a_venomous_phase_spider\nP -973.3225, -487.3356, 1.5679,     240, 0, 0,  3,  Excavator_Quellin\nP 537.4877, -1331.1465, 7.3866,     240, 0, 0,  3,  Tarn_Macklin\nP 583.0985, -387.5437, -258.2588,   240, 0, 0,  3,  Chetari_Courier_(roamer)\nP -756.7524, -473.4888, -163.3982,  240, 0, 0,  3,  Neb\nP -747.9862, -473.5895, -163.3943,  240, 0, 0,  3,  Dralliw`tar\nP 706.7919, -587.4830, -197.7350,   240, 0, 0,  3,  Warmaster_Utvara\nP 193.2833, -965.6218, -258.3822,   240, 0, 0,  3,  Whelp_Kidnapper\nP 2577.9209, 214.0488, 11.5378,     240, 0, 0,  3,  Whelp_Kidnapper\nP 2412.3813, 19.4547, 11.5375,      240, 0, 0,  3,  Whelp_Kidnapper\nAdd the following points to the necroplis.txt file:\nP 0.0000, 0.0000, 0.0000,          127, 64, 0,  2,  0\nP -2500.0000, -2075.0000, 0.0000,  127, 64, 0,  2,  2500\nP -2000.0000, -2075.0000, 0.0000,  127, 64, 0,  2,  2000\nP -1500.0000, -2075.0000, 0.0000,  127, 64, 0,  2,  1500\nP -1000.0000, -2075.0000, 0.0000,  127, 64, 0,  2,  1000\nP -500.0000, -2075.0000, 0.0000,   127, 64, 0,  2,  500\nP 0.0000, -2075.0000, 0.0000,      127, 64, 0,  2,  0\nP 500.0000, -2075.0000, 0.0000,    127, 64, 0,  2,  -500\nP 1000.0000, -2075.0000, 0.0000,   127, 64, 0,  2,  -1000\nP 1500.0000, -2075.0000, 0.0000,   127, 64, 0,  2,  -1500\nP 2000.0000, -2075.0000, 0.0000,   127, 64, 0,  2,  -2000\nP 2500.0000, -2075.0000, 0.0000,   127, 64, 0,  2,  -2500\nP 3000.0000, -2075.0000, 0.0000,   127, 64, 0,  2,  -3000\nP -2773.0000, -2010.0000, 0.0000,  127, 64, 0,  2,  2000\nP -2773.0000, -1510.0000, 0.0000,  127, 64, 0,  2,  1500\nP -2773.0000, -1010.0000, 0.0000,  127, 64, 0,  2,  1000\nP -2773.0000, -510.0000, 0.0000,   127, 64, 0,  2,  500\nP -2773.0000, 0.0000, 0.0000,      127, 64, 0,  2,  0\nP -2773.0000, 490.0000, 0.0000,    127, 64, 0,  2,  -500\nP -2773.0000, 990.0000, 0.0000,    127, 64, 0,  2,  -1000\nP 0.0000, 1003.0000, 0.0000,       127, 64, 0,  2,  File_Set_=_necroplis.txtSubmitted by: GidonoRewards:\n[",
    },
    {
      id = "8649",
      title = "Hunter of Accursed Temple of Cazic-Thule (Luclin)",
      exp = "05",
      exp_name = "The Legacy of Ykesha",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "Achievement",
      repeatable = false,
      group_size = "Solo",
      npc = "A blood",
      loc = nil,
      triggers = {
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "**Level:** 1\n**Maximum Level:** 125\n**Monster Mission:** No\n**Repeatable:** No\n**Can Be Shrouded?:** No\n**Quest Type:** Achievement\n**Group Size:** Solo\n\nThis achievement is gained upon defeating the following rare monsters in Accursed Temple of Cazic-Thule:\na barbed scale piranha\na blood claw raptor\na blood fin piranha\na crystaline mass\na diamond scale piranha\na disciple of Thule\na diseased mosquito\na frenzied shiverback\na gelatinous mass\na graystriped mosquito\na gyrating mass\na noxious jungle spider\na poisonstrand hunter\na quivering mass\na razor fin piranha\na razor tooth piranha\na rotting horror\na rotting shiverback\na silverflank shiverback\na swirling black mass\na swirling green mass\na swirling red mass\na Tae Ew aggressor\na Tae Ew bloodfiend\na Tae Ew convert\na Tae Ew hunter\na Tae Ew prophet\na Tae Ew spear fisher\na Tae Ew trapper\na Tae Ew warlord\na Tae Ew warmaster\na Thul Tae Ew adept\na Thul Tae Ew crusader\na Thul Tae Ew despoiler\na Thul Tae Ew ritualist\na Thul Tae Ew spirtcaller\na Thul Tae Ew torturer\na toxic jungle hunter\na virulent mosquito\nan enraged Amygdalan\nan enraged disciple\nan enraged jungle raptor\nan enraged tiger raptor\nan envenomed hunter\nan ooze covered ritualist\nDismay\nDreadfang\nFrightchaser\nSilverfang\nSoul Siphon\nTerrorclaw\nToxiferiousSubmitted by: GidonoRewards:\n[",
    },
    {
      id = "8666",
      title = "Hunter of Shadeweaver's Thicket",
      exp = "03",
      exp_name = "The Shadows of Luclin",
      min_lvl = 1,
      max_lvl = 125,
      quest_type = "Achievement",
      repeatable = false,
      group_size = "Solo",
      npc = "A blood",
      loc = nil,
      triggers = {
      },
      items_required = {
      },
      rewards = {
      },
      factions = {
      },
      walkthrough = "**Level:** 1\n**Maximum Level:** 125\n**Monster Mission:** No\n**Repeatable:** No\n**Can Be Shrouded?:** No\n**Quest Type:** Achievement\n**Group Size:** Solo\n\nThis achievement is gained upon defeating the following rare monster in Shadeweaver's Thicket:\na blood drenched hopling\nSeethekerSubmitted by: GidonoRewards:\n[",
    },
  },
}
