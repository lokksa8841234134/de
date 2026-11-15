--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
--[[---------------------------------------------------------------------------
	Функции режима на сервере: вход и загрузка игрока, появление, экипировка,
	модель персонажа, смерть и возрождение, ограничения спавн-меню, эффекты HUD
---------------------------------------------------------------------------]]
util.AddNetworkString("DarkRP.PlayerLoaded")
util.AddNetworkString("DarkRP.Hud.Kill")
util.AddNetworkString("DarkRP.Hud.SelfHIT")
util.AddNetworkString("DarkRP.Hud.Suppression")
util.AddNetworkString("DarkRP.Hud.Suppress")
util.AddNetworkString("DrawProgressBar")
util.AddNetworkString("RemovePropgressBar")

local DEFAULT_MODEL = "models/player/group01/male_07.mdl"

-- Раннее возрождение (вторая половина ожидания, рассудок > 40): штраф рассудка
-- от EARLY_SPAWN_KARMA (сразу после половины) до EARLY_SPAWN_KARMA_MIN (под конец)
local EARLY_SPAWN_KARMA = 25
local EARLY_SPAWN_KARMA_MIN = 5
local EARLY_SPAWN_MIN_KARMA = 40

-- Убийство игрока из GM.KarmaTeam
local KILL_KARMA = -25

local function hasPerm(ply, perm)
	if ply:IsSuperAdmin() then return true end

	-- серверные данные sAdmin (sAdmin.playerData) появляются после загрузки модуля admin
	return sAdmin and sAdmin.playerData and sAdmin.hasPermission(ply, perm) and true or false
end

--[[---------------------------------------------------------------------------
	Вход на сервер
---------------------------------------------------------------------------]]
function GM:PlayerInitialSpawn(ply, transition)
	self.BaseClass.PlayerInitialSpawn(self, ply, transition)

	ply.DarkRPUnInitialized = true
	ply:SetTeam(0)

	ply:SetDarkRPVar("rpname", ply:SteamName())
	ply:SetDarkRPVar("job", team.GetName(0))
	ply:SetDarkRPVar("karma", 100)
	ply:SetDarkRPVar("voicedist", 2)

	DarkRP.LoadPlayerData(ply)
	DarkRP.log("other", ply, nil, "подключился к серверу")
end

-- клиент прогрузился и готов принимать данные (cl_init.lua, InitPostEntity)
net.Receive("DarkRP.PlayerLoaded", function(_, ply)
	if not IsValid(ply) or ply.DarkRPClientReady then return end
	ply.DarkRPClientReady = true

	if not ply.DarkRPUnInitialized then
		DarkRP.SendPlayerData(ply, "jobxp", ply.jobxp or {})
	end

	hook.Run("DarkRP.PlayerLoaded", ply)
end)

-- повторная загрузка, если запрос к БД завершился ошибкой
timer.Create("DarkRP.RetryLoad", 30, 0, function()
	if not DarkRP.DBReady then return end

	for _, ply in ipairs(player.GetHumans()) do
		if ply.DarkRPUnInitialized and not ply.DarkRPDataLoading then
			DarkRP.LoadPlayerData(ply)
		end
	end
end)

function GM:PlayerDisconnected(ply)
	self.BaseClass.PlayerDisconnected(self, ply)

	DarkRP.log("other", ply, nil, "отключился от сервера")
end

--[[---------------------------------------------------------------------------
	Появление
---------------------------------------------------------------------------]]
function GM:PlayerSpawn(ply, transition)
	player_manager.SetPlayerClass(ply, "player_DarkRP")

	ply:UnSpectate()
	ply:Extinguish()

	for i = 0, 2 do
		local vm = ply:GetViewModel(i)
		if IsValid(vm) then vm:Extinguish() end
	end

	player_manager.OnPlayerSpawn(ply, transition)
	player_manager.RunClass(ply, "Spawn")

	ply:SetWalkSpeed(self.Config.walkspeed)
	ply:SetRunSpeed(ply:isCP() and self.Config.runspeedcp or self.Config.runspeed)

	if not transition then
		hook.Call("PlayerLoadout", self, ply)
	end

	hook.Call("PlayerSetModel", self, ply)

	local job = DarkRP.Teams[ply:Team()]

	if job and job.PlayerSpawn then
		job.PlayerSpawn(ply)
		-- PlayerSpawn может вернуть игрока на стартовую профессию (мэр)
		job = DarkRP.Teams[ply:Team()]
	end

	-- emsspawned: игрока подняли на месте (ставит модуль медиков перед ply:Spawn()),
	-- арестованный появляется в камере (police/sv_arrest.lua)
	if not ply.emsspawned then
		if ply:getDarkRPVar("Arrested") and DarkRP.retrieveJailPos then
			ply:SetPos(DarkRP.retrieveJailPos(ply))
		elseif job and job.spawn_point and util.IsInWorld(job.spawn_point) then
			ply:SetPos(DarkRP.findEmptyPos(job.spawn_point, {ply}, 600, 30, Vector(0, 0, 70)))
		end
	end

	ply.emsspawned = nil
end

-- класс player_default не вызывается: он выдаёт стандартный пистолет
function GM:PlayerLoadout(ply)
	for _, class in ipairs(self.Config.DefaultWeapons or {}) do
		ply:Give(class)
	end

	local job = DarkRP.Teams[ply:Team()]

	for _, class in ipairs(job and job.weapons or {}) do
		local wep = ply:Give(class)
		if IsValid(wep) then wep.GivenByTeam = true end
	end

	if ply:HasWeapon("keys") then
		ply:SelectWeapon("keys")
	end
end

--[[---------------------------------------------------------------------------
	Модель: персонаж (MCR) + форма профессии (job.outfit)
	nojob - только внешность персонажа, без формы
---------------------------------------------------------------------------]]
function GM:PlayerSetModel(ply, job, teamId, nojob)
	teamId = teamId or ply:Team()
	job = job or DarkRP.Teams[teamId]

	local char = ply.characters and ply.characters[ply:getDarkRPVar("character")]

	if not char or not char.suit then
		local model = job and job.model
		if istable(model) then model = model[1] end

		ply:SetModel(isstring(model) and model or DEFAULT_MODEL)
		ply:SetupHands()
		McINV.InventorySize(ply)
		return
	end

	ply:SetMaterial("")
	ply:SetSubMaterial()
	ply.insuit = nil

	MCR.ApplySkinData(ply, char)

	-- размер карманов по тату; форма работы (outfit ниже) может задать свой
	McINV.InventorySize(ply)

	if job and job.outfit and not nojob then
		local model = ply:GetModel()
		local subs = {}

		for i = 0, 31 do
			subs[i] = ply:GetSubMaterial(i)
		end

		job.outfit(ply, char)

		-- форма сменила модель: сабматериалы одежды персонажа к ней не относятся
		if ply:GetModel() ~= model then
			for i = 0, 31 do
				if subs[i] ~= "" and ply:GetSubMaterial(i) == subs[i] then
					ply:SetSubMaterial(i, "")
				end
			end
		end
	end

	MCR.SetFaceMatID(ply, char.face or 1)
	MCR.SetEyeMatID(ply, char.eye or 1)
	ply:SetupHands()
end

--[[---------------------------------------------------------------------------
	Смерть и возрождение
	Время ожидания - DarkRP.DeathTime() (shared/workarounds.lua), как на экране смерти
---------------------------------------------------------------------------]]
function GM:PlayerDeath(ply, inflictor, attacker)
	local CT = CurTime()
	ply.DeathTime = CT
	ply.NextSpawnTime = CT + DarkRP.DeathTime()

	if IsValid(attacker) and attacker:IsVehicle() and IsValid(attacker:GetDriver()) then
		attacker = attacker:GetDriver()
	end

	local weapon = IsValid(inflictor) and inflictor:GetClass() or nil

	if IsValid(attacker) and attacker:IsPlayer() and attacker ~= ply then
		net.Start("DarkRP.Hud.Kill")
		net.Send(attacker)

		if self.KarmaTeam[ply:Team()] then
			attacker:addKarma(KILL_KARMA)
		end

		DarkRP.log("damage", attacker, ply, "убил", nil, weapon, ply)
		return
	end

	DarkRP.log("damage", ply, nil, "погиб", nil, IsValid(attacker) and attacker:GetClass() or weapon, ply)
end

function GM:PlayerDeathThink(ply)
	if not ply:IsBot() and not (ply:KeyPressed(IN_ATTACK) or ply:KeyPressed(IN_ATTACK2) or ply:KeyPressed(IN_JUMP)) then return end

	local CT = CurTime()

	if ply.NextSpawnTime and ply.NextSpawnTime > CT then
		if ply:IsBot() then return end

		local total = ply.NextSpawnTime - (ply.DeathTime or CT)
		local left = ply.NextSpawnTime - CT

		if total <= 0 or left > total * 0.5 then return end
		if (ply:getDarkRPVar("karma") or 0) <= EARLY_SPAWN_MIN_KARMA then return end

		local penalty = math.max(EARLY_SPAWN_KARMA_MIN, math.ceil(EARLY_SPAWN_KARMA * left / (total * 0.5)))
		ply:addKarma(-penalty)
		DarkRP.log("other", ply, nil, "возродился раньше срока", nil, "-" .. penalty .. " рассудка")
	end

	ply:Spawn()
end

-- нельзя уйти от задержания/наручников/бессознания через kill
function GM:CanPlayerSuicide(ply)
	if not ply:IsFreeman() then
		return false
	end

	return true
end

--[[---------------------------------------------------------------------------
	Ограничения песочницы
---------------------------------------------------------------------------]]
function GM:CanDrive(ply, ent)
	return false
end

-- включить noclip - только суперадмин (права sAdmin добавляет модуль admin), выключить можно всегда
function GM:PlayerNoClip(ply, on)
	if not on then return true end
	if not IsValid(ply) or ply:InVehicle() or not ply:Alive() then return false end

	return ply:IsSuperAdmin()
end

function GM:PlayerSpawnObject(ply, model, skin)
	if ply.DarkRPUnInitialized then return false end
	if not ply:IsSuperAdmin() and not ply:IsUnrestrained() then return false end

	return self.BaseClass.PlayerSpawnObject(self, ply, model, skin)
end

local allowedModels

local function normalizeModel(model)
	return string.lower(string.gsub(model, "\\", "/"))
end

local function isAllowedModel(model)
	if not allowedModels then
		allowedModels = {}

		for _, category in pairs(allowed_spawnlist or {}) do
			for _, item in pairs(category.contents or {}) do
				if item.type == "model" and isstring(item.model) then
					allowedModels[normalizeModel(item.model)] = true
				end
			end
		end
	end

	return allowedModels[normalizeModel(model)] == true
end

function GM:PlayerSpawnProp(ply, model)
	if not hasPerm(ply, "propspawn") and not (isstring(model) and isAllowedModel(model)) then
		return false
	end

	return self.BaseClass.PlayerSpawnProp(self, ply, model)
end

function GM:PlayerSpawnSENT(ply, class)
	if not hasPerm(ply, "propspawn") then return false end

	return self.BaseClass.PlayerSpawnSENT(self, ply, class)
end

function GM:PlayerSpawnRagdoll(ply, model)
	if not hasPerm(ply, "propspawn") then return false end

	return self.BaseClass.PlayerSpawnRagdoll(self, ply, model)
end

function GM:PlayerSpawnEffect(ply, model)
	if not hasPerm(ply, "propspawn") then return false end

	return self.BaseClass.PlayerSpawnEffect(self, ply, model)
end

function GM:PlayerSpawnSWEP(ply, class, info)
	if not ply:IsSuperAdmin() then return false end

	return self.BaseClass.PlayerSpawnSWEP(self, ply, class, info)
end

function GM:PlayerGiveSWEP(ply, class, info)
	return ply:IsSuperAdmin()
end

function GM:PlayerSpawnNPC(ply, npcType, weapon)
	if not ply:IsSuperAdmin() then return false end

	return self.BaseClass.PlayerSpawnNPC(self, ply, npcType, weapon)
end

function GM:PlayerSpawnVehicle(ply, model, class, info)
	if not ply:IsSuperAdmin() then return false end

	return self.BaseClass.PlayerSpawnVehicle(self, ply, model, class, info)
end

-- F1-F4 обрабатывает клиент (PlayerBindPress)
function GM:ShowHelp(ply)
end

function GM:ShowTeam(ply)
end

function GM:ShowSpare1(ply)
end

function GM:ShowSpare2(ply)
end

--[[---------------------------------------------------------------------------
	Эффекты HUD: попадание, взрывы рядом, подавление огнём
---------------------------------------------------------------------------]]
local EXPLOSION_RADIUS_SQR = 600 * 600

hook.Add("PostEntityTakeDamage", "DarkRP.Hud.Damage", function(ent, dmginfo, took)
	if not took then return end

	local CT = CurTime()

	if ent:IsPlayer() and dmginfo:GetDamage() > 0 then
		ent.LastDamage = CT

		if not ent.DarkRPSelfHitCD or ent.DarkRPSelfHitCD <= CT then
			ent.DarkRPSelfHitCD = CT + 0.1

			net.Start("DarkRP.Hud.SelfHIT", true)
			net.Send(ent)
		end
	end

	if not dmginfo:IsExplosionDamage() then return end

	local pos = dmginfo:GetDamagePosition()
	if pos:IsZero() then pos = ent:GetPos() end

	local targets = {}

	for _, ply in ipairs(player.GetAll()) do
		if not ply:Alive() or ply:GetPos():DistToSqr(pos) > EXPLOSION_RADIUS_SQR then continue end
		if ply.DarkRPSuppressionCD and ply.DarkRPSuppressionCD > CT then continue end

		ply.DarkRPSuppressionCD = CT + 0.5
		targets[#targets + 1] = ply
	end

	if #targets == 0 then return end

	net.Start("DarkRP.Hud.Suppression", true)
	net.Send(targets)
end)

-- та же проверка промаха, что и в client/hud.lua (DarkRP.Hud.Suppress), чтобы не слать лишнего
local function isSuppressed(ply, src, fireAng, dist)
	local origin = ply:GetPos()
	local myPos = origin + (ply:EyePos() - origin) / 2
	local distSqr = myPos:DistToSqr(src)

	if distSqr >= (dist + 256) ^ 2 then return false end

	local miss = (myPos - src):Angle() - fireAng
	miss:Normalize()
	local missSqr = miss.p ^ 2 + miss.y ^ 2

	return (missSqr <= 2025 and distSqr <= 90000) or (distSqr > 90000 and missSqr <= 8100 / (distSqr / 5625))
end

hook.Add("EntityFireBullets", "DarkRP.Hud.Suppress", function(ent, data)
	if not IsValid(ent) or not ent:IsPlayer() then return end
	if not isvector(data.Src) or not isvector(data.Dir) then return end

	local CT = CurTime()
	if ent.DarkRPSuppressCD and ent.DarkRPSuppressCD > CT then return end
	ent.DarkRPSuppressCD = CT + 0.1

	local src = data.Src
	local dir = data.Dir:GetNormalized()

	local tr = util.TraceLine({
		start = src,
		endpos = src + dir * (tonumber(data.Distance) or 56756),
		filter = ent,
		mask = MASK_SHOT,
	})

	local dist = math.floor(src:Distance(tr.HitPos))
	local fireAng = dir:Angle()
	local targets = {}

	for _, ply in ipairs(player.GetAll()) do
		if ply == ent or not ply:Alive() then continue end

		if isSuppressed(ply, src, fireAng, dist) then
			targets[#targets + 1] = ply
		end
	end

	if #targets == 0 then return end

	net.Start("DarkRP.Hud.Suppress", true)
		net.WriteEntity(ent)
		net.WriteVector(src)
		net.WriteAngle(fireAng)
		net.WriteInt(dist, 32)
	net.Send(targets)
end)
