local addonName, ns = ...  -- luacheck: ignore 211/addonName

local TalentedTracker = LibStub("AceAddon-3.0"):NewAddon(
    "TalentedTracker", "AceConsole-3.0", "AceEvent-3.0"
)
ns.addon = TalentedTracker

function TalentedTracker:OnInitialize()
    local dbName = "TalentedTrackerDB"

    _G[dbName] = _G[dbName] or {}
    ns.db = _G[dbName]

    -- Clean up legacy account-wide recipe cache
    ns.db.recipeCache = nil
    ns.db.recipeCacheScanned = nil

    self:RegisterChatCommand("tt", "SlashCommand")
    self:RegisterChatCommand("talentedtracker", "SlashCommand")

    -- Snapshot current beast quest completion state
    ns.completedQuests = {}
    for _, beast in ipairs(ns.BEASTS) do
        if C_QuestLog.IsQuestFlaggedCompleted(beast.questID) then
            ns.completedQuests[beast.questID] = true
        end
    end

    ns.InitMinimapButton()
end

function TalentedTracker:OnEnable()
    self:RegisterEvent("QUEST_LOG_UPDATE", "OnQuestLogUpdate")
    self:RegisterEvent("TRADE_SKILL_LIST_UPDATE", "OnTradeSkillListUpdate")
    self:RegisterEvent("BAG_UPDATE_DELAYED", "OnBagUpdate")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "OnZoneChanged")
end

------------------------------------------------------------------------
-- Status queries
------------------------------------------------------------------------

function TalentedTracker:HasSkinning()
    local info = C_TradeSkillUI.GetProfessionInfoBySkillLineID(ns.SKINNING_SKILL_LINE_ID)
    return info and info.skillLevel and info.skillLevel > 0
end

function TalentedTracker:GetBeastStatus()
    local results = {}
    for _, beast in ipairs(ns.BEASTS) do
        table.insert(results, {
            beast = beast,
            skinned = C_QuestLog.IsQuestFlaggedCompleted(beast.questID),
            hasLure = C_Item.GetItemCount(beast.lureItemID, true) > 0,
            canCraft = ns.RecipeCache:CanCraftLure(beast.lureItemID),
        })
    end
    return results
end

function TalentedTracker:GetUnskinnedBeasts(craftableOnly)
    local unskinned = {}
    for _, entry in ipairs(self:GetBeastStatus()) do
        if not entry.skinned then
            if not craftableOnly or entry.hasLure or entry.canCraft then
                table.insert(unskinned, entry)
            end
        end
    end
    return unskinned
end

function TalentedTracker:GetBeastsForRoute(craftableOnly)
    local result = {}
    for _, entry in ipairs(self:GetBeastStatus()) do
        local include = not entry.skinned or ns.includeSkinned
        if include then
            if not craftableOnly or entry.hasLure or entry.canCraft or entry.skinned then
                table.insert(result, entry)
            end
        end
    end
    return result
end

function TalentedTracker:GetCompletedCount()
    local count = 0
    for _, beast in ipairs(ns.BEASTS) do
        if C_QuestLog.IsQuestFlaggedCompleted(beast.questID) then
            count = count + 1
        end
    end
    return count
end

------------------------------------------------------------------------
-- Status display
------------------------------------------------------------------------

function TalentedTracker:PrintStatus()
    if not self:HasSkinning() then
        self:Print("You don't have Midnight Skinning.")
        return
    end

    local status = self:GetBeastStatus()
    local remaining = 0

    for _, entry in ipairs(status) do
        if entry.skinned then
            self:Printf("  |cff888888%s — skinned|r", entry.beast.name)
        else
            remaining = remaining + 1
            local lureTag
            if entry.hasLure then
                lureTag = "|cff00ff00have lure|r"
            elseif entry.canCraft then
                lureTag = "|cffffff00can craft lure|r"
            else
                lureTag = "|cffff0000no recipe|r"
            end
            self:Printf("  %s — %s", entry.beast.name, lureTag)
        end
    end

    if remaining == 0 then
        self:Print("All renowned beasts skinned for today!")
    else
        self:Printf("%d/%d remaining.", remaining, #ns.BEASTS)
    end

    if not ns.RecipeCache:IsCacheComplete() then
        self:Print("|cffffff00Recipe data not yet cached. Open your Skinning profession window to scan.|r")
    end
end

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------

function TalentedTracker:SlashCommand(input)
    local args = {}
    for word in (input or ""):gmatch("%S+") do
        table.insert(args, word:lower())
    end
    local cmd = args[1] or "status"

    if cmd == "status" or cmd == "" then
        ns.MainWindow:Toggle()
    elseif cmd == "route" then
        local includeAll = args[2] == "all"
        ns.Integrations:CreateRoute(not includeAll)
    elseif cmd == "shop" then
        ns.Integrations:CreateShoppingList()
    elseif cmd == "scan" then
        self:Print("Scanning recipes... (open your Skinning profession window if not already open)")
        local found = ns.RecipeCache:ScanForLureRecipes()
        if found then
            self:Print("Lure recipe data cached successfully!")
        else
            self:Print("No lure recipes found. Is your Skinning profession window open?")
        end
    elseif cmd == "help" then
        self:Print("Commands:")
        self:Print("  /tt — Show beast status")
        self:Print("  /tt route — Route to beasts you can lure (have lure or can craft)")
        self:Print("  /tt route all — Route to ALL unskinned beasts")
        self:Print("  /tt shop — Auctionator shopping list for lure reagents")
        self:Print("  /tt scan — Rescan skinning recipes")
    else
        self:Printf("Unknown command: %s. Use /tt help", cmd)
    end
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

function TalentedTracker:OnQuestLogUpdate()
    -- Check each beast quest for newly completed ones
    for _, beast in ipairs(ns.BEASTS) do
        local completed = C_QuestLog.IsQuestFlaggedCompleted(beast.questID)
        if completed and not ns.completedQuests[beast.questID] then
            ns.completedQuests[beast.questID] = true
            self:Printf("|cff00ff00%s skinned!|r (%d/%d skinned)",
                beast.name, self:GetCompletedCount(), #ns.BEASTS)
            ns.Routing:OnQuestCompleted(beast.questID)
            ns.MainWindow:Refresh()
        end
    end
end

function TalentedTracker:OnTradeSkillListUpdate()
    if not ns.RecipeCache:IsCacheComplete() then
        local found = ns.RecipeCache:ScanForLureRecipes()
        if found then
            self:Print("Lure recipe data cached successfully!")
            ns.MainWindow:Refresh()
        end
    end
end

function TalentedTracker:OnBagUpdate()
    ns.MainWindow:Refresh()
end

function TalentedTracker:OnZoneChanged()
    ns.Routing:OnZoneChanged()
end
