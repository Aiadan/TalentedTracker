local addonName, ns = ...  -- luacheck: ignore 211/addonName

ns.SKINNING_SKILL_LINE_ID = 2917

------------------------------------------------------------------------
-- Zone definitions
------------------------------------------------------------------------

-- Zone IDs
ns.ZONE_SILVERMOON   = 2393
ns.ZONE_EVERSONG     = 2395
ns.ZONE_ZULAMAN      = 2437
ns.ZONE_HARANDAR     = 2413
ns.ZONE_HARANDAR_DEN = 2576
ns.ZONE_VOIDSTORM    = 2405

-- Sub-zone map IDs that should be treated as their parent zone for routing
ns.ZONE_ALIASES = {
    [ns.ZONE_HARANDAR_DEN] = ns.ZONE_HARANDAR,
}

-- Zones walkable from Silvermoon (no portal needed)
ns.WALKABLE_ZONES = {
    [ns.ZONE_SILVERMOON] = true,
    [ns.ZONE_EVERSONG]   = true,
    [ns.ZONE_ZULAMAN]    = true,
}

-- Portal connections: zone -> { exitPortal, smPortal }
-- exitPortal: portal IN the zone that takes you to SM
-- smPortal: portal IN Silvermoon that takes you to the zone
ns.PORTALS = {
    [ns.ZONE_HARANDAR] = {
        exitMapID = ns.ZONE_HARANDAR_DEN,
        exitX = 0.6467, exitY = 0.7095,
        exitName = "Eversong Rootway",
        exitPoiSearch = "Eversong",
        exitPoiMapID = ns.ZONE_HARANDAR_DEN,
        smX = 0.369, smY = 0.682,
        smName = "Rootway to Harandar",
        smPoiSearch = "Harandar",
        smPoiMapID = ns.ZONE_SILVERMOON,
    },
    [ns.ZONE_VOIDSTORM] = {
        exitMapID = ns.ZONE_VOIDSTORM,
        exitX = 0.516, exitY = 0.702,
        exitName = "Portal to Silvermoon",
        exitPoiSearch = "Silvermoon",
        exitPoiMapID = ns.ZONE_VOIDSTORM,
        smX = 0.353, smY = 0.655,
        smName = "Portal to Voidstorm",
        smPoiSearch = "Voidstorm",
        smPoiMapID = ns.ZONE_SILVERMOON,
    },
}

-- Direct zone-to-zone portals (shortcuts that skip Silvermoon)
-- arrivalMapID/X/Y = where you end up in the destination zone after taking the portal
ns.DIRECT_PORTALS = {
    {
        fromZone = ns.ZONE_HARANDAR,
        toZone = ns.ZONE_VOIDSTORM,
        portalMapID = ns.ZONE_HARANDAR_DEN,
        portalX = 0.617, portalY = 0.728,
        portalName = "Portal to Voidstorm",
        poiSearch = "Voidstorm",
        poiMapID = ns.ZONE_HARANDAR_DEN,
        arrivalMapID = ns.ZONE_VOIDSTORM,
        arrivalX = 0.516, arrivalY = 0.702,  -- near the SM portal area in Voidstorm
    },
}

-- Known inns in Midnight zones, keyed by GetBindLocation() return value (subzone name).
-- Used to determine where the hearthstone teleports to.
ns.INNS = {
    -- Silvermoon City
    ["Wayfarer's Rest"]    = { mapID = ns.ZONE_SILVERMOON, x = 0.670, y = 0.622 },
    -- Eversong Woods
    ["Fairbreeze Village"] = { mapID = ns.ZONE_EVERSONG,   x = 0.462, y = 0.460 },  -- Sylmara Dawnpetal
    ["Goldenmist Village"] = { mapID = ns.ZONE_EVERSONG,   x = 0.392, y = 0.614 },  -- Innkeeper Areyn
    ["Tranquillien"]       = { mapID = ns.ZONE_EVERSONG,   x = 0.490, y = 0.684 },  -- Innkeeper Kalarin
    -- Zul'Aman
    ["Witherbark Bluffs"]  = { mapID = ns.ZONE_ZULAMAN,    x = 0.368, y = 0.234 },  -- Gav'jan
    ["Camp Stonewash"]     = { mapID = ns.ZONE_ZULAMAN,    x = 0.464, y = 0.256 },  -- Provisioner Jok
    ["Amani'Zar Village"]  = { mapID = ns.ZONE_ZULAMAN,    x = 0.454, y = 0.650 },  -- Tavikko
    -- Harandar
    ["The Den"]            = { mapID = ns.ZONE_HARANDAR,   x = 0.508, y = 0.554 },  -- Yinaa
    ["Har'alnor Den"]      = { mapID = ns.ZONE_HARANDAR,   x = 0.310, y = 0.650 },  -- Narou
    ["Har'mara"]           = { mapID = ns.ZONE_HARANDAR,   x = 0.350, y = 0.228 },  -- Gnu'la
    ["Har'athir"]          = { mapID = ns.ZONE_HARANDAR,   x = 0.690, y = 0.516 },  -- Tla'nith
    -- Voidstorm
    ["Dusk's Repose"]      = { mapID = ns.ZONE_VOIDSTORM,  x = 0.530, y = 0.682 },  -- Hospitus
    ["Locus Point"]        = { mapID = ns.ZONE_VOIDSTORM,  x = 0.416, y = 0.746 },  -- Darkhearth Kein
    ["The Ingress"]        = { mapID = ns.ZONE_VOIDSTORM,  x = 0.356, y = 0.586 },  -- Franelle Darkdreamer
}

-- Teleport anchors
-- Priority within same portalCosts is determined by list order (sort is stable)
-- Order: Mage teleport > Astral Recall > Hearthstone > Arcantina Key
ns.TELEPORTS = {
    {
        name = "Teleport: Silvermoon City",
        spellID = 1259190,
        destMapID = ns.ZONE_SILVERMOON,
        destX = 0.5274, destY = 0.6535,
        portalCosts = 1, -- 1 loading screen, no cooldown
    },
    {
        name = "Astral Recall",
        spellID = 556,
        portalCosts = 1, -- 1 loading screen
        resolveFromBind = true,
    },
    {
        name = "Hearthstone",
        itemID = 6948,
        portalCosts = 1, -- 1 loading screen
        -- destMapID/destX/destY resolved at runtime from GetBindLocation()
    },
    {
        name = "Personal Key to the Arcantina",
        itemID = 253629,
        isToy = true,
        destMapID = ns.ZONE_SILVERMOON,
        destX = 0.670, destY = 0.622,
        portalCosts = 2, -- 2 loading screens (into Arcantina, then out to SM)
    },
}

------------------------------------------------------------------------
-- Beast data
------------------------------------------------------------------------

ns.BEASTS = {
    {
        name = "Gloomclaw",
        npcID = 245688,
        questID = 88545,
        lureItemID = 238652,
        lureName = "Majestic Eversong Lure",
        mapID = 2395,
        x = 0.4200,
        y = 0.7994,
    },
    {
        name = "Silverscale",
        npcID = 245699,
        questID = 88526,
        lureItemID = 238653,
        lureName = "Majestic Zul'Aman Lure",
        mapID = 2437,
        x = 0.4782,
        y = 0.5332,
    },
    {
        name = "Lumenfin",
        npcID = 245690,
        questID = 88531,
        lureItemID = 238654,
        lureName = "Majestic Harandar Lure",
        mapID = 2413,
        x = 0.6685,
        y = 0.4771,
    },
    {
        name = "Umbrafang",
        npcID = 247096,
        questID = 88532,
        lureItemID = 238655,
        lureName = "Majestic Voidstorm Lure",
        mapID = 2405,
        x = 0.5460,
        y = 0.6580,
    },
    {
        name = "Netherscythe",
        npcID = 247101,
        questID = 88524,
        lureItemID = 238656,
        lureName = "Grand Beast Lure",
        mapID = 2405,
        x = 0.4325,
        y = 0.8275,
    },
}

-- Set of lure item IDs for recipe output matching
ns.LURE_ITEM_IDS = {}
for _, beast in ipairs(ns.BEASTS) do
    ns.LURE_ITEM_IDS[beast.lureItemID] = beast
end
