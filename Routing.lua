local addonName, ns = ...  -- luacheck: ignore 211/addonName

ns.Routing = {}

-- Cost in equivalent yards for one loading screen (portal/teleport).
-- Flying speed is ~58 yards/sec, loading screen ~3-4 sec.
local PORTAL_COST = 200

-- Strip parenthetical beast name suffix for chat output
local function ChatName(step)
    return step.name:gsub(" %(.+%)$", "")
end

-- Extract beast visit order from a step list for comparison
local function GetBeastOrder(steps)
    local order = {}
    for _, step in ipairs(steps) do
        if step.type == "beast" and step.questID then
            table.insert(order, step.questID)
        end
    end
    return order
end

local function SameBeastOrder(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

-- Color code for step type: green=beast, cyan=teleport, yellow=portal
local function ColoredStep(step)
    local color = step.type == "beast" and "|cff00ff00" or step.type == "teleport" and "|cff00ccff" or "|cffffff00"
    return color .. ChatName(step) .. "|r"
end

-- Navigation state
local navSteps = nil          -- ordered list of waypoint steps
local navIndex = 0            -- current step index
local navUID   = nil          -- current TomTom waypoint UID
local navCraftableOnly = true -- route filter setting used when this route was created
local navVisitedQuests = {}   -- questIDs of beasts we've completed or skipped this route
local navTotalSteps = 0       -- total steps in the original route (for display)
local navCompletedSteps = 0   -- steps completed so far

------------------------------------------------------------------------
-- Zone alias resolution
------------------------------------------------------------------------

local function ResolveZone(mapID)
    return ns.ZONE_ALIASES[mapID] or mapID
end

------------------------------------------------------------------------
-- Distance helpers
------------------------------------------------------------------------

local function GetWorldPos(mapID, x, y)
    local continentID, worldPos = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
    if continentID and worldPos then
        return continentID, worldPos.x, worldPos.y
    end
    return nil, 0, 0
end

function ns.Routing:WorldDistance(mapID1, x1, y1, mapID2, x2, y2)
    local c1, wx1, wy1 = GetWorldPos(mapID1, x1, y1)
    local c2, wx2, wy2 = GetWorldPos(mapID2, x2, y2)
    if not c1 or not c2 or c1 ~= c2 then
        return math.huge
    end
    local dx = wx1 - wx2
    local dy = wy1 - wy2
    return math.sqrt(dx * dx + dy * dy)
end

------------------------------------------------------------------------
-- Travel cost between two points (possibly cross-zone via SM portals)
------------------------------------------------------------------------

-- Cost to travel between zones via Silvermoon hub portals.
function ns.Routing:TravelCostViaSM(fromMapID, fromX, fromY, toMapID, toX, toY)
    local fromPortal = ns.PORTALS[fromMapID]
    local exitCost
    if fromPortal then
        local walkToExit = self:WorldDistance(fromMapID, fromX, fromY, fromPortal.exitMapID, fromPortal.exitX, fromPortal.exitY)
        if walkToExit == math.huge then walkToExit = 200 end
        exitCost = walkToExit + PORTAL_COST
    elseif ns.WALKABLE_ZONES[fromMapID] then
        exitCost = self:WorldDistance(fromMapID, fromX, fromY, ns.ZONE_SILVERMOON, 0.5, 0.65)
        if exitCost == math.huge then exitCost = 300 end
    else
        return math.huge
    end

    local toPortal = ns.PORTALS[toMapID]
    local entryCost
    if toPortal then
        local smOriginX = fromPortal and fromPortal.smX or 0.5
        local smOriginY = fromPortal and fromPortal.smY or 0.65
        local smWalk = self:WorldDistance(ns.ZONE_SILVERMOON, smOriginX, smOriginY,
                                          ns.ZONE_SILVERMOON, toPortal.smX, toPortal.smY)
        if smWalk == math.huge then smWalk = 100 end
        local walkToDest = self:WorldDistance(toMapID, toPortal.exitX, toPortal.exitY, toMapID, toX, toY)
        if walkToDest == math.huge then walkToDest = 200 end
        entryCost = smWalk + PORTAL_COST + walkToDest
    elseif ns.WALKABLE_ZONES[toMapID] then
        local walkDist = self:WorldDistance(ns.ZONE_SILVERMOON, 0.5, 0.65, toMapID, toX, toY)
        if walkDist == math.huge then walkDist = 400 end
        entryCost = walkDist
    else
        return math.huge
    end

    return exitCost + entryCost
end

-- Returns the cost to travel from point A to point B.
function ns.Routing:TravelCost(fromMapID, fromX, fromY, toMapID, toX, toY)
    -- Same zone: direct walk
    if fromMapID == toMapID then
        return self:WorldDistance(fromMapID, fromX, fromY, toMapID, toX, toY)
    end

    -- Both walkable from SM (Eversong, Zul'Aman, SM itself): direct walk
    if ns.WALKABLE_ZONES[fromMapID] and ns.WALKABLE_ZONES[toMapID] then
        local dist = self:WorldDistance(fromMapID, fromX, fromY, toMapID, toX, toY)
        if dist < math.huge then
            return dist
        end
    end

    -- Check for direct zone-to-zone portals (e.g. Harandar Den → Voidstorm)
    -- A direct portal is always faster than going through SM since it's in the
    -- same hub but saves an entire SM round-trip.
    for _, dp in ipairs(ns.DIRECT_PORTALS) do
        if dp.fromZone == fromMapID and dp.toZone == toMapID then
            -- Walk to hub (same as walking to SM exit portal area)
            local walkToHub = self:ExitCost(fromMapID, fromX, fromY)
            if not walkToHub then walkToHub = 300 end
            -- ExitCost includes SM portal loading screen, replace with direct portal loading screen
            walkToHub = walkToHub - PORTAL_COST + PORTAL_COST -- net zero, but conceptually correct
            -- Walk from arrival in destination zone to the beast
            local walkToDest = self:WorldDistance(dp.arrivalMapID, dp.arrivalX, dp.arrivalY, toMapID, toX, toY)
            if walkToDest == math.huge then walkToDest = 200 end
            return walkToHub + walkToDest
        end
    end

    return self:TravelCostViaSM(fromMapID, fromX, fromY, toMapID, toX, toY)
end

-- Returns just the exit cost portion of a cross-zone leg (cost to get from a point to SM).
-- Returns 0 if already in a walkable zone. Returns nil if not a cross-zone situation.
function ns.Routing:ExitCost(fromMapID, fromX, fromY)
    local fromPortal = ns.PORTALS[fromMapID]
    if fromPortal then
        local walkToExit = self:WorldDistance(fromMapID, fromX, fromY, fromPortal.exitMapID, fromPortal.exitX, fromPortal.exitY)
        if walkToExit == math.huge then walkToExit = 200 end
        return walkToExit + PORTAL_COST
    elseif ns.WALKABLE_ZONES[fromMapID] then
        local walkToSM = self:WorldDistance(fromMapID, fromX, fromY, ns.ZONE_SILVERMOON, 0.5, 0.65)
        if walkToSM == math.huge then walkToSM = 300 end
        return walkToSM
    end
    return nil
end

------------------------------------------------------------------------
-- Build the step-by-step route between two beast locations
------------------------------------------------------------------------

local function FindDirectPortal(fromMapID, toMapID)
    for _, dp in ipairs(ns.DIRECT_PORTALS) do
        if dp.fromZone == fromMapID and dp.toZone == toMapID then
            return dp
        end
    end
    return nil
end

local function BuildLegSteps(fromMapID, _, _, toMapID, toX, toY, beastEntry) -- luacheck: no unused args
    local steps = {}

    -- Same zone or walkable: just go to the beast
    if fromMapID == toMapID or (ns.WALKABLE_ZONES[fromMapID] and ns.WALKABLE_ZONES[toMapID]) then
        table.insert(steps, {
            type = "beast",
            name = beastEntry.beast.name,
            mapID = toMapID,
            x = toX,
            y = toY,
            questID = beastEntry.beast.questID,
        })
        return steps
    end

    local beastName = beastEntry.beast.name

    -- Check for a direct portal shortcut
    local directPortal = FindDirectPortal(fromMapID, toMapID)
    if directPortal then
        table.insert(steps, {
            type = "portal",
            name = directPortal.portalName .. " (" .. beastName .. ")",
            mapID = directPortal.portalMapID,
            x = directPortal.portalX,
            y = directPortal.portalY,
            poiSearch = directPortal.poiSearch,
            poiMapID = directPortal.poiMapID,
        })
    else
        -- Travel through Silvermoon
        local fromPortal = ns.PORTALS[fromMapID]
        local toPortal = ns.PORTALS[toMapID]

        -- Step 1: Go to zone exit portal (if in a portal zone)
        if fromPortal then
            table.insert(steps, {
                type = "portal",
                name = fromPortal.exitName .. " (" .. beastName .. ")",
                mapID = fromPortal.exitMapID,
                x = fromPortal.exitX,
                y = fromPortal.exitY,
                poiSearch = fromPortal.exitPoiSearch,
                poiMapID = fromPortal.exitPoiMapID,
            })
        end

        -- Step 2: Go to SM entry portal for destination (if destination needs a portal)
        if toPortal then
            table.insert(steps, {
                type = "portal",
                name = toPortal.smName .. " (" .. beastName .. ")",
                mapID = ns.ZONE_SILVERMOON,
                x = toPortal.smX,
                y = toPortal.smY,
                poiSearch = toPortal.smPoiSearch,
                poiMapID = toPortal.smPoiMapID,
            })
        end
    end

    -- Step 3: Go to the beast
    table.insert(steps, {
        type = "beast",
        name = beastEntry.beast.name,
        mapID = toMapID,
        x = toX,
        y = toY,
        questID = beastEntry.beast.questID,
    })

    return steps
end

-- Variant for teleport legs: player uses HS/Arcantina, lands at teleport dest, then goes to next beast
local function BuildTeleportLegSteps(teleport, toMapID, toX, toY, beastEntry)
    local steps = {}

    local beastName = beastEntry.beast.name

    -- Step 1: Use teleport
    table.insert(steps, {
        type = "teleport",
        name = "Use " .. teleport.name .. " (" .. beastName .. ")",
        mapID = teleport.destMapID,
        x = teleport.destX,
        y = teleport.destY,
        itemID = teleport.itemID,
    })

    local tpMapID = teleport.destMapID

    -- Step 2: Navigate from teleport destination to the beast
    -- If we landed in the same zone or a walkable-connected zone, go directly
    local sameOrWalkable = (tpMapID == toMapID) or
        (ns.WALKABLE_ZONES[tpMapID] and ns.WALKABLE_ZONES[toMapID])

    if not sameOrWalkable then
        -- Need to get to SM first (if not already there), then take portal
        if not ns.WALKABLE_ZONES[tpMapID] then
            -- Teleport landed in a portal zone (Harandar/Voidstorm), need exit portal to SM
            local exitPortal = ns.PORTALS[tpMapID]
            if exitPortal then
                table.insert(steps, {
                    type = "portal",
                    name = exitPortal.exitName .. " (" .. beastName .. ")",
                    mapID = exitPortal.exitMapID,
                    x = exitPortal.exitX,
                    y = exitPortal.exitY,
                    poiSearch = exitPortal.exitPoiSearch,
                    poiMapID = exitPortal.exitPoiMapID,
                })
            end
        end

        -- Now in SM (or walkable zone), take portal to destination zone if needed
        local toPortal = ns.PORTALS[toMapID]
        if toPortal then
            table.insert(steps, {
                type = "portal",
                name = toPortal.smName .. " (" .. beastName .. ")",
                mapID = ns.ZONE_SILVERMOON,
                x = toPortal.smX,
                y = toPortal.smY,
                poiSearch = toPortal.smPoiSearch,
                poiMapID = toPortal.smPoiMapID,
            })
        end
    end

    -- Final step: Go to the beast
    table.insert(steps, {
        type = "beast",
        name = beastEntry.beast.name,
        mapID = toMapID,
        x = toX,
        y = toY,
        questID = beastEntry.beast.questID,
    })

    return steps
end

------------------------------------------------------------------------
-- Teleport availability
------------------------------------------------------------------------

function ns.Routing:ResolveHearthstone()
    local bindLoc = GetBindLocation()
    if not bindLoc then return nil end
    local inn = ns.INNS[bindLoc]
    if not inn then return nil end
    return inn.mapID, inn.x, inn.y
end

function ns.Routing:GetAvailableTeleports()
    local available = {}
    if InCombatLockdown() then return available end
    for _, tp in ipairs(ns.TELEPORTS) do
        local destMapID, destX, destY = tp.destMapID, tp.destX, tp.destY

        -- Hearthstone and Astral Recall: resolve destination from bind location
        if tp.itemID == 6948 or tp.resolveFromBind then
            destMapID, destX, destY = self:ResolveHearthstone()
            if not destMapID then
                destMapID = nil
            end
        end

        if destMapID then
            local isAvailable = false

            if tp.spellID then
                -- Spell-based teleport (e.g. Mage Teleport: Silvermoon City)
                if IsSpellKnown(tp.spellID) then
                    local cdInfo = C_Spell.GetSpellCooldown(tp.spellID)
                    local offCooldown = not cdInfo or cdInfo.duration == 0
                    if offCooldown then
                        isAvailable = true
                    end
                end
            else
                -- Item-based teleport
                local hasItem
                if tp.isToy then
                    hasItem = PlayerHasToy(tp.itemID)
                else
                    hasItem = C_Item.GetItemCount(tp.itemID, false) > 0 or tp.itemID == 6948
                end
                if hasItem then
                    local startTime, duration = C_Item.GetItemCooldown(tp.itemID)
                    local offCooldown = (startTime == 0) or (GetTime() >= startTime + duration)
                    if offCooldown then
                        isAvailable = true
                    end
                end
            end

            if isAvailable then
                table.insert(available, {
                    name = tp.name,
                    itemID = tp.itemID,
                    spellID = tp.spellID,
                    destMapID = destMapID,
                    destX = destX,
                    destY = destY,
                    portalCosts = tp.portalCosts,
                })
            end
        end
    end
    return available
end

------------------------------------------------------------------------
-- TSP solver (brute force over permutations)
------------------------------------------------------------------------

local function Permutations(list)
    if #list <= 1 then return { list } end
    local result = {}
    for i = 1, #list do
        local rest = {}
        for j = 1, #list do
            if j ~= i then table.insert(rest, list[j]) end
        end
        for _, perm in ipairs(Permutations(rest)) do
            local p = { list[i] }
            for _, v in ipairs(perm) do table.insert(p, v) end
            table.insert(result, p)
        end
    end
    return result
end

function ns.Routing:SolveRoute(beastEntries)
    if #beastEntries == 0 then return nil end

    local SM_CENTER_X, SM_CENTER_Y = 0.46, 0.70

    -- Get player position
    local playerMapID = ResolveZone(C_Map.GetBestMapForUnit("player"))
    local playerPos = C_Map.GetPlayerMapPosition(playerMapID, "player")
    local playerX, playerY
    if playerPos then
        playerX, playerY = playerPos.x, playerPos.y
    else
        playerX, playerY = 0.5, 0.5
    end

    local teleports = self:GetAvailableTeleports()
    -- Sort teleports by priority: lowest portal cost first (mage > HS > Arcantina)
    table.sort(teleports, function(a, b) return a.portalCosts < b.portalCosts end)
    local perms = Permutations(beastEntries)
    local bestCost = math.huge
    local bestPerm = nil
    local bestTeleportAssignment = nil -- { [legIndex] = teleport }

    for _, perm in ipairs(perms) do
        -- Calculate cost of each leg (transition between consecutive beasts)
        local legCosts = {}
        local prevMapID, prevX, prevY = playerMapID, playerX, playerY

        for i, entry in ipairs(perm) do
            local toMapID = entry.beast.mapID
            local toX, toY = entry.beast.x, entry.beast.y
            local cost = self:TravelCost(prevMapID, prevX, prevY, toMapID, toX, toY)
            legCosts[i] = cost
            prevMapID, prevX, prevY = toMapID, toX, toY
        end

        -- If ending at SM, add return leg from last beast
        local returnLegIndex = nil
        if ns.endAtSilvermoon then
            local lastBeast = perm[#perm].beast
            local returnCost = self:TravelCost(lastBeast.mapID, lastBeast.x, lastBeast.y,
                                                ns.ZONE_SILVERMOON, SM_CENTER_X, SM_CENTER_Y)
            returnLegIndex = #perm + 1
            legCosts[returnLegIndex] = returnCost
        end

        local totalCost = 0
        for _, c in ipairs(legCosts) do totalCost = totalCost + c end

        -- Try assigning teleports to cross-zone legs.
        -- A teleport replaces only the "exit" portion of a leg (getting back to SM from
        -- the previous beast). The "entry" portion (SM to next beast) stays the same.
        local tpAssignment = {}
        if #teleports > 0 then
            -- Find cross-zone legs and their exit costs
            local returnLegs = {}
            prevMapID, prevX, prevY = playerMapID, playerX, playerY
            for i, entry in ipairs(perm) do
                local toMapID = entry.beast.mapID
                local needsPortal = not (prevMapID == toMapID or
                    (ns.WALKABLE_ZONES[prevMapID] and ns.WALKABLE_ZONES[toMapID]))
                if needsPortal and legCosts[i] < math.huge then
                    local normalExit = self:ExitCost(prevMapID, prevX, prevY) or 0
                    table.insert(returnLegs, {
                        index = i,
                        exitCost = normalExit,
                    })
                end
                prevMapID = perm[i].beast.mapID
                prevX, prevY = perm[i].beast.x, perm[i].beast.y
            end

            -- Include return-to-SM leg if ending at Silvermoon
            if returnLegIndex and legCosts[returnLegIndex] < math.huge then
                local lastBeast = perm[#perm].beast
                local normalExit = self:ExitCost(lastBeast.mapID, lastBeast.x, lastBeast.y) or 0
                table.insert(returnLegs, {
                    index = returnLegIndex,
                    exitCost = normalExit,
                })
            end

            -- Compute savings for every (teleport, leg) pair.
            -- Saving = normal exit cost - teleport cost to reach SM
            local savingsMatrix = {}
            for tpIdx, tp in ipairs(teleports) do
                savingsMatrix[tpIdx] = {}
                for _, leg in ipairs(returnLegs) do
                    local tpCostToSM = tp.portalCosts * PORTAL_COST
                    -- If teleport doesn't land in SM or a walkable zone, add travel from TP dest to SM
                    if not ns.WALKABLE_ZONES[tp.destMapID] and tp.destMapID ~= ns.ZONE_SILVERMOON then
                        local toSM = self:ExitCost(tp.destMapID, tp.destX, tp.destY) or 500
                        tpCostToSM = tpCostToSM + toSM
                    elseif ns.WALKABLE_ZONES[tp.destMapID] and tp.destMapID ~= ns.ZONE_SILVERMOON then
                        local walkToSM = self:WorldDistance(tp.destMapID, tp.destX, tp.destY,
                                                            ns.ZONE_SILVERMOON, 0.5, 0.65)
                        if walkToSM == math.huge then walkToSM = 300 end
                        tpCostToSM = tpCostToSM + walkToSM
                    end
                    savingsMatrix[tpIdx][leg.index] = leg.exitCost - tpCostToSM
                end
            end

            -- Greedy assignment: repeatedly pick the (teleport, leg) pair with highest saving
            local usedTPs = {}
            local usedLegs = {}
            local tpSavings = 0
            for _ = 1, math.min(#teleports, #returnLegs) do
                local bestSaving, bestTP, bestLeg = 0, nil, nil
                for tpIdx = 1, #teleports do
                    if not usedTPs[tpIdx] then
                        for _, leg in ipairs(returnLegs) do
                            if not usedLegs[leg.index] then
                                local s = savingsMatrix[tpIdx][leg.index]
                                if s > bestSaving then
                                    bestSaving = s
                                    bestTP = tpIdx
                                    bestLeg = leg.index
                                end
                            end
                        end
                    end
                end
                if not bestTP then break end
                usedTPs[bestTP] = true
                usedLegs[bestLeg] = true
                tpSavings = tpSavings + bestSaving
                tpAssignment[bestLeg] = teleports[bestTP]
            end
            totalCost = totalCost - tpSavings
        end

        if totalCost < bestCost then
            bestCost = totalCost
            bestPerm = perm
            bestTeleportAssignment = tpAssignment
        end
    end

    if not bestPerm then return nil end

    -- Build step-by-step route from the best permutation
    local steps = {}
    local prevMapID, prevX, prevY = playerMapID, playerX, playerY

    for i, entry in ipairs(bestPerm) do
        local toMapID = entry.beast.mapID
        local toX, toY = entry.beast.x, entry.beast.y
        local legSteps

        if bestTeleportAssignment and bestTeleportAssignment[i] then
            legSteps = BuildTeleportLegSteps(bestTeleportAssignment[i], toMapID, toX, toY, entry)
        else
            legSteps = BuildLegSteps(prevMapID, prevX, prevY, toMapID, toX, toY, entry)
        end

        for _, step in ipairs(legSteps) do
            table.insert(steps, step)
        end
        prevMapID, prevX, prevY = toMapID, toX, toY
    end

    -- Append return-to-Silvermoon if requested
    if ns.endAtSilvermoon then
        local returnIdx = #bestPerm + 1
        if bestTeleportAssignment and bestTeleportAssignment[returnIdx] then
            local tp = bestTeleportAssignment[returnIdx]
            table.insert(steps, {
                type = "teleport",
                name = "Use " .. tp.name .. " (Silvermoon City)",
                mapID = tp.destMapID,
                x = tp.destX,
                y = tp.destY,
                itemID = tp.itemID,
                spellID = tp.spellID,
            })
        else
            -- Walk/portal back to SM
            local fromPortal = ns.PORTALS[prevMapID]
            if fromPortal then
                table.insert(steps, {
                    type = "portal",
                    name = fromPortal.exitName .. " (Silvermoon City)",
                    mapID = fromPortal.exitMapID,
                    x = fromPortal.exitX,
                    y = fromPortal.exitY,
                    poiSearch = fromPortal.exitPoiSearch,
                    poiMapID = fromPortal.exitPoiMapID,
                })
            end
        end
    end

    return steps, bestCost
end

------------------------------------------------------------------------
-- TomTom navigation
------------------------------------------------------------------------

-- Try to find an AreaPOI matching a portal step and supertrack it.
-- Returns true if a POI was found and supertracked.
local function TrySuperTrackPortalPOI(step)
    if not step.poiSearch or not step.poiMapID then return false end
    local poiIDs = C_AreaPoiInfo.GetAreaPOIForMap(step.poiMapID)
    if not poiIDs then return false end
    for _, poiID in ipairs(poiIDs) do
        local info = C_AreaPoiInfo.GetAreaPOIInfo(step.poiMapID, poiID)
        if info and info.name and info.name:find(step.poiSearch, 1, true) then
            C_SuperTrack.SetSuperTrackedMapPin(
                Enum.SuperTrackingMapPinType.AreaPOI, poiID)
            return true
        end
    end
    return false
end

local function SetTomTomWaypoint(step)
    if step.type == "teleport" then
        UIErrorsFrame:AddMessage(ChatName(step), 0, 0.8, 1, 1, 5)
    end
    if TomTom and TomTom.AddWaypoint then
        local opts = {
            title = step.name,
            persistent = false,
            minimap = true,
            world = true,
            crazy = true,
            arrivaldistance = 10,
            cleardistance = 0, -- we manage removal ourselves
        }
        -- Use distance callback to auto-advance for beast steps
        if step.type == "beast" then
            opts.callbacks = TomTom:DefaultCallbacks(opts)
            opts.callbacks.distance = opts.callbacks.distance or {}
            opts.callbacks.distance[10] = function()
                ns.Routing:AdvanceWaypoint()
            end
        end
        return TomTom:AddWaypoint(step.mapID, step.x, step.y, opts)
    else
        -- Fallback: try to supertrack the portal POI if this is a portal step
        if step.type == "portal" and TrySuperTrackPortalPOI(step) then
            return nil
        end
        -- Otherwise use a custom map pin
        if C_Map.CanSetUserWaypointOnMap(step.mapID) then
            local point = UiMapPoint.CreateFromCoordinates(step.mapID, step.x, step.y)
            C_Map.SetUserWaypoint(point)
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        end
        return nil
    end
end

local function ClearCurrentWaypoint()
    if navUID and TomTom then
        TomTom:RemoveWaypoint(navUID)
    else
        if C_Map.HasUserWaypoint() then
            C_Map.ClearUserWaypoint()
        end
        if C_SuperTrack.IsSuperTrackingMapPin() then
            C_SuperTrack.ClearSuperTrackedMapPin()
        end
    end
    navUID = nil
end

function ns.Routing:StartNavigation(steps, craftableOnly)
    self:StopNavigation()
    navSteps = steps
    navIndex = 0
    navCraftableOnly = craftableOnly
    navVisitedQuests = {}
    navTotalSteps = #steps
    navCompletedSteps = 0

    -- Print route summary
    ns.addon:Print("Route planned (" .. #steps .. " steps):")
    for i, step in ipairs(steps) do
        local icon = step.type == "beast" and "|cff00ff00" or step.type == "teleport" and "|cff00ccff" or "|cffffff00"
        ns.addon:Printf("  %d. %s%s|r", i, icon, ChatName(step))
    end

    self:AdvanceWaypoint()
end

function ns.Routing:AdvanceWaypoint()
    ClearCurrentWaypoint()

    -- Mark current beast step as visited before advancing
    if navSteps and navIndex > 0 and navIndex <= #navSteps then
        local curStep = navSteps[navIndex]
        if curStep.type == "beast" and curStep.questID then
            navVisitedQuests[curStep.questID] = true
        end
    end

    -- After completing a beast, re-plan the remaining route from current position
    local didReplan = false
    if navSteps and navIndex > 0 then
        local curStep = navSteps[navIndex]
        if curStep and curStep.type == "beast" then
            didReplan = self:ReplanRoute()
        end
    end

    if not didReplan then
        -- No replan happened, just move to next step
        navIndex = navIndex + 1
        if not navSteps or navIndex > #navSteps then
            ns.addon:Print("|cff00ff00Route complete!|r")
            self:StopNavigation()
            ns.MainWindow:Refresh()
            return
        end
        navCompletedSteps = navCompletedSteps + 1
        local step = navSteps[navIndex]
        ns.addon:Printf("Step %d/%d: %s", navCompletedSteps, navTotalSteps, ColoredStep(step))
        navUID = SetTomTomWaypoint(step)
        ns.MainWindow:Refresh()
    end
end

function ns.Routing:SkipCurrentStep()
    if not self:IsNavigating() then return end

    -- Find the next beast step from the current position onward — that's what we're skipping
    local skippedBeast = nil
    for i = navIndex, #navSteps do
        if navSteps[i].type == "beast" and navSteps[i].questID then
            skippedBeast = navSteps[i]
            break
        end
    end

    if not skippedBeast then return end

    navVisitedQuests[skippedBeast.questID] = true
    ns.addon:Printf("Skipped %s", skippedBeast.name)

    -- Re-plan from current position excluding visited beasts
    if not self:ReplanRoute() then
        ns.addon:Print("|cff00ff00Route complete!|r")
        self:StopNavigation()
        ns.MainWindow:Refresh()
    end
end

-- Build a return-to-SM route when no beasts remain but endAtSilvermoon is checked.
function ns.Routing:PlanReturnToSilvermoon()
    local currentMapID = C_Map.GetBestMapForUnit("player")
    local steps = {}

    -- Check if a teleport is available for the return
    local teleports = self:GetAvailableTeleports()
    table.sort(teleports, function(a, b) return a.portalCosts < b.portalCosts end)

    local bestTP = nil
    if #teleports > 0 then
        local playerPos = C_Map.GetPlayerMapPosition(currentMapID, "player")
        local px, py = playerPos and playerPos.x or 0.5, playerPos and playerPos.y or 0.5
        local normalExit = self:ExitCost(currentMapID, px, py) or 0
        for _, tp in ipairs(teleports) do
            local tpCost = tp.portalCosts * PORTAL_COST
            if tpCost < normalExit then
                bestTP = tp
                break
            end
        end
    end

    if bestTP then
        table.insert(steps, {
            type = "teleport",
            name = "Use " .. bestTP.name .. " (Silvermoon City)",
            mapID = bestTP.destMapID,
            x = bestTP.destX,
            y = bestTP.destY,
            itemID = bestTP.itemID,
            spellID = bestTP.spellID,
        })
    else
        local fromPortal = ns.PORTALS[currentMapID]
        if fromPortal then
            table.insert(steps, {
                type = "portal",
                name = fromPortal.exitName .. " (Silvermoon City)",
                mapID = fromPortal.exitMapID,
                x = fromPortal.exitX,
                y = fromPortal.exitY,
                poiSearch = fromPortal.exitPoiSearch,
                poiMapID = fromPortal.exitPoiMapID,
            })
        end
    end

    if #steps == 0 then
        -- Already in a walkable zone, just complete
        return false
    end

    ClearCurrentWaypoint()
    local savedVisited = navVisitedQuests
    local savedCraftable = navCraftableOnly
    navSteps = steps
    navIndex = 1
    navVisitedQuests = savedVisited
    navCraftableOnly = savedCraftable

    ns.addon:Print("Returning to Silvermoon:")
    for i, step in ipairs(steps) do
        local icon = step.type == "teleport" and "|cff00ccff" or "|cffffff00"
        ns.addon:Printf("  %d. %s%s|r", i, icon, ChatName(step))
    end

    local step = navSteps[1]
    ns.addon:Printf("Step 1/%d: %s", #navSteps, ColoredStep(step))
    navUID = SetTomTomWaypoint(step)
    ns.MainWindow:Refresh()
    return true
end

-- Re-plan the route from current position with remaining (unvisited) beasts.
-- Returns true if a new route was started, false if no beasts remain.
function ns.Routing:ReplanRoute()
    local beasts = ns.addon:GetBeastsForRoute(navCraftableOnly)

    -- Filter out beasts we've already visited or skipped
    local remaining = {}
    for _, entry in ipairs(beasts) do
        if not navVisitedQuests[entry.beast.questID] then
            table.insert(remaining, entry)
        end
    end

    if #remaining == 0 then
        -- No beasts left, but if ending at SM and we're not there, route back
        if ns.endAtSilvermoon then
            local currentMapID = ResolveZone(C_Map.GetBestMapForUnit("player"))
            if currentMapID ~= ns.ZONE_SILVERMOON then
                return self:PlanReturnToSilvermoon()
            end
        end
        return false
    end

    local steps = self:SolveRoute(remaining)
    if not steps or #steps == 0 then
        return false
    end

    -- Compare new route's beast order with the remaining old route
    local oldOrder = GetBeastOrder(navSteps)
    -- Remove already-visited beasts from old order for comparison
    local oldRemaining = {}
    for _, qid in ipairs(oldOrder) do
        if not navVisitedQuests[qid] then
            table.insert(oldRemaining, qid)
        end
    end
    local newOrder = GetBeastOrder(steps)
    local routeChanged = not SameBeastOrder(oldRemaining, newOrder)

    -- Replace the current route with the new plan
    ClearCurrentWaypoint()
    local savedVisited = navVisitedQuests
    local savedCraftable = navCraftableOnly
    navSteps = steps
    navIndex = 1
    navCompletedSteps = navCompletedSteps + 1
    navVisitedQuests = savedVisited
    navCraftableOnly = savedCraftable

    if routeChanged then
        navTotalSteps = navCompletedSteps + #steps - 1
        ns.addon:Print("Route re-planned (" .. #steps .. " steps remaining):")
        for i, step in ipairs(steps) do
            local icon = step.type == "beast" and "|cff00ff00" or step.type == "teleport" and "|cff00ccff" or "|cffffff00"
            ns.addon:Printf("  %d. %s%s|r", i, icon, ChatName(step))
        end
    end

    local step = navSteps[1]
    ns.addon:Printf("Step %d/%d: %s", navCompletedSteps, navTotalSteps, ColoredStep(step))
    navUID = SetTomTomWaypoint(step)
    ns.MainWindow:Refresh()
    return true
end

function ns.Routing:StopNavigation()
    ClearCurrentWaypoint()
    navSteps = nil
    navIndex = 0
    navVisitedQuests = {}
    navTotalSteps = 0
    navCompletedSteps = 0
end

function ns.Routing:IsNavigating()
    return navSteps ~= nil and navIndex > 0
end

function ns.Routing:GetCurrentStep()
    if navSteps and navIndex > 0 and navIndex <= #navSteps then
        return navSteps[navIndex], navCompletedSteps, navTotalSteps
    end
    return nil
end

------------------------------------------------------------------------
-- Event-based waypoint advancement
------------------------------------------------------------------------

-- Called when the player changes zones (portal taken)
function ns.Routing:OnZoneChanged()
    if not self:IsNavigating() then return end
    local step = navSteps[navIndex]
    if not step then return end

    local currentMapID = ResolveZone(C_Map.GetBestMapForUnit("player"))

    -- If current step is a portal and we've changed zone, advance
    if step.type == "portal" then
        if currentMapID ~= step.mapID then
            self:AdvanceWaypoint()
        end
    elseif step.type == "teleport" then
        if currentMapID == ns.ZONE_SILVERMOON then
            self:AdvanceWaypoint()
        end
    end

    -- If we're on a transit step (portal/teleport) but already in the zone of the
    -- next beast, skip ahead — the player got there by an unexpected route.
    if self:IsNavigating() and navSteps[navIndex] and navSteps[navIndex].type ~= "beast" then
        for i = navIndex + 1, #navSteps do
            if navSteps[i].type == "beast" then
                if ResolveZone(navSteps[i].mapID) == currentMapID then
                    -- Skip ahead to this beast step
                    ClearCurrentWaypoint()
                    navCompletedSteps = navCompletedSteps + (i - navIndex)
                    navIndex = i
                    local beastStep = navSteps[navIndex]
                    ns.addon:Printf("Step %d/%d: %s", navCompletedSteps, navTotalSteps, ColoredStep(beastStep))
                    navUID = SetTomTomWaypoint(beastStep)
                    ns.MainWindow:Refresh()
                    return
                end
                break -- only check the next beast, not further ones
            end
        end
    end

    -- If ending at SM and we've arrived, complete the route
    if ns.endAtSilvermoon and self:IsNavigating() and currentMapID == ns.ZONE_SILVERMOON then
        -- Check if all remaining steps are just getting to SM (no more beasts)
        local hasRemainingBeast = false
        for i = navIndex, #navSteps do
            if navSteps[i].type == "beast" then
                hasRemainingBeast = true
                break
            end
        end
        if not hasRemainingBeast then
            ns.addon:Print("|cff00ff00Route complete! Welcome back to Silvermoon.|r")
            self:StopNavigation()
            ns.MainWindow:Refresh()
        end
    end
end

-- Called when a beast quest is completed
function ns.Routing:OnQuestCompleted(questID)
    if not self:IsNavigating() then return end
    local step = navSteps[navIndex]
    if step and step.type == "beast" and step.questID == questID then
        self:AdvanceWaypoint()
    end
end
