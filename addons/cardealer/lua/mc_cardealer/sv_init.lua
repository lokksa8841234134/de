--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
--[[
	n.y.noire: шаг 15.4.3 - серверная часть автосалона (под клиент автора cl_init.lua).
	Всё общение - одно сообщение "McCD.Msg":
		клиент -> сервер: UInt(3) код действия
			0 список (Bool: true - страница продажи, false - гараж)
			1 покупка (String машина, Float цвет)
			2 продажа (UInt(32) номер, у донатных Bool: true - обмен на кредиты)
			3 тюнинг (Float номер, String вид, данные вида)
			4 выгнать из гаража (UInt(16) номер)
			5 убрать машину в гараж
		сервер -> клиент: String имя функции McCD (Garage, GarageUpdate) и её данные
	Покупки донатных машин, неон, номерные рамки и открытие обвесов - за кредиты Glac (¤),
	остальное - за деньги DarkRP, как показывает клиент.
]]

util.AddNetworkString("McCD.Msg")

local CFG = McCD.Config

local NPC_RANGE = 400 * 400
local BASE_SLOTS = 5
local UNLOCK_BG_PRICE = 750

McCD.Spawned = McCD.Spawned or {}

--[[ помощники ]]

local function notify(ply, msg, kind)
	DarkRP.notify(ply, kind or 1, 5, msg)
end

local function money(n)
	return DarkRP.formatMoney and DarkRP.formatMoney(n) or ("$" .. string.Comma(n))
end

local function credits(n)
	return "¤" .. string.Comma(n)
end

local function payMoney(ply, n)
	n = math.Round(tonumber(n) or 0)
	if n <= 0 then return true end

	if not ply:canAfford(n) then
		notify(ply, "Не хватает денег: нужно " .. money(n) .. ".")
		return false
	end

	ply:addMoney(-n)
	return true
end

local function payCredits(ply, n)
	n = math.Round(tonumber(n) or 0)
	if n <= 0 then return true end

	if not ply.TakeCredits or not ply:TakeCredits(n) then
		notify(ply, "Не хватает кредитов: нужно " .. credits(n) .. ".")
		return false
	end

	return true
end

local function nearDealer(ply)
	local pos = ply:GetPos()

	for _, ent in ipairs(ents.FindByClass("mcs_npc")) do
		if ent:GetPos():DistToSqr(pos) <= NPC_RANGE then return true end
	end

	return false
end

function McCD.MaxSlots(ply)
	local extra = MQS and MQS.GetDataStored and tonumber(MQS.GetDataStored(ply, "car_slots")) or 0
	return BASE_SLOTS + math.max(extra, 0)
end

function McCD.NewPlate()
	local used = {}

	for _, ply in ipairs(player.GetAll()) do
		for _, car in ipairs(ply.McCD_Cars or {}) do
			if car.uniqueid then used[car.uniqueid] = true end
		end
	end

	local plate

	for i = 1, 10 do
		plate = DarkRP.GenLPlate(tostring(math.random(1000, 9999)) .. i)
		if not used[plate] then break end
	end

	return plate
end

local function groupAllowed(ply, cfg)
	if not istable(cfg.grouprequirements) or table.IsEmpty(cfg.grouprequirements) then return true end

	local group = ply:GetUserGroup()

	for k, v in pairs(cfg.grouprequirements) do
		if v == group or (k == group and v == true) then return true end
	end

	return false
end

local function carIndex(ply, car)
	for i, c in ipairs(ply:LoadCars()) do
		if c == car then return i end
	end
end

--[[ отправка гаража ]]

function McCD.SendGarage(ply, sell)
	local cars = ply:LoadCars()

	-- на пустой список клиент молча ничего не открывает
	if #cars == 0 then
		notify(ply, "У вас нет машин.")
	end

	net.Start("McCD.Msg")
		net.WriteString("Garage")
		net.WriteTable(cars)
		net.WriteBool(sell and true or false)
	net.Send(ply)
end

function McCD.SendGarageUpdate(ply, index)
	net.Start("McCD.Msg")
		net.WriteString("GarageUpdate")
		net.WriteTable(ply:LoadCars())
		net.WriteFloat(index or 1)
	net.Send(ply)
end

--[[ выдача машины (покупка, кейсы и наборы Glac) ]]

-- возвращает запись и её номер (0 - машина ждёт загрузки гаража); nil - машины нет в sh_cars.lua
function McCD.AddCar(ply, class, color, extra)
	if not IsValid(ply) then return end

	local cfg = McCD.Cars[class]
	if not cfg then
		ErrorNoHalt("[McCD] AddCar: машины '" .. tostring(class) .. "' нет в sh_cars.lua\n")
		return
	end

	-- n.y.noire: гараж ещё не загрузился (набор Glac сразу после входа) - машина ждёт в очереди
	if not ply.McCD_Loaded then
		ply.McCD_Pending = ply.McCD_Pending or {}
		table.insert(ply.McCD_Pending, {class, color, extra})
		return {entity = class, name = cfg.name or class, pending = true}, 0
	end

	local palette = cfg.palette or CFG.CarColors
	local first = palette and palette[1]

	if not IsColor(color) then
		color = IsColor(first) and first or (istable(first) and IsColor(first[1]) and first[1]) or Color(255, 255, 255)
	end

	local car = {
		entity = class,
		uniqueid = McCD.NewPlate(),
		color = Color(color.r, color.g, color.b, color.a),
		skin = 0,
		bodygroups = istable(cfg.bodygroups) and table.Copy(cfg.bodygroups) or {},
		unlockedbg = cfg.unlockedbg or nil,
		radio = true,
	}

	if istable(extra) then
		for k, v in pairs(extra) do car[k] = v end
	end

	McCD.PrepareCar(car)

	local cars = ply:LoadCars()
	cars[#cars + 1] = car
	ply:SaveCars()

	return car, #cars
end

-- вызывается из McCD.ChopShop (sh_config.lua): машина сдана на разборку
function McCD.AddCarParameter(owner, dataId, params, ent)
	if not IsValid(owner) or not istable(params) then return end

	local cars = owner:LoadCars()
	local car = IsValid(ent) and ent.McCD_CarData or nil

	if not car or not carIndex(owner, car) then
		car = cars[dataId]
		if not car or (IsValid(ent) and ent.McCD_UniqueId and car.uniqueid ~= ent.McCD_UniqueId) then return end
	end

	for k, v in pairs(params) do car[k] = v end
	owner:SaveCars()
end

--[[ машина в мире ]]

function McCD.GetSpawned(ply, car)
	local list = McCD.Spawned[ply]
	if not list then return end

	for ent in pairs(list) do
		if IsValid(ent) and ent.McCD_CarData == car then return ent end
	end
end

local function trackSpawned(ply, ent)
	McCD.Spawned[ply] = McCD.Spawned[ply] or {}
	McCD.Spawned[ply][ent] = true
end

local function zoneFree(zone)
	for _, ent in ipairs(ents.FindInBox(zone[1], zone[2])) do
		if ent:IsPlayer() or ent:IsVehicle() or ent.IsSimfphyscar or IsValid(ent:GetPhysicsObject()) then
			return false
		end
	end

	return true
end

local function spawnCar(ply, class)
	local pos = ply:GetPos()
	local pads = ents.FindByClass("mcarspawn")

	table.sort(pads, function(a, b) return a:GetPos():DistToSqr(pos) < b:GetPos():DistToSqr(pos) end)

	for _, pad in ipairs(pads) do
		if not IsValid(pad:Occupied(nil, nil, true)) then
			local ent = pad:SpawnVehicle(class)
			if IsValid(ent) then return ent end
		end
	end

	if not simfphys or not isfunction(simfphys.SpawnVehicleSimple) then return end

	for _, zone in ipairs(CFG.SpawnZone or {}) do
		if not zoneFree(zone) then continue end

		local center = (zone[1] + zone[2]) / 2
		center.z = math.min(zone[1].z, zone[2].z) + 30

		local ent = simfphys.SpawnVehicleSimple(class, center, zone[3] or Angle(0, 0, 0))
		if IsValid(ent) then return ent end
	end
end

-- цвет, скин, обвесы, номер и тюнинг из записи гаража
function McCD.ApplyLook(ent, car)
	local cfg = McCD.Cars[car.entity] or {}

	if IsColor(car.color) then ent:SetColor(car.color) end
	ent:SetSkin(tonumber(car.skin) or 0)

	for id, val in pairs(car.bodygroups or {}) do
		ent:SetBodygroup(tonumber(id) or 0, tonumber(val) or 0)
	end

	for i = 0, #(ent:GetMaterials() or {}) do
		ent:SetSubMaterial(i, nil)
	end

	local pack = car.skin_pack and istable(cfg.skins_pack) and cfg.skins_pack[car.skin_pack]

	if istable(pack) then
		for idx, mat in pairs(pack) do
			ent:SetSubMaterial(tonumber(idx) or 0, mat)
		end
	end

	ent.McCD_UniqueId = car.uniqueid
	ent:SetNWString("McCD.UniqueId", car.uniqueid or "")

	local plate = CFG.Plates[tonumber(car.plates) or 0]
	ent.customplates = plate and plate[2] ~= "" and plate[2] or nil

	ent:SetNWBool("MccD.Radio", car.radio ~= false)
	ent:SetNW2Int("MccD.Neon", tonumber(car.neon) or 0)

	local horn = CFG.Horns[tonumber(car.horn) or 0]
	ent.snd_horn = horn and horn[2] or nil
end

-- параметры simfphys: ставятся после инициализации машины
function McCD.ApplyTune(ent, car)
	if not IsValid(ent) then return end

	if not ent.McCD_Base then
		ent.McCD_Base = {
			torque = ent.GetMaxTorque and ent:GetMaxTorque(),
			brake = ent.GetBrakePower and ent:GetBrakePower(),
		}
	end

	local base = ent.McCD_Base
	local nitro = math.Clamp(tonumber(car.nitro) or 0, 0, 3)
	local breaks = math.Clamp(tonumber(car.breaks) or 0, 0, 3)

	-- n.y.noire: прирост за уровень подобран нами (вопрос 1 в step15_4_3_cardealer_radio.md)
	if base.torque and ent.SetMaxTorque then ent:SetMaxTorque(base.torque * (1 + 0.08 * nitro)) end
	if base.brake and ent.SetBrakePower then ent:SetBrakePower(base.brake * (1 + 0.15 * breaks)) end

	local height = tonumber(car.suspension)

	if height then
		if ent.SetFrontSuspensionHeight then ent:SetFrontSuspensionHeight(height) end
		if ent.SetRearSuspensionHeight then ent:SetRearSuspensionHeight(height) end
	end

	local smoke = CFG.Smoke[tonumber(car.smoke) or 0]

	if smoke and IsColor(smoke[2]) and ent.SetTireSmokeColor then
		ent:SetTireSmokeColor(Vector(smoke[2].r, smoke[2].g, smoke[2].b) / 255)
	end

	if car.bpw and ent.SetBulletProofTires then ent:SetBulletProofTires(true) end
	if car.turbo and ent.SetTurboCharged then ent:SetTurboCharged(true) end
	if car.supercharger and ent.SetSuperCharged then ent:SetSuperCharged(true) end
end

function McCD.SpawnPlayerCar(ply, car)
	local ent = spawnCar(ply, car.entity)
	if not IsValid(ent) then return end

	ent.McCD_CarData = car
	ent.McCD_CarDataId = carIndex(ply, car)
	ent.Owner = ply
	ent.EntityOwner = ply

	if ent.CPPISetOwner then ent:CPPISetOwner(ply) end
	if ent.keysOwn then ent:keysOwn(ply) end
	if ent.SetSpawn_List then ent:SetSpawn_List(car.entity) end

	McCD.ApplyLook(ent, car)

	timer.Simple(1, function()
		McCD.ApplyTune(ent, car)
	end)

	trackSpawned(ply, ent)
	hook.Run("McCD.CarSpawned", ply, ent, car)

	return ent
end

function McCD.Despawn(ply, car)
	local list = McCD.Spawned[ply]
	if not list then return 0 end

	local n = 0

	for ent in pairs(list) do
		local match = not car or (IsValid(ent) and ent.McCD_CarData == car)

		if match and IsValid(ent) then
			ent:Remove()
			n = n + 1
		end

		if match or not IsValid(ent) then
			list[ent] = nil
		end
	end

	return n
end

--[[ действия ]]

local ops = {}

ops[0] = function(ply)
	McCD.SendGarage(ply, net.ReadBool())
end

ops[1] = function(ply)
	local class = net.ReadString()
	local colorid = math.floor(net.ReadFloat())
	local cfg = McCD.Cars[class]

	if not cfg or cfg.nobuy then return end

	if not groupAllowed(ply, cfg) then
		notify(ply, "Эта машина вам недоступна.")
		return
	end

	if #ply:LoadCars() >= McCD.MaxSlots(ply) then
		notify(ply, "В гараже нет места (" .. McCD.MaxSlots(ply) .. " машин).")
		return
	end

	local palette = cfg.palette or CFG.CarColors or {}
	local entry = palette[colorid] or palette[1]
	local color = IsColor(entry) and entry or (istable(entry) and entry[1]) or nil

	local price = tonumber(cfg.price) or 0

	if cfg.donate then
		price = math.Round(price * (CFG.Discount or 1))
		if not payCredits(ply, price) then return end
	else
		if not payMoney(ply, price) then return end
	end

	local car = McCD.AddCar(ply, class, color)

	if not car then
		if cfg.donate then ply:AddCredits(price) else ply:addMoney(price) end
		notify(ply, "Не удалось оформить покупку, деньги возвращены.")
		return
	end

	notify(ply, "Вы купили " .. car.name .. ". Машина в гараже.", 0)
	DarkRP.log("money", ply, nil, "купил машину " .. class .. " (" .. tostring(car.uniqueid) .. ")" .. (cfg.donate and " за кредиты" or ""), nil, price)
end

ops[2] = function(ply)
	local idx = net.ReadUInt(32)
	local cars = ply:LoadCars()
	local car = cars[idx]
	if not car then return end

	if car.nocase or (tonumber(car.wcitimer) or 0) > os.time() then
		notify(ply, "Эту машину сейчас нельзя продать.")
		return
	end

	local refund = tonumber(car.refundprice) or 0
	local text

	if car.donate then
		if net.ReadBool() then
			local n = math.Round(refund / 2)
			ply:AddCredits(n)
			text = credits(n)
		else
			local n = math.Round(refund * 150 / 2)
			ply:addMoney(n)
			text = money(n)
		end
	else
		ply:addMoney(refund)
		text = money(refund)
	end

	McCD.Despawn(ply, car)
	table.remove(cars, idx)
	ply:SaveCars()

	notify(ply, "Машина " .. tostring(car.name) .. " продана за " .. text .. ".", 0)
	DarkRP.log("money", ply, nil, "продал машину " .. tostring(car.entity) .. " (" .. tostring(car.uniqueid) .. ") за " .. text)

	McCD.SendGarage(ply, true)
end

--[[ тюнинг: каждый вид возвращает цену, валюту (true - кредиты), функцию применения и нужно ли обновить список ]]

local tune = {}

tune.color = function(ply, car, cfg)
	local v = CFG.TuneColors[net.ReadUInt(16)]
	if not v or not IsColor(v[1]) then return end

	return v[2] or CFG.CarColorPrice, false, function()
		car.color = Color(v[1].r, v[1].g, v[1].b, v[1].a)
	end
end

tune.skin = function(ply, car, cfg)
	local k = math.floor(net.ReadFloat())
	if cfg.noskin then return end
	if istable(cfg.allowed_skins) and not cfg.allowed_skins[k] then return end
	if k < 0 or k > 64 then return end

	return CFG.CarSkinPrice or 0, false, function()
		car.skin = k
	end
end

tune.skin_pack = function(ply, car, cfg)
	local k = net.ReadString()

	if k == "" then
		return 0, false, function() car.skin_pack = nil end
	end

	if not istable(cfg.skins_pack) or not cfg.skins_pack[k] then return end
	if not (MQS and MQS.GetSData and MQS.GetSData(ply, k)) then return end

	return 0, false, function()
		car.skin_pack = k
	end
end

tune.unlockgbs = function(ply, car, cfg)
	if car.unlockedbg then return end

	return UNLOCK_BG_PRICE, true, function()
		car.unlockedbg = true
	end
end

local function bodygroupBanned(cfg, ent, id, val)
	if istable(cfg.baned_bg) and cfg.baned_bg[id] then return true end
	if istable(cfg.baned_bgs) and istable(cfg.baned_bgs[id]) and cfg.baned_bgs[id][val] then return true end

	if istable(CFG.BannedBodyGroup) and IsValid(ent) then
		local name = ent:GetBodygroupName(id)
		if name and CFG.BannedBodyGroup[name] then return true end
	end

	return false
end

tune.bodygroups = function(ply, car, cfg)
	local done = net.ReadTable()
	local count = math.floor(net.ReadFloat())

	if not car.unlockedbg or not istable(done) then return end

	local ent = McCD.GetSpawned(ply, car)
	local clean = {}
	local changes = 0

	for id, val in pairs(done) do
		id, val = tonumber(id), tonumber(val)
		if not id or not val or id < 0 or id > 31 or val < 0 or val > 31 then continue end
		if bodygroupBanned(cfg, ent, id, val) then continue end

		clean[id] = val
		if (tonumber(car.bodygroups[id]) or 0) ~= val then changes = changes + 1 end
	end

	if changes == 0 then return end

	-- цена по фактическим изменениям, но не меньше показанной клиенту
	local price = math.max(changes, count) * (CFG.BodyGroupPrice or 950)

	return price, false, function()
		for id, val in pairs(clean) do car.bodygroups[id] = val end
	end
end

tune.nitro = function(ply, car, cfg)
	local k = math.floor(net.ReadFloat())
	if cfg.tuneblock or not CFG.Nitro[k] then return end

	return CFG.Nitro[k], false, function() car.nitro = k end
end

tune.breaks = function(ply, car, cfg)
	local k = math.floor(net.ReadFloat())
	if cfg.tuneblock or not CFG.Breaks[k] then return end

	return CFG.Breaks[k], false, function() car.breaks = k end
end

tune.suspension = function(ply, car, cfg)
	local v = CFG.Suspension[math.floor(net.ReadFloat())]
	if not v then return end

	return v[3] or CFG.SuspensionPrice, false, function() car.suspension = v[1] end
end

tune.horn = function(ply, car, cfg)
	local k = math.floor(net.ReadFloat())
	local v = CFG.Horns[k]
	if not v then return end

	return v[3] or 0, false, function() car.horn = k end
end

tune.smoke = function(ply, car, cfg)
	local k = math.floor(net.ReadFloat())
	if not CFG.Smoke[k] then return end

	return k == 0 and 0 or CFG.TireSmokePrice, false, function() car.smoke = k end
end

tune.neon = function(ply, car, cfg)
	local k = math.floor(net.ReadFloat())
	if cfg.tuneblock or not CFG.Neon[k] then return end

	return k == 0 and 0 or CFG.NeonPrice, true, function() car.neon = k end
end

tune.plate_gen = function(ply, car, cfg)
	if (tonumber(car.lpcd) or 0) > os.time() then
		notify(ply, "Номер можно сменить через " .. string.NiceTime(car.lpcd - os.time()) .. ".")
		return
	end

	return CFG.RandomPlate, false, function()
		car.uniqueid = McCD.NewPlate()
		car.lpcd = os.time() + (CFG.CoolDown or 21600)
	end, true
end

tune.plates = function(ply, car, cfg)
	local k = math.floor(net.ReadFloat())
	local v = CFG.Plates[k]
	if not v then return end

	return v[3] or 0, true, function() car.plates = k end
end

ops[3] = function(ply)
	local idx = math.floor(net.ReadFloat())
	local kind = net.ReadString()
	local car = ply:LoadCars()[idx]
	if not car or not tune[kind] then return end

	local cfg = McCD.Cars[car.entity]
	if not cfg then return end

	if (tonumber(car.wcitimer) or 0) > os.time() then
		notify(ply, "Машина сейчас недоступна.")
		return
	end

	local price, inCredits, apply, sendUpdate = tune[kind](ply, car, cfg)
	if not apply then return end

	if inCredits then
		if not payCredits(ply, price) then return end
	else
		if not payMoney(ply, price) then return end
	end

	apply()
	ply:SaveCars()

	local ent = McCD.GetSpawned(ply, car)

	if IsValid(ent) then
		McCD.ApplyLook(ent, car)
		McCD.ApplyTune(ent, car)
	end

	if sendUpdate then
		McCD.SendGarageUpdate(ply, idx)
	end

	DarkRP.log("money", ply, nil, "тюнинг " .. kind .. " для " .. tostring(car.uniqueid), nil, math.Round(tonumber(price) or 0))
end

ops[4] = function(ply)
	local idx = net.ReadUInt(16)
	local car = ply:LoadCars()[idx]
	if not car then return end

	if CFG.BlackListJobs and (CFG.BlackListJobs[ply:Team()] or table.HasValue(CFG.BlackListJobs, ply:Team())) then
		notify(ply, "На этой работе личную машину брать нельзя.")
		return
	end

	if (tonumber(car.wcitimer) or 0) > os.time() then
		notify(ply, "Машина ещё не вернулась: " .. string.NiceTime(car.wcitimer - os.time()) .. ".")
		return
	end

	if IsValid(McCD.GetSpawned(ply, car)) then
		notify(ply, "Эта машина уже выгнана.")
		return
	end

	-- в городе одна личная машина: предыдущая убирается в гараж
	McCD.Despawn(ply)

	local fee = McCD.GetSpawnFee(car)
	if not payMoney(ply, fee) then return end

	local ent = McCD.SpawnPlayerCar(ply, car)

	if not IsValid(ent) then
		ply:addMoney(fee)
		notify(ply, "Все места на парковке заняты, попробуйте позже.")
		return
	end

	notify(ply, "Машина выгнана за " .. money(fee) .. ". Номер: " .. tostring(car.uniqueid) .. ".", 0)
	DarkRP.log("money", ply, nil, "выгнал машину " .. tostring(car.entity) .. " (" .. tostring(car.uniqueid) .. ")", nil, fee)
end

ops[5] = function(ply)
	local n = 0

	for ent in pairs(McCD.Spawned[ply] or {}) do
		if IsValid(ent) and ent:GetPos():DistToSqr(ply:GetPos()) <= 2500 * 2500 then
			local driver = ent.GetDriver and ent:GetDriver()
			if IsValid(driver) and driver ~= ply then continue end

			ent:Remove()
			McCD.Spawned[ply][ent] = nil
			n = n + 1
		end
	end

	notify(ply, n > 0 and "Машина убрана в гараж." or "Рядом нет вашей машины.", n > 0 and 0 or 1)
end

net.Receive("McCD.Msg", function(len, ply)
	if not IsValid(ply) then return end
	if (ply.McCD_Next or 0) > CurTime() then return end
	ply.McCD_Next = CurTime() + 0.4

	local op = net.ReadUInt(3)
	if not ops[op] then return end

	if not ply.McCD_Loaded then
		notify(ply, "Гараж ещё загружается, попробуйте через минуту.")
		McCD.LoadPlayer(ply)
		return
	end

	if not ply:Alive() or not nearDealer(ply) then
		notify(ply, "Подойдите к продавцу.")
		return
	end

	ops[op](ply)
end)

-- машины, выданные до загрузки гаража
hook.Add("McCD.CarsLoaded", "McCD.Pending", function(ply)
	local pending = ply.McCD_Pending
	if not pending then return end

	ply.McCD_Pending = nil

	for _, p in ipairs(pending) do
		McCD.AddCar(ply, p[1], p[2], p[3])
	end
end)

-- n.y.noire: личная машина убирается при выходе владельца
hook.Add("PlayerDisconnected", "McCD.Despawn", function(ply)
	McCD.Despawn(ply)
	McCD.Spawned[ply] = nil
end)

hook.Add("EntityRemoved", "McCD.Spawned", function(ent)
	if not ent.McCD_CarData or not IsValid(ent.Owner) then return end

	local list = McCD.Spawned[ent.Owner]
	if list then list[ent] = nil end
end)
