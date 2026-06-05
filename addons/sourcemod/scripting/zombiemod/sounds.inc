/**
 * =============================================================================
 * Zombie Mod for Day of Defeat Source - Ambient Sound Module
 *
 * Plays a looping ambient sound track during active ZM rounds.
 *
 * Sound path is read from zombiemod.cfg under the Sounds section:
 *   "Sound_Ambience"  "DoD_ZombieMod\zr_ambience.mp3"
 *
 * The sound file should be exactly 60 seconds long. A repeating one-shot
 * timer restarts it every 60 seconds to create a seamless loop.
 *
 * Ambience is suppressed per-map via zombiemod_whitelist.cfg:
 *   "Ambience" "1"  — suppress ZM track, leave map audio alone
 *   "Ambience" "0"  — play ZM track (default when key is absent)
 * =============================================================================
 */

/* Duration of the ambience track in seconds — must match the sound file */
#define AMBIENCE_DURATION 60.0

Handle g_hAmbienceTimer = null;

// ============================================================================
// PUBLIC INTERFACE
// ============================================================================

void Sounds_OnMapStart()
{
	/* Timer was auto-killed by TIMER_FLAG_NO_MAPCHANGE on map change.
	 * Null the handle so Sounds_StopAmbience doesn't try to KillTimer
	 * an already-dead handle on the next round start. */
	g_hAmbienceTimer = null;

	/* Precache ambience sound and add to downloads table if configured */
	if (g_szSounds[Sound_Ambience][0] != '\0')
	{
		char downloadPath[PLATFORM_MAX_PATH];
		Format(downloadPath, sizeof(downloadPath), "sound/%s", g_szSounds[Sound_Ambience]);
		AddFileToDownloadsTable(downloadPath);
		PrecacheSound(g_szSounds[Sound_Ambience]);
	}
}

void Sounds_OnRoundStart()
{
	/* Only play ambience when the mod is actually active */
	if (!g_bModActive)
		return;

	if (g_szSounds[Sound_Ambience][0] == '\0')
		return;

	/* Per-map override — Ambience "1" in whitelist means leave map audio alone */
	if (g_bWhiteListed[WhiteList_Ambience])
		return;

	Sounds_PlayAmbience();
}

void Sounds_OnRoundEnd()
{
	Sounds_StopAmbience();
}

void Sounds_OnClientConnect(int client)
{
	if (IsFakeClient(client))
		return;

	/* Only emit if ambience is actively looping */
	if (!g_bModActive || g_bRoundEnded || g_hAmbienceTimer == null)
		return;

	if (g_szSounds[Sound_Ambience][0] == '\0')
		return;

	EmitSoundToClient(client, g_szSounds[Sound_Ambience]);
}

// ============================================================================
// INTERNAL
// ============================================================================

void Sounds_PlayAmbience()
{
	/* Stop any existing timer before starting fresh */
	Sounds_StopAmbience();

	/* Play to all connected real clients */
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
			EmitSoundToClient(i, g_szSounds[Sound_Ambience]);
	}

	/* Schedule the next loop */
	g_hAmbienceTimer = CreateTimer(AMBIENCE_DURATION, Timer_AmbienceLoop, _, TIMER_FLAG_NO_MAPCHANGE);
}

void Sounds_StopAmbience()
{
	if (g_hAmbienceTimer != null)
	{
		KillTimer(g_hAmbienceTimer);
		g_hAmbienceTimer = null;
	}

	if (g_szSounds[Sound_Ambience][0] == '\0')
		return;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
			StopSound(i, SNDCHAN_AUTO, g_szSounds[Sound_Ambience]);
	}
}

public Action Timer_AmbienceLoop(Handle timer)
{
	g_hAmbienceTimer = null;

	/* Stop if the mod has gone inactive (round end, not enough players, etc.) */
	if (!g_bModActive)
		return Plugin_Stop;

	Sounds_PlayAmbience();
	return Plugin_Stop;
}
