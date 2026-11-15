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
	Коробка: содержимое - self.inv, вместимость (кг) - Space, название в меню - StorageName
	Пакеты (spawned_bag, spawned_metalbag) наследуют коробку и задают своё
---------------------------------------------------------------------------]]
function ENT:Initialize()
	local model = self:GetModel()

	if not model or model == "" then
		self:SetModel("models/props_junk/cardboard_box003b.mdl")
	end

	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)
	self:SetUseType(SIMPLE_USE)

	local phys = self:GetPhysicsObject()

	if IsValid(phys) then
		phys:Wake()
	end

	-- вместимость и название можно задать до Spawn
	if self:GetSpace() <= 0 then self:SetSpace(15) end
	if self:GetStorageName() == "" then self:SetStorageName("Коробка") end

	self.inv = self.inv or McINV.NewInventory()
end

function ENT:Use(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return end
	if DarkRP.UseDelay(self, 1) then return end

	if McINV.Loot(self, ply, false) then
		self:EmitSound("physics/cardboard/cardboard_box_strain1.wav")
	end
end
