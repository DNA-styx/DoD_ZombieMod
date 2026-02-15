/**
 * =============================================================================
 * Zombie Mod for Day of Defeat Source - Phase 1.5
 */

bool g_bModActive;
#if defined _steamtools_included
bool g_bUseSteamTools;
#endif
bool g_bRoundEnded;
bool g_bBlockChangeClass;
int g_iZombie;
int g_iLastHuman;
int g_iRoundWins;
int g_iBeamSprite;
int g_iHaloSprite;
int g_iRoundTimer;
int g_iBeaconTicks;
int g_iNumZombieSpawns;
Handle g_hRoundTimer;
float g_vecZombieSpawnOrigin[MAX_SPAWNPOINTS][3];

// Client Info enums - separated by type for proper storage
enum ClientInfo_Int
{
	ClientInfo_KillsAsHuman,
	ClientInfo_KillsAsZombie,
	ClientInfo_Critter,
	ClientInfo_Pistol,
	ClientInfo_PrimaryWeapon,
	ClientInfo_EquipmentItem
}

enum ClientInfo_Bool
{
	ClientInfo_IsCritical,
	ClientInfo_SelectedClass,
	ClientInfo_HasCustomClass,
	ClientInfo_HasEquipped,
	ClientInfo_ShouldAutoEquip,
	ClientInfo_WeaponCanUse
}

enum ClientInfo_Float
{
	ClientInfo_DamageScale,
	ClientInfo_Health
}

// Properly typed storage arrays
int g_ClientInfo_Int[DOD_MAXPLAYERS + 1][ClientInfo_Int];
bool g_ClientInfo_Bool[DOD_MAXPLAYERS + 1][ClientInfo_Bool];
float g_flPlayerSpawnTime[DOD_MAXPLAYERS + 1];  // Track when players spawn for no-clip
float g_ClientInfo_Float[DOD_MAXPLAYERS + 1][ClientInfo_Float];
// Track zombie spawn time for spawn protection
// float g_flZombieSpawnTime[DOD_MAXPLAYERS + 1];  // UNUSED - Replaced by g_bSpawnProtected boolean flag in v0.7.101

// Spawn protection
bool g_bSpawnProtected[DOD_MAXPLAYERS + 1];

// ConVar storage arrays (needed by multiple files)
Handle g_ConVarHandles[ConVar_Size];
int g_ConVarInts[ConVar_Size];
bool g_ConVarBools[ConVar_Size];
float g_ConVarFloats[ConVar_Size];
