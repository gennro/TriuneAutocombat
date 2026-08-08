local mq = require("mq")

local function Main()
print('Stopping KissEdit')
mq.cmd('/lua stop kissedit/kissedit')
mq.delay(100)
print('Starting KissEdit')
mq.cmd('/lua run kissedit')
--print('Starting KissAssist')
mq.delay(1000)
mq.cmd('/kasettings load')

end

Main()










