--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ATTACHMENT.Base = "att_rail"
ATTACHMENT.Name = "Крепление для прицела"
ATTACHMENT.Icon = Material("viper/mw/attachments/icons/augolf/icon_attachment_sm_augolf_arrail.vmt")

ATTACHMENT.Bodygroups = {
	["tag_rail_upper"] = 2,
	["tag_sight"] = 3
}

ATTACHMENT.ExcludedAttachments = {"attachment_vm_sm_augolf_lmgrail"}

ATTACHMENT.CosmeticChange = true
local BaseClass = GetAttachmentBaseClass(ATTACHMENT.Base)

function ATTACHMENT:Stats(weapon)
	BaseClass.Stats(self, weapon)
	weapon.PrintName = "AUG A2"
end