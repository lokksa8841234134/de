--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ATTACHMENT.Base = "attachment_vm_sh_romeo870_barrel"
ATTACHMENT.Name = "Раритет"
ATTACHMENT.Model = Model("models/viper/mw/attachments/romeo870/attachment_vm_sh_pump_barrel.mdl")
ATTACHMENT.Icon = Material("viper/mw/attachments/icons/romeo870/icon_attachment_sh_romeo870_barrel_v2.vmt")

ATTACHMENT.ExcludedCategories = {"ЛЦУ", "Muzzle Devices"}


ATTACHMENT.CosmeticChange = true
local BaseClass = GetAttachmentBaseClass(ATTACHMENT.Base)

function ATTACHMENT:Stats(weapon)
	BaseClass.Stats(self, weapon)
	weapon.Primary.Sound = Sound("bocw.shotgun_pump.fire")
	weapon.Primary.ClipSize = 4
	weapon.Bullet.EffectiveRange = weapon.Bullet.EffectiveRange * 1.1
	weapon.Bullet.Spread = 0.07
end