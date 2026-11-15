--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
local rp_languages = {}
local selectedLanguage = GetConVar("gmod_language"):GetString() -- Switch language by setting gmod_language to another language

function DarkRP.addLanguage(name, tbl)
	local old = rp_languages[name] or {}
	rp_languages[name] = tbl

	-- Merge the language with the translations added by DarkRP.addPhrase
	for k,v in pairs(old) do
		rp_languages[name][k] = v
	end
	LANGUAGE = rp_languages[name] -- backwards compatibility
end

function DarkRP.addPhrase(lang, name, phrase)
	rp_languages[lang] = rp_languages[lang]  or {}
	rp_languages[lang][name] = phrase
end

function DarkRP.getPhrase(name, ...)
	local langTable = rp_languages[selectedLanguage] or rp_languages.en

	if not langTable[name] then return name end

	return string.format(langTable[name] or rp_languages.en[name], ...)
end
