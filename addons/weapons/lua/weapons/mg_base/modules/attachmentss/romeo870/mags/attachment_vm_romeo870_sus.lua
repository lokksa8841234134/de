--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ATTACHMENT.Base = "att_magazine"
ATTACHMENT.Category = "Системы"
ATTACHMENT.Name = "Cock N bols"

function ATTACHMENT:PostProcess(weapon)
	weapon.UseINV = weapon.UseINV or weapon.UsedINV
	weapon.UsedINV = nil
	weapon.UseMags = nil
end 