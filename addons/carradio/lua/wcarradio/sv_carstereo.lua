--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
--[[
	n.y.noire: шаг 15.4.3 - серверная часть магнитолы (под меню радио в simfphys/client/hud.lua).
	"wyozicr_cradio": [Entity радиоприёмника - только для стационарного], Int(8) значение, Bool громкость.
		Bool false: 1 - следующая станция, -1 - предыдущая, 0 - включить/выключить
		Bool true: громкость 0-100
	Станция - NW2Int "wcr_chan" (0 - выключено), громкость - NW2Float "radio_vol".
	Играет только машина с NWBool "MccD.Radio" (ставит автосалон и квесты MQS).
]]

util.AddNetworkString("wyozicr_cradio")

-- Int(8) + Bool = 9 бит; больше - впереди сущность стационарного радио
local BASE_BITS = 9
local STATION_RANGE = 120 * 120

local function isStationRadio(ent)
	return IsValid(ent) and ent:GetClass() == "spawned_junk" and ent.Geteclass and ent:Geteclass() == "radio"
end

local function playerCar(ply)
	local car = ply.GetSimfphys and ply:GetSimfphys()

	if not IsValid(car) then
		local veh = ply:GetVehicle()
		car = IsValid(veh) and veh:WCR_GetCarEntity() or nil
	end

	if not IsValid(car) then return end

	-- переключает только водитель
	local driver = car.GetDriver and car:GetDriver()
	if IsValid(driver) and driver ~= ply then return end

	return car
end

function wyozicr.StationCount()
	return #(wyozicr.AllStations or {})
end

function wyozicr.StepChannel(ent, dir)
	local count = wyozicr.StationCount()
	if count == 0 then return end

	local chan = ent:WCR_GetChannel()

	if dir == 0 then
		if chan > 0 then
			ent.WCR_LastChan = chan
			ent:WCR_SetChannel(0)
		else
			ent:WCR_SetChannel(math.Clamp(ent.WCR_LastChan or 1, 1, count))
		end

		return
	end

	if chan == 0 then chan = ent.WCR_LastChan or (dir > 0 and 0 or 1) end

	chan = (chan - 1 + dir) % count + 1
	ent.WCR_LastChan = chan
	ent:WCR_SetChannel(chan)
end

net.Receive("wyozicr_cradio", function(len, ply)
	if not IsValid(ply) or not ply:Alive() then return end
	if (ply.WCR_Next or 0) > CurTime() then return end
	ply.WCR_Next = CurTime() + 0.15

	local station
	if len > BASE_BITS then station = net.ReadEntity() end

	local val = net.ReadInt(8)
	local isVolume = net.ReadBool()
	local ent

	if station ~= nil then
		if not isStationRadio(station) or station:GetPos():DistToSqr(ply:GetPos()) > STATION_RANGE then return end

		-- стационарному радио клиент тоже проверяет "MccD.Radio"
		if not station:GetNWBool("MccD.Radio") then station:SetNWBool("MccD.Radio", true) end
		ent = station
	else
		ent = playerCar(ply)
		if not IsValid(ent) or not ent:WCR_HasRadioCapability() then return end
	end

	if isVolume then
		ent:SetNW2Float("radio_vol", math.Clamp(val, 0, 100) / 100)
	else
		wyozicr.StepChannel(ent, math.Clamp(val, -1, 1))
	end
end)

-- магнитолу сняли (разборка у Рамона и т.п.) - радио замолкает
timer.Create("wyozicr.NoRadioOff", 2, 0, function()
	for _, ent in ipairs(ents.FindByClass("gmod_sent_vehicle_fphysics_base")) do
		if IsValid(ent) and ent:WCR_GetChannel() > 0 and not ent:WCR_HasRadioCapability() then
			ent:WCR_SetChannel(0)
		end
	end
end)
