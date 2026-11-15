--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
function Slawer.Elections:DisplayPopup()
    if IsValid(Slawer.Elections.Popup) then return end
    Slawer.Elections.Popup = vgui.Create("Slawer.Elections:Popup")
end

function Slawer.Elections:ClosePopup()
    if IsValid(Slawer.Elections.Popup) then
        Slawer.Elections.Popup:Remove()
    end
end

function Slawer.Elections:ShowVotingMenu()
    if IsValid(Slawer.Elections.VotingMenu) then
        Slawer.Elections.VotingMenu:Remove()
    end

    Slawer.Elections.VotingMenu = vgui.Create("Slawer.Elections:Voting")
    Slawer.Elections.VotingMenu:Populate(Slawer.Elections.Candidates)
end