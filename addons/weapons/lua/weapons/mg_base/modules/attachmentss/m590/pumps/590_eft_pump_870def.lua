--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ATTACHMENT.Base = "att_pump"
ATTACHMENT.Name = "Тактическое цевьё"
ATTACHMENT.Model = Model("models/590_dqr/weapon_mossberg_590a1_12g_bolt_lod0.mdl")
ATTACHMENT.Icon = Material("icon/870_pp.vmt")

local BaseClass = GetAttachmentBaseClass(ATTACHMENT.Base)

function ATTACHMENT:Stats(weapon)
	BaseClass.Stats(self, weapon)
	weapon.Recoil.Vertical[1] = weapon.Recoil.Vertical[1] * 1.2
	weapon.Recoil.Vertical[2] = weapon.Recoil.Vertical[2] * 1.1
	weapon.Recoil.Horizontal[1] = weapon.Recoil.Horizontal[1] * 1.1
	weapon.Recoil.Horizontal[2] = weapon.Recoil.Horizontal[2] * 1.2
	weapon.Primary.RPM = 350
	weapon.Animations.Rechamber.Length = 0.38
	weapon.Cone.Hip = 1.3
	weapon.Cone.Max = 7.5
end
