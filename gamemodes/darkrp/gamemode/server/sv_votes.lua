--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
--[[---------------------------------------------------------------------------
	Голосования и вопросы (клиентский UI: DoVote / DoQuestion)

	DarkRP.createVote(question, voters|nil, callback(yes, no, data), time, data)
	DarkRP.createQuestion(question, target, callback(answer, target, data), time, data)
	Ответы: vote <id> yea|nay, ans <id> 1|2
---------------------------------------------------------------------------]]
local votes = {}
local questions = {}
local voteCount = 0
local questionCount = 0

local function clampTime(time)
	return math.Clamp(math.floor(tonumber(time) or 30), 5, 99)
end

local function safeCall(name, fn, ...)
	if not isfunction(fn) then return end

	local ok, err = xpcall(fn, debug.traceback, ...)

	if not ok then
		ErrorNoHalt("[DarkRP] Ошибка в " .. name .. ": " .. tostring(err) .. "\n")
	end
end

--[[---------------------------------------------------------------------------
	Голосования
---------------------------------------------------------------------------]]
local function finishVote(id)
	local vote = votes[id]
	if not vote then return end

	votes[id] = nil
	timer.Remove("DarkRP.Vote." .. id)

	local online = {}

	for _, v in ipairs(vote.voters) do
		if IsValid(v) then online[#online + 1] = v end
	end

	if #online > 0 then
		DarkRP.UIEffect(online, "KillVoteVGUI", {id})
	end

	local yes, no = 0, 0

	for _, answer in pairs(vote.answers) do
		if answer then yes = yes + 1 else no = no + 1 end
	end

	safeCall("голосовании", vote.callback, yes, no, vote.data)
end

function DarkRP.createVote(question, voters, callback, time, data)
	local list, allowed = {}, {}

	for _, v in ipairs(voters or player.GetHumans()) do
		if IsValid(v) and v:IsPlayer() and not v:IsBot() and not allowed[v:UserID()] then
			list[#list + 1] = v
			allowed[v:UserID()] = true
		end
	end

	if #list == 0 then
		safeCall("голосовании", callback, 0, 0, data)
		return
	end

	voteCount = voteCount + 1
	local id = "v" .. voteCount
	time = clampTime(time)

	votes[id] = {
		voters = list,
		allowed = allowed,
		answers = {},
		total = #list,
		callback = callback,
		data = data
	}

	DarkRP.UIEffect(list, "DoVote", {msg = tostring(question or ""), id = id, time = time})
	timer.Create("DarkRP.Vote." .. id, time, 1, function() finishVote(id) end)

	return id
end

local voteAnswers = {yea = true, yes = true, ["1"] = true, nay = false, no = false, ["0"] = false}

concommand.Add("vote", function(ply, _, args)
	if not IsValid(ply) then return end

	local id = tostring(args[1] or "")
	local vote = votes[id]
	local uid = ply:UserID()

	if not vote or not vote.allowed[uid] or vote.answers[uid] ~= nil then return end

	local answer = voteAnswers[string.lower(tostring(args[2] or ""))]
	if answer == nil then return end

	vote.answers[uid] = answer

	if table.Count(vote.answers) >= vote.total then
		finishVote(id)
	end
end)

--[[---------------------------------------------------------------------------
	Вопросы одному игроку
---------------------------------------------------------------------------]]
local function finishQuestion(id, answer)
	local question = questions[id]
	if not question then return end

	questions[id] = nil
	timer.Remove("DarkRP.Question." .. id)

	if IsValid(question.target) then
		DarkRP.UIEffect(question.target, "KillQuestionVGUI", {id})
	end

	safeCall("вопросе", question.callback, answer, question.target, question.data)
end

function DarkRP.createQuestion(question, target, callback, time, data)
	if not IsValid(target) or not target:IsPlayer() or target:IsBot() then
		safeCall("вопросе", callback, false, target, data)
		return
	end

	questionCount = questionCount + 1
	local id = "q" .. questionCount
	time = clampTime(time)

	questions[id] = {
		target = target,
		callback = callback,
		data = data
	}

	DarkRP.UIEffect(target, "DoQuestion", {msg = tostring(question or ""), id = id, time = time})
	timer.Create("DarkRP.Question." .. id, time, 1, function() finishQuestion(id, false) end)

	return id
end

concommand.Add("ans", function(ply, _, args)
	if not IsValid(ply) then return end

	local id = tostring(args[1] or "")
	local question = questions[id]
	if not question or question.target ~= ply then return end

	finishQuestion(id, tostring(args[2] or "") == "1")
end)

hook.Add("PlayerDisconnected", "DarkRP.Questions", function(ply)
	local ids = {}

	for id, question in pairs(questions) do
		if question.target == ply then ids[#ids + 1] = id end
	end

	for _, id in ipairs(ids) do
		finishQuestion(id, false)
	end
end)