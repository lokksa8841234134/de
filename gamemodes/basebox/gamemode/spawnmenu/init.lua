--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
AddCSLuaFile( "basebox/gamemode/spawnmenu/controls/manifest.lua" )
AddCSLuaFile( "basebox/gamemode/spawnmenu/controls/control_presets.lua" )
AddCSLuaFile( "basebox/gamemode/spawnmenu/controls/preset_editor.lua" )
AddCSLuaFile( "basebox/gamemode/spawnmenu/controls/ropematerial.lua" )
AddCSLuaFile( "basebox/gamemode/spawnmenu/controls/ctrlnumpad.lua" )
AddCSLuaFile( "basebox/gamemode/spawnmenu/controls/ctrlcolor.lua" )
AddCSLuaFile( "basebox/gamemode/spawnmenu/controls/ctrllistbox.lua" )
AddCSLuaFile( "basebox/gamemode/spawnmenu/contextmenu.lua" )
AddCSLuaFile( "basebox/gamemode/spawnmenu/creationmenu.lua" )
AddCSLuaFile( "basebox/gamemode/spawnmenu/spawnmenu.lua" )
AddCSLuaFile( "basebox/gamemode/spawnmenu/toolmenu.lua" )
AddCSLuaFile( "basebox/gamemode/spawnmenu/controlpanel.lua" )
AddCSLuaFile( "basebox/gamemode/spawnmenu/toolpanel.lua" )
AddCSLuaFile( "basebox/gamemode/spawnmenu/creationmenu/manifest.lua" )
AddCSLuaFile( "basebox/gamemode/spawnmenu/creationmenu/content/content.lua" )
AddCSLuaFile( "basebox/gamemode/spawnmenu/creationmenu/content/contentcontainer.lua" )
AddCSLuaFile( "basebox/gamemode/spawnmenu/creationmenu/content/contentheader.lua" )
AddCSLuaFile( "basebox/gamemode/spawnmenu/creationmenu/content/contenticon.lua" )
AddCSLuaFile( "basebox/gamemode/spawnmenu/creationmenu/content/contentsearch.lua" )
AddCSLuaFile( "basebox/gamemode/spawnmenu/creationmenu/content/contentsidebar.lua" )
AddCSLuaFile( "basebox/gamemode/spawnmenu/creationmenu/content/contentsidebartoolbox.lua" )
AddCSLuaFile( "basebox/gamemode/spawnmenu/creationmenu/content/postprocessicon.lua" )
AddCSLuaFile( "basebox/gamemode/spawnmenu/creationmenu/content/contenttypes/addonprops.lua" )
AddCSLuaFile( "basebox/gamemode/spawnmenu/creationmenu/content/contenttypes/custom.lua" )
AddCSLuaFile( "basebox/gamemode/spawnmenu/creationmenu/content/contenttypes/entities.lua" )
AddCSLuaFile( "basebox/gamemode/spawnmenu/creationmenu/content/contenttypes/gameprops.lua" )
AddCSLuaFile( "basebox/gamemode/spawnmenu/creationmenu/content/contenttypes/npcs.lua" )
AddCSLuaFile( "basebox/gamemode/spawnmenu/creationmenu/content/contenttypes/postprocess.lua" )
AddCSLuaFile( "basebox/gamemode/spawnmenu/creationmenu/content/contenttypes/weapons.lua" )
AddCSLuaFile( "basebox/gamemode/spawnmenu/creationmenu/content/contenttypes/vehicles.lua" )
AddCSLuaFile( "basebox/gamemode/spawnmenu/creationmenu/content/contenttypes/dupes.lua" )

--
-- Список разрешённых пропов (allowed_spawnlist) нужен и серверу:
-- по нему GM:PlayerSpawnProp в DarkRP проверяет модели у игроков без права "propspawn".
-- Файл содержит только таблицу, клиентских вызовов в нём нет.
--
include( "creationmenu/content/contenttypes/dupes.lua" )
