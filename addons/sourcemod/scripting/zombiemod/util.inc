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
// MESSAGE HELPER FUNCTIONS
// ============================================================================

// Message prefix for personal messages (olive/yellow)
#define ZM_PREFIX_PERSONAL "\x04[ZM]\x01"

// Message prefix for broadcast messages (green)
#define ZM_PREFIX_BROADCAST "\x04[ZM]\x01"

/* Send a personal message to one client with the standard [ZM] prefix */
void ZM_PrintToChat(int client, const char[] format, any ...)
{
	char buffer[256];
	VFormat(buffer, sizeof(buffer), format, 3);
	PrintToChat(client, "\x04[ZM]\x01 %s", buffer);
}

/* Broadcast a message to all clients with the standard [ZM] prefix */
void ZM_PrintToChatAll(const char[] format, any ...)
{
	char buffer[256];
	VFormat(buffer, sizeof(buffer), format, 2);
	PrintToChatAll("\x04[ZM]\x01 %s", buffer);
}

// ============================================================================
// UTILITY FUNCTIONS
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
	/* `static` was previously used here but the lookup re-runs every call,
	 * so the modifier had no effect. Removed for clarity. */
	int fragOffset = FindDataMapInfo(client, "m_iFrags");
	
	if (fragOffset == -1)
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
		/* Pick uniformly across the full range. Previous formula used
		 * `% (arraySize - 1)` which excluded the last array entry. */
		g_iZombie = GetArrayCell(clientArray, GetURandomInt() % arraySize);
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
