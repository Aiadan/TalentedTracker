local addonName, ns = ...  -- luacheck: ignore 211/addonName

local SIXTH_SENSE_NAME = "Sixth Sense"
local PROXIMITY_THRESHOLD = 200 -- yards, generous since debuff already confirms location

local button, craftButton
local activeBeast = nil

------------------------------------------------------------------------
-- Find which beast we're near based on proximity
------------------------------------------------------------------------

local function FindNearestBeast()
    local playerMapID = C_Map.GetBestMapForUnit("player")
    if not playerMapID then return nil end
    local playerPos = C_Map.GetPlayerMapPosition(playerMapID, "player")
    if not playerPos then return nil end

    local bestDist = PROXIMITY_THRESHOLD
    local bestBeast = nil

    for _, beast in ipairs(ns.BEASTS) do
        if beast.mapID == playerMapID then
            local dist = ns.Routing:WorldDistance(playerMapID, playerPos.x, playerPos.y,
                                                   beast.mapID, beast.x, beast.y)
            if dist < bestDist then
                bestDist = dist
                bestBeast = beast
            end
        end
    end

    return bestBeast
end

------------------------------------------------------------------------
-- Create the secure action button (for using lures)
------------------------------------------------------------------------

local function CreateLureButton()
    button = CreateFrame("Button", "TalentedTrackerLureButton", UIParent, "SecureActionButtonTemplate")
    button:SetSize(48, 48)
    button:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
    button:SetMovable(true)
    button:SetClampedToScreen(true)
    button:RegisterForDrag("LeftButton")
    button:RegisterForClicks("AnyUp", "AnyDown")

    button.icon = button:CreateTexture(nil, "BACKGROUND")
    button.icon:SetAllPoints(true)

    local ht = button:CreateTexture(nil, "HIGHLIGHT")
    ht:SetAllPoints(true)
    ht:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    ht:SetBlendMode("ADD")

    button:SetScript("OnDragStart", button.StartMoving)
    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        ns.db.lureButtonPos = { point = point, relPoint = relPoint, x = x, y = y }
    end)

    button:SetScript("OnEnter", function(self)
        if activeBeast then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Place lure for " .. activeBeast.name)
            GameTooltip:AddLine(activeBeast.lureName, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)

    local pos = ns.db.lureButtonPos
    if pos then
        button:ClearAllPoints()
        button:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    end

    button:Hide()
    return button
end

------------------------------------------------------------------------
-- Create the craft button (for crafting lures when we don't have one)
------------------------------------------------------------------------

local function CreateCraftButton()
    craftButton = CreateFrame("Button", "TalentedTrackerCraftButton", UIParent)
    craftButton:SetSize(48, 48)
    craftButton:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
    craftButton:SetMovable(true)
    craftButton:SetClampedToScreen(true)
    craftButton:RegisterForDrag("LeftButton")

    craftButton.icon = craftButton:CreateTexture(nil, "BACKGROUND")
    craftButton.icon:SetAllPoints(true)

    local ht = craftButton:CreateTexture(nil, "HIGHLIGHT")
    ht:SetAllPoints(true)
    ht:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    ht:SetBlendMode("ADD")

    craftButton:SetScript("OnDragStart", craftButton.StartMoving)
    craftButton:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        ns.db.lureButtonPos = { point = point, relPoint = relPoint, x = x, y = y }
    end)

    craftButton:SetScript("OnEnter", function(self)
        if activeBeast then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Open recipe for " .. activeBeast.name)
            GameTooltip:AddLine(activeBeast.lureName, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    craftButton:SetScript("OnLeave", GameTooltip_Hide)

    craftButton:SetScript("OnClick", function()
        if not activeBeast then return end
        local recipeID = ns.RecipeCache:GetRecipeID(activeBeast.lureItemID)
        if recipeID then
            C_TradeSkillUI.OpenRecipe(recipeID)
        else
            ns.addon:Print("Recipe not cached. Open your Skinning profession window first.")
        end
    end)

    local pos = ns.db.lureButtonPos
    if pos then
        craftButton:ClearAllPoints()
        craftButton:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    end

    craftButton:Hide()
    return craftButton
end

------------------------------------------------------------------------
-- Update button state based on current beast and inventory
------------------------------------------------------------------------

local function UpdateButtonIcon(btn, itemID)
    local icon = C_Item.GetItemIconByID(itemID)
    if icon and btn.icon then
        btn.icon:SetTexture(icon)
    end
end

local function ShowLureButton(beast)
    if not button then CreateLureButton() end
    if not craftButton then CreateCraftButton() end

    activeBeast = beast
    local hasLure = C_Item.GetItemCount(beast.lureItemID, false) > 0

    if hasLure then
        -- Show secure macro button that places lure at player's feet
        button:SetAttribute("type1", "macro")
        button:SetAttribute("macrotext", "/use [@player] item:" .. beast.lureItemID)
        UpdateButtonIcon(button, beast.lureItemID)
        button:Show()
        craftButton:Hide()
    else
        -- Check if we can craft
        local canCraft = ns.RecipeCache:CanCraftLure(beast.lureItemID)
        if canCraft then
            UpdateButtonIcon(craftButton, beast.lureItemID)
            craftButton:Show()
            button:Hide()
        else
            -- No lure and can't craft — hide both
            button:Hide()
            craftButton:Hide()
        end
    end
end

local function HideLureButton()
    activeBeast = nil
    if button then button:Hide() end
    if craftButton then craftButton:Hide() end
end

------------------------------------------------------------------------
-- Aura monitoring
------------------------------------------------------------------------

local auraFrame = CreateFrame("Frame")
auraFrame:RegisterEvent("UNIT_AURA")
auraFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
auraFrame:RegisterEvent("BAG_UPDATE_DELAYED")

auraFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_AURA" and unit ~= "player" then return end
    if InCombatLockdown() then return end

    local hasSixthSense = false
    for i = 1, 40 do
        local data = C_UnitAuras.GetAuraDataByIndex("player", i, "HARMFUL")
        if not data then break end
        if data.name == SIXTH_SENSE_NAME then
            local desc = C_Spell.GetSpellDescription(data.spellId)
            if desc and (desc:find("majestic beast", 1, true) or desc:find("grand beast", 1, true)) then
                hasSixthSense = true
                break
            end
        end
    end
    if hasSixthSense then
        local beast = FindNearestBeast()
        if beast then
            ShowLureButton(beast)
        else
            HideLureButton()
        end
    else
        HideLureButton()
    end
end)
