--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ATTACHMENT.Base = "att_laser"
ATTACHMENT.Name = "Лазерный целеуказатель"
ATTACHMENT.Model = Model("models/viper/mw/attachments/attachment_vm_laser03.mdl")
ATTACHMENT.Icon = Material("viper/mw/attachments/icons/laser/icon_attachment_laser03.vmt")

ATTACHMENT.Laser = {
	BeamMaterial = Material("mw19_laserbeam.vmt"),
	DotMaterial = Material("sprites/light_glow02_add.vmt"),
	BeamSize = 15,
	BeamWidth = 0.5,
	DotSize = 5,
	Color = Color(235, 51, 51),
	Attachment = "laser"
}