/**
 * =============================================================================
 * DoD:S ZM Zombie Class - TNT Zombie
 *
 * Explodes on death, dealing blast damage and screen shake to nearby players.
 * Visual indicator: TNT model attached to zombie's chest for easy identification.
 * 
 * Registered as a zombie class via the ZM API. The class slot (ID 2) is
 * pre-registered as a built-in; this plugin claims that slot by name and
 * attaches the death effect.
 *
 * Version 1.1.0: Added visual TNT chest indicator
 * =============================================================================
 */

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <dod_zm>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.1.0"

public Plugin myinfo =
{
	name        = "DoD:S ZM Zombie Class - TNT Zombie",
	author      = "Claude.ai guided by DNA.styx",
	description = "TNT zombie explodes on death with visual indicator",
	version     = PLUGIN_VERSION,
	url         = ""
};

// ============================================================================
// CONSTANTS
// ============================================================================

#define EXPLODE_SOUND       "ambient/explosions/explode_3.wav"
#define EXPLODE_SHAKE_AMP   20.0
#define EXPLODE_SHAKE_DUR   1.5
#define EXPLODE_SHAKE_FREQ  100.0

#define TNT_MODEL           "models/weapons/w_tnt.mdl"

// ============================================================================
// GLOBALS
// ============================================================================

ZMClassID g_ClassID = ZM_CLASS_INVALID;

// Explosion ConVars
ConVar g_cvRadius;
ConVar g_cvDamage;

// Track attached TNT entities per player
int g_iPlayerTNT[MAXPLAYERS + 1] = { INVALID_ENT_REFERENCE, ... };

// ============================================================================
// PLUGIN INIT
// ============================================================================

public void OnPluginStart()
{
	// Explosion ConVars
	g_cvRadius = CreateConVar("zm_zombie_tnt_radius", "300.0",
		"Blast radius of TNT zombie death explosion",
		FCVAR_PLUGIN, true, 50.0, true, 1000.0);

	g_cvDamage = CreateConVar("zm_zombie_tnt_damage", "150",
		"Maximum blast damage dealt at point of explosion (falls off with distance)",
		FCVAR_PLUGIN, true, 1.0, true, 500.0);

	AutoExecConfig(true, "zombiemod_zombie_tnt", "zombiemod");
}

public void OnPluginEnd()
{
	// Clean up all TNT visuals when plugin unloads/reloads
	for (int i = 1; i <= MaxClients; i++)
	{
		RemoveTNT(i);
	}
}

public void OnMapStart()
{
	PrecacheSound(EXPLODE_SOUND, true);
	PrecacheModel(TNT_MODEL, true);
}

public void OnClientDisconnect(int client)
{
	RemoveTNT(client);
}

// ============================================================================
// ZM LIBRARY REGISTRATION
// ============================================================================

public void OnAllPluginsLoaded()
{
	if (g_ClassID == ZM_CLASS_INVALID && ZM_IsLoaded())
		g_ClassID = ZM_RegisterZombieClass("TNT Zombie", "Explodes on death");
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, ZM_LIBRARY) && g_ClassID == ZM_CLASS_INVALID)
		g_ClassID = ZM_RegisterZombieClass("TNT Zombie", "Explodes on death");
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, ZM_LIBRARY))
		g_ClassID = ZM_CLASS_INVALID;
}

// ============================================================================
// ZM FORWARDS
// ============================================================================

public void ZM_OnClientSpawn(int client, ZMTeam team)
{
	// Remove any existing TNT first
	RemoveTNT(client);
	
	// Only attach to zombies (Axis team)
	if (team == ZM_TEAM_AXIS)
	{
		CreateTimer(0.2, Timer_CheckAndAttachTNT, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
}

public void ZM_OnZombieDeath(int client, ZMClassID classID)
{
	// Remove TNT visual before explosion
	RemoveTNT(client);

	// Only explode if this is a TNT zombie
	if (classID != g_ClassID)
		return;

	float origin[3];
	GetClientAbsOrigin(client, origin);

	float radius = g_cvRadius.FloatValue;
	int   damage = g_cvDamage.IntValue;

	PlayExplosionSound(origin);
	CreateExplosionVisual(origin, radius, damage);
	CreateScreenShake(origin, radius);
	DamageNearbyEntities(origin, radius, damage, client);
}

// ============================================================================
// TNT VISUAL ATTACHMENT
// ============================================================================

public Action Timer_CheckAndAttachTNT(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	if (client > 0 && IsClientInGame(client) && IsPlayerAlive(client))
	{
		// Only attach if this is a TNT zombie
		if (ZM_GetClientZombieClass(client) == g_ClassID)
		{
			CreateTNT(client);
		}
	}
	return Plugin_Stop;
}

void CreateTNT(int client)
{
	RemoveTNT(client);
	
	int tnt = CreateEntityByName("prop_dynamic_override");
	if (!IsValidEntity(tnt))
		return;
	
	DispatchKeyValue(tnt, "model", TNT_MODEL);
	DispatchKeyValue(tnt, "spawnflags", "64"); // Don't drop on death
	DispatchSpawn(tnt);
	
	// Parent to player
	SetVariantString("!activator");
	AcceptEntityInput(tnt, "SetParent", client);
	
	// Set attachment point and position
	SetVariantString("head");
	AcceptEntityInput(tnt, "SetParentAttachmentMaintainOffset");
	
	// Position and rotation offsets
	float offsetPos[3] = { -12.0, -4.0, 0.0 };
	float offsetAng[3] = { 90.0, 90.0, 0.0 };
	
	TeleportEntity(tnt, offsetPos, offsetAng, NULL_VECTOR);
	
	// Store as Entity Reference to prevent issues if entity is deleted externally
	g_iPlayerTNT[client] = EntIndexToEntRef(tnt);
}

void RemoveTNT(int client)
{
	int entRef = g_iPlayerTNT[client];
	
	// Check if reference is valid, then convert back to index to kill it
	if (entRef != INVALID_ENT_REFERENCE)
	{
		int tnt = EntRefToEntIndex(entRef);
		if (tnt != INVALID_ENT_REFERENCE && IsValidEntity(tnt))
		{
			AcceptEntityInput(tnt, "Kill");
		}
		g_iPlayerTNT[client] = INVALID_ENT_REFERENCE;
	}
}

// ============================================================================
// EXPLOSION EFFECTS
// ============================================================================

void PlayExplosionSound(float origin[3])
{
	EmitAmbientSound(EXPLODE_SOUND, origin, SOUND_FROM_WORLD,
		SNDLEVEL_NORMAL, SND_NOFLAGS, 1.0, SNDPITCH_NORMAL, 0.0);
}

void CreateExplosionVisual(float origin[3], float radius, int damage)
{
	TE_SetupExplosion(
		origin,
		PrecacheModel("sprites/sprite_fire01.vmt"),
		10.0,               /* Scale */
		15,                 /* Framerate */
		0,                  /* Flags */
		RoundFloat(radius), /* Radius */
		damage              /* Magnitude */
	);
	TE_SendToAll();
}

void CreateScreenShake(float origin[3], float radius)
{
	int shake = CreateEntityByName("env_shake");
	if (shake == -1)
		return;

	DispatchKeyValueFloat(shake, "amplitude",  EXPLODE_SHAKE_AMP);
	DispatchKeyValueFloat(shake, "radius",     radius);
	DispatchKeyValueFloat(shake, "duration",   EXPLODE_SHAKE_DUR);
	DispatchKeyValueFloat(shake, "frequency",  EXPLODE_SHAKE_FREQ);
	DispatchKeyValue(shake,      "spawnflags", "12");  /* 4=Everyone + 8=Physics */

	TeleportEntity(shake, origin, NULL_VECTOR, NULL_VECTOR);
	DispatchSpawn(shake);
	ActivateEntity(shake);
	AcceptEntityInput(shake, "StartShake");

	CreateTimer(EXPLODE_SHAKE_DUR, Timer_RemoveShake,
		EntIndexToEntRef(shake), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_RemoveShake(Handle timer, int ref)
{
	int shake = EntRefToEntIndex(ref);
	if (shake != INVALID_ENT_REFERENCE && IsValidEntity(shake))
	{
		AcceptEntityInput(shake, "StopShake");
		RemoveEntity(shake);
	}
	return Plugin_Stop;
}

void DamageNearbyEntities(float origin[3], float radius, int damage, int attacker)
{
	/* Damage players */
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i))
			continue;

		/* Skip the TNT zombie that exploded */
		if (i == attacker)
			continue;

		float targetPos[3];
		GetClientAbsOrigin(i, targetPos);

		float distance = GetVectorDistance(origin, targetPos);
		if (distance > radius)
			continue;

		/* Linear falloff: full damage at center, zero at edge */
		float damageScale = 1.0 - (distance / radius);
		int finalDamage = RoundFloat(float(damage) * damageScale);

		if (finalDamage > 0)
			SDKHooks_TakeDamage(i, attacker, attacker, float(finalDamage),
				DMG_BLAST, -1, NULL_VECTOR, origin);
	}

	/* Break props in radius */
	int entity = -1;
	while ((entity = FindEntityByClassname(entity, "prop_*")) != -1)
	{
		float propPos[3];
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", propPos);

		if (GetVectorDistance(origin, propPos) <= radius)
			AcceptEntityInput(entity, "Break");
	}
}
