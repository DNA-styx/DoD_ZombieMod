/**
 * =============================================================================
 * Zombie Mod for Day of Defeat Source - Modular Skill System
 * 
 * Handles registration and management of modular human skill plugins
 * NOTE: Native registration happens in main plugin's AskPluginLoad2
 * =============================================================================
 */

// ============================================================================
// CONSTANTS
// ============================================================================

#define MAX_SKILLS 32

// ============================================================================
// STRUCTURES
// ============================================================================

enum struct SkillInfo
{
	char name[ZM_MAX_SKILL_NAME];
	char description[ZM_MAX_SKILL_DESC];
	Handle plugin;  // Handle to the plugin that registered this skill
}

// ============================================================================
// GLOBALS
// ============================================================================

// Array to store registered skills
SkillInfo g_RegisteredSkills[MAX_SKILLS];
int g_SkillCount = 0;

// Current skill ID for each client (0 = none, 1+ = skill ID)
int g_ClientSkillID[MAXPLAYERS+1];

// Dynamic skill menu (rebuilt when skills register)
Menu g_DynamicSkillMenu = null;

// Forwards
Handle g_Forward_OnSkillAssigned = null;
Handle g_Forward_OnRoundStart = null;
Handle g_Forward_OnRoundEnd = null;
Handle g_Forward_OnClientDeath = null;
Handle g_Forward_OnClientSpawn = null;

// ============================================================================
// INITIALIZATION
// ============================================================================

void ModularSkills_Init()
{
	// Initialize all clients with no skill
	for (int i = 0; i <= MAXPLAYERS; i++)
	{
		g_ClientSkillID[i] = 0;  // No skill
	}
	
	// Create forwards
	g_Forward_OnSkillAssigned = CreateGlobalForward("ZM_OnSkillAssigned", ET_Ignore, Param_Cell, Param_Cell);
	g_Forward_OnRoundStart = CreateGlobalForward("ZM_OnRoundStart", ET_Ignore);
	g_Forward_OnRoundEnd = CreateGlobalForward("ZM_OnRoundEnd", ET_Ignore);
	g_Forward_OnClientDeath = CreateGlobalForward("ZM_OnClientDeath", ET_Ignore, Param_Cell);
	g_Forward_OnClientSpawn = CreateGlobalForward("ZM_OnClientSpawn", ET_Ignore, Param_Cell, Param_Cell);
	
	// Register built-in ESP skill
	RegisterBuiltInSkills();
	
	// Build initial menu
	RebuildSkillMenu();
}

void RegisterBuiltInSkills()
{
	// Register ESP as a built-in skill (ID will be 1)
	if (g_SkillCount < MAX_SKILLS)
	{
		strcopy(g_RegisteredSkills[g_SkillCount].name, ZM_MAX_SKILL_NAME, "ESP");
		strcopy(g_RegisteredSkills[g_SkillCount].description, ZM_MAX_SKILL_DESC, "See Zombie Class");
		g_RegisteredSkills[g_SkillCount].plugin = null;  // Built-in
		g_SkillCount++;
	}
}

// ============================================================================
// MENU MANAGEMENT
// ============================================================================

void RebuildSkillMenu()
{
	// Delete old menu if exists
	if (g_DynamicSkillMenu != null)
	{
		delete g_DynamicSkillMenu;
	}
	
	// Create new menu
	g_DynamicSkillMenu = new Menu(Menu_SkillSelect_Handler);
	g_DynamicSkillMenu.SetTitle("%t", "Skill Menu Title");
	g_DynamicSkillMenu.ExitBackButton = true;
	
	// Add "No Skill" option
	char display[128];
	Format(display, sizeof(display), "%t", "Skill No Skill");
	g_DynamicSkillMenu.AddItem("0", display);
	
	// Add all registered skills
	for (int i = 0; i < g_SkillCount; i++)
	{
		char skillID[8];
		IntToString(i + 1, skillID, sizeof(skillID));  // Skills start at ID 1
		
		Format(display, sizeof(display), "%s (%s)", 
			g_RegisteredSkills[i].name, 
			g_RegisteredSkills[i].description);
		
		g_DynamicSkillMenu.AddItem(skillID, display);
	}
}

void ShowSkillMenu(int client)
{
	if (g_DynamicSkillMenu != null)
	{
		g_DynamicSkillMenu.Display(client, MENU_TIME_FOREVER);
	}
}

public int Menu_SkillSelect_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			int client = param1;
			
			char info[8];
			menu.GetItem(param2, info, sizeof(info));
			
			int skillID = StringToInt(info);
			g_ClientSkillID[client] = skillID;
			
			// Call forward to notify skill plugins
			Call_StartForward(g_Forward_OnSkillAssigned);
			Call_PushCell(client);
			Call_PushCell(skillID);
			Call_Finish();
			
			// Return to equip menu immediately (centerprint handled by repeated timers in forward handlers)
			DisplayMenu(g_EquipMenu[Menu_Main], client, MENU_TIME_FOREVER);
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				DisplayMenu(g_EquipMenu[Menu_Main], param1, MENU_TIME_FOREVER);
			}
		}
	}
	
	return 0;
}

// ============================================================================
// CLIENT MANAGEMENT
// ============================================================================

void ModularSkills_OnClientConnect(int client)
{
	g_ClientSkillID[client] = 0;  // No skill
}

void ModularSkills_OnClientDisconnect(int client)
{
	g_ClientSkillID[client] = 0;
}

void ModularSkills_OnClientSpawn(int client, int team)
{
	// Reset skill on spawn
	g_ClientSkillID[client] = 0;
	
	// Call forward
	Call_StartForward(g_Forward_OnClientSpawn);
	Call_PushCell(client);
	Call_PushCell(team);
	Call_Finish();
}

void ModularSkills_OnClientDeath(int client)
{
	// Call forward
	Call_StartForward(g_Forward_OnClientDeath);
	Call_PushCell(client);
	Call_Finish();
}

void ModularSkills_OnRoundStart()
{
	// Call forward
	Call_StartForward(g_Forward_OnRoundStart);
	Call_Finish();
}

void ModularSkills_OnRoundEnd()
{
	// Call forward
	Call_StartForward(g_Forward_OnRoundEnd);
	Call_Finish();
}

// ============================================================================
// NATIVE IMPLEMENTATIONS
// These are called by skill plugins via natives registered in main plugin
// ============================================================================

public int Native_RegisterHumanSkill(Handle plugin, int numParams)
{
	// Get skill name and description
	char name[ZM_MAX_SKILL_NAME];
	GetNativeString(1, name, sizeof(name));
	
	char description[ZM_MAX_SKILL_DESC];
	GetNativeString(2, description, sizeof(description));
	
	// Check if this plugin already registered a skill (handle plugin reload)
	for (int i = 0; i < g_SkillCount; i++)
	{
		if (g_RegisteredSkills[i].plugin == plugin)
		{
			// Plugin is re-registering (probably reloaded)
			// Update the skill info and return existing ID
			strcopy(g_RegisteredSkills[i].name, ZM_MAX_SKILL_NAME, name);
			strcopy(g_RegisteredSkills[i].description, ZM_MAX_SKILL_DESC, description);
			
			int existingID = i + 1;  // Skills start at ID 1
			
			// Rebuild menu with updated info
			RebuildSkillMenu();
			
			PrintToServer("[Zombie Mod] Updated skill '%s' (ID %d) - plugin reloaded", name, existingID);
			return existingID;
		}
	}
	
	// Check if we have space for new skill
	if (g_SkillCount >= MAX_SKILLS)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Maximum skills (%d) reached", MAX_SKILLS);
		return view_as<int>(ZM_SKILL_INVALID);
	}
	
	// Register new skill
	strcopy(g_RegisteredSkills[g_SkillCount].name, ZM_MAX_SKILL_NAME, name);
	strcopy(g_RegisteredSkills[g_SkillCount].description, ZM_MAX_SKILL_DESC, description);
	g_RegisteredSkills[g_SkillCount].plugin = plugin;
	
	int skillID = g_SkillCount + 1;  // Skills start at ID 1
	g_SkillCount++;
	
	// Rebuild menu with new skill
	RebuildSkillMenu();
	
	PrintToServer("[Zombie Mod] Registered new skill '%s' with ID %d", name, skillID);
	
	return skillID;
}

public int Native_GetClientSkill(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	
	if (client < 1 || client > MaxClients)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d", client);
		return 0;
	}
	
	return g_ClientSkillID[client];
}

public int Native_IsClientHuman(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return false;
	
	return GetClientTeam(client) == Team_Allies;
}

public int Native_IsClientZombie(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return false;
	
	return GetClientTeam(client) == Team_Axis;
}

public int Native_IsModActive(Handle plugin, int numParams)
{
	return g_bModActive;
}

// ============================================================================
// GETTERS
// ============================================================================

int ModularSkills_GetClientSkill(int client)
{
	return g_ClientSkillID[client];
}

// For backwards compatibility with ESP skill (which is now ID 1)
bool ModularSkills_HasESP(int client)
{
	return g_ClientSkillID[client] == 1;  // ESP is skill ID 1
}
