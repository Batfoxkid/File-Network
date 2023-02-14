#include <sourcemod>
#include <sdktools>
#include <dhooks>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION			"1.0"
#define PLUGIN_VERSION_REVISION	"manual"
#define PLUGIN_VERSION_FULL		PLUGIN_VERSION ... "." ... PLUGIN_VERSION_REVISION

Handle SDKGetPlayerNetInfo;
Handle SDKSendFile;
Handle SDKIsFileInWaitingList;
int TransferID;

methodmap CNetChan
{
	public CNetChan(int client)
	{
		return SDKCall(SDKGetPlayerNetInfo, client);
	}

	public bool SendFile(const char[] filename)
	{
		return SDKCall(SDKSendFile, this, filename, TransferID++);
	}
	public bool IsFileInWaitingList(const char[] filename)
	{
		return SDKCall(SDKIsFileInWaitingList, this, filename);
	}
}

public Plugin myinfo =
{
	name		=	"File Network",
	author		=	"Batfoxkid",
	description	=	"But what if, no loading screen",
	version		=	PLUGIN_VERSION_FULL,
	url			=	"https://github.com/Batfoxkid/File-Network"
}

public void OnPluginStart()
{
	bool failed;

	GameData gamedata = new GameData("filenetwork");
	
	StartPrepSDKCall(SDKCall_Static);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CVEngineServer::GetPlayerNetInfo");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Pointer);
	SDKGetPlayerNetInfo = EndPrepSDKCall();
	if(!SDKGetPlayerNetInfo)
	{
		LogError("[Gamedata] Could not find CVEngineServer::GetPlayerNetInfo");
		failed = true;
	}
	
	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CNetChan::SendFile");
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_ByValue);
	SDKSendFile = EndPrepSDKCall();
	if(!SDKSendFile)
	{
		LogError("[Gamedata] Could not find CNetChan::SendFile");
		failed = true;
	}
	
	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CNetChan::IsFileInWaitingList");
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_ByValue);
	SDKIsFileInWaitingList = EndPrepSDKCall();
	if(!SDKIsFileInWaitingList)
	{
		LogError("[Gamedata] Could not find CNetChan::IsFileInWaitingList");
		failed = true;
	}

	if(failed)
		ThrowError("Gamedata failed, see error logs");
	
	RegAdminCmd("sm_filenetworktest", Command_Test, ADMFLAG_ROOT, "Test using send file");
}

public Action Command_Test(int client, int args)
{
	char buffer[PLATFORM_MAX_PATH];
	GetCmdArgString(buffer, sizeof(buffer));
	ReplaceString(buffer, sizeof(buffer), "\"", "");

	CNetChan chan = CNetChan(client);
	ReplyToCommand(client, "%x", chan);
	if(chan == -1)
	{
		ReplyToCommand(client, "Address invalid");
	}
	else if(chan.IsFileInWaitingList(buffer))
	{
		ReplyToCommand(client, "File already in waiting list");
	}
	else if(chan.SendFile(buffer))
	{
		ReplyToCommand(client, "Sent file to client");
	}
	else
	{
		ReplyToCommand(client, "File failed to send");
	}
	return Plugin_Handled;
}

/*
void CheckClient(int client)
{
	QueryClientConVar(client, "sv_allowupload", QueryCallback);
}

public void QueryCallback(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue, any value)
{
	if(result == ConVarQuery_Okay)
	{

	}
}
*/