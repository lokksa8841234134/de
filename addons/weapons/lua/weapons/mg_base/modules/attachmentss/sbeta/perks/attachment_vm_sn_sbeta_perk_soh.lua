--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ATTACHMENT.Base = "att_perk_soh"

local BaseClass = GetAttachmentBaseClass(ATTACHMENT.Base)

function ATTACHMENT:Stats(weapon)
    BaseClass.Stats(self, weapon)

    weapon.Animations.Reload_Start.Fps = weapon.Animations.Reload_Start.Fps * 1.25
    weapon.Animations.Reload_Loop.Fps = weapon.Animations.Reload_Loop.Fps * 1.25
    weapon.Animations.Reload_End.Fps = weapon.Animations.Reload_End.Fps * 1.25
    weapon.Animations.Reload_End_Empty.Fps = weapon.Animations.Reload_End_Empty.Fps * 1.25
end