/**
 * =============================================================================
 * DoD:S ZM Human Skill - TNT
 *
 * Human players place remote TNT packs via pistol right-click tap.
 * Holding pistol right-click detonates all placed packs simultaneously.
 *
 * Placement:  pistol right-click TAP  (< 0.5s) — places a pack at the aimed surface
 * Detonate:   pistol right-click HOLD (>= 0.5s) — detonates all placed packs
 *
 * Packs are immediately armed on placement.  They can be destroyed early by
 * environmental damage (zombie explosions, etc.) — this also triggers blast damage.
 * Placing a new pack silently removes the oldest one when the limit is reached.
 *
 * Based on:
 *   "Remote IED or TNT" by <eVa>Dog — http://www.theville.org
 *   "Tripmines 2016 Update" by 404 (abrandnewday) — http://www.unfgaming.net
 *
 * Author  : Claude.ai guided by DNA.styx
 * Version : 1.3.0
 * =============================================================================
 */

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <dod_zm>

#pragma semicolon 1
#pragma newdecls required

/* ============================================================================
 * CONSTANTS
 * ============================================================================ */

#define PLUGIN_VERSION "1.3.0"

/**
 * How long IN_ATTACK2 must be held (seconds) to detonate instead of place.
 * Release before threshold = tap → place.
 * Release at or after threshold = hold → detonate all.
 */
#define HOLD_THRESHOLD 0.5

/** Maximum distance from eye to place a pack (units) */
#define PACK_PLACE_DIST 150.0

/** DoD:S pistol classnames */
#define WEAPON_COLT "weapon_colt"
#define WEAPON_P38  "weapon_p38"

/** Asset defaults — override via ConVars in cfg/zombiemod/dod_zm_human_tnt.cfg */
#define DEFAULT_MODEL "models/weapons/w_tnt.mdl"
#define SPR_EXPLODE   "sprites/sprite_fire01.vmt"
#define SND_PLACE     "weapons/c4_plant.wav"
#define SND_EXPLODE   "weapons/explode3.wav"
#define SND_DENY      "common/weapon_denyselect.wav"

/* ============================================================================
 * GLOBALS
 * ============================================================================ */

ZMSkillID g_SkillID = ZM_SKILL_INVALID;

int   g_iPackCounter = 1;
int   g_iLastButtons[MAXPLAYERS + 1];
float g_fNextPlaceTime[MAXPLAYERS + 1];
float g_fAttack2PressTime[MAXPLAYERS + 1];
int   g_iExplodeSprite = -1;

/** Per-player list of active pack IDs. Pack ID N → entity targetname "zm_tnt_N". */
ArrayList g_PlayerPacks[MAXPLAYERS + 1];

ConVar g_cvNumPacks;
ConVar g_cvModel;
ConVar g_cvCooldown;
ConVar g_cvBlastRadius;
ConVar g_cvBlastDamage;

int   g_iNumPacks;
char  g_sModel[PLATFORM_MAX_PATH];
int   g_iCooldown;
float g_fBlastRadius;
float g_fBlastDamage;

/* ============================================================================
 * PLUGIN INFO
 * ============================================================================ */

public Plugin myinfo =
{
	name        = "DoD:S ZM Human Skill - TNT",
	author      = "Claude.ai guided by DNA.styx",
	description = "Remote TNT: pistol right-click to place, hold to detonate",
	version     = PLUGIN_VERSION,
	url         = "https://github.com/DNA-styx/DoD_ZombieMod_Plugins"
};

/* ============================================================================
 * PLUGIN INIT
 * ============================================================================ */

public void OnPluginStart()
{
	g_cvNumPacks    = CreateConVar("dod_zm_human_tnt_max",      "2",           "Maximum packs a player may have placed at once", _, true, 1.0, true, 10.0);
	g_cvModel       = CreateConVar("dod_zm_human_tnt_model",    DEFAULT_MODEL, "Model path for the TNT pack prop");
	g_cvCooldown    = CreateConVar("dod_zm_human_tnt_cooldown", "3",           "Whole seconds between pack placements per player", _, true, 0.0);
	g_cvBlastRadius = CreateConVar("dod_zm_human_tnt_radius",   "300.0",       "Blast radius in units",                            _, true, 50.0);
	g_cvBlastDamage = CreateConVar("dod_zm_human_tnt_damage",   "250.0",       "Blast damage dealt to zombies in radius",          _, true, 1.0);

	AutoExecConfig(true, "dod_zm_human_tnt", "zombiemod");

	g_cvNumPacks.AddChangeHook(OnConVarChanged);
	g_cvModel.AddChangeHook(OnConVarChanged);
	g_cvCooldown.AddChangeHook(OnConVarChanged);
	g_cvBlastRadius.AddChangeHook(OnConVarChanged);
	g_cvBlastDamage.AddChangeHook(OnConVarChanged);

	SyncConVars();
}

public void OnMapStart()
{
	PrecacheModel(g_sModel, true);
	PrecacheSound(SND_PLACE,   true);
	PrecacheSound(SND_EXPLODE, true);
	PrecacheSound(SND_DENY,    true);

	g_iExplodeSprite = PrecacheModel(SPR_EXPLODE, true);
	g_iPackCounter   = 1;
}

/* ============================================================================
 * ZM REGISTRATION
 * ============================================================================ */

public void OnAllPluginsLoaded()
{
	if (g_SkillID == ZM_SKILL_INVALID && ZM_IsLoaded())
		g_SkillID = ZM_RegisterHumanSkill("TNT", "Pistol right-click to place TNT");
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, ZM_LIBRARY) && g_SkillID == ZM_SKILL_INVALID)
		g_SkillID = ZM_RegisterHumanSkill("TNT", "Pistol right-click to place TNT");
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, ZM_LIBRARY))
		g_SkillID = ZM_SKILL_INVALID;
}

/* ============================================================================
 * CLIENT MANAGEMENT
 * ============================================================================ */

public void OnClientPostAdminCheck(int client)
{
	if (IsFakeClient(client))
		return;

	if (g_PlayerPacks[client] == null)
		g_PlayerPacks[client] = new ArrayList();
	else
		g_PlayerPacks[client].Clear();

	g_iLastButtons[client]      = 0;
	g_fNextPlaceTime[client]    = 0.0;
	g_fAttack2PressTime[client] = 0.0;
}

public void OnClientDisconnect(int client)
{
	RemovePlayerPacks(client);
	delete g_PlayerPacks[client];
	g_iLastButtons[client]      = 0;
	g_fNextPlaceTime[client]    = 0.0;
	g_fAttack2PressTime[client] = 0.0;
}

/* ============================================================================
 * ZM FORWARDS
 * ============================================================================ */

public void ZM_OnSkillAssigned(int client, ZMSkillID skillID)
{
	if (skillID != g_SkillID)
		return;

	PrintCenterText(client, "TNT selected!");
	ZM_Chat(client, "Pistol right click to place. Press and hold to detonate.");
}

public void ZM_OnClientDeath(int client)
{
	RemovePlayerPacks(client);
}

public void ZM_OnRoundStart()
{
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i))
			RemovePlayerPacks(i);
}

public void ZM_OnRoundEnd()
{
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i))
			RemovePlayerPacks(i);
}

/* ============================================================================
 * INPUT HANDLING
 * ============================================================================ */

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	if (g_SkillID == ZM_SKILL_INVALID)
		return Plugin_Continue;

	if (!IsClientInGame(client) || !IsPlayerAlive(client))
		return Plugin_Continue;

	if (ZM_GetClientSkill(client) != g_SkillID || !ZM_IsClientHuman(client))
		return Plugin_Continue;

	/* All actions require a pistol.  Clear press time on weapon switch so a
	 * mid-hold swap cannot trigger an accidental detonation. */
	if (!IsActivePistol(client))
	{
		g_fAttack2PressTime[client] = 0.0;
		g_iLastButtons[client] = buttons;
		return Plugin_Continue;
	}

	bool bHeld    = (buttons                    & IN_ATTACK2) != 0;
	bool bWasHeld = (g_iLastButtons[client]     & IN_ATTACK2) != 0;

	/* Rising edge — record press time */
	if (bHeld && !bWasHeld)
		g_fAttack2PressTime[client] = GetGameTime();

	/* Falling edge — tap vs hold */
	if (!bHeld && bWasHeld && g_fAttack2PressTime[client] > 0.0)
	{
		float fDuration = GetGameTime() - g_fAttack2PressTime[client];
		g_fAttack2PressTime[client] = 0.0;

		if (fDuration >= HOLD_THRESHOLD)
		{
			/* Hold → detonate all */
			if (g_PlayerPacks[client] != null && g_PlayerPacks[client].Length > 0)
				DetonateAllPacks(client);
			else
				EmitSoundToClient(client, SND_DENY);
		}
		else
		{
			/* Tap → place */
			float fNow = GetGameTime();
			if (fNow >= g_fNextPlaceTime[client])
			{
				PlacePack(client);
				g_fNextPlaceTime[client] = fNow + float(g_iCooldown);
			}
			else
			{
				EmitSoundToClient(client, SND_DENY);
			}
		}
	}

	g_iLastButtons[client] = buttons;
	return Plugin_Continue;
}

/* ============================================================================
 * PACK PLACEMENT
 * ============================================================================ */

void PlacePack(int client)
{
	float vEye[3], vAngles[3];
	GetClientEyePosition(client, vEye);
	GetClientEyeAngles(client, vAngles);

	Handle hTrace = TR_TraceRayFilterEx(vEye, vAngles, MASK_SOLID, RayType_Infinite, TraceFilter_World);

	if (!TR_DidHit(hTrace))
	{
		delete hTrace;
		EmitSoundToClient(client, SND_DENY);
		return;
	}

	float vPos[3], vNormal[3];
	TR_GetEndPosition(vPos, hTrace);
	TR_GetPlaneNormal(hTrace, vNormal);
	delete hTrace;

	if (GetVectorDistance(vEye, vPos) > PACK_PLACE_DIST)
	{
		EmitSoundToClient(client, SND_DENY);
		return;
	}

	/* Push off the surface — 2 units keeps the model snug without clipping */
	vPos[0] += vNormal[0] * 2.0;
	vPos[1] += vNormal[1] * 2.0;
	vPos[2] += vNormal[2] * 2.0;

	/* Minimum distance guard — prevents player getting stuck when looking straight down */
	float vFeet[3];
	GetClientAbsOrigin(client, vFeet);
	if (GetVectorDistance(vFeet, vPos) < 50.0)
	{
		EmitSoundToClient(client, SND_DENY);
		return;
	}

	/* Remove oldest pack if at the limit */
	if (g_PlayerPacks[client] != null && g_PlayerPacks[client].Length >= g_iNumPacks)
		RemoveOldestPack(client);

	int iID = g_iPackCounter++;
	if (g_iPackCounter > 99999)
		g_iPackCounter = 1;

	char sEntName[64];
	FormatEx(sEntName, sizeof(sEntName), "zm_tnt_%d", iID);

	float vAbsAngles[3], vSpawnAngles[3];
	GetClientAbsAngles(client, vAbsAngles);

	if (vNormal[2] > 0.7 || vNormal[2] < -0.7)
	{
		/* Floor or ceiling — gimbal lock makes GetVectorAngles unreliable at
		 * pitch ±90. Lay the model flat using confirmed working values. */
		vSpawnAngles[0] = 0.0;
		vSpawnAngles[1] = vAbsAngles[1] + 90.0;
		vSpawnAngles[2] = 0.0;
	}
	else
	{
		/* Wall or slope — derive pitch from surface normal, apply confirmed
		 * yaw and roll values from wall testing. */
		GetVectorAngles(vNormal, vSpawnAngles);
		vSpawnAngles[1] = vAbsAngles[1] + 90.0;
		vSpawnAngles[2] = 90.0;
	}

	int iEnt = CreateEntityByName("prop_physics_override");
	if (iEnt < 1 || !IsValidEntity(iEnt))
		return;

	DispatchKeyValue(iEnt, "model",         g_sModel);
	DispatchKeyValue(iEnt, "targetname",    sEntName);
	DispatchKeyValue(iEnt, "StartDisabled", "false");
	DispatchKeyValue(iEnt, "ExplodeDamage", "0");  /* we apply damage ourselves */
	DispatchKeyValue(iEnt, "ExplodeRadius", "0");
	DispatchKeyValue(iEnt, "massScale",     "1.0");
	DispatchKeyValue(iEnt, "inertiaScale",  "0.1");

	DispatchSpawn(iEnt);
	ActivateEntity(iEnt);
	TeleportEntity(iEnt, vPos, vSpawnAngles, NULL_VECTOR);

	/* Armed immediately — health 1 so environment can destroy it */
	SetEntProp(iEnt, Prop_Data, "m_takedamage", 2); /* DAMAGE_YES */
	SetEntProp(iEnt, Prop_Data, "m_iHealth",    1);
	SetEntPropEnt(iEnt, Prop_Data, "m_hLastAttacker", client);

	AcceptEntityInput(iEnt, "DisableMotion");

	HookSingleEntityOutput(iEnt, "OnBreak", CB_PackBreak, false);

	g_PlayerPacks[client].Push(iID);

	EmitSoundToAll(SND_PLACE, iEnt, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, 100, iEnt, vPos);
}

/* ============================================================================
 * PACK REMOVAL
 * ============================================================================ */

void RemovePlayerPacks(int client)
{
	if (g_PlayerPacks[client] == null || g_PlayerPacks[client].Length == 0)
		return;

	for (int i = 0; i < g_PlayerPacks[client].Length; i++)
		RemovePackByID(g_PlayerPacks[client].Get(i), false);

	g_PlayerPacks[client].Clear();
}

void RemoveOldestPack(int client)
{
	if (g_PlayerPacks[client] == null || g_PlayerPacks[client].Length == 0)
		return;

	RemovePackByID(g_PlayerPacks[client].Get(0), false);
	g_PlayerPacks[client].Erase(0);
}

/**
 * Remove a pack by ID.
 *
 * @param iID       Pack ID
 * @param bExplode  True  → engine break → CB_PackBreak fires → blast damage applied
 *                  False → silent removal, no explosion
 */
void RemovePackByID(int iID, bool bExplode)
{
	char sEntName[64];
	FormatEx(sEntName, sizeof(sEntName), "zm_tnt_%d", iID);
	int iEnt = FindEntityByName(sEntName, "prop_physics");

	if (iEnt == -1 || !IsValidEntity(iEnt))
		return;

	if (bExplode)
		AcceptEntityInput(iEnt, "break");
	else
	{
		UnhookSingleEntityOutput(iEnt, "OnBreak", CB_PackBreak);
		RemoveEntity(iEnt);
	}
}

/* ============================================================================
 * DETONATION
 * ============================================================================ */

void DetonateAllPacks(int client)
{
	if (g_PlayerPacks[client] == null || g_PlayerPacks[client].Length == 0)
		return;

	/* Snapshot IDs — CB_PackBreak modifies g_PlayerPacks during iteration */
	int iCount  = g_PlayerPacks[client].Length;
	int[] ids   = new int[iCount];
	for (int i = 0; i < iCount; i++)
		ids[i] = g_PlayerPacks[client].Get(i);

	for (int i = 0; i < iCount; i++)
		RemovePackByID(ids[i], true);
}

/** OnBreak output callback — fires for both player detonation and environmental break. */
public void CB_PackBreak(const char[] sOutput, int iCaller, int iActivator, float fDelay)
{
	if (!IsValidEntity(iCaller))
		return;

	char sEntName[64];
	GetEntPropString(iCaller, Prop_Data, "m_iName", sEntName, sizeof(sEntName));
	if (StrContains(sEntName, "zm_tnt_") != 0)
		return;

	/* Clean up player list before applying damage to prevent re-entry */
	int iID = StringToInt(sEntName[7]); /* skip "zm_tnt_" (7 chars) */
	RemoveIDFromPlayerLists(iID);

	float vPos[3];
	GetEntPropVector(iCaller, Prop_Send, "m_vecOrigin", vPos);

	int iOwner = GetEntPropEnt(iCaller, Prop_Data, "m_hLastAttacker");

	/* Explosion visual */
	if (g_iExplodeSprite != -1)
	{
		TE_SetupExplosion(vPos, g_iExplodeSprite, 5.0, 1, 0, 600, 5000);
		TE_SendToAll();
	}

	/* Explosion sound — emitted from the pack entity so it spatialises correctly
	 * for all players. Must be called before kill so iCaller is still valid. */
	EmitSoundToAll(SND_EXPLODE, iCaller, SNDCHAN_AUTO, SNDLEVEL_GUNFIRE);

	/* Screen shake — env_shake entity centred on the blast */
	ShakeNearby(vPos, g_fBlastRadius * 1.5, 12.0, 0.8, 5.0);

	/* Radius damage — zombies only */
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || !ZM_IsClientZombie(i))
			continue;

		float vZombie[3];
		GetClientAbsOrigin(i, vZombie);
		if (GetVectorDistance(vPos, vZombie) > g_fBlastRadius)
			continue;

		SDKHooks_TakeDamage(i, iCaller, (iOwner > 0) ? iOwner : 0, g_fBlastDamage, DMG_BLAST, -1, NULL_VECTOR, vPos);
	}

	AcceptEntityInput(iCaller, "kill");
}

/* ============================================================================
 * CONVAR SYNC
 * ============================================================================ */

void SyncConVars()
{
	g_iNumPacks    = g_cvNumPacks.IntValue;
	g_iCooldown    = g_cvCooldown.IntValue;
	g_fBlastRadius = g_cvBlastRadius.FloatValue;
	g_fBlastDamage = g_cvBlastDamage.FloatValue;
	g_cvModel.GetString(g_sModel, sizeof(g_sModel));
}

public void OnConVarChanged(ConVar hCvar, const char[] sOld, const char[] sNew)
{
	SyncConVars();
}

/* ============================================================================
 * TRACE FILTER
 * ============================================================================ */

/** Passes only worldspawn (entity index 0). */
public bool TraceFilter_World(int iEntity, int iContentsMask)
{
	return iEntity == 0;
}

/* ============================================================================
 * STOCK HELPERS
 * ============================================================================ */

/**
 * Spawn an env_shake entity at vPos to shake screens within fRadius.
 *
 * @param vPos          Blast origin
 * @param fRadius       Shake radius (units)
 * @param fAmplitude    Shake intensity (8–16 is noticeable)
 * @param fDuration     Shake duration (seconds)
 * @param fFrequency    Shake frequency (Hz)
 */
stock void ShakeNearby(const float vPos[3], float fRadius, float fAmplitude, float fDuration, float fFrequency)
{
	int iShake = CreateEntityByName("env_shake");
	if (iShake == -1 || !IsValidEntity(iShake))
		return;

	char sBuf[16];
	FloatToString(fAmplitude, sBuf, sizeof(sBuf));
	DispatchKeyValue(iShake, "amplitude", sBuf);
	FloatToString(fRadius, sBuf, sizeof(sBuf));
	DispatchKeyValue(iShake, "radius", sBuf);
	FloatToString(fDuration, sBuf, sizeof(sBuf));
	DispatchKeyValue(iShake, "duration", sBuf);
	FloatToString(fFrequency, sBuf, sizeof(sBuf));
	DispatchKeyValue(iShake, "frequency", sBuf);

	DispatchSpawn(iShake);
	TeleportEntity(iShake, vPos, NULL_VECTOR, NULL_VECTOR);
	AcceptEntityInput(iShake, "StartShake");

	CreateTimer(fDuration + 0.5, Timer_RemoveShake, EntIndexToEntRef(iShake));
}

public Action Timer_RemoveShake(Handle hTimer, int iRef)
{
	int iEnt = EntRefToEntIndex(iRef);
	if (iEnt != INVALID_ENT_REFERENCE && IsValidEntity(iEnt))
		RemoveEntity(iEnt);
	return Plugin_Stop;
}

/**
 * Returns true if the client's active weapon is a DoD:S pistol.
 *
 * @param client    Client index
 * @return          True if Colt or P38 is active
 */
stock bool IsActivePistol(int client)
{
	int iActive = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (iActive == -1 || !IsValidEntity(iActive))
		return false;

	char sClass[32];
	GetEdictClassname(iActive, sClass, sizeof(sClass));
	return StrEqual(sClass, WEAPON_COLT, false) || StrEqual(sClass, WEAPON_P38, false);
}

/**
 * Find the first entity matching a targetname and classname.
 *
 * @param sName     Targetname to match (case-insensitive)
 * @param sClass    Entity classname to iterate
 * @return          Entity index, or -1 if not found
 */
stock int FindEntityByName(const char[] sName, const char[] sClass)
{
	int  iEnt = -1;
	char sEntName[64];

	while ((iEnt = FindEntityByClassname(iEnt, sClass)) != -1)
	{
		GetEntPropString(iEnt, Prop_Data, "m_iName", sEntName, sizeof(sEntName));
		if (StrEqual(sEntName, sName, false))
			return iEnt;
	}

	return -1;
}

/**
 * Scan all player pack lists and erase the given pack ID from whichever owns it.
 *
 * @param iID   Pack ID to remove
 */
stock void RemoveIDFromPlayerLists(int iID)
{
	for (int c = 1; c <= MaxClients; c++)
	{
		if (g_PlayerPacks[c] == null)
			continue;

		int idx = g_PlayerPacks[c].FindValue(iID);
		if (idx != -1)
		{
			g_PlayerPacks[c].Erase(idx);
			return;
		}
	}
}
