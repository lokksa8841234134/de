--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
AddCSLuaFile()
ENT.Type = "ai"
ENT.Base = "base_entity"

function ENT:Initialize()
    self:SetRenderMode(RENDERMODE_TRANSALPHA)
end

function ENT:Draw()
    self:DrawModel()
end

function ENT:DrawTranslucent()
    self:Draw()
end
