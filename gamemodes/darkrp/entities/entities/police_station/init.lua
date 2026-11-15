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
	Станция служебного транспорта - сервер

	NPC у стоянки: [E] открывает меню аренды (police/sv_govcars.lua).
	Расставляет станции police/sv_govcars.lua (GovCars.EntSpawns), до Spawn
	задаются тип (police, medic, city), название, логотип и точка выдачи.
	Модель - сотрудник своей службы, поза как у NPC арсенала (MCS).
---------------------------------------------------------------------------]]

local MODELS = {
	police = "models/cityrp/pm/nypd/male_02.mdl",
	medic = "models/cityrp/pm/normal/male_06.mdl",
	city = "models/cityrp/pm/normal/male_02.mdl",
}

function ENT:Initialize()
	self:SetModel(MODELS[self:GetType()] or MODELS.police)
	self:SetSolid(SOLID_BBOX)
	self:SetCollisionBounds(Vector(-16, -16, 0), Vector(16, 16, 72))
	self:SetMoveType(MOVETYPE_NONE)
	self:SetUseType(SIMPLE_USE)

	local seq = self:LookupSequence("menu_combine")
	if not seq or seq < 0 then seq = self:LookupSequence("idle_all_01") end
	if seq and seq >= 0 then self:ResetSequence(seq) end
end

-- анимация позы (AutomaticFrameAdvance в shared.lua)
function ENT:Think()
	self:NextThink(CurTime())

	return true
end

function ENT:Use(activator)
	if not IsValid(activator) or not activator:IsPlayer() then return end

	DarkRP.Police.OpenGovCars(activator, self)
end
