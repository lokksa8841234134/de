--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ATTACHMENT.Base = "att_receiver"
ATTACHMENT.Model = Model("models/viper/mw/attachments/akilo47/v_akilo47m.mdl")

ATTACHMENT.Bodygroups = {
	["receiver"] = 1
}

function ATTACHMENT:OverrideMaterial(path, mat)
	if mat == "weapon_vm_ar_akilo47_fore" then
		return "gbskins/", "weapon_vm_ar_akilo74_fore"
	end

	if mat == "weapon_vm_ar_akilo47_pgrip" then
		return "gbskins/", "weapon_vm_ar_akilo74_pgrip"
	end

	if mat == "weapon_vm_ar_akilo47_stock" then
		return "gbskins/", "weapon_vm_ar_akilo74_stock"
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