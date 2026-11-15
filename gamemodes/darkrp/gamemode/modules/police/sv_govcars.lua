--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	Служебный транспорт - сервер

	Станции выдачи - NPC police_station у стоянок: "NYPD", "FDNY" и
	"Городские службы" (GovCars.EntSpawns в police_station/shared.lua).
	Ставятся при загрузке карты rp_southside_noire (rp_southside) и после
	очистки, двигать и удалять их может только суперадмин.
	Машины - GovCars.Cars: тип станции (type), кому положена (teams), с
	какого ранга MRS (rank), экзамен (exam), личный допуск (exclus), сколько
	одновременно на сервере (max), аренда (price, иначе GovCars.Price).

	[E] по станции (police_station/init.lua) открывает меню
	(police_station/cl_init.lua): net GovCars, S->C, Entity станция,
	Entity своя служебная машина (или NULL). Меню отвечает C->S, String:
	  SpawnCar, String машина, Entity станция - арендовать;
	  Fill, Entity станция - заправить свою машину;
	  RemoveCar, Entity станция - убрать свою машину в гараж;
	  Tow - эвакуатор за GovCars.PriceTow, если машина далеко.
	Заправить и убрать можно машину, которая не дальше GovCars.DistToCar
	(квадрат расстояния) от станции - как проверяет меню.
	Одна служебная машина на игрока. Она убирается при смене профессии,
	если новой профессии не положена, при смене персонажа и выходе.

	Машины - simfphys (gmod_sent_vehicle_fphysics_base). В дампе нет
	серверной части simfphys (init.lua этой сущности, шаг 15): пока её
	нет, аренда отвечает "Служебные машины пока недоступны".
---------------------------------------------------------------------------]]

util.AddNetworkString("GovCars")

-- координаты GovCars - для этой карты (rp_southside - она же под другим именем)
local MAPS = {rp_southside_noire = true, rp_southside = true}
local USE_RANGE = 300 * 300
local SPAWN_CLEAR = 150 -- на месте выдачи никого: игроков, машин, пропов
local SPAWN_LIFT = Vector(0, 0, 25) -- как спавн simfphys: чуть выше точки
local CAR_CLASS = "gmod_sent_vehicle_fphysics_base"
local STATION = "police_station"

-- [машина] = {owner = игрок, id = машина из GovCars.Cars}
local govCars = {}
local warned = false

local function money(n)
	return (GAMEMODE.Config.currency or "$") .. string.Comma(n)
end

local function rankOf(ply)
	return tonumber(MRS.GetNWdata(ply, "Rank")) or 1
end

local function isStation(ent)
	return IsValid(ent) and ent:GetClass() == STATION
end

local function nearStation(ply, station)
	return isStation(station) and station:GetPos():DistToSqr(ply:GetPos()) <= USE_RANGE
end

local function carNearStation(car, station)
	return car:GetPos():DistToSqr(station:GetPos()) <= GovCars.DistToCar
end

-- кому открывается станция: профессии всех машин её типа
local function stationTeams(tp)
	local teams = {}

	for _, cfg in pairs(GovCars.Cars) do
		if cfg.type == tp then
			for t, ok in pairs(cfg.teams or {}) do
				if ok then teams[t] = true end
			end
		end
	end

	return teams
end

local function carName(id)
	local vehicle = list.Get("simfphys_vehicles")[id]

	return vehicle and vehicle.Name or id
end

--[[---------------------------------------------------------------------------
	Станции на карте
---------------------------------------------------------------------------]]
local function spawnStations()
	for _, ent in ipairs(ents.FindByClass(STATION)) do
		if ent.GovStatic then ent:Remove() end
	end

	if not MAPS[game.GetMap()] or not GovCars then return end

	for _, v in ipairs(GovCars.EntSpawns) do
		local ent = ents.Create(STATION)
		if not IsValid(ent) then return end

		-- тип нужен до Spawn: по нему Initialize выбирает модель
		ent:SetNameType(v.name)
		ent:SetType(v.type)
		ent:SetBlinker(v.effect or 0)
		ent:SetSpawnPoint(v.spawn_point or 1)
		ent:SetPos(v.pos)
		ent:SetAngles(v.ang)
		ent.GovStatic = true
		ent:Spawn()
	end
end

hook.Add("InitPostEntity", "DarkRP.GovCars", spawnStations)

hook.Add("PostCleanupMap", "DarkRP.GovCars", function()
	for car in pairs(govCars) do
		if not IsValid(car) then govCars[car] = nil end
	end

	spawnStations()
end)

local function protected(ply, ent)
	if IsValid(ent) and ent.GovStatic and not (IsValid(ply) and ply:IsSuperAdmin()) then return false end
end

hook.Add("PhysgunPickup", "DarkRP.GovCars", protected)
hook.Add("CanPlayerUnfreeze", "DarkRP.GovCars", protected)
hook.Add("CanDrive", "DarkRP.GovCars", protected)

hook.Add("CanProperty", "DarkRP.GovCars", function(ply, property, ent)
	return protected(ply, ent)
end)

hook.Add("CanTool", "DarkRP.GovCars", function(ply, tr)
	return protected(ply, tr and tr.Entity)
end)

--[[---------------------------------------------------------------------------
	Меню станции
---------------------------------------------------------------------------]]
function DarkRP.Police.OpenGovCars(ply, station)
	if not IsValid(ply) or not ply:IsPlayer() or not isStation(station) then return end
	if DarkRP.NetDelay(ply, 1) then return end
	if not ply:IsFreeman() or not nearStation(ply, station) then return end

	if not stationTeams(station:GetType())[ply:Team()] then
		return
	end

	net.Start("GovCars")
		net.WriteEntity(station)
		net.WriteEntity(IsValid(ply.GovCar) and ply.GovCar or NULL)
	net.Send(ply)
end

-- серверная часть simfphys: без неё машина не поедет (Initialize в init.lua)
local function simfphysReady()
	local stored = scripted_ents.GetStored(CAR_CLASS)
	local ok = simfphys ~= nil and isfunction(simfphys.SpawnVehicleSimple) and istable(stored) and istable(stored.t) and isfunction(stored.t.Initialize)

	if not ok and not warned then
		warned = true
		print("[GovCars] нет серверной части simfphys (" .. CAR_CLASS .. "/init.lua): служебные машины не выдаются")
	end

	return ok
end

local function spawnBlocked(pos)
	for _, ent in ipairs(ents.FindInSphere(pos, SPAWN_CLEAR)) do
		if ent:IsPlayer() then
			if ent:Alive() then return true end
		elseif ent:IsVehicle() or ent:GetClass() == CAR_CLASS or ent:GetClass() == "prop_physics" then
			return true
		end
	end

	return false
end

local function countCars(id)
	local n = 0

	for car, data in pairs(govCars) do
		if IsValid(car) and data.id == id then n = n + 1 end
	end

	return n
end

-- почему машину не выдать (nil - можно)
local function denied(ply, cfg, id)
	if not (cfg.teams and cfg.teams[ply:Team()]) then return "Эта машина не положена вашей должности" end
	if cfg.rank and rankOf(ply) < cfg.rank then return "Эта машина выдаётся с ранга " .. cfg.rank end
	if cfg.exclus and not cfg.exclus[ply:SteamID()] then return "Эта машина выдаётся только по личному разрешению" end

	if cfg.exam then
		local exam = MRS.GetSData(ply, cfg.exam)
		if not exam or exam == 0 then return "Сначала сдайте экзамен на служебный транспорт" end
	end

	if IsValid(ply.GovCar) then return "У вас уже есть служебная машина" end
	if cfg.max and countCars(id) >= cfg.max then return "Все такие машины уже на выезде" end
end

local function spawnCar(ply, id, station)
	local cfg = GovCars.Cars[id]
	if not cfg or not nearStation(ply, station) or cfg.type ~= station:GetType() then return end

	local why = denied(ply, cfg, id)

	if why then
		return
	end

	local price = tonumber(cfg.price or GovCars.Price) or 0

	if not ply:canAfford(price) then
		return
	end

	if not simfphysReady() then
		return
	end

	local vehicle = list.Get("simfphys_vehicles")[id]

	if not vehicle or not isstring(vehicle.Model) or not util.IsValidModel(vehicle.Model) then
		return
	end

	local spawn = GovCars.Spwans[station:GetSpawnPoint()]
	if not spawn then return end

	-- как предпросмотр в меню: точка выдачи + pos_extra (без высоты)
	local extra = isvector(cfg.pos_extra) and Vector(cfg.pos_extra.x, cfg.pos_extra.y, 0) or Vector(0, 0, 0)
	local pos = spawn[1] + extra

	if spawnBlocked(pos) then
		return
	end

	local car = simfphys.SpawnVehicleSimple(id, pos + SPAWN_LIFT + (isvector(vehicle.SpawnOffset) and vehicle.SpawnOffset or Vector(0, 0, 0)), spawn[2])

	if not IsValid(car) then
		return
	end

	if cfg.color then car:SetColor(cfg.color) end
	if cfg.skin then car:SetSkin(cfg.skin) end

	if istable(cfg.bodygroups) then
		for k, v in pairs(cfg.bodygroups) do
			car:SetBodygroup(k, v)
		end
	end

	-- IsECPDVeh - служебная машина для cardealer (не продаётся и т.п.)
	car.IsECPDVeh = true
	car.GovCarOwner = ply
	car.EntityOwner = ply
	if car.CPPISetOwner then car:CPPISetOwner(ply) end
	if car.keysOwn then car:keysOwn(ply) end

	govCars[car] = {owner = ply, id = id}
	ply.GovCar = car

	if price > 0 then ply:addMoney(-price) end

	DarkRP.log("police", ply, nil, "арендовал служебную машину " .. carName(id) .. " за " .. money(price))
end

local function fillCar(ply, station)
	local car = ply.GovCar
	if not IsValid(car) or not nearStation(ply, station) then return end

	if not carNearStation(car, station) then
		return
	end

	local max = car.GetMaxFuel and car:GetMaxFuel() or 60

	if car.SetFuel then
		car:SetFuel(max)
	else
		car:SetNW2Float("Fuel", max)
	end
end

local function storeCar(ply, station)
	local car = ply.GovCar
	if not IsValid(car) or not nearStation(ply, station) then return end

	if not carNearStation(car, station) then
		return
	end

	local name = carName(govCars[car] and govCars[car].id or "")

	car:Remove()
	DarkRP.log("police", ply, nil, "сдал служебную машину " .. name)
end

local function towCar(ply)
	local car = ply.GovCar
	if not IsValid(car) then return end

	local near = false

	for _, station in ipairs(ents.FindByClass(STATION)) do
		if nearStation(ply, station) then
			near = true
			break
		end
	end

	if not near then return end

	local price = tonumber(GovCars.PriceTow) or 0

	if not ply:canAfford(price) then
		return
	end

	local name = carName(govCars[car] and govCars[car].id or "")

	if price > 0 then ply:addMoney(-price) end
	car:Remove()

	DarkRP.log("police", ply, nil, "вызвал эвакуатор для служебной машины " .. name .. " за " .. money(price))
end

net.Receive("GovCars", function(_, ply)
	local action = net.ReadString()

	if not GovCars or DarkRP.NetDelay(ply, 1) then return end
	if not ply:IsFreeman() then return end

	if action == "SpawnCar" then
		local id = net.ReadString()
		spawnCar(ply, id, net.ReadEntity())
	elseif action == "Fill" then
		fillCar(ply, net.ReadEntity())
	elseif action == "RemoveCar" then
		storeCar(ply, net.ReadEntity())
	elseif action == "Tow" then
		towCar(ply)
	end
end)

--[[---------------------------------------------------------------------------
	Когда машина убирается сама
---------------------------------------------------------------------------]]
hook.Add("EntityRemoved", "DarkRP.GovCars", function(ent)
	local data = govCars[ent]
	if not data then return end

	govCars[ent] = nil

	if IsValid(data.owner) and data.owner.GovCar == ent then
		data.owner.GovCar = nil
	end
end)

hook.Add("OnPlayerChangedTeam", "DarkRP.GovCars", function(ply, _, new)
	local car = ply.GovCar
	if not IsValid(car) then return end

	local data = govCars[car]
	local cfg = data and GovCars.Cars[data.id]
	if cfg and cfg.teams and cfg.teams[new] then return end

	car:Remove()
end)

local function removeCar(ply)
	if IsValid(ply.GovCar) then ply.GovCar:Remove() end
end

hook.Add("PlayerDisconnected", "DarkRP.GovCars", removeCar)
hook.Add("MCR.CharacterReset", "DarkRP.GovCars", removeCar)
