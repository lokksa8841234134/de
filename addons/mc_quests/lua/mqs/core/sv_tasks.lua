--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	MQS (квесты) - сервер, часть 2: ход квеста

	MQS.StartTask(квест, игрок[, npc, force]) - начать (проверки -
	  MQS.CanStartTask в sh_util.lua); MQS.UpdateObjective(игрок[, задача]) -
	  следующая задача или переход к задаче с номером; MQS.FailTask(игрок[,
	  причина, тихо]) - провал; MQS.CompleteTask(игрок) - выполнить сейчас.

	Задачи квеста (quest.objects) идут по порядку. В начале задачи
	выполняются её события (MQS.Events, sh_init.lua), потом сервер раз в
	0.25 с проверяет её условие. За последней задачей квест выполнен
	(награда quest.reward); у квеста с повтором (looped) задачи идут
	заново, пока не кончится время (do_time) или игрок не остановит (P).
	Что квест поставил (машина, предметы, NPC, сцены, оружие, профессия,
	точка возрождения), в конце убирается.

	Старт: net MQS.StartTask (меню NPC, MCS, телефон, контракты),
	mqs_start (вступление, эпизоды F4, кнопка в редакторе); mqs_stop - отказ.
	Хуки: MQS.TaskStarted (игрок, квест, номер), MQS.ObjectiveChanged
	(игрок, квест, задача), MQS.TaskCompleted (игрок, квест),
	MQS.TaskFailed (игрок, квест, причина).
---------------------------------------------------------------------------]]

local THINK = 0.25					-- проверка задач, с
local POINT_DIST = 350				-- "Move to point" и точки "Move to any point" без радиуса
local LEAVE_DIST = 1000				-- "Leave area" без радиуса
local STOP_SPEED = 30				-- "машина должна остановиться": быстрее - ещё едет, юн./с
local TALK_DIST = 150				-- "Talk to NPC" с автостартом: разговор сам, ближе этого
local NPC_DIST = 250				-- старт квеста у NPC: игрок не дальше
local MAX_JUMPS = 64				-- переходов между задачами подряд: больше - квест зациклен
local UNDERGROUND = -4500			-- ниже - интерьеры под картой (как у клиента)
local PENALTY_JAIL = 600			-- "Kill Penalty" arrest: срок, с
local EDIT_REASON = "Задание изменено администратором"

-- задачи, где квестовую машину надо вести самому (как у клиента, cl_hud.lua)
local VEHICLE_TASKS = {
	["Move to point"] = true,
	["Leave area"] = true,
	["Leave area LP"] = true,
	["Wait time"] = true
}

-- active_quest первым: клиент перестаёт рисовать квест раньше, чем пропадёт остальное
local END_KEYS = {"active_quest", "active_questid", "quest_objective", "do_time", "loops"}
local SELF_KEYS = {"quest_wait", "quest_ent", "quest_colected", "targets"}

MQS.TaskID = MQS.TaskID or 0
MQS.TaskState = MQS.TaskState or {}

local state = MQS.TaskState
local spam = MQS.NetSpam
local depth, jumps = 0, 0
local setObjective

--[[---------------------------------------------------------------------------
	Мелочи
---------------------------------------------------------------------------]]
local function phrase(id)
	return MSD.GetPhrase(id)
end

local function setPublic(ply, id, value)
	if value == false then value = nil end
	if ply.MQSdata and ply.MQSdata[id] == value then return end

	MQS.SetNWdata(ply, id, value)
end

local function setSelf(ply, id, value)
	if value == false then value = nil end
	if ply.MQSdata_self and ply.MQSdata_self[id] == value then return end

	MQS.SetSelfNWdata(ply, id, value)
end

-- текущий квест игрока: номер, запись MQS.ActiveTask, квест
local function current(ply)
	if not IsValid(ply) then return end

	local q = MQS.HasQuest(ply)
	local id = q and tonumber(q.id)
	local task = id and MQS.ActiveTask[id]

	if not task or task.player ~= ply then return end

	return id, task, MQS.Quests[task.task]
end

MQS.GetPlayerTask = current

local function questOf(task)
	return task and MQS.Quests[task.task]
end

local function objectiveOf(quest, oid)
	local obj = quest and istable(quest.objects) and oid and quest.objects[oid]

	return istable(obj) and obj or nil
end

-- квест ещё идёт и задача та же (события могли его закончить или сменить задачу)
local function alive(id, ply, gen)
	local task = MQS.ActiveTask[id]
	local st = state[id]

	return task and task.player == ply and st and (gen == nil or st.gen == gen) and true or false
end

local function near(a, b, dist)
	return a:DistToSqr(b) <= dist * dist
end

local function radius(v, def)
	v = tonumber(v)

	return v and v > 0 and v or def
end

--[[---------------------------------------------------------------------------
	Задержки и награды
---------------------------------------------------------------------------]]
local function setCooldown(ply, tk, quest, secs)
	secs = tonumber(secs)
	if not secs or secs <= 0 then return end

	if quest.cooldow_perply then
		if not IsValid(ply) then return end

		local now = os.time()
		local cd = {}

		-- истёкшие задержки не храним
		for k, v in pairs(MQS.GetDataStored(ply, "CoolDown") or {}) do
			if tonumber(v) and tonumber(v) > now then cd[k] = v end
		end

		cd[tk] = now + secs
		MQS.SetNWStoredData(ply, "CoolDown", cd)

		return
	end

	for k, t in pairs(MQS.TaskQueue) do
		if not tonumber(t) or t <= CurTime() then MQS.TaskQueue[k] = nil end
	end

	MQS.TaskQueue[tk] = CurTime() + secs
	MQS.SendDataToClien({index = "TaskQueue", data = MQS.TaskQueue})
end

local function giveRewards(ply, rewards, tk)
	if not istable(rewards) or not IsValid(ply) then return end

	for name, val in pairs(rewards) do
		local r = MQS.Rewards[name]

		if istable(r) and isfunction(r.reward) and not (isfunction(r.check) and r.check()) then
			local ok, err = pcall(r.reward, ply, val)

			if not ok then
				print("[MQS] " .. tostring(tk) .. ": награда \"" .. tostring(name) .. "\": " .. tostring(err))
			end
		end
	end
end

--[[---------------------------------------------------------------------------
	Конец квеста: убрать всё, что он поставил, и сбросить данные
---------------------------------------------------------------------------]]
local function removeEnt(ent, id)
	if IsValid(ent) and not ent:IsPlayer() and ent.task_id == id then SafeRemoveEntity(ent) end
end

local function endTask(ply, id)
	local task = MQS.ActiveTask[id]
	if not task then return end

	local tk = task.task
	local valid = IsValid(ply)

	if valid then
		for _, k in ipairs(END_KEYS) do
			setPublic(ply, k, nil)
		end

		for _, k in ipairs(SELF_KEYS) do
			setSelf(ply, k, nil)
		end
	end

	-- машину сначала отвязать: её удаление не должно провалить квест ещё раз
	local veh = task.vehicle
	task.vehicle = nil

	for _, idx in pairs(task.ents or {}) do
		removeEnt(Entity(tonumber(idx) or -1), id)
	end

	for _, idx in pairs(task.misc_ents or {}) do
		removeEnt(Entity(tonumber(idx) or -1), id)
	end

	if veh then removeEnt(Entity(tonumber(veh) or -1), id) end

	-- то, на что ссылка потерялась (машина после "Check for vehicle" и т.п.)
	for _, ent in ipairs(ents.GetAll()) do
		if ent.IsMQS and ent.task_id == id then removeEnt(ent, id) end
	end

	MQS.ActiveTask[id] = nil
	state[id] = nil

	-- сцены, которые больше не нужны ни одному квесту
	for name in pairs(istable(task.scenes) and task.scenes or {}) do
		local used = false

		for _, other in pairs(MQS.ActiveTask) do
			if istable(other.scenes) and other.scenes[name] then
				used = true
				break
			end
		end

		if not used then MQS.Scenes.UnLoad(name) end
	end

	if valid then
		for _, wep in ipairs(ply:GetWeapons()) do
			if wep.MQS_weapon then ply:StripWeapon(wep:GetClass()) end
		end

		-- "Strip All Weapons" с возвратом: оружие до квеста - обратно
		if ply.MQS_restore and istable(ply.MQS_oldWeap) then
			for cls in pairs(ply.MQS_oldWeap) do
				if isstring(cls) and not ply:HasWeapon(cls) then ply:Give(cls) end
			end
		end

		-- "Set Job Name": прежнее название, если профессия та же
		local job = ply.MQS_OldJob

		if istable(job) and isstring(job[1]) and ply.updateJob and ply:Team() == job[2] then ply:updateJob(job[1]) end
		if ply.EventData then ply.EventData.SpawnPoint = nil end

		ply.MQS_restore, ply.MQS_oldWeap, ply.MQS_OldJob = nil, nil, nil
		ply.MQS_CamPos, ply.MQS_CamEnd = nil, nil

		net.Start("MQS.UIEffect")
		net.WriteString("Quest End")
		net.WriteTable({id = id, uid = ply:UserID()})
		net.Send(ply)
	end

	-- метка "Track player" у других игроков
	net.Start("MQS.UIEffect")
	net.WriteString("UnTrack")
	net.WriteTable({id = id})
	net.Broadcast()

	local n = (MQS.TaskCount[tk] or 1) - 1
	MQS.TaskCount[tk] = n > 0 and n or nil

	MQS.ActiveDataShare()
	MQS.SendDataToClien({index = "TaskCount", data = MQS.TaskCount})
end

--[[---------------------------------------------------------------------------
	Провал и выполнение
---------------------------------------------------------------------------]]
-- MQS.FailTask(игрок[, причина, тихо, без задержки])
function MQS.FailTask(ply, reason, silent, nocd)
	local id, task, quest = current(ply)
	if not id then return false end

	local tk = task.task

	if not silent then
		MQS.Notify(ply, phrase("m_failed"), isstring(reason) and reason or "", 2)
	end

	if quest and not nocd then setCooldown(ply, tk, quest, quest.cool_down_onfail) end

	endTask(ply, id)
	hook.Run("MQS.TaskFailed", ply, tk, reason)

	return true
end

-- MQS.CompleteTask(игрок[, награды, текст, цвет 1-4]) - выполнить сейчас.
-- Без наград - награда квеста (квест с наградой за круг уже наградил по кругам)
function MQS.CompleteTask(ply, rewards, text, color)
	local id, task, quest = current(ply)
	if not id then return false end

	local tk = task.task
	quest = quest or {}

	-- в выполненные до наград: награда "Remove quest played data" правит этот же список
	local list = table.Copy(MQS.GetDataStored(ply, "QuestList") or {})
	local first = not list[tk]

	list[tk] = (tonumber(list[tk]) or 0) + 1
	MQS.SetNWStoredData(ply, "QuestList", list)

	if rewards == nil and not (quest.looped and quest.reward_ower_loop) then rewards = quest.reward end

	giveRewards(ply, rewards, tk)

	if not isstring(text) or text == "" then text = quest.success end
	if not isstring(text) or text == "" then text = phrase("m_done_quest") end

	MQS.Notify(ply, phrase("m_success"), text, math.Clamp(math.floor(tonumber(color) or 3), 1, 4))

	setCooldown(ply, tk, quest, quest.cool_down)

	if first then MQS.AddStat(tk, "u") end

	endTask(ply, id)
	hook.Run("MQS.TaskCompleted", ply, tk)

	return true
end

local function loopTask(ply, id)
	local task = MQS.ActiveTask[id]
	local quest = questOf(task)
	if not quest then return end

	setPublic(ply, "loops", (tonumber(ply.MQSdata.loops) or 0) + 1)

	if quest.reward_ower_loop then giveRewards(ply, quest.reward, task.task) end

	MQS.TaskNotify(ply, phrase("m_loop"), 4)

	return setObjective(ply, id, 1)
end

--[[---------------------------------------------------------------------------
	Задачи
---------------------------------------------------------------------------]]
local function runEvents(ply, id, obj, gen, tk)
	if not istable(obj.events) then return end

	for _, ev in ipairs(obj.events) do
		if not alive(id, ply, gen) then return end

		local name = istable(ev) and ev[1]
		local fn = isstring(name) and MQS.Events[name]

		if isfunction(fn) then
			local ok, err = pcall(fn, id, ply, ev[2], obj, tk)

			if not ok then print("[MQS] " .. tk .. ": событие \"" .. name .. "\": " .. tostring(err)) end
		elseif isstring(name) then
			print("[MQS] " .. tk .. ": нет события \"" .. name .. "\"")
		end
	end
end

-- живые цели "Kill NPC" (событие "Spawn npc" с отметкой цели)
local function countTargets(task, id, except)
	local n = 0

	for _, idx in pairs(task.misc_ents or {}) do
		local ent = Entity(tonumber(idx) or -1)

		if IsValid(ent) and ent ~= except and ent.is_quest_npc and ent.task_id == id and ent:Health() > 0 then
			n = n + 1
		end
	end

	return n
end

-- квестовые предметы на карте, которые ещё не подняли (предметы-переходы не в счёт)
local function countItems(task, id)
	local n = 0

	for _, idx in pairs(task.ents or {}) do
		local ent = Entity(tonumber(idx) or -1)

		if IsValid(ent) and ent.task_id == id and not ent.picked and not ent.updateobj then n = n + 1 end
	end

	return n
end

local function doSetObjective(ply, id, oid)
	local task = MQS.ActiveTask[id]
	if not task or task.player ~= ply then return end

	local quest = questOf(task)
	local st = state[id]

	if not quest or not st then return MQS.FailTask(ply, phrase("m_failed")) end

	oid = math.floor(tonumber(oid) or 0)

	local obj = objectiveOf(quest, oid)

	-- за последней задачей
	if not obj then
		if quest.looped and objectiveOf(quest, 1) then return loopTask(ply, id) end

		return MQS.CompleteTask(ply)
	end

	st.gen = st.gen + 1

	local gen = st.gen

	st.oid, st.start, st.startPos = oid, CurTime(), ply:GetPos()
	st.wait, st.need, st.collected, st.killed, st.lp, st.talked, st.check, st.center = nil, nil, nil, nil, nil, nil, nil, nil

	runEvents(ply, id, obj, gen, task.task)
	if not alive(id, ply, gen) then return end

	local t = obj.type
	local counters = {}

	if t == "Skip to" then
		return setObjective(ply, id, tonumber(obj.oid) or oid + 1)
	elseif t == "Randomize" then
		local list = {}

		for k, v in pairs(istable(obj.objects) and obj.objects or {}) do
			local n = tonumber(k)

			if v and n and n ~= oid and objectiveOf(quest, n) then list[#list + 1] = n end
		end

		return setObjective(ply, id, #list > 0 and list[math.random(#list)] or oid + 1)
	elseif t == "End of quest" then
		local text = isstring(obj.desc) and obj.desc ~= t and obj.desc or nil
		local rewards = istable(obj.reward) and next(obj.reward) ~= nil and obj.reward or nil

		return MQS.CompleteTask(ply, rewards, text, obj.notify)
	elseif t == "Kill NPC" then
		if countTargets(task, id) < 1 then return setObjective(ply, id, oid + 1) end
	elseif t == "Collect quest ents" then
		local n = countItems(task, id)
		local lim = tonumber(obj.target_limit)

		if lim and lim >= 1 then n = math.min(n, math.floor(lim)) end

		if n < 1 then
			print("[MQS] " .. task.task .. ": задача " .. oid .. " - на карте нет квестовых предметов")

			return MQS.FailTask(ply, phrase("q_enterror"))
		end

		st.need, st.collected = n, 0
		counters.quest_ent, counters.quest_colected = n, 0
	elseif t == "Wait time" or t == "Wait taxi time" then
		st.wait = CurTime() + math.max(tonumber(obj.time) or 10, 0)
		st.center = isvector(obj.point) and obj.point or st.startPos
		counters.quest_wait = st.wait
	elseif t == "Kill random target" then
		st.killed = 0
		counters.targets = 0
	elseif t == "Leave area LP" then
		st.lp = isvector(task.LastPoint) and task.LastPoint or ply:GetPos()
	end

	-- счётчики раньше номера задачи: клиент рисует задачу по ним
	for k, v in pairs(counters) do
		setSelf(ply, k, v)
	end

	setPublic(ply, "quest_objective", oid)

	for _, k in ipairs(SELF_KEYS) do
		if counters[k] == nil then setSelf(ply, k, nil) end
	end

	-- машина появилась или пропала - её номер нужен клиентам
	if st.veh ~= task.vehicle then
		st.veh = task.vehicle
		MQS.ActiveDataShare()
	end

	-- своё описание задачи - внизу экрана (на старте там и так название квеста)
	if isstring(obj.desc) and obj.desc ~= "" and obj.desc ~= t and st.started ~= CurTime() then
		MQS.TaskNotify(ply, obj.desc, 4)
	end

	hook.Run("MQS.ObjectiveChanged", ply, task.task, oid)
end

setObjective = function(ply, id, oid)
	if depth == 0 then jumps = 0 end

	jumps = jumps + 1

	if jumps > MAX_JUMPS then
		local task = MQS.ActiveTask[id]

		print("[MQS] " .. tostring(task and task.task) .. ": задачи переходят друг в друга по кругу")

		if not MQS.FailTask(ply, phrase("q_errorloop")) then endTask(ply, id) end

		return
	end

	depth = depth + 1

	local ok, err = pcall(doSetObjective, ply, id, oid)

	depth = depth - 1

	if not ok then
		print("[MQS] Ошибка задачи: " .. tostring(err))

		if MQS.ActiveTask[id] and not MQS.FailTask(ply, phrase("m_failed")) then endTask(ply, id) end
	end
end

local function advance(ply, id)
	local st = state[id]

	if st then setObjective(ply, id, (st.oid or 0) + 1) end
end

--[[---------------------------------------------------------------------------
	Старт
	MQS.StartTask(квест, игрок[, npc, force]) - npc: NPC, у которого взяли квест
	(для квестов, привязанных к NPC); force - без проверок (вступление)
---------------------------------------------------------------------------]]
function MQS.StartTask(tk, ply, npc, force)
	if not isstring(tk) or not IsValid(ply) or not ply:IsPlayer() then return false end

	MQS.InitPlayer(ply)

	if not ply.MQS_Loaded then
		MQS.SmallNotify("Данные заданий ещё загружаются - попробуйте через пару секунд", ply, 1)

		return false
	end

	local ok, reason = MQS.CanStartTask(tk, ply, npc, force)

	if not ok then
		if isstring(reason) and reason ~= "" then MQS.SmallNotify(reason, ply, 1) end

		return false, reason
	end

	local quest = MQS.Quests[tk]

	if not objectiveOf(quest, 1) then
		MQS.SmallNotify("В квесте нет задач", ply, 1)

		return false
	end

	MQS.TaskID = MQS.TaskID + 1

	local id = MQS.TaskID

	MQS.ActiveTask[id] = {task = tk, player = ply, ents = {}, misc_ents = {}, scenes = {}}
	state[id] = {gen = 0, started = CurTime()}
	MQS.TaskCount[tk] = (MQS.TaskCount[tk] or 0) + 1

	ply.MQS_restore, ply.MQS_oldWeap, ply.MQS_OldJob = nil, nil, nil

	-- квест целиком (с задачами) - раньше, чем клиент начнёт его рисовать
	MQS.ReQuest(tk, ply)
	MQS.ActiveDataShare()
	MQS.SendDataToClien({index = "TaskCount", data = MQS.TaskCount})

	setPublic(ply, "active_questid", id)

	local dt = tonumber(quest.do_time)
	if dt and dt > 0 then setPublic(ply, "do_time", CurTime() + dt) end

	-- сервер знает о квесте сразу, клиенты - после первой задачи (иначе нарисуют пустую)
	ply.MQSdata.active_quest = tk

	MQS.Notify(ply, isstring(quest.name) and quest.name ~= "" and quest.name or tk, isstring(quest.desc) and quest.desc or "", 1)
	MQS.AddStat(tk, "t")
	hook.Run("MQS.TaskStarted", ply, tk, id)

	setObjective(ply, id, 1)

	if MQS.ActiveTask[id] then MQS.SetNWdata(ply, "active_quest", tk) end

	return true
end

-- MQS.UpdateObjective(игрок[, задача]) - следующая задача или переход к задаче с номером
function MQS.UpdateObjective(ply, oid)
	local id = current(ply)
	if not id then return false end

	local st = state[id]

	setObjective(ply, id, tonumber(oid) or (st and st.oid or 0) + 1)

	return true
end

-- остановить все прохождения квеста (его изменили или удалили) - без задержки
function MQS.StopQuestTasks(tk, reason)
	local list = {}

	for _, task in pairs(MQS.ActiveTask) do
		if task.task == tk then list[#list + 1] = task.player end
	end

	for _, pl in ipairs(list) do
		MQS.FailTask(pl, reason or EDIT_REASON, false, true)
	end
end

-- игрок вышел: квест провален молча, задержка за провал - как обычно
function MQS.EndPlayerTask(ply)
	MQS.FailTask(ply, nil, true)

	for id, task in pairs(MQS.ActiveTask) do
		if task.player == ply then endTask(ply, id) end
	end
end

--[[---------------------------------------------------------------------------
	Квестовые предметы (entities/mqs_ent/init.lua)
---------------------------------------------------------------------------]]
-- можно ли поднять предмет сейчас: предмет-переход - всегда, остальные - в задаче сбора
function MQS.CanPickQuestEnt(ply, ent)
	local id, _, quest = current(ply)
	if not id or ent.task_id ~= id then return false end
	if ent.updateobj then return true end

	local st = state[id]
	local obj = objectiveOf(quest, st and st.oid)

	return obj and obj.type == "Collect quest ents" or false
end

-- предмет подняли или разбили: засчитать
function MQS.QuestEntPicked(ply, ent)
	if not MQS.CanPickQuestEnt(ply, ent) then return false end

	local id = current(ply)
	local st = state[id]

	ent.picked = true

	if ent.updateobj then
		setObjective(ply, id, tonumber(ent.updateobj) or st.oid + 1)

		return true
	end

	st.collected = (st.collected or 0) + 1
	setSelf(ply, "quest_colected", st.collected)

	if st.collected >= (st.need or 1) then advance(ply, id) end

	return true
end

--[[---------------------------------------------------------------------------
	Проверка задач (раз в THINK)
---------------------------------------------------------------------------]]
local function findNPC(class, uid)
	for _, ent in ipairs(ents.FindByClass(class)) do
		if ent.GetUID and tostring(ent:GetUID()) == tostring(uid) then return ent end
	end
end

-- "Talk to NPC" с автостартом: разговор открывается сам, как будто игрок нажал E
local function openTalk(ply, npc)
	if util.NetworkStringToID("MCS.OpenMenu") == 0 then return end

	ply.MCSTalk = npc

	net.Start("MCS.OpenMenu")
	net.WriteEntity(npc)
	net.Send(ply)
end

local function checkTask(id, task)
	local ply = task.player

	if not IsValid(ply) then return endTask(ply, id) end

	local quest = questOf(task)
	local st = state[id]

	if not quest or not st then
		if not MQS.FailTask(ply, phrase("m_failed")) then endTask(ply, id) end

		return
	end

	-- время квеста вышло
	local dt = tonumber(ply.MQSdata and ply.MQSdata.do_time)

	if dt and CurTime() >= dt then
		if quest.reward_on_time then return MQS.CompleteTask(ply) end

		return MQS.FailTask(ply, "Время на задание вышло")
	end

	if not ply:Alive() then return end

	local obj = objectiveOf(quest, st.oid)
	if not obj then return end

	local t = obj.type
	local veh = task.vehicle and Entity(task.vehicle)

	if veh and not IsValid(veh) then veh = nil end

	-- в задачах с квестовой машиной засчитывается только езда на ней
	local inVeh = not (veh and VEHICLE_TASKS[t] and not obj.ignore_veh) or MQS.GetActiveVehicle(ply) == veh
	local pos = ply:GetPos()

	if t == "Move to point" then
		if not inVeh or not isvector(obj.point) or not near(pos, obj.point, radius(obj.dist, POINT_DIST)) then return end

		if obj.vehicle_stop then
			local v = MQS.GetActiveVehicle(ply)

			if IsValid(v) and v:GetVelocity():Length() > STOP_SPEED then return end
		end

		task.LastPoint = obj.point

		return advance(ply, id)
	elseif t == "Move to any point" then
		for _, p in pairs(istable(obj.points) and obj.points or {}) do
			if istable(p) and p.active ~= false and isvector(p.point) and near(pos, p.point, radius(p.dist, POINT_DIST)) then
				local target = tonumber(p.id)

				task.LastPoint = p.point

				if target and target ~= st.oid and objectiveOf(quest, target) then return setObjective(ply, id, target) end

				return advance(ply, id)
			end
		end
	elseif t == "Leave area" then
		local c = isvector(obj.point) and obj.point or st.startPos

		if inVeh and isvector(c) and not near(pos, c, radius(obj.dist, LEAVE_DIST)) then return advance(ply, id) end
	elseif t == "Leave area LP" then
		local c = st.lp or task.LastPoint

		if inVeh and isvector(c) and not near(pos, c, radius(obj.dist, LEAVE_DIST)) then return advance(ply, id) end
	elseif t == "Wait time" then
		local area = tonumber(obj.stay_inarea)
		local c = st.center

		-- под картой (интерьеры) расстояние до точки наверху не считаем
		if area and area > 0 and isvector(c) and not (pos.z < UNDERGROUND and c.z > UNDERGROUND) and not near(pos, c, area) then
			return MQS.FailTask(ply, phrase("q_must_stay_area"))
		end

		-- без квестовой машины время стоит
		if not inVeh then
			st.wait = (st.wait or CurTime()) + THINK

			if (st.check or 0) <= CurTime() then
				st.check = CurTime() + 1
				setSelf(ply, "quest_wait", st.wait)
			end

			return
		end

		if st.wait and CurTime() >= st.wait then return advance(ply, id) end
	elseif t == "Wait taxi time" then
		if st.wait and CurTime() >= st.wait then return advance(ply, id) end
	elseif t == "Collect quest ents" then
		-- предметы пропали (очистка карты) - собрать нужное уже нельзя
		if (st.check or 0) <= CurTime() then
			st.check = CurTime() + 2

			if countItems(task, id) + (st.collected or 0) < (st.need or 1) then
				return MQS.FailTask(ply, phrase("q_enterror"))
			end
		end
	elseif t == "Kill NPC" then
		if (st.check or 0) <= CurTime() then
			st.check = CurTime() + 1

			if countTargets(task, id) < 1 then return advance(ply, id) end
		end
	elseif t == "Talk to NPC" and obj.autostart and not st.talked and obj.npc ~= nil then
		local npc = findNPC("mcs_npc", obj.npc)

		if IsValid(npc) and near(pos, npc:GetPos(), TALK_DIST) then
			st.talked = true
			openTalk(ply, npc)
		end
	end
end

timer.Create("MQS.TaskThink", THINK, 0, function()
	local ids = {}

	for id in pairs(MQS.ActiveTask) do
		ids[#ids + 1] = id
	end

	for _, id in ipairs(ids) do
		local task = MQS.ActiveTask[id]

		if task then
			local ok, err = pcall(checkTask, id, task)

			if not ok then print("[MQS] Ошибка проверки задачи: " .. tostring(err)) end
		end
	end
end)

--[[---------------------------------------------------------------------------
	События игры
---------------------------------------------------------------------------]]
local function countKill(ply, id, obj)
	local st = state[id]
	if not st then return end

	st.killed = (st.killed or 0) + 1
	setSelf(ply, "targets", st.killed)

	if st.killed >= (tonumber(obj.target_count) or 1) then advance(ply, id) end
end

-- задача "Kill random target" нужного вида: 1 - NPC, 2 - игрок
local function randomTarget(ply, kind)
	local id, _, quest = current(ply)
	if not id then return end

	local obj = objectiveOf(quest, state[id] and state[id].oid)
	if not obj or obj.type ~= "Kill random target" or (tonumber(obj.target_type) or 1) ~= kind then return end

	return id, obj
end

local function anyClass(cls, value)
	return not isstring(cls) or cls == "" or cls == value
end

-- "Kill Penalty": fail - провал, arrest - арест, remove - без штрафа
local function penalty(ply, kind)
	if kind == "fail" then
		MQS.FailTask(ply, "Убийство во время задания")
	elseif kind == "arrest" and DarkRP and isfunction(DarkRP.AutoArrest) then
		DarkRP.AutoArrest(ply, PENALTY_JAIL, "Убийство во время задания")
	end
end

hook.Add("PlayerDeath", "MQS.Tasks", function(victim, _, attacker)
	local id, _, quest = current(victim)

	if id and quest and quest.fail_ondeath then MQS.FailTask(victim, phrase("dead")) end

	if not IsValid(attacker) or not attacker:IsPlayer() or attacker == victim then return end

	local tid, obj = randomTarget(attacker, 2)

	if tid and anyClass(obj.target_class, team.GetName(victim:Team())) then countKill(attacker, tid, obj) end

	local aid, atask = current(attacker)

	if aid and atask.penalty then penalty(attacker, atask.penalty) end
end)

hook.Add("OnNPCKilled", "MQS.Tasks", function(npc, attacker)
	-- подопечный (событие "Spawn npc" с защитой)
	local owner = npc.is_quest_protect

	if IsValid(owner) and owner:IsPlayer() then
		local oid = current(owner)

		if oid and oid == npc.task_id then MQS.FailTask(owner, "Вы не уберегли подопечного") end
	end

	-- цель "Kill NPC"
	local tid = npc.is_quest_npc and npc.task_id
	local task = tid and MQS.ActiveTask[tid]

	if task then
		local st = state[tid]
		local obj = st and objectiveOf(questOf(task), st.oid)

		if obj and obj.type == "Kill NPC" and countTargets(task, tid, npc) < 1 then advance(task.player, tid) end
	end

	-- случайная цель
	if IsValid(attacker) and attacker:IsPlayer() then
		local rid, obj = randomTarget(attacker, 1)

		if rid and anyClass(obj.target_class, npc:GetClass()) then countKill(attacker, rid, obj) end
	end
end)

-- цель квеста бьёт только его игрок (кроме открытых целей)
hook.Add("EntityTakeDamage", "MQS.Tasks", function(ent, dmg)
	if not ent.is_quest_npc or ent.open_target or ent.task_id == nil then return end

	local task = MQS.ActiveTask[ent.task_id]
	local att = dmg:GetAttacker()

	if task and IsValid(att) and att:IsPlayer() and att ~= task.player then return true end
end)

hook.Add("playerArrested", "MQS.Tasks", function(ply)
	local id, task, quest = current(ply)
	if not id or hook.Call("MQS.AllowJailTaskStart", nil, ply, task.task, quest) then return end

	MQS.FailTask(ply, "Вас арестовали")
end)

hook.Add("OnPlayerChangedTeam", "MQS.Tasks", function(ply, _, new)
	local id, _, quest = current(ply)
	if not id or not quest then return end

	local name = team.GetName(new)
	local wl, bl = quest.team_whitelist, quest.team_blacklist

	local listed = istable(wl) and (wl[name] or wl[new]) and true or false

	-- как в MQS.CanStartTask: team_blacklist - флажок «team_whitelist - это чёрный список»
	if istable(wl) and next(wl) ~= nil and (bl and listed or not bl and not listed) then
		MQS.FailTask(ply, phrase("team_bl"))
	end
end)

-- квестовая машина пропала (взо��вали, убрал админ) - провал
hook.Add("EntityRemoved", "MQS.Tasks", function(ent)
	local id = ent.IsMQS and ent.task_id
	local task = id and MQS.ActiveTask[id]

	if not task or task.vehicle ~= ent:EntIndex() then return end

	task.vehicle = nil

	local ply = task.player

	timer.Simple(0, function()
		if IsValid(ply) and MQS.ActiveTask[id] == task then MQS.FailTask(ply, phrase("vehicle_bum")) end
	end)
end)

-- "Set spawn point": возрождение в точке квеста
hook.Add("PlayerSpawn", "MQS.SpawnPoint", function(ply)
	timer.Simple(0, function()
		if not IsValid(ply) or not current(ply) then return end

		local sp = ply.EventData and ply.EventData.SpawnPoint
		if not istable(sp) or not isvector(sp[1]) then return end

		ply:SetPos(sp[1])

		if isangle(sp[2]) then ply:SetEyeAngles(sp[2]) end
	end)
end)

-- вступительный квест сам (MQS.Config.IntoQuestAutogive)
local function introAutogive(ply)
	if not MQS.Config.IntoQuestAutogive or not isstring(MQS.Config.IntoQuest) then return end

	timer.Simple(3, function()
		if IsValid(ply) and ply.MQS_Loaded and not current(ply) and MQS.CanPlayIntro(ply) then
			MQS.StartTask(MQS.Config.IntoQuest, ply, nil, true)
		end
	end)
end

hook.Add("MQS.PlayerDataLoaded", "MQS.Intro", introAutogive)
hook.Add("MCR.CharacterSelected", "MQS.Intro", introAutogive)

--[[---------------------------------------------------------------------------
	Старт от клиента. После id квеста: ничего; String UID (NPC MCS);
	Bool (true - MCS) + String UID или Int16 UID (NPC MQS)
---------------------------------------------------------------------------]]
-- NPC рядом с игроком (NPC MCS с ignore - с любого расстояния: звонок и т.п.)
local function npcNear(ply, simple, uid)
	local npc = findNPC(simple and "mcs_npc" or "mqs_npc", uid)
	if not IsValid(npc) then return false end

	if simple and MCS and istable(MCS.Spawns) then
		local sp = MCS.Spawns[npc:GetUID()]

		if istable(sp) and sp.ignore then return true end
	end

	return near(ply:GetPos(), npc:GetPos(), NPC_DIST)
end

-- UID в том же виде, что в связи квеста (строка или число): MQS.HasNPCLink сравнивает как есть
local function linkValue(tk, uid)
	local q = MQS.Quests[tk]
	local link = q and q.link
	local id = istable(link) and link.id or link

	if id ~= nil and tostring(id) == tostring(uid) then return id end

	return uid
end

net.Receive("MQS.StartTask", function(len, ply)
	if spam(ply, "start", 1) then return end

	local tk = net.ReadString()
	if not isstring(tk) or tk == "" or #tk > 64 then return end

	local rest = len - (#tk + 1) * 8
	local simple, uid

	if rest >= 9 and rest % 8 == 1 then
		simple = net.ReadBool()
		uid = simple and net.ReadString() or net.ReadInt(16)
	elseif rest >= 8 and rest % 8 == 0 then
		simple, uid = true, net.ReadString()
	end

	if uid == nil or uid == "" then return MQS.StartTask(tk, ply) end
	if not npcNear(ply, simple, uid) then return end

	MQS.StartTask(tk, ply, linkValue(tk, uid))
end)

concommand.Add("mqs_start", function(ply, _, args)
	if not IsValid(ply) or spam(ply, "start", 1) then return end

	local tk = args[1]
	if not isstring(tk) or tk == "" then return end

	-- вступление - без проверок, если игрок его ещё не проходил
	if tk == MQS.Config.IntoQuest and MQS.CanPlayIntro(ply) then return MQS.StartTask(tk, ply, nil, true) end

	MQS.StartTask(tk, ply)
end)

concommand.Add("mqs_stop", function(ply)
	if not IsValid(ply) or spam(ply, "stop", 1) then return end

	local id, _, quest = current(ply)
	if not id or not quest then return end

	-- круг уже пройден - остановка с наградой
	if quest.looped and not quest.reward_on_time and (tonumber(ply.MQSdata.loops) or 0) > 0 then
		return MQS.CompleteTask(ply)
	end

	if quest.stop_anytime then MQS.FailTask(ply, phrase("quest_abandon")) end
end)

--[[---------------------------------------------------------------------------
	Квестовая машина (событие "Spawn vehicle"): default - из списка Vehicles,
	simfphys - simfphys.SpawnVehicleSimple; LFS на сервере нет
---------------------------------------------------------------------------]]
function MQS.SpawnQuestVehicle(ply, class, vtype, pos, ang)
	if not isstring(class) or not isvector(pos) then return end

	ang = isangle(ang) and ang or Angle(0, 0, 0)

	local veh

	if vtype == "simfphys" then
		if not simfphys or not isfunction(simfphys.SpawnVehicleSimple) then
			print("[MQS] simfphys не установлен - машина " .. class .. " не появится")

			return
		end

		veh = simfphys.SpawnVehicleSimple(class, pos, ang)
	elseif vtype == "lfs" then
		print("[MQS] LFS на сервере нет - машина " .. class .. " не появится")

		return
	else
		local vt = list.Get("Vehicles")[class]

		if not istable(vt) or not isstring(vt.Class) then
			print("[MQS] Нет машины " .. class .. " в списке Vehicles")

			return
		end

		veh = ents.Create(vt.Class)
		if not IsValid(veh) then return end

		if isstring(vt.Model) then veh:SetModel(vt.Model) end

		veh:SetPos(pos)
		veh:SetAngles(ang)

		for k, v in pairs(istable(vt.KeyValues) and vt.KeyValues or {}) do
			veh:SetKeyValue(k, v)
		end

		veh:Spawn()
		veh:Activate()
		veh.VehicleName = class
		veh.VehicleTable = vt
	end

	if not IsValid(veh) then return end

	if IsValid(ply) then
		if veh.CPPISetOwner then veh:CPPISetOwner(ply) end
		if veh.keysOwn then veh:keysOwn(ply) end
	end

	return veh
end

--[[---------------------------------------------------------------------------
	NPC квестов на карте (MQS.Config.NPC.list, места - по картам)
---------------------------------------------------------------------------]]
function MQS.SpawnNPCs()
	for _, ent in ipairs(ents.FindByClass("mqs_npc")) do
		ent:Remove()
	end

	local cfg = MQS.Config and MQS.Config.NPC
	local map = game.GetMap()

	for uid, npc in pairs(istable(cfg) and istable(cfg.list) and cfg.list or {}) do
		local sp = istable(npc) and istable(npc.spawns) and npc.spawns[map]

		if istable(sp) and isvector(sp[1]) then
			local ent = ents.Create("mqs_npc")

			if IsValid(ent) then
				ent.npcData = npc
				ent:SetPos(sp[1])
				ent:SetAngles(isangle(sp[2]) and sp[2] or Angle(0, 0, 0))
				ent:Spawn()
				ent:SetUID(tonumber(uid) or 0)
				ent:SetNamer(isstring(npc.name) and npc.name or "")
			end
		end
	end
end

hook.Add("InitPostEntity", "MQS.NPC", function()
	MQS.WorldReady = true
	MQS.SpawnNPCs()
end)

hook.Add("PostCleanupMap", "MQS.NPC", function()
	MQS.SpawnNPCs()
end)

hook.Add("MQS.Hook.PostConfigLoad", "MQS.NPC", function()
	if MQS.WorldReady then MQS.SpawnNPCs() end
end)

--[[---------------------------------------------------------------------------
	Дополнения к событиям и наградам sh_init.lua
---------------------------------------------------------------------------]]
-- "Give Inv" (событие и награда): в карманы, а если места нет - на землю у ног
local function giveItem(ply, val)
	if not IsValid(ply) or not istable(val) or not McINV or not istable(McINV.ttypes) then return end

	local itype, class = val[2], val[1]
	local cat = McINV.ttypes[itype]
	local data = cat and istable(DarkRP[cat]) and DarkRP[cat][class]
	if not istable(data) then return end

	local item = McINV.AddCustomItem(nil, itype, class, data)
	if not istable(item) then return end

	-- тот же тип, что выбирает McINV.AddCustomItem
	local t = istable(McINV.DarkRPTypes) and McINV.DarkRPTypes[itype] or itype
	if t == "Stations" then t = INV_ENTITY end

	local weight = isfunction(McINV.GetWeight) and tonumber(McINV.GetWeight(item, t, item.class)) or 0

	if ply.HaveSpace and ply:HaveSpace(weight) and ply:AddItem(t, item) then return end

	local pos = ply:GetPos() + ply:GetForward() * 30 + Vector(0, 0, 10)

	if McINV.SpawnItem(t, item, pos, Angle(0, ply:EyeAngles().y, 0), ply) then
		MQS.SmallNotify("В карманах нет места - награда лежит рядом", ply, 1)
	end
end

MQS.Events["Give Inv"] = function(_, ply, data)
	giveItem(ply, data)
end

if istable(MQS.Rewards["Give Inv"]) then MQS.Rewards["Give Inv"].reward = giveItem end

-- "Set Job Name": прежнее название профессии вернётся в конце квеста (если профессия та же)
local setJob = MQS.Events["Set Job Name"]

if isfunction(setJob) then
	MQS.Events["Set Job Name"] = function(task, ply, data, ...)
		if IsValid(ply) and ply.MQS_OldJob == nil and ply.getDarkRPVar then
			ply.MQS_OldJob = {ply:getDarkRPVar("job"), ply:Team()}
		end

		return setJob(task, ply, data, ...)
	end
end
