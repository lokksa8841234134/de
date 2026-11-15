--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ATTACHMENT.Base = "att_pistolgrip"
ATTACHMENT.Name = "Облегчённая рукоять"
ATTACHMENT.Model = Model("models/viper/mw/attachments/attachment_vm_pi_mike_pistolgrip02.mdl")
ATTACHMENT.Icon = Material("viper/mw/attachments/icons/mike/icon_attachment_pi_mike_pistolgrip02.vmt")
ATTACHMENT.UseJunk = "parts_all"
local BaseClass = GetAttachmentBaseClass(ATTACHMENT.Base)
function ATTACHMENT:Stats(weapon)
    BaseClass.Stats(self, weapon)
    weapon.Animations.Ads_In.Fps = weapon.Animations.Ads_In.Fps * 1.05
    weapon.Animations.Ads_Out.Fps = weapon.Animations.Ads_Out.Fps * 1.05
    weapon.Recoil.AdsMultiplier = weapon.Recoil.AdsMultiplier * 0.95
end