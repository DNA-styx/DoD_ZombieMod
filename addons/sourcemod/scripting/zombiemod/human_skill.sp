/**
 * =============================================================================
 * Zombie Mod for Day of Defeat Source - Human Skill Module
 * 
 * Handles skill selection for human players
 * =============================================================================
 */

// ============================================================================
// INITIALIZATION
// ============================================================================

void HumanSkills_Init()
{
	// Initialize all clients with no skill
	for (int i = 0; i <= MAXPLAYERS; i++)
	{
		g_iHumanSkill[i] = view_as<int>(HumanSkill_None);
	}
	
	// Create skill selection menu
	CreateHumanSkillMenu();
}

void CreateHumanSkillMenu()
{
	g_HumanSkillMenu = new Menu(MenuHandler_HumanSkill);
	
	char title[64];
	Format(title, sizeof(title), "%T", "Skill Menu Title", LANG_SERVER);
	g_HumanSkillMenu.SetTitle(title);
	
	char noSkill[64];
	Format(noSkill, sizeof(noSkill), "%T", "Skill No Skill", LANG_SERVER);
	g_HumanSkillMenu.AddItem("0", noSkill);
	
	char esp[64];
	Format(esp, sizeof(esp), "%T", "Skill ESP", LANG_SERVER);
	g_HumanSkillMenu.AddItem("1", esp);
	
	g_HumanSkillMenu.ExitButton = true;
	g_HumanSkillMenu.ExitBackButton = true;
}

// ============================================================================
// CLIENT EVENTS
// ============================================================================

void HumanSkills_OnClientConnect(int client)
{
	// Reset skill on connect
	g_iHumanSkill[client] = view_as<int>(HumanSkill_None);
}

void HumanSkills_OnClientDisconnect(int client)
{
	// Reset skill on disconnect
	g_iHumanSkill[client] = view_as<int>(HumanSkill_None);
}

void HumanSkills_OnSpawn(int client)
{
	// Reset skill on spawn (forces re-selection each spawn)
	g_iHumanSkill[client] = view_as<int>(HumanSkill_None);
}

// ============================================================================
// MENU HANDLER
// ============================================================================

public int MenuHandler_HumanSkill(Menu menu, MenuAction action, int client, int selection)
{
	if (action == MenuAction_Select)
	{
		// Verify client is still a human
		if (!IsClientInGame(client) || GetClientTeam(client) != Team_Allies)
			return 0;
		
		// Get skill choice from menu
		char info[8];
		menu.GetItem(selection, info, sizeof(info));
		int choice = StringToInt(info);
		
		// Apply skill based on selection
		switch (choice)
		{
			case 0:  // No Skill
			{
				g_iHumanSkill[client] = view_as<int>(HumanSkill_None);
				ZM_PrintToChat(client, "%t", "No Skill Selected");
			}
			case 1:  // ESP
			{
				g_iHumanSkill[client] = view_as<int>(HumanSkill_ESP);
				ZM_PrintToChat(client, "%t", "ESP Skill Selected");
			}
		}
		
		// Return to main equip menu
		DisplayMenu(g_EquipMenu[Menu_Main], client, MENU_TIME_FOREVER);
	}
	else if (action == MenuAction_Cancel)
	{
		// User pressed Back - return to main menu
		if (selection == MenuCancel_ExitBack)
		{
			if (IsClientInGame(client))
			{
				DisplayMenu(g_EquipMenu[Menu_Main], client, MENU_TIME_FOREVER);
			}
		}
	}
	
	return 0;
}

// ============================================================================
// GETTERS
// ============================================================================

HumanSkill HumanSkills_GetSkill(int client)
{
	return view_as<HumanSkill>(g_iHumanSkill[client]);
}

bool HumanSkills_HasESP(int client)
{
	// Delegate to modular skills system
	// ESP is now skill ID 1 in the modular system
	return ModularSkills_HasESP(client);
}

// ============================================================================
// SKILL ASSIGNMENT HANDLER
// ============================================================================

// Handle skill assignment for built-in skills (ESP, No Skill)
// This is called by modular_skills.sp via the ZM_OnSkillAssigned forward
public void ZM_OnSkillAssigned(int client, int skillID)
{
	// Only handle built-in skills (0 = No Skill, 1 = ESP)
	// External skill plugins handle their own messages
	if (skillID == 0)
	{
		// No Skill selected
		g_iHumanSkill[client] = view_as<int>(HumanSkill_None);
		PrintCenterText(client, "%t", "No Skill Selected");
		
		// Refresh centerprint to keep it visible (~5 seconds total)
		CreateTimer(1.0, Timer_RepeatNoSkillMessage, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		CreateTimer(2.0, Timer_RepeatNoSkillMessage, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		CreateTimer(3.0, Timer_RepeatNoSkillMessage, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		CreateTimer(4.0, Timer_RepeatNoSkillMessage, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
	else if (skillID == 1)
	{
		// ESP selected
		g_iHumanSkill[client] = view_as<int>(HumanSkill_ESP);
		PrintCenterText(client, "%t", "ESP Skill Selected");
		
		// Refresh centerprint to keep it visible (~5 seconds total)
		CreateTimer(1.0, Timer_RepeatESPMessage, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		CreateTimer(2.0, Timer_RepeatESPMessage, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		CreateTimer(3.0, Timer_RepeatESPMessage, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		CreateTimer(4.0, Timer_RepeatESPMessage, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
}

// ============================================================================
// ESP ZOMBIE IDENTIFICATION
// ============================================================================

void HumanSkills_OnPlayerRunCmd(int client, int buttons, int lastButtons)
{
	// Human ESP ability - Right-click with knife to identify zombie
	if (!ModularSkills_HasESP(client))
		return;
	
	// Check if right-click pressed (not held)
	if (!(buttons & IN_ATTACK2) || (lastButtons & IN_ATTACK2))
		return;
	
	// Check if knife equipped
	int activeWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (activeWeapon == -1)
		return;
	
	char weaponName[32];
	GetEntityClassname(activeWeapon, weaponName, sizeof(weaponName));
	
	if (!StrEqual(weaponName, "weapon_amerknife"))
		return;
	
	// Get aim target
	int target = GetClientAimTarget(client, false);
	
	if (target <= 0 || target > MaxClients || !IsClientInGame(target) || !IsPlayerAlive(target))
		return;
	
	// Check if target is zombie
	if (GetClientTeam(target) != Team_Axis)
		return;
	
	// NOW check cooldown (only if aiming at valid zombie target)
	float currentTime = GetGameTime();
	if (currentTime < g_fESPIdentifyCooldown[client])
	{
		float remaining = g_fESPIdentifyCooldown[client] - currentTime;
		int roundedSeconds = RoundToCeil(remaining);  // Round up to nearest second
		if (roundedSeconds < 1)
			roundedSeconds = 1;  // Minimum 1 second display
		ZM_PrintToChat(client, "%t", "ESP Identify Cooldown", roundedSeconds);
		return;
	}
	
	// Get zombie class
	ZombieClass zombieClass = ZombieClasses_GetClass(target);
	char className[32];
	char targetName[MAX_NAME_LENGTH];
	char reporterName[MAX_NAME_LENGTH];
	
	// Get class name
	switch (zombieClass)
	{
		case ZombieClass_Normal: strcopy(className, sizeof(className), "Normal Zombie");
		case ZombieClass_Gas: strcopy(className, sizeof(className), "Gas Zombie");
		case ZombieClass_TNT: strcopy(className, sizeof(className), "TNT Zombie");
		case ZombieClass_Ghost: strcopy(className, sizeof(className), "Ghost Zombie");
	}
	
	// Get names
	GetClientName(target, targetName, sizeof(targetName));
	GetClientName(client, reporterName, sizeof(reporterName));
	
	// Broadcast to all players (simple version - color formatting to be revisited later)
	PrintToChatAll("[ZM] %s reports: %s is %s", reporterName, targetName, className);
	
	// Set cooldown
	g_fESPIdentifyCooldown[client] = currentTime + ESP_IDENTIFY_COOLDOWN;
}

// ============================================================================
// TIMER CALLBACKS - Repeated centerprint to keep messages visible
// ============================================================================

public Action Timer_RepeatESPMessage(Handle timer, int userId)
{
	int client = GetClientOfUserId(userId);
	
	if (client == 0 || !IsClientInGame(client))
		return Plugin_Stop;
	
	// Refresh centerprint to keep it visible
	PrintCenterText(client, "%t", "ESP Skill Selected");
	
	return Plugin_Stop;
}

public Action Timer_RepeatNoSkillMessage(Handle timer, int userId)
{
	int client = GetClientOfUserId(userId);
	
	if (client == 0 || !IsClientInGame(client))
		return Plugin_Stop;
	
	// Refresh centerprint to keep it visible
	PrintCenterText(client, "%t", "No Skill Selected");
	
	return Plugin_Stop;
}
