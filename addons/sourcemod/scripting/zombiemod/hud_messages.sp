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
// HELPER FUNCTIONS
// ============================================================================

// Get zombie class display name from ZombieClass enum
void GetZombieClassDisplayName(ZombieClass class, char[] buffer, int maxlength)
{
	switch (class)
	{
		case ZombieClass_Normal: strcopy(buffer, maxlength, "Normal Zombie");
		case ZombieClass_Gas: strcopy(buffer, maxlength, "Gas Zombie");
		case ZombieClass_TNT: strcopy(buffer, maxlength, "TNT Zombie");
		case ZombieClass_Ghost: strcopy(buffer, maxlength, "Ghost Zombie");
		default: strcopy(buffer, maxlength, "Zombie");
	}
}

// ============================================================================
// ZOMBIE INFO DISPLAY (Humans viewing zombies)
// ============================================================================

public Action Timer_ShowZombieInfo(Handle timer)
{
	if (!g_bModActive || g_bRoundEnded)
		return Plugin_Continue;
	
	// Show zombie info to all humans (ESP skill controls class visibility)
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
	
	// Ghost zombies are ALWAYS completely hidden - even with ESP
	if (class == ZombieClass_Ghost)
		return;
	
	// Check if human has ESP skill
	bool hasESP = HumanSkills_HasESP(client);
	
	// Display based on critical status, ESP skill, and class
	if (isCritical)
	{
		// Critical zombies - no health display, just name/class
		if (hasESP && class == ZombieClass_Gas)
		{
			// ESP reveals Gas zombie class
			PrintCenterText(client, "%t", "Critical Gas Zombie Display", name);
		}
		else if (hasESP && class == ZombieClass_TNT)
		{
			// ESP reveals TNT zombie class
			PrintCenterText(client, "%t", "Critical TNT Zombie Display", name);
		}
		else
		{
			// Without ESP or Normal class: Generic display (no class indicator)
			PrintCenterText(client, "%t", "Critical Zombie Display", name);
		}
	}
	else
	{
		// Normal health zombies - show health
		if (hasESP && class == ZombieClass_Gas)
		{
			// ESP reveals Gas zombie class
			PrintCenterText(client, "%t", "Gas Zombie Display", name, health);
		}
		else if (hasESP && class == ZombieClass_TNT)
		{
			// ESP reveals TNT zombie class
			PrintCenterText(client, "%t", "TNT Zombie Display", name, health);
		}
		else
		{
			// Without ESP or Normal class: Generic display (no class indicator)
			// Format: "{name} ({health} HP)"
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
	
	// Get zombie class name using helper function
	char className[64];
	ZombieClass zombieClass = view_as<ZombieClass>(g_iZombieClass[client]);
	GetZombieClassDisplayName(zombieClass, className, sizeof(className));
	
	// Get current health
	int health = RoundFloat(g_ClientInfo_Float[client][ClientInfo_Health]);
	
	// Show "You are now a [Class]!" message in center
	PrintCenterText(client, "%t", "Became Zombie", className);
	
	// Show health in hint text (class already shown above)
	PrintHintText(client, "%t", "Zombie Self Info", health);
	
	// Possible DoD:S bug that PrintHintText doesn't display after being killed
	PrintToChat(client, "%t", "Zombie Self Info", health);
	
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

