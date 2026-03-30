local addonName, ns = ...  -- luacheck: ignore 211/addonName

ns.RecipeCache = {}

local function GetCharKey()
    local name, realm = UnitName("player"), GetRealmName()
    return name .. "-" .. realm
end

local function GetCharCache()
    local key = GetCharKey()
    ns.db.recipeCacheByChar = ns.db.recipeCacheByChar or {}
    ns.db.recipeCacheByChar[key] = ns.db.recipeCacheByChar[key] or {}
    return ns.db.recipeCacheByChar[key]
end

function ns.RecipeCache:IsCacheComplete()
    if not ns.db then return false end
    local cc = GetCharCache()
    return cc.scanned
end

function ns.RecipeCache:ScanForLureRecipes()
    local recipeIDs = C_TradeSkillUI.GetFilteredRecipeIDs()
    if not recipeIDs or #recipeIDs == 0 then
        return false
    end

    local cc = GetCharCache()
    cc.recipes = cc.recipes or {}
    local found = 0

    -- Clear previous data so removed recipes don't persist
    cc.recipes = {}

    for _, recipeID in ipairs(recipeIDs) do
        local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)
        if recipeInfo and recipeInfo.learned then
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
                cc.recipes[schematic.outputItemID] = {
                    recipeID = recipeID,
                    learned = true,
                    reagents = reagents,
                }
                found = found + 1
            end
        end
    end

    cc.scanned = true
    ns.RecipeCache:ResolveReagentNames()
    return found > 0
end

function ns.RecipeCache:ResolveReagentNames()
    local cc = GetCharCache()
    for _, data in pairs(cc.recipes or {}) do
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
    if not ns.db then return false end
    local cc = GetCharCache()
    local cached = cc.recipes and cc.recipes[lureItemID]
    return cached and cached.learned
end

function ns.RecipeCache:GetReagents(lureItemID)
    if not ns.db then return nil end
    local cc = GetCharCache()
    local cached = cc.recipes and cc.recipes[lureItemID]
    if cached then return cached.reagents end
    return nil
end
