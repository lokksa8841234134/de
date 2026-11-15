--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	Компьютеры участка (slawer_mayor_computer) - сервер

	В дампе нет расстановки компьютеров: PermaProps (gtools) хранит пропы
	в sv.db сервера, а её в дампе нет. Мониторы pd_deskscreen в участке -
	клиентские пропы (a_config_gmodla/lua/clprops/day_preset1.lua): на их
	места и ставятся компьютеры. Сами они не рисуются (монитор уже рисует
	клиентский проп), но [E] по монитору открывает компьютер.
	Создаются при загрузке карты и после очистки (PostCleanupMap),
	двигать и удалять их может только суперадмин.
	Slawer.Mayor:PoliceAtComputer(ply) - может ли полицейский сейчас
	пользоваться компьютером (вкладки "Задержанные", "Розыск", ордера)
---------------------------------------------------------------------------]]

local MODEL = "models/unioncity2/props_unioncity/pd_deskscreen.mdl"
local USE_RANGE = 250 * 250 -- квадрат: клиент закрывает компьютер дальше 200 юнитов

local POSITIONS = {
	rp_southside_noire = {
		{Vector(8289.96875, 8054.96875, 240), Angle(0, 180, 0)},
		{Vector(8607, 8056, 240.125), Angle(0, 180, 0)},
		{Vector(8210, 8678, 328), Angle(0, 90, 0)},
		{Vector(8704, 8680, 328), Angle(0, 90, 0)},
	},
}

-- rp_southside - та же карта под другим именем: у НПС mc_simple_npcs
-- для обоих имён одинаковые координаты
POSITIONS.rp_southside = POSITIONS.rp_southside_noire

local function spawnComputers()
	for _, ent in ipairs(ents.FindByClass("slawer_mayor_computer")) do
		if ent.SlawerStatic then ent:Remove() end
	end

	for _, v in ipairs(POSITIONS[game.GetMap()] or {}) do
		local ent = ents.Create("slawer_mayor_computer")
		if not IsValid(ent) then return end

		ent:SetModel(MODEL)
		ent:SetPos(v[1])
		ent:SetAngles(v[2])
		ent.SlawerStatic = true
		ent:Spawn()
		ent:SetNoDraw(true)
	end
end

-- полицейский живой, не в наручниках, не арестован и рядом с компьютером
function Slawer.Mayor:PoliceAtComputer(ply)
	if not IsValid(ply) or not ply:IsPlayer() or not ply:isCP() or not ply:IsFreeman() then return false end

	local pos = ply:GetPos()

	for _, ent in ipairs(ents.FindByClass("slawer_mayor_computer")) do
		if ent:GetPos():DistToSqr(pos) <= USE_RANGE then return true end
	end

	return false
end

hook.Add("InitPostEntity", "Slawer.Mayor.Computers", spawnComputers)
hook.Add("PostCleanupMap", "Slawer.Mayor.Computers", spawnComputers)

local function protected(ply, ent)
	if IsValid(ent) and ent.SlawerStatic and not (IsValid(ply) and ply:IsSuperAdmin()) then return false end
end

hook.Add("PhysgunPickup", "Slawer.Mayor.Computers", protected)
hook.Add("CanPlayerUnfreeze", "Slawer.Mayor.Computers", protected)
hook.Add("CanDrive", "Slawer.Mayor.Computers", protected)

hook.Add("CanProperty", "Slawer.Mayor.Computers", function(ply, property, ent)
	return protected(ply, ent)
end)

hook.Add("CanTool", "Slawer.Mayor.Computers", function(ply, tr)
	return protected(ply, tr and tr.Entity)
end)
