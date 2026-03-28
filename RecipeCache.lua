local addonName, ns = ...  -- luacheck: ignore 211/addonName

ns.RecipeCache = {}

function ns.RecipeCache:IsCacheComplete()
    if not ns.db or not ns.db.recipeCache then return false end
    -- We don't require all 5 lures to be in the cache — the player may not know all recipes.
    -- Consider complete if we've done at least one successful scan.
    return ns.db.recipeCacheScanned
end

function ns.RecipeCache:ScanForLureRecipes()
    local recipeIDs = C_TradeSkillUI.GetFilteredRecipeIDs()
    if not recipeIDs or #recipeIDs == 0 then
        return false
    end

    ns.db.recipeCache = ns.db.recipeCache or {}
    local found = 0

    for _, recipeID in ipairs(recipeIDs) do
        local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
        if ok and schematic and schematic.outputItemID and ns.LURE_ITEM_IDS[schematic.outputItemID] then
            local reagents = {}
            for _, slot in ipairs(schematic.reagentSlotSchematics) do
                if slot.required then
                    for _, reagent in ipairs(slot.reagents) do
                        if reagent.itemID then
                            table.insert(reagents, {
                                itemID = reagent.itemID,
                                quantity = slot.quantityRequired,
                            })
                        end
                    end
                end
            end
            ns.db.recipeCache[schematic.outputItemID] = {
                recipeID = recipeID,
                learned = true,
                reagents = reagents,
            }
            found = found + 1
        end
    end

    ns.db.recipeCacheScanned = true
    ns.RecipeCache:ResolveReagentNames()
    return found > 0
end

function ns.RecipeCache:ResolveReagentNames()
    for _, data in pairs(ns.db.recipeCache or {}) do
        for _, reagent in ipairs(data.reagents) do
            if not reagent.name then
                local itemName = GetItemInfo(reagent.itemID)
                if itemName then
                    reagent.name = itemName
                else
                    C_Item.RequestLoadItemDataByID(reagent.itemID)
                end
            end
        end
    end
end

function ns.RecipeCache:CanCraftLure(lureItemID)
    if not ns.db or not ns.db.recipeCache then return false end
    local cached = ns.db.recipeCache[lureItemID]
    return cached and cached.learned
end

function ns.RecipeCache:GetReagents(lureItemID)
    if not ns.db or not ns.db.recipeCache then return nil end
    local cached = ns.db.recipeCache[lureItemID]
    if cached then return cached.reagents end
    return nil
end
