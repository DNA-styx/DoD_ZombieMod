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

// Protection alpha oscillation (uses same system as Ghost zombie)
float g_fProtectionAlpha[DOD_MAXPLAYERS + 1];
bool g_bProtectionAlphaIncreasing[DOD_MAXPLAYERS + 1];
Handle g_hProtectionAlphaTimers[DOD_MAXPLAYERS + 1];

// ============================================================================
// INITIALIZATION
// ============================================================================

void SpawnProtection_Init()
{
	// Initialize all clients as unprotected
	for (int i = 0; i < DOD_MAXPLAYERS + 1; i++)
	{
		g_bSpawnProtected[i] = false;
		g_hProtectionAlphaTimers[i] = INVALID_HANDLE;
		g_fProtectionAlpha[i] = 0.0;
		g_bProtectionAlphaIncreasing[i] = true;
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
	
	// Clean up alpha timer
	if (g_hProtectionAlphaTimers[client] != INVALID_HANDLE)
	{
		KillTimer(g_hProtectionAlphaTimers[client]);
		g_hProtectionAlphaTimers[client] = INVALID_HANDLE;
	}
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
	
	// Visual indicator: Ghost-like alpha oscillation for ALL zombies during spawn protection
	// This makes all zombies look similar during protection and provides seamless transition for Ghost class
	SetEntityRenderMode(client, RENDER_TRANSCOLOR);
	
	// Initialize alpha oscillation (same as Ghost zombie)
	g_fProtectionAlpha[client] = 0.0;  // Start invisible
	g_bProtectionAlphaIncreasing[client] = true;
	
	// Start alpha oscillation timer (0.05 second intervals, same as Ghost)
	int userid = GetClientUserId(client);
	g_hProtectionAlphaTimers[client] = CreateTimer(0.05, Timer_ProtectionAlpha, userid, 
		TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	
	// Make weapon match body alpha
	int weapon = GetPlayerWeaponSlot(client, 2);  // Slot 2 = melee (spade)
	if (weapon > 0 && IsValidEntity(weapon))
	{
		SetEntityRenderMode(weapon, RENDER_TRANSCOLOR);
		SetEntityRenderColor(weapon, 255, 255, 255, 0);  // Start invisible
	}
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
	
	// Kill protection alpha timer
	if (g_hProtectionAlphaTimers[client] != INVALID_HANDLE)
	{
		KillTimer(g_hProtectionAlphaTimers[client]);
		g_hProtectionAlphaTimers[client] = INVALID_HANDLE;
	}
	
	// Handle visual transition based on zombie class
	if (g_iZombieClass[client] == view_as<int>(ZombieClass_Ghost))
	{
		// Ghost zombies: Delegate to zombie_classes.sp to start Ghost alpha timer
		// Pass current alpha state for seamless transition
		ZombieClasses_OnProtectionEnd(client, g_fProtectionAlpha[client], g_bProtectionAlphaIncreasing[client]);
	}
	else
	{
		// Other zombies: Return to normal solid appearance
		SetEntityRenderMode(client, RENDER_NORMAL);
		SetEntityRenderColor(client, 255, 255, 255, 255);
		
		// Reset weapon render
		int weapon = GetPlayerWeaponSlot(client, 2);
		if (weapon > 0 && IsValidEntity(weapon))
		{
			SetEntityRenderMode(weapon, RENDER_NORMAL);
			SetEntityRenderColor(weapon, 255, 255, 255, 255);
		}
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

// ============================================================================
// PROTECTION ALPHA OSCILLATION
// ============================================================================

public Action Timer_ProtectionAlpha(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	
	// Stop timer if client invalid or no longer protected
	if (!client || !IsClientInGame(client) || !g_bSpawnProtected[client])
	{
		if (client)
			g_hProtectionAlphaTimers[client] = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	// Oscillate alpha between 0 and 50 (same as Ghost zombie)
	if (g_bProtectionAlphaIncreasing[client])
	{
		g_fProtectionAlpha[client] += 2.0;
		if (g_fProtectionAlpha[client] >= 50.0)
			g_bProtectionAlphaIncreasing[client] = false;
	}
	else
	{
		g_fProtectionAlpha[client] -= 2.0;
		if (g_fProtectionAlpha[client] <= 0.0)
			g_bProtectionAlphaIncreasing[client] = true;
	}
	
	int alpha = RoundToNearest(g_fProtectionAlpha[client]);
	
	// Apply alpha to player
	SetEntityRenderColor(client, 255, 255, 255, alpha);
	
	// Apply same alpha to weapon
	int weapon = GetPlayerWeaponSlot(client, 2);
	if (weapon > 0 && IsValidEntity(weapon))
	{
		SetEntityRenderColor(weapon, 255, 255, 255, alpha);
	}
	
	return Plugin_Continue;
}
