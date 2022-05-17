#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <regex>
#include <clientprefs>
#include <jslib>

#define PLUGIN_VERSION "0.3.4"
#define PLUGIN_DESCRIPTION "Displays player velocity"

#define HORIZONTAL (1 << 0)
#define VERTICAL   (1 << 1)
#define ABSOLUTE   (1 << 2)

#define RED   0
#define GREEN 1
#define BLUE  2

#define ALL (HORIZONTAL|VERTICAL|ABSOLUTE)
#define DISABLED 0

#define X_POS 0
#define Y_POS 1

#define X_MIN 0.0
#define X_MAX 0.90

#define Y_MIN 0.0
#define Y_MAX 1.0

#define X_DEFAULT 0.47
#define Y_DEFAULT 0.67

#define HOLDTIME 0.1
#define COLOR_DEFAULT {255, 255, 255}

enum Axis: {
	Horizontal,
	Vertical,
	Absolute,
	AXIS_MAX
}

bool g_bLateLoad;

Menu g_Menu;

Cookie g_CookieEnabled;
Cookie g_CookieFlags;
Cookie g_CookieColor;
Cookie g_CookiePos;

Handle g_HudSync;

Regex g_hRegexHex;

bool g_bEnabled[MAXPLAYERS+1];
int g_iColor[MAXPLAYERS+1][3];
int g_iFlags[MAXPLAYERS+1];
bool g_bEditing[MAXPLAYERS+1];
float g_fPos[MAXPLAYERS+1][2];
bool g_bInScore[MAXPLAYERS+1];

float g_fLastSpeed[MAXPLAYERS+1][AXIS_MAX];
float g_fLastIncrease[MAXPLAYERS+1][AXIS_MAX];

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
	g_hRegexHex = new Regex("([A-Fa-f0-9]{6})");

	g_CookieEnabled = new Cookie("Speedo_Enable", "Speedo enable cookie", CookieAccess_Private);
	g_CookieFlags = new Cookie("Speedo_Flags", "Speedo flag cookie", CookieAccess_Private);
	g_CookieColor = new Cookie("Speedo_Color", "Speedo color cookie", CookieAccess_Private);
	g_CookiePos = new Cookie("Speedo_Position", "Speedo position cookie", CookieAccess_Private);

	BuildMenu();

	for (int i = 1; i <= MaxClients; i++) {
		SetDefaults(i);
	}

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

public void OnGameFrame() {
	for (int client = 1; client <= MaxClients; ++client) {
		if (!IsClientInGame(client) || IsFakeClient(client)) {
			continue;
		}

		bool isEditing = g_bEditing[client];
		if ((isEditing || g_bEnabled[client]) && !g_bInScore[client]) {
			int flags = isEditing ? ALL : GetClientFlags(client);
			if (!flags) {
				g_bEnabled[client] = false;
				continue;
			}

			float velocity[3];
			GetEntPropVector(client, Prop_Data, "m_vecVelocity", velocity);

			char horizontal[32];
			if (flags & HORIZONTAL) {
				FormatInfo(horizontal, sizeof(horizontal), client, velocity, Horizontal, 'H');
			}
			
			char vertical[32];
			if (flags & VERTICAL) {
				FormatInfo(vertical, sizeof(vertical), client, velocity, Vertical, 'V');
			}
			
			char absolute[32];
			if (flags & ABSOLUTE) {
				FormatInfo(absolute, sizeof(absolute), client, velocity, Absolute, 'A');
			}

			char text[128];
			FormatEx(text, sizeof(text), "%s%s%s", horizontal, vertical, absolute);

			SetHudTextParams(
				g_fPos[client][X_POS],
				g_fPos[client][Y_POS],
				HOLDTIME,
				g_iColor[client][RED],
				g_iColor[client][GREEN],
				g_iColor[client][BLUE],
				255,
				.fadeIn = 0.0,
				.fadeOut = 0.0
			);

			ShowSyncHudText(client, g_HudSync, text);
		}
	}
}

void FormatInfo(char[] buffer, int size, int client, const float velocity[3], Axis axis, char prefix) {
	float speed = CalcSpeed(velocity, axis);
	float last = g_fLastSpeed[client][axis];
	if (speed > last) {
		g_fLastIncrease[client][axis] = speed;
	}

	FormatEx(buffer, size, "%c: %04.0f u/s %0.0f\n", prefix, AbsF(speed), g_fLastIncrease[client][axis]);
	g_fLastSpeed[client][axis] = speed;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon,
int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2]) {
	if (!IsValidClient(client)) {
		return Plugin_Continue;
	}

	g_bInScore[client] = (buttons & IN_SCORE) == IN_SCORE;

	if (g_bEditing[client]) {
		g_fPos[client][X_POS] = ClampF(g_fPos[client][X_POS] + 0.0005 * mouse[0], X_MIN, X_MAX);
		g_fPos[client][Y_POS] = ClampF(g_fPos[client][Y_POS] + 0.0005 * mouse[1], Y_MIN, Y_MAX);

		if (buttons & (IN_ATTACK|IN_ATTACK2)) {
			g_bEditing[client] = false;
			SetCookiePosition(client, g_fPos[client]);

			CreateTimer(0.2, timerUnfreeze, client);
		}
		else if (buttons & (IN_ATTACK3|IN_JUMP)) {
			g_fPos[client][X_POS] = X_DEFAULT;
			g_fPos[client][Y_POS] = Y_DEFAULT;
			
			g_bEditing[client] = false;
			SetCookiePosition(client, g_fPos[client]);
			CreateTimer(0.2, timerUnfreeze, client);
		}
	}

	return Plugin_Continue;
}

// ------------------- Commands

public Action cmdSpeedo(int client, int args) {
	if (!client) {
		return Plugin_Handled;
	}

	if (!args) {
		g_Menu.Display(client, MENU_TIME_FOREVER);
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
		g_iColor[client] = COLOR_DEFAULT;

		char hex[7];
		RGBToHex(g_iColor[client], hex, sizeof(hex));

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

	HexToRGB(hex, g_iColor[client]);
	SetCookieColor(client, hex);

	return Plugin_Handled;
}

public Action cmdPos(int client, int args) {
	if (!client) {
		return Plugin_Handled;
	}

	if (args == 2) {
		char _x[6];
		GetCmdArg(1, _x, sizeof(_x));

		float x = StringToFloat(_x);
		if (x < X_MIN || x > X_MAX) {
			PrintToChat(
				client,
				"\x01[\x03Speedo\x01] X pos [%0.2f] out of bounds: Range (%0.2f, %0.2f)",
				x, X_MIN, X_MAX
			);
			return Plugin_Handled;
		}

		char _y[6];
		GetCmdArg(2, _y, sizeof(_y));

		float y = StringToFloat(_y);
		if (y < Y_MIN || y > Y_MAX) {
			PrintToChat(
				client,
				"\x01[\x03Speedo\x01] Y pos [%0.2f] out of bounds: Range (%0.2f, %0.2f)",
				y, Y_MIN, Y_MAX
			);
			return Plugin_Handled;	
		}

		g_fPos[client][X_POS] = x;
		g_fPos[client][Y_POS] = y;
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

			int flag = StringToInt(choice);
			if (flag && (flag & GetClientFlags(param1)) == flag) {
				char buffer[32];
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
		HexToRGB(color, g_iColor[client]);
	}	
}

void GetCookiePosition(int client) {
	char position[10];
	g_CookiePos.Get(client, position, sizeof(position));

	if (position[0] != '\0') {
		char buffer[2][5];
		ExplodeString(position, " ", buffer, sizeof(buffer), sizeof(buffer[]));
		g_fPos[client][X_POS] = StringToFloat(buffer[X_POS]);
		g_fPos[client][Y_POS] = StringToFloat(buffer[Y_POS]);
	}	
}

// ------------------- Cookie Setters

void SetCookieEnable(int client, bool enabled) {
	g_CookieEnabled.Set(client, enabled ? "1" : "0");
}

void SetCookieFlags(int client, int flags) {
	char _flags[2];
	IntToString(flags, _flags, sizeof _flags);

	g_CookieFlags.Set(client, _flags);
}

void SetCookieColor(int client, const char[] hex) {
	g_CookieColor.Set(client, hex);
	PrintToChat(client, "\x01[\x03Speedo\x01] \x07%06XHex color updated: %s", StringToInt(hex, 16), hex);
}

void SetCookiePosition(int client, float pos[2]) {
	char _pos[10];
	FormatEx(_pos, sizeof(_pos), "%0.2f %0.2f", pos[X_POS], pos[Y_POS]);

	g_CookiePos.Set(client, _pos);

	PrintToChat(client, "\x01[\x03Speedo\x01] Position saved (%0.2f, %0.2f)", pos[0], pos[1]);
}

// ------------------- Timer

public Action timerUnfreeze(Handle timer, int client) {
	SetEntityFlags(client, GetEntityFlags(client) & ~(FL_ATCONTROLS|FL_FROZEN));
}

// ------------------- Normal Functions

bool IsValidClient(int client) {
	return (0 < client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client));
}

bool IsValidHex(const char[] hex) {
	return (strlen(hex) == 6 && g_hRegexHex.Match(hex));
}

void SetDefaults(int client) {
	g_bEnabled[client] = false;
	g_iColor[client] = COLOR_DEFAULT;
	g_fPos[client][X_POS] = X_DEFAULT;
	g_fPos[client][Y_POS] = Y_DEFAULT;
	g_fLastSpeed[client][Horizontal] = 0.0;
	g_fLastSpeed[client][Vertical] = 0.0;
	g_fLastSpeed[client][Absolute] = 0.0;
	g_fLastIncrease[client][Horizontal] = 0.0;
	g_fLastIncrease[client][Vertical] = 0.0;
	g_fLastIncrease[client][Absolute] = 0.0;
}

int GetClientFlags(int client) {
	return g_iFlags[client];
}

int SetClientFlag(int client, int flag) {
	if (flag) {
		g_iFlags[client] ^= flag;	
	}
	else {
		g_iFlags[client] = DISABLED;
	}

	return g_iFlags[client];
}

float CalcSpeed(const float velocity[3], Axis axis) {
	switch (axis) {
		case Horizontal: {
			float x = velocity[0];
			float y = velocity[1];
			return SquareRoot(x*x + y*y);
		}
		case Vertical: {
			return velocity[2];
		}
		case Absolute: {
			float x = velocity[0];
			float y = velocity[1];
			float z = velocity[2];
			return SquareRoot(x*x + y*y + z*z);
		}
	}

	return 0.0;
}
