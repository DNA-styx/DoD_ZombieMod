# DoD:S Zombie Mod - Plugin Development Specification v1.3.2

## Overview

Complete guide for creating custom human skill plugins and zombie class plugins for the DoD:S Zombie Mod. This modular plugin system allows developers to create custom skills and zombie classes without modifying the main plugin.

**Version 1.3.2 Changes:**
- Added pitfall documentation for repeating class-poll timers (zombie class plugins)
- Updated zombie class plugin template to include team validation in poll timers

**Version 1.3.1 Changes (dod_zm.inc v1.3.1):**
- Added `ZM_PREFIX_PERSONAL` and `ZM_PREFIX_BROADCAST` chat prefix constants
- Plugin developers should use these instead of raw color codes

**Version 1.3 Changes (dod_zm.inc v1.3.0):**
- Added zombie class API: `ZM_RegisterZombieClass`, `ZM_GetClientZombieClass`, `ZM_GetZombieClassName`
- Added `ZMClassID` enum and `ZM_MAX_CLASS_NAME` / `ZM_MAX_CLASS_DESC` constants
- Added `ZM_OnZombieDeath` forward — implement this to attach a death effect to your class
- Backward compatible: skill plugins compiled against v1.1.0 load without changes

**Version 1.2 Changes:**
- Removed message helper functions from public API (use native PrintToChat with color codes)
- Simplified API to core functionality only

**Previous Features:**
- Duplicate registration protection — by name and plugin handle (v0.9.10+)
- Modular skill and class system with dynamic menus
- Forward-based communication

---

## Quick Start (5 Minutes)

### 1. Include the API Header
```sourcepawn
#include <sourcemod>
#include <sdktools>
#include <dod_zm>  // Required API header
```

### 2. Store Skill ID
```sourcepawn
ZMSkillID g_SkillID = ZM_SKILL_INVALID;
```

### 3. Register Your Skill
```sourcepawn
public void OnAllPluginsLoaded()
{
    if (g_SkillID == ZM_SKILL_INVALID && ZM_IsLoaded())
    {
        g_SkillID = ZM_RegisterHumanSkill(
            "My Skill",              // Name in menu
            "Does something cool"    // Description
        );
    }
}

public void OnLibraryAdded(const char[] name)
{
    if (StrEqual(name, ZM_LIBRARY) && g_SkillID == ZM_SKILL_INVALID)
        g_SkillID = ZM_RegisterHumanSkill("My Skill", "Does something cool");
}
```

### 4. Check If Active
```sourcepawn
public Action OnPlayerRunCmd(int client, int &buttons, /*...*/)
{
    // Check if player has YOUR skill
    if (ZM_GetClientSkill(client) != g_SkillID)
        return Plugin_Continue;
    
    // Your skill logic here
    if ((buttons & IN_ATTACK2) && !(g_LastButtons[client] & IN_ATTACK2))
    {
        ActivateAbility(client);
    }
    
    g_LastButtons[client] = buttons;
    return Plugin_Continue;
}
```

### 5. Compile & Deploy
```bash
./compile.sh dod_zm_myskill.sp
# Place .smx in plugins/ folder
sm plugins load dod_zm_myskill
```

Done! Your skill appears in the equipment menu.

---

## System Architecture

### Main Components
- **Main Plugin:** `dod_zombiemod.smx` - Core zombie mod with native registrations
- **API Header:** `dod_zm.inc` - Defines natives, forwards, helper functions, message prefixes
- **Skill Plugins:** `dod_zm_*.smx` - Individual skill plugins that register with main plugin

### How It Works
1. Main plugin loads and registers natives via `AskPluginLoad2`
2. Main plugin creates library `"dod_zm_core"`
3. Skill plugins load and register via `ZM_RegisterHumanSkill()`
4. Main plugin builds dynamic menu with all registered skills
5. Players select skills from menu (locked per life)
6. Skill plugins check `ZM_GetClientSkill(client) == g_SkillID` to activate

### Plugin Reload Support (v0.8.8+)
- Main plugin detects duplicate registrations
- Skill plugins can be reloaded without creating duplicate menu entries
- Same skill ID maintained across reloads

---

## Chat Messages

### Standard Message Format

All chat messages must use `ZM_Chat()` or `ZM_ChatAll()` — stock functions
defined in `dod_zm.inc` that handle the prefix and colour automatically.
Do **not** call `PrintToChat` / `PrintToChatAll` directly with raw colour
codes. Getting colour codes wrong (wrong position, leading space, wrong
code for DoD:S) produces white text.

**Personal Messages (to one player):**
```sourcepawn
ZM_Chat(client, "Ability activated!");
ZM_Chat(client, "Cooldown: %d seconds", remaining);
```

**Broadcast Messages (to all players):**
```sourcepawn
ZM_ChatAll("%N selected a skill!", client);
```

Both functions produce `[ZM] message` in green, regardless of the player's
team. `\x04` is confirmed green in DoD:S for all teams. `\x03` is not used
as it renders as team colour and appears white for some players.

**Translation phrases** work the same way — pass `%t` as the format:
```sourcepawn
ZM_Chat(client, "%t", "My Phrase Key");
ZM_ChatAll("%t", "My Broadcast Phrase", client);
```

**Common mistake — do not do this:**
```sourcepawn
// Wrong — leading space before \x04 breaks colour
PrintToChat(client, " \x04[ZM]\x01 message");

// Wrong — \x04 passed as %s argument, not in literal format string
PrintToChat(client, "%s message", "\x04[ZM]\x01");

// Correct
ZM_Chat(client, "message");
```

---

## Complete API Reference

#### `ZM_RegisterHumanSkill`
```sourcepawn
ZMSkillID ZM_RegisterHumanSkill(const char[] name, const char[] description)
```
**Purpose:** Register your skill with the main plugin  
**When:** Call in `OnAllPluginsLoaded()` or `OnLibraryAdded()`  
**Parameters:**
- `name` - Skill name shown in menu (max 64 chars)
- `description` - Skill description shown to players (max 128 chars)

**Returns:** `ZMSkillID` (skill ID) or `ZM_SKILL_INVALID` (-1) on failure

**Example:**
```sourcepawn
g_SkillID = ZM_RegisterHumanSkill("Medic", "Heal teammates with right-click");
```

**Important:** Always check `g_SkillID == ZM_SKILL_INVALID` before registering to avoid duplicate attempts.

---

#### `ZM_GetClientSkill`
```sourcepawn
ZMSkillID ZM_GetClientSkill(int client)
```
**Purpose:** Get the currently active skill for a client  
**Parameters:**
- `client` - Client index (1-MaxClients)

**Returns:** `ZMSkillID` or `ZM_SKILL_NONE` (0) if no skill selected

**Example:**
```sourcepawn
if (ZM_GetClientSkill(client) == g_SkillID)
{
    // Player has YOUR skill active
}
```

---

#### `ZM_IsClientHuman`
```sourcepawn
bool ZM_IsClientHuman(int client)
```
**Purpose:** Check if client is on human team (Allies)  
**Parameters:**
- `client` - Client index

**Returns:** `true` if human, `false` otherwise

---

#### `ZM_IsClientZombie`
```sourcepawn
bool ZM_IsClientZombie(int client)
```
**Purpose:** Check if client is on zombie team (Axis)  
**Parameters:**
- `client` - Client index

**Returns:** `true` if zombie, `false` otherwise

---

#### `ZM_IsModActive`
```sourcepawn
bool ZM_IsModActive()
```
**Purpose:** Check if zombie mod is currently active  
**Returns:** `true` if active, `false` otherwise

---

#### `ZM_IsLoaded` (Stock Helper)
```sourcepawn
bool ZM_IsLoaded()
```
**Purpose:** Check if main ZM plugin is loaded  
**Returns:** `true` if loaded, `false` otherwise  
**Note:** This is a stock function defined in the .inc file

---

### Forwards (Events You Receive)

#### `ZM_OnSkillAssigned`
```sourcepawn
forward void ZM_OnSkillAssigned(int client, ZMSkillID skillID);
```
**Purpose:** Called when a player selects a skill  
**When:** After player spawns and selects from equipment menu  
**Parameters:**
- `client` - Client who selected skill
- `skillID` - The skill ID they selected (0 = none, 1+ = skill)

**Use Case:** Initialize skill state and confirm selection to the player.

**You must use `PrintCenterText` to confirm skill selection.** The equipment
menu covers most of the screen when this forward fires — a chat message alone
will not be seen. Center text is visible over the top of the menu and gives
the player clear confirmation of what they selected. Follow it with a
`ZM_Chat` message describing how to use the skill.

**Example:**
```sourcepawn
public void ZM_OnSkillAssigned(int client, ZMSkillID skillID)
{
    if (skillID == g_SkillID)
    {
        PrintCenterText(client, "Medic skill selected!");
        ZM_Chat(client, "Medic selected — right-click to heal.");
    }
}
```

---

#### `ZM_OnRoundStart`
```sourcepawn
forward void ZM_OnRoundStart();
```
**Purpose:** Called when round starts  
**Use Case:** Reset round-based state, counters, cooldowns

---

#### `ZM_OnRoundEnd`
```sourcepawn
forward void ZM_OnRoundEnd();
```
**Purpose:** Called when round ends  
**Use Case:** Clean up round state

---

#### `ZM_OnClientDeath`
```sourcepawn
forward void ZM_OnClientDeath(int client);
```
**Purpose:** Called when a client dies  
**Parameters:**
- `client` - Client who died

**Use Case:** Kill timers, remove buffs, clean up client state

---

#### `ZM_OnClientSpawn`
```sourcepawn
forward void ZM_OnClientSpawn(int client, ZMTeam team);
```
**Purpose:** Called when a client spawns  
**Parameters:**
- `client` - Client who spawned
- `team` - Team they spawned on (`ZM_TEAM_ALLIES` or `ZM_TEAM_AXIS`)

**Use Case:** Reset per-life state

---

### Enums & Constants

```sourcepawn
#define ZM_LIBRARY "dod_zm_core"

/* Chat prefix constants */
#define ZM_PREFIX_PERSONAL  "\x04[ZM]\x01"  // Olive — personal messages
#define ZM_PREFIX_BROADCAST "\x03[ZM]\x01"  // Green — broadcast messages

#define ZM_MAX_SKILL_NAME 64
#define ZM_MAX_SKILL_DESC 128

// Message prefixes for standardized formatting
#define ZM_PREFIX_PERSONAL "\x04[ZM]\x01"    // Olive prefix for individual messages
#define ZM_PREFIX_BROADCAST "\x03[ZM]\x01"   // Green prefix for broadcast messages

enum ZMSkillID
{
    ZM_SKILL_INVALID = -1,  // Registration failed
    ZM_SKILL_NONE = 0,      // No skill selected
    // Skills IDs start at 1 and increment
};

enum ZMTeam
{
    ZM_TEAM_UNASSIGNED = 0,
    ZM_TEAM_SPECTATOR = 1,
    ZM_TEAM_ALLIES = 2,    // Humans
    ZM_TEAM_AXIS = 3       // Zombies
};
```

---

## Zombie Class API

The zombie class system allows external plugins to register new zombie classes and attach death effects. Built-in classes (Normal, Gas, TNT, Ghost) are pre-registered with IDs 0–3.

---

### `ZM_RegisterZombieClass`
```sourcepawn
ZMClassID ZM_RegisterZombieClass(const char[] name, const char[] description)
```
**Purpose:** Register a zombie class with the main plugin  
**When:** Call in `OnAllPluginsLoaded()` or `OnLibraryAdded()`  
**Returns:** `ZMClassID` or `ZM_CLASS_INVALID` (-1) on failure

**Note:** If a class with the same name is already registered (e.g. a built-in), the existing slot is returned and updated. This means a plugin registering "TNT Zombie" will claim the pre-registered ID 2 — class selection menus and random assignment are unaffected.

---

### `ZM_GetClientZombieClass`
```sourcepawn
ZMClassID ZM_GetClientZombieClass(int client)
```
**Purpose:** Get the current zombie class ID for a client  
**Returns:** Class ID (0=Normal, 1=Gas, 2=TNT, 3=Ghost for built-ins)

---

### `ZM_GetZombieClassName`
```sourcepawn
void ZM_GetZombieClassName(ZMClassID classID, char[] buffer, int maxlength)
```
**Purpose:** Get the display name for any registered class ID

---

### `ZM_OnZombieDeath` (Forward)
```sourcepawn
forward void ZM_OnZombieDeath(int client, ZMClassID classID);
```
**Purpose:** Called when a zombie dies. Implement this to attach a death effect to your class.  
**Always check** `classID == g_ClassID` before acting — this fires for every zombie death.

**Example:**
```sourcepawn
public void ZM_OnZombieDeath(int client, ZMClassID classID)
{
    if (classID != g_ClassID)
        return;

    // Your death effect here
    float origin[3];
    GetClientAbsOrigin(client, origin);
    EmitAmbientSound("your/sound.wav", origin, SOUND_FROM_WORLD);

    // Optionally notify nearby players
    PrintToChatAll("\x03[ZM]\x01 %N triggered a death effect!", client);
}
```

---

### Zombie Class Enums & Constants
```sourcepawn
#define ZM_MAX_CLASS_NAME 64
#define ZM_MAX_CLASS_DESC 128

enum ZMClassID
{
    ZM_CLASS_INVALID = -1,  // Registration failed
    // Built-in IDs: 0=Normal, 1=Gas, 2=TNT, 3=Ghost
    // External classes start at 4+
};
```

---

### Zombie Class Plugin Template

```sourcepawn
#include <sourcemod>
#include <sdktools>
#include <dod_zm>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0.0"

public Plugin myinfo =
{
    name        = "DoD:S ZM Zombie Class - [Class Name]",
    author      = "[Your Name]",
    description = "[Class description]",
    version     = PLUGIN_VERSION,
    url         = ""
};

ZMClassID g_ClassID = ZM_CLASS_INVALID;

public void OnPluginStart()
{
    // Create ConVars, hook events, etc.
}

public void OnMapStart()
{
    // Precache sounds and models here
}

public void OnAllPluginsLoaded()
{
    if (g_ClassID == ZM_CLASS_INVALID && ZM_IsLoaded())
        g_ClassID = ZM_RegisterZombieClass("[Class Name]", "[Description]");
}

public void OnLibraryAdded(const char[] name)
{
    if (StrEqual(name, ZM_LIBRARY) && g_ClassID == ZM_CLASS_INVALID)
        g_ClassID = ZM_RegisterZombieClass("[Class Name]", "[Description]");
}

public void OnLibraryRemoved(const char[] name)
{
    if (StrEqual(name, ZM_LIBRARY))
        g_ClassID = ZM_CLASS_INVALID;
}

public void ZM_OnZombieDeath(int client, ZMClassID classID)
{
    if (classID != g_ClassID)
        return;

    // Implement your death effect here
}
```

---

### Pitfall: Repeating Class-Poll Timers Must Check Team

Zombie class plugins that use a repeating timer to poll `ZM_GetClientZombieClass` (because
real players choose their class from a menu after spawn) **must also verify the player is
still on the zombie team** before attaching any visual or applying any effect.

A player can transition from the zombie team to the human team between the timer being
started and it resolving — for example during a round reset or team change. Without the
team check, the timer will see a stale class ID and attach the visual to the now-human
player.

**Incorrect — missing team check:**
```sourcepawn
public Action Timer_CheckAndAttach(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);

    if (!client || !IsClientInGame(client))
        return Plugin_Stop;

    if (!IsPlayerAlive(client))
        return Plugin_Stop;

    if (ZM_GetClientZombieClass(client) == g_ClassID)
    {
        AttachVisual(client);   // BUG: client may now be human
        return Plugin_Stop;
    }

    return Plugin_Continue;
}
```

**Correct — team check included:**
```sourcepawn
public Action Timer_CheckAndAttach(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);

    if (!client || !IsClientInGame(client))
        return Plugin_Stop;

    if (!IsPlayerAlive(client))
        return Plugin_Stop;

    // Stop if player is no longer on the zombie team
    if (!ZM_IsClientZombie(client))
        return Plugin_Stop;

    if (ZM_GetClientZombieClass(client) == g_ClassID)
    {
        AttachVisual(client);
        return Plugin_Stop;
    }

    return Plugin_Continue;
}
```

---

## Common Patterns

### Pattern 1: Button-Activated Ability

```sourcepawn
int g_LastButtons[MAXPLAYERS+1];

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3])
{
    if (g_SkillID == ZM_SKILL_INVALID)
        return Plugin_Continue;
    
    if (!IsClientInGame(client) || !IsPlayerAlive(client))
        return Plugin_Continue;
    
    if (ZM_GetClientSkill(client) != g_SkillID)
        return Plugin_Continue;
    
    if (!ZM_IsClientHuman(client))
        return Plugin_Continue;
    
    // Detect RIGHT CLICK press (not hold!)
    if ((buttons & IN_ATTACK2) && !(g_LastButtons[client] & IN_ATTACK2))
    {
        ActivateAbility(client);
    }
    
    g_LastButtons[client] = buttons;
    return Plugin_Continue;
}
```

---

### Pattern 2: Cooldown System with Feedback

```sourcepawn
float g_NextUseTime[MAXPLAYERS+1];

void ActivateAbility(int client)
{
    float currentTime = GetGameTime();
    
    if (currentTime < g_NextUseTime[client])
    {
        float remaining = g_NextUseTime[client] - currentTime;
        ZM_Chat(client, "Ability on cooldown: %.1f seconds", remaining);
        return;
    }
    
    // Do ability
    DoAbilityEffect(client);
    
    // Set cooldown
    g_NextUseTime[client] = currentTime + 15.0;  // 15 seconds
    ZM_Chat(client, "Ability activated!");
}

// Reset on spawn
public void ZM_OnClientSpawn(int client, ZMTeam team)
{
    g_NextUseTime[client] = 0.0;
}
```

---

### Pattern 3: Temporary Buff

```sourcepawn
bool g_BuffActive[MAXPLAYERS+1];
Handle g_BuffTimer[MAXPLAYERS+1];

void ApplyBuff(int client)
{
    g_BuffActive[client] = true;
    
    // Apply effect
    SetEntityGravity(client, 0.5);
    
    // Timer to remove
    g_BuffTimer[client] = CreateTimer(10.0, Timer_RemoveBuff, 
        GetClientUserId(client));
    
    ZM_Chat(client, "Low gravity activated for 10 seconds!");
}

public Action Timer_RemoveBuff(Handle timer, int userId)
{
    int client = GetClientOfUserId(userId);
    if (client && IsClientInGame(client))
    {
        g_BuffActive[client] = false;
        SetEntityGravity(client, 1.0);
        g_BuffTimer[client] = null;
        
        ZM_Chat(client, "Buff expired!");
    }
    return Plugin_Stop;
}

// Clean up on death/disconnect
public void ZM_OnClientDeath(int client)
{
    if (g_BuffTimer[client] != null)
    {
        KillTimer(g_BuffTimer[client]);
        g_BuffTimer[client] = null;
    }
    g_BuffActive[client] = false;
}
```

---

### Pattern 4: Passive Ability with Broadcast

```sourcepawn
public void ZM_OnSkillAssigned(int client, ZMSkillID skillID)
{
    if (skillID == g_SkillID && ZM_IsClientHuman(client))
    {
        // Apply passive effect
        int health = GetClientHealth(client);
        SetEntityHealth(client, health + 50);
        
        PrintToChat(client, "\x04[ZM]\x01 \x03+50 HP\x01 bonus!");
        ZM_ChatAll("Player %N selected Tank skill!", client);
    }
}
```

---

### Pattern 5: Resource System with Feedback

```sourcepawn
int g_Charges[MAXPLAYERS+1];
#define MAX_CHARGES 5

void UseCharge(int client)
{
    if (g_Charges[client] >= MAX_CHARGES)
    {
        ZM_Chat(client, "No charges left (%d/%d)", 
            g_Charges[client], MAX_CHARGES);
        return;
    }
    
    g_Charges[client]++;
    
    // Do ability
    ZM_Chat(client, "Charge used (%d/%d)", 
        g_Charges[client], MAX_CHARGES);
}

// Reset on spawn
public void ZM_OnClientSpawn(int client, ZMTeam team)
{
    g_Charges[client] = 0;
}
```

---

## Required Plugin Structure

### Minimal Working Plugin

```sourcepawn
#include <sourcemod>
#include <sdktools>
#include <dod_zm>  // REQUIRED: Include the API

#pragma semicolon 1
#pragma newdecls required

// Plugin info
#define PLUGIN_VERSION "1.0.0"
#define PLUGIN_NAME "DoD:S ZM - Your Skill Name"

public Plugin myinfo = {
    name = PLUGIN_NAME,
    author = "Your Name",
    description = "Your skill description",
    version = PLUGIN_VERSION,
    url = ""
};

// Store skill ID
ZMSkillID g_SkillID = ZM_SKILL_INVALID;

// Initialize
public void OnPluginStart()
{
    // Hook events, create ConVars, etc.
}

// Register skill (when ZM already loaded)
public void OnAllPluginsLoaded()
{
    if (g_SkillID == ZM_SKILL_INVALID && ZM_IsLoaded())
    {
        g_SkillID = ZM_RegisterHumanSkill(
            "Your Skill",
            "What it does"
        );
    }
}

// Register skill (when ZM loads after us)
public void OnLibraryAdded(const char[] name)
{
    if (StrEqual(name, ZM_LIBRARY) && g_SkillID == ZM_SKILL_INVALID)
    {
        g_SkillID = ZM_RegisterHumanSkill(
            "Your Skill",
            "What it does"
        );
    }
}

// Handle ZM unloading
public void OnLibraryRemoved(const char[] name)
{
    if (StrEqual(name, ZM_LIBRARY))
    {
        // Clean up
        g_SkillID = ZM_SKILL_INVALID;
    }
}

// Clean up on disconnect
public void OnClientDisconnect(int client)
{
    // Clean up client state
}

// Your skill logic
public Action OnPlayerRunCmd(int client, int &buttons, /*...*/)
{
    if (ZM_GetClientSkill(client) != g_SkillID)
        return Plugin_Continue;
    
    // Your ability logic here
    
    return Plugin_Continue;
}
```

---

## Critical Requirements

### Must Have:

1. **Include the API:** `#include <dod_zm>`
2. **Store skill ID:** `ZMSkillID g_SkillID = ZM_SKILL_INVALID;`
3. **Register in OnAllPluginsLoaded:** Check `g_SkillID == ZM_SKILL_INVALID` first
4. **Register in OnLibraryAdded:** Check `g_SkillID == ZM_SKILL_INVALID` first
5. **Handle OnLibraryRemoved:** Clean up and reset `g_SkillID`
6. **Check skill active:** Always use `ZM_GetClientSkill(client) == g_SkillID`
7. **Check team:** Use `ZM_IsClientHuman(client)` for human-only abilities
8. **Confirm skill selection:** Use `PrintCenterText` in `ZM_OnSkillAssigned` — chat alone is not visible over the menu
9. **Use chat helpers:** Use `ZM_Chat(client, ...)` and `ZM_ChatAll(...)` — never call `PrintToChat` directly

### Common Mistakes:

1. Not checking if skill already registered (handled by main plugin in v0.8.8+)
2. Not checking if player has skill - ability works for everyone
3. Not tracking button state - spam on OnPlayerRunCmd
4. Not cleaning up timers - memory leaks
5. Forgetting OnLibraryAdded - broken if ZM reloads
6. Hardcoding skill ID - breaks when other skills load
7. Calling PrintToChat directly instead of ZM_Chat — inconsistent prefix and colour
8. Repeating class-poll timers missing `ZM_IsClientZombie` check — visual attaches to human on team transition

---

## File Naming & Locations

### File Names
```
dod_zm_skillname.sp
```

**Examples (skill plugins):**
- `dod_zm_medic.sp` - Medic skill
- `dod_zm_engineer.sp` - Engineer skill
- `dod_zm_scout.sp` - Scout skill

**Examples (zombie class plugins):**
- `dod_zm_tnt.sp` - TNT zombie death effect
- `dod_zm_gas.sp` - Gas zombie (if extracted)

### Directory Structure
```
addons/sourcemod/
├── scripting/
│   ├── include/
│   │   └── dod_zm.inc              ← API header (skill & class plugins)
│   ├── dod_zm_yourskill.sp         ← Your skill plugin
│   └── dod_zm_yourclass.sp         ← Your class plugin
└── plugins/
    ├── dod_zombiemod.smx           ← Main plugin
    ├── dod_zm_yourskill.smx        ← Your skill
    └── dod_zm_yourclass.smx        ← Your class
```

**Important:** The main plugin (`dod_zombiemod.smx`) does **NOT** need `dod_zm.inc`. The .inc file is **ONLY** for skill and class plugin developers.

---

## Testing Checklist

Before releasing your skill plugin:

- [ ] Plugin loads without main ZM plugin
- [ ] Plugin registers skill when ZM loads
- [ ] Plugin can be reloaded without duplicates (v0.9.10+)
- [ ] Skill appears in equipment menu
- [ ] Skill activates correctly
- [ ] Only works for humans (not zombies)
- [ ] Resets on death
- [ ] Resets on round start
- [ ] Timers cleaned up on disconnect
- [ ] No console errors
- [ ] Uses `ZM_Chat` / `ZM_ChatAll` for all chat messages
- [ ] Does not call `PrintToChat` / `PrintToChatAll` directly
- [ ] `ZM_OnSkillAssigned` uses `PrintCenterText` to confirm selection
- [ ] Good player feedback (clear messages, sounds)
- [ ] Works with other skills (no conflicts)
- [ ] Handles main plugin reload gracefully
- [ ] Repeating class-poll timers include `ZM_IsClientZombie` check (zombie class plugins)

---

## Debugging Tips

### Enable Logging
```sourcepawn
PrintToServer("[My Skill] Player %N activated ability", client);
LogMessage("[My Skill] Skill ID: %d, Player skill: %d", 
    g_SkillID, ZM_GetClientSkill(client));
```

### Check Registration
```sourcepawn
if (g_SkillID == ZM_SKILL_INVALID)
    SetFailState("Failed to register skill!");
else
    PrintToServer("[My Skill] Registered as ID %d", g_SkillID);
```

### Console Commands for Testing
```
sm plugins list              // List all plugins
sm plugins reload myskill    // Reload your skill
sm plugins unload myskill    // Unload your skill
```

---

## FAQ

**Q: Can I make skills for zombies?**  
A: Yes — use `ZM_RegisterZombieClass` and implement `ZM_OnZombieDeath` to attach a death effect to your class. See the Zombie Class API section above.

**Q: How many skills can be registered?**  
A: Currently 32, but this can be increased if needed.

**Q: Will my skill work if the main plugin reloads?**  
A: Yes! If you implement `OnLibraryAdded()` correctly, your skill will re-register automatically.

**Q: Can skills conflict with each other?**  
A: No - each skill has a unique ID and only activates when selected.

**Q: Can I make skills that cost money/points?**  
A: Not built-in, but you could integrate with an economy plugin.

**Q: What happens when I reload my skill plugin or upload a new .smx?**  
A: The main plugin matches by skill name (case-insensitive) and by plugin handle. Either match updates the existing slot in-place — no duplicate menu entries. This means `sm plugins reload`, map restarts with a new .smx, and plugin updates all work correctly without a full server restart.

**Q: How do I share my skill with others?**  
A: Share the .sp file! Others can compile it themselves. Consider posting on GitHub.

---

## Best Practices Summary

1. Always check `g_SkillID == ZM_SKILL_INVALID` before registering
2. Always check `ZM_GetClientSkill(client) == g_SkillID` before activating
3. Track button state to prevent spam
4. Clean up timers in disconnect/death handlers
5. Use `ZM_IsClientHuman()` for human-only abilities
6. Use `ZM_Chat(client, ...)` for personal messages
7. Use `ZM_ChatAll(...)` for broadcast messages
8. Test with main plugin reload scenarios
9. Document your skill's usage
10. Balance carefully (cooldowns, costs, effects)
11. Share with the community!

---

## Support

- **GitHub Issues:** https://github.com/DNA-styx/DoD_ZombieMod/issues
- **Discord:** https://discord.gg/bemuuRKscw
- **Documentation:** See `dod_zm.inc` for API details

---

## Quick Start Template

Copy this to start a new skill:

```sourcepawn
#include <sourcemod>
#include <sdktools>
#include <dod_zm>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0.0"
#define PLUGIN_NAME "DoD:S ZM - [Skill Name]"

public Plugin myinfo = {
    name = PLUGIN_NAME,
    author = "[Your Name]",
    description = "[Skill description]",
    version = PLUGIN_VERSION,
    url = ""
};

ZMSkillID g_SkillID = ZM_SKILL_INVALID;

public void OnPluginStart() {}

public void OnAllPluginsLoaded()
{
    if (g_SkillID == ZM_SKILL_INVALID && ZM_IsLoaded())
        g_SkillID = ZM_RegisterHumanSkill("[Name]", "[Description]");
}

public void OnLibraryAdded(const char[] name)
{
    if (StrEqual(name, ZM_LIBRARY) && g_SkillID == ZM_SKILL_INVALID)
        g_SkillID = ZM_RegisterHumanSkill("[Name]", "[Description]");
}

public void OnLibraryRemoved(const char[] name)
{
    if (StrEqual(name, ZM_LIBRARY))
        g_SkillID = ZM_SKILL_INVALID;
}

// Add your skill logic here
// Use ZM_Chat(client, "Message") for personal messages
// Use ZM_ChatAll("Message") for broadcasts
```

---

**End of Specification v1.3.2**

*This document contains everything needed to create custom skill and zombie class plugins for DoD:S Zombie Mod.*
