--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ATTACHMENT.Base = "att_perk"
ATTACHMENT.Name = "Bolthead"
ATTACHMENT.Icon = Material("viper/mw/attachments/icons/perks/perk_icon_bolt.vmt")

local BaseClass = GetAttachmentBaseClass(ATTACHMENT.Base)

function ATTACHMENT:Stats(weapon)
    BaseClass.Stats(self, weapon)
    
    if (weapon.Animations.Rechamber != nil) then
        weapon.Animations.Rechamber.Fps = weapon.Animations.Rechamber.Fps * 1.5
    end
end