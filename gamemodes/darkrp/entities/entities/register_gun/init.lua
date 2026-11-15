--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- оружейный шкаф: общий код касс - modules/inventory/sv_registers.lua
McINV.SetupRegister(ENT)

--[[---------------------------------------------------------------------------
	Замок: ключи владельца (doorsystem/sv_doors.lua, keysLock и keysUnLock)
	и отмычка (onLockpickCompleted в shared.lua). Открытый шкаф (IsUnLocked)
	E по самому шкафу открывается как контейнер любому (McINV.CanAccess),
	запертый - снова только владельцу, у остальных содержимое закрывается
---------------------------------------------------------------------------]]
function ENT:Lock()
	self.IsUnLocked = nil
	McINV.CloseViewers(self)
end

function ENT:UnLock()
	self.IsUnLocked = true
end
