/**
 * =============================================================================
 * Zombie Mod for Day of Defeat Source - HUD Messages Module
 * 
 * Handles all HUD display messages:
 * - "View as Human" (humans aiming at zombies - shows zombie info)
 * - Human name display (zombies aiming at humans)
 * =============================================================================
 */

// ============================================================================
// GLOBALS
// ============================================================================

// No globals needed - zombie info timer uses TIMER_FLAG_NO_MAPCHANGE auto-cleanup

// ============================================================================
// INITIALIZATION & CLEANUP
// ============================================================================

void HUD_OnMapStart()
{
	// Recreate zombie info timer - no handle stored, TIMER_FLAG_NO_MAPCHANGE auto-cleans
	CreateTimer(0.1, Timer_ShowZombieInfo, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

// ============================================================================
// ZOMBIE INFO DISPLAY (Humans viewing zombies)
// ============================================================================

public Action Timer_ShowZombieInfo(Handle timer)
{
	if (!g_bModActive || g_bRoundEnded)
		return Plugin_Continue;
	
	// Check if display is enabled via ConVar
	if (!g_ConVarBools[ConVar_Show_Zombie_Info])
		return Plugin_Continue;
	
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || !IsPlayerAlive(client) || IsFakeClient(client))
			continue;
		
		// Show different info based on team
		if (GetClientTeam(client) == Team_Allies)
		{
			// Humans see zombie info (name, health, class)
			ShowZombieInfoToHuman(client);
		}
		else if (GetClientTeam(client) == Team_Axis)
		{
			// Zombies see human names
			ShowHumanNameToZombie(client);
		}
	}
	
	return Plugin_Continue;
}

void ShowZombieInfoToHuman(int client)
{
	// Get who the client is aiming at
	int target = GetClientAimTarget(client, false);
	
	// Not aiming at a valid entity
	if (target <= 0 || target > MaxClients)
		return;
	
	// Not aiming at a valid player
	if (!IsClientInGame(target) || !IsPlayerAlive(target))
		return;
	
	// Not aiming at a zombie
	if (GetClientTeam(target) != Team_Axis)
		return;
	
	// Get zombie info
	char name[MAX_NAME_LENGTH];
	GetClientName(target, name, sizeof(name));
	
	int health = RoundFloat(g_ClientInfo_Float[target][ClientInfo_Health]);
	bool isCritical = g_ClientInfo_Bool[target][ClientInfo_IsCritical];
	ZombieClass class = ZombieClasses_GetClass(target);
	
	// Display based on critical status and class
	if (isCritical)
	{
		// Critical zombies - no health display, just class/name
		if (class == ZombieClass_Gas)
		{
			PrintCenterText(client, "%t", "Critical Gas Zombie Display", name);
		}
		else if (class == ZombieClass_TNT)
		{
			PrintCenterText(client, "%t", "Critical TNT Zombie Display", name);
		}
		else
		{
			PrintCenterText(client, "%t", "Critical Zombie Display", name);
		}
	}
	else
	{
		// Normal zombies - show health and class
		if (class == ZombieClass_Gas)
		{
			PrintCenterText(client, "%t", "Gas Zombie Display", name, health);
		}
		else if (class == ZombieClass_TNT)
		{
			PrintCenterText(client, "%t", "TNT Zombie Display", name, health);
		}
		else
		{
			// Normal and Teleporter classes - same display (no class shown)
			PrintCenterText(client, "%t", "Zombie Info Display", name, health);
		}
	}
}

void ShowHumanNameToZombie(int client)
{
	// Get who the zombie is aiming at
	int target = GetClientAimTarget(client, false);
	
	// Not aiming at a valid entity
	if (target <= 0 || target > MaxClients)
		return;
	
	// Not aiming at a valid player
	if (!IsClientInGame(target) || !IsPlayerAlive(target))
		return;
	
	// Not aiming at a human
	if (GetClientTeam(target) != Team_Allies)
		return;
	
	// Get human name
	char name[MAX_NAME_LENGTH];
	GetClientName(target, name, sizeof(name));
	
	// Show "Human: {name}"
	PrintCenterText(client, "%t", "Human Info Display", name);
}

// ============================================================================
// ZOMBIE SELF-INFO DISPLAY (Shows class and health on spawn)
// ============================================================================

// Called from player.sp when a zombie spawns
void HUD_ShowZombieSpawnInfo(int userid)
{
	// Create timer that waits for spawn to fully complete, then shows info once
	CreateTimer(0.3, Timer_ShowZombieSelfInfo, userid, TIMER_REPEAT);
}

public Action Timer_ShowZombieSelfInfo(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	
	// Client could have disconnected during the 0.3s delay
	if (!client || !IsClientInGame(client))
		return Plugin_Stop;
	
	// Wait for player to be alive
	if (!IsPlayerAlive(client))
		return Plugin_Continue;
	
	// Show "You are now a Zombie!" message
	PrintCenterText(client, "%t", "Became Zombie");
	
	// Get zombie class name
	char className[64];
	int zombieClass = g_iZombieClass[client];
	
	switch (zombieClass)
	{
		case ZombieClass_Normal: strcopy(className, sizeof(className), "Normal Zombie");
		case ZombieClass_Teleporter: strcopy(className, sizeof(className), "Teleporter Zombie");
		case ZombieClass_Gas: strcopy(className, sizeof(className), "Gas Zombie");
		case ZombieClass_TNT: strcopy(className, sizeof(className), "TNT Zombie");
		default: strcopy(className, sizeof(className), "Zombie");
	}
	
	// Get current health
	int health = RoundFloat(g_ClientInfo_Float[client][ClientInfo_Health]);
	
	// Show class and health once, then stop timer
	PrintHintText(client, "%t", "Zombie Self Info", className, health);
	
	// Possible DoD:S bug that PrintHintText doesn't display after being killed
	PrintToChat(client, "%t", "Zombie Self Info", className, health);
	
	return Plugin_Stop;
}

// ============================================================================
// GAME COMMENCING AND COUNTDOWN DISPLAY
// ============================================================================

// Called from player.sp when minimum players reached and game is about to start
void HUD_ShowGameCommencing()
{
	// Show initial messages
	PrintToChatAll("%t%t", ZM_PREFIX, "Game Commencing");
	PrintCenterTextAll("%t", "Game Commencing");
	
	// Create repeating commencing messages
	CreateTimer(2.0, Timer_ShowCommencingMessage, _, TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(4.0, Timer_ShowCommencingMessage, _, TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(6.0, Timer_ShowCommencingMessage, _, TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(8.0, Timer_ShowCommencingMessage, _, TIMER_FLAG_NO_MAPCHANGE);
	
	// Create countdown timers
	CreateTimer(10.0, Timer_Countdown_5, _, TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(11.0, Timer_Countdown_4, _, TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(12.0, Timer_Countdown_3, _, TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(13.0, Timer_Countdown_2, _, TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(14.0, Timer_Countdown_1, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_ShowCommencingMessage(Handle timer)
{
	PrintCenterTextAll("%t", "Game Commencing");
	return Plugin_Stop;
}

public Action Timer_Countdown_5(Handle timer)
{
	PrintCenterTextAll("-= 5 =-");
	return Plugin_Stop;
}

public Action Timer_Countdown_4(Handle timer)
{
	PrintCenterTextAll("-= 4 =-");
	return Plugin_Stop;
}

public Action Timer_Countdown_3(Handle timer)
{
	PrintCenterTextAll("-= 3 =-");
	return Plugin_Stop;
}

public Action Timer_Countdown_2(Handle timer)
{
	PrintCenterTextAll("-= 2 =-");
	return Plugin_Stop;
}

public Action Timer_Countdown_1(Handle timer)
{
	PrintCenterTextAll("-= 1 =-");
	return Plugin_Stop;
}

