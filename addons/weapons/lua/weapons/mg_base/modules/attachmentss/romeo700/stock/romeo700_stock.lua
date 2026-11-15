--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ATTACHMENT.Base = "att_stock"
ATTACHMENT.Model = Model("models/noire/700.mdl")

function ATTACHMENT:OverrideMaterial(path, mat, weapon)
	if weapon:HasAttachment("romeo700_scope") and mat == "nam_m40" then return path, "nam_m40a1" end
	return path, mat
end