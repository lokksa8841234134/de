--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ATTACHMENT.Base = "att_receiver"
ATTACHMENT.Name = "Default"
ATTACHMENT.Model = Model("models/590_dqr/weapon_mossberg_590a1_12g_lod0.mdl")

ATTACHMENT.AttachmentBodygroups = {
	["tag_psg"] = 1,
	["tag_stock"] = 1
}

local BaseClass = GetAttachmentBaseClass(ATTACHMENT.Base)

function ATTACHMENT:PostProcess(weapon)
	BaseClass.PostProcess(self, weapon)
	--weapon:SetGripPoseParameter("grip_front_offset")
	weapon:SetGripPoseParameter2("grip_stockh_offset")
end