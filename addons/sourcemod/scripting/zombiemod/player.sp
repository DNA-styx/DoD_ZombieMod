/**
 * =============================================================================
 * Zombie Mod for Day of Defeat Source
 *
 * By: Andersso
 *
 * SourceMod (C)2004-2008 AlliedModders LLC.  All rights reserved.
 * =============================================================================
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * As a special exception, AlliedModders LLC gives you permission to link the
 * code of this program (as well as its derivative works) to "Half-Life 2," the
 * "Source Engine," the "SourcePawn JIT," and any Game MODs that run on software
 * by the Valve Corporation.  You must obey the GNU General Public License in
 * all respects for all other code used.  Additionally, AlliedModders LLC grants
 * this exception to all derivative works.  AlliedModders LLC defines further
 * exceptions, found in LICENSE.txt (as of this writing, version JULY-31-2007),
 * or <http://www.sourcemod.net/license.php>.
 */

InitPlayers()
{
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Pre);
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
	HookEvent("dod_stats_player_damage", Event_PlayerDamage, EventHookMode_Post);
	
	AddNormalSoundHook(OnNormalSoundPlayed);
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_WeaponCanUse, OnWeaponCanUse);
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	SDKHook(client, SDKHook_ShouldCollide, OnShouldCollide);
	
		
	g_ClientInfo_Int[client][ClientInfo_KillsAsHuman] = 
	g_ClientInfo_Int[client][ClientInfo_KillsAsZombie] = 
	g_ClientInfo_Int[client][ClientInfo_Critter] = 
	g_ClientInfo_Bool[client][ClientInfo_IsCritical] = 
	g_ClientInfo_Bool[client][ClientInfo_SelectedClass] = 
	g_ClientInfo_Bool[client][ClientInfo_HasCustomClass] = 
	g_ClientInfo_Bool[client][ClientInfo_ShouldAutoEquip] = false;
	
	EmitSoundToClient(client, g_szSounds[Sound_JoinServer]);
}

public void OnClientDisconnect_Post(int client)
{
	if (g_bModActive)
	{
		// If the disconnected player was critical, give the critter the kill and reward.
		if (g_ClientInfo_Bool[client][ClientInfo_IsCritical])
		{
			int critAttacker = GetClientOfUserId(g_ClientInfo_Int[client][ClientInfo_Critter]);
			
			if (critAttacker)
			{
				AddPlayerKills(critAttacker, 1);
				GiveHumanReward(critAttacker);
			}
		}
		
		int numAllies = GetTeamClientCount(Team_Allies);
		int numAxis = GetTeamClientCount(Team_Axis);
		
		// Restart if there are not enough players.
		if (numAllies + numAxis <= g_ConVarInts[ConVar_MinPlayers])
		{
			g_bRoundEnded = true;
			
			CreateTimer(10.0, Timer_RestartRound, _, TIMER_FLAG_NO_MAPCHANGE);
		}
		else if (numAxis == 0)
		{
			SelectZombie();
			
			SetPlayerState(g_iZombie, PlayerState_ObserverMode);
			ChangeClientTeam(g_iZombie, Team_Axis);
			
			PrintHintText(g_iZombie, "You are now a Zombie!");
			ZM_PrintToChatAll("Player %N is now a Zombie.", g_iZombie);
		}
		else if (numAllies == 0)
		{
			CheckWinConditions();
		}
	}
}

SetPlayerModel(client, model)
{
	if (g_szModel[model][0] != '\0')
	{
		SetEntityModel(client, g_szModel[model]);
	}
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	if (g_ConVarBools[ConVar_Enabled])
	{
		int clientUserId = GetEventInt(event, "userid");
		int client = GetClientOfUserId(clientUserId);
		
		// Track spawn time for no-clip period
		g_flPlayerSpawnTime[client] = GetGameTime();
		
		g_ClientInfo_Float[client][ClientInfo_Health] = MAX_HEALTH;
		g_ClientInfo_Bool[client][ClientInfo_WeaponCanUse] = true;
		
		if (!g_bModActive)
		{
			if (!g_bRoundEnded && g_ConVarInts[ConVar_MinPlayers] <= GetTeamClientCount(Team_Allies) + GetTeamClientCount(Team_Axis))
			{
				g_bRoundEnded = true;
				
				ZM_PrintToChatAll("Game commencing in 15 seconds!");
				
				CreateTimer(15.0, Timer_RestartRound, _, TIMER_FLAG_NO_MAPCHANGE);
				
				SetRoundState(DoDRoundState_Restart);
			}
		}
		else
		{
			switch (GetClientTeam(client))
			{
				case Team_Allies:
				{
					g_ClientInfo_Float[client][ClientInfo_DamageScale] = 1.0;
					g_ClientInfo_Bool[client][ClientInfo_HasEquipped] = false;
					
					if (!g_bRoundEnded)
					{
						if (!g_ClientInfo_Bool[client][ClientInfo_ShouldAutoEquip])
						{
							CreateTimer(1.0, Timer_ShowEquipMenu, clientUserId, TIMER_FLAG_NO_MAPCHANGE);
						}
						else
						{
							Menu_PerformEquip(client);
						}
						
						int playerClass = GetPlayerClass(client);
						
						if (playerClass == PlayerClass_Rifleman
							 || playerClass == PlayerClass_Support)
						{
							GivePlayerItem(client, "weapon_colt");
						}
						else if (playerClass == PlayerClass_Assault)
						{
							// Remove smoke grenade
							int weapon = GetPlayerWeaponSlot(client, Slot_Melee);
							
							if (weapon != INVALID_WEAPON)
							{
								RemovePlayerItem(client, weapon);
								AcceptEntityInput(weapon, "Kill");
							}
							
							GivePlayerItem(client, "weapon_amerknife");
						}
						else if (playerClass == PlayerClass_Rocket)
						{
							// Remove secondary weapon
							int weapon = GetPlayerWeaponSlot(client, Slot_Secondary);
							
							if (weapon != INVALID_WEAPON)
							{
								RemovePlayerItem(client, weapon);
								AcceptEntityInput(weapon, "Kill");
							}
							
							GivePlayerItem(client, "weapon_colt");
						}
						
						SetWeaponAmmo(client, Ammo_Colt, ExtraAmmoColt);
					}
				}
				case Team_Axis:
				{
					g_ClientInfo_Float[client][ClientInfo_DamageScale] = (MAX_HEALTH / g_ConVarFloats[ConVar_Zombie_Health]);
					g_ClientInfo_Float[client][ClientInfo_Health] = g_ConVarFloats[ConVar_Zombie_Health];
					g_ClientInfo_Bool[client][ClientInfo_IsCritical] = false;
					
					// ============================================================================
					// PHASE 2: Track spawn time for time-based spawn protection
					// ============================================================================
					g_flZombieSpawnTime[client] = GetGameTime();
					
					RemoveWeapons(client);
					GivePlayerItem(client, "weapon_spade");
					
					PlaySoundFromPlayer(client, g_szSounds[Sound_ZombieSpawn]);
					
					SetPlayerModel(client, Model_Zombie_Default);
					
					SetPlayerLaggedMovementValue(client, g_ConVarFloats[ConVar_Zombie_Speed]);
				}
			}
		}
	}
}

public Action Timer_ShowEquipMenu(Handle timer, int client)
{
	if ((client = GetClientOfUserId(client)) && GetClientTeam(client) == Team_Allies)
	{
		DisplayMenu(g_EquipMenu[Menu_Main], client, 30);
	}
	return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (g_bModActive)
	{
		int clientUserId = GetEventInt(event, "userid");
		int client = GetClientOfUserId(clientUserId);
		int attackerUserId = GetEventInt(event, "attacker");
		int attacker = GetClientOfUserId(attackerUserId);
		
		if (GetEventBool(event, "dominated") || GetEventBool(event, "revenge"))
		{
			SetEventBool(event, "dominated", false);
			SetEventBool(event, "revenge", false);
			ResetDominations(attacker, client);
		}
		
		if (GetClientTeam(client) == Team_Allies)
		{
			SetEventString(event, "weapon", "crit");
			CreateTimer(0.1, Timer_SwitchToZombieTeam, clientUserId | (attackerUserId << 16), TIMER_FLAG_NO_MAPCHANGE);
		}
		else
		{
			PlaySoundFromPlayer(client, g_szSounds[Sound_ZombieDeath]);
			
			int critAttacker = GetClientOfUserId(g_ClientInfo_Int[client][ClientInfo_Critter]);
			
			if (critAttacker)
			{
				if (critAttacker != attacker)
				{
					AddPlayerKills(critAttacker, 1);
					
					SetEventInt(event, "attacker", g_ClientInfo_Int[client][ClientInfo_Critter]);
					SetEventString(event, "weapon", "crit");
					
					if (attacker)
					{
						AddPlayerKills(attacker, -1);
					}
				}
				
				GiveHumanReward(critAttacker);
				
				g_ClientInfo_Int[client][ClientInfo_Critter] = 0;
				
				g_ClientInfo_Int[attacker][ClientInfo_KillsAsHuman]++;
			}
			else if (attacker && attacker != client)
			{
				GiveHumanReward(attacker);
				
				g_ClientInfo_Int[attacker][ClientInfo_KillsAsHuman]++;
			}
		}
	}
	return Plugin_Continue;
}

public Action Timer_SwitchToZombieTeam(Handle timer, int data)
{
	int client = data & 0x0000FFFF;
	int attacker = data >> 16;
	
	if ((client = GetClientOfUserId(client)))
	{
		ChangeClientTeam(client, Team_Axis);
	}
	
	if (!CheckWinConditions() && (attacker = GetClientOfUserId(attacker)) && attacker != client)
	{
		g_ClientInfo_Int[attacker][ClientInfo_Critter] = 0;
		g_ClientInfo_Int[attacker][ClientInfo_KillsAsZombie]++;
		
		if (IsPlayerAlive(attacker))
		{
			if (g_ClientInfo_Bool[attacker][ClientInfo_IsCritical] && g_ConVarInts[ConVar_Zombie_CritReward])
			{
				int newHealth = GetClientHealth(attacker) + g_ConVarInts[ConVar_Zombie_CritReward];
				
				SetEntityHealth(attacker, newHealth);
				g_ClientInfo_Float[attacker][ClientInfo_Health] = (g_ClientInfo_Float[attacker][ClientInfo_DamageScale] * float(newHealth));
				
				g_ClientInfo_Bool[attacker][ClientInfo_IsCritical] = false;
				
				ZM_PrintToChat(attacker, "You received a %ihp boost for your kill!", g_ConVarInts[ConVar_Zombie_CritReward]);
			}
			
			GiveZombieReward(attacker);
		}
	}
	return Plugin_Continue;
}

public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	if (g_bModActive)
	{
		CheckWinConditions();
		
		SetEventBroadcast(event, true);
	}
	return Plugin_Continue;
}

public void Event_PlayerDamage(Event event, const char[] name, bool dontBroadcast)
{
	if (g_bModActive)
	{
		int client = GetClientOfUserId(GetEventInt(event, "victim"));
		
		int attackerUserId = GetEventInt(event, "attacker");
		int attacker = GetClientOfUserId(attackerUserId);
		
		if (GetClientTeam(client) == Team_Axis && attacker
			 && !g_ClientInfo_Bool[client][ClientInfo_IsCritical]
			 && GetEventInt(event, "hitgroup") == 1)
		{
			switch (GetEventInt(event, "weapon"))
			{
				case 
				WeaponID_AmerKnife, 
				WeaponID_Colt, 
				WeaponID_P38, 
				WeaponID_Spring, 
				WeaponID_K98_Scoped, 
				WeaponID_Bazooka, 
				WeaponID_Pschreck, 
				WeaponID_Thompson_Punch, 
				WeaponID_MP40_Punch:
				{
					// Don't change this, when a players health is 1 the game sometimes fucks up and the players view-offset drops down to the floor, like if you were a crushed midget.
					// Plus, the health bar looks bad.
					SetEntityHealth(client, 2);
					g_ClientInfo_Float[client][ClientInfo_Health] = (g_ClientInfo_Float[client][ClientInfo_DamageScale] * 2.0);
					
					g_ClientInfo_Int[client][ClientInfo_Critter] = attackerUserId;
					g_ClientInfo_Bool[client][ClientInfo_IsCritical] = true;
					
					float vecVelocity[3], vecClientEyePos[3], vecAttackerEyePos[3];
					
					GetClientEyePosition(client, vecClientEyePos);
					GetClientEyePosition(attacker, vecAttackerEyePos);
					
					MakeVectorFromPoints(vecAttackerEyePos, vecClientEyePos, vecVelocity);
					NormalizeVector(vecVelocity, vecVelocity);
					ScaleVector(vecVelocity, 400.0);
					
					PopHelmet(client, vecVelocity, vecClientEyePos);
					
					PlaySoundFromPlayer(client, g_szSounds[Sound_ZombieCritical]);
					
					EmitSoundToClient(attacker, g_szSounds[Sound_FinishHim]);
					PrintCenterText(attacker, "FINISH HIM!");
					
					ZM_PrintToChat(client, "You got hit by a fatal shot, take cover!");
				}
			}
		}
	}
}

public ActionOnPopHelmet(client, floatvecVelocity[3], floatvecOrigin[3])
{
	return g_bModActive && !g_ClientInfo_Bool[client][ClientInfo_IsCritical] && GetClientTeam(client) == Team_Axis ? Plugin_Handled : Plugin_Continue;
}

public ActionOnJoinClass(client, &playerClass)
{
	if (g_bModActive)
	{
		if (GetClientTeam(client) == Team_Allies)
		{
			if (g_bBlockChangeClass)
			{
				ZM_PrintToChat(client, "90 seconds of the round has passed, you cannot change class any more!");
				
				return Plugin_Handled;
			}
		}
		else
		{
			return Plugin_Handled;
		}
	}
	
	return Plugin_Continue;
}

public Action OnEnterPlayerState(int client, int &playerState)
{
	// Blocks the class menu from being displayed
	if (g_bModActive && playerState == PlayerState_PickingClass)
	{
		// This prevents the class selection menu to pop up on all team changes.
		// It is however displayed once for allied players, allowing them to decide witch class to.
		if (GetClientTeam(client) == Team_Allies && !g_ClientInfo_Bool[client][ClientInfo_SelectedClass])
		{
			g_ClientInfo_Bool[client][ClientInfo_SelectedClass] = true;
			return Plugin_Continue;
		}
		
		if (GetDesiredPlayerClass(client) == PlayerClass_None)
		{
			SetDesiredPlayerClass(client, PlayerClass_Assault);
		}
		
		playerState = PlayerState_ObserverMode;
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

public Action OnVoiceCommand(int client, int &voiceCommand)
{
	// Block zombies from making voice commands.
	return g_bModActive && GetClientTeam(client) == Team_Axis ? Plugin_Handled : Plugin_Continue;
}

public Action OnPlayerRespawn(int client)
{
	g_ClientInfo_Bool[client][ClientInfo_WeaponCanUse] = false;
}

public Action OnNormalSoundPlayed(int clients[64], int &numClients, char sample[PLATFORM_MAX_PATH], int &entity, int &channel, float &volume, int &level, int &pitch, int &flags)
{
	if (g_bModActive && entity && entity <= MaxClients)
	{
		// Block all german pain and round start sounds.
		if (GetClientTeam(entity) == Team_Axis
			 && (StrContains(sample, "pain", false) != -1
				 || StrContains(sample, "player/german/startround", false) != -1))
		{
			return Plugin_Stop;
		}
	}
	
	return Plugin_Continue;
}

public Action OnWeaponCanUse(int client, int weapon)
{
	if (g_bModActive && g_ClientInfo_Bool[client][ClientInfo_WeaponCanUse])
	{
		char className[MAX_WEAPON_LENGTH];
		GetEdictClassname(weapon, className, sizeof(className));
		
		if (GetClientTeam(client) == Team_Axis)
		{
			static const char allowedZombieWeapons[][] = 
			{
				"spade", 
				"frag_us_live", 
				"frag_ger_live", 
				"riflegren_us_live", 
				"riflegren_ger_live"
			};
			
			for (int i; i < sizeof(allowedZombieWeapons); i++)
			{
				if (StrEqual(className[7], allowedZombieWeapons[i])) // Skip the first 7 characters in className to avoid comparing the "weapon_" prefix.
				{
					return Plugin_Continue;
				}
			}
			
			return Plugin_Handled;
		}
	}
	
	return Plugin_Continue;
}

public Action OnTakeDamage(int client, int &attacker, int &inflictor, float &damage, int &damageType)
{
	if (g_bModActive)
	{
		if (attacker && attacker < MaxClients && GetClientTeam(client) == Team_Axis && IsInZombieSpawn(client))
		{
			PrintHintText(attacker, "Spawn Protection enabled");
			
			return Plugin_Handled;
		}
		
		if (g_ClientInfo_Float[client][ClientInfo_DamageScale] != 1.0)
		{
			static damageAccumulatorOffset;
			
			if (!damageAccumulatorOffset && (damageAccumulatorOffset = FindDataMapInfo(client, "m_flDamageAccumulator")) == -1)
			{
				LogError("Error: Failed to obtain offset: \"m_flDamageAccumulator\"!");
				return Plugin_Continue;
			}
			
			damage *= g_ClientInfo_Float[client][ClientInfo_DamageScale];
			
			float newHealth = g_ClientInfo_Float[client][ClientInfo_Health] - damage;
			
			// Is the player supposed to die?
			if (newHealth <= 0.0)
			{
				// Set the damage required to kill the player.
				damage = float(GetEntData(client, g_iOffset_Health)) + GetEntDataFloat(client, damageAccumulatorOffset);
				
				return Plugin_Changed;
			}
			
			// Will the health go down to zero?
			if (float(GetEntData(client, g_iOffset_Health)) + GetEntDataFloat(client, damageAccumulatorOffset) - damage <= 0)
			{
				g_ClientInfo_Float[client][ClientInfo_Health] = newHealth;
				
				return Plugin_Handled;
			}
			
			// Correct the players health.
			SetEntData(client, g_iOffset_Health, RoundFloat(g_ClientInfo_Float[client][ClientInfo_Health]), _, true);
			
			g_ClientInfo_Float[client][ClientInfo_Health] = newHealth;
			
			return Plugin_Changed;
		}
	}
	
	return Plugin_Continue;
}

public bool OnShouldCollide(int client, int collisionGroup, int contentsMask, bool originalResult)
{
	if (!g_bModActive)
		return originalResult;
	
	// Allow humans to pass through each other for 3 seconds after spawn
	// This prevents spawn blocking by bots
	if (client > 0 && client <= MaxClients && IsClientInGame(client))
	{
		if (GetClientTeam(client) == Team_Allies)
		{
			float timeSinceSpawn = GetGameTime() - g_flPlayerSpawnTime[client];
			if (timeSinceSpawn < g_ConVarFloats[ConVar_Spawn_NoClip_Time])
			{
				// No collision for first 3 seconds
				// Show debug message to player
				// Only show message to real players, not bots
				// Only show if debug mode is enabled
				if (!IsFakeClient(client) && g_ConVarBools[ConVar_Debug])
				{
									PrintHintText(client, "Spawn no-clip disabled");
				}
				return false;
			}
		}
	}
	
	// Normal collision for everyone else
	return true;
}

// ============================================================================
// ZOMBIE NAME/HEALTH DISPLAY
// ============================================================================

Handle g_hZombieInfoTimer = null;

void InitZombieInfoDisplay()
{
	// Prevent double-initialization
	if (g_hZombieInfoTimer != null)
	{
		return;
	}
	
	g_hZombieInfoTimer = CreateTimer(0.1, Timer_ShowZombieInfo, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnMapStart()
{
	// Recreate timer on map change
	
	// Clear old handle if it exists
	g_hZombieInfoTimer = null;
	
	// Recreate the timer
	g_hZombieInfoTimer = CreateTimer(0.1, Timer_ShowZombieInfo, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	
	// Also recreate zombie self-health timer
	RecreateZombieSelfHealthTimer();
}

void CleanupZombieInfoDisplay()
{
	// Timer will auto-clean with TIMER_FLAG_NO_MAPCHANGE
	// Just set handle to null
	g_hZombieInfoTimer = null;
}

public Action Timer_ShowZombieInfo(Handle timer)
{
	if (!g_bModActive || !g_ConVarBools[ConVar_Show_Zombie_Info])
		return Plugin_Continue;
	
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || !IsPlayerAlive(client))
			continue;
		
		// Show different info based on team
		if (GetClientTeam(client) == Team_Allies)
		{
			// Humans see zombie info
			ShowZombieInfoToClient(client);
		}
		else if (GetClientTeam(client) == Team_Axis)
		{
			// Zombies see human info
			ShowHumanInfoToClient(client);
		}
	}
	
	return Plugin_Continue;
}

void ShowZombieInfoToClient(int client)
{
	int target = GetClientAimTarget(client);
	
	// Validate target
	if (target <= 0 || target > MaxClients)
		return;
	
	if (!IsClientInGame(target) || !IsPlayerAlive(target))
		return;
	
	// Only show zombie info
	if (GetClientTeam(target) != Team_Axis)
		return;
	
	// Get zombie's real health
	int health = RoundFloat(g_ClientInfo_Float[target][ClientInfo_Health]);
	
	char name[MAX_NAME_LENGTH];
	GetClientName(target, name, sizeof(name));
	
	// Show different message for critical zombies
	if (g_ClientInfo_Bool[target][ClientInfo_IsCritical])
	{
		PrintCenterText(client, "%s (CRITICAL HEALTH!)", name);
	}
	else
	{
		PrintCenterText(client, "%s (%d HP)", name, health);
	}
}

void ShowHumanInfoToClient(int client)
{
	int target = GetClientAimTarget(client);
	
	// Validate target
	if (target <= 0 || target > MaxClients)
		return;
	
	if (!IsClientInGame(target) || !IsPlayerAlive(target))
		return;
	
	// Only show human info
	if (GetClientTeam(target) != Team_Allies)
		return;
	
	char name[MAX_NAME_LENGTH];
	GetClientName(target, name, sizeof(name));
	
	// Show only name, no health
	PrintCenterText(client, "%s", name);
}

// ============================================================================
// ZOMBIE SELF HEALTH DISPLAY
// ============================================================================

Handle g_hZombieSelfHealthTimer = null;

void InitZombieSelfHealthDisplay()
{
	// Prevent double-initialization
	if (g_hZombieSelfHealthTimer != null)
		return;
	
	g_hZombieSelfHealthTimer = CreateTimer(0.5, Timer_ShowZombieSelfHealth, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void RecreateZombieSelfHealthTimer()
{
	// Clear old handle
	g_hZombieSelfHealthTimer = null;
	
	// Recreate the timer
	g_hZombieSelfHealthTimer = CreateTimer(0.5, Timer_ShowZombieSelfHealth, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void CleanupZombieSelfHealthDisplay()
{
	// Timer will auto-clean with TIMER_FLAG_NO_MAPCHANGE
	g_hZombieSelfHealthTimer = null;
}

public Action Timer_ShowZombieSelfHealth(Handle timer)
{
	if (!g_bModActive)
		return Plugin_Continue;
	
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || !IsPlayerAlive(client))
			continue;
		
		// Only show to zombies
		if (GetClientTeam(client) != Team_Axis)
			continue;
		
		ShowZombieSelfHealth(client);
	}
	
	return Plugin_Continue;
}

void ShowZombieSelfHealth(int client)
{
	int health = RoundFloat(g_ClientInfo_Float[client][ClientInfo_Health]);
	
	// Use PrintHintText for DoD:S compatibility
	PrintHintText(client, "Your Health: %d HP", health);
}
