--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
--[[-------------------------------------------------------------------------

We override the default fire visuals and sound by creating an entity of our own with the same name (entityflame),
which is removed immediately on creation - this is the only functionality we care for.

---------------------------------------------------------------------------]]

AddCSLuaFile()

DEFINE_BASECLASS("base_anim")

if SERVER then
	function ENT:Initialize()
		self:Remove()
	end
end