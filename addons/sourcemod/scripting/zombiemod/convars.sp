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
	ConVar_Human_EquipMenu, 
	ConVar_Zombie_Health, 
	ConVar_Zombie_CritReward, 
	ConVar_Zombie_Speed, 
	ConVar_Zombie_MaxSpeed, 
	ConVar_Beacon_Interval,
	ConVar_Spawn_NoClip_Time,
	ConVar_Zombie_Spawn_Protect_Time,
	ConVar_Show_Zombie_Info,
	ConVar_Debug, 
	
	ConVar_Size
}

// Properly typed storage for ConVars

void InitConVars()
{
	CreateConVar("sm_zombiemod_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_NOTIFY | FCVAR_DONTRECORD);
	
	AddConVar(ConVar_Enabled, CreateConVar("dod_zombiemod_enabled", "1", "Whether or not enable Zombie Mod", FCVAR_PLUGIN, true, 0.0, true, 1.0));
	AddConVar(ConVar_WinLimit, CreateConVar("dod_zombiemod_winlimit", "5", "Maximum amount of rounds until mapchange", FCVAR_PLUGIN, true, 1.0));
	AddConVar(ConVar_MinPlayers, CreateConVar("dod_zombiemod_minplayers", "3", "Minumum amount of players to start Zombie Mod", FCVAR_PLUGIN, true, 3.0, true, 32.0));
	AddConVar(ConVar_Zombie_RoundTime, CreateConVar("dod_zombiemod_roundtime", "600", "How long time (in seconds) each round takes", FCVAR_PLUGIN, true, 120.0));
	AddConVar(ConVar_Human_MaxHealth, CreateConVar("dod_zombiemod_human_maxhealth", "150", "Maximum amount of health a human can have", FCVAR_PLUGIN, true, 1.0));
	AddConVar(ConVar_Zombie_Health, CreateConVar("dod_zombiemod_zombie_health", "8000", "Amount of health a zombie will have on spawn", FCVAR_PLUGIN, true, 1.0));
	AddConVar(ConVar_Zombie_CritReward, CreateConVar("dod_zombiemod_crit_reward", "250", "Amount of health a zombie will get for being critted", FCVAR_PLUGIN, true, 0.0, true, 100.0));
	AddConVar(ConVar_Zombie_Speed, CreateConVar("dod_zombiemod_zombie_speed", "0.65", "Amount of speed a zombie will have on spawn", FCVAR_PLUGIN, true, 0.0));
	AddConVar(ConVar_Zombie_MaxSpeed, CreateConVar("dod_zombiemod_zombie_maxspeed", "0.85", "Maximum amount of speed a zombie can have", FCVAR_PLUGIN, true, 0.0));
	AddConVar(ConVar_Beacon_Interval, CreateConVar("dod_zombiemod_beacon_interval", "8", "Time beween toggleing beacon on last human", FCVAR_PLUGIN, true, 1.0));
	AddConVar(ConVar_Spawn_NoClip_Time, CreateConVar("dod_zombiemod_spawn_noclip_time", "15.0", "Seconds humans can pass through teammates after spawn (prevents spawn blocking)", FCVAR_PLUGIN, true, 0.0));
	AddConVar(ConVar_Zombie_Spawn_Protect_Time, CreateConVar("dod_zombiemod_zombie_spawn_protect_time", "10.0", "Seconds zombies are protected from damage after spawning", FCVAR_PLUGIN, true, 0.0));
	AddConVar(ConVar_Show_Zombie_Info, CreateConVar("dod_zombiemod_show_info", "1", "Show zombie name and health when aiming at them (0=off, 1=on)", FCVAR_PLUGIN, true, 0.0, true, 1.0));
	AddConVar(ConVar_Debug, CreateConVar("dod_zombiemod_debug", "0", "Enable debug messages (0=off, 1=on)", FCVAR_PLUGIN, true, 0.0, true, 1.0));
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
