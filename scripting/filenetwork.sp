#include <sourcemod>
#include <sdktools>
#include <dhooks>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION	"manual"

enum struct FileEnum
{
	int Client;
	char Filename[PLATFORM_MAX_PATH];
	Handle Plugin;
	Function Func;
	any Data;
}

Handle SDKGetPlayerNetInfo;
Handle SDKSendFile;
Handle SDKRequestFile;
Handle SDKIsFileInWaitingList;
Address EngineAddress;
int TransferID;
char SendFileMatch[PLATFORM_MAX_PATH];

ArrayList FileListing;

bool InQuery[MAXPLAYERS+1];
Handle SendingTimer[MAXPLAYERS+1];
char CurrentlySending[MAXPLAYERS+1][PLATFORM_MAX_PATH];

methodmap CNetChan
{
	public CNetChan(int client)
	{
		return SDKCall(SDKGetPlayerNetInfo, EngineAddress, client);
	}

	public bool SendFile(const char[] filename)
	{
		bool result = SDKCall(SDKSendFile, this, filename, TransferID++);
		strcopy(SendFileMatch, sizeof(SendFileMatch), filename);
		return result;
	}
	public int RequestFile(const char[] filename)
	{
		return SDKCall(SDKRequestFile, this, filename);
	}
	public bool IsFileInWaitingList(const char[] filename)
	{
		return SDKCall(SDKIsFileInWaitingList, this, filename);
	}
}

public Plugin myinfo =
{
	name		=	"File Network",
	author		=	"Batfoxkid & Artvin",
	description	=	"But what if, no loading screen",
	version		=	PLUGIN_VERSION,
	url			=	"github.com/Batfoxkid/File-Network"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("FileNet_SendFile", Native_SendFile);
	CreateNative("FileNet_IsFileInWaitingList", Native_IsFileInWaitingList);
	
	RegPluginLibrary("filenetwork");
	return APLRes_Success;
}

public void OnPluginStart()
{
	GameData gamedata = new GameData("filenetwork");
	
	char identifier[64];
	if(!gamedata.GetKeyValue("EngineInterface", identifier, sizeof(identifier)))
		SetFailState("[Gamedata] Could not find EngineInterface");
	
	StartPrepSDKCall(SDKCall_Static);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CreateInterface");
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	Handle sdkcall = EndPrepSDKCall();
	if(!sdkcall)
		SetFailState("[Gamedata] Could not find CreateInterface");
	
	EngineAddress = SDKCall(sdkcall, identifier, 0);
	if(EngineAddress == Address_Null)
		SetFailState("[Gamedata] EngineInterface is incorrect for mod");
	
	delete sdkcall;
	
	bool failed;

	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual, "GetPlayerNetInfo");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	SDKGetPlayerNetInfo = EndPrepSDKCall();
	if(!SDKGetPlayerNetInfo)
	{
		LogError("[Gamedata] Could not find GetPlayerNetInfo");
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
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CNetChan::RequestFile");
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_ByValue);
	SDKRequestFile = EndPrepSDKCall();
	if(!SDKRequestFile)
	{
		LogError("[Gamedata] Could not find CNetChan::RequestFile");
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
	
	FileListing = new ArrayList(sizeof(FileEnum));
	RegAdminCmd("sm_filenet_send", Command_TestSend, ADMFLAG_ROOT, "Test using send file");
	RegAdminCmd("sm_filenet_request", Command_TestRequest, ADMFLAG_ROOT, "Test using request file");
}

public Action Command_TestSend(int client, int args)
{
	char buffer[PLATFORM_MAX_PATH];
	GetCmdArgString(buffer, sizeof(buffer));
	ReplaceString(buffer, sizeof(buffer), "\"", "");

	CNetChan chan = CNetChan(client);
	if(!chan)
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

public Action Command_TestRequest(int client, int args)
{
	char buffer[PLATFORM_MAX_PATH];
	GetCmdArgString(buffer, sizeof(buffer));
	ReplaceString(buffer, sizeof(buffer), "\"", "");

	CNetChan chan = CNetChan(client);
	if(!chan)
	{
		ReplyToCommand(client, "Address invalid");
	}
	else
	{
		chan.RequestFile(buffer);
		ReplyToCommand(client, "Requested file from client");
	}
	return Plugin_Handled;
}

public void OnClientDisconnect_Post(int client)
{
	static FileEnum info;

	int match = -1;
	while((match = FileListing.FindValue(client, FileEnum::Client)) != -1)
	{
		FileListing.GetArray(match, info);
		CallSentFileFinish(info, false);

		FileListing.Erase(match);
	}

	delete SendingTimer[client];
	CurrentlySending[client][0] = 0;
}

public Action Timer_SendingClient(Handle timer, int client)
{
	CNetChan chan = CNetChan(client);
	if(!chan)
		return Plugin_Continue;
	
	if(CurrentlySending[client][0])
	{
		// Client still downloading this file
		if(chan.IsFileInWaitingList(CurrentlySending[client]))
			return Plugin_Continue;
		
		// We finished this file
		int length = FileListing.Length;
		for(int i; i < length; i++)
		{
			static FileEnum info;
			FileListing.GetArray(i, info);
			if(info.Client == client && StrEqual(info.Filename, CurrentlySending[client], false))
			{
				CallSentFileFinish(info, true);
				FileListing.Erase(i);
				break;
			}
		}

		CurrentlySending[client][0] = 0;
	}

	int length = FileListing.Length;
	for(int i; i < length; i++)
	{
		static FileEnum info;
		FileListing.GetArray(i, info);
		if(info.Client == client)
		{
			if(chan.SendFile(info.Filename))
			{
				strcopy(CurrentlySending[client], sizeof(CurrentlySending[]), info.Filename);
			}
			else
			{
				// Failed reasons tend to be bad names, bad sizes, etc.
				CallSentFileFinish(info, false);
				FileListing.Erase(i);
			}

			return Plugin_Continue;
		}	
	}

	// No more files to send
	SendingTimer[client] = null;
	return Plugin_Stop;
}

static void CallSentFileFinish(const FileEnum info, bool success)
{
	if(info.Func && info.Func != INVALID_FUNCTION)
	{
		Call_StartFunction(info.Plugin, info.Func);
		Call_PushCell(info.Client);
		Call_PushString(info.Filename);
		Call_PushCell(success);
		Call_PushCell(info.Data);
		Call_Finish();
	}
}

void StartNative()
{
	if(!FileListing)
		ThrowNativeError(SP_ERROR_NATIVE, "Please wait until OnAllPluginsLoaded");
}

void StartSendingClient(int client)
{
	// Clients need sv_allowupload in order for this to work, sorry CSGO fans
	if(!InQuery[client] && QueryClientConVar(client, "sv_allowupload", QueryCallback) != QUERYCOOKIE_FAILED)
		InQuery[client] = true;
}

public void QueryCallback(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue, any value)
{
	if(!SendingTimer[client] && IsClientInGame(client))
	{
		if(result == ConVarQuery_Okay && StringToInt(cvarValue))
		{
			SendingTimer[client] = CreateTimer(0.5, Timer_SendingClient, client, TIMER_REPEAT);
			Timer_SendingClient(null, client);
		}
		else
		{
			PrintToChat(client, "[SM] The server is trying to send you a file, enable sv_allowupload to allow this process");
		}
	}

	InQuery[client] = false;
}

int GetNativeClient(int param)
{
	int client = GetNativeCell(param);
	if(client < 1 || client > MaxClients)
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d", client);
	
	if(!IsClientInGame(client))
		ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not in-game", client);
	
	if(IsFakeClient(client))
		ThrowNativeError(SP_ERROR_NATIVE, "Client %d is a bot player", client);
	
	return client;
}

bool FileExistsForClient(int client, const char[] filename)
{
	int length = FileListing.Length;
	for(int i; i < length; i++)
	{
		static FileEnum info;
		FileListing.GetArray(i, info);
		if(info.Client == client)
		{
			if(StrEqual(info.Filename, filename, false))
				return true;
		}	
	}
	
	return false;
}

public any Native_SendFile(Handle plugin, int params)
{
	StartNative();

	FileEnum info;
	info.Client = GetNativeClient(1);
	GetNativeString(2, info.Filename, sizeof(info.Filename));

	info.Plugin = plugin;
	info.Func = GetNativeFunction(3);
	info.Data = GetNativeCell(4);

	FileListing.PushArray(info);

	StartSendingClient(info.Client);
	return true;
}

public any Native_IsFileInWaitingList(Handle plugin, int params)
{
	StartNative();

	int client = GetNativeCell(1);

	if(SendingTimer[client])	// Just to double check with CNetChan::IsFileInWaitingList
		TriggerTimer(SendingTimer[client], true);

	int length;
	GetNativeStringLength(2, length);
	char[] filename = new char[++length];
	GetNativeString(2, filename, length);
	
	return FileExistsForClient(client, filename);
}