# Talented Tracker

A World of Warcraft addon for efficiently completing your daily renowned beast skinning in Midnight.

Talented Tracker knows where every beast is, which ones you've already skinned today, and plans the shortest route between them — accounting for portals, hearthstone location, and teleport cooldowns.

## Features

### Beast Tracking
- Shows all 5 renowned beasts with their daily status: skinned, have lure, can craft lure, or no recipe
- Automatically detects quest completion when you skin a beast
- Recipe data discovered automatically when you open your Skinning profession window (cached across sessions)

### Route Planning
- Calculates the optimal visit order across all Midnight zones using a shortest-path solver
- Models the full portal network: Silvermoon ↔ Harandar, Silvermoon ↔ Voidstorm, Harandar → Voidstorm shortcut, plus walkable Eversong Woods and Zul'Aman
- Factors in your hearthstone bind location — supports all 15 Midnight zone inns
- Uses the Personal Key to the Arcantina as a second teleport anchor (2 loading screens)
- Mages with Teleport: Silvermoon City get a third teleport option
- Shamans get a second hearthstone use through Astral Recall
- Teleports are assigned to the route legs where they save the most travel time
- Re-plans the route after every beast completion or skip, since cooldowns may have changed

### Step-by-Step Navigation
- Guides you through the route one waypoint at a time: beast → portal → beast → portal → ...
- Portal and teleport steps show which beast you're heading toward (e.g. "Portal to Harandar (Lumenfin)")
- Auto-advances when you arrive within 10 yards of a beast or when you complete the skinning quest
- Auto-advances on zone change when you take a portal
- Skips transit steps if you arrive in the beast's zone by an unexpected route
- Skip button to drop a beast from the route and re-plan
- Stop button to cancel navigation at any time
- Works with **TomTom** (crazy arrow) when installed
- Falls back to the built-in map pin system otherwise, with automatic supertracking of portal POIs

### Lure Action Button
- Automatically appears when you're standing at a beast location with the Sixth Sense debuff
- If you have the lure in your inventory, clicking the button places it at your feet instantly
- If you don't have the lure but know the recipe, clicking opens the profession window to the recipe
- Switches from craft to place automatically when the lure enters your bags
- Draggable, position is saved

### Auctionator Shopping List
- Creates a shopping list for reagents needed to craft lures you're missing
- Aggregates quantities across all needed lures and subtracts what you already have in your bags
- Requires the optional Auctionator addon

### Options
- **Include skinned beasts** — adds already-skinned beasts to routes and shopping lists (useful for pre-crafting tomorrow's lures or visiting locations where someone else may place a lure)
- **End at Silvermoon** — appends a return trip to Silvermoon City at the end of the route

## Slash Commands

| Command | Description |
|---------|-------------|
| `/tt` | Toggle the main window |
| `/tt route` | Plan route to beasts you can lure |
| `/tt route all` | Plan route to all unskinned beasts |
| `/tt shop` | Create Auctionator shopping list |
| `/tt scan` | Rescan skinning recipes |
| `/tt help` | Show available commands |

## Installation

Install from CurseForge, or clone this repository and symlink the `TalentedTracker` folder into your `Interface\AddOns` directory.

### Optional Dependencies
- **TomTom** — enables the crazy arrow for waypoint navigation
- **Auctionator** — enables the reagent shopping list feature

## Renowned Beasts

| Beast | Zone | Lure |
|-------|------|------|
| Gloomclaw | Eversong Woods | Majestic Eversong Lure |
| Silverscale | Zul'Aman | Majestic Zul'Aman Lure |
| Lumenfin | Harandar | Majestic Harandar Lure |
| Umbrafang | Voidstorm | Majestic Voidstorm Lure |
| Netherscythe | Voidstorm | Grand Beast Lure |
