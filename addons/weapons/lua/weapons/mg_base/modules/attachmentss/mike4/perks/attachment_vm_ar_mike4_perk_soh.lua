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
	weapon.Animations.Reload = weapon.Animations.Reload_Fast
	weapon.Animations.Reload_Empty = weapon.Animations.Reload_Empty_Fast
	weapon.Animations.Reload_Calsmg = weapon.Animations.Reload_Calsmg_Fast
	weapon.Animations.Reload_Empty_Calsmg = weapon.Animations.Reload_Empty_Calsmg_Fast
	weapon.Animations.Reload_XmagLrg = weapon.Animations.Reload_XmagLrg_Fast
	weapon.Animations.Reload_Empty_XmagLrg = weapon.Animations.Reload_Empty_XmagLrg_Fast
	weapon.Animations.Reload_Xmag = weapon.Animations.Reload_Xmag_Fast
	weapon.Animations.Reload_Empty_Xmag = weapon.Animations.Reload_Empty_Xmag_Fast
end