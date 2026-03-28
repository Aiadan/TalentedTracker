local addonName, ns = ...  -- luacheck: ignore 211/addonName

local LDB = LibStub("LibDataBroker-1.1")
local LDBIcon = LibStub("LibDBIcon-1.0")

local dataObj = LDB:NewDataObject("TalentedTracker", {
    type = "launcher",
    icon = "Interface\\AddOns\\TalentedTracker\\icon",
    OnClick = function(_, button)
        if button == "LeftButton" then
            ns.MainWindow:Toggle()
        end
    end,
    OnTooltipShow = function(tooltip)
        tooltip:SetText("|cFF33FF99Talented Tracker|r")
        tooltip:AddLine("Renowned beast skinning tracker", 1, 1, 1)
        tooltip:AddLine(" ")
        tooltip:AddLine("|cffaaaaaa< Left-Click >|r Toggle window", 0.2, 1, 0.2)
        tooltip:AddLine("|cffaaaaaa< Drag >|r Move button", 0.2, 1, 0.2)
    end,
})

function ns.InitMinimapButton()
    ns.db.minimap = ns.db.minimap or { hide = false }
    LDBIcon:Register("TalentedTracker", dataObj, ns.db.minimap)
end
