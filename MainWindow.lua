local addonName, ns = ...  -- luacheck: ignore 211/addonName

ns.MainWindow = {}

local WINDOW_WIDTH = 320
local WINDOW_HEIGHT = 340
local ROW_HEIGHT = 24
local PADDING = 10

local frame, contentFrame, rows, routeBtn, routeAllBtn, shopBtn, statusText

------------------------------------------------------------------------
-- Beast row creation
------------------------------------------------------------------------

local function CreateBeastRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(WINDOW_WIDTH - PADDING * 2, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", PADDING, -(index - 1) * ROW_HEIGHT)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("LEFT", 4, 0)
    row.name:SetWidth(140)
    row.name:SetJustifyH("LEFT")

    row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.status:SetPoint("RIGHT", -4, 0)
    row.status:SetJustifyH("RIGHT")

    return row
end

------------------------------------------------------------------------
-- Window creation
------------------------------------------------------------------------

local function CreateMainFrame()
    frame = CreateFrame("Frame", "TalentedTrackerMainFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("MEDIUM")
    table.insert(UISpecialFrames, "TalentedTrackerMainFrame")

    frame.TitleText:SetText("Talented Tracker")

    -- Content area
    contentFrame = CreateFrame("Frame", nil, frame)
    contentFrame:SetPoint("TOPLEFT", frame.InsetBorderTop or frame.Inset or frame, "TOPLEFT", PADDING, -60)
    contentFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PADDING, 80)

    -- Beast rows
    rows = {}
    for i = 1, #ns.BEASTS do
        rows[i] = CreateBeastRow(contentFrame, i)
    end

    -- Status summary line
    statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PADDING + 4, 60)
    statusText:SetWidth(WINDOW_WIDTH - PADDING * 2)
    statusText:SetJustifyH("LEFT")

    -- Buttons
    routeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    routeBtn:SetSize(90, 22)
    routeBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PADDING, PADDING + 22)
    routeBtn:SetText("Route")
    routeBtn:SetScript("OnClick", function() ns.Integrations:CreateRoute(true) end)
    routeBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Plan route to beasts you can lure")
        GameTooltip:Show()
    end)
    routeBtn:SetScript("OnLeave", GameTooltip_Hide)

    routeAllBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    routeAllBtn:SetSize(90, 22)
    routeAllBtn:SetPoint("LEFT", routeBtn, "RIGHT", 4, 0)
    routeAllBtn:SetText("Route All")
    routeAllBtn:SetScript("OnClick", function() ns.Integrations:CreateRoute(false) end)
    routeAllBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Plan route to ALL unskinned beasts")
        GameTooltip:Show()
    end)
    routeAllBtn:SetScript("OnLeave", GameTooltip_Hide)

    shopBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    shopBtn:SetSize(90, 22)
    shopBtn:SetPoint("LEFT", routeAllBtn, "RIGHT", 4, 0)
    shopBtn:SetText("Shop")
    shopBtn:SetScript("OnClick", function() ns.Integrations:CreateShoppingList() end)
    shopBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Create Auctionator shopping list for lure reagents")
        GameTooltip:Show()
    end)
    shopBtn:SetScript("OnLeave", GameTooltip_Hide)

    -- Scan hint button (small text button below the main buttons)
    local scanBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    scanBtn:SetSize(WINDOW_WIDTH - PADDING * 2, 18)
    scanBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PADDING, PADDING)
    scanBtn:SetNormalFontObject("GameFontNormalSmall")
    scanBtn:SetText("Scan Recipes")
    scanBtn:SetScript("OnClick", function()
        local found = ns.RecipeCache:ScanForLureRecipes()
        if found then
            ns.addon:Print("Lure recipe data cached successfully!")
        else
            ns.addon:Print("No lure recipes found. Is your Skinning profession window open?")
        end
        ns.MainWindow:Refresh()
    end)
    scanBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Rescan skinning recipes (profession window must be open)")
        GameTooltip:Show()
    end)
    scanBtn:SetScript("OnLeave", GameTooltip_Hide)

    frame:Hide()
    return frame
end

------------------------------------------------------------------------
-- Refresh display
------------------------------------------------------------------------

function ns.MainWindow:Refresh()
    if not frame or not frame:IsShown() then return end

    local status = ns.addon:GetBeastStatus()
    local remaining = 0

    for i, entry in ipairs(status) do
        local row = rows[i]
        row.name:SetText(entry.beast.name)

        if entry.skinned then
            row.name:SetTextColor(0.5, 0.5, 0.5)
            row.status:SetText("Skinned")
            row.status:SetTextColor(0.5, 0.5, 0.5)
        else
            remaining = remaining + 1
            row.name:SetTextColor(1, 1, 1)
            if entry.hasLure then
                row.status:SetText("Have lure")
                row.status:SetTextColor(0, 1, 0)
            elseif entry.canCraft then
                row.status:SetText("Can craft")
                row.status:SetTextColor(1, 1, 0)
            else
                row.status:SetText("No recipe")
                row.status:SetTextColor(1, 0.3, 0.3)
            end
        end
    end

    if remaining == 0 then
        statusText:SetText("|cff00ff00All renowned beasts skinned for today!|r")
    else
        statusText:SetText(string.format("%d / %d remaining", remaining, #ns.BEASTS))
    end

    -- Enable/disable buttons based on state
    local hasMapzeroth = _G["Mapzeroth"] ~= nil
    local hasAuctionator = Auctionator and Auctionator.API and Auctionator.API.v1
    routeBtn:SetEnabled(hasMapzeroth and remaining > 0)
    routeAllBtn:SetEnabled(hasMapzeroth and remaining > 0)
    shopBtn:SetEnabled(hasAuctionator and remaining > 0)
end

------------------------------------------------------------------------
-- Show / Hide / Toggle
------------------------------------------------------------------------

function ns.MainWindow:Show()
    if not frame then CreateMainFrame() end
    frame:Show()
    self:Refresh()
end

function ns.MainWindow:Hide()
    if frame then frame:Hide() end
end

function ns.MainWindow:Toggle()
    if frame and frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end
