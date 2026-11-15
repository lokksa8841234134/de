--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
include("shared.lua")

function ENT:Explode()
	if self.emitter then
		pos = self:GetPos()

		for i = 1, 30 do
			local particle = self.emitter:Add("particle/particle_smokegrenade", pos + Vector(0,0,45))
			particle:SetVelocity(VectorRand() * 400)
			particle:SetDieTime(math.random(20,50))
			particle:SetStartAlpha(200)
			particle:SetEndAlpha(0)
			particle:SetColor(100, 200, 255)
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
end