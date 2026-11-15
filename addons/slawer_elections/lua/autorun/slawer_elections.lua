--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
Slawer = Slawer or {}
Slawer.Elections = Slawer.Elections or {}
Slawer.Elections.CFG = Slawer.Elections.CFG or {}
Slawer.Elections.Lang = Slawer.Elections.Lang or {}
Slawer.Elections.Candidates = Slawer.Elections.Candidates or {}

SetGlobalInt("Slawer.Elections:CurrentState", 0)

local strMainDir = "slawer_elections/"

local function loadDirectory( strDir, strFileType )
    local tblFiles = file.Find( strMainDir .. strDir .. "*", "LUA" )

    for k, v in pairs( tblFiles ) do
        if strFileType == "server" then
            if SERVER then include( strMainDir .. strDir .. v ) end
        elseif strFileType == "client" then
            if SERVER then
                AddCSLuaFile( strMainDir .. strDir .. v )
            else
                include( strMainDir .. strDir .. v )
            end
        elseif strFileType == "shared" then
            if SERVER then AddCSLuaFile( strMainDir .. strDir .. v ) end
            include( strMainDir .. strDir .. v )
        end
    end
end

loadDirectory( "", "shared" )

function Slawer.Elections:L(strTag)
    return Slawer.Elections.Lang[Slawer.Elections.CFG.Language][strTag] or strTag
end

loadDirectory( "shared/", "shared" )
loadDirectory( "languages/", "shared" )
loadDirectory( "client/", "client" )
loadDirectory( "client/vgui/", "client" )
loadDirectory( "client/vgui/elements/", "client" )
loadDirectory( "server/", "server" )