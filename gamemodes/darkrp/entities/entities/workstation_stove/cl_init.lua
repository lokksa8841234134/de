--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
include("shared.lua")
local power = Color(255,0,0)

function ENT:Draw()
	self:DrawModel()
	if self:GetPos():DistToSqr(LocalPlayer():GetPos()) > 100000 then return end

	if not self.crafting or self:GetModel() ~= "models/props_wasteland/kitchen_stove003a.mdl" then return end

	local CT = CurTime()

	render.SetMaterial(Material("sprites/light_glow02_add"))
	render.DrawSprite(self:LocalToWorld(Vector(15.2,-8.3,34.55)), 8, 8, power)

	if self.nextemitter and self.nextemitter > CT then return end

	self.nextemitter = CT + 0.1
	local Pos = self:LocalToWorld(Vector(14.46,0.47,29) + Vector(math.random(-1, 2),math.random(-5, 5), 0))

	self.emitter = self.emitter or ParticleEmitter(Pos, false)


	local particle = self.emitter:Add("particle/smokesprites_001" .. math.random(6), Pos)
	particle:SetVelocity(VectorRand())
	particle:SetDieTime(math.random(3, 9))
	particle:SetStartAlpha(55)
	particle:SetEndAlpha(0)
	particle:SetColor(255, 255, 255)
	particle:SetStartSize(math.random(0, 2))
	particle:SetEndSize(9)
	particle:SetRoll(math.Rand(0, 360))
	particle:SetAirResistance(120)
	particle:SetCollide(true)
	particle:SetBounce(0.01)
	particle:SetGravity(Vector(0,0,10))
end