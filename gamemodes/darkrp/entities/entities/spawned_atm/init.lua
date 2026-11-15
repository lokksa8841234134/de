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
	Банкомат: E - меню (cl_init.lua, ENT:OpenMenu через UI-эффект atm_open):
	"Зарплатный счет" - снять накопленную зарплату (payday, server/sv_money.lua),
	"Штрафы" - свои штрафы и их оплата (slawer_mayor/modules/policemen/sv_tickets.lua).
	Ставит администратор (спавн-меню), стоит на месте: физика заморожена
---------------------------------------------------------------------------]]
local DEFAULT_MODEL = "models/props_downtown/atm.mdl"
local RANGE = 150 * 150

function ENT:Initialize()
	local model = self:GetModel()

	if not model or model == "" then
		self:SetModel(DEFAULT_MODEL)
	end

	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)
	self:SetUseType(SIMPLE_USE)

	local phys = self:GetPhysicsObject()

	if IsValid(phys) then
		phys:EnableMotion(false)
	end
end

function ENT:Use(ply)
	if not IsValid(ply) or not ply:IsPlayer() or not ply:IsFreeman() then return end
	if DarkRP.UseDelay(ply, 1) then return end

	DarkRP.UIEffect(ply, "atm_open", {idx = self:EntIndex()})
end

-- "Вывести средства": весь зарплатный счёт в кошелёк
Slawer.Mayor:NetReceive("GetSalary", function(ply, data)
	if not istable(data) or not IsValid(ply) or not ply:IsFreeman() then return end

	local atm = Entity(math.floor(tonumber(data.ent) or 0))
	if not IsValid(atm) or atm:GetClass() ~= "spawned_atm" or atm:GetPos():DistToSqr(ply:GetPos()) > RANGE then return end

	local payday = math.floor(tonumber(ply:getDarkRPVar("payday")) or 0)
	if payday <= 0 then return end

	ply:addPaydayMoney(-payday)
	ply:addMoney(payday)

	DarkRP.log("money", ply, nil, "снял зарплату в банкомате", nil, payday, atm)
end)
