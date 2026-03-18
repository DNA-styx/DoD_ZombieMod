/**
 * =============================================================================
 * DoD:S ZM - Barricade Builder Skill
 * Human skill plugin for moving props to build barricades
 * 
 * Based on "Gravity Gun" by Dron-elektron
 * Original: https://github.com/dronelektron/sm-gravity-gun
 * 
 * Modifications by claude.ai (guided by DNA.styx):
 * - Simplified from player-grabbing to prop-only manipulation
 * - Applied to all humans automatically (no skill selection required)
 * - Ray trace-based prop selection (crosshair aim)
 * - Knife right-click activation
 * - Removed admin systems, menus, and configuration
 * - Added natural prop settling on release
 * 
 * Version: 1.1.0
 * =============================================================================
 */

#include <sourcemod>
#include <sdktools>
#include <dod_zm>  // Include the ZM API

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.1.0"
#define PLUGIN_NAME "DoD:S ZM Human Ability - Barricade Builder"
#define PLUGIN_AUTHOR "Dron-elektron, modified by Claude.ai guided by DNA.styx"
#define PLUGIN_DESCRIPTION "Human ability: All humans can pick up and place in-game props with American knife right-click"

// Constants
#define ENTITY_NOT_FOUND -1
#define NO_PROP_HELD -1
#define MAX_PROP_DISTANCE 256.0      // Maximum distance to detect props
#define HOLD_DISTANCE 128.0          // Distance to hold prop from player
#define UPDATE_INTERVAL 0.05         // How often to update prop position (50ms)
#define SPEED_FACTOR 8.0             // How fast prop moves to target position
#define AIM_TOLERANCE 64.0           // Maximum distance from crosshair aim point to prop
#define SETTLE_VELOCITY -50.0        // Downward velocity when releasing props

// Weapon definitions for DoD:S
#define WEAPON_AMERKNIFE "weapon_amerknife"  /* American knife — the only trigger weapon */

// ============================================================================
// GLOBALS
// ============================================================================

// Global arrays to track player states
int g_heldProp[MAXPLAYERS + 1];           // Entity index of prop being held
bool g_isHoldingButton[MAXPLAYERS + 1];   // Is player holding +attack2
Handle g_updateTimer[MAXPLAYERS + 1];     // Timer handle for prop updates

// ============================================================================
// PLUGIN INFO & INITIALIZATION
// ============================================================================

public Plugin myinfo = {
    name = PLUGIN_NAME,
    author = PLUGIN_AUTHOR,
    description = PLUGIN_DESCRIPTION,
    version = PLUGIN_VERSION,
    url = ""
};

public void OnLibraryRemoved(const char[] name)
{
    /* Release all held props if main plugin unloads */
    if (StrEqual(name, ZM_LIBRARY))
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i))
                ReleaseProp(i);
        }
        
    }
}

// ============================================================================
// CLIENT MANAGEMENT
// ============================================================================

public void OnClientConnected(int client) {
    ResetClientState(client);
}

public void OnClientDisconnect(int client) {
    ReleaseProp(client);
    ResetClientState(client);
}

// Reset a client's state variables
void ResetClientState(int client) {
    g_heldProp[client] = NO_PROP_HELD;
    g_isHoldingButton[client] = false;
    g_updateTimer[client] = null;
}

// ============================================================================
// ZM API FORWARDS
// ============================================================================

public void ZM_OnRoundStart()
{
    // Release all props at round start
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client))
        {
            ReleaseProp(client);
        }
    }
}

public void ZM_OnClientDeath(int client)
{
    // Release prop when player dies
    ReleaseProp(client);
}

public void ZM_OnClientSpawn(int client, ZMTeam team)
{
    // Reset state when player spawns
    ResetClientState(client);
}

// ============================================================================
// MAIN ABILITY LOGIC
// ============================================================================

// Main command handler - called every frame for each player
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3]) {
    /* Early exit if ZM not loaded */
    if (!ZM_IsLoaded())
        return Plugin_Continue;
    
    if (!IsClientInGame(client) || !IsPlayerAlive(client))
        return Plugin_Continue;
    
    /* Ability applies to all humans — release prop if player is no longer human */
    if (!ZM_IsClientHuman(client))
    {
        if (g_heldProp[client] != NO_PROP_HELD)
            ReleaseProp(client);
        return Plugin_Continue;
    }
    
    // Check if player has a valid weapon equipped (knife or pistol)
    if (!HasValidWeaponEquipped(client)) {
        // If they don't have valid weapon out but are holding a prop, release it
        if (g_heldProp[client] != NO_PROP_HELD) {
            ReleaseProp(client);
        }
        return Plugin_Continue;
    }
    
    // Use IN_ATTACK2 (right click) instead of IN_ATTACK to avoid damaging props
    bool isPressingAttack = (buttons & IN_ATTACK2) != 0;
    
    // Detect button press (transition from not pressing to pressing)
    if (isPressingAttack && !g_isHoldingButton[client]) {
        g_isHoldingButton[client] = true;
        TryGrabProp(client);
    }
    // Detect button release (transition from pressing to not pressing)
    else if (!isPressingAttack && g_isHoldingButton[client]) {
        g_isHoldingButton[client] = false;
        ReleaseProp(client);
    }
    
    return Plugin_Continue;
}

/* Returns true only when the American knife is the active weapon */
bool HasValidWeaponEquipped(int client) {
    int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    
    if (!IsValidEntity(weapon)) {
        return false;
    }
    
    char classname[64];
    GetEntityClassname(weapon, classname, sizeof(classname));
    
    return StrEqual(classname, WEAPON_AMERKNIFE, false);
}

// Try to grab the nearest prop
void TryGrabProp(int client) {
    // Don't grab if already holding something
    if (g_heldProp[client] != NO_PROP_HELD) {
        return;
    }
    
    int nearestProp = FindNearestPropInView(client);
    
    if (nearestProp == ENTITY_NOT_FOUND) {
        return;
    }
    
    // Store the prop reference
    g_heldProp[client] = nearestProp;
    
    // Start update timer to move prop with player
    if (g_updateTimer[client] != null) {
        KillTimer(g_updateTimer[client]);
    }
    
    int userId = GetClientUserId(client);
    g_updateTimer[client] = CreateTimer(UPDATE_INTERVAL, Timer_UpdatePropPosition, userId, TIMER_REPEAT);
}

// Release the held prop
void ReleaseProp(int client) {
    if (g_heldProp[client] == NO_PROP_HELD) {
        return;
    }
    
    int prop = g_heldProp[client];
    
    // Stop the prop's movement and add slight downward velocity to help it settle
    if (IsValidEntity(prop)) {
        float settleVel[3] = {0.0, 0.0, SETTLE_VELOCITY};
        TeleportEntity(prop, NULL_VECTOR, NULL_VECTOR, settleVel);
    }
    
    // Kill the update timer
    if (g_updateTimer[client] != null) {
        KillTimer(g_updateTimer[client]);
        g_updateTimer[client] = null;
    }
    
    g_heldProp[client] = NO_PROP_HELD;
}

// Find the nearest prop that the player is aiming at
int FindNearestPropInView(int client) {
    float clientEyePos[3], clientEyeAngles[3];
    GetClientEyePosition(client, clientEyePos);
    GetClientEyeAngles(client, clientEyeAngles);
    
    // Perform ray trace to see what player is aiming at
    float aimDirection[3];
    GetAngleVectors(clientEyeAngles, aimDirection, NULL_VECTOR, NULL_VECTOR);
    
    // Calculate end point of the trace
    float traceEnd[3];
    traceEnd[0] = clientEyePos[0] + (aimDirection[0] * MAX_PROP_DISTANCE);
    traceEnd[1] = clientEyePos[1] + (aimDirection[1] * MAX_PROP_DISTANCE);
    traceEnd[2] = clientEyePos[2] + (aimDirection[2] * MAX_PROP_DISTANCE);
    
    // Do the ray trace
    Handle trace = TR_TraceRayFilterEx(clientEyePos, traceEnd, MASK_SOLID, RayType_EndPoint, TraceFilter_IgnorePlayers, client);
    
    float hitPos[3];
    TR_GetEndPosition(hitPos, trace);
    CloseHandle(trace);
    
    // Now find the closest prop to where the player is aiming
    int nearestProp = ENTITY_NOT_FOUND;
    float nearestDistance = AIM_TOLERANCE;
    
    // Array of classnames to check
    char propTypes[3][32] = {
        "prop_physics_override",
        "prop_physics",
        "prop_physics_multiplayer"
    };
    
    // Search for props near the aim point
    for (int i = 0; i < 3; i++) {
        int prop = ENTITY_NOT_FOUND;
        
        while ((prop = FindEntityByClassname(prop, propTypes[i])) != ENTITY_NOT_FOUND) {
            // Skip if prop is already being held by someone
            if (IsPropBeingHeld(prop)) {
                continue;
            }
            
            // Check if prop is within range of player
            float propPos[3];
            GetEntPropVector(prop, Prop_Data, "m_vecAbsOrigin", propPos);
            float distanceFromPlayer = GetVectorDistance(clientEyePos, propPos);
            
            if (distanceFromPlayer > MAX_PROP_DISTANCE) {
                continue;
            }
            
            // Check distance from aim point to prop
            float distanceFromAim = GetVectorDistance(hitPos, propPos);
            
            if (distanceFromAim < nearestDistance) {
                nearestDistance = distanceFromAim;
                nearestProp = prop;
            }
        }
    }
    
    return nearestProp;
}

/**
 * Trace filter that allows the ray to pass through all players.
 * Without this, a teammate standing between the user and a prop would
 * cause hitPos to land on the teammate rather than the surface behind
 * them, resulting in incorrect prop selection.
 * Players are not props and cannot be selected regardless.
 */
public bool TraceFilter_IgnorePlayers(int entity, int contentsMask, int client)
{
    return entity > MaxClients;
}

// Check if a prop is currently being held by any player
bool IsPropBeingHeld(int prop) {
    for (int client = 1; client <= MaxClients; client++) {
        if (IsClientInGame(client) && g_heldProp[client] == prop) {
            return true;
        }
    }
    return false;
}

// Timer callback to continuously update prop position
public Action Timer_UpdatePropPosition(Handle timer, int userId) {
    int client = GetClientOfUserId(userId);
    
    // Stop timer if client is invalid
    if (client == 0) {
        return Plugin_Stop;
    }
    
    // Stop timer if client disconnected or died
    if (!IsClientInGame(client) || !IsPlayerAlive(client)) {
        ReleaseProp(client);
        return Plugin_Stop;
    }
    
    int prop = g_heldProp[client];
    
    // Stop timer if no prop or prop is invalid
    if (prop == NO_PROP_HELD || !IsValidEntity(prop)) {
        g_heldProp[client] = NO_PROP_HELD;
        g_updateTimer[client] = null;
        return Plugin_Stop;
    }
    
    // Calculate where the prop should be
    float targetPos[3];
    CalculateHoldPosition(client, targetPos);
    
    // Calculate velocity to move prop toward target
    float propPos[3];
    GetEntPropVector(prop, Prop_Data, "m_vecAbsOrigin", propPos);
    
    float velocity[3];
    MakeVectorFromPoints(propPos, targetPos, velocity);
    ScaleVector(velocity, SPEED_FACTOR);
    
    // Apply the velocity to move the prop
    TeleportEntity(prop, NULL_VECTOR, NULL_VECTOR, velocity);
    
    return Plugin_Continue;
}

// Calculate the position where the prop should be held
void CalculateHoldPosition(int client, float result[3]) {
    float clientEyePos[3], clientAngles[3], forwardVec[3];
    
    GetClientEyePosition(client, clientEyePos);
    GetClientEyeAngles(client, clientAngles);
    
    // Get forward direction from player's view
    GetAngleVectors(clientAngles, forwardVec, NULL_VECTOR, NULL_VECTOR);
    
    // Calculate position in front of player's eyes
    result[0] = clientEyePos[0] + (forwardVec[0] * HOLD_DISTANCE);
    result[1] = clientEyePos[1] + (forwardVec[1] * HOLD_DISTANCE);
    result[2] = clientEyePos[2] + (forwardVec[2] * HOLD_DISTANCE);
}
