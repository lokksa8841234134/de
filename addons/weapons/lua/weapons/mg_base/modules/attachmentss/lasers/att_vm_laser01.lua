--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ATTACHMENT.Base = "att_laser"
ATTACHMENT.Name = "Фонарь"
ATTACHMENT.Model = Model("models/viper/mw/attachments/attachment_vm_laser01.mdl")
ATTACHMENT.Icon = Material("viper/mw/attachments/icons/laser/icon_attachment_laser01.vmt")

ATTACHMENT.Laser = {}

ATTACHMENT.Flashlight = {
    FlashlightMaterial = Material("effects/flashlight001.vmt"),
    Color = Color(255, 255, 255, 255),
    Attachment = "laser"
}

function ATTACHMENT:DoLaserRender(weapon, laserModel)
end