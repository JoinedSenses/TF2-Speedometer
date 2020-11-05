#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <regex>
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

#define PLUGIN_VERSION "0.3.2"
#define PLUGIN_DESCRIPTION "Displays player velocity"

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
#define FRAMELIMIT 2
#define HOLDTIME 5.0

Menu g_Menu;

Cookie g_CookieEnabled;
Cookie g_CookieFlags;
Cookie g_CookieColor;
Cookie g_CookiePos;

Handle g_HudSync;

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
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = "http://github.com/JoinedSenses"
};

// ------------------- SM API

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	g_bLateLoad = late;
	return APLRes_Success;
}

public void OnPluginStart() {
	CreateConVar(
		"sm_speedo_version",
		PLUGIN_VERSION,
		PLUGIN_DESCRIPTION,
		FCVAR_SPONLY|FCVAR_NOTIFY|FCVAR_DONTRECORD
	).SetString(PLUGIN_VERSION);

	RegConsoleCmd("sm_speedo", cmdSpeedo);
	RegConsoleCmd("sm_speedocolor", cmdColor);
	RegConsoleCmd("sm_speedopos", cmdPos);

	g_HudSync = CreateHudSynchronizer();

	BuildMenu();
	for (int i = 0; i <= MaxClients; i++) {
		SetDefaults(i);
	}

	g_hRegexHex = new Regex("([A-Fa-f0-9]{6})");

	g_CookieEnabled = new Cookie("Speedo_Enable", "Speedo enable cookie", CookieAccess_Private);
	g_CookieFlags = new Cookie("Speedo_Flags", "Speedo flag cookie", CookieAccess_Private);
	g_CookieColor = new Cookie("Speedo_Color", "Speedo color cookie", CookieAccess_Private);
	g_CookiePos = new Cookie("Speedo_Position", "Speedo position cookie", CookieAccess_Private);

	if (g_bLateLoad) {
		for (int i = 1; i <= MaxClients; i++) {
			if (IsClientInGame(i) && !IsFakeClient(i) && AreClientCookiesCached(i)) {
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

float Clamp(float value, float min, float max) {
	if (value > max) {
		return max;
	}

	if (value < min) {
		return min;
	}

	return value;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon,
		int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2]) {
	if (!IsValidClient(client)) {
		return Plugin_Continue;
	}

	bool isEditing = g_bEditing[client];
	int tick = GetGameTickCount();
	if ((isEditing || (g_bEnabled[client] && (tick - g_iLastFrame[client]) > FRAMELIMIT)) && !(buttons & IN_SCORE)) {
		if (isEditing) {
			g_fPos[client][XPOS] = Clamp(g_fPos[client][XPOS] + 0.0005 * mouse[0], XLOWER, XUPPER);
			g_fPos[client][YPOS] = Clamp(g_fPos[client][YPOS] + 0.0005 * mouse[1], YLOWER, YUPPER);

			if (buttons & (IN_ATTACK|IN_ATTACK2)) {
				g_bEditing[client] = false;
				SetCookiePosition(client, g_fPos[client]);

				CreateTimer(0.2, timerUnfreeze, client);
			}
			else if (buttons & (IN_ATTACK3|IN_JUMP)) {
				g_fPos[client][XPOS] = XDEFAULT;
				g_fPos[client][YPOS] = YDEFAULT;
				
				g_bEditing[client] = false;
				SetCookiePosition(client, g_fPos[client]);
				CreateTimer(0.2, timerUnfreeze, client);
			}
		}

		char horizontal[24];
		char vertical[24];
		char absolute[24];

		int flags = isEditing ? ALL : GetClientFlags(client);
		if (flags & HORIZONTAL) {
			FormatEx(horizontal, sizeof(horizontal), "H: %04.0f u/s\n", CalcVelocity(client, HORIZONTAL));
		}
		if (flags & VERTICAL) {
			FormatEx(vertical, sizeof(vertical), "V: %04.0f u/s\n", CalcVelocity(client, VERTICAL));
		}
		if (flags & ABSOLUTE) {
			FormatEx(absolute, sizeof(absolute), "A: %04.0f u/s", CalcVelocity(client, ABSOLUTE));
		}

		char text[128];
		FormatEx(text, sizeof(text), "%s%s%s", horizontal, vertical, absolute);

		SetHudTextParams(
			g_fPos[client][XPOS],
			g_fPos[client][YPOS],
			HOLDTIME,
			g_iColor[client][RED],
			g_iColor[client][GREEN],
			g_iColor[client][BLUE],
			255,
			.fadeIn=0.0,
			.fadeOut=0.0
		);
		ShowSyncHudText(client, g_HudSync, text);

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

	char arg[32];
	GetCmdArgString(arg, sizeof(arg));

	char[][] mode = new char[args][3];
	ExplodeString(arg, " ", mode, args, 3);

	bool invalid = false;
	int flags;

	for (int i = 0; i < args; ++i) {
		if (mode[i][1] != '\0') {
			invalid = true;
			break;
		}

		switch (CharToLower(mode[i][0])) {
			case 'h': {
				flags |= HORIZONTAL;
			}
			case 'v': {
				flags |= VERTICAL;
			}
			case 'a': {
				flags |= ABSOLUTE;
			}
			case 't': {
				flags = flags ? 0 : ALL;
				break;
			}
			default: {
				invalid = true;
				break;
			}
		}
	}

	if (invalid) {
		PrintToChat(
			client,
			"\x01[\x03Speedo\x01] One or more invalid parameters. " ...
			"Parameters: \x03h\x01, \x03v\x01, \x03a\x01, \x03t"
		);
		return Plugin_Handled;
	}

	SetClientFlag(client, flags);
	SetCookieEnable(client, (g_bEnabled[client] = !!flags));
	SetCookieFlags(client, flags);

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

		SetCookieColor(client, hex);

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
	SetCookieColor(client, hex);

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
			PrintToChat(
				client,
				"\x01[\x03Speedo\x01] X pos [%0.2f] out of bounds: Range (%0.2f, %0.2f)",
				x, XLOWER, XUPPER
			);
			return Plugin_Handled;
		}

		char ypos[6];
		GetCmdArg(2, ypos, sizeof(ypos));

		float y = StringToFloat(ypos);
		if (y < YLOWER || y > YUPPER) {
			PrintToChat(
				client,
				"\x01[\x03Speedo\x01] Y pos [%0.2f] out of bounds: Range (%0.2f, %0.2f)",
				y, YLOWER, YUPPER
			);
			return Plugin_Handled;	
		}

		g_fPos[client][XPOS] = x;
		g_fPos[client][YPOS] = y;
		SetCookiePosition(client, g_fPos[client]);

		PrintToChat(client, "Position updated to (%0.2f, %0.2f)", x, y);

		return Plugin_Handled;
	}

	if (IsClientObserver(client)) {
		PrintToChat(client, "\x01[\x03Speedo\x01] Cannot use mouse position feature while in spectate");
		return Plugin_Handled;
	}

	if (g_bEditing[client]) {
		g_bEditing[client] = false;
		SetEntityFlags(client, GetEntityFlags(client)&~(FL_ATCONTROLS|FL_FROZEN));
	}
	else {
		g_bEditing[client] = true;
		SetEntityFlags(client, GetEntityFlags(client)|FL_ATCONTROLS|FL_FROZEN);
		PrintToChat(
			client,
			"\x01" ...
			"[\x03Speedo\x01] Update position using\x03 mouse movement\x01.\n" ...
			"[\x03Speedo\x01] Save with \x03attack\x01.\n" ...
			"[\x03Speedo\x01] Reset with \x03jump\x01."
		);
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
			SetCookieEnable(param1, (g_bEnabled[param1] = !!flags));
			SetCookieFlags(param1, flags);
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
				FormatEx(buffer, sizeof(buffer), "%s (Current)", type);
				return RedrawMenuItem(buffer);
			}
		}
		case MenuAction_DrawItem: {
			char choice[2];
			menu.GetItem(param2, choice, sizeof(choice));

			if (choice[0] == '0' && !GetClientFlags(param1)) {
				return ITEMDRAW_DISABLED;
			}
		}
	}

	return 0;
}

// ------------------- Cookie Getters

void GetCookieEnabled(int client) {
	char enable[2];
	g_CookieEnabled.Get(client, enable, sizeof(enable));
	g_bEnabled[client] = (enable[0] == '1');
}

void GetCookieFlags(int client) {
	char flags[2];
	g_CookieFlags.Get(client, flags, sizeof(flags));
	g_iFlags[client] = StringToInt(flags);
}

void GetCookieColor(int client) {
	char color[7];
	g_CookieColor.Get(client, color, sizeof(color));
	if (color[0] != '\0') {
		HexStrToRGB(color, g_iColor[client]);
	}	
}

void GetCookiePosition(int client) {
	char position[10];
	g_CookiePos.Get(client, position, sizeof(position));
	if (position[0] != '\0') {
		char buffer[2][5];
		ExplodeString(position, " ", buffer, sizeof(buffer), sizeof(buffer[]));
		g_fPos[client][XPOS] = StringToFloat(buffer[XPOS]);
		g_fPos[client][YPOS] = StringToFloat(buffer[YPOS]);
	}	
}

// ------------------- Cookie Setters

void SetCookieEnable(int client, bool enabled) {
	g_CookieEnabled.Set(client, enabled ? "1" : "0");
}

void SetCookieFlags(int client, int flags) {
	char sFlags[2];
	IntToString(flags, sFlags, sizeof sFlags);
	g_CookieFlags.Set(client, sFlags);
}

void SetCookieColor(int client, const char[] hex) {
	g_CookieColor.Set(client, hex);
	PrintToChat(client, "\x01[\x03Speedo\x01] \x07%06XHex color updated: %s", StringToInt(hex, 16), hex);
}

void SetCookiePosition(int client, float pos[2]) {
	char sPos[10];
	FormatEx(sPos, sizeof(sPos), "%0.2f %0.2f", pos[XPOS], pos[YPOS]);
	g_CookiePos.Set(client, sPos);
	PrintToChat(client, "\x01[\x03Speedo\x01] Position saved (%0.2f, %0.2f)", pos[0], pos[1]);
}

// ------------------- Timer

Action timerUnfreeze(Handle timer, int client) {
	SetEntityFlags(client, GetEntityFlags(client) & ~(FL_ATCONTROLS|FL_FROZEN));
}

// ------------------- Internal Functions

bool IsValidClient(int client) {
	return (0 < client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client));
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
	rgb[1] = ((hexInt >>  8) & 0xFF);
	rgb[2] = ((hexInt >>  0) & 0xFF);
}

void RGBToHexStr(int rgb[3], char[] hexstr, int size) {
	int hex; 
	hex |= ((rgb[0] & 0xFF) << 16);
	hex |= ((rgb[1] & 0xFF) <<  8);
	hex |= ((rgb[2] & 0xFF) <<  0);

	FormatEx(hexstr, size, "%06X", hex);
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
	else {
		g_iFlags[client] = DISABLED;
	}

	return g_iFlags[client];
}

float abs(float x) {
   return view_as<float>(view_as<int>(x) & ~(cellmin));
}

float CalcVelocity(int client, int type) {
	float currentVel[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", currentVel);

	switch (type) {
		case HORIZONTAL: {
			float x = currentVel[0];
			float y = currentVel[1];
			return SquareRoot(x*x + y*y);
		}
		case VERTICAL: {
			return abs(currentVel[2]);
		}
		case ABSOLUTE: {
			float x = currentVel[0];
			float y = currentVel[1];
			float z = currentVel[2];
			return SquareRoot(x*x + y*y + z*z);
		}
	}

	return -1.0;
}
