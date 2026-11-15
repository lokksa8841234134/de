--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
if (SERVER) then
	AddCSLuaFile("shared.lua")
end

SWEP.PrintName = "Руки"
SWEP.Base = "weapon_base"
SWEP.Author = "MacTavish"
SWEP.ViewModel = "models/weapons/c_realhands.mdl"
SWEP.WorldModel = ""
SWEP.ViewModelFOV = 64
SWEP.UseHands = true
SWEP.Primary.Ammo = "none"
SWEP.Spawnable = false
SWEP.AdminSpawnable = true
SWEP.DrawCrosshair = false
SWEP.HoldType = "normal"
SWEP.Slot = 7
SWEP.SwimDelay = 1
SWEP.Primary.Ammo = "none"
SWEP.Primary.Clipsize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Secondary.Ammo = "none"
SWEP.Secondary.Clipsize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.DrawAmmo = false
SWEP.PlaySprintAnim = false
SWEP.PlayJumpAnim = false
SWEP.AutoSwitchTo = true
SWEP.AutoSwitchFrom = true

function SWEP:Think()
end

function SWEP:Holster()
	return false
end

function SWEP:Deploy()
	self:SetHoldType("normal")
end

function SWEP:PrimaryAttack()
	self:SetHoldType("normal")
end

function SWEP:SecondaryAttack()
end

function SWEP:Initialize()
	self:SetHoldType("normal")
end

if CLIENT then
	local clrs = {
		m = Color(255, 255, 255, 200),
		s = Color(127, 127, 127, 150),
		d = Color(0, 0, 0, 20),
		r = Color(255, 0, 0),
	}

	local cuffs = Material("cyberhud/cuffs.png", "smooth")

	function SWEP:DrawHUD()
		if self:GetOwner():getDarkRPVar("unconscious") then return end
		local x, y = ScrW() / 2, ScrH() * 0.8
		local sp = draw.SimpleTextOutlined("Вы в наручниках", "MSDFont.20", x, y + 3, clrs.m, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 2, clrs.d)
		MSD.DrawKey(x - sp / 2 - 30, y, "    ", 155)
		MSD.DrawTexturedRect(x - sp / 2 - 26, y + 4, 20, 20, cuffs, clrs.m)
	end
end