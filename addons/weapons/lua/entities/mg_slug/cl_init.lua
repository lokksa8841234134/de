--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
include("shared.lua")

local base = baseclass.Get(ENT.Base)

function ENT:DrawTracer()
    if (GetViewEntity() == self:GetOwner()) then
        base.DrawTracer(self)
    end
end