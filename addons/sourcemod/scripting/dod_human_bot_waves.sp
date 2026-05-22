/**
 * =============================================================================
 * DoD:S - Human Bot Wave Spawner
 *
 * Prevents allied human bots from getting stuck inside each other on spawn
 * by freezing all but the first bot, then unfreezing them one at a time
 * in configurable waves.
 * =============================================================================
 */

#include <sourcemod>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0.3"

public Plugin myinfo =
{
	name        = "DoD:S - Human Bot Wave Spawner",
	author      = "claude.ai guided by DNA.styx",
	description = "Staggers allied human bot spawns to prevent noclip overlap",
	version     = PLUGIN_VERSION,
	url         = "https://github.com/DNA-styx/DoD_ZombieMod"
};

// ---- ConVars ----------------------------------------------------------------

ConVar g_cvWaveInterval;

// ---- State ------------------------------------------------------------------

/**
 * Queue of client userids waiting to be unfrozen.
 * Populated as bots spawn after the first one.
 */
ArrayList g_PendingQueue;

/**
 * Repeating timer handle — non-null while a wave is in progress.
 * Fires every zm_bot_wave_interval seconds to unfreeze the next queued bot.
 */
Handle g_WaveTimer = null;

// ---- Plugin Init ------------------------------------------------------------

public void OnPluginStart()
{
	g_PendingQueue = new ArrayList();

	g_cvWaveInterval = CreateConVar(
		"zm_bot_wave_interval",
		"0.5",
		"Time in seconds between each bot unfreeze wave.",
		FCVAR_NONE,
		true, 0.1,
		true, 10.0
	);

	AutoExecConfig(true, "dod_human_bot_waves");

	HookEvent("dod_round_active", Event_RoundActive);
	HookEvent("dod_round_win",    Event_RoundEnd);
}

// ---- Events -----------------------------------------------------------------

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	// Unfreeze any bots still waiting so they aren't stuck during end-of-round
	ResetWaveState(true);
}

/**
 * Fires when the engine's own spawn freeze lifts. At this point all players
 * are alive and unfrozen by the engine, so it is safe to apply FL_FROZEN.
 * Iterate all alive allied bots — let the first one go, freeze the rest.
 */
public void Event_RoundActive(Event event, const char[] name, bool dontBroadcast)
{
	bool firstPassed = false;

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client))
			continue;

		if (!IsPlayerAlive(client))
			continue;

		if (!IsFakeClient(client))
			continue;

		// Allies team only (team 2 in DoD:S)
		if (GetClientTeam(client) != 2)
			continue;

		if (!firstPassed)
		{
			// Let the first bot move freely
			firstPassed = true;
			continue;
		}

		// Freeze and queue all others
		SetClientFrozen(client, true);
		g_PendingQueue.Push(GetClientUserId(client));
	}

	// Only start the timer if there is something to release
	if (g_PendingQueue.Length > 0)
	{
		float interval = g_cvWaveInterval.FloatValue;
		g_WaveTimer = CreateTimer(
			interval,
			Timer_WaveUnfreeze,
			_,
			TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE
		);
	}
}

// ---- Timer ------------------------------------------------------------------

/**
 * Fires every zm_bot_wave_interval seconds.
 * Pops the front of the queue and unfreezes that bot.
 * Stops and resets state when the queue is empty.
 */
public Action Timer_WaveUnfreeze(Handle timer)
{
	if (g_PendingQueue.Length == 0)
	{
		g_WaveTimer = null;
		return Plugin_Stop;
	}

	int userId = g_PendingQueue.Get(0);
	g_PendingQueue.Erase(0);

	int client = GetClientOfUserId(userId);
	if (client && IsClientInGame(client) && IsPlayerAlive(client))
		SetClientFrozen(client, false);

	return Plugin_Continue;
}

// ---- Helpers ----------------------------------------------------------------

/**
 * Freeze or unfreeze a client using the FL_FROZEN entity flag.
 *
 * @param client    Client index
 * @param freeze    True to freeze, false to unfreeze
 */
void SetClientFrozen(int client, bool freeze)
{
	int flags = GetEntityFlags(client);

	if (freeze)
		SetEntityFlags(client, flags | FL_FROZEN);
	else
		SetEntityFlags(client, flags & ~FL_FROZEN);
}

/**
 * Clear the pending queue and kill the wave timer.
 *
 * @param unfreezeAll   If true, unfreeze every client still in the queue
 *                      before clearing (use on round end).
 *                      If false, just discard queue entries without unfreezing.
 */
void ResetWaveState(bool unfreezeAll)
{
	if (unfreezeAll)
	{
		for (int i = 0; i < g_PendingQueue.Length; i++)
		{
			int userId = g_PendingQueue.Get(i);
			int client = GetClientOfUserId(userId);

			if (client && IsClientInGame(client))
				SetClientFrozen(client, false);
		}
	}

	g_PendingQueue.Clear();

	if (g_WaveTimer != null)
	{
		KillTimer(g_WaveTimer);
		g_WaveTimer = null;
	}
}
