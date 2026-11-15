--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ATTACHMENT.Base = "att_magazine"
ATTACHMENT.Model = Model("models/weapons/cs2/tec9/attachment_vm_pi_tec9_mag.mdl")

ATTACHMENT.BulletList = {
	[0] = {"j_ammo_02"},
	[1] = {"j_ammo_03"},
	[2] = {"j_ammo_04"},
	[3] = {"j_ammo_05"},
}

local BaseClass = GetAttachmentBaseClass(ATTACHMENT.Base)

function ATTACHMENT:Stats(weapon)
	BaseClass.Stats(self, weapon)
end