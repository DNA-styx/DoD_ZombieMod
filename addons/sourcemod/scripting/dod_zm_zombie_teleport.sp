#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION "0.0.5"

// Team constants for DoD:S
#define TEAM_ALLIES 2
#define TEAM_AXIS   3

// Sound to play on teleport
#define TELEPORT_SOUND "buttons/spark6.wav"

public Plugin myinfo =
{
	name        = "Zombies Behind Us!",
	author      = "ChatGPT, Claudeai, guided by DNA.styx",
	description = "Teleports random spawning Zombie to a human spawn points",
	version     = PLUGIN_VERSION,
	url         = "https://github.com/DNA-styx/DoD_ZombieMod"
};

// ============================================================================
// GLOBALS
// ============================================================================

bool      g_bTeleportActive = false;
Handle    g_hActivationTimer = null;
ArrayList g_AlliedSpawns = null;

ConVar g_cvDelay;
ConVar g_cvChance;

// ============================================================================
// PLUGIN LIFECYCLE
// ============================================================================

public void OnPluginStart()
{
	// Hook events
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	HookEvent("dod_round_start", Event_RoundStart);
	HookEvent("dod_round_win", Event_RoundEnd);
	
	// Create ConVars
	g_cvDelay  = CreateConVar("sm_zombie_teleport_delay", "60.0",
		"Seconds after round start before teleport activates",
		FCVAR_NOTIFY, true, 0.0, true, 300.0);
	
	g_cvChance = CreateConVar("sm_zombie_teleport_chance", "0.25",
		"Chance (0.0 - 1.0) a zombie is teleported on spawn",
		FCVAR_NOTIFY, true, 0.0, true, 1.0);
	
	AutoExecConfig(true, "dod_zm_zombie_teleport");
	
	// Create spawn cache
	g_AlliedSpawns = new ArrayList(3);
}

public void OnMapStart()
{
	g_AlliedSpawns.Clear();
	CacheAlliedSpawns();
	
	// Precache teleport sound
	PrecacheSound(TELEPORT_SOUND, true);
}

public void OnMapEnd()
{
	// Clean up timer
	if (g_hActivationTimer != null)
	{
		KillTimer(g_hActivationTimer);
		g_hActivationTimer = null;
	}
	
	g_bTeleportActive = false;
}

// ============================================================================
// ROUND CONTROL
// ============================================================================

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	// Disable teleport at round start
	g_bTeleportActive = false;
	
	// Kill existing timer if it exists
	if (g_hActivationTimer != null)
	{
		KillTimer(g_hActivationTimer);
		g_hActivationTimer = null;
	}
	
	// Start delay timer
	float delay = g_cvDelay.FloatValue;
	g_hActivationTimer = CreateTimer(delay, Timer_EnableTeleport, 0, TIMER_FLAG_NO_MAPCHANGE);
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	// Disable teleport when round ends
	g_bTeleportActive = false;
	
	// Kill timer if round ends before activation
	if (g_hActivationTimer != null)
	{
		KillTimer(g_hActivationTimer);
		g_hActivationTimer = null;
	}
}

public Action Timer_EnableTeleport(Handle timer)
{
	g_bTeleportActive = true;
	g_hActivationTimer = null;
	
	return Plugin_Stop;
}

// ============================================================================
// SPAWN CACHING
// ============================================================================

void CacheAlliedSpawns()
{
	int entity = -1;
	float origin[3];
	
	// Find all Allied spawn points
	while ((entity = FindEntityByClassname(entity, "info_player_allies")) != -1)
	{
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);
		g_AlliedSpawns.PushArray(origin);
	}
}

// ============================================================================
// TELEPORT LOGIC
// ============================================================================

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	// Check if teleport is active
	if (!g_bTeleportActive)
		return;
	
	// Get client
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	// Validate client
	if (!client || !IsClientInGame(client) || !IsPlayerAlive(client))
		return;
	
	// Only teleport Axis team (zombies)
	if (GetClientTeam(client) != TEAM_AXIS)
		return;
	
	// Roll random chance
	float chance = g_cvChance.FloatValue;
	float roll = GetRandomFloat(0.0, 1.0);
	
	if (roll > chance)
		return;
	
	// Attempt teleport
	TeleportToRandomAlliedSpawn(client);
}

void TeleportToRandomAlliedSpawn(int client)
{
	int spawnCount = g_AlliedSpawns.Length;
	
	if (spawnCount == 0)
		return;
	
	// Pick random spawn point
	int index = GetRandomInt(0, spawnCount - 1);
	float spawnPos[3];
	g_AlliedSpawns.GetArray(index, spawnPos);
	
	// Use exact Allied spawn position (known good spawn point)
	TeleportEntity(client, spawnPos, NULL_VECTOR, NULL_VECTOR);
	
	// Play spark sound to nearby players
	EmitAmbientSound(TELEPORT_SOUND, spawnPos, SOUND_FROM_WORLD, SNDLEVEL_NORMAL, SND_NOFLAGS, 1.0, SNDPITCH_NORMAL, 0.0);
	
	// Create green sparks shooting upward
	CreateSparkEffect(spawnPos);
}

void CreateSparkEffect(float position[3])
{
	int spark = CreateEntityByName("env_spark");
	
	if (spark == -1)
		return;
	
	// Set spark properties
	DispatchKeyValue(spark, "spawnflags", "128");     // Shoot upward
	DispatchKeyValue(spark, "MaxDelay", "0");         // No delay
	DispatchKeyValue(spark, "Magnitude", "2");        // Size
	DispatchKeyValue(spark, "TrailLength", "2");      // Trail length
	
	// Teleport to position
	TeleportEntity(spark, position, NULL_VECTOR, NULL_VECTOR);
	
	// Spawn and activate
	DispatchSpawn(spark);
	ActivateEntity(spark);
	
	// Trigger spark once
	AcceptEntityInput(spark, "StartSpark");
	
	// Remove after 1 second
	CreateTimer(1.0, Timer_RemoveSpark, EntIndexToEntRef(spark), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_RemoveSpark(Handle timer, int ref)
{
	int spark = EntRefToEntIndex(ref);
	
	if (spark != INVALID_ENT_REFERENCE && IsValidEntity(spark))
	{
		AcceptEntityInput(spark, "StopSpark");
		RemoveEntity(spark);
	}
	
	return Plugin_Stop;
}

