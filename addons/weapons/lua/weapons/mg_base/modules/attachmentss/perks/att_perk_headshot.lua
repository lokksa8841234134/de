--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ATTACHMENT.Base = "att_perk"
ATTACHMENT.Name = "Soft-point Rounds"
ATTACHMENT.Icon = Material("viper/mw/attachments/icons/perks/perk_icon_flinch.vmt")

local BaseClass = GetAttachmentBaseClass(ATTACHMENT.Base)

function ATTACHMENT:Stats(weapon)
    BaseClass.Stats(self, weapon)
    
    if (weapon.Bullet != nil && weapon.Bullet.HeadshotMultiplier != nil) then
        weapon.Bullet.HeadshotMultiplier = weapon.Bullet.HeadshotMultiplier * 1.35
    end
end