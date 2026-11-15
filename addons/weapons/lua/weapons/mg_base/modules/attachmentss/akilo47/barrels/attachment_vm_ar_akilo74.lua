--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ATTACHMENT.Base = "att_barrel"
ATTACHMENT.Model = Model("models/viper/mw/attachments/akilo47/attachment_vm_ar_akilo47_barrel.mdl")

ATTACHMENT.ExcludedCategories = {"Рукоятки"}

function ATTACHMENT:OverrideMaterial(path, mat)
	if mat == "weapon_vm_ar_akilo47_fore" then
		return "gbskins/", "weapon_vm_ar_akilo74_fore"
	end

	return path, mat
end

function ATTACHMENT:OverrideWeaponMaterial(path, mat)
	if mat == "weapon_vm_ar_akilo47_pgrip" then
		return "gbskins/", "weapon_vm_ar_akilo74_pgrip"
	end

	if mat == "weapon_vm_ar_akilo47_stock" then
		return "gbskins/", "weapon_vm_ar_akilo74_stock"
	end

	return path, mat
end