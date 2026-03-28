std = "lua51"
max_line_length = 160

exclude_files = {
    "Libs/",
}

ignore = {
    "211/addonName",
    "212/self",
}

globals = {
    "LibStub",
}

read_globals = {
    -- WoW API
    "C_Item",
    "C_Map",
    "C_QuestLog",
    "C_Timer",
    "C_TradeSkillUI",
    "C_AddOns",
    "CreateFrame",
    "Enum",
    "GameTooltip",
    "GameTooltip_Hide",
    "GetItemInfo",
    "UIParent",
    "UISpecialFrames",

    -- WoW globals
    "GREEN_FONT_COLOR",
    "RED_FONT_COLOR",
    "NORMAL_FONT_COLOR",

    -- Optional dependency globals
    "Auctionator",
}
