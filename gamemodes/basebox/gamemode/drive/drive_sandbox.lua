--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
AddCSLuaFile()

--
-- Режим управления сущностью из контекстного меню (свойство "Drive").
-- В DarkRP GM:CanDrive запрещает его игрокам, но режим должен быть
-- зарегистрирован: shared.lua подключает этот файл на обеих сторонах.
--
-- Управление: WASD/пробел/Ctrl — полёт, Shift — быстрее,
-- колесо мыши — дистанция камеры, зажатый R — вращение сущности мышью,
-- E — выйти из режима.
--

DEFINE_BASECLASS( "drive_base" )

drive.Register( "drive_sandbox",
{
	--
	-- Called on creation
	--
	Init = function( self )

		self.CameraDist = 4
		self.CameraDistVel = 0.1

	end,

	--
	-- Calculates the view when driving the entity
	--
	CalcView = function( self, view )

		local idealdist = math.max( 10, self.Entity:BoundingRadius() ) * self.CameraDist

		self:CalcView_ThirdPerson( view, idealdist, 2, { self.Entity } )

		view.angles.roll = 0

	end,

	--
	-- Clientside only: camera zoom and frozen view while rotating
	--
	SetupControls = function( self, cmd )

		if ( cmd:KeyDown( IN_RELOAD ) ) then

			self.CameraForceViewAngles = self.CameraForceViewAngles or cmd:GetViewAngles()
			cmd:SetViewAngles( self.CameraForceViewAngles )

		else

			self.CameraForceViewAngles = nil

		end

		self.CameraDistVel = self.CameraDistVel + cmd:GetMouseWheel() * -0.5

		self.CameraDist = self.CameraDist + self.CameraDistVel * FrameTime()
		self.CameraDist = math.Clamp( self.CameraDist, 2, 20 )
		self.CameraDistVel = math.Approach( self.CameraDistVel, 0, self.CameraDistVel * FrameTime() * 2 )

	end,

	--
	-- Called before each move. Fill mv with the entity state.
	--
	StartMove = function( self, mv, cmd )

		self.Player:SetObserverMode( OBS_MODE_CHASE )

		if ( mv:KeyReleased( IN_USE ) ) then
			self:Stop()
		end

		mv:SetOrigin( self.Entity:GetNetworkOrigin() )
		mv:SetVelocity( self.Entity:GetAbsVelocity() )
		mv:SetMoveAngles( mv:GetAngles() )

		local entang = self.Entity:GetAngles()

		--
		-- Holding reload: the mouse rotates the entity around the camera axes
		--
		if ( mv:KeyDown( IN_RELOAD ) ) then

			local camang = mv:GetAngles()

			entang:RotateAroundAxis( camang:Up(), cmd:GetMouseX() * 0.25 )
			entang:RotateAroundAxis( camang:Right(), cmd:GetMouseY() * 0.25 )

		end

		self.EntityAngles = entang

	end,

	--
	-- Runs the actual move. Only mv should be changed here.
	--
	Move = function( self, mv )

		local speed = 0.0005 * FrameTime()
		if ( mv:KeyDown( IN_SPEED ) ) then speed = 0.005 * FrameTime() end

		local ang = mv:GetMoveAngles()
		local pos = mv:GetOrigin()
		local vel = mv:GetVelocity()

		vel = vel + ang:Forward() * mv:GetForwardSpeed() * speed
		vel = vel + ang:Right() * mv:GetSideSpeed() * speed
		vel = vel + ang:Up() * mv:GetUpSpeed() * speed

		if ( math.abs( mv:GetForwardSpeed() ) + math.abs( mv:GetSideSpeed() ) + math.abs( mv:GetUpSpeed() ) < 0.1 ) then
			vel = vel * 0.90
		else
			vel = vel * 0.99
		end

		pos = pos + vel

		mv:SetVelocity( vel )
		mv:SetOrigin( pos )

	end,

	--
	-- The move is finished. Apply mv to the entity.
	--
	FinishMove = function( self, mv )

		self.Entity:SetNetworkOrigin( mv:GetOrigin() )
		self.Entity:SetAbsVelocity( mv:GetVelocity() )

		if ( self.EntityAngles ) then
			self.Entity:SetAngles( self.EntityAngles )
		end

		local phys = self.Entity:GetPhysicsObject()

		if ( SERVER && IsValid( phys ) ) then

			phys:EnableMotion( true )
			phys:SetPos( mv:GetOrigin() )
			phys:SetAngles( self.Entity:GetAngles() )
			phys:Wake()
			phys:EnableMotion( false )

		end

	end

}, "drive_base" )
