/**
 * =============================================================================
 * Zombie Mod for Day of Defeat Source - Global Variables
 *
 * Shared state accessed by multiple modules. Declared here to ensure
 * consistent include order. See consts.inc for enums and defines.
 * =============================================================================
 */

// ============================================================================
// Round / Mod State
// ============================================================================

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

// ============================================================================
// Client Info
// Per-client state split by type to allow typed array storage.
// ============================================================================

/* Client Info enums - separated by type for proper storage */
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

int g_ClientInfo_Int[DOD_MAXPLAYERS + 1][ClientInfo_Int];
bool g_ClientInfo_Bool[DOD_MAXPLAYERS + 1][ClientInfo_Bool];
float g_flPlayerSpawnTime[DOD_MAXPLAYERS + 1];  /* Spawn time used by OnShouldCollide no-clip window */
float g_ClientInfo_Float[DOD_MAXPLAYERS + 1][ClientInfo_Float];

// ============================================================================
// ConVar Storage
// Cached at load time by convars.inc; read by all modules.
// ============================================================================

Handle g_ConVarHandles[ConVar_Size];
int g_ConVarInts[ConVar_Size];
bool g_ConVarBools[ConVar_Size];
float g_ConVarFloats[ConVar_Size];

// ============================================================================
// Zombie Classes
// Class enum and per-client tracking. See zombie_classes_core.inc for behaviour.
// ============================================================================

/**
 * ZombieClass - used by zombie_classes_core.inc, player.inc, hud_messages.inc.
 */
enum ZombieClass
{
	ZombieClass_Normal = 0,
	ZombieClass_Gas,
	ZombieClass_TNT,
	ZombieClass_Ghost
}

int g_iZombieClass[MAXPLAYERS+1];

// ============================================================================
// Human Skills (Built-in)
// Legacy built-in skill system. ESP is the only remaining built-in skill.
// External skills use human_skills_modular.inc / api.inc instead.
// ============================================================================

/**
 * HumanSkill - used by equipmenu.inc, human_skills_core.inc, hud_messages.inc.
 */
enum HumanSkill
{
	HumanSkill_None = 0,
	HumanSkill_ESP
}

int g_iHumanSkill[MAXPLAYERS+1];
Menu g_HumanSkillMenu = null;

// ============================================================================
// Input / Ability Tracking
// Per-frame state used in OnPlayerRunCmd.
// ============================================================================

int g_iLastButtons[MAXPLAYERS+1];           /* Previous frame buttons for edge detection */
float g_fESPIdentifyCooldown[MAXPLAYERS+1]; /* Per-client ESP ability cooldown */
float g_flEquipMenuExpiry[MAXPLAYERS+1];    /* GameTime when equip menu window closes */

// ============================================================================
// Forward Handles
// Declared here so api.inc and human_skills_modular.inc can both reference them.
// ============================================================================

Handle g_Forward_OnSkillAssigned = null;
Handle g_Forward_OnRoundStart    = null;
Handle g_Forward_OnRoundEnd      = null;
Handle g_Forward_OnClientDeath   = null;
Handle g_Forward_OnClientSpawn   = null;
Handle g_Forward_OnZombieDeath   = null;
