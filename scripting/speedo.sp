#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <regex>
#include <smlib/math>
#include <clientprefs>

enum (<<= 1) {
	HORIZONTAL = 1,
	VERTICAL,
	ABSOLUTE
}

enum {
	RED,
	GREEN,
	BLUE
}

#define PLUGIN_VERSION "0.2.3"

#define ALL (HORIZONTAL|VERTICAL|ABSOLUTE)
#define DISABLED 0
#define XPOS 0
#define YPOS 1
#define XLOWER 0.0
#define XUPPER 0.90
#define YLOWER 0.0
#define YUPPER 1.0
#define XDEFAULT 0.47
#define YDEFAULT 0.67
#define FRAMELIMIT 3
#define HOLDTIME 5.0

Menu g_Menu;
Handle g_hCookieSpeedoEnabled;
Handle g_hCookieSpeedoFlags;
Handle g_hCookieSpeedoColor;
Handle g_hCookieSpeedoPos;
Handle g_hSpeedOMeter;
Regex g_hRegexHex;
int g_iColor[MAXPLAYERS+1][3];
int g_iDefaultColor[] = {255, 255, 255};
int g_iFlags[MAXPLAYERS+1];
int g_iLastFrame[MAXPLAYERS+1];
bool g_bEnabled[MAXPLAYERS+1];
bool g_bEditing[MAXPLAYERS+1];
bool g_bLateLoad;
float g_fPos[MAXPLAYERS+1][2];

public Plugin myinfo = {
	name = "Speedometer",
	author = "JoinedSenses",
	description = "Speedometer",
	version = PLUGIN_VERSION,
	url = "http://github.com/JoinedSenses"
};

// ------------------- SM API

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	g_bLateLoad = late;
	return APLRes_Success;
}

public void OnPluginStart() {
	CreateConVar("sm_speedo_version", PLUGIN_VERSION, "Speedometer Version", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY).SetString(PLUGIN_VERSION);

	RegConsoleCmd("sm_speedo", cmdSpeedo);
	RegConsoleCmd("sm_speedocolor", cmdColor);
	RegConsoleCmd("sm_speedopos", cmdPos);

	g_hSpeedOMeter = CreateHudSynchronizer();

	BuildMenu();
	for (int i = 0; i <= MaxClients; i++) {
		SetDefaults(i);		
	}

	g_hRegexHex = new Regex("([A-Fa-f0-9]{6})");

	g_hCookieSpeedoEnabled = RegClientCookie("Speedo_Enable", "Speedo enable cookie", CookieAccess_Private);
	g_hCookieSpeedoFlags = RegClientCookie("Speedo_Flags", "Speedo flag cookie", CookieAccess_Private);
	g_hCookieSpeedoColor = RegClientCookie("Speedo_Color", "Speedo color cookie", CookieAccess_Private);
	g_hCookieSpeedoPos = RegClientCookie("Speedo_Position", "Speedo position cookie", CookieAccess_Private);

	if (g_bLateLoad) {
		for (int i = 1; i <= MaxClients; i++) {
			if (IsValidClient(i) && AreClientCookiesCached(i)) {
				OnClientCookiesCached(i);
			}
		}
	}
}

public void OnClientConnected(int client) {
	SetDefaults(client);
}

public void OnClientCookiesCached(int client) {
	GetCookieEnabled(client);
	GetCookieFlags(client);
	GetCookieColor(client);
	GetCookiePosition(client);
}





public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2]) {
	if (!IsValidClient(client)) {
		return Plugin_Continue;
	}

	bool isEditing = g_bEditing[client];
	int tick = GetGameTickCount();
	if ((isEditing || (g_bEnabled[client] && (tick - g_iLastFrame[client]) > FRAMELIMIT)) && !(buttons & IN_SCORE)) {
		if (isEditing) {
			g_fPos[client][XPOS] = Math_Clamp(g_fPos[client][XPOS] + 0.0005 * mouse[0], XLOWER, XUPPER);
			g_fPos[client][YPOS] = Math_Clamp(g_fPos[client][YPOS] + 0.0005 * mouse[1], YLOWER, YUPPER);

			if (buttons & (IN_ATTACK|IN_ATTACK2)) {
				g_bEditing[client] = false;
				SetPosCookie(client, g_fPos[client]);

				CreateTimer(0.2, timerUnfreeze, client);
			}
			else if (buttons & (IN_ATTACK3|IN_JUMP)) {
				g_fPos[client][XPOS] = XDEFAULT;
				g_fPos[client][YPOS] = YDEFAULT;
				
				g_bEditing[client] = false;
				SetPosCookie(client, g_fPos[client]);
				CreateTimer(0.2, timerUnfreeze, client);
			}
		}

		char horizontal[24];
		char vertical[24];
		char absolute[24];

		int flags = isEditing ? ALL : GetClientFlags(client);
		if (flags & HORIZONTAL) {
			Format(horizontal, sizeof(horizontal), "H: %04.0f u/s\n", CalcVelocity(client, HORIZONTAL));
		}
		if (flags & VERTICAL) {
			Format(vertical, sizeof(vertical), "V: %04.0f u/s\n", CalcVelocity(client, VERTICAL));
		}
		if (flags & ABSOLUTE) {
			Format(absolute, sizeof(absolute), "A: %04.0f u/s", CalcVelocity(client, ABSOLUTE));
		}

		char text[128];
		Format(text, sizeof(text), "%s%s%s", horizontal, vertical, absolute);

		SetHudTextParams(g_fPos[client][XPOS], g_fPos[client][YPOS], HOLDTIME, g_iColor[client][RED], g_iColor[client][GREEN], g_iColor[client][BLUE], 255, .fadeIn=0.0, .fadeOut=0.0);
		ShowSyncHudText(client, g_hSpeedOMeter, text);

		g_iLastFrame[client] = tick;
	}
	return Plugin_Continue;
}

// ------------------- Commands

public Action cmdSpeedo(int client, int args) {
	if (!client) {
		return Plugin_Handled;
	}

	if (!args) {
		displayMenu(client);
		return Plugin_Handled;
	}

	char mode[32];
	GetCmdArg(1, mode, sizeof(mode));

	if (strlen(mode) > 1) {
		PrintToChat(client, "\x01[\x03Speedo\x01] Invalid parameter. Parameters: \x03h\x01, \x03v\x01, \x03a\x01, \x03d");
		return Plugin_Handled;
	}

	int flag;
	switch (mode[0]) {
		case 'h', 'H': {
			flag = HORIZONTAL;
		}
		case 'v', 'V': {
			flag = VERTICAL;
		}
		case 'a', 'A': {
			flag = ABSOLUTE;
		}
		case 'd', 'D': {
			flag = ALL;
		}
		default: {
			PrintToChat(client, "\x01[\x03Speedo\x01] Invalid parameter. Parameters: \x03h\x01, \x03v\x01, \x03a\x01, \x03d");
			return Plugin_Handled;
		}
	}
	int flags = SetClientFlag(client, flag);
	SetEnableCookie(client, (g_bEnabled[client] = !!flags));
	SetFlagsCookie(client, flags);

	return Plugin_Handled;
}

public Action cmdColor(int client, int args) {
	if (!client) {
		return Plugin_Handled;
	}

	if (!args) {
		g_iColor[client] = g_iDefaultColor;
		char hex[7];
		RGBToHexStr(g_iColor[client], hex, sizeof(hex));
		SetColorCookie(client, hex);
		PrintToChat(client, "\x01[\x03Speedo\x01] Color reset. Use /speedo <hexvalue> to change.");
		return Plugin_Handled;
	}

	char hex[7];
	GetCmdArg(1, hex, sizeof(hex));

	if (!IsValidHex(hex)) {
		PrintToChat(client, "\x01[\x03Speedo\x01] Invalid hex value");
		return Plugin_Handled;
	}

	HexStrToRGB(hex, g_iColor[client]);
	SetColorCookie(client, hex);
	return Plugin_Handled;
}

public Action cmdPos(int client, int args) {
	if (!client) {
		return Plugin_Handled;
	}

	if (args == 2) {
		char xpos[6];
		GetCmdArg(1, xpos, sizeof(xpos));
		float x = StringToFloat(xpos);
		if (x < XLOWER || x > XUPPER) {
			PrintToChat(client, "\x01[\x03Speedo\x01] X pos [%0.2f] out of bounds: Range (%0.2f, %0.2f)", x, YLOWER, YUPPER);
			return Plugin_Handled;
		}

		char ypos[6];
		GetCmdArg(2, ypos, sizeof(ypos));
		float y = StringToFloat(ypos);
		if (y < YLOWER || y > YUPPER) {
			PrintToChat(client, "\x01[\x03Speedo\x01] Y pos [%0.2f] out of bounds: Range (%0.2f, %0.2f)", y, YLOWER, YUPPER);
			return Plugin_Handled;	
		}

		g_fPos[client][XPOS] = x;
		g_fPos[client][YPOS] = y;
		SetPosCookie(client, g_fPos[client]);
		PrintToChat(client, "Position updated to (%0.2f, %0.2f)", x, y);
		return Plugin_Handled;
	}

	if (IsClientObserver(client)) {
		PrintToChat(client, "\x01[\x03Speedo\x01] Cannot use mouse position feature while in spectate");
		return Plugin_Handled;
	}

	switch (g_bEditing[client]) {
		case true: {
			g_bEditing[client] = false;
			SetEntityFlags(client, GetEntityFlags(client)&~(FL_ATCONTROLS|FL_FROZEN));
		}
		case false: {
			g_bEditing[client] = true;
			SetEntityFlags(client, GetEntityFlags(client)|FL_ATCONTROLS|FL_FROZEN);
			PrintToChat(
				client, "\x01"
			...	"[\x03Speedo\x01] Update position using\x03 mouse movement\x01.\n"
			... "[\x03Speedo\x01] Save with \x03attack\x01.\n"
			... "[\x03Speedo\x01] Reset with \x03jump\x01."
			);
		}
	}
	return Plugin_Handled;
}

// ------------------- Menu

void BuildMenu() {
	g_Menu = new Menu(menuHandler_Speedo, MENU_ACTIONS_DEFAULT|MenuAction_DisplayItem|MenuAction_DrawItem);
	g_Menu.SetTitle("Speedometer Type");

	g_Menu.AddItem("1", "Horizontal Speed");
	g_Menu.AddItem("2", "Vertical Speed");
	g_Menu.AddItem("4", "Absolute Speed");
	g_Menu.AddItem("7", "Toggle All");
	g_Menu.AddItem("0", "Disable");
}

int menuHandler_Speedo(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select: {
			char choice[2];
			menu.GetItem(param2, choice, sizeof(choice));

			int flag = StringToInt(choice);
			int flags = SetClientFlag(param1, flag);
			SetEnableCookie(param1, (g_bEnabled[param1] = !!flags));
			SetFlagsCookie(param1, flags);
			menu.DisplayAt(param1, menu.Selection, MENU_TIME_FOREVER);
		}
		case MenuAction_DisplayItem: {
			char choice[2];
			char type[18];
			menu.GetItem(param2, choice, sizeof(choice), _, type, sizeof(type));

			char buffer[32];
			int flag = StringToInt(choice);
			int clientflags = GetClientFlags(param1);
			if (flag && (flag & clientflags) == flag) {
				Format(buffer, sizeof(buffer), "%s (Current)", type);
				return RedrawMenuItem(buffer);
			}
		}
		case MenuAction_DrawItem: {
			char choice[2];
			menu.GetItem(param2, choice, sizeof(choice));

			if (!StringToInt(choice) && !GetClientFlags(param1)) {
				return ITEMDRAW_DISABLED;
			}
		}
	}
	return 0;
}

// ------------------- Cookie Getters

void GetCookieEnabled(int client) {
	char sEnable[2];
	GetClientCookie(client, g_hCookieSpeedoEnabled, sEnable, sizeof(sEnable));
	g_bEnabled[client] = (sEnable[0] != '\0' && StringToInt(sEnable));
}

void GetCookieFlags(int client) {
	char sFlags[2];
	GetClientCookie(client, g_hCookieSpeedoFlags, sFlags, sizeof(sFlags));
	g_iFlags[client] = StringToInt(sFlags);
}


void GetCookieColor(int client) {
	char sColor[7];
	GetClientCookie(client, g_hCookieSpeedoColor, sColor, sizeof(sColor));
	if (sColor[0] != '\0') {
		HexStrToRGB(sColor, g_iColor[client]);
	}	
}

void GetCookiePosition(int client) {
	char sPos[10];
	GetClientCookie(client, g_hCookieSpeedoPos, sPos, sizeof(sPos));
	if (sPos[0] != '\0') {
		char buffer[2][5];
		ExplodeString(sPos, " ", buffer, sizeof(buffer), sizeof(buffer[]));
		g_fPos[client][XPOS] = StringToFloat(buffer[XPOS]);
		g_fPos[client][YPOS] = StringToFloat(buffer[YPOS]);
	}	
}

// ------------------- Cookie Setters

void SetEnableCookie(int client, bool enabled) {
	char sEnable[2];
	Format(sEnable, sizeof(sEnable), "%i", enabled);
	SetClientCookie(client, g_hCookieSpeedoEnabled, sEnable);
}

void SetFlagsCookie(int client, int flags) {
	char sFlags[2];
	Format(sFlags, sizeof(sFlags), "%i", flags);
	SetClientCookie(client, g_hCookieSpeedoFlags, sFlags);
}

void SetColorCookie(int client, const char[] hex) {
	SetClientCookie(client, g_hCookieSpeedoColor, hex);
	PrintToChat(client, "\x01[\x03Speedo\x01] \x07%06XHex color updated: %s", StringToInt(hex, 16), hex);
}

void SetPosCookie(int client, float pos[2]) {
	char posstr[10];
	Format(posstr, sizeof(posstr), "%0.2f %0.2f", pos[XPOS], pos[YPOS]);
	SetClientCookie(client, g_hCookieSpeedoPos, posstr);
	PrintToChat(client, "\x01[\x03Speedo\x01] Position saved (%0.2f, %0.2f)", pos[0], pos[1]);
}

// ------------------- Timer

Action timerUnfreeze(Handle timer, int client) {
	SetEntityFlags(client, GetEntityFlags(client) & ~(FL_ATCONTROLS|FL_FROZEN));
}

// ------------------- Internal Functions

bool IsValidClient(int client) {
	return (0 < client <= MaxClients && IsClientConnected(client) && IsClientInGame(client) && !IsFakeClient(client));
}

bool IsValidHex(const char[] hex) {
	return (strlen(hex) == 6 && g_hRegexHex.Match(hex));
}

void displayMenu(int client) {
	g_Menu.Display(client, MENU_TIME_FOREVER);
}

void SetDefaults(int client) {
	g_bEnabled[client] = false;
	g_iLastFrame[client] = 0;
	g_iColor[client] = g_iDefaultColor;
	g_fPos[client][XPOS] = XDEFAULT;
	g_fPos[client][YPOS] = YDEFAULT;
}

void HexStrToRGB(const char[] hex, int rgb[3]) {
	int hexInt = StringToInt(hex, 16);
	rgb[0] = ((hexInt >> 16) & 0xFF);
	rgb[1] = ((hexInt >> 8) & 0xFF);
	rgb[2] = ((hexInt >> 0) & 0xFF);
}

void RGBToHexStr(int rgb[3], char[] hexstr, int size) {
	int hex; 
	hex |= ((rgb[0] & 0xFF) << 16);
	hex |= ((rgb[1] & 0xFF) <<  8);
	hex |= ((rgb[2] & 0xFF) <<  0);

	Format(hexstr, size, "%06X", hex);
}

int GetClientFlags(int client) {
	return g_iFlags[client];
}

int SetClientFlag(int client, int flag) {
	if (flag) {
		if (g_iFlags[client] & flag) {
			g_iFlags[client] &= ~flag;
		}
		else {
			g_iFlags[client] |= flag;
		}		
	}
	else g_iFlags[client] = DISABLED;

	return g_iFlags[client];
}

float abs(float x) {
   return (x > 0) ? x : -x;
}

float CalcVelocity(int client, int type) {
	float currentVel[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", currentVel);
	switch (type) {
		case HORIZONTAL: {
			return SquareRoot((currentVel[0]*currentVel[0]) + (currentVel[1]*currentVel[1]));
		}
		case VERTICAL: {
			return abs(currentVel[2]);
		}
		case ABSOLUTE: {
			return SquareRoot((currentVel[0]*currentVel[0]) + (currentVel[1]*currentVel[1]) + (currentVel[2]*currentVel[2]));
		}
	}
	return -1.0;
}