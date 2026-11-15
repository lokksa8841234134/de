--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	MCS (Mactavish's Simple NPCs) - сервер

	NPC из MCS.Spawns (sh_npcspawn.lua, npcs/*.lua) встают на карту при старте
	и после очистки карты: каждый, у кого в pos есть точка для текущей карты.
	NPC без точки (pos = {}) ставят другие: скупщика Дезза - звонок дилеру
	(MCS.CreateDiller), квестовых - MQS через MCS.SpawnNPC.

	Разговор открывает ENT:Use (entities/mcs_npc/shared.lua, код автора),
	реплики листает клиент (cl_menu.lua). На сервер приходят только:
	MCS.Dialogue - ответ с действием MCS.AddonList (function_sv) или CallBack
	реплики; MCS.Formater - реплика, которую считает сервер (скупщик, разборка
	машин); MCS.SrartAnimation - анимация и жесты NPC в разговоре;
	MCS.CloseMenu - конец разговора с NPC "по одному" (uselimit).

	Сервер не верит номерам из сообщения: игрок свободен и рядом с NPC (кроме
	NPC с ignore - таксофон, планшет), а реплика достижима из начала разговора
	по ответам. Условия показа ответов (ans[4]) клиентские и здесь не
	проверяются: каждое действие само проверяет, можно ли его выполнить.
---------------------------------------------------------------------------]]

util.AddNetworkString("MCS.OpenMenu")
util.AddNetworkString("MCS.CloseMenu")
util.AddNetworkString("MCS.Dialogue")
util.AddNetworkString("MCS.Formater")
util.AddNetworkString("MCS.SrartAnimation")
util.AddNetworkString("MCS.GetConfigData")
util.AddNetworkString("MCS.SaveConfig")

local NPC_CLASS = "mcs_npc"
local TALK_RANGE = 300 * 300			-- квадрат: дальше разговор не засчитывается (как у инвентаря NPC)
local DEALER = "dezz"					-- скупщик, которого вызывают по телефону
local DEALER_TIME = 300					-- сколько скупщик ждёт на точке, с (разговор продлевает, ENT:Use)
local THINK_DELAY = 0.5					-- проверка разговоров и поз NPC, с
local STUDIO_LOOPING = 0x0001			-- флаг зацикленной анимации (GetSequenceInfo().flags)
local PM_PATH = "models/cityrp/pm/normal/"	-- случайный горожанин (randompm), как пассажиры MQS

--[[---------------------------------------------------------------------------
	Поза NPC. sequence - имя или список имён: переходы (не зацикленные)
	играются по порядку, затем одна из зацикленных поз, случайная
---------------------------------------------------------------------------]]
local function idleOf(ent, sequence)
	local trans, loops = {}, {}

	for _, name in ipairs(istable(sequence) and sequence or {sequence}) do
		local id = isstring(name) and name ~= "" and ent:LookupSequence(name) or -1

		if id and id >= 0 then
			local info = ent:GetSequenceInfo(id)

			if info and bit.band(info.flags or 0, STUDIO_LOOPING) == 0 then
				trans[#trans + 1] = id
			else
				loops[#loops + 1] = id
			end
		end
	end

	-- позы нет в модели - обычная стойка
	if #trans == 0 and #loops == 0 then
		local id = ent:SelectWeightedSequence(ACT_IDLE)
		if id and id >= 0 then loops[1] = id end
	end

	return {trans = trans, loops = loops}
end

local function playStep(npc, step)
	local chain = npc.MCSChain
	local id = chain and chain[step]

	npc.MCSChainAt = nil
	if not id then return end

	npc:ResetSequence(id)
	npc:SetCycle(0)

	if chain[step + 1] then
		npc.MCSChainNext = step + 1
		npc.MCSChainAt = CurTime() + npc:SequenceDuration(id)
	end
end

-- поза по умолчанию: после спавна, разговора (ENT:Think, turntoplayer) и испуга
function MCS.PlayDefAnimation(npc)
	if not IsValid(npc) or npc.scared or not npc.MCSIdle then return end

	local chain = {}

	for i, id in ipairs(npc.MCSIdle.trans) do
		chain[i] = id
	end

	local loops = npc.MCSIdle.loops

	if #loops > 0 then
		chain[#chain + 1] = loops[math.random(#loops)]
	end

	npc.LastAnim = nil
	npc.MCSChain = chain
	playStep(npc, 1)
end

--[[---------------------------------------------------------------------------
	MCS.SpawnNPC(npct, uid, pos, ang) - поставить NPC (вызывает и MQS).
	npct - таблица из MCS.Spawns, uid - её ключ. Вернёт энтити или NULL
---------------------------------------------------------------------------]]
-- внешность: models - несколько вариантов (продавцы), берётся случайный
local function lookOf(npct)
	if istable(npct.models) and #npct.models > 0 then
		local look = npct.models[math.random(#npct.models)]
		if istable(look) then return look end
	end

	return npct
end

function MCS.SpawnNPC(npct, uid, pos, ang)
	if not istable(npct) or not isstring(uid) or not istable(MCS.Spawns[uid]) or not isvector(pos) then return NULL end

	local look = lookOf(npct)
	local model = look.model or npct.model
	local gender

	if npct.randompm then
		gender = math.random(2) == 1 and "male" or "female"
		model = PM_PATH .. gender .. "_0" .. (gender == "male" and math.random(9) or math.random(6)) .. ".mdl"
	end

	if not isstring(model) or model == "" then return NULL end

	local ent = ents.Create(NPC_CLASS)
	if not IsValid(ent) then return NULL end

	-- до Spawn: клиентский Initialize по UID берёт extras и ClModels
	ent:SetModel(model)
	ent:SetPos(pos)
	ent:SetAngles(isangle(ang) and ang or angle_zero)
	ent:SetUID(uid)
	ent:SetNamer(tostring(npct.name or ""))
	ent:SetInputLimit(npct.uselimit and true or false)

	if istable(npct.hasinv) then
		ent:SetSpace(tonumber(npct.hasinv[1]) or 0)
		ent:SetStorageName(tostring(npct.hasinv[2] or ""))
	end

	ent:Spawn()
	ent:Activate()

	-- NPC_STATE_SCRIPT: ИИ не перебивает позу своими анимациями
	ent:SetHullType(HULL_HUMAN)
	ent:SetHullSizeNormal()
	ent:SetNPCState(NPC_STATE_SCRIPT)
	ent:SetSolid(SOLID_BBOX)
	ent:SetMoveType(MOVETYPE_NONE)
	ent:SetUseType(SIMPLE_USE)

	ent:SetSkin(tonumber(look.skin or npct.skin) or 0)

	for k, v in pairs(istable(look.bgr) and look.bgr or istable(npct.bgr) and npct.bgr or {}) do
		ent:SetBodygroup(k, v)
	end

	for k, v in pairs(istable(look.submat) and look.submat or istable(npct.submat) and npct.submat or {}) do
		ent:SetSubMaterial(k, v)
	end

	if gender and MCR and MCR.SetMatID then
		local count = gender == "male" and 44 or 25

		MCR.SetMatID(ent, gender, "top", math.random(count))
		MCR.SetMatID(ent, gender, "pants", math.random(count))
	end

	if isnumber(npct.scale) and npct.scale ~= 1 then
		ent:SetModelScale(npct.scale)
	end

	if npct.noshadow then
		ent:DrawShadow(false)
	end

	-- extras - поля энтити, как у клиента (policeEvidnce, RDMContract)
	if istable(npct.extras) then
		for k, v in pairs(npct.extras) do
			ent[k] = v
		end
	end

	if istable(npct.hasinv) and McINV and McINV.NewInventory then
		ent.inv = McINV.NewInventory()
	end

	ent.checkpos = npct.checkpos and true or nil

	if npct.turntoplayer then
		ent.turntoplayer = true
		ent.DefAng = ent:GetAngles()
	end

	-- испуг вызывает полицию (Dispatcher.Call, аддон services). Без неё
	-- ENT:PingPlayer падает до таймера, и NPC остался бы испуганным навсегда
	if istable(npct.scare_anim) and istable(Dispatcher) and isfunction(Dispatcher.Call) then
		ent.canscare = true
	end

	local sequence = look.sequence or npct.sequence
	local last = istable(sequence) and sequence[#sequence] or sequence

	ent.MCSIdle = idleOf(ent, sequence)
	ent:SetDefAnimation(isstring(last) and last or "")
	MCS.PlayDefAnimation(ent)

	return ent
end

--[[---------------------------------------------------------------------------
	NPC на карте: при старте и после очистки карты.
	Инвентари NPC (склад улик, склад RDM) переживают очистку
---------------------------------------------------------------------------]]
local keptInv = {}

local function keepInventories()
	for _, ent in ipairs(ents.FindByClass(NPC_CLASS)) do
		if ent.MCSStatic and istable(ent.inv) then
			keptInv[ent:GetUID()] = ent.inv
		end
	end
end

function MCS.SpawnAll()
	keepInventories()

	for _, ent in ipairs(ents.FindByClass(NPC_CLASS)) do
		if ent.MCSStatic then ent:Remove() end
	end

	local map = string.lower(game.GetMap())
	local count = 0

	for uid, npct in pairs(MCS.Spawns) do
		local spot = istable(npct) and istable(npct.pos) and npct.pos[map]
		if not istable(spot) or not isvector(spot[1]) then continue end

		local ent = MCS.SpawnNPC(npct, uid, spot[1], spot[2])
		if not IsValid(ent) then continue end

		ent.MCSStatic = true

		if keptInv[uid] and ent.inv then
			ent.inv = keptInv[uid]
		end

		count = count + 1
	end

	keptInv = {}

	print("[MCS NPCs] NPC spawned: " .. count)
end

hook.Add("InitPostEntity", "MCS.Spawn", function()
	MCS.SpawnAll()
end)

hook.Add("PreCleanupMap", "MCS.Spawn", keepInventories)

hook.Add("PostCleanupMap", "MCS.Spawn", function()
	MCS.SpawnAll()
end)

--[[---------------------------------------------------------------------------
	MCS.CreateDiller(ply) - скупщик Дезз (действие "Dezz" после звонка дилеру).
	Один на сервер: ставится на случайную точку get_pos и ждёт 5 минут
---------------------------------------------------------------------------]]
function MCS.CreateDiller(ply)
	local npct = MCS.Spawns[DEALER]
	if not istable(npct) then return NULL end

	local ent = MCS.Dealler

	if not IsValid(ent) then
		local points = {}

		for _, v in ipairs(istable(npct.get_pos) and npct.get_pos or {}) do
			if istable(v) and isvector(v[1]) and util.IsInWorld(v[1]) then
				points[#points + 1] = v
			end
		end

		if #points == 0 then return NULL end

		local point = points[math.random(#points)]

		ent = MCS.SpawnNPC(npct, DEALER, point[1], point[2])
		if not IsValid(ent) then return NULL end

		MCS.Dealler = ent
	end

	ent.timer = math.max(ent.timer or 0, CurTime() + DEALER_TIME)

	if IsValid(ply) then
		DarkRP.log("crime", ply, nil, "назначил встречу скупщику")

		-- метка на телефоне - с серверной частью телефона (mc_phone)
		if McPhone and isfunction(McPhone.ToggleGPS) then
			McPhone.ToggleGPS(ply, npct.name, ent:GetPos())
		end
	end

	return ent
end

-- "Нужно встретиться" в разговоре с дилером: телефон шлёт пустой MCS.Dialogue
local function dealerCall(ply)
	if DarkRP.NetDelay(ply, 2) then return end
	if not ply:IsUnrestrained() or ply:getDarkRPVar("character") == nil then return end

	-- занят ли дилер, решает проверка телефона автора (mc_phone/sh_init.lua);
	-- ей нужны данные квестов игрока (MQSdata, сервер MQS)
	if not istable(ply.MQSdata) or not istable(ply.MQSdata.Stored) then return end

	local busy = McPhone and McPhone.ExtraNumbersFunc and McPhone.ExtraNumbersFunc.dealer
	if not isfunction(busy) or busy(ply) ~= false then return end

	-- только что звонил Деззу (сервер телефона: mc_phone/sv_init.lua)
	if not isfunction(McPhone.TakeExtraCall) or not McPhone.TakeExtraCall(ply, "9523877") then return end

	MCS.AddonList.Dezz.function_sv(ply)
end

--[[---------------------------------------------------------------------------
	Разговор: кто с кем говорит и какие реплики ему доступны
---------------------------------------------------------------------------]]
local function canTalk(ply, npc, npct)
	if not IsValid(ply) or not ply:IsPlayer() or ply:getDarkRPVar("character") == nil then return false end

	-- таксофон, планшет: разговор не у NPC, как и у клиента
	if npct.ignore then return ply:Alive() end

	if not ply:IsUnrestrained() then return false end

	return ply:GetPos():DistToSqr(npc:GetPos()) <= TALK_RANGE
end

-- конец разговора с NPC "по одному" (uselimit)
local function release(npc)
	local ply = npc.UsingPlayer

	npc.UsingPlayer = nil

	if IsValid(ply) and ply.MCSInUse == npc then
		ply.MCSInUse = nil
		ply.MCSFormat = nil
	end
end

-- ответы реплики: у реплики с Formater_SV - только присланные сервером
local function answersOf(ply, npc, npct, mid)
	local dialog = npct.dialogs[mid]
	if not istable(dialog) then return nil end

	if isfunction(dialog.Formater_SV) then
		local f = ply.MCSFormat

		return f and f.npc == npc and f.mid == mid and f.answers or nil
	end

	return istable(dialog.Answers) and dialog.Answers or nil
end

-- ссылки на реплики из ответов: номер, случайный из списка, openid действия
local function addLinks(queue, answers)
	if not istable(answers) then return end

	for _, ans in pairs(answers) do
		local link = istable(ans) and ans[2]

		if isnumber(link) then
			queue[#queue + 1] = link
		elseif istable(link) then
			for _, v in ipairs(link) do
				if isnumber(v) then queue[#queue + 1] = v end
			end

			if isnumber(link.openid) then queue[#queue + 1] = link.openid end
		end
	end
end

-- реплика квеста MQS "Talk to NPC" у этого NPC
local function questDialogs(ply, npc, npct, queue)
	if not MQS or not isfunction(MQS.HasQuest) or not istable(MQS.Quests) then return end

	local q = MQS.HasQuest(ply)
	local quest = q and MQS.Quests[q.quest]
	local obj = quest and istable(quest.objects) and quest.objects[MQS.GetNWdata(ply, "quest_objective")]

	if not istable(obj) or obj.type ~= "Talk to NPC" or obj.npc ~= npc:GetUID() then return end

	if istable(npct.quest_random) then
		for _, v in ipairs(npct.quest_random) do
			queue[#queue + 1] = v
		end
	else
		queue[#queue + 1] = obj.dialog
	end
end

-- начало разговора - как у клиента: квест, профессия (teams), random_dialog, 1
local function reachable(ply, npc, npct, mid)
	local dialogs = npct.dialogs
	local queue = {1}

	if istable(npct.teams) then queue[#queue + 1] = npct.teams[ply:Team()] end

	if istable(npct.random_dialog) then
		for _, v in ipairs(npct.random_dialog) do
			queue[#queue + 1] = v
		end
	end

	questDialogs(ply, npc, npct, queue)

	local seen = {}
	local i = 1

	while i <= #queue do
		local id = queue[i]
		i = i + 1

		if isnumber(id) and not seen[id] and istable(dialogs[id]) then
			if id == mid then return true end

			seen[id] = true
			addLinks(queue, dialogs[id].Answers)

			local f = ply.MCSFormat
			if f and f.npc == npc and f.mid == id then addLinks(queue, f.answers) end
		end
	end

	return false
end

-- реплика mid этого NPC доступна игроку прямо сейчас; вернёт таблицу NPC
local function talkCheck(ply, npc, mid)
	if not IsValid(npc) or npc:GetClass() ~= NPC_CLASS then return nil end

	local npct = MCS.Spawns[npc:GetUID()]
	if not istable(npct) or not istable(npct.dialogs) or not istable(npct.dialogs[mid]) then return nil end
	if not canTalk(ply, npc, npct) then return nil end
	if npc:GetInputLimit() and npc.UsingPlayer ~= ply then return nil end
	if not reachable(ply, npc, npct, mid) then return nil end

	ply.MCSTalk = npc

	return npct
end

-- NPC, с которым игрок говорит сейчас (для анимаций: в них нет энтити)
local function talkingTo(ply)
	local npc = ply.MCSInUse

	if not IsValid(npc) or npc.UsingPlayer ~= ply then
		npc = ply.MCSTalk
		if not IsValid(npc) or npc:GetClass() ~= NPC_CLASS or npc:GetInputLimit() then return nil end
	end

	local npct = MCS.Spawns[npc:GetUID()]
	if not istable(npct) or not canTalk(ply, npc, npct) then return nil end

	return npc, npct
end

-- анимации, которые клиент может попросить у NPC: Animation, Gestures и ans[5] его реплик
local animCache = {}

local function animList(uid, npct)
	if animCache[uid] then return animCache[uid] end

	local list = {}

	for _, dialog in pairs(istable(npct.dialogs) and npct.dialogs or {}) do
		if not istable(dialog) then continue end

		if isstring(dialog.Animation) then list[dialog.Animation] = true end

		for _, ges in pairs(istable(dialog.Gestures) and dialog.Gestures or {}) do
			if istable(ges) and isstring(ges[1]) then list[ges[1]] = true end
		end

		for _, ans in pairs(istable(dialog.Answers) and dialog.Answers or {}) do
			if istable(ans) and isstring(ans[5]) then list[ans[5]] = true end
		end
	end

	animCache[uid] = list

	return list
end

--[[---------------------------------------------------------------------------
	Ответ (клиент: UInt(15) реплика, UInt(15) ответ, Entity NPC).
	Ответ 0 - CallBack реплики. Реплика 0 без NPC - "Нужно встретиться" у дилера
---------------------------------------------------------------------------]]
net.Receive("MCS.Dialogue", function(_, ply)
	local mid = net.ReadUInt(15)
	local sid = net.ReadUInt(15)
	local npc = net.ReadEntity()

	if mid == 0 then
		if sid == 0 and not IsValid(npc) then dealerCall(ply) end
		return
	end

	if DarkRP.NetDelay(ply, 0.3) then return end

	local npct = talkCheck(ply, npc, mid)
	if not npct then return end

	local name, data

	if sid == 0 then
		-- CallBack: клиент шлёт его, не глядя на enabled
		local callback = npct.dialogs[mid].CallBack
		if not istable(callback) then return end

		name, data = callback.name, callback.data
	else
		local answers = answersOf(ply, npc, npct, mid)
		local ans = answers and answers[sid]
		if not istable(ans) then return end

		if istable(ans[2]) then
			name, data = ans[2].id, ans[2].data
		else
			name = ans[2]
		end

		if not isstring(name) or not MCS.AddonList[name] or not MCS.AddonList[name].enabled then return end
	end

	local addon = isstring(name) and MCS.AddonList[name]
	if not addon or not isfunction(addon.function_sv) then return end

	addon.function_sv(ply, npc, data)
end)

--[[---------------------------------------------------------------------------
	Реплика от сервера (клиент: UInt(15) реплика, Entity NPC).
	Ответ: String текст, String звук, Table ответы
---------------------------------------------------------------------------]]
net.Receive("MCS.Formater", function(_, ply)
	local mid = net.ReadUInt(15)
	local npc = net.ReadEntity()

	if DarkRP.NetDelay(ply, 0.5) then return end

	local npct = talkCheck(ply, npc, mid)
	if not npct or not isfunction(npct.dialogs[mid].Formater_SV) then return end

	local line, snd, answers = npct.dialogs[mid].Formater_SV(ply, npc)
	if not isstring(line) then return end

	if not istable(answers) or table.IsEmpty(answers) then
		answers = {{"...", "close"}}
	end

	ply.MCSFormat = {npc = npc, mid = mid, answers = answers}

	net.Start("MCS.Formater")
		net.WriteString(line)
		net.WriteString(isstring(snd) and snd or "")
		net.WriteTable(answers)
	net.Send(ply)
end)

--[[---------------------------------------------------------------------------
	Анимация NPC в разговоре (клиент: String имя, Bool жест)
---------------------------------------------------------------------------]]
net.Receive("MCS.SrartAnimation", function(_, ply)
	local name = net.ReadString()
	local gesture = net.ReadBool()

	-- жесты идут по ходу реплики, поза - при её открытии: счётчики у них
	-- раздельные (NetDelay считает по месту вызова), жест не съедает позу
	if gesture then
		if DarkRP.NetDelay(ply, 0.1) then return end
	elseif DarkRP.NetDelay(ply, 0.1) then
		return
	end

	local npc, npct = talkingTo(ply)
	if not npc or npc.scared or not animList(npc:GetUID(), npct)[name] then return end

	local id = npc:LookupSequence(name)
	if not id or id < 0 then return end

	if gesture then
		npc:AddGestureSequence(id, true)
		return
	end

	-- поза разговора; к позе по умолчанию NPC вернётся сам (MCS.Think)
	npc.MCSChainAt = nil
	npc:ResetSequence(id)
	npc:SetCycle(0)
	npc.LastAnim = CurTime()
end)

-- клиент закрыл разговор с NPC "по одному"
net.Receive("MCS.CloseMenu", function(_, ply)
	local npc = ply.MCSInUse

	if IsValid(npc) and npc.UsingPlayer == ply then
		release(npc)
	end

	ply.MCSInUse = nil
end)

--[[---------------------------------------------------------------------------
	Раз в полсекунды: NPC отпускает собеседника, который ушёл, умер, попал в
	наручники или сменил персонажа; после разговора и испуга - поза по умолчанию
---------------------------------------------------------------------------]]
timer.Create("MCS.Think", THINK_DELAY, 0, function()
	local CT = CurTime()

	for _, npc in ipairs(ents.FindByClass(NPC_CLASS)) do
		local ply = npc.UsingPlayer

		if ply ~= nil then
			local npct = MCS.Spawns[npc:GetUID()]

			if not IsValid(ply) or ply.MCSInUse ~= npc or not istable(npct) or not canTalk(ply, npc, npct) then
				release(npc)
			end
		end

		if npc.scared then continue end

		if npc.LastAnim then
			if not npc.UsingPlayer and not npc.turned and CT >= npc.LastAnim + npc:SequenceDuration() then
				MCS.PlayDefAnimation(npc)
			end
		elseif npc.MCSChainAt and CT >= npc.MCSChainAt then
			playStep(npc, npc.MCSChainNext)
		end
	end
end)

hook.Add("PlayerUse", "MCS.Talk", function(ply, ent)
	if IsValid(ent) and ent:GetClass() == NPC_CLASS then
		ply.MCSTalk = ent
	end
end)

hook.Add("EntityRemoved", "MCS.Release", function(ent)
	if ent.UsingPlayer and ent:GetClass() == NPC_CLASS then
		release(ent)
	end
end)

--[[---------------------------------------------------------------------------
	NPC не двигают физганом, тулганом и меню свойств. Суперадмину можно
---------------------------------------------------------------------------]]
local function protected(ply, ent)
	if IsValid(ent) and ent:GetClass() == NPC_CLASS and not (IsValid(ply) and ply:IsSuperAdmin()) then return false end
end

hook.Add("PhysgunPickup", "MCS.Protect", protected)
hook.Add("CanPlayerUnfreeze", "MCS.Protect", protected)
hook.Add("CanDrive", "MCS.Protect", protected)

hook.Add("CanProperty", "MCS.Protect", function(ply, property, ent)
	return protected(ply, ent)
end)

hook.Add("CanTool", "MCS.Protect", function(ply, tr)
	return protected(ply, tr and tr.Entity)
end)
