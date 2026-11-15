--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ATTACHMENT.Base = "att_receiver"
ATTACHMENT.Name = "Гражданский ресивер"
ATTACHMENT.Model = Model("models/viper/mw/attachments/mpapa5/attachment_vm_sm_mpapa5_receiver.mdl")

function ATTACHMENT:OverrideMaterial(path, mat, weapon)
	if mat == "weapon_vm_sm_mpapa5_lower" then
		mat = "weapon_vm_sm_mpapa5_lower_sar"
	end

	return path, mat
end