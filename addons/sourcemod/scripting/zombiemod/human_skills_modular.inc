/**
 * =============================================================================
 * Zombie Mod for Day of Defeat Source - Human Skills (Modular / External)
 *
 * Manages registration of external human skill plugins and the dynamic
 * skill selection menu. Native handlers live here; forward creation and
 * native registration are in api.inc.
 *
 * External plugins register via ZM_RegisterHumanSkill() in dod_zm.inc.
 * Built-in skills (ESP) are handled by human_skills_core.inc.
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
	Handle plugin;  /* null = built-in; otherwise the registering plugin handle */
}

// ============================================================================
// GLOBALS
// ============================================================================

// Array to store registered skills
SkillInfo g_RegisteredSkills[MAX_SKILLS];
int g_SkillCount = 0;

// Current skill ID for each client (0 = none, 1+ = skill ID)
int g_ClientSkillID[MAXPLAYERS+1];

/* Dynamic skill menu — rebuilt each time a skill registers */
Menu g_DynamicSkillMenu = null;

// ============================================================================
// INITIALIZATION
// ============================================================================

void ModularSkills_OnPluginStart()
{
	// Initialize all clients with no skill
	for (int i = 0; i <= MAXPLAYERS; i++)
	{
		g_ClientSkillID[i] = 0;  /* ZM_SKILL_NONE */
	}
	
	/* Register built-in ESP skill (ID 1) */
	RegisterBuiltInSkills();
	
	/* Build initial dynamic menu */
	RebuildSkillMenu();
}

void RegisterBuiltInSkills()
{
	/* ESP is the only built-in skill; ID will be 1 */
	if (g_SkillCount < MAX_SKILLS)
	{
		strcopy(g_RegisteredSkills[g_SkillCount].name,        ZM_MAX_SKILL_NAME, "ESP");
		strcopy(g_RegisteredSkills[g_SkillCount].description, ZM_MAX_SKILL_DESC, "See Zombie Class");
		g_RegisteredSkills[g_SkillCount].plugin = null;
		g_SkillCount++;
	}
}

// ============================================================================
// MENU MANAGEMENT
// ============================================================================

void RebuildSkillMenu()
{
	if (g_DynamicSkillMenu != null)
		delete g_DynamicSkillMenu;
	
	/* Build fresh menu */
	g_DynamicSkillMenu = new Menu(Menu_SkillSelect_Handler);
	g_DynamicSkillMenu.SetTitle("%t", "Skill Menu Title");
	g_DynamicSkillMenu.ExitBackButton = true;
	
	/* No Skill option — always first */
	char display[128];
	Format(display, sizeof(display), "%t", "Skill No Skill");
	g_DynamicSkillMenu.AddItem("0", display);
	
	/* Registered skills follow */
	for (int i = 0; i < g_SkillCount; i++)
	{
		char skillID[8];
		IntToString(i + 1, skillID, sizeof(skillID));  /* Skills start at ID 1 */
		
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
		g_DynamicSkillMenu.Display(client, EquipMenu_GetRemainingTime(client));
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
			
			/* Fire ZM_OnSkillAssigned forward */
			Call_StartForward(g_Forward_OnSkillAssigned);
			Call_PushCell(client);
			Call_PushCell(skillID);
			Call_Finish();
			
			/* Return to equip menu; centerprint is handled in ZM_OnSkillAssigned */
			DisplayMenu(g_EquipMenu[Menu_Main], client, EquipMenu_GetRemainingTime(client));
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				DisplayMenu(g_EquipMenu[Menu_Main], param1, EquipMenu_GetRemainingTime(param1));
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
	g_ClientSkillID[client] = 0;
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
	Call_StartForward(g_Forward_OnClientDeath);
	Call_PushCell(client);
	Call_Finish();
}

void ModularSkills_OnZombieDeath(int client, int classID)
{
	Call_StartForward(g_Forward_OnZombieDeath);
	Call_PushCell(client);
	Call_PushCell(classID);
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
	
	/* Check for an existing slot matching by name (catches new .smx upload with
	 * same skill name) or by plugin handle (catches sm plugins reload).
	 * Update the slot in-place and return the existing ID rather than appending. */
	for (int i = 0; i < g_SkillCount; i++)
	{
		bool sameHandle = (g_RegisteredSkills[i].plugin == plugin);
		bool sameName   = (strcmp(g_RegisteredSkills[i].name, name, false) == 0);

		if (sameHandle || sameName)
		{
			strcopy(g_RegisteredSkills[i].name,        ZM_MAX_SKILL_NAME, name);
			strcopy(g_RegisteredSkills[i].description, ZM_MAX_SKILL_DESC, description);
			g_RegisteredSkills[i].plugin = plugin;  /* Update handle (new .smx has new handle) */

			int existingID = i + 1;  /* Skills start at ID 1 */

			RebuildSkillMenu();

			PrintToServer("[Zombie Mod] Updated skill '%s' (ID %d) - plugin reloaded", name, existingID);
			return existingID;
		}
	}

	/* New skill - check capacity */
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
	APIValidateClientIndex(client);
	return g_ClientSkillID[client];
}

public int Native_IsClientHuman(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	APIValidateClientIndex(client);
	return GetClientTeam(client) == Team_Allies;
}

public int Native_IsClientZombie(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	APIValidateClientIndex(client);
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
