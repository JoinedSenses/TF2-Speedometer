#pragma semicolon 1
#include <sourcemod>
#include <smlib>
#pragma newdecls required

#define PLUGIN_VERSION "0.0.2"

public Plugin myinfo = {
	name = "Speedometer",
	author = "CrancK",
	description = "Speedometer",
	version = PLUGIN_VERSION,
	url = ""
};

bool speedo[MAXPLAYERS];
Handle SpeedOMeter; 

public void OnPluginStart(){
	RegConsoleCmd("sm_speedo", Command_Speedo);
	CreateConVar("sm_speedo_version", PLUGIN_VERSION, "Speedometer Version", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	SpeedOMeter = CreateHudSynchronizer();
}

public void OnClientDisconnect(int client){
		speedo[client] = false;
}

public Action Command_Speedo(int client, int args){
	speedo[client] = !speedo[client];
	if (speedo[client])
		ReplyToCommand(client, "Speedo ON");
	else
		ReplyToCommand(client, "Speedo OFF");
	return Plugin_Handled;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon){
	if (IsValidEntity(client) && speedo[client]){
		float currentVel[3], currentSpd;
		GetEntPropVector(client, Prop_Data, "m_vecVelocity", currentVel);
		currentSpd = SquareRoot((currentVel[0]*currentVel[0]) + (currentVel[1]*currentVel[1]));
		SetHudTextParams(0.44, 0.67, 1.0, 255, 50, 50, 255);
		ShowSyncHudText(client, SpeedOMeter, "Speed: %.0f u/s", currentSpd);
	}
}