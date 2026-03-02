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
	
	// Initialize human skills
	HumanSkills_OnClientConnect(client);
	
	// Initialize button tracking for gas ability
	g_iLastButtons[client] = 0;
		
	g_ClientInfo_Int[client][ClientInfo_KillsAsHuman] = 
	g_ClientInfo_Int[client][ClientInfo_KillsAsZombie] = 
	g_ClientInfo_Int[client][ClientInfo_Critter] = 
	g_ClientInfo_Bool[client][ClientInfo_IsCritical] = 
	g_ClientInfo_Bool[client][ClientInfo_SelectedClass] = 
	g_ClientInfo_Bool[client][ClientInfo_HasCustomClass] = 
	g_ClientInfo_Bool[client][ClientInfo_ShouldAutoEquip] = false;
	
	EmitSoundToClient(client, g_szSounds[Sound_JoinServer]);
}

public void OnClientPostAdminCheck(int client)
{
	// Check if this is the first real player joining a bot-only game
	// This fires after client is fully loaded and authenticated (better than OnClientPutInServer)
	if (g_bModActive && !g_bRoundEnded && !IsFakeClient(client))
	{
		if (GetRealPlayerCount() == 1)
		{
			// This is the first real player - restart the round
			g_bRoundEnded = true;
			
			// Notify all players
			PrintToChatAll("%t%t", ZM_PREFIX, "First Real Player Restart", client);
			
			// Restart after short delay
			CreateTimer(3.0, Timer_RestartRound, _, TIMER_FLAG_NO_MAPCHANGE);
		}
	}
}

public void OnClientDisconnect_Post(int client)
{
	// Clean up zombie class data
	ZombieClasses_OnClientDisconnect(client);
	
	// Clean up pickup boosts
	Pickups_OnClientDisconnect(client);
	
	// Clean up human skills
	HumanSkills_OnClientDisconnect(client);
	
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
			
			PrintToChatAll("%t%t", ZM_PREFIX, "Player Became Zombie", g_iZombie);
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
				
				// Show game commencing messages and countdown
				HUD_ShowGameCommencing();
				
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
					
					// Reset human skill on spawn (forces re-selection each spawn)
					HumanSkills_OnSpawn(client);
					
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
						
						// Give Colt to Rifleman and Support classes
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
						
						// Give Colt ammo (use ConVar limit)
						SetWeaponAmmo(client, Ammo_Colt, g_ConVarInts[ConVar_Human_Pistol_MaxAmmo]);
					}
				}
				case Team_Axis:
				{
					g_ClientInfo_Float[client][ClientInfo_DamageScale] = (MAX_HEALTH / g_ConVarFloats[ConVar_Zombie_Health]);
					g_ClientInfo_Float[client][ClientInfo_Health] = g_ConVarFloats[ConVar_Zombie_Health];
					g_ClientInfo_Bool[client][ClientInfo_IsCritical] = false;
					
					RemoveWeapons(client);
					GivePlayerItem(client, "weapon_spade");
					
					// Assign zombie class (includes Ghost alpha activation if needed)
					ZombieClasses_OnSpawn(client);
					
					SetPlayerModel(client, Model_Zombie_Default);
					
					SetPlayerLaggedMovementValue(client, g_ConVarFloats[ConVar_Zombie_Speed]);
					
					// Play zombie spawn sound for all players (including bots)
					PlaySoundFromPlayer(client, g_szSounds[Sound_ZombieSpawn]);
					
					// Show messages to real players only (bots don't need these)
					if (!IsFakeClient(client))
					{
						HUD_ShowZombieSpawnInfo(clientUserId);
					}
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
			// Trigger zombie class death effects
			ZombieClasses_OnDeath(client);
			
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
		
		// Notify all players
		PrintToChatAll("%t%t", ZM_PREFIX, "Player Became Zombie", client);
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
				
				PrintToChat(attacker, "%t%t", ZM_PREFIX, "Crit Kill Bonus", g_ConVarInts[ConVar_Zombie_CritReward]);
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
	
	// Reset visual effects when changing teams
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client && IsClientInGame(client))
	{
		ResetPlayerVisuals(client);
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
					
					PrintToChat(client, "%t%t", ZM_PREFIX, "Fatal Shot Warning");
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
				PrintToChat(client, "%t%t", ZM_PREFIX, "Class Change Blocked");
				
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
			// TODO: Revisit grenade mechanics for zombies in future
			// Currently disabled because zombies get stuck with grenades and can't switch back to spade
			static const char allowedZombieWeapons[][] = 
			{
				"spade"
				// "frag_us_live",       // Commented out - causes weapon switching bug
				// "frag_ger_live",      // Commented out - causes weapon switching bug
				// "riflegren_us_live",  // Commented out - causes weapon switching bug
				// "riflegren_ger_live"  // Commented out - causes weapon switching bug
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
		// Apply pickup damage modifications
		if (attacker > 0 && attacker <= MaxClients)
		{
			damage = Pickups_ModifyDamage(attacker, damage);
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

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	// Gas Zombie ability - Right-click (detect PRESS, not HOLD)
	if (g_bModActive && GetClientTeam(client) == Team_Axis)
	{
		// Check if button was just pressed (not held from previous frame)
		if ((buttons & IN_ATTACK2) && !(g_iLastButtons[client] & IN_ATTACK2))
		{
			ZombieClasses_TryUseGasAbility(client);
		}
		
		// Store current buttons for next frame comparison
		g_iLastButtons[client] = buttons;
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
				// No collision for first N seconds (prevents spawn blocking)
				return false;
			}
		}
	}
	
	// Normal collision for everyone else
	return true;
}

// ============================================================================
// VISUAL CLEANUP
// ============================================================================

void ResetPlayerVisuals(int client)
{
	// Deactivate ghost zombie effects if active
	if (g_iZombieClass[client] == view_as<int>(ZombieClass_Ghost))
	{
		DeactivateGhostEffect(client);
	}
	
	// Reset render mode and color to normal (catches any other visual effects)
	SetEntityRenderMode(client, RENDER_NORMAL);
	SetEntityRenderColor(client, 255, 255, 255, 255);
}
