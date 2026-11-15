--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ATTACHMENT.Base = "att_barrel"
ATTACHMENT.Name = "Увеличенный ствол"
ATTACHMENT.Model = Model("models/zaihny/mw23/attachments/mike93/attachment_vm_jup_pi_mike93_bar_000.mdl")
ATTACHMENT.Icon = Material("viper/mw/attachments/icons/mike9/icon_attachment_pi_mike9_barlong.vmt")

ATTACHMENT.UseJunk = "parts_all"

local BaseClass = GetAttachmentBaseClass(ATTACHMENT.Base)

function ATTACHMENT:Stats(weapon)
    BaseClass.Stats(self, weapon)
    weapon.Bullet.EffectiveRange = weapon.Bullet.EffectiveRange * 1.12
    weapon.Bullet.DropOffStartRange = weapon.Bullet.DropOffStartRange * 1.12
    weapon.Cone.Hip =  weapon.Cone.Hip * 0.9
    weapon.Animations.Ads_In.Fps = weapon.Animations.Ads_In.Fps * 0.9
    weapon.Animations.Ads_Out.Fps = weapon.Animations.Ads_Out.Fps * 0.9
    weapon.Animations.Draw.Fps = weapon.Animations.Draw.Fps * 0.9
    weapon.Animations.Holster.Fps = weapon.Animations.Holster.Fps * 0.9
end