/**
 * =============================================================================
 * Zombie Mod for Day of Defeat Source - Phase 1.5
 */

enum
{
	ConVar_Enabled, 
	ConVar_WinLimit, 
	ConVar_MinPlayers, 
	ConVar_Zombie_RoundTime, 
	ConVar_Human_MaxHealth,
	ConVar_Human_Pistol_MaxAmmo,
	// ConVar_Human_EquipMenu,  // UNUSED - Never created or used - Commented out v0.7.58
	ConVar_Zombie_Health, 
	ConVar_Zombie_CritReward, 
	ConVar_Zombie_Speed, 
	ConVar_Zombie_MaxSpeed, 
	ConVar_Beacon_Interval,
	ConVar_Spawn_NoClip_Time,
	ConVar_Class_Chance,
	ConVar_Gas_Cooldown,
	ConVar_Pickup_Timeout,
	ConVar_Ghost_Alpha_Max,
	ConVar_Teleport_Chance,
	ConVar_Barrier_Health_Display,
	ConVar_Zombie_Show_Weapon,
	ConVar_Sounds_Enabled,

	ConVar_Size
}

// Properly typed storage for ConVars

void ConVars_OnPluginStart()
{
	CreateConVar("sm_zombiemod_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_NOTIFY | FCVAR_DONTRECORD);

	/* General */
	AddConVar(ConVar_Enabled,          CreateConVar("dod_zombiemod_enabled",    "1",   "Enable Zombie Mod (0=disabled)", FCVAR_PLUGIN, true, 0.0, true, 1.0));
	AddConVar(ConVar_WinLimit,         CreateConVar("dod_zombiemod_winlimit",   "3",   "Rounds until map change", FCVAR_PLUGIN, true, 1.0));
	AddConVar(ConVar_MinPlayers,       CreateConVar("dod_zombiemod_minplayers", "3",   "Minimum players to start Zombie Mod", FCVAR_PLUGIN, true, 3.0, true, 32.0));
	AddConVar(ConVar_Zombie_RoundTime, CreateConVar("dod_zombiemod_roundtime",  "600", "Round time in seconds", FCVAR_PLUGIN, true, 120.0));
	AddConVar(ConVar_Beacon_Interval,  CreateConVar("dod_zombiemod_beacon_interval", "8", "Seconds between beacon pulses on last human", FCVAR_PLUGIN, true, 1.0));

	/* Human */
	AddConVar(ConVar_Human_MaxHealth,      CreateConVar("dod_zombiemod_human_maxhealth",     "150", "Maximum health humans can have", FCVAR_PLUGIN, true, 100.0));
	AddConVar(ConVar_Human_Pistol_MaxAmmo, CreateConVar("dod_zombiemod_human_pistol_maxammo", "21", "Maximum pistol ammo for Colt and P38 (rounds, 3 clips of 7)", FCVAR_PLUGIN, true, 7.0));
	AddConVar(ConVar_Spawn_NoClip_Time,    CreateConVar("dod_zombiemod_spawn_noclip_time",   "15.0", "Seconds humans can pass through teammates after spawn", FCVAR_PLUGIN, true, 0.0));
	AddConVar(ConVar_Pickup_Timeout,       CreateConVar("dod_zombiemod_pickup_timeout",      "30.0", "Seconds before a pickup auto-destroys if not collected", FCVAR_PLUGIN, true, 5.0, true, 120.0));

	/* Zombie */
	AddConVar(ConVar_Zombie_Health,    CreateConVar("dod_zombiemod_zombie_health",    "8000", "Zombie health on spawn", FCVAR_PLUGIN, true, 1.0));
	AddConVar(ConVar_Zombie_CritReward,CreateConVar("dod_zombiemod_crit_reward",     "250",  "Health given to zombie that lands a crit kill", FCVAR_PLUGIN, true, 0.0, true, 100.0));
	AddConVar(ConVar_Zombie_Speed,     CreateConVar("dod_zombiemod_zombie_speed",    "0.65", "Zombie movement speed on spawn", FCVAR_PLUGIN, true, 0.0));
	AddConVar(ConVar_Zombie_MaxSpeed,  CreateConVar("dod_zombiemod_zombie_maxspeed", "0.85", "Maximum zombie movement speed", FCVAR_PLUGIN, true, 0.0));
	AddConVar(ConVar_Class_Chance,     CreateConVar("dod_zombiemod_class_chance",    "50",   "Chance (%) zombie spawns as special class (0=disabled)", FCVAR_PLUGIN, true, 0.0, true, 100.0));
	AddConVar(ConVar_Gas_Cooldown,     CreateConVar("dod_zombiemod_gas_cooldown",    "15.0", "Seconds between Gas Zombie ability uses", FCVAR_PLUGIN, true, 5.0, true, 60.0));
	AddConVar(ConVar_Ghost_Alpha_Max,  CreateConVar("dod_zombiemod_ghost_alpha_max", "50.0", "Ghost Zombie max alpha (0=invisible, 255=fully visible)", FCVAR_PLUGIN, true, 0.0, true, 255.0));
	AddConVar(ConVar_Teleport_Chance,  CreateConVar("dod_zombiemod_teleport_chance", "25",   "Chance (%) zombie teleports to human spawn on respawn (0=disabled)", FCVAR_PLUGIN, true, 0.0, true, 100.0));
	AddConVar(ConVar_Barrier_Health_Display, CreateConVar("dod_zombiemod_barrier_health_display", "1", "Show barrier health to zombie when damaging a prop (1=on, 0=off)", FCVAR_PLUGIN, true, 0.0, true, 1.0));
	AddConVar(ConVar_Zombie_Show_Weapon,    CreateConVar("dod_zombiemod_zombie_show_weapon",     "1", "Show zombie weapon (spade) when spawning as zombie (1=visible, 0=hidden)", FCVAR_PLUGIN, true, 0.0, true, 1.0));
	AddConVar(ConVar_Sounds_Enabled,        CreateConVar("dod_zombiemod_sounds_enabled",          "1", "Play ambient sound track during active ZM rounds (1=on, 0=off)", FCVAR_PLUGIN, true, 0.0, true, 1.0));
}

void AddConVar(int conVar, Handle conVarHandle)
{
	g_ConVarHandles[conVar] = conVarHandle;
	
	UpdateConVarValue(conVar);
	
	HookConVarChange(conVarHandle, OnConVarChange);
}

void UpdateConVarValue(int conVar)
{
	g_ConVarInts[conVar] = GetConVarInt(g_ConVarHandles[conVar]);
	g_ConVarBools[conVar] = GetConVarBool(g_ConVarHandles[conVar]);
	g_ConVarFloats[conVar] = GetConVarFloat(g_ConVarHandles[conVar]);
}

public void OnConVarChange(Handle conVar, const char[] oldValue, const char[] newValue)
{
	for (int i = 0; i < ConVar_Size; i++)
	{
		if (conVar == g_ConVarHandles[i])
		{
			UpdateConVarValue(i);
			
			ConVarChanged(i);
			
			break;
		}
	}
}

void ConVarChanged(int conVar)
{
	switch (conVar)
	{
		case ConVar_Enabled:
		{
			if (g_bModActive && !g_ConVarBools[conVar])
			{
				g_bModActive = false;
				
				SetRoundState(DoDRoundState_Restart);
			}
		}
	}
}
