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
			}
			case 1:  // ESP
			{
				g_iHumanSkill[client] = view_as<int>(HumanSkill_ESP);
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
	return g_iHumanSkill[client] == view_as<int>(HumanSkill_ESP);
}
