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

    -- Subtract reagents already in inventory, build search strings
    local searchStrings = {}
    for itemID, info in pairs(reagentTotals) do
        local have = C_Item.GetItemCount(itemID, true)
        local need = info.quantity - have
        if need > 0 then
            if info.name then
                local searchTerm = Auctionator.API.v1.ConvertToSearchString(
                    "TalentedTracker",
                    {
                        searchString = info.name,
                        isExact = true,
                        quantity = need,
                    }
                )
                table.insert(searchStrings, searchTerm)
            else
                -- Name not yet resolved — request it for next time
                C_Item.RequestLoadItemDataByID(itemID)
                ns.addon:Printf("Item name for %d not yet loaded. Try /tt shop again in a moment.", itemID)
            end
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
