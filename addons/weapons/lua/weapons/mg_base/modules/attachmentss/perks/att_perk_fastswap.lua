--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ATTACHMENT.Base = "att_perk"
ATTACHMENT.Name = "Quickdraw"
ATTACHMENT.Icon = Material("viper/mw/attachments/icons/perks/perk_icon_fastswap.vmt")

local BaseClass = GetAttachmentBaseClass(ATTACHMENT.Base)

function ATTACHMENT:Stats(weapon)
    BaseClass.Stats(self, weapon)
    
    weapon.Animations.Draw.Fps = weapon.Animations.Draw.Fps * 1.5
    weapon.Animations.Holster.Fps = weapon.Animations.Holster.Fps * 1.5
end