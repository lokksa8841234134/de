--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
Glac.RegisterConfig("case_id1", function()
	Glac.AddCase("case_id1", {
		Name = "Манетрон",
		icon = SERVER and "" or Material("gmodla/f4/poster/muni1.png", "smooth"),
		icon_size = {700, 1000},
		desc = "игровая валюта",
		details = "Получи шанс выиграть от $2.500 до $500.000 игровой валюты",
		Category = "Cases",
		Price = 250,
	})

	Glac.AddDrop("case_id1", "money", 200)
	Glac.AddDrop("case_id1", "money1", 175)
	Glac.AddDrop("case_id1", "money2", 150)
	Glac.AddDrop("case_id1", "money3", 100)
	Glac.AddDrop("case_id1", "money4", 50)
	Glac.AddDrop("case_id1", "money4.1", 50)
	Glac.AddDrop("case_id1", "money5", 1)
end)
