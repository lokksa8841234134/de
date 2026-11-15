--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

--[[---------------------------------------------------------------------------
	Кран для двигателя (станция механика): ставится из посылки, сверху -
	экран (register_screen). E по крану или экрану - "Заказ автозапчастей"
	(только механик): McINV.UseRegister и сеть CarParts.Order -
	modules/inventory/sv_registers.lua
---------------------------------------------------------------------------]]
local DEFAULT_MODEL = "models/mark2580/gtav/mp_apa_hi_garage/garage_stuff/engine_hoist_02a.mdl"

function ENT:Initialize()
	local data = DarkRP.Stations[self:GetClass()]
	local model = self:GetModel()

	if not model or model == "" then
		self:SetModel(data and data.model or DEFAULT_MODEL)
	end

	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)
	self:SetUseType(SIMPLE_USE)

	local phys = self:GetPhysicsObject()

	if IsValid(phys) then
		phys:Wake()
	end

	McINV.AttachScreen(self)
end

function ENT:Use(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return end
	if DarkRP.UseDelay(ply, 1) then return end

	McINV.UseRegister(self, ply, false)
end

function ENT:OnRemove()
	local screen = self:Getscreen()
	if IsValid(screen) then screen:Remove() end
end
