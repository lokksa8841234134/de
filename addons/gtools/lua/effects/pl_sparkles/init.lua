--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
local cl = Color(255, 0, 0, 25)
local Blood = {
	"decals/blood2",
	"decals/blood7",
	"decals/blood3",
	"decals/blood8"
}

function EFFECT:Init(data)
	self.WeaponEnt = data:GetEntity()
	self.Attachment = data:GetAttachment()

	self.Position = data:GetOrigin()
	self.Forward = data:GetNormal()
	self.Angle = self.Forward:Angle()
	self.Right = self.Angle:Right()
	local emitter = ParticleEmitter(data:GetOrigin())

	for i = 1, 5 do
		local particle = emitter:Add(Blood[math.random(1, 4)], self.Position - self.Forward * 4, cl)
		particle:SetVelocity(10 * VectorRand() + 10 * VectorRand() + 10 * VectorRand())
		particle:SetGravity(Vector(0, 0, -500))
		particle:SetAirResistance(0)
		particle:SetDieTime(1)
		particle:SetStartSize(5)
		particle:SetEndSize(0)
		particle:SetStartLength(0)
		particle:SetEndLength(105)
		particle:SetRoll(math.Rand(180, 480))
		particle:SetRollDelta(math.Rand(-1, 1))
		particle:SetCollide(true)

		if i == 1 and math.random(3) == 3 then
			particle:SetCollideCallback(function()
				local tr = {}
				tr.start = particle:GetPos()
				tr.endpos = particle:GetPos() + particle:GetAngles():Forward() * 50
				tr.filter = particle
				tr = util.TraceLine(tr)
				util.Decal("Blood", tr.HitPos + tr.HitNormal, tr.HitPos - tr.HitNormal)
			end)
		end
	end

	emitter:Finish()
end

--end
function EFFECT:Think()
	return false
end

function EFFECT:Render()
end