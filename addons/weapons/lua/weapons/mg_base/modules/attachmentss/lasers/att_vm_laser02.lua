--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ATTACHMENT.Base = "att_laser"
ATTACHMENT.Name = "Фонарь с ЛЦУ"
ATTACHMENT.Model = Model("models/viper/mw/attachments/attachment_vm_laser02.mdl")
ATTACHMENT.Icon = Material("viper/mw/attachments/icons/laser/icon_attachment_laser02.vmt")

ATTACHMENT.Flashlight = {
	FlashlightMaterial = Material("effects/flashlight001.vmt"),
	Color = Color(255, 255, 255, 255),
	Attachment = "laser"
}

ATTACHMENT.Laser = {
	BeamMaterial = Material("mw19_laserbeam.vmt"),
	DotMaterial = Material("sprites/light_glow02_add.vmt"),
	BeamSize = 15,
	BeamWidth = 0.5,
	DotSize = 5,
	Color = Color(235, 51, 51),
	Attachment = "laser"
}