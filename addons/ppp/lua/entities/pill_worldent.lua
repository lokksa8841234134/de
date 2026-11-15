--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
AddCSLuaFile()
ENT.Type = "anim"
ENT.PrintName = "Pill?"

function ENT:SetupDataTables()
	self:NetworkVar("String", 0, "PillForm")
end

if SERVER then
	function ENT:Initialize()
		self:SetModel("models/pills.mdl")
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_VPHYSICS)
		self:SetSolid(SOLID_VPHYSICS)
		local phys = self:GetPhysicsObject()

		if (phys:IsValid()) then
			phys:Wake()
		end

		self:SetUseType(SIMPLE_USE)

		if self.DarkRPItem then
			self:SetPillForm(self.DarkRPItem.pill)
		end
	end

	function ENT:Use(ply)
		ply:EmitSound("weapons/bugbait/bugbait_squeeze1.wav")
		pk_pills.apply(ply, self:GetPillForm())
		self:Remove()
	end

	function ENT:Think()
		if self:WaterLevel() > 0 then
			self:EmitSound("weapons/underwater_explode3.wav")
			self:Remove()
		end
	end
end

function ENT:Draw()
	self:DrawModel()
end