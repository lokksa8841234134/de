--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_edit"
ENT.PrintName = "Gas?"
ENT.Author = "Mac"
ENT.Spawnable = true
ENT.AdminSpawnable = true

if SERVER then
	function ENT:Initialize()
		self:SetModel("models/props_junk/plasticbucket001a.mdl")
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_VPHYSICS)
		self:SetSolid(SOLID_VPHYSICS)
		local phys = self:GetPhysicsObject()
		phys:EnableMotion(false)

	end

	function ENT:Think()
		local CT = CurTime()
		if (not self.cuffed or self.cuffed < CT) then
			self.cuffed = CT + 2
			for _,ply in pairs(ents.FindInSphere(self:GetPos(), 600)) do
				if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() or ply:HasGodMode() or ply:GetMoveType() == MOVETYPE_NOCLIP then continue end
				ply:AddTempStat("cough", 35)
				ply:AddTempStat("shock", 25)
				local d = DamageInfo()
				d:SetDamage(35)
				d:SetAttacker(ply)
				d:SetDamageType(DMG_SLOWBURN)
				ply:TakeDamageInfo( d )
			end
		end
	end
	return
end

function ENT:Initialize()
	self.emitter = ParticleEmitter(self:GetPos() + Vector(0,0,45))

	pos = self:GetPos()

	for i = 1, 30 do
		local particle = self.emitter:Add("particle/particle_smokegrenade", pos + Vector(0,0,45))
		particle:SetVelocity(VectorRand() * 400)
		particle:SetDieTime(math.random(20,50))
		particle:SetStartAlpha(200)
		particle:SetEndAlpha(0)
		particle:SetColor(105, 255, 110)
		particle:SetStartSize(math.Rand(50, 70))
		particle:SetEndSize(math.Rand(130, 220))
		particle:SetRoll(math.Rand(0, 360))
		particle:SetRollDelta(math.Rand(-1, 1))
		particle:SetAirResistance(20)
		particle:SetCollide(true)
		particle:SetBounce(0.1)
		particle:SetGravity(VectorRand() * 100)
	end
end