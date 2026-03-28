local addonName, ns = ...  -- luacheck: ignore 211/addonName

ns.SKINNING_SKILL_LINE_ID = 2917

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
