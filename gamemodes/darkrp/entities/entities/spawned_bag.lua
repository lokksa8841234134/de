--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "spawned_storage"
ENT.PrintName = "Пакет"
ENT.Author = "Mactavish"
ENT.Spawnable = true
ENT.invCanStore = 0.01

if SERVER then
	function ENT:Initialize()
		self:SetModel("models/props_shops/prop_bakery_flourbag_01_a.mdl")
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_VPHYSICS)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
		local phys = self:GetPhysicsObject()
		phys:Wake()
		self:SetSpace(2)
		self:SetStorageName("Пакет")
		self.inv = {}
		self.inv[INV_WEAPON] = {}
		self.inv[INV_ENTITY] = {}
		self.inv[INV_AMMO] = {}
		self.inv[INV_FOOD] = {}
		self.inv[INV_JUNK] = {}
	end

	function ENT:Use(ply)
		if DarkRP.UseDelay(self, 2) then return end
		McINV.Loot(self, ply, false, true)
		self:EmitSound("physics/cardboard/cardboard_box_strain1.wav")
	end
end