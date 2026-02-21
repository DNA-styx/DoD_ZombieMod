/**
 * =============================================================================
 * Zombie Mod for Day of Defeat Source - Zombie Spawn Protection Module
 * 
 * Handles spawn protection for zombies (visual indicator + damage immunity)
 * Code based on Spawn Protection v1.5.2 by Fredd (optimized by Grey83)
 * https://forums.alliedmods.net/showthread.php?t=68139
 * =============================================================================
 */

// ============================================================================
// GLOBALS
// ============================================================================

bool g_bSpawnProtected[DOD_MAXPLAYERS + 1];

// ============================================================================
// INITIALIZATION
// ============================================================================

void SpawnProtection_Init()
{
	// Initialize all clients as unprotected
	for (int i = 0; i < DOD_MAXPLAYERS + 1; i++)
	{
		g_bSpawnProtected[i] = false;
	}
}

void SpawnProtection_OnClientConnect(int client)
{
	// Ensure new clients start without protection
	g_bSpawnProtected[client] = false;
}

void SpawnProtection_OnClientDisconnect(int client)
{
	// Clean up on disconnect
	g_bSpawnProtected[client] = false;
}

// ============================================================================
// SPAWN PROTECTION ACTIVATION
// ============================================================================

void SpawnProtection_Activate(int client)
{
	// Only apply to zombies (Axis team)
	if (GetClientTeam(client) != Team_Axis)
		return;
	
	float protectTime = g_ConVarFloats[ConVar_Zombie_Spawn_Protect_Time];
	if (protectTime <= 0.0)
		return;  // Protection disabled
	
	// Enable protection
	g_bSpawnProtected[client] = true;
	
	// Damage immunity
	SetEntProp(client, Prop_Data, "m_takedamage", 0, 1);
	
	// Auto-remove after time expires
	CreateTimer(protectTime, Timer_RemoveSpawnProtection, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

void SpawnProtection_ApplyVisuals(int client)
{
	// Only apply visuals if actually protected
	if (!g_bSpawnProtected[client])
		return;
	
	// Visual indicator: Green translucent (only for non-Ghost zombies)
	// Ghost zombies have their own alpha management
	SetEntityRenderColor(client, 0, 255, 0, 120);
}

// ============================================================================
// SPAWN PROTECTION REMOVAL
// ============================================================================

void SpawnProtection_Remove(int client)
{
	if (!g_bSpawnProtected[client])
		return;
	
	g_bSpawnProtected[client] = false;
	
	// Restore normal damage
	SetEntProp(client, Prop_Data, "m_takedamage", 2, 1);
	
	// Restore normal rendering - but NOT for Ghost zombies who have their own alpha management
	if (g_iZombieClass[client] != view_as<int>(ZombieClass_Ghost))
	{
		SetEntityRenderColor(client, 255, 255, 255, 255);
	}
}

public Action Timer_RemoveSpawnProtection(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (client && g_bSpawnProtected[client])
	{
		SpawnProtection_Remove(client);
	}
	return Plugin_Stop;
}

// ============================================================================
// CHECKS
// ============================================================================

bool SpawnProtection_IsProtected(int client)
{
	return g_bSpawnProtected[client];
}

void SpawnProtection_OnPlayerAttack(int client)
{
	// Remove protection if zombie attacks while protected
	if (g_bSpawnProtected[client] && IsPlayerAlive(client))
	{
		SpawnProtection_Remove(client);
	}
}
