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
	Ящик (станция): ставится оружием установки из посылки, Inventory.Pack - обратно в посылку
	содержимое - self.inv, вместимость (кг) - Space
---------------------------------------------------------------------------]]
function ENT:Initialize()
	local model = self:GetModel()

	if not model or model == "" then
		self:SetModel("models/props/cs_militia/footlocker01_closed.mdl")
	end

	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)
	self:SetUseType(SIMPLE_USE)

	local phys = self:GetPhysicsObject()

	if IsValid(phys) then
		phys:Wake()
	end

	if self:GetSpace() <= 0 then self:SetSpace(45) end
	if self:GetStorageName() == "" then self:SetStorageName("Ящик") end

	self.inv = self.inv or McINV.NewInventory()
end

function ENT:Use(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return end
	if DarkRP.UseDelay(self, 1) then return end

	if McINV.Loot(self, ply, false) then
		self:EmitSound("items/ammocrate_open.wav")
	end
end
