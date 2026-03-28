# Talented Tracker

Addon for tracking daily renowned beast skinning in WoW: Midnight.

## Architecture

- **Ace3 addon** using AceAddon, AceConsole, AceEvent
- **4 Lua files** loaded in order: Data → RecipeCache → Core → Integrations
- **Namespace pattern:** `(addonName, ns)` shared across all files
- `ns.addon` = the Ace3 addon object (TalentedTracker)

## Dependencies

- **Ace3** (hard) — addon framework
- **Mapzeroth** (hard) — multi-destination routing via `RouteMultiDestinationV2()`
- **Auctionator** (optional) — shopping list via `Auctionator.API.v1.CreateShoppingList()`

## Key Data

5 renowned beasts defined in `Data.lua` with quest IDs, lure item IDs, NPC IDs, map coordinates.

Daily completion tracked via `C_QuestLog.IsQuestFlaggedCompleted(questID)`.

Lures are bind-on-pickup — cannot be bought on AH, only crafted. Sixth Sense is a debuff at the lure spot, not a learnable spell.

## Recipe Cache

Recipe spell IDs and reagent lists are server-side data discovered dynamically:
- Scans `C_TradeSkillUI.GetFilteredRecipeIDs()` when profession window opens
- Matches recipe output items against known lure item IDs
- Cached in SavedVariables (`recipeCache`) — persists across sessions
- Only recipes the player knows appear, so cache also tracks craftability

## Slash Commands

- `/tt` — status overview
- `/tt route` — Mapzeroth route to beasts you can lure
- `/tt route all` — route to ALL unskinned beasts
- `/tt shop` — Auctionator reagent shopping list
- `/tt scan` — force recipe rescan
