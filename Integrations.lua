local addonName, ns = ...  -- luacheck: ignore 211/addonName

ns.Integrations = {}

------------------------------------------------------------------------
-- Routing
------------------------------------------------------------------------

function ns.Integrations:CreateRoute(craftableOnly)
    local beasts = ns.addon:GetBeastsForRoute(craftableOnly)

    if #beasts == 0 then
        if craftableOnly then
            ns.addon:Print("No beasts remaining that you can lure. Try /tt route all to include all unskinned beasts.")
        else
            ns.addon:Print("All beasts skinned for today!")
        end
        return
    end

    local steps = ns.Routing:SolveRoute(beasts)
    if not steps or #steps == 0 then
        ns.addon:Print("Could not compute a route.")
        return
    end

    ns.Routing:StartNavigation(steps, craftableOnly)
end

------------------------------------------------------------------------
-- Auctionator shopping list
------------------------------------------------------------------------

function ns.Integrations:CreateShoppingList()
    if not Auctionator or not Auctionator.API or not Auctionator.API.v1 then
        ns.addon:Print("Auctionator is not loaded. Cannot create shopping list.")
        return
    end

    if not ns.RecipeCache:IsCacheComplete() then
        ns.addon:Print("Recipe data not yet cached. Open your Skinning profession window first, then try again.")
        return
    end

    local beasts = ns.addon:GetBeastsForRoute(false)
    if #beasts == 0 then
        ns.addon:Print("No beasts to shop for.")
        return
    end

    -- Aggregate reagents across all craftable lures we don't have yet
    local reagentTotals = {} -- [itemID] = { name, quantity }
    local craftableCount = 0

    for _, entry in ipairs(beasts) do
        if not entry.hasLure and entry.canCraft then
            craftableCount = craftableCount + 1
            local reagents = ns.RecipeCache:GetReagents(entry.beast.lureItemID)
            if reagents then
                for _, reagent in ipairs(reagents) do
                    if not reagentTotals[reagent.itemID] then
                        reagentTotals[reagent.itemID] = {
                            name = reagent.name,
                            quantity = 0,
                        }
                    end
                    reagentTotals[reagent.itemID].quantity = reagentTotals[reagent.itemID].quantity + reagent.quantity
                end
            end
        end
    end

    if craftableCount == 0 then
        ns.addon:Print("No craftable lures needed (you either have all lures or don't know the recipes).")
        return
    end

    -- Collect needed reagents and check if item data is cached
    local needed = {} -- { {itemID, quantity}, ... }
    local missing = {} -- item IDs not yet cached
    for itemID, info in pairs(reagentTotals) do
        local have = C_Item.GetItemCount(itemID, true)
        local need = info.quantity - have
        if need > 0 then
            table.insert(needed, { itemID = itemID, quantity = need })
            if not GetItemInfo(itemID) then
                table.insert(missing, itemID)
            end
        end
    end

    -- If any item names are missing, request them and retry after they load
    if #missing > 0 then
        for _, itemID in ipairs(missing) do
            C_Item.RequestLoadItemDataByID(itemID)
        end
        ns.addon:Print("Loading item data...")
        local remaining = #missing
        local retryFrame = CreateFrame("Frame")
        retryFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        retryFrame:SetScript("OnEvent", function(frame, _, loadedItemID)
            for i, id in ipairs(missing) do
                if id == loadedItemID then
                    table.remove(missing, i)
                    remaining = remaining - 1
                    break
                end
            end
            if remaining <= 0 then
                frame:UnregisterAllEvents()
                frame:SetScript("OnEvent", nil)
                ns.Integrations:CreateShoppingList()
            end
        end)
        -- Timeout after 5 seconds in case items never load
        C_Timer.After(5, function()
            if remaining > 0 then
                retryFrame:UnregisterAllEvents()
                retryFrame:SetScript("OnEvent", nil)
                ns.Integrations:CreateShoppingList()
            end
        end)
        return
    end

    -- Build search strings
    local searchStrings = {}
    for _, item in ipairs(needed) do
        local name = GetItemInfo(item.itemID)
        if name then
            local searchTerm = Auctionator.API.v1.ConvertToSearchString(
                "TalentedTracker",
                {
                    searchString = name,
                    isExact = true,
                    quantity = item.quantity,
                }
            )
            table.insert(searchStrings, searchTerm)
        end
    end

    if #searchStrings == 0 then
        ns.addon:Print("You already have all the reagents you need!")
        return
    end

    Auctionator.API.v1.CreateShoppingList(
        "TalentedTracker",
        "Talented Tracker - Lure Materials",
        searchStrings
    )
    ns.addon:Printf("Auctionator shopping list created with %d item(s).", #searchStrings)
end
