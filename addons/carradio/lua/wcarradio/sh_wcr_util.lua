--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
local function isTracked(cls, ent)
	return cls == "prop_vehicle_jeep" or cls == "prop_vehicle_jeep_old" or (cls == "spawned_junk" and ent.Geteclass and ent:Geteclass() == "radio")
end

local carents = setmetatable({}, {
	__mode = "v"
})

for _, e in pairs(ents.GetAll()) do
	if isTracked(e:GetClass(), e) then
		table.insert(carents, e)
	end
end

hook.Add(SERVER and "OnEntityCreated" or "NetworkEntityCreated", "CarRadio_CarTracker", function(e)
	if isTracked(e:GetClass(), e) then
		table.insert(carents, e)
	end
end)

hook.Add("EntityRemoved", "CarRadio_CarTracker", function(e)
	if isTracked(e:GetClass(), e) then
		table.RemoveByValue(carents, e)
	end
end)

function wyozicr.GetCarEnts()
	return carents
end