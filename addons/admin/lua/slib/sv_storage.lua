--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
--[[---------------------------------------------------------------------------
    slib: серверное SQL-хранилище (используется sAdmin)

    MySQL - через MySQLite гейммода (darkrp/gamemode/config/mysql.lua),
    иначе SQLite через встроенный sql.* (garrysmod/sv.db).

    slib.dbReady()                       - база готова к запросам
    slib.dbIsMySQL()                     - подключён MySQL
    slib.dbAutoIncrement()               - тип столбца автоинкрементного ключа
    slib.dbEscape(value)                 - значение в кавычках для подстановки в запрос
    slib.dbQuery(query, callback, onErr) - callback(rows, lastInsertId), rows всегда таблица
    slib.onDBReady(id, fn)               - fn() после готовности базы (сразу, если уже готова)

    Запросы до готовности базы откладываются и выполняются после onDBReady.
---------------------------------------------------------------------------]]
slib = slib or {}
slib.db = slib.db or {ready = false, queue = {}, order = {}, pending = {}}

local db = slib.db
local colTag, colError = Color(121, 43, 185), Color(255, 90, 90)

local function hasMySQLite()
    return istable(MySQLite) and isfunction(MySQLite.query)
end

local function logError(err, query)
    MsgC(colTag, "[slib:db] ", colError, tostring(err), color_white, " (" .. tostring(query) .. ")\n")
end

local function isInsert(query)
    local word = string.match(query, "^%s*(%a+)")

    return word ~= nil and string.upper(word) == "INSERT"
end

slib.dbReady = function()
    return db.ready
end

slib.dbIsMySQL = function()
    return hasMySQLite() and isfunction(MySQLite.isMySQL) and MySQLite.isMySQL() or false
end

slib.dbAutoIncrement = function()
    return slib.dbIsMySQL() and "INTEGER NOT NULL AUTO_INCREMENT PRIMARY KEY" or "INTEGER PRIMARY KEY AUTOINCREMENT"
end

slib.dbEscape = function(value)
    value = tostring(value == nil and "" or value)

    if slib.dbIsMySQL() and isfunction(MySQLite.SQLStr) then
        return MySQLite.SQLStr(value)
    end

    return sql.SQLStr(value)
end

slib.dbQuery = function(query, callback, onError)
    if not isstring(query) or query == "" then return end

    if not db.ready then
        table.insert(db.pending, {query, callback, onError})
        return
    end

    local function fail(err, sqlText)
        logError(err, sqlText or query)

        if onError then
            xpcall(onError, ErrorNoHaltWithStack, err)
        end

        return true
    end

    local function done(rows, lastInsert)
        if not callback then return end
        xpcall(callback, ErrorNoHaltWithStack, istable(rows) and rows or {}, tonumber(lastInsert))
    end

    if slib.dbIsMySQL() then
        MySQLite.query(query, done, fail)
        return
    end

    -- SQLite: запрос синхронный, id новой строки берём сразу после INSERT
    local rows = sql.Query(query)

    if rows == false then
        fail(sql.LastError(), query)
        return
    end

    done(rows, isInsert(query) and sql.QueryValue("SELECT last_insert_rowid()") or nil)
end

slib.onDBReady = function(id, fn)
    if not isfunction(fn) then return end

    if not db.queue[id] then
        table.insert(db.order, id)
    end

    db.queue[id] = fn

    if db.ready then
        xpcall(fn, ErrorNoHaltWithStack)
    end
end

local function markReady()
    if db.ready then return end
    db.ready = true

    MsgC(colTag, "[slib:db] ", color_white, slib.dbIsMySQL() and "MySQL" or "SQLite", " готов\n")

    for _, id in ipairs(db.order) do
        local fn = db.queue[id]

        if fn then
            xpcall(fn, ErrorNoHaltWithStack)
        end
    end

    local pending = db.pending
    db.pending = {}

    for _, q in ipairs(pending) do
        slib.dbQuery(q[1], q[2], q[3])
    end

    hook.Run("slib.DBReady")
end

-- DarkRP вызывает DatabaseInitialized через hook.Call: хук не должен ничего возвращать,
-- иначе GM:DatabaseInitialized (создание таблиц DarkRP) не выполнится
hook.Add("DatabaseInitialized", "slib.DBReady", function()
    markReady()
end)

hook.Add("Initialize", "slib.DBReady", function()
    if not hasMySQLite() then
        markReady()
    end
end)
