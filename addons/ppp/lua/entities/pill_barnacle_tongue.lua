--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
AddCSLuaFile()
ENT.Base = "base_nextbot"
ENT.Spawnable = true
ENT.PhysgunDisabled = false
ENT.PrintName = "Roomba"
ENT.Purpose = "Your personal robot cleaner"

if CLIENT then
    language.Add("npc_roomba", ENT.PrintName)
end

function ENT:Initialize()
    self:SetModel("models/props_phx/games/chess/black_dama.mdl")

    if (SERVER) then
        self:SetMaxHealth(10)
        self:SetHealth(10)
        self:DrawShadow(true)
        self:SetUseType(SIMPLE_USE)
    end
end

function ENT:RunBehaviour()
    while (true) do
        self.loco:SetDesiredSpeed(30)
        self:StartLoopingSound("vacum.mp3")
        --self:EmitSound("vacum.mp3",120,101,1,2,0,1)
        self:MoveToPos(self:GetPos() + Vector(math.Rand(-1, 1), math.Rand(-1, 1), 0) * 200) -- this took me a bit

        local pos = self:FindSpot("random", {
            type = 'hiding',
            radius = 5000
        })

        if (pos) then
            self.loco:SetDesiredSpeed(30) -- run speed
            self:MoveToPos(pos)
        end

        coroutine.yield()
    end
end

function ENT:OnKilled(dmginfo)
    hook.Call("OnNPCKilled", GAMEMODE, self, dmginfo:GetAttacker(), dmginfo:GetInflictor())
    self:Remove()
    local explosion = ents.Create("env_explosion") -- Explosion time!
    explosion:SetPos(self:GetPos())
    explosion:Spawn()
    explosion:SetKeyValue("iMagnitude", "50")
    explosion:Fire("Explode", 0, 0)
end

function ENT:OnRemove()
    self:StopSound("vacum.mp3")
end

-- you have no idea how much this took me to work for some reason
list.Set("NPC", "npc_roomba", {
    Name = "Roomba",
    Class = "npc_roomba",
    Category = "Roombas"
})