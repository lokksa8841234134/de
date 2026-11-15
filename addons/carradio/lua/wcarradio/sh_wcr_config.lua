--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
-- List of car models in which carradio is disabled
wyozicr.DisabledModels = {"path/to/carmodel.mdl"}

-- Whether we should override stations below with Wyozi Home Kit: Media Pack stations, if they exist
wyozicr.UseHomeKitStations = true

-- List of stations. See below for instructions
wyozicr.Stations = {
	{
		Name = "First Amendment Tracks",
		Link = "http://194.67.93.33:8010/radio.mp3",
		Icon = "https://macnco.one/cityrp/radio/com/1.png"
	},
	{
		Name = "Outlet Forkers FM",
		Link = "http://194.67.93.33:8020/radio.mp3",
		Icon = "https://macnco.one/cityrp/radio/com/2.png"
	},
	{
		Name = "Let's Rock New York",
		Link = "http://194.67.93.33:8030/radio.mp3",
		Icon = "https://macnco.one/cityrp/radio/com/3.png"
	},
	{
		Name = "Neonlight 98.3",
		Link = "http://194.67.93.33:8050/radio.mp3",
		Icon = "https://macnco.one/cityrp/radio/com/4.png"
	},
	{
		Name = "Protospective",
		Link = "http://194.67.93.33:8040/radio.mp3",
		Icon = "https://macnco.one/cityrp/radio/com/5.png"
	},
	{
		Name = "Noire.FM",
		Link = "http://194.67.93.33:8000/radio.mp3",
		Icon = "https://macnco.one/cityrp/radio/com/6.png"
	},
	{
		Name = "RedNeck Voice",
		Link = "http://194.67.93.33:8060/radio.mp3",
		Icon = "https://macnco.one/cityrp/radio/com/7.png"
	},
}