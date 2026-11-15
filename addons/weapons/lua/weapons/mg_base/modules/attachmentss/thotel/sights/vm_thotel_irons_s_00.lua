--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ATTACHMENT.Base = "att_sight"
ATTACHMENT.Model = Model("models/easy/vg/attachments/thotel/vm_thotel_irons_s_00.mdl")
local BaseClass = GetAttachmentBaseClass(ATTACHMENT.Base)

function ATTACHMENT:PostProcess(weapon)
	BaseClass.PostProcess(self, weapon)

	if weapon:HasAttachment("vm_sm_thotel_angled_00") then
		weapon:SetGripPoseParameter("grip_ang_offset")
	elseif weapon:HasAttachment("att_ammo") then
		weapon:SetGripPoseParameter("grip_fmag_offset")
	end
end