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
// DEPRECATED WRAPPER FUNCTIONS (v0.7.52)
// ============================================================================
// These wrapper functions have been removed in favor of direct PrintToChat
// calls with translation support. Kept here commented for reference.
//
// void ZM_PrintToChat(int client, const char[] format, any ...)
// {
//     char buffer[192];
//     VFormat(buffer, sizeof(buffer), format, 3);
//     
//     PrintToChat(client, ZM_PRINT_FORMAT, buffer);
// }
// 
// void ZM_PrintToChatAll(const char[] format, any ...)
// {
//     char buffer[192];
//     VFormat(buffer, sizeof(buffer), format, 2);
//     
//     for (int i = 1; i <= MaxClients; i++)
//     {
//         if (IsClientInGame(i))
//         {
//             PrintToChat(i, ZM_PRINT_FORMAT, buffer);
//         }
//     }
// }
// ============================================================================

// ============================================================================
// PHASE 2: SPAWN PROTECTION - Changed from distance to time-based
// ============================================================================
// OLD: Zombies protected within 400 units of spawn (problematic on small maps)
// NEW: Zombies protected for configurable seconds after spawning (default 10s)
// ConVar: dod_zombiemod_zombie_spawn_protect_time
// ============================================================================

void ScreenOverlay(int client, const char[] material)
{
	ClientCommand(client, "r_screenoverlay \"%s\"", material);
}

void RemoveScreenOverlay(int client)
{
	ClientCommand(client, "r_screenoverlay 0");
}

void RemoveWeapons(int client)
{
	for (int i = 0; i < Slot_Size; i++)
	{
		int weapon = GetPlayerWeaponSlot(client, i);
		
		if (weapon != INVALID_WEAPON)
		{
			RemovePlayerItem(client, weapon);
			AcceptEntityInput(weapon, "Kill");
		}
	}
}

void FlashTimer(int timeRemaining)
{
	Event event = CreateEvent("dod_timer_flash", true);
	
	if (event != null)
	{
		event.SetInt("time_remaining", timeRemaining);
		event.Fire();
	}
}

int GetPlayerPistol(int client)
{
	int weapon = GetPlayerWeaponSlot(client, Slot_Secondary);
	
	if (weapon != INVALID_WEAPON)
	{
		char className[MAX_WEAPON_LENGTH];
		GetEdictClassname(weapon, className, sizeof(className));
		
		if (StrEqual(className[7], "colt"))
		{
			return Pistol_Colt;
		}
		
		if (StrEqual(className[7], "p38"))
		{
			return Pistol_P38;
		}
	}
	
	return Pistol_Invalid;
}

void PlaySoundFromPlayer(int client, const char[] sample)
{
	float vecPosition[3];
	GetClientEyePosition(client, vecPosition);
	
	EmitAmbientSound(sample, vecPosition, client, SNDLEVEL_SCREAMING);
}

void AddPlayerKills(int client, int amount)
{
	static int fragOffset;
	
	if ((fragOffset = FindDataMapInfo(client, "m_iFrags")) == -1)
	{
		LogError("Unable to find datamap offset: \"m_iFrags\" !");
		
		return;
	}
	
	SetEntData(client, fragOffset, GetEntData(client, fragOffset) + amount, _, true);
}

int GetHumanCount()
{
	int numHumans;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsClientSourceTV(i) && GetClientTeam(i) == Team_Allies)
		{
			numHumans++;
		}
	}
	
	return numHumans;
}

void SelectZombie()
{
	Handle clientArray = CreateArray();
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (i != g_iZombie && IsClientInGame(i) && !IsClientSourceTV(i) && GetClientTeam(i) > Team_Spectator)
		{
			PushArrayCell(clientArray, i);
		}
	}
	
	int arraySize = GetArraySize(clientArray);
	
	if (arraySize)
	{
		g_iZombie = GetArrayCell(clientArray, arraySize >= 2 ? GetURandomInt() % (arraySize - 1) : 0);
	}
	else
	{
		LogError("Failed to select zombie");
	}
	
	CloseHandle(clientArray);
}

/**
 * Counts the number of real (non-bot, non-SourceTV) players on the server
 * 
 * @return              Number of real players
 */
int GetRealPlayerCount()
{
	int count = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && !IsClientSourceTV(i))
		{
			count++;
		}
	}
	return count;
}
