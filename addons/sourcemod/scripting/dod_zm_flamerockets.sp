#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

/**
 * =============================================================================
 * DoD:S ZM - Flame Rockets
 *
 * Rocket launchers ignite players on hit and deal bonus damage.
 * Includes fix for looping fire sound bug.
 *
 * Fire sound fix based on:
 * IgniteEntity Sound Fix by Root_
 * https://github.com/zadroot/IgniteEntityFix/
 * =============================================================================
 */

public Plugin myinfo =
{
    name        = "DoD:S ZM - Flame Rockets",
    author      = "donkey, modified for ZombieMod by Claude.ai guided by DNA.styx",
    description = "Rocket launchers ignite players on hit",
    version     = "1.0.3",
    url         = "https://github.com/DNA-styx/DoD_ZombieMod_Plugins"
};

/* ============================================================================
 * Constants
 * ============================================================================ */

#define FIRE_LOOP_SOUND "ambient/fire/fire_small_loop2.wav"

/* ============================================================================
 * Globals
 * ============================================================================ */

ConVar g_CvarTime;
ConVar g_CvarMulti;
ConVar g_CvarAmmo;

float g_fBurnTime;
float g_fDmgMulti;
int   g_iAmmo;

/* Weapon names reported by player_hurt */
static const char g_sRocketWeapons[][] =
{
    "bazooka",
    "pschreck",
    "rocket_bazooka",   /* splash damage */
    "rocket_pschreck"   /* splash damage */
};

/* Weapon classnames to scan for on spawn */
static const char g_sRocketClasses[][] =
{
    "weapon_bazooka",
    "weapon_pschreck"
};

/* ============================================================================
 * Plugin Start
 * ============================================================================ */

public void OnPluginStart()
{
    g_CvarTime = CreateConVar(
        "zm_flamerocket_time",
        "3.0",
        "Burn duration in seconds applied on any rocket hit",
        _,
        true, 0.0,
        true, 60.0
    );

    g_CvarMulti = CreateConVar(
        "zm_flamerocket_multi",
        "3.0",
        "Damage multiplier applied to rocket hits (1.0 = no change)",
        _,
        true, 1.0,
        true, 10.0
    );

    g_CvarAmmo = CreateConVar(
        "zm_flamerocket_ammo",
        "10",
        "Reserve rocket ammo given to players carrying a rocket launcher on spawn",
        _,
        true, 0.0,
        true, 99.0
    );

    g_CvarTime.AddChangeHook(OnCvarChanged);
    g_CvarMulti.AddChangeHook(OnCvarChanged);
    g_CvarAmmo.AddChangeHook(OnCvarChanged);

    /* Load initial values */
    g_fBurnTime = g_CvarTime.FloatValue;
    g_fDmgMulti = g_CvarMulti.FloatValue;
    g_iAmmo     = g_CvarAmmo.IntValue;

    HookEvent("player_hurt",  Event_PlayerHurt);
    HookEvent("player_spawn", Event_PlayerSpawn);

    /* Hook damage for any clients already in game (late load) */
    for (int i = 1; i <= MaxClients; i++)
        if (IsClientInGame(i))
            SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);

    /* Hook fire sound to fix looping bug */
    AddNormalSoundHook(FireLoopSound);

    AutoExecConfig(true, "dod_zm_flamerockets", "zombiemod");
}

/* ============================================================================
 * CVar change handler
 * ============================================================================ */

public void OnCvarChanged(ConVar cvar, const char[] oldValue, const char[] newValue)
{
    g_fBurnTime = g_CvarTime.FloatValue;
    g_fDmgMulti = g_CvarMulti.FloatValue;
    g_iAmmo     = g_CvarAmmo.IntValue;
}

/* ============================================================================
 * OnClientPutInServer - hook damage per client
 * ============================================================================ */

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

/* ============================================================================
 * OnTakeDamage - multiply damage for rocket projectiles
 * ============================================================================ */

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage,
    int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
    if (inflictor <= 0 || !IsValidEntity(inflictor))
        return Plugin_Continue;

    char classname[32];
    GetEntityClassname(inflictor, classname, sizeof(classname));

    if (strcmp(classname, "rocket_bazooka", false) != 0 &&
        strcmp(classname, "rocket_pschreck", false) != 0)
        return Plugin_Continue;

    damage *= g_fDmgMulti;
    return Plugin_Changed;
}

/* ============================================================================
 * player_hurt - apply burn on rocket hit
 * ============================================================================ */

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
    char weapon[32];
    event.GetString("weapon", weapon, sizeof(weapon));

    bool isRocket = false;
    for (int i = 0; i < sizeof(g_sRocketWeapons); i++)
    {
        if (strcmp(weapon, g_sRocketWeapons[i], false) == 0)
        {
            isRocket = true;
            break;
        }
    }

    if (!isRocket)
        return;

    int victim = GetClientOfUserId(event.GetInt("userid"));

    if (!victim || !IsClientInGame(victim) || !IsPlayerAlive(victim))
        return;

    if (g_fBurnTime <= 0.0)
        return;

    IgniteEntity(victim, g_fBurnTime);
}

/* ============================================================================
 * player_spawn - set rocket reserve ammo
 * ============================================================================ */

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    if (!client || !IsClientInGame(client))
        return;

    /* Short delay to allow weapon grants to complete */
    CreateTimer(0.2, Timer_SetAmmo, GetClientUserId(client));
}

public Action Timer_SetAmmo(Handle timer, int userId)
{
    int client = GetClientOfUserId(userId);

    if (!client || !IsClientInGame(client) || !IsPlayerAlive(client))
        return Plugin_Stop;

    /* Scan inventory for a rocket launcher */
    for (int slot = 0; slot < 5; slot++)
    {
        int weapon = GetPlayerWeaponSlot(client, slot);

        if (weapon == -1)
            continue;

        char classname[64];
        GetEntityClassname(weapon, classname, sizeof(classname));

        for (int i = 0; i < sizeof(g_sRocketClasses); i++)
        {
            if (strcmp(classname, g_sRocketClasses[i], false) == 0)
            {
                int ammoType = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");

                if (ammoType != -1)
                    SetEntProp(client, Prop_Send, "m_iAmmo", g_iAmmo, _, ammoType);

                return Plugin_Stop;
            }
        }
    }

    return Plugin_Stop;
}

/* ============================================================================
 * FireLoopSound - Fix for looping fire sound bug
 *
 * Hooks fire sound emissions and blocks the default looping sound.
 * Instead, manually emits sound only for players that are actually burning.
 * This prevents the sound from getting stuck after player death or respawn.
 * ============================================================================ */

public Action FireLoopSound(int clients[MAXPLAYERS], int &numClients, char sample[PLATFORM_MAX_PATH],
    int &entity, int &channel, float &volume, int &level, int &pitch, int &flags,
    char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
    /* Check if this is the fire loop sound */
    if (!StrEqual(sample, FIRE_LOOP_SOUND, false))
        return Plugin_Continue;

    /* Block the default sound emission */
    /* We'll manually emit it only for players who are actually burning */
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client) && IsPlayerAlive(client) &&
            GetEntPropEnt(client, Prop_Send, "m_hEffectEntity") < 1)
        {
            /* Create timer to check and emit fire sound if player is burning */
            CreateTimer(0.1, Timer_EmitFireSound, client, TIMER_FLAG_NO_MAPCHANGE);
        }
    }

    return Plugin_Stop;
}

/* ============================================================================
 * Timer_EmitFireSound - Emit fire sound only if client is actually burning
 *
 * Checks the m_hEffectEntity netprop to determine if the client is burning.
 * If burning (value > 0), emits the ambient fire sound from the player's position.
 * ============================================================================ */

public Action Timer_EmitFireSound(Handle timer, any client)
{
    /* Check if client is actually ignited by checking m_hEffectEntity */
    /* If value is > 0, the player is burning */
    if (IsClientInGame(client) && IsPlayerAlive(client) &&
        GetEntPropEnt(client, Prop_Send, "m_hEffectEntity") > 0)
    {
        /* Get player's position */
        float origin[3];
        GetClientAbsOrigin(client, origin);

        /* Emit ambient sound from the player's position */
        EmitAmbientSound(FIRE_LOOP_SOUND, origin, client);
    }

    return Plugin_Stop;
}
