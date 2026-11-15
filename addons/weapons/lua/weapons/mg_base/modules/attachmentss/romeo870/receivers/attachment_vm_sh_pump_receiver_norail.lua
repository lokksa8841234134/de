--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ATTACHMENT.Base = "att_receiver"
ATTACHMENT.Name = "Раритет (альт.)"
ATTACHMENT.Model = Model("models/viper/mw/attachments/romeo870/attachment_vm_sh_pump_receiver_norail.mdl")
ATTACHMENT.Icon = Material("viper/mw/attachments/icons/romeo870/icon_attachment_sh_romeo870_receiver_v2.vmt")

ATTACHMENT.ExcludedAttachments = {"attachment_vm_sh_romeo870_stock_pistolgrip", "attachment_vm_sh_romeo870_stock", "attachment_vm_sh_romeo870_stock_wood"}

ATTACHMENT.ExcludedCategories = {"Системы", "Приклады", "Приклады", "Прицелы"}


ATTACHMENT.CosmeticChange = true

ATTACHMENT.AttachmentBodygroups = {
	["tag_stock"] = 1,
}

local BaseClass = GetAttachmentBaseClass(ATTACHMENT.Base)

function ATTACHMENT:PostProcess(weapon)
	BaseClass.PostProcess(self, weapon)
	weapon:SetGripPoseParameter2("grip_stockh_offset")
	weapon.DoEjection = function() end
	weapon.PrintName = "Ithaca 37"
end