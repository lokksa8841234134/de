--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
AddCSLuaFile()
ENT.Type = "anim"
ENT.PrintName = "Barnacle Tongue"
ENT.units = {
	[1] = Vector(12,-332,0),
	[2] = Vector(12,-225,0),
	[3] = Vector(12,-112,0),
	[4] = Vector(12,0,0),
	[5] = Vector(12,112,0),
	[6] = Vector(12,225,0),
	[7] = Vector(12,332,0),
}

function ENT:Initialize()
	if SERVER then
		self:SetModel("models/hunter/plates/plate3x16.mdl")
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_NONE)
		self:SetNoDraw(true)
	end
end

if CLIENT then return end

function ENT:Use(ply)
	if DarkRP.UseDelay(ply, 2) then return end

	local sp = ply:GetEyeTrace().HitPos
	local found

	for id, unit in ipairs(self.units) do
		if sp and not DarkRP.InRangeVector(sp, self:LocalToWorld(unit), 50) then continue end
		found = id
	end

	if not found then return end

	-- ячейку и склад выдаёт работник складов (mc_simple_npcs, "Get Unit")
	if not ply.sunitkey or ply.sunitkey ~= found or ply.sunit ~= self then return end

	ply:EmitSound("doors/door_metal_gate_move1.wav")
	DarkRP.ForceAnimation(ply, "pickup", 1.5)

	-- хранилище закроется, если отойти от места, где его открыли
	local pos = ply:GetPos()

	timer.Simple(1, function()
		if not IsValid(ply) or not IsValid(self) then return end
		ply:EmitSound("doors/door_metal_gate_close1.wav")
		McINV.OpenBank(ply, false, self, pos)
	end)
end