--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
--[[---------------------------------------------------------------------------
    sAdmin -> журнал DarkRP (data/darkrp_logs и консоль администрации):
    выполненные команды. Текст личных сообщений (pm, dm, asay) не пишется.
---------------------------------------------------------------------------]]
local PRIVATE = {
    ["pm"] = true,
    ["dm"] = true,
    ["asay"] = true
}

hook.Add("sA:RanCommand", "sA:DarkRPLog", function(ply, name, args, argsStr)
    if not DarkRP or not DarkRP.log then return end

    local text = (IsValid(ply) and "" or "КОНСОЛЬ ") .. "выполнил команду " .. tostring(name)

    if PRIVATE[name] then
        -- только адресат (игрок или номер обращения), без текста
        if name ~= "asay" and istable(args) and args[1] then
            text = text .. " [" .. tostring(args[1]) .. "]"
        end
    elseif isstring(argsStr) and argsStr ~= "" then
        text = text .. " [" .. argsStr .. "]"
    end

    DarkRP.log("admin", IsValid(ply) and ply or nil, nil, text)
end)
