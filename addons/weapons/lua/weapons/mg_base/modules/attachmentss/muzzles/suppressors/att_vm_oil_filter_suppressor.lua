--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ATTACHMENT.Base = "att_muzzle"
ATTACHMENT.Name = "Самодельный глушитель"
ATTACHMENT.Model = Model("models/viper/mw/attachments/attachment_vm_oil_filter_suppressor.mdl")
ATTACHMENT.Icon = Material("viper/mw/attachments/icons/muzzle/icon_attachment_oil_filter_suppressor.vmt")

ATTACHMENT.BonemergeToCategory = {"Стволы"}

ATTACHMENT.AttachmentBodygroups = {
	["tag_tip"] = 1,
	["muzzle"] = 1,
	["tip"] = 1
}

ATTACHMENT.Bodygroups = {
	["tag_tip"] = 1,
	["muzzle"] = 1,
	["tip"] = 1
}

local BaseClass = GetAttachmentBaseClass(ATTACHMENT.Base)

function ATTACHMENT:Stats(weapon)
	BaseClass.Stats(self, weapon)
	weapon.Resource = weapon.Resource * 7
	weapon.DistSound = ""
	weapon:doSuppressorStats()
end

function ATTACHMENT:OverrideMaterial(path, mat)
	return "phoenix_storms/trains/", "track_plateside"
end