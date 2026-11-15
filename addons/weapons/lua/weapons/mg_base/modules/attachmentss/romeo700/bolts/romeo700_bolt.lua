--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ATTACHMENT.Base = "att_bolt"
ATTACHMENT.Model = Model("models/noire/700bolt.mdl")

ATTACHMENT.Bodygroups = {
	["sight"] = 2
}

function ATTACHMENT:OverrideWeaponMaterial(path, mat)
	return "", "null"
end