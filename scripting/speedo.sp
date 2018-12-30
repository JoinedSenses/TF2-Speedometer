#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <regex>
#include <smlib/math>

#define PLUGIN_VERSION "0.1.0"

enum (<<= 1) {
	HORIZONTAL = 1,
	VERTICAL,
	ABSOLUTE
}

#define ALL (HORIZONTAL|VERTICAL|ABSOLUTE)
#define DISABLED 0

Menu g_Menu;
Handle g_hSpeedOMeter;
Regex g_hRegexHex;
int g_iFlags[MAXPLAYERS+1];
int g_iColor[MAXPLAYERS+1][3];
bool g_bEnabled[MAXPLAYERS+1];
int g_iDefaultColor[] = {163, 163, 163};

public Plugin myinfo = {
	name = "Speedometer",
	author = "JoinedSenses",
	description = "Speedometer",
	version = PLUGIN_VERSION,
	url = "http://github.com/JoinedSenses"
};

public void OnPluginStart() {
	CreateConVar("sm_speedo_version", PLUGIN_VERSION, "Speedometer Version", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY).SetString(PLUGIN_VERSION);

	RegConsoleCmd("sm_speedo", cmdSpeedo);
	RegConsoleCmd("sm_speedocolor", cmdColor);

	g_hSpeedOMeter = CreateHudSynchronizer();

	BuildMenu();
	for (int i = 0; i <= MaxClients; i++) {
		SetDefaultColor(i);		
	}

	g_hRegexHex = new Regex("([A-Fa-f0-9]{6})");
}

public void OnClientDisconnect(int client) {
	g_bEnabled[client] = false;
	SetDefaultColor(client);
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon){
	if (g_bEnabled[client]) {
		char horizontal[24];
		char vertical[24];
		char absolute[24];

		int flags = GetClientFlags(client);
		if (flags & HORIZONTAL) {
			Format(horizontal, sizeof(horizontal), "H: %0.0f u/s\n", CalcVelocity(client, HORIZONTAL));
		}
		if (flags & VERTICAL) {
			Format(vertical, sizeof(vertical), "V: %0.0f u/s\n", CalcVelocity(client, VERTICAL));
		}
		if (flags & ABSOLUTE) {
			Format(absolute, sizeof(absolute), "A: %0.0f u/s", CalcVelocity(client, ABSOLUTE));
		}
		char text[128];
		Format(text, sizeof(text), "%s%s%s", horizontal, vertical, absolute);

		SetHudTextParams(0.35, 0.67, 1.0, g_iColor[client][0], g_iColor[client][1], g_iColor[client][2], 255);
		ShowSyncHudText(client, g_hSpeedOMeter, text);
	}
}

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

	g_bEnabled[client] = !!SetClientFlag(client, flag);

	return Plugin_Handled;
}

public Action cmdColor(int client, int args) {
	if (!client) {
		return Plugin_Handled;
	}

	char hex[7];
	GetCmdArg(1, hex, sizeof(hex));

	if (!IsValidHex(hex)) {
		PrintToChat(client, "\x01[\x03Speedo\x01] Invalid hex value");
		return Plugin_Handled;
	}

	HexToRGB(hex, g_iColor[client]);
	PrintToChat(client, "\x01[\x03Speedo\x01] \x07%6XHex color updated", StringToInt(hex, 16));
	return Plugin_Handled;
}

void SetDefaultColor(int client) {
	g_iColor[client] = g_iDefaultColor;
}

void HexToRGB(const char[] hex, int rgb[3]) {
	int hexInt = StringToInt(hex, 16);
	rgb[0] = ((hexInt >> 16) & 0xFF);
	rgb[1] = ((hexInt >> 8) & 0xFF);
	rgb[2] = ((hexInt >> 0) & 0xFF);
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

int GetClientFlags(int client) {
	return g_iFlags[client];
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

float abs(float x) {
   return (x > 0) ? x : -x;
}

bool IsValidHex(const char[] hex) {
	return (strlen(hex) == 6 && g_hRegexHex.Match(hex));
}

void displayMenu(int client) {
	g_Menu.Display(client, MENU_TIME_FOREVER);
}

void BuildMenu() {
	g_Menu = new Menu(menuHandler_Speedo, MENU_ACTIONS_DEFAULT|MenuAction_DisplayItem|MenuAction_DrawItem);
	g_Menu.SetTitle("Speedometer Type");

	g_Menu.AddItem("1", "Horizontal Speed");
	g_Menu.AddItem("2", "Vertical Speed");
	g_Menu.AddItem("4", "Absolute Speed");
	g_Menu.AddItem("7", "All");
	g_Menu.AddItem("0", "Disable");
}

int menuHandler_Speedo(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select: {
			char choice[2];
			menu.GetItem(param2, choice, sizeof(choice));

			int flag = StringToInt(choice);

			g_bEnabled[param1] = !!SetClientFlag(param1, flag);
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