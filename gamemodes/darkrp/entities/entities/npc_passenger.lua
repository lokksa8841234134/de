--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
AddCSLuaFile()

ENT.Base = "base_nextbot"
ENT.Spawnable = false

local rand_standing = {
	"pose_standing_01",
	"pose_standing_02",
	"menu_combine",
	"idle_suitcase"
}

function ENT:Initialize()
	self:SetModel( "models/cityrp/pm/normal/male_02.mdl" )
	self:ResetSequence( "pose_standing_01" )
	self.standpos = self.standpos or rand_standing[math.random(#rand_standing)]
	self:SetCollisionGroup(COLLISION_GROUP_WORLD)
end

function ENT:RunBehaviour()

	while true do

		if self.simf and IsValid(self.simf) and self.simf.IsSimfphyscar then
			self:StartActivity( ACT_IDLE )
			self:PlaySequenceAndWait( self.standpos ) -- Sit on the floor

			if not IsValid(self.simf) then
				continue
			end

			local pos = self.simf:GetPos()

			if self.pmdata.enp then
				pos = self.simf:LocalToWorld(self.pmdata.enp)
			end

			if pos and pos:DistToSqr(self:GetPos()) < (self.pmdata.enp and 200000 or 110000) and IsValid(self.simf) and self.simf.ForwardSpeed and self.simf.ForwardSpeed < 100 then
				self:StartActivity( ACT_WALK ) -- run anim
				self.loco:SetDesiredSpeed( 100 )
				self:ResetSequence( "walk_all" )
				self:MoveToPos( pos, {tolerance = 85} ) -- move to position (yielding)
				self:StartActivity( ACT_IDLE ) -- when we finished, go into the idle anim
				self:ResetSequence( "idle_all_01" )
				coroutine.wait(0.1)
				if not self.pmdata.enp then
					self:AddGestureSequence( self:LookupSequence("gesture_item_drop") )
					coroutine.wait(1)
					self:ResetSequence( "idle_all_01" )
					if IsValid(self.simf.mqsowner) then
						MQS.UpdateObjective(self.simf.mqsowner)
					end
				end
				if IsValid(self.simf) then
					self.simf:SetCLPass(self.pmdata)
				end
				self:Remove()
			else
				coroutine.wait(0.5)
			end
		else
			self:StartActivity( ACT_IDLE )
			self:ResetSequence( "idle_all_01" )
			local pos = self:FindSpot( "random", { type = "hiding", radius = 5000 } )
			if ( pos ) then
				self:StartActivity( ACT_WALK )
				self.loco:SetDesiredSpeed( 90 )
				self:ResetSequence( "walk_all" )
				self:MoveToPos( pos )
				self:ResetSequence( "idle_all_angry" ) -- play a fear animation
				self:StartActivity( ACT_IDLE ) -- when we finished, go into the idle anim
				self:Remove()
			end
		end

		coroutine.yield()
	end

end

function ENT:OnKilled( dmginfo )
	dmginfo:SetDamage(0)
end
--
-- List the NPC as spawnable
--
list.Set( "NPC", "npc_passenger", {
	Name = "Passenger NPC",
	Class = "npc_passenger",
	Category = "Nextbot"
} )
