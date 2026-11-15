--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ATTACHMENT.Base = "att_barrel"
ATTACHMENT.Name = "Укороченный ствол (115 мм)"
ATTACHMENT.Model = Model("models/att/m4/barrel_ar15_short.mdl")
ATTACHMENT.ExcludedCategories = {"ЛЦУ", "Рукоятки"}

local BaseClass = GetAttachmentBaseClass(ATTACHMENT.Base)
function ATTACHMENT:Stats(weapon)
	BaseClass.Stats(self, weapon)
	weapon.AlternateGrips = true
	weapon.Animations.Ads_In.Fps = weapon.Animations.Ads_In.Fps * 1.13
	weapon.Animations.Ads_Out.Fps = weapon.Animations.Ads_Out.Fps * 1.13
	weapon.Animations.Draw.Fps = weapon.Animations.Draw.Fps * 1.3
	weapon.Animations.Holster.Fps = weapon.Animations.Holster.Fps * 1.3
	weapon.Bullet.EffectiveRange = weapon.Bullet.EffectiveRange * 0.8
	weapon.Bullet.DropOffStartRange = weapon.Bullet.DropOffStartRange * 0.65
end