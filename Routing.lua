local addonName, ns = ...  -- luacheck: ignore 211/addonName

ns.Routing = {}

-- Cost in equivalent yards for one loading screen (portal/teleport).
local PORTAL_COST = 500

-- Navigation state
local navSteps = nil          -- ordered list of waypoint steps
local navIndex = 0            -- current step index
local navUID   = nil          -- current TomTom waypoint UID
local navCraftableOnly = true -- route filter setting used when this route was created
local navVisitedQuests = {}   -- questIDs of beasts we've completed or skipped this route

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

-- Returns the cost to travel from point A to point B.
-- If they're walkable (same continent, no portal needed), it's Euclidean distance.
-- If cross-zone via portals, it includes portal hops through Silvermoon.
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

    -- Cross-zone via Silvermoon portals
    local fromPortal = ns.PORTALS[fromMapID]
    local exitCost
    if fromPortal then
        -- Walk to exit portal + loading screen
        local walkToExit = self:WorldDistance(fromMapID, fromX, fromY, fromPortal.exitMapID, fromPortal.exitX, fromPortal.exitY)
        if walkToExit == math.huge then
            -- Exit portal is on a different sub-map (e.g. Harandar Den vs Harandar)
            walkToExit = 200
        end
        exitCost = walkToExit + PORTAL_COST
    elseif ns.WALKABLE_ZONES[fromMapID] then
        -- Walking from Eversong/ZA/SM to SM center area
        exitCost = self:WorldDistance(fromMapID, fromX, fromY, ns.ZONE_SILVERMOON, 0.5, 0.65)
        if exitCost == math.huge then exitCost = 300 end
    else
        return math.huge -- unknown zone
    end

    local toPortal = ns.PORTALS[toMapID]
    local entryCost
    if toPortal then
        -- SM walk between portals + loading screen + walk to destination
        local smOriginX = fromPortal and fromPortal.smX or 0.5
        local smOriginY = fromPortal and fromPortal.smY or 0.65
        local smWalk = self:WorldDistance(ns.ZONE_SILVERMOON, smOriginX, smOriginY,
                                          ns.ZONE_SILVERMOON, toPortal.smX, toPortal.smY)
        if smWalk == math.huge then smWalk = 100 end
        local walkToDest = self:WorldDistance(toMapID, toPortal.exitX, toPortal.exitY, toMapID, toX, toY)
        if walkToDest == math.huge then walkToDest = 200 end
        entryCost = smWalk + PORTAL_COST + walkToDest
    elseif ns.WALKABLE_ZONES[toMapID] then
        -- Walking from SM to destination in Eversong/ZA
        local walkDist = self:WorldDistance(ns.ZONE_SILVERMOON, 0.5, 0.65, toMapID, toX, toY)
        if walkDist == math.huge then walkDist = 400 end
        entryCost = walkDist
    else
        return math.huge
    end

    return exitCost + entryCost
end

------------------------------------------------------------------------
-- Build the step-by-step route between two beast locations
------------------------------------------------------------------------

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

    -- Need portal travel through Silvermoon
    local fromPortal = ns.PORTALS[fromMapID]
    local toPortal = ns.PORTALS[toMapID]

    local beastName = beastEntry.beast.name

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
    for _, tp in ipairs(ns.TELEPORTS) do
        local destMapID, destX, destY = tp.destMapID, tp.destX, tp.destY

        -- Hearthstone: resolve destination from bind location
        if tp.itemID == 6948 then
            destMapID, destX, destY = self:ResolveHearthstone()
            if not destMapID then
                -- HS not bound to a known Midnight inn, skip it
                destMapID = nil
            end
        end

        if destMapID then
            local hasItem = C_Item.GetItemCount(tp.itemID, false) > 0 or tp.itemID == 6948
            if hasItem then
                local startTime, duration = C_Item.GetItemCooldown(tp.itemID)
                local offCooldown = (startTime == 0) or (GetTime() >= startTime + duration)
                if offCooldown then
                    table.insert(available, {
                        name = tp.name,
                        itemID = tp.itemID,
                        destMapID = destMapID,
                        destX = destX,
                        destY = destY,
                        portalCosts = tp.portalCosts,
                    })
                end
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

    -- Get player position
    local playerMapID = C_Map.GetBestMapForUnit("player")
    local playerPos = C_Map.GetPlayerMapPosition(playerMapID, "player")
    local playerX, playerY
    if playerPos then
        playerX, playerY = playerPos.x, playerPos.y
    else
        playerX, playerY = 0.5, 0.5
    end

    local teleports = self:GetAvailableTeleports()
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

        local totalCost = 0
        for _, c in ipairs(legCosts) do totalCost = totalCost + c end

        -- Try assigning teleports to the most expensive cross-zone return legs
        local tpAssignment = {}
        if #teleports > 0 then
            -- Find legs that involve returning to SM (cross-zone legs)
            local returnLegs = {}
            prevMapID = playerMapID
            for i, entry in ipairs(perm) do
                local toMapID = entry.beast.mapID
                local needsPortal = not (prevMapID == toMapID or
                    (ns.WALKABLE_ZONES[prevMapID] and ns.WALKABLE_ZONES[toMapID]))
                if needsPortal and legCosts[i] < math.huge then
                    table.insert(returnLegs, { index = i, cost = legCosts[i] })
                end
                prevMapID = toMapID
            end

            -- Sort by cost descending — assign teleports to most expensive legs first
            table.sort(returnLegs, function(a, b) return a.cost > b.cost end)

            local tpSavings = 0
            for j = 1, math.min(#teleports, #returnLegs) do
                local leg = returnLegs[j]
                local tp = teleports[j]
                -- Teleport replaces the entire leg. New cost: loading screens + travel from TP dest to beast.
                local entry = perm[leg.index]
                local tpLoadCost = tp.portalCosts * PORTAL_COST
                local travelFromTP = self:TravelCost(tp.destMapID, tp.destX, tp.destY,
                                                     entry.beast.mapID, entry.beast.x, entry.beast.y)
                if travelFromTP == math.huge then travelFromTP = 1000 end
                local newCost = tpLoadCost + travelFromTP
                local saving = leg.cost - newCost
                if saving > 0 then
                    tpSavings = tpSavings + saving
                    tpAssignment[leg.index] = tp
                end
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
    if TomTom and TomTom.AddWaypoint then
        local opts = {
            title = step.name,
            persistent = false,
            minimap = true,
            world = true,
            crazy = true,
            arrivaldistance = 20,
            cleardistance = 0, -- we manage removal ourselves
        }
        -- Use distance callback to auto-advance for beast steps
        if step.type == "beast" then
            opts.callbacks = TomTom:DefaultCallbacks(opts)
            opts.callbacks.distance = opts.callbacks.distance or {}
            opts.callbacks.distance[20] = function()
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

    -- Print route summary
    ns.addon:Print("Route planned (" .. #steps .. " steps):")
    for i, step in ipairs(steps) do
        local icon = step.type == "beast" and "|cff00ff00" or step.type == "teleport" and "|cff00ccff" or "|cffffff00"
        ns.addon:Printf("  %d. %s%s|r", i, icon, step.name)
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
        local step = navSteps[navIndex]
        ns.addon:Printf("Step %d/%d: %s", navIndex, #navSteps, step.name)
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
        return false
    end

    local steps = self:SolveRoute(remaining)
    if not steps or #steps == 0 then
        return false
    end

    -- Replace the current route with the new plan
    ClearCurrentWaypoint()
    local savedVisited = navVisitedQuests
    local savedCraftable = navCraftableOnly
    navSteps = steps
    navIndex = 1
    navVisitedQuests = savedVisited
    navCraftableOnly = savedCraftable

    ns.addon:Print("Route re-planned (" .. #steps .. " steps remaining):")
    for i, step in ipairs(steps) do
        local icon = step.type == "beast" and "|cff00ff00" or step.type == "teleport" and "|cff00ccff" or "|cffffff00"
        ns.addon:Printf("  %d. %s%s|r", i, icon, step.name)
    end

    local step = navSteps[1]
    ns.addon:Printf("Step 1/%d: %s", #navSteps, step.name)
    navUID = SetTomTomWaypoint(step)
    ns.MainWindow:Refresh()
    return true
end

function ns.Routing:StopNavigation()
    ClearCurrentWaypoint()
    navSteps = nil
    navIndex = 0
    navVisitedQuests = {}
end

function ns.Routing:IsNavigating()
    return navSteps ~= nil and navIndex > 0
end

function ns.Routing:GetCurrentStep()
    if navSteps and navIndex > 0 and navIndex <= #navSteps then
        return navSteps[navIndex], navIndex, #navSteps
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

    -- If current step is a portal and we're now in the right zone, advance
    if step.type == "portal" then
        local currentMapID = C_Map.GetBestMapForUnit("player")
        -- Portal step: the arrow was pointing to a portal. If we've changed zone,
        -- the player likely took it. Advance to next step.
        if currentMapID ~= step.mapID then
            self:AdvanceWaypoint()
        end
    elseif step.type == "teleport" then
        -- Teleport: if we're now in Silvermoon, advance
        local currentMapID = C_Map.GetBestMapForUnit("player")
        if currentMapID == ns.ZONE_SILVERMOON then
            self:AdvanceWaypoint()
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
