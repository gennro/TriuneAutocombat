| Ninjadvloot.inc v6.1 11/12/2019 Redguides.com
| Author A_Druid_00 12/19/2005
| Based on original looting code of toomanynames
| The following updates were all individually posted and consolidated by Maskoi into the current version.
| Updated: Moeymoejoe added strip out comma in item names when accessing ini file 08/02/2006
| Updated: mystikule added sell option to ini file 01/07/2008
| Updated: drkrain for House of Thule 10/23/2010
| Updated: Maskoi with Sell Routines 11/27/2010
| Updated: Maskoi with /item keep/sell/destroy ini commands 07/21/2011
| Updated: Maskoi with Foraged item handling 08/31/2011
| Updated: Maskoi with Buying item handling 07/31/2012
| Updated: Maskoi with Assign different ini file for item handling 01/01/2013
| Updated: Crystane with Looting while on mount (no overshooting on corpserun), added some conditional checks to skip unecessary delay I found. Announcement routine reworked. 05/13/2014
| Updated: TreeHuginDruid hard coded 1 second delay between loot and corpse item retrieval to resolve loot latency issue.
| Updated: Maskoi added suppot for Advanced Looting system  05/18/2015
| Updated: Hoosierbilly/Incognito reworked Advloot system adding several new features. July 2016
|		1. User selectable to auto assign group master looter and switch master looter when bags are full
|		2. Quest looting: loot any item marked =Quest|xx until everyone in group has xx number then leave on corpse
|		3. Auto distribute LORE items to everyone in group
|		4. User selectable to distribute nodrop items to everyone in the group, similar to quest looting
|		5. User selectable minimum plat value to mark items =Keep in the loot.ini file
|		6. User selectable limits on number of foraged items to keep using =quest|xx setting
| Updated: hoosierbilly added fishing item handling 5/7/17
|
| Updated 01 Sep 2017 by Eqmule fixed a /next i that was in the wrong place.
| Updated 23 Sep 2017 by Maskoi/Eqmule fixed #warning errors
| Updated 31 Dec 2017 by ChatWithThisName fixed multiple /next in /for statements in various locations.
| Updated 31 Jan 2019 by Eqmule Added code to respect the users advloot settings.
| Updated 11/12/2019 by Maskoi - renamed a zdist variable to avoid conflicts with Kiss.

| Selling Contributions by
|   drkrain - TLInv item check
|   dewey2461 - Add sold items to ini file Event
|
| Requirements: MQ2Moveutils
|
| Usage: add the following to your macro for looting
|   #include Ninjadvloot.inc
|   /call SetupAdvLootVars
|   /call LootMobs or /call UseAdvLoot
|
| Assign differnent ini files. Default is Loot.ini
|   /call SetupAdvLootVars "MyToonLoot.ini"
|   /call SetupAdvLootVars "LootMesa.ini"
|
| Commands
| Usage. Grab the item and put it on your cursor then use one of the following commands
|     /lootdestroy - Mark item on cursor to Destroy in Loot.ini file
|     /lootignore - Mark item on cursor to Ignore in Loot.ini file
|     /lootkeep - Mark item on cursor to Keep in Loot.ini file
|     /lootsell - Mark item on cursor to Sell in Loot.ini file
|     /lootquest - Mark item on cursor to Quest|default in Loot.ini file
|     /sellstuff - Target a vendor and this command will sell any item in your inventory marked sell.
|     /depositstuff - Target your guildbanker and this command will deposit any item in your inventory marked keep into the guild bank.

#Event CantLoot         "#*#may not loot this corpse#*#"
#Event Sell             "#*#You receive#*# for the #1#(s)#*#"
#Event EditIniItem      "[MQ2] LootIniItem #1# #2#"
#Event SellStuff        "[MQ2] NinjadvLoot selling items to vendor"
#Event Broke            "#*#you cannot afford#*#"
#Event Broke            "#*#you can't afford#*#"
#Event Forage           "Your forage mastery has enabled you to find something else!"
#Event Forage           "You have scrounged up #*#"
#Event Forage			"You caught #*#"
#Event InventoryFull    "#*#Your inventory appears full!#*#"
#Event Novalue          "#*#give you absolutely nothing for the #1#.#*#"
#Event NullSlot         "#*#Invalid item slot 'null#*#"
#Event Lore             "#*#You cannot loot this Lore Item.#*#"
#Event UnwantedLoot		"#*#No one was interested in the#*#item(s): #1#. These items#*#"
#Event LockedLoot		"#*#These item(s) are locked#*#"

Sub SetupAdvLootVars(string ChangeIniFile)

    /declare CantLootID							int                 outer
    /declare NinjadVersion                      string              outer   6.09
    /declare InventoryFull                      int                 outer   0
    /declare NinjaIniFile                       string              outer   Loot.ini
    /declare MasterCorpseList                   string              outer
    /declare Debugloot                          int                 outer   0
    /declare GlobalCount                        int                 outer   5
    /declare GlobalList[${GlobalCount}]         string              outer
    /varset GlobalList[1]                       string              outer  empty
    /declare AutoHater                          int                 outer
	/declare LootTimer							timer				outer
	/declare GMLCounter							int					outer	${Group.Members}
	/declare FreeBagSpace						int					outer	0
	/declare LootCountTrack						int					outer	0
	/declare SCountTrack						int					outer	0
	/declare MLSwitchTimer						timer				outer	0

   /if (${ChangeIniFile.Length} && ${ChangeIniFile.NotEqual[null]}) {
		/varset NinjaIniFile ${ChangeIniFile}
	}
	/echo SetupAdvLootVars: Reading from ${NinjaIniFile}
    /declare NALVersion                           string             outer   ${Ini[${NinjaIniFile},Settings,Version]}
    /if (!${Ini[${NinjaIniFile},Settings,Version].Length}) {
        /call CreateIni
        /ini "${NinjaIniFile}" "Settings" "Version" "0.0"
    }
    /if (${NALVersion.NotEqual[${NinjadVersion}]}) {
        /echo NINJADVLOOT: Version mismatch detected. Writing aliases.
        /noparse /squelch /alias /lootignore    /echo LootIniItem Ignore ${Cursor.Name}
        /noparse /squelch /alias /lootsell      /echo LootIniItem Sell ${Cursor.Name}
        /noparse /squelch /alias /lootkeep      /echo LootIniItem Keep ${Cursor.Name}
        /noparse /squelch /alias /lootdestroy   /echo LootIniItem Destroy ${Cursor.Name}
		/noparse /squelch /alias /lootquest		/echo LootIniItem Quest|${QuestKeep} ${Cursor.Name}
        /squelch /alias /sellstuff              /echo NinjadvLoot selling items to vendor
        /squelch /alias /depositstuff           /echo NinjadvLoot depositing items to guildbank
        /ini "${NinjaIniFile}" "Settings" "Version" "${NinjadVersion}"
    }

    | Loot ini settings
    /call NALLoadVar Settings AddNewSales        1                   int
    /call NALLoadVar Settings LootForage         1                   int
    /call NALLoadVar Settings LootMobs           TRUE                bool
    /call NALLoadVar Settings CorpseRadius       100                 int
    /call NALLoadVar Settings MobsTooClose       40                  int
    /call NALLoadVar Settings ReportLoot         FALSE               bool
    /call NALLoadVar Settings LootChannel        g                   string
	/call NALLoadVar Settings SpamLootInfo		 1					 int
    /call NALLoadVar Settings LootForageSpam     1                   int
    /call NALLoadVar Settings GlobalLootOn       1                   int
    /call NALLoadVar Settings CombatLooting      1                   int
	/call NALLoadVar Settings GMLSelect			 1					 int
	/call NALLoadVar Settings ExcludeBag1		 "Extraplanar Trade Satchel" string
	/call NALLoadVar Settings ExcludeBag2		 NULL				 string
	/call NALLoadVar Settings QuestKeep			 10					 int
	/call NALLoadVar Settings StackPlatValue	 0					 int
	/call NALLoadVar Settings NoDropDefault		 Quest|Keep|Ignore	 string
	/call NALLoadVar Settings LootLagDelay		 0					 int
	/call NALLoadVar Settings SaveBagSlots		 3					 int
    /call FindAutoHate
    /echo NINJADVLOOT: Variables are set. Using ${NinjaIniFile} file.

/return

Sub NALLoadVar(IniSection,IniVar,IniValue,VarType)
    /if (!${Defined[${IniVar}]} && ${Defined[VarType]}) /declare ${IniVar} ${VarType} outer
    /declare IniString string local ${Ini[${NinjaIniFile},${IniSection},${IniVar},NOTFOUND]}
    /varset ${IniVar} ${IniString}
    /if (${IniString.Equal["NOTFOUND"]}) {
        /if (${IniString.Equal["NOTFOUND"]}) /varset ${IniVar} ${IniValue}
        /ini "${NinjaIniFile}" "${IniSection}" "${IniVar}" "${${IniVar}}"
    }
/return

Sub FindAutoHate
    /declare i int local
    /for i 1 to 10
        /if (${Me.XTarget[${i}].TargetType.Equal[Auto Hater]}) {
            /varset AutoHater ${i}
            /echo NINJADVLOOT: AutoHater set to Xtarget${i}
            /return
        }
    /next i
/return

| ****************  Loot Mobs Section ******************** |

Sub LootMobs
    /declare DeadCount int local ${SpawnCount[corpse radius ${CorpseRadius} zradius 50]}
    /if (${Debugloot}) /echo DEBUGLOOT There are ${DeadCount} corpses in range.
    /if (${Debugloot}) /echo DEBUGLOOT !${LootMobs} || ${SpawnCount[npc radius ${MobsTooClose} zradius 50]} || !${DeadCount} || ${Me.Combat} || !${Me.FreeInventory} || ${Me.XTarget[${AutoHater}].ID} && !${CombatLooting})
    /if (!${LootMobs} || ${SpawnCount[npc radius ${MobsTooClose} zradius 50]} || !${DeadCount} || ${Me.Combat} || !${Me.FreeInventory} || ${Me.XTarget[${AutoHater}].ID} && !${CombatLooting}) /return
    /declare i int local
    /declare CorpseList string local
    /declare CorpseToLoot int local
    /declare NALZDist float local ${Math.Distance[${Target.Z}:${Me.Z}]}
    /declare ClosestCorpse int local
    /declare CorpseCount int local 0
    /for i 1 to ${DeadCount}
        /varset ClosestCorpse ${NearestSpawn[${i},corpse radius ${CorpseRadius} zradius 50].ID}
        /if (!${Spawn[${ClosestCorpse}].Deity.ID}) {
            /varset CorpseList ${CorpseList}${ClosestCorpse}|
            /if (!${MasterCorpseList.Find[${ClosestCorpse}]}) /varset MasterCorpseList ${MasterCorpseList}${ClosestCorpse}|
            /varcalc CorpseCount ${CorpseCount}+1
        }
    /next i
    /if (${Debugloot}) /echo DEBUGLOOT Trying to loot ${CorpseCount} corpses. ID's ${CorpseList}
    /for i 1 to ${CorpseCount}
    /varset CorpseToLoot ${CorpseList.Arg[${i},|]}
    /if (!${Defined[CorpseLocked${CorpseToLoot}]}) /declare CorpseLocked${CorpseToLoot} timer outer 0
        /if (${Spawn[${CorpseToLoot}].Deity.ID} || !${Spawn[${CorpseToLoot}].ID} || !${Spawn[${CorpseToLoot}].LineOfSight} || ${CorpseLocked${CorpseToLoot}} || ${Me.XTarget[${AutoHater}].ID} && !${CombatLooting}) /goto :SkipCorpse
            /if (${Target.ID}!=${CorpseToLoot}) /target id ${CorpseToLoot}
            /if (!${Me.Standing}) /stand
            /delay 3s ${Target.ID}==${CorpseToLoot} && ${Me.Standing}
            /if (${Target.Distance}>5) {
                /if (${Debugloot}) /echo DEBUGLOOT move to corpse
                /moveto mdist 10
                /moveto loc ${Target.Y} ${Target.X} ${Target.Z}
        /if (${Me.Mount.ID}) {
            /delay 3s ${Math.Distance[${Target.Y},${Target.X}]}<25
            /keypress back
        }
                /delay 3s ${MoveTo.Stopped} && !${Me.Moving}
                /call ZCheck ${NALZDist} 8
                /if (${Target.ID}) /face fast
            }
            /if (${Target.Distance}<12) {
                /if (${Debugloot}) /echo DEBUGLOOT /Call LootCorpse
                /call LootCorpse ${Target.ID}
                /call RemoveCorpseID ${CorpseToLoot}
            }
        :SkipCorpse
    /next i
    /if (${Debugloot}) /echo DEBUGLOOT Leave Sub LootMobs
/return

Sub LootCorpse(CorpseID)
    /if (${Debugloot}) /echo DEBUGLOOT Enter Sub LootCorpse
    /declare i              int    local
    /declare j              int    local
    /declare LootList       string local
    /declare FirstLetter    string local
    /declare GCheck            string local
    /call CheckCursor
    /varset CantLootID 0
    /if (${Debugloot}) /echo DEBUGLOOT /loot
    | Open Loot window
    /loot
    /if (${Debugloot}) /echo DEBUGLOOT /doevents CantLoot
    /delay 3s ${Window[LootWnd]}
    /delay 1s
    /doevents CantLoot
    /delay 3s ${CantLootID} || ${Window[LootWnd]}
    /if (${Target.ID}==${CantLootID} && !${Window[LootWnd]}) {
        /echo NINJADVLOOT: I can't loot ${Target.CleanName} ID:${CorpseID} right now.
        /if (${Defined[CorpseLocked${CorpseID}]}) /varset CorpseLocked${CorpseID} 150s
        /return
    }
    /if (${Debugloot}) /echo DEBUGLOOT Loot Window Open:${Window[LootWnd]} - # Loot Items:${Corpse.Items}
    /if (${Window[LootWnd].Open} && ${Corpse.Items}) {
        /declare loottotal int  local
        :LootLag
        /varset loottotal ${Corpse.Items}
        /if (${Debugloot}) {
		/echo DEBUGLOOT :LootLag ${loottotal}!=${Corpse.Items}
        }
	/delay 1s ${loottotal}!=${Corpse.Items}
        /if (${loottotal}!=${Corpse.Items}) /goto :LootLag
        /echo NINJADVLOOT: Looting ${Target.CleanName} ID:${CorpseID}.
        /for i 1 to ${loottotal}
            /if (${Corpse.Item[${i}].Lore} && ${FindItem[=${Corpse.Item[${i}]}].ID}) {
                /varset LootList ${LootList}${Corpse.Item[${i}]},
                /goto :LootedInGlobal
            }
            /if (${Debugloot}) /echo DEBUGLOOT Looting ${Corpse.Item[${i}].Name} ${i} of ${loottotal}
            | Global loot section
            /if (${GlobalLootOn}) {
                /for j 1 to ${GlobalCount}
                    /varset GCheck ${Ini[${NinjaIniFile},"Global","Global${j}"]}
                    | /echo ${GCheck.Arg[1,|]} ${GCheck.Arg[2,|]}
                    /if (${Corpse.Item[${i}].Name.Find[${GCheck.Arg[1,|]}]}) {
                        /if (${Select[${GCheck.Arg[2,|]},sell,keep]} && (!${Corpse.Item[${i}].Lore} || !${FindItem[=${Corpse.Item[${i}]}].ID}) && (${Me.FreeInventory} || (${FindItemCount[=${Corpse.Item[${i}].Name}]} && ${Corpse.Item[${i}].Stackable} && ${Corpse.Item[${i}].FreeStack}))) /call LootItem ${i} Keep Right
                        /if (${GCheck.Arg[2,|].Equal[Ignore]}) /varset LootList ${LootList}${Corpse.Item[${i}]},
                        /if (${GCheck.Arg[2,|].Equal[Destroy]}) /call LootItem ${i} Destroy left
                        /goto :LootedInGlobal
                    }
                /next j
            }
            /varset FirstLetter ${Corpse.Item[${i}].Name.Left[1]}
            /if (${Corpse.Item[${i}].ID} && !${Select[${Ini[${NinjaIniFile},"${FirstLetter}","${Corpse.Item[${i}]}"]},Ignore,Keep,Destroy,Sell,Quest]}) {
                /if (${Corpse.Item[${i}].NoDrop})  /ini "${NinjaIniFile}" "${FirstLetter}" "${Corpse.Item[${i}]}" Ignore
                /if (!${Corpse.Item[${i}].NoDrop}) /ini "${NinjaIniFile}" "${FirstLetter}" "${Corpse.Item[${i}]}" Keep
            }
            /if (${Ini[${NinjaIniFile},"${FirstLetter}","${Corpse.Item[${i}]}"].NotEqual[Destroy]} && !${Me.FreeInventory} && (!${FindItemCount[=${Corpse.Item[${i}].Name}]} || (${FindItemCount[=${Corpse.Item[${i}].Name}]} && ${Corpse.Item[${i}].Stackable} && !${Corpse.Item[${i}].FreeStack})) || (${Corpse.Item[${i}].Lore} && ${FindItem[=${Corpse.Item[${i}]}].ID}) || ${Ini[${NinjaIniFile},"${FirstLetter}","${Corpse.Item[${i}]}"].Equal[Ignore]}) /varset LootList ${LootList}${Corpse.Item[${i}]},
            /if ((${Ini[${NinjaIniFile},"${FirstLetter}","${Corpse.Item[${i}]}"].Equal[Keep]} || ${Ini[${NinjaIniFile},"${FirstLetter}","${Corpse.Item[${i}]}"].Equal[Sell]}) && (!${Corpse.Item[${i}].Lore} || !${FindItem[=${Corpse.Item[${i}]}].ID}) && (${Me.FreeInventory} || (${FindItemCount[=${Corpse.Item[${i}].Name}]} && ${Corpse.Item[${i}].Stackable} && ${Corpse.Item[${i}].FreeStack}))) /call LootItem ${i} Keep Right
            /if (${Ini[${NinjaIniFile},"${FirstLetter}","${Corpse.Item[${i}]}"].Equal[Destroy]}) /call LootItem ${i} Destroy left
            :LootedInGlobal
        /next i
        /if (${Corpse.Items}) {
            /if (${ReportLoot} && ${LootList.Length}) {
                /keypress /
                /delay 3
                /call Type "${LootChannel}"
                /keypress Space chat
                /notify LootWND LW_BroadcastButton leftmouseup
                /delay 3
                /call Type " ,left on corpse."
                /keypress Enter chat
                /if (${Defined[CorpseLocked${CorpseID}]}) /varset CorpseLocked${CorpseID} 440s
            }
        }
    }
    :clickdoneffs
        /nomodkey /notify LootWnd LW_DoneButton leftmouseup
        /if (${Debugloot}) /echo DEBUGLOOT :clickdoneffs
        /delay 5s !${Window[LootWnd].Open}
        /if (${Debugloot}) /echo DEBUGLOOT :clickdoneffs LootWin Open:${Window[LootWnd]}
    /if (${Window[LootWnd].Open}) /goto :clickdoneffs
    /call RemoveCorpseID ${CorpseID}
    /if (${Debugloot}) /echo DEBUGLOOT Leave Sub LootCorpse
/return

Sub Event_CantLoot
   /if (${Debugloot}) /echo DEBUGLOOT Enter Sub Event_CantLoot
   /varset CantLootID ${Target.ID}
   /if (${Debugloot}) /echo DEBUGLOOT  Event_CantLoot Can't loot ${Target.CleanName} ${Target.ID}
   /if (${Debugloot}) /echo DEBUGLOOT Leave Sub Event_CantLoot
/return

Sub RemoveCorpseID(CListID)
    /if (${Defined[CorpseLocked${CListID}]}) {
        /if (!${CorpseLocked${CListID}} && ${MasterCorpseList.Find[${CListID}]}) {
            /deletevar CorpseLocked${CListID}
            /varset MasterCorpseList ${MasterCorpseList.Replace[${CListID}|,]}
        }
    }
/return

Sub LootItem(int i,DoWhat,WhichButton)
    /if (${Debugloot}) /echo DEBUGLOOT Enter Sub LootItem ${i} ${DoWhat} ${WhichButton}
    /declare CorpseItemID int local ${Corpse.Item[${i}].ID}
    /nomodkey /shift /itemnotify loot${i} ${WhichButton}mouseup
    /delay 5s ${Window[ConfirmationDialogBox].Open} || !${Corpse.Item[${i}].NoDrop}
    /if (${Window[ConfirmationDialogBox].Open}) /nomodkey /notify ConfirmationDialogBox Yes_Button leftmouseup
    /delay 5s ${Cursor.ID} || ${WhichButton.NotEqual[left]}
    /if (${DoWhat.Equal[Destroy]} && ${Cursor.ID}==${CorpseItemID}) /destroy
    /delay 5s !${Corpse.Item[${i}].ID}
    /if (${Cursor.ID}) /call CheckCursor
    /if (${Debugloot}) /echo DEBUGLOOT Leave Sub LootItem
/return

Sub CheckCursor
    /if (${Debugloot}) /echo DEBUGLOOT Enter Sub CheckCursor
    :ALauto_inv
    /if (${Cursor.ID}) {
        /if (${Cursor.NoDrop} && !${Me.FreeInventory}) /return
        /timed 5 /autoinventory
        /delay 2s !${Cursor.ID}
        /goto :ALauto_inv
    }
    /if (${Debugloot}) /echo DEBUGLOOT Leave Sub CheckCursor
/return

| **************** Foraged Items Section ******************** |
Sub Event_Forage(S0)
    /if (!${LootForage}) /return
	/if (${Debugloot}) /echo DEBUGLOOT Enter Sub Forage items
    /declare ForagedItem string local
	/declare ForagedIniEntry string local
	/declare ForagedMaxKeep int local
/echo event trigger ${S0}
	/delay ${Math.Calc[${LootLagDelay}+10]} ${Cursor.ID}
    :MoreToAutoInventory
        /if (${Cursor.ID}) {
            /varset ForagedItem ${Cursor.Name}
			/varset ForagedIniEntry ${Ini[${NinjaIniFile},"${ForagedItem.Left[1]}","${ForagedItem}"].Arg[1,|]}
			/varset ForagedMaxKeep ${Ini[${NinjaIniFile},"${ForagedItem.Left[1]}","${ForagedItem}"].Arg[2,|]}
			/if (${ForagedMaxKeep}==NULL) /varset ForagedMaxKeep 1
 			/if (!${Select[${ForagedIniEntry},Ignore,Keep,Destroy,Sell,Quest]}) {
			/if (${Cursor.ID}) /ini "${NinjaIniFile}" "${Cursor.Name.Left[1]}" "${Cursor.Name}" Keep
                /if (${S0.Find[caught]}) {
					/echo Ninjadvloot: New fishing item >> ${Cursor.Name}=Keep << added to ${NinjaIniFile} file.
				} else /echo Ninjadvloot: New foraging item >> ${Cursor.Name}=Keep << added to ${NinjaIniFile} file.
            }
			/delay ${Math.Calc[${LootLagDelay}+5]}
            /if (${ForagedIniEntry.Equal[Destroy]} || ${ForagedIniEntry.Equal[Ignore]} || (${ForagedIniEntry.Equal[Quest]} && ${FindItemCount[=${Cursor.Name}]}>=${ForagedMaxKeep})) {
				/if (${LootForageSpam} && ${ForagedIniEntry.Equal[Quest]}) {
					/if (${S0.Find[caught]}) {
						/echo Ninjadvloot: I already caught ${FindItemCount[=${Cursor.Name}]} of ${ForagedMaxKeep} destroying ${Cursor.Name}
					} else /echo Ninjadvloot: I already foraged ${FindItemCount[=${Cursor.Name}]} of ${ForagedMaxKeep} destroying ${Cursor.Name}
                }
				/if (${LootForageSpam} && ${ForagedIniEntry.NotEqual[Quest]}) {
					/if (${S0.Find[caught]}) {
						/echo Ninjadvloot: Destroyed fishing item ${ForagedItem}.
					} else /echo Ninjadvloot: Destroyed forage item ${ForagedItem}.
				}
				/delay 5
				/if (${Cursor.Name.Equal[${ForagedItem}]}) /destroy
                /delay ${Math.Calc[${LootLagDelay}+10]} !${Cursor.ID}
			} else /if ((${ForagedIniEntry.Equal[Keep]} || ${ForagedIniEntry.Equal[Sell]} || ${FindItemCount[=${Cursor.Name}]}<${ForagedMaxKeep}) && (!${Cursor.Lore} || !${FindItem[=${Cursor.Name}].ID}) && (${Me.FreeInventory} || (${FindItemCount[=${Cursor.Name}]} && ${Cursor.Stackable} && ${Cursor.FreeStack}))) {
                /if (${LootForageSpam} && ${S0.Find[caught]}) {
					/echo Ninjadvloot: Keeping fishing item ${ForagedItem}.
				} else /echo Ninjadvloot: Keeping forage item ${ForagedItem}.
				}
				/autoinventory
                /delay ${Math.Calc[${LootLagDelay}+10]} !${Cursor.ID}
		}
		/delay 5
		/if (${Cursor.ID}) /goto :MoreToAutoInventory
	/if (${Debugloot}) /echo DEBUGLOOT Leaving Sub Forage items
/return

| **************** Search Loot Section ******************** |
Sub DoLootStuff(LootAction)
    /declare i int local
    /declare j int local
    /declare k int local
    /declare LootItem string
   /call NPC "${Target.CleanName}"
   | Top level inv has its own loop since ${FindItem[=${ItemToSell}].InvSlot} looks at top lev inv slots first in Sub SellToVendor for the item to sell.
   | Loop through top level inventory slots for sellable items
   /for k 1 to 10
        | Check if top level inv slot is not a container/bag
        /if (${InvSlot[pack${k}].Item.Container}==0) {
            | If top level inv slot is empty check for an item marked sell
            /if (${InvSlot[pack${k}].Item.ID}) {
                /varset LootItem ${InvSlot[pack${k}].Item}
                /if (${LootAction.Equal[sell]})  {
                /if (${Ini[${NinjaIniFile},"${LootItem.Left[1]}","${LootItem}"].Equal[Sell]}) /call SellToVendor "${LootItem}"
                }
                /if (${LootAction.Equal[deposit]})  {
                    /if (${Ini[${NinjaIniFile},"${LootItem.Left[1]}","${LootItem}"].Equal[Keep]}) /call DepositToGuildBank "${LootItem}"
                }
            }
        }
    /next k
    | Loop through top level inventory slots for containers
    /for i 1 to 10
        | Check if top level inv slot has a bag
        /if (${InvSlot[pack${i}].Item.Container}==0) /continue
        | Set j 1 to number of bag slots and loop through slots looking for items marked sell
        /for j 1 to ${InvSlot[pack${i}].Item.Container}
            /if (${InvSlot[pack${i}].Item.Item[${j}].ID}) {
            /varset LootItem ${InvSlot[pack${i}].Item.Item[${j}].Name}
            /if (${LootAction.Equal[sell]})  {
                /if (${Ini[${NinjaIniFile},"${LootItem.Left[1]}","${LootItem}"].Equal[Sell]}) /call SellToVendor "${LootItem}"
                }
                /if (${LootAction.Equal[deposit]})  {
                    /if (${Ini[${NinjaIniFile},"${LootItem.Left[1]}","${LootItem}"].Equal[Keep]}) /call DepositToGuildBank "${LootItem}"
                }
            }
        /next j
    /next i
    | Prevent spam from Sell event after selling items in Sub SellStuff
    /doevents flush Sell
    /if (${Window[MerchantWnd].Open}) {
        /echo Closing merchant window
        /nomodkey /notify MerchantWnd MW_Done_Button LeftMouseUp
    }
    /if (${Window[GuildBankWnd].Open}) {
        /echo Closing guildbank window
        /keypress esc
    }
/return

Sub NPC(string NPCName)
    /if (${NPCName.Equal[null]} && ${Target.Type.Equal[npc]}) /varset NPCName ${Target.CleanName}
    /target npc ${NPCName}
    /delay 10
        /if (!${Select[${Target.Type},npc,pet]} || !${Target.ID} || ${Target.Type.Equal[pet]} && !${Target.CleanName.Find[familiar]}) {
        /echo Please target a vendor or guildbanker
        /return
    }
    /delay 1s
    /echo Doing business with ${NPCName}
    /target id ${Spawn[${NPCName}].ID}
    /delay 3s ${Target.ID}==${Spawn[${NPCName}].ID}
    /if (${Target.Distance}>15) {
        /moveto id  ${Spawn[${NPCName}].ID}
        /delay 250 ${MoveTo.Stopped}
    }
    /face nolook
    /delay 1s
    /echo Opening merchant/guildbank window
    /nomodkey /click right target
    /echo Waiting 5s for merchant/guildbank window to populate
    /delay 5s
/return

| **************** Sell Loot Section ******************** |
Sub Event_Sell(string soldstr, string ItemName)
    /if (${Ini[${NinjaIniFile},"${ItemName.Left[1]}","${ItemName}"].Equal[Sell]}) /return
    /if ( ${AddNewSales} ) {
        /echo Setting ${ItemName} to sell
        /ini "${NinjaIniFile}" "${ItemName.Left[1]}" "${ItemName}" Sell
    }
/return

Sub SellToVendor(ItemToSell)
    /if (${Window[MerchantWnd].Open}) {
    :sell
        /echo Selling ${ItemToSell}
        /if (${InvSlot[pack${Select[${FindItem[=${ItemToSell}].ItemSlot},23,24,25,26,27,28,29,30,31,32]}].Item.Container}) {
            /nomodkey /itemnotify in Pack${Math.Calc[${FindItem[=${ItemToSell}].ItemSlot}-22]} ${Math.Calc[${FindItem[=${ItemToSell}].ItemSlot2}+1]} leftmouseup
        } else {
            /nomodkey /itemnotify ${FindItem[=${ItemToSell}].InvSlot} leftmouseup
        }
        /delay 5
        /nomodkey /shiftkey /notify merchantwnd MW_Sell_Button leftmouseup
        /doevents
        /if (${Macro.Return.Equal[TRUE]}) /return
        /delay 2s
    /if (${FindItemCount[=${ItemToSell}]}) /goto :sell
    }
/return

| **************** Deposit Loot Section ********************
Sub DepositToGuildBank(ItemToDeposit)
    /if (${Window[GuildBankWnd].Open}) {
        :deposit
            /if (${Window[GuildBankWnd].Child[GBANK_DepositCountLabel].Text.Arg[2,:]}==0) {
                /echo Guildbank Deposited Items is full.
                /return
            }
            /if (${FindItem[=${ItemToDeposit}].InvSlot}<=22) /return
            /echo Depositing ${ItemToDeposit}
            /if (!${InvSlot[pack${Float[${Math.Calc[${Select[${FindItem[=${ItemToDeposit}].ItemSlot},22,23,24,25,26,27,28,29,30,31,32]}-1]}].Int}].Item.Container}) {
                /nomodkey /shift /itemnotify ${FindItem[=${ItemToDeposit}].InvSlot} leftmouseup
            } else {
                /nomodkey /shift /itemnotify in Pack${Math.Calc[${FindItem[=${ItemToDeposit}].ItemSlot}-22]} ${Math.Calc[${FindItem[=${ItemToDeposit}].ItemSlot2}+1]} leftmouseup
            }
            /delay 5
            /nomodkey /notify GuildBankWnd GBANK_DepositButton leftmouseup
            /delay 2s
        /if (${FindItem[=${ItemToDeposit}].InvSlot}) /goto :deposit
    }
/return

| **************** Item set ini file event ********************
    Sub Event_EditIniItem(ItemString,ItemAction,ItemName)
        /if (${Cursor.ID}) {
            /echo -- Setting ${ItemName} to ${ItemAction}
            /ini "${NinjaIniFile}" ${ItemName.Left[1]} "${ItemName}" ${ItemAction}
        } else {
            /echo No item on cursor.
        }
    /return

| **************** Sell Stuff Event ********************
    Sub Event_SellStuff
        /call DoLootStuff sell
    /return

| **************** Deposit Stuff Event *******************
    Sub Event_DepositStuff
        /call DoLootStuff deposit
    /return

| **************** Broke Event ********************
Sub Event_Broke
    /if (!${Window[MerchantWnd].Open}) /return
    /echo You are out of money!
    /endmacro
/return

| **************** Type Stuff  ********************
| Lifted from commonsubs.inc by Armysoldier
Sub Type(InStr)
    /declare char string local
    /declare loopctr int local
    /for loopctr 1 to ${InStr.Length}
        /varset char ${InStr.Mid[${loopctr},1]}
        /if (!${char.Length}) {
            /nomodkey /keypress space chat
        } else {
            /nomodkey /keypress ${char} chat
        }
    /next loopctr
/return

| **************** Buy Stuff ********************
Sub Buy(string ItemToBuy, int amount)
    /if (!${Select[${Target.Type},npc,pet]} || !${Target.ID} || ${Target.Type.Equal[pet]} && !${Target.CleanName.Find[familiar]}) /return
    /declare i int local
    | /echo Buying ${ItemToBuy}!
    /declare QTY int local
    /declare ListItem int local
    /varcalc QTY ${amount}-${FindItemCount[${ItemToBuy}]}
    /delay 3
    /if (${FindItemCount[${ItemToBuy}]}>=${amount}) {
        /echo I already have ${FindItemCount[${ItemToBuy}]} ${ItemToBuy}.
        /return
    }
    /varset ListItem ${Window[MerchantWnd].Child[ItemList].List[=${ItemToBuy},2]}
    /if (!${ListItem}) {
        /echo couldn't find ${ItemToBuy}
        /return
    } else {
        /notify MerchantWnd ItemList listselect ${ListItem}
        /delay 5
    }
    /echo Buying ${ItemToBuy} Till I get ${amount}
    :Loop
    /doevents
    /if (${InventoryFull}) /return
    /if (${QTY}>0) {
        /if (${QTY}>19) {
            /Shiftkey /notify merchantwnd MW_Buy_Button leftmouseup
            /delay 5 ${FindItemCount[B${ItemToBuy}]}>=${QTY}
            /echo ${FindItemCount[${ItemToBuy}]}/${amount} ${ItemToBuy} in inventory
            /varcalc QTY ${amount}-${FindItemCount[${ItemToBuy}]}
            /if (${QTY}<=0) {
                /if (${Window[MerchantWnd].Open}) {
                    /echo Closing merchant window
                    /nomodkey /notify MerchantWnd MW_Done_Button LeftMouseUp
                }
                /return
            }
            /delay 5
            /if (${QTY}>19) /goto :Loop
        }
        /if (${QTY}>0 && ${QTY}<20) {
            /for i 1 to ${QTY}
                /Ctrlkey /notify merchantwnd MW_Buy_Button leftmouseup
                /delay 1s ${FindItemCount[${ItemToBuy}]}>=${Math.Calc[${FindItemCount[${ItemToBuy}]}+${i}]}
                /echo Buying ${ItemToBuy} ${i} of ${QTY}
                /if (${i}>=${QTY}) {
                    /echo ${FindItemCount[${ItemToBuy}]} ${ItemToBuy} in inventory
                    /if (${Window[MerchantWnd].Open}) {
                        /echo Closing merchant window
                        /nomodkey /notify MerchantWnd MW_Done_Button LeftMouseUp
                    }
                    /return
                }
            /next i
            /varcalc QTY ${amount}-${FindItemCount[${ItemToBuy}]}

        }
    }
/return

Sub ZCheck(float Zcur, float Zdiff)
    | Move down if Z distance more than Zcheck due to levitation
    /if (${Zcur}>=${Zdiff}) {
        /keypress end hold
        /delay 10
        /keypress end
    }
/return

Sub Event_InventoryFull
    /echo Your Inventory is full. Turning off looting functions.
    /varset LootMobs FALSE
    /varset InventoryFull 1
/return

Sub CreateIni
    /if (${Ini[${NinjaIniFile}].Length}) /return
    /declare a local Settings|Global|A|B|C|D|E|F|G|H|I|J|K|L|M|N|O|P|Q|R|S|T|U|V|W|X|Y|Z
    /echo Creating ini file ${NinjaIniFile}
    /declare i int local
    /declare j int local
    /for i 1 to 28
        /ini ${NinjaIniFile} "${a.Arg[${i},|]}" "|===================================" "==================================|"
        /if (${i}==2) {
            /for j 1 to ${GlobalCount}
                /ini ${NinjaIniFile} "Global" "Global${j}" "Item Name|Ignore/Destroy/Keep/Sell"
            /next j
        }
    /next i
/return

Sub Event_Novalue(string nvmstring, string nvItem)
        /declare NVSection ${nvItem.Left[1]}
        /declare NVTemp string local ${Ini[${NinjaIniFile},${NVSection},${nvItem}]}
        /if (${NVTemp.Equal[Sell]}) {
            /ini "${NinjaIniFile}" "${NVSection}" "${nvItem}" KEEP
            /delay 5
            /echo NINJADVLOOT: ${nvItem} is marked SELL but has no value. marking KEEP
        }
/return TRUE

Sub Event_NullSlot
        /echo NINJADVLOOT: Opening all bags to correct null slot
        /keypress OPEN_INV_BAGS
    /timed 30 /keypress CLOSE_INV_BAGS
/return

| **************** AdvLoot Stuff ********************

Sub Event_UnwantedLoot(S0,S1)
	/if (${Group.MasterLooter.ID}==${Me.ID}) {
		/if (${Debugloot}) /echo DEBUGLOOT Entering Sub UnwantedLoot, line# ${Macro.CurLine}
		/if (${SpamLootInfo}) /echo NINJADVLOOT: no one wants >${S1}< leaving ${AdvLoot.SList[1].Name} on corpse
		/delay 3s !${AdvLoot.LootInProgress}
		/advloot shared 1 leave
		/delay 3s !${AdvLoot.LootInProgress}
		/if (${LootLagDelay}) /delay ${LootLagDelay}
	}
/return

Sub Event_LockedLoot
	/if (${Debugloot}) /echo DEBUGLOOT Entering Sub LockedLoot, line# ${Macro.CurLine}
	/if (${SpamLootInfo}) /echo NINJADVLOOT: Loot item is locked, leaving item on corpse
		/doevents flush LockedLoot
		/delay 3s !${AdvLoot.LootInProgress}
		/advloot personal 1 leave
		/delay 3s !${AdvLoot.LootInProgress}
		/if (${LootLagDelay}) /delay ${LootLagDelay}
/return

Sub UseAdvLoot
    /if (!${Me.FreeInventory} || ${LootTimer} || (!${AdvLoot.SCount} && !${AdvLoot.PCount})) {
		/varset LootTimer ${Math.Calc[${Math.Rand[5]}+8]}s
		/return
	}
    /if (${Debugloot}) /echo DEBUGLOOT Entering Sub UseAdvLoot, line# ${Macro.CurLine}
    /if (${Me.UseAdvancedLooting}) {
        /delay 30 ${Window[AdvancedLootWnd].Open}
		/declare g int local
        /declare i int local
        /declare j int local
        /declare k int local
        /declare ItemsToProcess string local
        /declare ITSCount int local 0
        /declare ITPCount int local 0
		/declare ITStackSize int local 1
        /declare ITPName string local
        /declare ITPList string local
        /declare IniEntry string local
		/declare KeepAmount int local 0
		/declare ITStack int local 0
		/declare ICanLoot int local 1
		/declare ITLootCount int local ${AdvLoot.SCount}
		/declare SubStart int local ${Macro.RunTime}
		/declare SubEnd int local 0

		| Assign group a master looter, if one is not already
		/if (${AdvLoot.SList[1].ID} && !${Group.MasterLooter.ID} && ${Group.Leader.ID}==${Me.ID}) {
			/if (${GMLSelect}) {
				/if (${Debugloot}) /echo DEBUGLOOT Selecting a Group.MasterLooter, line# ${Macro.CurLine}
				/varset GMLCounter ${Group.Members}
				/for i ${Group.Members} downto 0
					/if (${Ini[KissAssist_${Group.Member[${i}].Name}.ini,General,LootOn].Length}) {
						/varset ICanLoot ${Ini[KissAssist_${Group.Member[${i}].Name}.ini,General,LootOn]}
					} else /if (${Ini[KissAssist_${EverQuest.Server}_${Group.Member[${i}].Name}.ini,General,LootOn].Length}) {
						/varset ICanLoot ${Ini[KissAssist_${EverQuest.Server}_${Group.Member[${i}].Name}.ini,General,LootOn]}
					} else /if (${Ini[${IniFileName}.ini,General,LootOn].Length}) {
						/varset ICanLoot ${Ini[${IniFileName}.ini,General,LootOn]}
					} else {
						/varset ICanLoot 1
					}
					/if (${Group.Member[${GMLCounter}].Type.Equal[mercenary]} || ${ICanLoot}==0) {
						/varcalc GMLCounter ${GMLCounter}-1
						/continue
					}
					/if (${GMLCounter}>=0) {
						/echo NINJADVLOOT: ${Group.Member[${GMLCounter}].Name} has been assigned the Master Looter Role
						/grouproles set ${Group.Member[${GMLCounter}].Name} 5
						/delay 2s ${Group.MasterLooter.ID}
					} else {
						/echo NINJADVLOOT: GMLSelect was unable to select a valid MasterLooter
						/echo NINJADVLOOT: Please assign one or more group members >> LootOn=1 << in kissassist_CharacterName.ini file
					}
				/next i
			} else {
				/if (!${GMLSelect}) /echo NINJADVLOOT: Please assign a group member the Master Looter Role in the group window
			}
		}
		| Change Master Looter if shared list count increases more than 5x without a decrease AND the shared list count is >8
		/if (${AdvLoot.SList[1].ID} && ${GMLSelect} && ${Group.Leader.ID}==${Me.ID} && ${AdvLoot.SCount}>8) {
			/if (${Debugloot}) /echo DEBUGLOOT: Start replace MasterLooter check, line# ${Macro.CurLine}
			/if (${ITLootCount} > ${SCountTrack}) {
				/varset SCountTrack ${ITLootCount}
				/varcalc LootCountTrack ${LootCountTrack}+1
				/if (${SpamLootInfo}) /echo NINJADVLOOT: ${Math.Calc[6-${LootCountTrack}]} shared list increases until new Master Looter is choosen
			}
			/if (${ITLootCount} < ${SCountTrack}) {
				/varset SCountTrack ${ITLootCount}
				/varcalc LootCountTrack ${LootCountTrack}-1
				/if (${LootCountTrack}<0) /varset LootCountTrack 0
				/if (${SpamLootInfo}) /echo NINJADVLOOT: ${Math.Calc[6-${LootCountTrack}]} shared list increases until new Master Looter is choosen
			}
			/if (${Debugloot}) /echo DEBUGLOOT: replace MasterLooter check: ITLootCount=${ITLootCount}, SCountTrack=${SCountTrack}, LootCountTrack=${LootCountTrack} assign a new looter if over 5, line# ${Macro.CurLine}
			/if (${LootCountTrack}>5 && !${MLSwitchTimer}) {
				/varcalc GMLCounter ${Group.MasterLooter.Index}-1
				/for i ${Group.Members} downto 0
				/if (${Ini[KissAssist_${Group.Member[${i}].Name}.ini,General,LootOn].Length}) {
					/varset ICanLoot ${Ini[KissAssist_${Group.Member[${i}].Name}.ini,General,LootOn]}
				} else /if (${Ini[KissAssist_${EverQuest.Server}_${Group.Member[${i}].Name}.ini,General,LootOn].Length}) {
					/varset ICanLoot ${Ini[KissAssist_${EverQuest.Server}_${Group.Member[${i}].Name}.ini,General,LootOn]}
				} else /if (${Ini[${IniFileName}.ini,General,LootOn].Length}) {
					/varset ICanLoot ${Ini[${IniFileName}.ini,General,LootOn]}
				} else {
					/varset ICanLoot 1
				}
				/if (${Group.Member[${GMLCounter}].Type.Equal[mercenary]} || ${ICanLoot}==0) {
					/if (${Debugloot}) /echo DEBUGLOOT: ${Group.Member[${GMLCounter}].Name} is a mercenary or flagged LootOn=0, try the next group member, line# ${Macro.CurLine}
					/varcalc GMLCounter ${GMLCounter}-1
					/continue
				}
				/if (${GMLCounter}>=0) {
					/echo NINJADVLOOT: ${Group.Member[${GMLCounter}].Name} has been assigned the Master Looter Role
					/grouproles set ${Group.Member[${GMLCounter}].Name} 5
					/delay 2s ${Group.MasterLooter.ID}
					/varset LootCountTrack 0
				} else {
					/varset GMLCounter ${Group.Members}
					/continue
				}
				/next i
				/if (${LootCountTrack}) /echo NINJADVLOOT: Unable to find a valid looter, Time to go sell or assign more group members LootOn=1.
				/varset MLSwitchTimer 35s
			}
		}
		| Check Bag Space
		/if (${Debugloot}) /echo DEBUGLOOT: Bag space check, line# ${Macro.CurLine}
		/varset FreeBagSpace 0
		/for k 1 to 10
		/if (${InvSlot[Pack${k}].Item.Container} && ${InvSlot[Pack${k}].Item.Name.NotEqual[${ExcludeBag1}]} && ${InvSlot[Pack${k}].Item.Name.NotEqual[${ExcludeBag2}]}) {
			/varcal FreeBagSpace ${FreeBagSpace}+(${InvSlot[Pack${k}].Item.Container}-${InvSlot[Pack${k}].Item.Items})
		}
		/next k

		| Everyone select need/no for quest items in shared loot
		/if (${AdvLoot.SCount} && ${FreeBagSpace} > 0) {
			/if (${Debugloot}) /echo DEBUGLOOT: Everyone check SharedList for =Quest|xx items, line# ${Macro.CurLine}
			/varset i 1
			:NextQItem
			/if (!${Me.FreeInventory}) /return
			/varset ITSCount ${AdvLoot.SCount}
			/varset ITPName ${AdvLoot.SList[${i}].Name}
			/varset IniEntry ${Ini[${NinjaIniFile},"${ITPName.Left[1]}","${ITPName}"].Arg[1,|]}
			/if (${AdvLoot.SList[${i}].ID} && ${Select[${IniEntry},Quest]}) {
				/varset KeepAmount ${Ini[${NinjaIniFile},"${ITPName.Left[1]}","${ITPName}"].Arg[2,|]}
				/if (${KeepAmount}==0) /varset KeepAmount ${QuestKeep}
				/if (${Debugloot}) /echo DEBUGLOOT: Sharedlist# ${ITSCount}, ItemName=${ITPName}, ToonItemCount=${FindItemCount[=${ITPName}]}, KeepAmount=${KeepAmount}, line# ${Macro.CurLine}
				/if (${FindItemCount[=${ITPName}]} < ${KeepAmount} && ${AdvLoot.SList[${i}].Need}==false && ${AdvLoot.SList[${i}].No}==false) {
					/if (${SpamLootInfo} && ${AdvLoot.SList[${i}].Need}==false) /echo NINJADVLOOT: SharedList: Quest check - I need ${Math.Calc[${KeepAmount}-${FindItemCount[=${ITPName}]}]} more ${ITPName}(s) selecting Need
					/delay 3s !${AdvLoot.LootInProgress}
					/if (${AdvLoot.SList[${i}].Greed}==false && ${AdvLoot.SList[${i}].Need}==false && ${AdvLoot.SList[${i}].No}==false) /advloot shared ${i} nd
					/if (${LootLagDelay}) /delay ${LootLagDelay}
				}
				/if (${FindItemCount[=${ITPName}]} >= ${KeepAmount} && ${AdvLoot.SList[${i}].No}==false) {
					/if (${SpamLootInfo} && ${AdvLoot.SList[${i}].No}==false) /echo NINJADVLOOT: SharedList: Quest check - I already have ${FindItemCount[=${ITPName}]} of ${KeepAmount} ${ITPName}(s) selecting No
					/delay 3s !${AdvLoot.LootInProgress}
					/if (${AdvLoot.SList[${i}].Greed}==false && ${AdvLoot.SList[${i}].Need}==false && ${AdvLoot.SList[${i}].No}==false) /advloot shared ${i} no
					/if (${LootLagDelay}) /delay ${LootLagDelay}
				}
				/varcalc i ${i}+1
				/if (${i}<=${ITSCount}) /goto :NextQItem
			}
		}
		| Select greed/no for items in shared loot list if not Master Looter
		/if (${Group.MasterLooter.ID}!=${Me.ID} && ${AdvLoot.SCount}) {
			/if (${Debugloot}) /echo DEBUGLOOT: check SharedList and select greed/no if NOT MasterLooter, line# ${Macro.CurLine}
			/if (${AdvLoot.SList[${i}].ID} && ${Select[${IniEntry},Keep,Sell,NULL]}  && !${FindItem[=${AdvLoot.SList[${i}].Name}].Lore} && !${FindItemBank[=${AdvLoot.SList[${i}].Name}].Lore} && ${AdvLoot.SList[${i}].No}==false) {
				/if (${SpamLootInfo} && ${AdvLoot.SList[${i}].Greed}==false && ${AdvLoot.SList[${i}].Need}==false && ${AdvLoot.SList[${i}].No}==false) /echo NINJADVLOOT: SharedList: item#${i} - I must have a ${ITPName} selecting Greed
				/delay 3s !${AdvLoot.LootInProgress}
				/if (${AdvLoot.SList[${i}].Greed}==false && ${AdvLoot.SList[${i}].Need}==false && ${AdvLoot.SList[${i}].No}==false) /advloot shared ${i} gd
				/delay 3s !${AdvLoot.LootInProgress}
				/varcalc i ${i}+1
				/if (${i}<=${ITSCount}) /goto :NextQItem
			}
			/if (${AdvLoot.SList[${i}].ID} && ${Select[${IniEntry},Ignore,Destroy]} || (${FindItem[=${AdvLoot.SList[${i}].Name}].Lore}||${FindItemBank[=${AdvLoot.SList[${i}].Name}].Lore})) {
				/if (${SpamLootInfo} && ${AdvLoot.SList[${i}].Greed}==false && ${AdvLoot.SList[${i}].Need}==false && ${AdvLoot.SList[${i}].No}==false) /echo NINJADVLOOT: SharedList: item#${i} - I don't want a ${ITPName} selecting No
				/delay 3s !${AdvLoot.LootInProgress}
				/if (${AdvLoot.SList[${i}].Greed}==false && ${AdvLoot.SList[${i}].Need}==false && ${AdvLoot.SList[${i}].No}==false) /advloot shared ${i} no
				/delay 3s !${AdvLoot.LootInProgress}
				/varcalc i ${i}+1
				/if (${i}<=${ITSCount}) /goto :NextQItem
			}
		}

		| End looting if bag space <= SaveBagSlots
		/if (${FreeBagSpace}<=${SaveBagSlots}) {
			/if (!${LootTimer}) {
				/echo NINJADVLOOT: Your bags are almost full, looting aborted until you go sell
				/varset LootTimer ${Math.Calc[${Math.Rand[5]}+23]}s
			}
			/return
		}
		| Master Looter process the Shared loot list
		/if (${Group.MasterLooter.ID}==${Me.ID} && ${AdvLoot.SCount}) {
			/if (${Debugloot}) /echo DEBUGLOOT: MasterLooter process SharedList, line# ${Macro.CurLine}
			/varset i 1
			:NextSItem
			/if (!${Me.FreeInventory}) /return
			/varset ITSCount ${AdvLoot.SCount}
			/varset ITPName ${AdvLoot.SList[${i}].Name}

			|Respect the users advloot settings ALWAYS
			/if (${AdvLoot.SList[${i}].Need} == TRUE || ${AdvLoot.SList[${i}].Greed} == TRUE) {
				|/echo NINJADVLOOT: Adding item ${ITPName}=Keep to ${NinjaIniFile} file.
				/ini "${NinjaIniFile}" "${ITPName.Left[1]}" "${ITPName}" Keep
			} else /if (${AdvLoot.SList[${i}].No} == TRUE || ${AdvLoot.SList[${i}].Never} == TRUE) {
				/echo NINJADVLOOT: Adding item ${ITPName}=Ignore to ${NinjaIniFile} file.
				/ini "${NinjaIniFile}" "${ITPName.Left[1]}" "${ITPName}" Ignore
			}

			/varset IniEntry ${Ini[${NinjaIniFile},"${ITPName.Left[1]}","${ITPName}"].Arg[1,|]}
			/if (${Debugloot}) /echo DEBUGLOOT: SharedList: item# ${i}, ItemName=${ITPName}, IniFile=${NinjaIniFile}, IniEntry=${IniEntry}, line# ${Macro.CurLine}


			| add nodrop items to ini file
			/if (${AdvLoot.SList[${i}].NoDrop} && !${Select[${IniEntry},Ignore,Keep,Destroy,Sell,Quest]}) {
				/if (${NoDropDefault.Arg[1,|].Equal[Quest]}) {
					/ini "${NinjaIniFile}" "${ITPName.Left[1]}" "${ITPName}" Quest|1
					/varset IniEntry Quest
					/echo NINJADVLOOT: Adding NoDrop item ${ITPName}=Quest|1 to ${NinjaIniFile} file.
				} else /if (${NoDropDefault.Arg[1,|].Equal[Keep]}) {
					/ini "${NinjaIniFile}" "${ITPName.Left[1]}" "${ITPName}" Keep
					/varset IniEntry Keep
					/echo NINJADVLOOT: Adding NoDrop item ${ITPName}=Keep to ${NinjaIniFile} file.
				} else {
					/ini "${NinjaIniFile}" "${ITPName.Left[1]}" "${ITPName}" Ignore
					/varset IniEntry Ignore
					/echo NINJADVLOOT: Adding NoDrop item ${ITPName}=Ignore to ${NinjaIniFile} file.
				}
				/delay ${Math.Calc[${LootLagDelay}+10]}
			}
			| Leave items marked ignore on corpse
			/if (${AdvLoot.SList[${i}].ID} && ${Select[${IniEntry},Ignore]}) {
				/if (${Debugloot}||${SpamLootInfo}) /echo NINJADVLOOT: SharedList: ${ITPName} is set to ${IniEntry}. Leaving item.
				/delay 3s !${AdvLoot.LootInProgress}
				/advloot shared ${i} leave
				/delay 3s !${AdvLoot.LootInProgress}
				/if (${LootLagDelay}) /delay ${LootLagDelay}
				/if (${i}<=${ITSCount}) /goto :NextSItem
			}
			| skip item if its lore and everyone in group has one
			/if (${AdvLoot.SList[${i}].ID} && !${AdvLoot.SList[${i}].NoDrop} && (${FindItem[=${AdvLoot.SList[${i}].Name}].Lore}||${FindItemBank[=${AdvLoot.SList[${i}].Name}].Lore}||(${FindItemCount[=${AdvLoot.SList[${i}].Name}]} && !${FindItem[=${AdvLoot.SList[${i}].Name}].ID}))) {
				/for g 0 to ${Group.Members}
				/if (${Debugloot}||${SpamLootInfo}) /echo NINJADVLOOT: SharedList: ${AdvLoot.SList[${i}].Name} is Lore and I have one. Giving to ${Group.Member[${g}].Name}
				/delay 3s !${AdvLoot.LootInProgress}
				/if (${AdvLoot.SList[${i}].ID} && ${AdvLoot.SList[${i}].Name.Equal[${ITPName}]}) /advloot shared ${i} giveto ${Group.Member[${g}].Name}
				/delay 3s !${AdvLoot.LootInProgress}
				/delay 5
				/if (${AdvLoot.SList[${i}].ID} && ${AdvLoot.SList[${i}].Name.Equal[${ITPName}]}) {
					/continue
				}
				/next g
				/if (${Debugloot}||${SpamLootInfo}) /echo NINJADVLOOT: SharedList: ${AdvLoot.SList[${i}].Name} is Lore and all group members have one. Skipping item.
				/delay 3s !${AdvLoot.LootInProgress}
				/if (${AdvLoot.SList[${i}].ID} && ${AdvLoot.SList[${i}].Name.Equal[${ITPName}]}) /advloot shared ${i} leave
				/if (${LootLagDelay}) /delay ${LootLagDelay}
				/if (${i}<=${ITSCount}) /goto :NextSItem
			}
			|Set nodrop lore items to autoroll if master looter already has one
			/if (${AdvLoot.SList[${i}].ID} && ${Select[${IniEntry},Keep,Sell,Destroy,Null]} && ${AdvLoot.SList[${i}].NoDrop} && (${FindItem[${AdvLoot.SList[${i}].Name}].Lore}||${FindItemBank[=${AdvLoot.SList[${i}].Name}].Lore}||(${FindItemCount[=${AdvLoot.SList[${i}].Name}]} && !${FindItem[=${AdvLoot.SList[${i}].Name}].ID}))) {
				/if ((${Debugloot}||${SpamLootInfo}) && ${AdvLoot.SList[${i}].AutoRoll}==False) /echo NINJADVLOOT: SharedList: NoDrop Lore ${ITPName} is marked ${IniEntry}. Setting to autoroll.
				/delay 3s !${AdvLoot.LootInProgress}
				/if (${AdvLoot.SList[${i}].AutoRoll}==False) /advloot shared ${i} autoroll
				/delay 3s !${AdvLoot.LootInProgress}
				/if (${LootLagDelay}) /delay ${LootLagDelay}
				/varcalc i ${i}+1
				/if (${i}<=${ITSCount}) /goto :NextSItem
			}
			| Set items marked quest to autoroll
			/if (${AdvLoot.SList[${i}].ID} && ${Select[${IniEntry},Quest]}) {
				/if ((${Debugloot}||${SpamLootInfo}) && ${AdvLoot.SList[${i}].AutoRoll}==False) /echo NINJADVLOOT: SharedList: ${ITPName} is marked ${IniEntry}. Setting item to AutoRoll.
				/delay 3s !${AdvLoot.LootInProgress}
				/if (${AdvLoot.SList[${i}].AutoRoll}==False) /advloot shared ${i} autoroll
				/if (${LootLagDelay}) /delay ${LootLagDelay}
				/varcalc i ${i}+1
				/if (${i}<=${ITSCount}) /goto :NextSItem
			}
			| Set items Master Looter has filtered never or no to autoroll
			/if (${AdvLoot.SList[${i}].ID} && (${AdvLoot.SList[${i}].Never}==true || ${AdvLoot.SList[${i}].No}==true)) {
				/if (${Debugloot}||${SpamLootInfo}) /echo NINJADVLOOT: SharedList: Master Looter has advloot filter set to Never or No. Set item ${ITPName} to AutoRoll.
				/delay 3s !${AdvLoot.LootInProgress}
				/if (${AdvLoot.SList[${i}].AutoRoll}==False) /advloot shared ${i} autoroll
				/delay 3s !${AdvLoot.LootInProgress}
				/if (${LootLagDelay}) /delay ${LootLagDelay}
				/varcalc i ${i}+1
				/if (${i}<=${ITSCount}) /goto :NextSItem
			}
			| Que items to my personal list
			/if (${AdvLoot.SList[${i}].ID} && ${Select[${IniEntry},Keep,Sell,Destroy,Null]} && ${AdvLoot.SList[${i}].No}==false && !${FindItem[=${AdvLoot.SList[${i}].Name}].Lore} && !${FindItemBank[=${AdvLoot.SList[${i}].Name}].Lore}) {
				/if (${Debugloot}||${SpamLootInfo}) /echo NINJADVLOOT: SharedList: ${ITPName} is marked ${IniEntry}. Que item to personal list.
				/delay 3s !${AdvLoot.LootInProgress}
				/advloot shared ${i} giveto ${Me.Name}
				/delay 3s !${AdvLoot.LootInProgress}
				/if (${LootLagDelay}) /delay ${LootLagDelay}
				/if (${i}<=${ITSCount}) /goto :NextSItem
			}
		}

| Loot/destroy anything in personal list
		/if (${AdvLoot.PCount}) {
			/if (${Debugloot}) /echo DEBUGLOOT: Everyone process PList, line# ${Macro.CurLine}
			/varset ITSCount ${AdvLoot.PCount}
			/if (${ITLootCount}==0) /varset ITLootCount ${AdvLoot.PCount}
			/for k ${ITSCount} downto 1
			/if (!${Me.FreeInventory}) /return
			/varset ITPName ${AdvLoot.PList[${k}].Name}
			/varset IniEntry ${Ini[${NinjaIniFile},"${ITPName.Left[1]}","${ITPName}"].Arg[1,|]}
			/varset ITStackSize ${AdvLoot.PList[${k}].StackSize}
			/if (${Debugloot}) /echo DEBUGLOOT: PList: item# ${k}, Name=${ITPName}, IniFile=${NinjaIniFile}, IniEntry=${IniEntry}, StackSize=${ITStackSize}, line# ${Macro.CurLine}

			| skip item if its lore and i have one
			/if (${FindItem[=${AdvLoot.PList[${k}].Name}].Lore}||${FindItemBank[=${AdvLoot.PList[${k}].Name}].Lore}||(${FindItemCount[=${AdvLoot.PList[${k}].Name}]} && !${FindItem[=${AdvLoot.PList[${k}].Name}].ID})) {
				/if (${Debugloot}||${SpamLootInfo}) /echo NINJADVLOOT: PList: ${ITPName} is Lore and I have one. Leaving item.
				/delay 3s !${AdvLoot.LootInProgress}
				/advloot personal ${k} leave
				/delay 3s !${AdvLoot.LootInProgress}
				/if (${LootLagDelay}) /delay ${LootLagDelay}
				/continue
			}
			| Add item to ini if it not in there
			/if (${AdvLoot.PList[${k}].NoDrop} && !${Select[${IniEntry},Ignore,Keep,Destroy,Sell,Quest]}) {
				/if (${NoDropDefault.Arg[1,|].Equal[Quest]}) {
					/ini "${NinjaIniFile}" "${ITPName.Left[1]}" "${ITPName}" Quest|1
					/varset IniEntry Quest
					/echo NINJADVLOOT: Adding NoDrop item ${ITPName}=Quest|1 to ${NinjaIniFile} file.
				} else /if (${NoDropDefault.Arg[1,|].Equal[Keep]}) {
					/ini "${NinjaIniFile}" "${ITPName.Left[1]}" "${ITPName}" Keep
					/varset IniEntry Keep
					/echo NINJADVLOOT: Adding NoDrop item ${ITPName}=Keep to ${NinjaIniFile} file.
				} else {
					/ini "${NinjaIniFile}" "${ITPName.Left[1]}" "${ITPName}" Ignore
					/varset IniEntry Ignore
					/echo NINJADVLOOT: Adding NoDrop item ${ITPName}=Ignore to ${NinjaIniFile} file.
				}
				/delay ${Math.Calc[${LootLagDelay}+5]}
			}
			/if (${AdvLoot.PList[${k}].ID} && !${Select[${IniEntry},Ignore,Keep,Destroy,Sell,Quest]}) {
				| Loot item, check its value and add to ini file.
				/if (!${FindItem[=${ITPName}].ID}) {
					/delay 3s !${AdvLoot.LootInProgress}
					/advloot personal ${k} loot
					/delay 3s !${AdvLoot.LootInProgress}
					/delay ${Math.Calc[${LootLagDelay}+5]}
					/if (${Window[ConfirmationDialogBox].Open}) {
						/nomodkey /notify ConfirmationDialogBox Yes_Button leftmouseup
						/delay ${Math.Calc[${LootLagDelay}+10]}
					}
				}
				/varset ITStack ${FindItem[=${ITPName}].StackSize}
				/if (${ITStack}>20) /varset ITStack 20
				/if (${Math.Calc[${ITStack}*(${FindItem[=${ITPName}].Value}/1000)]} < ${StackPlatValue} && !${FindItem[=${ITPName}].WornSlots}) {
					/ini "${NinjaIniFile}" "${ITPName.Left[1]}" "${ITPName}" Ignore
					/echo NINJADVLOOT: Adding worthless ${ITPName}=Ignore to the ${NinjaIniFile} file.
					/varset IniEntry Ignore
				} else {
					/ini "${NinjaIniFile}" "${ITPName.Left[1]}" "${ITPName}" Keep
					/echo NINJADVLOOT: Adding valuable ${ITPName}=Keep to the ${NinjaIniFile} file.
					/varset IniEntry Keep
				}
			}
			| Leave items marked ignore on corpse
			/if  (${Select[${IniEntry},Ignore]}||${AdvLoot.PList[${k}].Never}==true) {
				/if (${Debugloot}||${SpamLootInfo}) /echo NINJADVLOOT: PList: ${ITPName} is marked ${IniEntry}. Leaving item.
				/delay 3s !${AdvLoot.LootInProgress}
				/advloot personal ${k} leave
				/delay 3s !${AdvLoot.LootInProgress}
				/if (${LootLagDelay}) /delay ${LootLagDelay}
				/continue
			}
			| Check quantity of Quest items and loot or leave
			/if (${Select[${IniEntry},Quest]}) {
				/varset KeepAmount ${Ini[${NinjaIniFile},"${ITPName.Left[${i}]}","${ITPName}"].Arg[2,|]}
				/if (${KeepAmount}==0) /varset KeepAmount ${QuestKeep}
				/if (${FindItemCount[=${ITPName}]} < ${KeepAmount}) {
					/if (${Debugloot}||${SpamLootInfo}) /echo NINJADVLOOT: PList: I need ${Math.Calc[${KeepAmount}-${FindItemCount[=${ITPName}]}]} more ${ITPName}(s) loot it
					/delay 3s !${AdvLoot.LootInProgress}
					/advloot personal ${k} loot
					/delay ${Math.Calc[${LootLagDelay}+5]}
					/if (${Window[ConfirmationDialogBox].Open}) {
						/nomodkey /notify ConfirmationDialogBox Yes_Button leftmouseup
						/delay ${Math.Calc[${LootLagDelay}+10]}
					}
				} else {
					/if (${Debugloot}||${SpamLootInfo}) /echo NINJADVLOOT: PList: I already have ${FindItemCount[=${ITPName}]} of ${KeepAmount} ${ITPName}(s) leave it
					/delay 3s !${AdvLoot.LootInProgress}
					/advloot personal ${k} leave
					/if (${LootLagDelay}) /delay ${LootLagDelay}
				}
				/continue
			}
			| Loot remaining items keep/sell/destroy
			/if (${Select[${IniEntry},Keep,Destroy,Sell]}) {
				/if (${Debugloot}||${SpamLootInfo}) /echo NINJADVLOOT: PList: Looting Item# ${k}, ${ITPName}=${IniEntry}
				/delay 3s !${AdvLoot.LootInProgress}
				/advloot personal ${k} loot
				/delay 3s !${AdvLoot.LootInProgress}
				/delay ${Math.Calc[${LootLagDelay}+5]}
				/if (${Window[ConfirmationDialogBox].Open}) {
					/nomodkey /notify ConfirmationDialogBox Yes_Button leftmouseup
					/delay ${Math.Calc[${LootLagDelay}+10]}
				}
				/if (${Select[${IniEntry},Destroy]}) {
					/if (${LootLagDelay}) /delay ${LootLagDelay}
					/call HandleItem "${ITPName}" Destroy "${ITStackSize}"
				}
			}
			/next k
			| Report Bag Space
			/if (${SpamLootInfo}) {
				/if (${Debugloot}) /echo DEBUGLOOT Report available bag space, line# ${Macro.CurLine}
				/varset FreeBagSpace 0
				/for k 1 to 10
				/if (${InvSlot[Pack${k}].Item.Container} && ${InvSlot[Pack${k}].Item.Name.NotEqual[${ExcludeBag1}]} && ${InvSlot[Pack${k}].Item.Name.NotEqual[${ExcludeBag2}]}) {
					/varcal FreeBagSpace ${FreeBagSpace}+(${InvSlot[Pack${k}].Item.Container}-${InvSlot[Pack${k}].Item.Items})
				}
				/next k
				/echo NINJADVLOOT: free bag space = ${FreeBagSpace}, looting stops if <= ${SaveBagSlots}
			}
		}
	}
	/varset LootTimer ${Math.Calc[${Math.Rand[5]}+8]}s
	/varset SubEnd ${Macro.RunTime}
	/if (${Debugloot}) /echo Looting complete - elasped time to process ${ITLootCount} items = ${Math.Calc[${SubEnd}-${SubStart}]} seconds
	/if (${Debugloot})  /echo Leaving UseAdvLoot - next check in ${Math.Calc[${LootTimer}/10]} seconds, line# ${Macro.CurLine}
/return

Sub HandleItem(ItemName, DoWhat, HowMany)
    /if (${Debugloot}) /echo DEBUGLOOT Enter Sub HandleItem ${ItemName} ${DoWhat} ${HowMany}, line# ${Macro.CurLine}
	/declare dc int local
	/declare Bag int local
	/for dc 1 to ${HowMany}
    /declare HandleTimer timer local 5s
    /if (${DoWhat.Equal[Destroy]} && ${FindItem[=${ItemName}].ID}) {
        :GetItem
            /nomodkey /ctrl /itemnotify "${ItemName}" leftmouseup
            /delay 1s ${Cursor.ID}
        /if (!${Cursor.ID} && ${HandleTimer}) /goto :GetItem
        /if (${Cursor.ID}==${FindItem[=${ItemName}].ID}) {
            /if (${Debugloot}||${SpamLootInfo}) /echo NINJADVLOOT: Destroying ${dc} of ${HowMany} ${Cursor.Name}
            /destroy
            /delay ${Math.Calc[${LootLagDelay}+5]}
            /if (${Window[ConfirmationDialogBox].Open}) {
                /nomodkey /notify ConfirmationDialogBox Yes_Button leftmouseup
				/delay ${Math.Calc[${LootLagDelay}+10]}
            }
            /delay 1s !${Cursor.ID}
        }
    }
	/next dc
	|Close any packs left open
	/for Bag 1 to 10
	/if (${Window[Pack${Bag}].Open}) /itemnotify pack${Bag} rightmouseup
	/next Bag

    /if (${Debugloot}) /echo DEBUGLOOT Leave Sub HandleItem, line# ${Macro.CurLine}
/return

Sub CheckGlobalList(GItemName,int GListNum, LootSystem)
/declare i int local
/declare j int local
/declare GItem string local
    | Create global list from ini file
    /if (${GlobalLootOn} && ${GlobalList[1].Equal[empty]}) {
        /for i 1 to ${${GlobalCount}}
            /varset GItem ${Ini[${NinjaIniFile},"Global","Global${i}"]}
            /if (!${GItem.Find[item name]} && !${GItem}) {
                /varset GlobalList[${i}] ${GItem}
            }
        /next i
    }
    | Check if item is in global list
	/if (${Debugloot}) /echo DEBUGLOOT CheckGlobalList
    /for j 1 to ${GlobalCount}
        /if (${GlobalList[${i}].Arg[1,|].Find[${GItemName}]}) {
            /if (${LootSystem.Equal[${AdvLoot.SCount}]}) {
                /if (${GlobalList[${i}].Arg[2,|].Equal[Ignore]}) /advloot shared ${GListNum} leave
                /if (${Select[${GlobalList[${i}].Arg[2,|]},sell,keep,destroy]} ) {
                    /advloot shared ${GListNum} giveto ${Me.Name}
                    /delay 10
                }
            }
            /if (${LootSystem.Equal[${AdvLoot.PCount}]}) {
                /if (${GlobalList[${i}].Arg[2,|].Equal[Ignore]}) /advloot shared ${GListNum} leave
                /if (${Select[${GlobalList[${i}].Arg[2,|]},sell,keep,destroy]} ) {
                    /advloot personal ${GListNum} loot
                    /delay 10
                    /if (${Window[ConfirmationDialogBox].Open}) {
                        /nomodkey /notify ConfirmationDialogBox Yes_Button leftmouseup
                        /delay 10
                    }
                    /if (${Select[${IniEntry},Destroy]}) {
                        /call HandleItem "${GItemName}" Destroy
                    }
                }
            }
        }
    /next j
/return
