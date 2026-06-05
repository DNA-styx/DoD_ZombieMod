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

// ============================================================================
// Initialization
// ============================================================================

void Players_OnPluginStart()
{
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Pre);
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
	HookEvent("dod_stats_player_damage", Event_PlayerDamage, EventHookMode_Post);

	AddNormalSoundHook(OnNormalSoundPlayed);

	for (int i = 0; i <= MAXPLAYERS; i++)
		g_hZombieInfoTimer[i] = null;
}


// ============================================================================
// Client Connection / Disconnection
// ============================================================================

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_WeaponCanUse, OnWeaponCanUse);
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	SDKHook(client, SDKHook_ShouldCollide, OnShouldCollide);
	
	// Initialize human skills
	HumanSkills_OnClientConnect(client);
	ModularSkills_OnClientConnect(client);
	
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
	Sounds_OnClientConnect(client);   // play ambience to late-joiners during active rounds
}

public void OnClientPostAdminCheck(int client)
{
	/* Check if this is the first real player joining a bot-only game */
	if (g_bModActive && !g_bRoundEnded && !IsFakeClient(client))
	{
		if (GetRealPlayerCount() == 1)
		{
			g_bRoundEnded = true;
			
			ZM_PrintToChatAll("%t", "First Real Player Restart", client);
			
			CreateTimer(3.0, Timer_RestartRound, _, TIMER_FLAG_NO_MAPCHANGE);
		}
	}
}

public void OnClientDisconnect_Post(int client)
{
	/* Clear pending restart flag if this player disconnects before spawning */
	// Clean up zombie class data
	ZombieClasses_OnClientDisconnect(client);

	/* Kill any pending zombie spawn info timer */
	if (g_hZombieInfoTimer[client] != null)
	{
		KillTimer(g_hZombieInfoTimer[client]);
		g_hZombieInfoTimer[client] = null;
	}

	// Clean up pickup boosts
	Pickups_OnClientDisconnect(client);
	
	// Clean up human skills
	HumanSkills_OnClientDisconnect(client);
	ModularSkills_OnClientDisconnect(client);
	
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
			
			/* Guard against SelectZombie failure (no eligible clients). */
			if (g_iZombie > 0 && g_iZombie <= MaxClients
				&& IsClientInGame(g_iZombie))
			{
				SetPlayerState(g_iZombie, PlayerState_ObserverMode);
				ChangeClientTeam(g_iZombie, Team_Axis);
				
				ZM_PrintToChatAll("%t", "Player Became Zombie", g_iZombie);
			}
		}
		else if (numAllies == 0)
		{
			CheckWinConditions();
		}
	}
}

SetPlayerModel(int client)
{
	/* Build a list of populated model slots then pick one at random.
	 * Falls back to no change if no models are configured. */
	int populated[Model_Size];
	int count = 0;

	for (int i = 0; i < Model_Size; i++)
	{
		if (g_szModel[i][0] != '\0')
			populated[count++] = i;
	}

	if (count == 0)
		return;

	int chosen = populated[count > 1 ? GetRandomInt(0, count - 1) : 0];
	SetEntityModel(client, g_szModel[chosen]);
}


// ============================================================================
// Spawn / Death Events
// ============================================================================

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	if (g_ConVarBools[ConVar_Enabled])
	{
		int clientUserId = GetEventInt(event, "userid");
		int client = GetClientOfUserId(clientUserId);
		
		// Track spawn time for no-clip period
		g_flPlayerSpawnTime[client] = GetGameTime();
		
		// Reset ESP identification cooldown
		g_fESPIdentifyCooldown[client] = 0.0;
		
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
						
						// Notify modular skills system
						ModularSkills_OnClientSpawn(client, Team_Allies);
				}
				case Team_Axis:
				{
					g_ClientInfo_Float[client][ClientInfo_DamageScale] = (MAX_HEALTH / g_ConVarFloats[ConVar_Zombie_Health]);
					g_ClientInfo_Float[client][ClientInfo_Health] = g_ConVarFloats[ConVar_Zombie_Health];
					g_ClientInfo_Bool[client][ClientInfo_IsCritical] = false;
					
					RemoveWeapons(client);
					GivePlayerItem(client, "weapon_spade");

					/* Hide spade if CVar is off. Weapon entity is destroyed on
					 * death so no cleanup needed. */
					if (!g_ConVarBools[ConVar_Zombie_Show_Weapon])
					{
						int spade = GetPlayerWeaponSlot(client, Slot_Melee);
						if (spade != -1)
						{
							SetEntityRenderMode(spade, RENDER_TRANSALPHA);
							SetEntityRenderColor(spade, 255, 255, 255, 0);
						}
					}
					ZombieClasses_OnSpawn(client);
					
					SetPlayerModel(client);
					
					SetPlayerLaggedMovementValue(client, g_ConVarFloats[ConVar_Zombie_Speed]);
					
					// Play zombie spawn sound for all players (including bots)
					PlaySoundFromPlayer(client, g_szSounds[Sound_ZombieSpawn]);

					/* Class info centre print is shown by MenuHandler_ZombieClass
					 * after the player picks their class (or on timeout/exit).
					 * Showing it here would display "Normal Zombie" before the
					 * class menu has been interacted with. */
						
						// Notify modular skills system
						ModularSkills_OnClientSpawn(client, Team_Axis);
				}
			}
		}
	}
}

public Action Timer_ShowEquipMenu(Handle timer, int client)
{
	if ((client = GetClientOfUserId(client)) && GetClientTeam(client) == Team_Allies)
	{
		g_flEquipMenuExpiry[client] = GetGameTime() + 30.0;
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
			SetEventString(event, "weapon", "zm_zombie_kill");
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
			
			// Notify modular skills system
			ModularSkills_OnClientDeath(client);
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
		ZM_PrintToChatAll("%t", "Player Became Zombie", client);
	}
	
	// Resolve attacker before win condition check to allow logging in both branches
	attacker = GetClientOfUserId(attacker);
	
	bool wasEnded = g_bRoundEnded;
	
	if (!CheckWinConditions() && attacker && attacker != client)
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
				
				ZM_PrintToChat(attacker, "%t", "Crit Kill Bonus", g_ConVarInts[ConVar_Zombie_CritReward]);
			}
			
			GiveZombieReward(attacker);
		}
	}
	
	// HLStatsX: zombie killed the last human (the kill that ended the round)
	if (g_bRoundEnded && !wasEnded && attacker && attacker != client && client && !IsFakeClient(attacker))
	{
		char attackerSteam[32], victimSteam[32];
		GetClientAuthId(attacker, AuthId_Steam2, attackerSteam, sizeof(attackerSteam));
		GetClientAuthId(client, AuthId_Steam2, victimSteam, sizeof(victimSteam));
		LogToGame("\"%N<%d><%s><Axis>\" triggered \"zm_killed_last_human\" against \"%N<%d><%s><Allies>\"",
			attacker, GetClientUserId(attacker), attackerSteam,
			client, GetClientUserId(client), victimSteam);
	}
	
	return Plugin_Continue;
}


// ============================================================================
// Team Change
// ============================================================================

public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	if (g_bModActive)
	{
		CheckWinConditions();

		SetEventBroadcast(event, true);
	}

	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client && IsClientInGame(client))
	{
		ResetPlayerVisuals(client);
	}

	return Plugin_Continue;
}


// ============================================================================
// Damage Handling
// ============================================================================

/**
 * Maps a crit-eligible weapon ID to its HLStatsX log string.
 * Used to write zm_crit_<weapon> kill lines when a crit shot lands.
 */
void GetCritWeaponName(int weaponId, char[] buffer, int maxlen)
{
	switch (weaponId)
	{
		case WeaponID_AmerKnife:         strcopy(buffer, maxlen, "zm_crit_amerknife");
		case WeaponID_Colt:              strcopy(buffer, maxlen, "zm_crit_colt");
		case WeaponID_P38:               strcopy(buffer, maxlen, "zm_crit_p38");
		case WeaponID_Spring_Zoomed:     strcopy(buffer, maxlen, "zm_crit_spring");
		case WeaponID_K98_Scoped_Zoomed: strcopy(buffer, maxlen, "zm_crit_k98_scoped");
		case WeaponID_Bazooka:           strcopy(buffer, maxlen, "zm_crit_bazooka");
		case WeaponID_Pschreck:          strcopy(buffer, maxlen, "zm_crit_pschreck");
		case WeaponID_Thompson_Punch:    strcopy(buffer, maxlen, "zm_crit_thompson");
		case WeaponID_MP40_Punch:        strcopy(buffer, maxlen, "zm_crit_mp40");
		default:                         strcopy(buffer, maxlen, "zm_crit_unknown");
	}
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
				WeaponID_Spring_Zoomed, 
				WeaponID_K98_Scoped_Zoomed, 
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
					
					StopSound(attacker, SNDCHAN_AUTO, g_szSounds[Sound_FinishHim]);
					EmitSoundToClient(attacker, g_szSounds[Sound_FinishHim]);
					
					ZM_PrintToChat(client, "%t", "Fatal Shot Warning");
					
					// HLStatsX: log the weapon that triggered the crit
					char attackerSteam[32], victimSteam[32], critWeapon[32];
					GetClientAuthId(attacker, AuthId_Steam2, attackerSteam, sizeof(attackerSteam));
					GetClientAuthId(client, AuthId_Steam2, victimSteam, sizeof(victimSteam));
					GetCritWeaponName(GetEventInt(event, "weapon"), critWeapon, sizeof(critWeapon));
					LogToGame("\"%N<%d><%s><Allies>\" killed \"%N<%d><%s><Axis>\" with \"%s\"",
						attacker, GetClientUserId(attacker), attackerSteam,
						client, GetClientUserId(client), victimSteam,
						critWeapon);
				}
			}
		}
	}
}

public ActionOnPopHelmet(client, floatvecVelocity[3], floatvecOrigin[3])
{
	return g_bModActive && !g_ClientInfo_Bool[client][ClientInfo_IsCritical] && GetClientTeam(client) == Team_Axis ? Plugin_Handled : Plugin_Continue;
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
			/* Cache the datamap offset across calls. Use a separate
			 * "checked" flag so a failed lookup (-1) doesn't get retried
			 * forever, and -1 doesn't accidentally get used as an offset
			 * later in this function. */
			static int damageAccumulatorOffset = -1;
			static bool damageAccumulatorChecked = false;
			
			if (!damageAccumulatorChecked)
			{
				damageAccumulatorChecked = true;
				damageAccumulatorOffset = FindDataMapInfo(client, "m_flDamageAccumulator");
				if (damageAccumulatorOffset == -1)
				{
					LogError("Error: Failed to obtain offset: \"m_flDamageAccumulator\"!");
				}
			}
			
			if (damageAccumulatorOffset == -1)
				return Plugin_Continue;
			
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


// ============================================================================
// Per-Frame Input (OnPlayerRunCmd)
// Gas zombie active ability and ESP identification triggered here.
// ============================================================================

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	// Store previous button state before updating
	int lastButtons = g_iLastButtons[client];
	g_iLastButtons[client] = buttons;
	
	if (!g_bModActive)
		return Plugin_Continue;
	
	if (!IsClientInGame(client) || !IsPlayerAlive(client))
		return Plugin_Continue;
	
	int team = GetClientTeam(client);
	
	// Human ESP ability - delegated to human_skill.sp
	if (team == Team_Allies)
	{
		HumanSkills_OnPlayerRunCmd(client, buttons, lastButtons);
	}
	// Gas Zombie ability - Right-click (detect PRESS, not HOLD)
	else if (team == Team_Axis)
	{
		// Check if button was just pressed (not held from previous frame)
		if ((buttons & IN_ATTACK2) && !(lastButtons & IN_ATTACK2))
		{
			ZombieClasses_TryUseGasAbility(client);
		}
	}
	
	return Plugin_Continue;
}

public bool OnShouldCollide(int client, int collisionGroup, int contentsMask, bool originalResult)
{
	if (!g_bModActive)
		return originalResult;
	
	/* Allow humans to pass through each other for ConVar_Spawn_NoClip_Time seconds after spawn.
	 * Prevents spawn blocking by bots. */
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
// Utility
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

public ActionOnJoinClass(client, &playerClass)
{
	if (g_bModActive)
	{
		if (GetClientTeam(client) == Team_Allies)
		{
			if (g_bBlockChangeClass)
			{
				ZM_PrintToChat(client, "%t", "Class Change Blocked");
				
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
