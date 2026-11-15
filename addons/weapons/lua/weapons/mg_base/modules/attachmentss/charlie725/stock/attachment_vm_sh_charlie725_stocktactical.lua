--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ATTACHMENT.Base = "att_stock"
ATTACHMENT.Name = "Модифицированный приклад"
ATTACHMENT.Model = Model("models/viper/mw/attachments/charlie725/attachment_vm_sh_charlie725_stocktactical.mdl")
ATTACHMENT.Icon = Material("viper/mw/attachments/icons/charlie725/icon_attachment_sh_charlie725_stocktactical.vmt")
local BaseClass = GetAttachmentBaseClass(ATTACHMENT.Base)

function ATTACHMENT:Stats(weapon)
	BaseClass.Stats(self, weapon)
	weapon.Animations.Ads_In.Fps = weapon.Animations.Ads_In.Fps * 0.77
	weapon.Animations.Ads_Out.Fps = weapon.Animations.Ads_Out.Fps * 0.77
	weapon.Animations.Holster.Fps = weapon.Animations.Holster.Fps * 0.8
	weapon.Animations.Draw.Fps = weapon.Animations.Draw.Fps * 0.8
	weapon.Recoil.Horizontal[1] = weapon.Recoil.Horizontal[1] * 0.75
	weapon.Recoil.Horizontal[2] = weapon.Recoil.Horizontal[2] * 0.75
	weapon.Cone.Shake = weapon.Cone.Shake * 0.2
	weapon.Recoil.Punch = 0.75

	weapon.HolsterData = weapon.HolsterDataBack
	weapon.SlotType = 1
end