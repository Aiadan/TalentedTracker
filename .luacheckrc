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
    "C_AreaPoiInfo",
    "C_Item",
    "C_Map",
    "C_QuestLog",
    "C_Spell",
    "C_SuperTrack",
    "C_UnitAuras",
    "C_Timer",
    "C_TradeSkillUI",
    "C_AddOns",
    "CreateFrame",
    "CreateVector2D",
    "Enum",
    "GameTooltip",
    "GameTooltip_Hide",
    "GetBindLocation",
    "GetItemInfo",
    "InCombatLockdown",
    "GetRealmName",
    "IsSpellKnown",
    "PlayerHasToy",
    "GetTime",
    "UiMapPoint",
    "UnitName",
    "UIErrorsFrame",
    "UIParent",
    "UISpecialFrames",

    -- WoW globals
    "GREEN_FONT_COLOR",
    "RED_FONT_COLOR",
    "NORMAL_FONT_COLOR",

    -- Optional dependency globals
    "Auctionator",
    "TomTom",
}
