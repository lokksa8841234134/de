--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
--[[---------------------------------------------------------------------------
	Настройки базы данных DarkRP (только сервер, клиенту не отправляется)

	По умолчанию данные хранятся в SQLite (garrysmod/sv.db) - ничего настраивать не нужно.
	Для MySQL: установите модуль mysqloo или tmysql4 в garrysmod/lua/bin,
	укажите данные подключения и включите EnableMySQL.
	Если модуль не установлен, сервер предупредит в консоли и останется на SQLite.
---------------------------------------------------------------------------]]
RP_MySQLConfig = RP_MySQLConfig or {}

RP_MySQLConfig.EnableMySQL = false -- true - использовать MySQL вместо SQLite
RP_MySQLConfig.Host = "127.0.0.1" -- адрес сервера MySQL
RP_MySQLConfig.Username = "user" -- пользователь
RP_MySQLConfig.Password = "password" -- пароль
RP_MySQLConfig.Database_name = "DarkRP" -- имя базы данных
RP_MySQLConfig.Database_port = 3306 -- порт
RP_MySQLConfig.Preferred_module = "mysqloo" -- "mysqloo" или "tmysql4"
RP_MySQLConfig.MultiStatements = false -- несколько запросов в одном (только mysqloo)
