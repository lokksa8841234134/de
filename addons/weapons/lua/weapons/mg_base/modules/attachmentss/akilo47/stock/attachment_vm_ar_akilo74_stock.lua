--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ATTACHMENT.Base = "att_stock"
ATTACHMENT.Model = Model("models/viper/mw/attachments/akilo47/attachment_vm_ar_akilo47_stock.mdl")

function ATTACHMENT:OverrideMaterial(path, mat)
	if mat == "weapon_vm_ar_akilo47_stock" then
		return "gbskins/", "weapon_vm_ar_akilo74_stock"
	end

	return path, mat
end