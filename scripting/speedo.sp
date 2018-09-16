#pragma semicolon 1
#include <sourcemod>
#include <smlib/math>
#pragma newdecls required
#define PLUGIN_VERSION "0.0.4"

enum SpeedoType {
	DISABLED,
	HORIZONTAL,
	VERTICAL,
	ABSOLUTE
}

Menu
	SpeedoMenu;
Handle
	SpeedOMeter;
SpeedoType
	speedotype[MAXPLAYERS+1];
bool
	speedo[MAXPLAYERS+1];

public Plugin myinfo = {
	name = "Speedometer",
	author = "CrancK",
	description = "Speedometer",
	version = PLUGIN_VERSION,
	url = ""
};

public void OnPluginStart(){
	RegConsoleCmd("sm_speedo", Command_Speedo);
	CreateConVar("sm_speedo_version", PLUGIN_VERSION, "Speedometer Version", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	SpeedOMeter = CreateHudSynchronizer();

	SpeedoMenu = new Menu(SpeedoMenu_Handler, MENU_ACTIONS_DEFAULT|MenuAction_DrawItem);
	SpeedoMenu.SetTitle("Speedometer Type");

	SpeedoMenu.AddItem("1", "Horizontal Speed");
	SpeedoMenu.AddItem("2", "Vertical Speed");
	SpeedoMenu.AddItem("3", "Absolute Speed");
	SpeedoMenu.AddItem("0", "Disable");
}

public void OnClientDisconnect(int client){
		speedo[client] = false;
}

public Action Command_Speedo(int client, int args) {
	if (client == 0) {
		return Plugin_Handled;
	}
	if (args == 0) {
		displayMenu(client);
		return Plugin_Handled;
	}
	char mode[32];
	GetCmdArg(1, mode, sizeof(mode));

	if (strlen(mode) > 1) {
		ReplyToCommand(client, "\x01[\x03Speedo\x01] Invalid parameter. Parameters: \x03h\x01, \x03v\x01, \x03a\x01, \x03d");
		return Plugin_Handled;
	}
	switch (mode[0]){
		case 'h','H': {
			speedotype[client] = HORIZONTAL;
			PrintToChat(client, "\x01[\x03Speedo\x01] \x03Horizontal Mode Enabled");			
		}
		case 'v','V': {
			speedotype[client] = VERTICAL;
			PrintToChat(client, "\x01[\x03Speedo\x01] \x03Vertical Mode Enabled");			
		}
		case 'a','A': {
			speedotype[client] = ABSOLUTE;
			PrintToChat(client, "\x01[\x03Speedo\x01] \x03Absolute Mode Enabled");			
		}
		case 'd','D': {
			if (speedo[client]) {
				speedo[client] = false;
				speedotype[client] = DISABLED;
				PrintToChat(client, "\x01[\x03Speedo\x01] \x03Disabled");
			}
			return Plugin_Handled;			
		}
		default: {
			PrintToChat(client, "\x01[\x03Speedo\x01] Unknown parameter");
			return Plugin_Handled;
		}
	}
	speedo[client] = true;
	
	return Plugin_Handled;
}

void displayMenu(int client) {
	SpeedoMenu.Display(client, MENU_TIME_FOREVER);
}

int SpeedoMenu_Handler(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select: {
			char choice[2];
			menu.GetItem(param2, choice, sizeof(choice));
			SpeedoType value = view_as<SpeedoType>(StringToInt(choice));
			PrintToChat(param1, "\x01[\x03Speedo\x01] \x03%s", (value == DISABLED) ? "Disabled" : !speedo[param1] ? "Enabled" : "Mode Changed");
			speedo[param1] = (value == DISABLED) ? false : true;
			speedotype[param1] = value;
			menu.DisplayAt(param1, GetMenuSelectionPosition(), MENU_TIME_FOREVER);
		}
		case MenuAction_DrawItem: {
			char item[2];
			menu.GetItem(param2, item, sizeof(item));
			SpeedoType value = view_as<SpeedoType>(StringToInt(item));
			if (speedotype[param1] == value) {
				return ITEMDRAW_DISABLED;
			}
			return ITEMDRAW_DEFAULT;
		}
	}
	return 0;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon){
	if (speedo[client]) {
		float currentVel[3], currentSpd;
		GetEntPropVector(client, Prop_Data, "m_vecVelocity", currentVel);
		switch (speedotype[client]) {
			case HORIZONTAL: {
				currentSpd = SquareRoot((currentVel[0]*currentVel[0]) + (currentVel[1]*currentVel[1]));
			}
			case VERTICAL: {
				currentSpd = abs(currentVel[2]);
			}
			case ABSOLUTE: {
				currentSpd = SquareRoot((currentVel[0]*currentVel[0]) + (currentVel[1]*currentVel[1]) + (currentVel[2]*currentVel[2]));
			}
		}
		SetHudTextParams(0.44, 0.67, 1.0, 255, 50, 50, 255);
		ShowSyncHudText(client, SpeedOMeter, "Speed: %.0f u/s", currentSpd);
	}
}

float abs(float x) {
   return (x > 0) ? x : -x;
}