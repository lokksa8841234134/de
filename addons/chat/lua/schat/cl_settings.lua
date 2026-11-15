--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
local Settings = {
	width = 550,
	height = 300,
	font_size = 18,
	allow_any_url = false
}

function Settings:ValidateInteger(n, min, max)
	return math.Round( math.Clamp(tonumber(n), min, max) )
end

function Settings:ValidateColor(clr)
	return Color(
		self:ValidateInteger(clr.r or 255, 0, 255),
		self:ValidateInteger(clr.g or 255, 0, 255),
		self:ValidateInteger(clr.b or 255, 0, 255),
		self:ValidateInteger(clr.a or 255, 0, 255)
	)
end

function Settings:GetDefaultPosition()
	return 15, ScrH() - 405
end

function Settings:GetDefaultSize()
	return 550, 300
end

function Settings:SetWhitelistEnabled(enabled)
	self.allow_any_url = not enabled

	if enabled then
		SChat.InternalMessage('Whitelist', 'Only load images from trusted websites.')
	else
		SChat.InternalMessage('Whitelist', 'Load images from any website.')
	end
end

function Settings:GetEmojiInfo(id)
	for _, cat in ipairs(self.emojiCategories) do
		for _, v in ipairs(cat.emojis) do

			if type(v) == 'string' then
				if id == v then
					return 'materials/icon72/' .. id .. '.png'
				end
			else
				if id == v[1] then
					return v[2], true
				end
			end

		end
	end
end

Settings.emojiCategories = {
	-- {category = 'Places', emojis = {
	-- 	'airplane',
	-- 	'ambulance',
	-- 	'barber',
	-- 	'beginner',
	-- 	'bike',
	-- 	'blue_car',
	-- 	'boat',
	-- 	'bullettrain_front',
	-- 	'bus',
	-- 	'car',
	-- 	'checkered_flag',
	-- 	'helicopter',
	-- 	'moyai',
	-- 	'rainbow',
	-- 	'rocket',
	-- 	'stars',
	-- 	'traffic_light',
	-- 	'vertical_traffic_light',
	-- 	'warning'
	-- }}
}

SChat.Settings = Settings