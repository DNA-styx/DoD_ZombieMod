/**
 * =============================================================================
 * Zombie Mod for Day of Defeat Source - Human Skills (Core / Built-in)
 *
 * Handles the built-in human skills that ship with the main plugin.
 * Currently the only built-in skill is ESP (zombie class identification).
 *
 * These are NOT plugin-created skills. External human skill plugins use
 * the modular API defined in human_skills_modular.inc and dod_zm.inc.
 * =============================================================================
 */

/* Cooldown between ESP identify uses (seconds) */
#define ESP_IDENTIFY_COOLDOWN 5.0

// ============================================================================
// Initialization
// ============================================================================

void HumanSkills_OnPluginStart()
{
	for (int i = 0; i <= MAXPLAYERS; i++)
		g_iHumanSkill[i] = view_as<int>(HumanSkill_None);

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

	g_HumanSkillMenu.ExitButton     = true;
	g_HumanSkillMenu.ExitBackButton = true;
}

// ============================================================================
// Client Events
// ============================================================================

void HumanSkills_OnClientConnect(int client)
{
	g_iHumanSkill[client] = view_as<int>(HumanSkill_None);
}

void HumanSkills_OnClientDisconnect(int client)
{
	g_iHumanSkill[client] = view_as<int>(HumanSkill_None);
}

void HumanSkills_OnSpawn(int client)
{
	/* Reset each spawn so the player must re-select via the equipment menu */
	g_iHumanSkill[client] = view_as<int>(HumanSkill_None);
}

// ============================================================================
// Menu Handler
// ============================================================================

public int MenuHandler_HumanSkill(Menu menu, MenuAction action, int client, int selection)
{
	if (action == MenuAction_Select)
	{
		if (!IsClientInGame(client) || GetClientTeam(client) != Team_Allies)
			return 0;

		char info[8];
		menu.GetItem(selection, info, sizeof(info));
		int choice = StringToInt(info);

		switch (choice)
		{
			case 0:
			{
				g_iHumanSkill[client] = view_as<int>(HumanSkill_None);
				ZM_PrintToChat(client, "%t", "No Skill Selected");
			}
			case 1:
			{
				g_iHumanSkill[client] = view_as<int>(HumanSkill_ESP);
				ZM_PrintToChat(client, "%t", "ESP Skill Selected");
			}
		}

		DisplayMenu(g_EquipMenu[Menu_Main], client, EquipMenu_GetRemainingTime(client));
	}
	else if (action == MenuAction_Cancel && selection == MenuCancel_ExitBack)
	{
		if (IsClientInGame(client))
			DisplayMenu(g_EquipMenu[Menu_Main], client, EquipMenu_GetRemainingTime(client));
	}

	return 0;
}

// ============================================================================
// Getters
// ============================================================================

HumanSkill HumanSkills_GetSkill(int client)
{
	return view_as<HumanSkill>(g_iHumanSkill[client]);
}

bool HumanSkills_HasESP(int client)
{
	/* ESP is registered as skill ID 1 in the modular system */
	return ModularSkills_HasESP(client);
}

// ============================================================================
// Skill Assignment — Built-in Forward Handler
// ============================================================================

/**
 * Handles ZM_OnSkillAssigned for built-in skill IDs (0=None, 1=ESP).
 * External skill plugins handle their own confirmation messages.
 * Uses repeated centerprint timers to keep the message visible for ~5 seconds.
 */
public void ZM_OnSkillAssigned(int client, int skillID)
{
	if (skillID == 0)
	{
		g_iHumanSkill[client] = view_as<int>(HumanSkill_None);
		PrintCenterText(client, "%t", "No Skill Selected");

		CreateTimer(1.0, Timer_RepeatNoSkillMessage, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		CreateTimer(2.0, Timer_RepeatNoSkillMessage, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		CreateTimer(3.0, Timer_RepeatNoSkillMessage, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		CreateTimer(4.0, Timer_RepeatNoSkillMessage, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
	else if (skillID == 1)
	{
		g_iHumanSkill[client] = view_as<int>(HumanSkill_ESP);
		PrintCenterText(client, "%t", "ESP Skill Selected");

		CreateTimer(1.0, Timer_RepeatESPMessage, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		CreateTimer(2.0, Timer_RepeatESPMessage, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		CreateTimer(3.0, Timer_RepeatESPMessage, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		CreateTimer(4.0, Timer_RepeatESPMessage, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
}

// ============================================================================
// ESP — Zombie Identification
// Triggered by right-click with any pistol.
// Prints zombie class to all players; subject to per-client cooldown.
// ============================================================================

void HumanSkills_OnPlayerRunCmd(int client, int buttons, int lastButtons)
{
	if (!ModularSkills_HasESP(client))
		return;

	/* Edge detect: right-click pressed this frame, not held from last */
	if (!(buttons & IN_ATTACK2) || (lastButtons & IN_ATTACK2))
		return;

	/* Require any pistol to be the active weapon */
	int activeWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (activeWeapon == -1)
		return;

	char weaponName[32];
	GetEntityClassname(activeWeapon, weaponName, sizeof(weaponName));

	if (!StrEqual(weaponName, "weapon_colt"))
		return;

	/* Must be aiming at a live zombie */
	int target = GetClientAimTarget(client, false);

	if (target <= 0 || target > MaxClients
		|| !IsClientInGame(target) || !IsPlayerAlive(target))
		return;

	if (GetClientTeam(target) != Team_Axis)
		return;

	/* Check cooldown only after confirming a valid target */
	float currentTime = GetGameTime();
	if (currentTime < g_fESPIdentifyCooldown[client])
	{
		float remaining      = g_fESPIdentifyCooldown[client] - currentTime;
		int roundedSeconds   = RoundToCeil(remaining);
		if (roundedSeconds < 1)
			roundedSeconds = 1;

		ZM_PrintToChat(client, "%t", "ESP Identify Cooldown", roundedSeconds);
		return;
	}

	/* Look up class name and broadcast */
	ZombieClass zombieClass = ZombieClasses_GetClass(target);
	char className[ZM_MAX_CLASS_NAME];
	char targetName[MAX_NAME_LENGTH];
	char reporterName[MAX_NAME_LENGTH];

	GetZombieClassDisplayName(zombieClass, className, sizeof(className));
	GetClientName(target,   targetName,   sizeof(targetName));
	GetClientName(client,   reporterName, sizeof(reporterName));

	ZM_PrintToChatAll("%s reports: %s is %s", reporterName, targetName, className);

	g_fESPIdentifyCooldown[client] = currentTime + ESP_IDENTIFY_COOLDOWN;
}

// ============================================================================
// Timer Callbacks — Repeated centerprint to keep selection visible
// ============================================================================

public Action Timer_RepeatESPMessage(Handle timer, int userId)
{
	int client = GetClientOfUserId(userId);
	if (client && IsClientInGame(client))
		PrintCenterText(client, "%t", "ESP Skill Selected");
	return Plugin_Stop;
}

public Action Timer_RepeatNoSkillMessage(Handle timer, int userId)
{
	int client = GetClientOfUserId(userId);
	if (client && IsClientInGame(client))
		PrintCenterText(client, "%t", "No Skill Selected");
	return Plugin_Stop;
}
