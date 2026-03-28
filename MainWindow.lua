local addonName, ns = ...  -- luacheck: ignore 211/addonName

ns.MainWindow = {}

local WINDOW_WIDTH = 300
local ROW_HEIGHT = 22
local PADDING = 10

local frame, rows, routeBtn, routeAllBtn, shopBtn, stopBtn, skipBtn, statusText, navText, includeSkinnedCB

------------------------------------------------------------------------
-- Beast row creation
------------------------------------------------------------------------

local function CreateBeastRow(parent, _, yOffset)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(WINDOW_WIDTH - PADDING * 2, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -yOffset)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("LEFT", 4, 0)
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
    -- Calculate height from content
    -- Title bar ~24, inset top ~4, beast rows, status line, checkbox, nav text, buttons, scan button, padding
    local beastAreaHeight = #ns.BEASTS * ROW_HEIGHT
    local bottomAreaHeight = 14 + 4 + 22 + 4 + 22 + 4 + 14 + 4 + 22 + 4 + 18 + PADDING
    -- status(14) + gap + cb1(22) + gap + cb2(22) + gap + navText(14) + gap + buttons(22) + gap + scan(18) + pad
    local WINDOW_HEIGHT = 28 + 4 + beastAreaHeight + 4 + bottomAreaHeight

    frame = CreateFrame("Frame", "TalentedTrackerMainFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    local pos = ns.db.windowPos
    if pos then
        frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        frame:SetPoint("CENTER")
    end
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        ns.db.windowPos = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    frame:SetFrameStrata("MEDIUM")
    table.insert(UISpecialFrames, "TalentedTrackerMainFrame")

    frame.TitleText:SetText("Talented Tracker")

    -- Content area for beast rows, anchored below title bar
    local contentFrame = CreateFrame("Frame", nil, frame)
    contentFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -28)
    contentFrame:SetSize(WINDOW_WIDTH - PADDING * 2, beastAreaHeight)

    -- Beast rows
    rows = {}
    for i = 1, #ns.BEASTS do
        rows[i] = CreateBeastRow(contentFrame, i, (i - 1) * ROW_HEIGHT)
    end

    -- Everything below beast rows anchors from the bottom up
    -- Bottom-most: Scan Recipes button
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
    scanBtn:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        GameTooltip:SetText("Rescan skinning recipes (profession window must be open)")
        GameTooltip:Show()
    end)
    scanBtn:SetScript("OnLeave", GameTooltip_Hide)

    -- Action buttons row (above scan)
    routeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    routeBtn:SetSize(86, 22)
    routeBtn:SetPoint("BOTTOMLEFT", scanBtn, "TOPLEFT", 0, 4)
    routeBtn:SetText("Route")
    routeBtn:SetScript("OnClick", function() ns.Integrations:CreateRoute(true) end)
    routeBtn:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        GameTooltip:SetText("Plan route to beasts you can lure")
        GameTooltip:Show()
    end)
    routeBtn:SetScript("OnLeave", GameTooltip_Hide)

    routeAllBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    routeAllBtn:SetSize(86, 22)
    routeAllBtn:SetPoint("LEFT", routeBtn, "RIGHT", 4, 0)
    routeAllBtn:SetText("Route All")
    routeAllBtn:SetScript("OnClick", function() ns.Integrations:CreateRoute(false) end)
    routeAllBtn:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        GameTooltip:SetText("Plan route to ALL unskinned beasts")
        GameTooltip:Show()
    end)
    routeAllBtn:SetScript("OnLeave", GameTooltip_Hide)

    shopBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    shopBtn:SetSize(86, 22)
    shopBtn:SetPoint("LEFT", routeAllBtn, "RIGHT", 4, 0)
    shopBtn:SetText("Shop")
    shopBtn:SetScript("OnClick", function() ns.Integrations:CreateShoppingList() end)
    shopBtn:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        GameTooltip:SetText("Create Auctionator shopping list for lure reagents")
        GameTooltip:Show()
    end)
    shopBtn:SetScript("OnLeave", GameTooltip_Hide)

    stopBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    stopBtn:SetSize(86, 22)
    stopBtn:SetPoint("LEFT", routeAllBtn, "RIGHT", 4, 0)
    stopBtn:SetText("Stop")
    stopBtn:SetScript("OnClick", function()
        ns.Routing:StopNavigation()
        ns.addon:Print("Route cancelled.")
        ns.MainWindow:Refresh()
    end)
    stopBtn:Hide()

    skipBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    skipBtn:SetSize(86, 22)
    skipBtn:SetPoint("LEFT", routeBtn, "RIGHT", 4, 0)
    skipBtn:SetText("Skip")
    skipBtn:SetScript("OnClick", function()
        ns.Routing:SkipCurrentStep()
    end)
    skipBtn:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        GameTooltip:SetText("Skip current beast and re-plan route")
        GameTooltip:Show()
    end)
    skipBtn:SetScript("OnLeave", GameTooltip_Hide)
    skipBtn:Hide()

    -- Nav text (above buttons)
    navText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    navText:SetPoint("BOTTOMLEFT", routeBtn, "TOPLEFT", 2, 4)
    navText:SetWidth(WINDOW_WIDTH - PADDING * 2)
    navText:SetJustifyH("LEFT")
    navText:SetTextColor(0, 0.8, 1)
    navText:Hide()

    -- Checkboxes (above nav text)
    local endAtSMCB = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    endAtSMCB:SetSize(22, 22)
    endAtSMCB:SetPoint("BOTTOMLEFT", routeBtn, "TOPLEFT", -2, 18)
    endAtSMCB:SetChecked(false)
    endAtSMCB:SetScript("OnClick", function(cb)
        ns.endAtSilvermoon = cb:GetChecked()
    end)
    local endAtSMLabel = endAtSMCB:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    endAtSMLabel:SetPoint("LEFT", endAtSMCB, "RIGHT", 2, 0)
    endAtSMLabel:SetText("End at Silvermoon")

    includeSkinnedCB = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    includeSkinnedCB:SetSize(22, 22)
    includeSkinnedCB:SetPoint("BOTTOMLEFT", endAtSMCB, "TOPLEFT", 0, 4)
    includeSkinnedCB:SetChecked(false)
    includeSkinnedCB:SetScript("OnClick", function(cb)
        ns.includeSkinned = cb:GetChecked()
        ns.MainWindow:Refresh()
    end)
    local cbLabel = includeSkinnedCB:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cbLabel:SetPoint("LEFT", includeSkinnedCB, "RIGHT", 2, 0)
    cbLabel:SetText("Include skinned beasts")

    -- Status summary (above checkboxes)
    statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("BOTTOMLEFT", includeSkinnedCB, "TOPLEFT", 4, 2)
    statusText:SetWidth(WINDOW_WIDTH - PADDING * 2)
    statusText:SetJustifyH("LEFT")

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

    -- Navigation state
    local navigating = ns.Routing:IsNavigating()
    if navigating then
        local step, idx, total = ns.Routing:GetCurrentStep()
        if step then
            navText:SetText(string.format("Navigating: %d/%d — %s", idx, total, step.name))
        end
        navText:Show()
        -- During nav: Route (disabled) | Skip | Stop
        routeBtn:SetEnabled(false)
        routeAllBtn:Hide()
        shopBtn:Hide()
        skipBtn:Show()
        stopBtn:Show()
    else
        navText:Hide()
        -- Normal: Route | Route All | Shop
        routeAllBtn:Show()
        shopBtn:Show()
        skipBtn:Hide()
        stopBtn:Hide()
        local hasAuctionator = Auctionator and Auctionator.API and Auctionator.API.v1
        local canRoute = (remaining > 0 or ns.includeSkinned)
        routeBtn:SetEnabled(canRoute)
        routeAllBtn:SetEnabled(canRoute)
        shopBtn:SetEnabled(hasAuctionator and (remaining > 0 or ns.includeSkinned))
    end
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
