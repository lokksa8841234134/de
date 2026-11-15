--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ENT.Type = "anim"
ENT.Base = "workstation_base"
ENT.PrintName = "Кофемашина"
ENT.Author = "Mactavish"
ENT.Spawnable = true
ENT.AdminSpawnable = false
ENT.SortBy = "order"
ENT.CanPack = false

ENT.BluePrints = {
	["coffeecup"] = {
		name = "Кружка кофе",
		order = "a1",
		time = 48,
		sound = "gb_sfx/craft/nespresso.wav",
		products = {
			{
				type = INV_FOOD,
				class = "coffeecup",
				count = 1,
			},
		},
		componets = {
			{
				type = INV_JUNK,
				class = "coffee",
				count = 1,
			},
			{
				type = INV_FOOD,
				class = "whater",
				count = 1,
			},
		}
	}
}