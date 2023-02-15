#include <sourcemod>

#pragma semicolon 1
#pragma newdecls required

public void OnPluginStart()
{
	GameData gamedata = new GameData("testgamedata");

	delete gamedata;
}