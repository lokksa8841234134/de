--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ATTACHMENT.Base = "att_barrel"
ATTACHMENT.Model = Model("models/att/glock/glock_slide.mdl")
ATTACHMENT.Name = "Заводской ствол"

ATTACHMENT.ExcludedCategories = {"Дуло"}

function ATTACHMENT:OverrideMaterial(path, mat, weapon)
	if weapon:HasAttachment("att_reargrip_golf") and mat == "glock_17" then return path, "glock_17silver" end
	return path, mat
end