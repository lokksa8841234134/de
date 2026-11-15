--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
sAdmin = sAdmin or {}
sAdmin.permissions = sAdmin.permissions or {}
sAdmin.usergroups = sAdmin.usergroups or {}
sAdmin.base_Perms = sAdmin.base_Perms or {}
local nameToKey, isBasePerm = {}, {}

sAdmin.registerPermission = function(name, category, base, type)
	if nameToKey[name] then return end

	local k = table.insert(base and sAdmin.base_Perms or sAdmin.permissions, {
		name = name,
		category = category,
		type = type
	})

	nameToKey[name] = k

	if base then
		isBasePerm[name] = true
	end
end

sAdmin.getPermissiondata = function(name)
	if sAdmin.permissions[nameToKey[name]] and sAdmin.permissions[nameToKey[name]].name == name then return sAdmin.permissions[nameToKey[name]] end
	if sAdmin.base_Perms[nameToKey[name]] and sAdmin.base_Perms[nameToKey[name]].name == name then return sAdmin.base_Perms[nameToKey[name]] end

	return false
end

sAdmin.getPermissionsKeys = function(name) return nameToKey end

sAdmin.hasPermission = function(ply, name)
	if not IsValid(ply) then return true end
	local sid64 = ply:SteamID64()
	local usergroup = sAdmin.playerData[sid64] and sAdmin.playerData[sid64].rank ~= "" and sAdmin.playerData[sid64].rank or ply:GetUserGroup()
	local perms = sAdmin.usergroups[usergroup] and sAdmin.usergroups[usergroup].permissions or {}
	local result = tonumber(perms[name]) or tobool(perms[name]) or (tobool(perms["all_perms"] and not isBasePerm[name]))
	if not result and sAdmin.config["super_users"][sid64] then return true end

	return result
end

sAdmin.FindByPerm = function(perm)
	local tbl = {}

	for k, v in pairs(slib.playerCache) do
		if sAdmin.hasPermission(v, perm) or sAdmin.config["super_users"][v:SteamID64()] then
			table.insert(tbl, v)
		end
	end

	return tbl
end

sAdmin.logPerm = function()
	return sAdmin.FindByPerm("can_log")
end

sAdmin.registerPermission("immunity", nil, true, 0)
sAdmin.registerPermission("all_perms", nil, true)
sAdmin.registerPermission("manage_perms", nil, true)
sAdmin.registerPermission("menu", nil, true)
sAdmin.registerPermission("silent", nil, true)
--sAdmin.registerPermission("password_protected", nil, true)
sAdmin.registerPermission("is_staff", nil, true)
sAdmin.registerPermission("rslots", nil, true)
sAdmin.registerPermission("weapon_upgrade", nil, true)
sAdmin.registerPermission("phys_players", nil, true)
sAdmin.registerPermission("propspawn", nil, true)
sAdmin.registerPermission("can_log", nil, true)
sAdmin.registerPermission("FSpectate", nil, true)
sAdmin.registerPermission("FSpectateTeleport", nil, true)
sAdmin.registerPermission("restore_create", "Restore")
sAdmin.registerPermission("restore_approve", "Restore")