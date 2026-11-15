--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ATTACHMENT.Base = "att_grip_mac10"
ATTACHMENT.Name = "Ремень"
ATTACHMENT.Model = Model("models/mac_10_fg.mdl")
ATTACHMENT.Icon = Material("icon/mac_sling.vmt")

ATTACHMENT.VElement = {
	Bone = "tag_grip_attach",
	Position = Vector(0, -0.24, 0),
	Angles = Angle(0, 0, 0),
	Offsets = {}
}

local BaseClass = GetAttachmentBaseClass(ATTACHMENT.Base)

function ATTACHMENT:PostProcess(weapon)
	BaseClass.PostProcess(self, weapon)
end

function ATTACHMENT:PostProcess(weapon)
	BaseClass.PostProcess(self, weapon)
	weapon:SetGripPoseParameter("grip_vert_offset")
	weapon.Animations.Ads_In.Fps = weapon.Animations.Ads_In.Fps * 1.2
	weapon.Animations.Ads_Out.Fps = weapon.Animations.Ads_Out.Fps * 0.95
	weapon.Recoil.Vertical[2] = weapon.Recoil.Vertical[2] * 1.3
	weapon.Recoil.Horizontal[2] = weapon.Recoil.Horizontal[2] * 1.3
end