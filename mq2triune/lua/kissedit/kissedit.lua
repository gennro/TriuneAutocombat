-------------------------------------------
local imGui = require('ImGui')
local mq = require('mq')
local shouldDrawGUI = true
local openGUI = true
local utils = require('mq/Utils')
local ini = require('kissedit/lib/LIP')
---------------------------------------------



--------------CONFIG----------------------------
local MacroName = "kissassist"
local Me_CleanName = mq.TLO.Me.Name()
local IniFileName = string.format("%s_%s.ini", MacroName, Me_CleanName)
    config_dir = mq.TLO.MacroQuest.Path():gsub('\\', '/')
    settings_file = '/config/KissAssist_'..Me_CleanName..'.ini'
	settings_path2 = tostring(config_dir)..'/config'
    settings_path = tostring(config_dir)..tostring(settings_file)

local template_dir = config_dir..'/lua/kissedit/templates/'

local config = ini.load(settings_path)
local configSettings = config
local Output_Text = "KissEdit Running"
local sections = {}
local values = {}
local parsed = {}
local sectionNames = {}
local editedline = {}
local settings = {}
local inputs = {}
local inputs1 = {}
local newKeys = {}
local checkboxes = {}
local templates = {}
local alwaysFalse = false
 for key, value in pairs(configSettings) do
table.insert(sections, value)

table.insert(sectionNames, key)
--table.sort(sectionNames)
end
------------INI SETTINGS----------------------------

if config.Buffs.BuffsOn then 
checkboxes['buffson'] = config.Buffs.BuffsOn
end



-------------------------------------------------------

------------------------------------------
local function ReloadIni()
mq.cmd('/lua run kissedit/kissrestart')
end
------------------------------------------


------------------------------------------
local function edit(inputFile, key, value)
value = tostring(value)

	local fileContent = {}
    local file = io.open(inputFile, 'r')
    for line in file:lines() do
        table.insert (fileContent, line)
    end
    io.close(file)

for k, v in pairs(fileContent) do
local lineNumber = k
local lineMatch = string.find(v, key..'=')
--print("value "..v, lineMatch)
if lineMatch ~= nil and lineMatch < 3 then
print('editing')
print(key.."="..value)
    fileContent[k] = key.."="..value
print('edited')
end
end
    file = io.open(inputFile, 'w')
    for index, value in ipairs(fileContent) do
        file:write(value..'\n')
    end
    io.close(file)
ReloadIni()
end
------------------------------------------





------------------------------------------
local function deleteKey(inputFile, key, value)
value = tostring(value)

	local fileContent = {}
    local file = io.open(inputFile, 'r')
    for line in file:lines() do
        table.insert (fileContent, line)
    end
    io.close(file)

for k, v in pairs(fileContent) do
local lineNumber = k
local lineMatch = string.find(v, key..'=')
--print("value "..v, lineMatch)
if lineMatch ~= nil and lineMatch < 3 then
print('editing')
print(key.."="..value)
    fileContent[k] = ''
print('edited')
end
end
    file = io.open(inputFile, 'w')
    for index, value in ipairs(fileContent) do
        file:write(value..'\n')
    end
    io.close(file)
ReloadIni()
end
------------------------------------------





------------------------------------------
local function salvageINI(inputFile, key, value)
key = tostring(key)
value = tostring(value)
print(key)
print(value)
if key == value then
mq.cmd('/lua run kissedit/salvageini')
else 
print('Incorrect File Name Entered')

end
end
------------------------------------------














------------------------------------------
local function addSection(inputFile, key)
section = tostring(key)
	local fileContent = {}
    local file = io.open(inputFile, 'r')
    for line in file:lines() do
        table.insert (fileContent, line)
    end
    io.close(file)


local lineMatch =nil
local lineMatch2=nil
local lineMatch=nil
local newLine='['..key..']'

for k, v in pairs(fileContent) do
local lineNumber = k

matchingstring = tostring('%b['..key..']')

local lineMatch = string.find(v, matchingstring)
local lineMatch3 = string.find(v, '=')

end

if lineMatch == nil and lineMatch3 == nil then
print('editing')

table.insert(fileContent, newLine)

print(newLine)
--print('edited')
end



    file = io.open(inputFile, 'w')
    for index, value in ipairs(fileContent) do
        file:write(value..'\n')
    end
    io.close(file)
ReloadIni()
end
------------------------------------------



--------------------------------------------

------------------------------------------
local function deleteSection(inputFile, value)
value=tostring(value)
print(value)
	local fileContent = {}
    local file = io.open(inputFile, 'r')
    for line in file:lines() do
        table.insert (fileContent, line)
    end
    io.close(file)


for k, v in pairs(fileContent) do
local lineNumber = k
local matchingstring = tostring(value..'%]')

local lineMatch = string.find(v, matchingstring)
local lineMatch2 = string.find(v, '%b[]')
local lineMatch3 = string.find(v, '=')
local newLine= ' '
if lineMatch ~= nil and lineMatch < 3  and lineMatch2 ~= nil and lineMatch3 == nil then
print('editing')

fileContent[k] = newLine
print('edited')

end
end
    file = io.open(inputFile, 'w')
    for index, value in ipairs(fileContent) do
        file:write(value..'\n')
    end
    io.close(file)
ReloadIni()
end








------------------------------------------




------------------------------------------
local function addKey(inputFile, key, section)
section = tostring(section)
	local fileContent = {}
    local file = io.open(inputFile, 'r')
    for line in file:lines() do
        table.insert (fileContent, line)
    end
    io.close(file)

print(fileContent[1])
for k, v in pairs(fileContent) do
local lineNumber = k
local lineMatch = string.find(v, section)
--print("value "..v, lineMatch)
if lineMatch ~= nil then
print('editing')
local newLine= key..'=NULL'
newIndex=tonumber(k+1)


local lineMatch2 = string.find(v, key..'=')
if lineMatch2 == nil then

table.insert(fileContent, newIndex, newLine)

print('edited')

end
end
end
    file = io.open(inputFile, 'w')
    for index, value in ipairs(fileContent) do
        file:write(value..'\n')
    end
    io.close(file)
ReloadIni()
end
------------------------------------------

local function importIni(inputFile, fileName)
newFile = tostring(template_dir)..tostring(fileName)

if utils.File.Exists(newFile) then

	local fileContent = {}
    local file = io.open(inputFile, 'r')
    for line in file:lines() do
        table.insert (fileContent, line)
    end
    io.close(file)

	local fileContent2 = {}
    local file2 = io.open(newFile, 'r')
    for line in file2:lines() do
        table.insert (fileContent2, line)
    end
    io.close(file2)


    file = io.open(inputFile, 'w')
    for index, value in ipairs(fileContent2) do
        file:write(value..'\n')
    end
    io.close(file)

print('File Imported')
ReloadIni()
end
end





------------------------------------------------

function GetFiles(mask)

   local files = {}
   local tmpfile = template_dir..'temp.ini'
 --  os.execute('ls -f > '..tmpfile)
   local f = io.open(tmpfile)
   if not f then return files end  
   local k = 1
   for line in f:lines() do
      files[k] = line
      k = k + 1
   end
   f:close()
   return files
 end


local function listFiles(directory) 

templates=GetFiles('.ini')

end



local function DrawIni()


--ImGui.Text(Output_Text) ImGui.SameLine()


------------------------------------------
if  ImGui.SmallButton('KissReload') then 
ReloadIni()
end
 ImGui.SameLine()
------------------------------------------
if  ImGui.SmallButton('Start KissAssist') then 

if mq.TLO.Group.Leader() then
mq.cmd('/mac kissAssist '..mq.TLO.Group.Leader())
else if mq.TLO.Target() then
mq.cmd('/mac kissAssist '..mq.TLO.Target())

end 
end
end





ImGui.SameLine()
------------------------------
if  ImGui.SmallButton('Stop KissAssist') then 
mq.cmd('/endmac kissassist')
end


ImGui.SameLine() 

if  ImGui.SmallButton('Start Hunter') then 
mq.cmd('/mac kissAssist hunter')
end




ImGui.SameLine()
------------------------------
ImGui.PushID('edit_sections')
 
newKeys.addsection = ImGui.Selectable("Add Section", newKeys.addsection, ImGuiSelectableFlags.None, ImVec2(75,20))

ImGui.PopID('edit_sections')
if newKeys.addsection then 

ImGui.PushID('inputs_sections')
inputs1.addsection = ImGui.InputText('New Section', inputs1.addsection, 256)
ImGui.PopID('inputs_sections')

ImGui.PushID('save_sections')
if  ImGui.SmallButton('Save') then 
addSection(settings_path, inputs1.addsection)
end
ImGui.PopID('save_sections')
end
-------------------------------

ImGui.SameLine() 
------------------------------
ImGui.PushID('edit_dsections')
 
newKeys.deletesection = ImGui.Selectable("Delete Section", newKeys.deletesection, ImGuiSelectableFlags.None, ImVec2(90,20))

ImGui.PopID('edit_dsections')
if newKeys.deletesection then 

ImGui.PushID('inputs_dsections')
inputs1.deletesection = ImGui.InputText('Delete Section', inputs1.deletesection, 0, ImVec2(300,20))
ImGui.PopID('inputs_sections')

ImGui.PushID('save_dsections')
if  ImGui.SmallButton('Save') then 
deleteSection(settings_path, inputs1.deletesection)
end
ImGui.PopID('save_dsections')
end
-------------------------------





ImGui.NewLine() 
    if ImGui.BeginTabBar("Tabs", ImGuiTabBarFlags.FittingPolicyScroll ) then
for key, value in pairs(sections) do


if ImGui.BeginTabItem(sectionNames[key]) then
  ImGui.PushID("tab_"..sectionNames[key])

--ImGui.Text(sectionNames[key])
--ImGui.SameLine()
ImGui.PushID('edit_'..key)
 




newKeys[key] = ImGui.Selectable("AddKey", newKeys[key], ImGuiSelectableFlags.None, ImVec2(80,30))
------------------------------------------------------
--newKeys[key] = ImGui.Checkbox("AddKey", newKeys[key])

ImGui.PopID('edit_'..key)
if newKeys[key] then 

ImGui.PushID('inputs_'..key)
inputs1[key] = ImGui.InputText('New Key', inputs1[key], 256)
ImGui.PopID('inputs_'..key)

ImGui.PushID('save_'..key)
if  ImGui.SmallButton('Save') then 
addKey(settings_path, inputs1[key], sectionNames[key])
end
ImGui.PopID('save_'..key)

end


-------------------------------------------

if sectionNames[key] == 'DPS'then 
ImGui.PushID("b_AddClicky")
if  ImGui.SmallButton('AddClicky') then 

mq.cmd('/setdps item ')
end
ImGui.PopID("b_AddClicky")
end
----------------------------------------------------
for k, v in pairs(value) do
v=tostring(v)
ImGui.PushID('delete_'..k)

  settings['delete_'..k] = ImGui.Selectable("x", settings['delete_'..k], ImGuiSelectableFlags.None, ImVec2(10,15))

if settings['delete_'..k] then
ImGui.SameLine()
if ImGui.SmallButton('Delete Key') then 
deleteKey(settings_path, k)
end
end
ImGui.PopID('delete_'..k)

ImGui.SameLine()

ImGui.PushID('edit_'..k)
  settings[k] = ImGui.Selectable("Edit", settings[k], ImGuiSelectableFlags.None, ImVec2(30,15))
ImGui.PopID('edit_'..k)
if settings[k] then 
ImGui.SameLine() 
ImGui.PushID('input_'..k)
inputs[k] = ImGui.InputText(k, inputs[k], 256)
ImGui.PopID('input_'..k)

ImGui.PushID('save_'..k)
if  ImGui.SmallButton('Save') then 
--edit(settings_path, k, searchText)
edit(settings_path, k, inputs[k])
end
ImGui.PopID('save_'..k)

end


ImGui.SameLine() 
ImGui.Text(k) 
ImGui.SameLine() 
ImGui.Text(v)




end

ImGui.EndTabItem(sectionNames[key])
ImGui.PopID("tab_"..sectionNames[key])
end


end
---------------------------------------------------




--------------------------------------------------
if ImGui.BeginTabItem('KissEditor') then
  ImGui.PushID("tab_KissEditor")
key='KissEditor'
newKeys[key] = ImGui.Selectable("Salvage Ini File", newKeys[key], ImGuiSelectableFlags.None, ImVec2(100,30))
------------------------------------------------------
--newKeys[key] = ImGui.Checkbox("AddKey", newKeys[key])

ImGui.PopID('edit_'..key)
if newKeys[key] then 
ImGui.Text('If Your KissAssist Wont Load Even With A Target Or Group Leader You Might Have A Broken INI File. Start From Scratch Here:')


ImGui.Text(tostring(IniFileName))
ImGui.PushID('inputs_'..key)
inputs1[key] = ImGui.InputText('Ini File Name', inputs1[key], 256)
ImGui.PopID('inputs_'..key)

ImGui.PushID('save_'..key)
if  ImGui.SmallButton('Delete Ini And Run KissAssist') then 
salvageINI(settings_path, inputs1[key], IniFileName)
end
ImGui.PopID('save_'..key)
ImGui.NewLine()
end

---------------------------------------------------
ImGui.SameLine()
 
newKeys.importIni = ImGui.Selectable("Import From Template", newKeys.importIni, ImGuiSelectableFlags.None, ImVec2(150,20))

if newKeys.importIni then 
ImGui.Text('Preformatted Ini Files')
local d = tostring(config_dir)
listFiles(d)

ImGui.Columns(2)

for k,v in pairs(templates) do

if v ~= 'temp.ini' then
ImGui.PushID('t_'..v)
if  ImGui.SmallButton(v) then 
importIni(settings_path, v)
end
ImGui.PopID('t_'..v)
end
end

ImGui.Columns(1)
end
------------------------------------------







end
  ImGui.PopID("tab_KissEditor")
ImGui.EndTabItem("tab_KissEditor")






--ImGui.EndTab(key)
end



end


-- Function to draw the UI
local function DrawMainWindow()

    if not openGUI then return end
    openGUI, shouldDrawGUI = ImGui.Begin("KissEdit", openGUI)
    if shouldDrawGUI then
	DrawIni()
end
  	ImGui.End("KissEdit")
end
	mq.imgui.init('KissEdit', DrawMainWindow)

while openGUI do
    mq.delay('1s')
end

	DrawMainWindow()
       