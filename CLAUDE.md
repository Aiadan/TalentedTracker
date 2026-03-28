# Talented Tracker

Addon for tracking daily renowned beast skinning in WoW: Midnight.

## Architecture

- **Ace3 addon** using AceAddon, AceConsole, AceEvent
- **7 Lua files** loaded in order: Data → Routing → RecipeCache → Core → MainWindow → MinimapButton → Integrations
- **Namespace pattern:** `(addonName, ns)` shared across all files
- `ns.addon` = the Ace3 addon object (TalentedTracker)

## Dependencies

- **Ace3** (embedded) — addon framework
- **TomTom** (optional) — waypoint arrows; falls back to built-in map pin
- **Auctionator** (optional) — shopping list via `Auctionator.API.v1.CreateShoppingList()`

## Key Data

5 renowned beasts defined in `Data.lua` with quest IDs, lure item IDs, NPC IDs, map coordinates.

Daily completion tracked via `C_QuestLog.IsQuestFlaggedCompleted(questID)`.

Lures are bind-on-pickup — cannot be bought on AH, only crafted. Sixth Sense is a debuff at the lure spot, not a learnable spell.

## Routing

Custom TSP solver in `Routing.lua`:
- Models Midnight portal network (SM ↔ Harandar, SM ↔ Voidstorm; Eversong/Zul'Aman walkable)
- Brute-force permutation (5! = 120 max) with portal hop costs
- Hearthstone bind location resolved via `GetBindLocation()` → `ns.INNS` lookup
- Arcantina Key as second teleport anchor
- Teleports assigned to most expensive return legs
- Re-plans after each beast completion or skip (cooldowns may have changed)
- TomTom step-by-step navigation with auto-advance on arrival (20yd) and zone change

## Recipe Cache

Recipe spell IDs and reagent lists are server-side data discovered dynamically:
- Scans `C_TradeSkillUI.GetFilteredRecipeIDs()` when profession window opens
- Matches recipe output items against known lure item IDs
- Cached in SavedVariables (`recipeCache`) — persists across sessions
- Only recipes the player knows appear, so cache also tracks craftability

## Slash Commands

- `/tt` — toggle main window
- `/tt route` — route to beasts you can lure
- `/tt route all` — route to ALL unskinned beasts
- `/tt shop` — Auctionator reagent shopping list
- `/tt scan` — force recipe rescan
