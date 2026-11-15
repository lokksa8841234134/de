--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ATTACHMENT.Base = "att_grip"
ATTACHMENT.Name = "Мод. вертикальная рукоятка"
ATTACHMENT.Model = Model("models/viper/mw/attachments/attachment_vm_vertgrip_stubby04.mdl")
ATTACHMENT.Icon = Material("viper/mw/attachments/icons/grips/icon_attachment_vertgrip_stubby04.vmt")
local BaseClass = GetAttachmentBaseClass(ATTACHMENT.Base)
function ATTACHMENT:Stats(weapon)
    BaseClass.Stats(self, weapon)
    
    weapon.Animations.Ads_In.Fps = weapon.Animations.Ads_In.Fps * 0.97
    weapon.Animations.Ads_Out.Fps = weapon.Animations.Ads_Out.Fps * 0.97
    weapon.Animations.Holster.Fps = weapon.Animations.Holster.Fps * 0.97
    weapon.Animations.Draw.Fps = weapon.Animations.Draw.Fps * 0.97
    weapon.Recoil.Horizontal[1] = self:ChangeRecoil(weapon.Recoil.Horizontal[1], 0.85)
    weapon.Recoil.Horizontal[2] = self:ChangeRecoil(weapon.Recoil.Horizontal[2], 0.85)
    weapon.HoldType = "RifleWithVerticalGrip"
end 