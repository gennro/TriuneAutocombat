local mq = require("mq")
local MacroName = "kissassist"
local Me_CleanName = mq.TLO.Me.Name()
local IniFileName = string.format("%s_%s.ini", MacroName, Me_CleanName)
    config_dir = mq.TLO.MacroQuest.Path():gsub('\\', '/')
    settings_file = '/config/KissAssist_'..Me_CleanName..'.ini'
    settings_path = tostring(config_dir)..tostring(settings_file)


local function Main()
key = tostring(settings_path)
value = tostring(IniFileName)
inputFile = tostring(settings_path)
print(key)

print('Deleting Ini File'..value)
print(inputFile)
file = os.remove(inputFile)
print('Ini File Deleted')
print('Running Kiss Assist')
mq.delay('1s')
if mq.TLO.Group.Leader() ~= nil then
mq.cmd('/mac kissassist '..tostring(mq.TLO.Group.Leader()))
else if mq.TLO.Target ~= nil then
mq.cmd('/mac kissassist '..tostring(mq.TLO.Target()))

end
end



mq.delay('15s')
mq.cmd('/lua run kissedit/kissrestart')
end

Main()










