--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
--[[
	n.y.noire: шаг 15.4.3 - хранение личного гаража.
	Таблица mccd_cars(uid, data): одна строка на игрока, data - JSON-список машин.
	В базе лежит только то, что купил игрок (класс, номер, цвет, скин, обвесы, тюнинг, флаги).
	Название, цена, донатность и настройки гаража берутся из sh_cars.lua при каждой загрузке,
	поэтому смена цен в конфиге сразу видна у всех.
	Машины, которых больше нет в конфиге, не показываются, но и не теряются:
	они сохраняются обратно без изменений (вернутся, если класс добавят снова).
]]

local pmeta = FindMetaTable("Player")

McCD.DBReady = McCD.DBReady or false

-- поля из McCD.Cars, которые нужны клиенту в списке гаража; в базу не пишутся
McCD.SyncFields = {
	"name", "donate", "nocase", "noskin", "allowed_skins", "baned_bg", "baned_bgs",
	"tuneblock", "cantune", "garage_vect", "garage_angle", "garage_zoom", "fweels",
}

local noSave = {originalprice = true, refundprice = true, pending = true}
for _, f in ipairs(McCD.SyncFields) do noSave[f] = true end

local function dbError(what)
	return function(err)
		ErrorNoHalt("[McCD] " .. what .. ": " .. tostring(err) .. "\n")
	end
end

-- дополняет запись данными конфига; false - класса больше нет (запись не трогается)
function McCD.PrepareCar(car)
	local cfg = istable(car) and McCD.Cars[car.entity]
	if not cfg then return false end

	for _, f in ipairs(McCD.SyncFields) do
		car[f] = cfg[f]
	end

	car.name = car.name or car.entity

	local c = car.color
	car.color = istable(c) and Color(tonumber(c.r) or 255, tonumber(c.g) or 255, tonumber(c.b) or 255, tonumber(c.a) or 255) or Color(255, 255, 255)

	car.skin = tonumber(car.skin) or 0

	-- JSON превращает ключи в строки - возвращаем числа
	local bg = {}

	for k, v in pairs(istable(car.bodygroups) and car.bodygroups or {}) do
		local id = tonumber(k)
		if id then bg[id] = tonumber(v) or 0 end
	end

	car.bodygroups = bg
	car.originalprice = tonumber(cfg.price) or 0
	car.refundprice = math.Round(car.originalprice * (McCD.Config.RefundPercentage or 70) / 100)

	if car.radio == nil then car.radio = true end

	return true
end

local function serialize(car)
	local out = {}

	for k, v in pairs(car) do
		if not noSave[k] then out[k] = v end
	end

	if IsColor(car.color) then
		out.color = {r = car.color.r, g = car.color.g, b = car.color.b, a = car.color.a}
	end

	return out
end

function pmeta:LoadCars()
	return self.McCD_Cars or {}
end

function pmeta:SaveCars()
	if not self.McCD_Loaded or not McCD.DBReady then return end

	local id = DarkRP.GetPlayerUID(self)
	if not id then return end

	local list = {}

	for _, car in ipairs(self.McCD_Cars or {}) do
		list[#list + 1] = serialize(car)
	end

	for _, raw in ipairs(self.McCD_Lost or {}) do
		list[#list + 1] = raw
	end

	MySQLite.query("REPLACE INTO mccd_cars(uid, data) VALUES(" .. id .. ", " .. MySQLite.SQLStr(util.TableToJSON(list)) .. ")", nil, dbError("гараж не сохранён (" .. id .. ")"))
end

local function finish(ply, cars, lost)
	ply.McCD_Cars = cars
	ply.McCD_Lost = lost
	ply.McCD_Loaded = true

	hook.Run("McCD.CarsLoaded", ply, cars)
end

local function load(ply)
	if not IsValid(ply) or ply.McCD_Loaded or ply.McCD_Loading then return end

	-- у ботов гараж только в памяти
	if ply:IsBot() then
		finish(ply, {}, {})
		return
	end

	local id = DarkRP.GetPlayerUID(ply)
	if not id or not McCD.DBReady then return end

	ply.McCD_Loading = true

	MySQLite.query("SELECT data FROM mccd_cars WHERE uid = " .. id, function(rows)
		if not IsValid(ply) then return end

		ply.McCD_Loading = nil
		if ply.McCD_Loaded then return end

		local raw = rows and rows[1] and util.JSONToTable(rows[1].data or "") or {}
		local cars, lost = {}, {}

		for _, car in ipairs(raw) do
			if not istable(car) then continue end

			if McCD.PrepareCar(car) then
				cars[#cars + 1] = car
			else
				lost[#lost + 1] = car
			end
		end

		finish(ply, cars, lost)
	end, function(err)
		if IsValid(ply) then ply.McCD_Loading = nil end
		dbError("гараж не загружен (" .. id .. ")")(err)
	end)
end

McCD.LoadPlayer = load

local function createTable()
	MySQLite.query("CREATE TABLE IF NOT EXISTS mccd_cars(uid BIGINT NOT NULL PRIMARY KEY, data TEXT NOT NULL)", function()
		McCD.DBReady = true

		for _, ply in ipairs(player.GetAll()) do load(ply) end
	end, dbError("таблица mccd_cars"))
end

hook.Add("DatabaseInitialized", "McCD.DB", createTable)

-- автосалон грузится на PostGamemodeLoaded: база могла уже подняться
if DarkRP.DBReady then createTable() end

hook.Add("PlayerInitialSpawn", "McCD.DB", load)
