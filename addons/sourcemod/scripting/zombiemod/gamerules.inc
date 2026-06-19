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

void GameRules_OnPluginStart()
{
	HookEvent("dod_round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("dod_round_active", Event_RoundActive, EventHookMode_PostNoCopy);
}


// ============================================================================
// Round Events
// ============================================================================

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	if (g_bModActive)
	{
		static const char objectiveKillEnts[][] = 
		{
			"dod_round_timer", 
			"dod_bomb_target", 
			"dod_capture_area"
		};
		
		static const char teamBlockerKillEnts[][] = 
		{
			"func_team_wall", 
			"func_teamblocker"
		};
		
		int entity = -1;
		
		if (!g_bWhiteListed[WhiteList_Objectives])
		{
			SetNumControlPoints(0);
			
			// Remove all objective related entities
			for (int i; i < sizeof(objectiveKillEnts); i++)
			{
				while ((entity = FindEntityByClassname(entity, objectiveKillEnts[i])) != -1)
				{
					AcceptEntityInput(entity, "Kill");
				}
			}
			
			entity = -1;
			
			// Disable all bomb dispensers
			while ((entity = FindEntityByClassname(entity, "dod_bomb_dispenser")) != -1)
			{
				AcceptEntityInput(entity, "Disable");
			}
			
			entity = -1;
			
			// Hide all control point flags
			while ((entity = FindEntityByClassname(entity, "dod_control_point")) != -1)
			{
				AcceptEntityInput(entity, "HideModel");
			}
			
			entity = -1;
			
			// Stop flag wave sound on all control points
			while ((entity = FindEntityByClassname(entity, "ambient_generic")) != -1)
			{
				char soundFileName[PLATFORM_MAX_PATH];
				GetEntPropString(entity, Prop_Data, "m_iszSound", soundFileName, sizeof(soundFileName));
				
				if (StrEqual(soundFileName, "ambient/flag.wav"))
				{
					AcceptEntityInput(entity, "StopSound");
				}
			}
			
			if (g_hRoundTimer != null)
			{
				KillTimer(g_hRoundTimer);
				
				g_hRoundTimer = null;
			}
			
			CreateTimer(0.1, Timer_CreateRoundTimer, _, TIMER_FLAG_NO_MAPCHANGE);
		}
		
		// Remove HDR tone-mapping controllers
		if (!g_bWhiteListed[WhiteList_Environment])
		{
			entity = -1;
			
			while ((entity = FindEntityByClassname(entity, "env_tonemap_controller")) != -1)
			{
				AcceptEntityInput(entity, "Kill");
			}
		}
		
		// Remove trigger_hurts
		if (!g_bWhiteListed[WhiteList_TriggerHurts])
		{
			entity = -1;
			
			while ((entity = FindEntityByClassname(entity, "trigger_hurt")) != -1)
			{
				AcceptEntityInput(entity, "Kill");
			}
		}
		
		// Remove team blockers
		if (!g_bWhiteListed[WhiteList_TeamBlockers])
		{
			entity = -1;
			
			for (int i; i < sizeof(teamBlockerKillEnts); i++)
			{
				while ((entity = FindEntityByClassname(entity, teamBlockerKillEnts[i])) != -1)
				{
					AcceptEntityInput(entity, "Kill");
				}
			}
		}
		
		entity = -1;
		
		// Remove scoring entities
		while ((entity = FindEntityByClassname(entity, "dod_scoring")) != -1)
		{
			AcceptEntityInput(entity, "Kill");
		}
	}
		
		// Notify modular skills system
		ModularSkills_OnRoundStart();
}


// ============================================================================
// Win Condition Checks
// ============================================================================

public Action Timer_CreateRoundTimer(Handle timer)
{
	if ((g_iRoundTimer = CreateEntityByName("dod_round_timer")) != -1)
	{
		SetTimeRemaining(g_iRoundTimer, g_ConVarInts[ConVar_Zombie_RoundTime]);
		
		PauseTimer(g_iRoundTimer);
	}
	
	// Initialize zombie classes for new round
	ZombieClasses_OnRoundStart();
	
	// Reset pickup spawn timer for new round
	Pickups_OnRoundStart();

	// Start ambient sound track
	Sounds_OnRoundStart();
	
	return Plugin_Continue;
}

public void Event_RoundActive(Event event, const char[] name, bool dontBroadcast)
{
	if (g_bModActive)
	{
		/* Timer_CreateRoundTimer leaves g_iRoundTimer at -1 if entity
		 * creation failed. Guard so we don't call ResumeTimer(-1)
		 * and don't spin up Timer_RoundTimerThink with a bad ref. */
		if (g_iRoundTimer <= 0)
		{
			LogError("Event_RoundActive: dod_round_timer entity not available");
			return;
		}
		
		ResumeTimer(g_iRoundTimer);
		
		g_hRoundTimer = CreateTimer(1.0, Timer_RoundTimerThink, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
	}
}


// ============================================================================
// Timers
// Round timer, end game, and restart timers.
// ============================================================================

bool CheckWinConditions()
{
	if (g_bRoundEnded)
	{
		return true;
	}
	
	int numHumans = GetHumanCount();
	
	if (!numHumans)
	{
		RoundEnd(Team_Axis);
	}
	else if (numHumans == 1 && !g_iLastHuman)
	{
		ZM_PrintToChatAll("%t", "Last Human Beaconed");
		EmitSoundToAll(g_szSounds[Sound_LastManStanding]);
		
		// Find and set the last human
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && !IsClientSourceTV(i))
			{
				if (!g_iLastHuman && GetClientTeam(i) == Team_Allies)
				{
					g_iLastHuman = GetClientUserId(i);
					
					// HLStatsX: award the last human standing (bot or real player)
					char steamId[32];
					GetClientAuthId(i, AuthId_Steam2, steamId, sizeof(steamId));
					LogToGame("\"%N<%d><%s><Allies>\" triggered \"zm_last_human_standing\"",
						i, GetClientUserId(i), steamId);
					
					break;  // Found them, exit loop
				}
			}
		}
	}
	
	return g_bRoundEnded;
}

RoundEnd(winningTeam)
{
	// Disable zombie class features (teleporter, etc.)
	ZombieClasses_OnRoundEnd();

	// Stop ambient sound track
	Sounds_OnRoundEnd();

	// Notify skill plugins
	ModularSkills_OnRoundEnd();
	
	bool winLimitReached = ++g_iRoundWins >= g_ConVarInts[ConVar_WinLimit];
	
	if (winLimitReached)
	{
		ZM_PrintToChatAll("%t", "Win Limit Reached");
		EmitSoundToAll(g_szSounds[Sound_End]);
	}
	else if (winningTeam == Team_Allies)
	{
		EmitSoundToAll(g_szSounds[Sound_HumansWin]);
		
		// HLStatsX: award all surviving humans
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && !IsClientSourceTV(i) && !IsFakeClient(i)
				&& GetClientTeam(i) == Team_Allies && IsPlayerAlive(i))
			{
				char steamId[32];
				GetClientAuthId(i, AuthId_Steam2, steamId, sizeof(steamId));
				LogToGame("\"%N<%d><%s><Allies>\" triggered \"zm_human_survived\"",
					i, GetClientUserId(i), steamId);
			}
		}
	}
	else if (winningTeam == Team_Axis)
	{
		EmitSoundToAll(g_szSounds[Sound_ZombiesWin]);
	}
	
	// Handle per-client operations (stop sound, overlays)
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsClientSourceTV(i))
		{
			if (g_iLastHuman)
			{
				StopSound(i, SNDCHAN_AUTO, g_szSounds[Sound_LastManStanding]);
			}
			
			// Reset all visual effects (spawn protection, ghost zombie, etc.)
			ResetPlayerVisuals(i);
			
			// Apply screen overlays
			if (winningTeam == Team_Allies)
			{
				ScreenOverlay(i, g_szOverlay[Overlay_HumansWin]);
			}
			else if (winningTeam == Team_Axis)
			{
				ScreenOverlay(i, g_szOverlay[Overlay_ZombiesWin]);
			}
		}
	}
	
	g_bRoundEnded = true;
	
	if (winLimitReached)
	{
		char buffer[64];
		
		Handle topHumanKills = CreateArray(), topZombieKills = CreateArray();
		
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && !IsClientSourceTV(i))
			{
				if (g_ClientInfo_Int[i][ClientInfo_KillsAsHuman])
				{
					PushArrayCell(topHumanKills, i);
				}
				
				if (g_ClientInfo_Int[i][ClientInfo_KillsAsZombie])
				{
					PushArrayCell(topZombieKills, i);
				}
			}
		}
		
		Handle topScorePanel = CreatePanel();
		
		SetPanelTitle(topScorePanel, "Top scores");
		DrawPanelText(topScorePanel, "\n \nHumans:");
		
		int topHumanArraySize = GetArraySize(topHumanKills);
		
		if (topHumanArraySize)
		{
			SortADTArrayCustom(topHumanKills, SortByKillsAsHuman);
			
			if (topHumanArraySize > SCOREBOARD_MAX_ELEMENTS)
			{
				topHumanArraySize = SCOREBOARD_MAX_ELEMENTS;
			}
			
			for (int i; i < topHumanArraySize; i++)
			{
				int client = GetArrayCell(topHumanKills, i);
				
				GetClientName(client, buffer, sizeof(buffer));
				Format(buffer, sizeof(buffer), "%i. %s (%i Kills)", i + 1, buffer, g_ClientInfo_Int[client][ClientInfo_KillsAsHuman]);
				
				DrawPanelText(topScorePanel, buffer);
			}
		}
		else
		{
			DrawPanelText(topScorePanel, "<None>");
		}
		
		DrawPanelText(topScorePanel, "\n \nZombies:");
		
		int topZombieArraySize = GetArraySize(topZombieKills);
		
		if (topZombieArraySize)
		{
			SortADTArrayCustom(topZombieKills, SortByKillsAsZombie);
			
			if (topZombieArraySize > SCOREBOARD_MAX_ELEMENTS)
			{
				topZombieArraySize = SCOREBOARD_MAX_ELEMENTS;
			}
			
			for (int i; i < topZombieArraySize; i++)
			{
				int client = GetArrayCell(topZombieKills, i);
				
				GetClientName(client, buffer, sizeof(buffer));
				Format(buffer, sizeof(buffer), "%i. %s (%i Kills)", i + 1, buffer, g_ClientInfo_Int[client][ClientInfo_KillsAsZombie]);
				
				DrawPanelText(topScorePanel, buffer);
			}
		}
		else
		{
			DrawPanelText(topScorePanel, "<None>");
		}
		
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && !IsClientSourceTV(i))
			{
				SendPanelToClient(topScorePanel, i, MenuHandler_Dummy, 10);
			}
		}
		
		CloseHandle(topHumanKills);
		CloseHandle(topZombieKills);
		CloseHandle(topScorePanel);
		
		CreateTimer(10.0, Timer_EndGame, _, TIMER_FLAG_NO_MAPCHANGE);
	}
	else
	{
		CreateTimer(10.0, Timer_RestartRound, _, TIMER_FLAG_NO_MAPCHANGE);
	}
}

public SortByKillsAsHuman(client, target, Handlearray, Handlehandle)
{
	return g_ClientInfo_Int[target][ClientInfo_KillsAsHuman] - g_ClientInfo_Int[client][ClientInfo_KillsAsHuman];
}

public SortByKillsAsZombie(client, target, Handlearray, Handlehandle)
{
	return g_ClientInfo_Int[target][ClientInfo_KillsAsZombie] - g_ClientInfo_Int[client][ClientInfo_KillsAsZombie];
}

public MenuHandler_Dummy(Handlepanel, MenuAction:menuAction, param1, param2)
{
	return;
}

public ActionOnAddWaveTime(index, &floatdelay)
{
	return g_bModActive ? Plugin_Handled : Plugin_Continue;
}

public Action Timer_RoundTimerThink(Handle timer)
{
	if (g_bRoundEnded)
	{
		PauseTimer(g_iRoundTimer);
		
		g_hRoundTimer = null;
		
		return Plugin_Stop;
	}
	
	int timeRemaining = RoundFloat(GetTimeRemaining(g_iRoundTimer)) - 1;
	
	if (!g_bBlockChangeClass && (g_ConVarInts[ConVar_Zombie_RoundTime] - timeRemaining == 60))
	{
		g_bBlockChangeClass = true;
	}
	
	if (g_iLastHuman)
	{
		int lastHuman = GetClientOfUserId(g_iLastHuman);
		
		int interval = g_ConVarInts[ConVar_Beacon_Interval];
		
		if (lastHuman && g_iBeaconTicks++ % (interval * 2) >= interval)
		{
			float vecPosition[3];
			GetClientAbsOrigin(lastHuman, vecPosition);
			
			vecPosition[2] += 10.0;
			
			TE_SetupBeamRingPoint(vecPosition, 10.0, 550.0, g_iBeamSprite, g_iHaloSprite, 0, 10, 0.6, 10.0, 0.5, { 0, 255, 0, 255 }, 10, 0);
			TE_SendToAll();
			
			EmitAmbientSound(SOUND_BLIP, vecPosition, lastHuman, SNDLEVEL_RAIDSIREN);
		}
	}
	
	switch (timeRemaining)
	{
		case 0:
		{
			RoundEnd(Team_Allies);
			
			g_hRoundTimer = null;
			
			return Plugin_Stop;
		}
		
		case 60, 120:
		{
			FlashTimer(timeRemaining);
		}
	}
	
	return Plugin_Continue;
}

public Action Timer_EndGame(Handle timer)
{
	int entity = CreateEntityByName("game_end", -1);
	
	if (entity != -1)
	{
		AcceptEntityInput(entity, "EndGame");
	}
	else
	{
		LogError("Unable to create entity: \"game_end\" !");
	}
	return Plugin_Continue;
}

public Action Timer_RestartRound(Handle timer, int data)
{
	/* When fired by the first-real-player join path, `data` carries that player's
	 * userid so we can force them onto Allies and exclude them from the zombie
	 * draw. From every other call site `data` is 0 (a normal restart). */
	int forcedHuman = data ? GetClientOfUserId(data) : 0;
	
	if (g_ConVarInts[ConVar_MinPlayers] <= GetTeamClientCount(Team_Allies) + GetTeamClientCount(Team_Axis))
	{
		g_iLastHuman = g_iBeaconTicks = g_bBlockChangeClass = false;
		
		g_bModActive = true;
		
		// Start teleport delay timer now that mod is active
		ZombieClasses_OnModActive();
		
		SelectZombie(forcedHuman > 0 ? forcedHuman : -1);
		
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && !IsClientSourceTV(i))
			{
				RemoveScreenOverlay(i);
				
				if (i != g_iZombie && GetClientTeam(i) > Team_Spectator)
				{
					// This prevents the players from committing suicide
					SetPlayerState(i, PlayerState_ObserverMode);
					
					ChangeClientTeam(i, Team_Allies);
				}
			}
		}
		
		/* Guarantee the first joining human lands on Allies and is never the
		 * zombie. The loop above already moves playable-team non-zombies to
		 * Allies, but this is explicit so the outcome never depends on the
		 * player's transient team state when the timer fires. */
		if (forcedHuman > 0 && forcedHuman <= MaxClients
			&& IsClientInGame(forcedHuman)
			&& forcedHuman != g_iZombie
			&& GetClientTeam(forcedHuman) != Team_Allies)
		{
			SetPlayerState(forcedHuman, PlayerState_ObserverMode);
			ChangeClientTeam(forcedHuman, Team_Allies);
		}
		
		/* Guard against SelectZombie failure (no eligible clients).
		 * Without this check, GetClientTeam(-1) and subsequent calls
		 * would error with an invalid client index. */
		if (g_iZombie > 0 && g_iZombie <= MaxClients
			&& IsClientInGame(g_iZombie)
			&& GetClientTeam(g_iZombie) != Team_Axis)
		{
			SetPlayerState(g_iZombie, PlayerState_ObserverMode);
			ChangeClientTeam(g_iZombie, Team_Axis);
		}
	}
	else
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && !IsClientSourceTV(i))
			{
				RemoveScreenOverlay(i);
			}
		}
		
		if (g_hRoundTimer != null)
		{
			KillTimer(g_hRoundTimer);
			
			g_hRoundTimer = null;
		}
		
		int entity = FindEntityByClassname(-1, "dod_round_timer");
		
		// Round-timers are preserved on round restarts, and therefore it needs to get removed when the mod is inactive.
		if (entity != -1)
		{
			AcceptEntityInput(entity, "Kill");
		}
		
		g_bModActive = false;
	}
	
	g_bRoundEnded = false;
	
	SetRoundState(DoDRoundState_Restart);
	return Plugin_Continue;
}
