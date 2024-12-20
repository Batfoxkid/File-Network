#include <sourcemod>
#include <sdktools>
#include <dhooks>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION	"manual"

#define TIMEOUT_PERIOD	90	// How long until we consider a requested file to be timed out

enum struct FileEnum
{
	int Client;
	char Filename[PLATFORM_MAX_PATH];
	Handle Plugin;
	Function Func;
	any Data;

	int Id;
}

Handle SDKGetPlayerNetInfo;
Handle SDKSendFile;
Handle SDKRequestFile;
Handle SDKIsFileInWaitingList;
Handle SDKCreateFragmentsFromFile;
Handle SDKGetNetChannel;
Address EngineAddress;
ConVar CvarMaxFileSize;

// Sending
int TransferID;
ArrayList SendListing;
Handle SendingTimer[MAXPLAYERS+1];
char CurrentlySending[MAXPLAYERS+1][PLATFORM_MAX_PATH];

// Requesting
ArrayList RequestListing;
Handle RequestingTimer[MAXPLAYERS+1];
int CurrentlyRequesting[MAXPLAYERS+1] = {-1, ...};
int StartedRequestingAt[MAXPLAYERS+1];

methodmap CNetChan
{
	public CNetChan(int client)
	{
		return SDKCall(SDKGetPlayerNetInfo, EngineAddress, client);
	}

	public bool SendFile(const char[] filename)
	{
		return SDKCall(SDKSendFile, this, filename, TransferID++);
	}
	public int RequestFile(const char[] filename)
	{
		int id = SDKCall(SDKRequestFile, this, filename);
		return id;
	}
	public bool IsFileInWaitingList(const char[] filename)
	{
		bool result;

		if(SDKIsFileInWaitingList)
		{
			result = SDKCall(SDKIsFileInWaitingList, this, filename);
		}
		else
		{
			int value = CvarMaxFileSize.IntValue;
			CvarMaxFileSize.IntValue = -1;
			result = SDKCall(SDKCreateFragmentsFromFile, this, filename, 0, 0);
			CvarMaxFileSize.IntValue = value;
		}

		return result;
	}
}

public Plugin myinfo =
{
	name		=	"File Network",
	author		=	"Batfoxkid, Artvin",
	description	=	"But what if, no loading screen",
	version		=	PLUGIN_VERSION,
	url			=	"github.com/Batfoxkid/File-Network"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("FileNet_SendFile", Native_SendFile);
	CreateNative("FileNet_RequestFile", Native_RequestFile);
	CreateNative("FileNet_IsFileInWaitingList", Native_IsFileInWaitingList);
	CreateNative("FileNet_GetNetChanPtr", Native_GetNetChanPtr);
	
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
		CvarMaxFileSize = FindConVar("net_maxfilesize");
		if(!CvarMaxFileSize)
		{
			LogError("[Game] Could not find net_maxfilesize");
			failed = true;
		}

		StartPrepSDKCall(SDKCall_Raw);
		PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CNetChan::CreateFragmentsFromFile");
		PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
		PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_ByValue);
		SDKCreateFragmentsFromFile = EndPrepSDKCall();
		if(!SDKCreateFragmentsFromFile)
		{
			LogError("[Gamedata] Could not find CNetChan::IsFileInWaitingList or CNetChan::CreateFragmentsFromFile");
			failed = true;
		}
	}
	
	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CBaseClient::GetNetChannel");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_ByValue);
	SDKGetNetChannel = EndPrepSDKCall();
	if(!SDKGetNetChannel)
	{
		LogError("[Gamedata] Could not find CBaseClient::GetNetChannel");
		failed = true;
	}

	DynamicDetour detour = DynamicDetour.FromConf(gamedata, "CGameClient::FileReceived");
	if(detour)
	{
		if(!detour.Enable(Hook_Post, OnFileReceived))
		{
			LogError("[Gamedata] Failed to enable detour: CGameClient::FileReceived");
			failed = true;
		}
		
		delete detour;
	}
	else
	{
		LogError("[Gamedata] Could not find CGameClient::FileReceived");
		failed = true;
	}

	//THIS ONLY WORKS ON WINDOWS!!!!!!
	//linux uses a different solution, timeout logic.
	detour = DynamicDetour.FromConf(gamedata, "CGameClient::FileDenied");
	if(detour)
	{
		if(!detour.Enable(Hook_Post, OnFileDenied))
		{
			LogError("[Gamedata] Failed to enable detour: CGameClient::FileDenied");
			failed = true;
		}
		
		delete detour;
	}
	else
	{
		LogError("[Gamedata] Could not find CGameClient::FileDenied");
		failed = true;
	}

	if(failed)
		ThrowError("Gamedata failed, see error logs");
	
	SendListing = new ArrayList(sizeof(FileEnum));
	RequestListing = new ArrayList(sizeof(FileEnum));
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
	while((match = SendListing.FindValue(client, FileEnum::Client)) != -1)
	{
		SendListing.GetArray(match, info);
		SendListing.Erase(match);

		CallSentFileFinish(info, false);
	}

	match = -1;
	while((match = RequestListing.FindValue(client, FileEnum::Client)) != -1)
	{
		RequestListing.GetArray(match, info);
		RequestListing.Erase(match);

		CallRequestFileFinish(info, false);
	}

	delete SendingTimer[client];
	CurrentlySending[client][0] = 0;

	delete RequestingTimer[client];
	CurrentlyRequesting[client] = -1;
}

public void OnNotifyPluginUnloaded(Handle plugin)
{
	int match = -1;
	while((match = SendListing.FindValue(plugin, FileEnum::Plugin)) != -1)
	{
		SendListing.Erase(match);
	}

	match = -1;
	while((match = RequestListing.FindValue(plugin, FileEnum::Plugin)) != -1)
	{
		RequestListing.Erase(match);
	}
}

/*
	Requesting Files
*/

public MRESReturn OnFileReceived(Address address, DHookParam param)
{
	int id = param.Get(2);
	CNetChan chan = SDKCall(SDKGetNetChannel, address);

	int length = RequestListing.Length;
	for(int i; i < length; i++)
	{
		static FileEnum info;
		RequestListing.GetArray(i, info);
		if(info.Id == id && chan == CNetChan(info.Client))
		{
			if(CurrentlyRequesting[info.Client] == id)
				CurrentlyRequesting[info.Client] = -1;
			
			RequestListing.Erase(i);
			CallRequestFileFinish(info, true);

			if(RequestingTimer[info.Client])
				TriggerTimer(RequestingTimer[info.Client]);
			
			break;
		}
	}
	return MRES_Ignored;
}

void StartRequestingClient(int client)
{
	if(!RequestingTimer[client])
	{
		RequestingTimer[client] = CreateTimer(1.0, Timer_RequestingClient, client, TIMER_REPEAT);
		TriggerTimer(RequestingTimer[client]);
	}
}

public Action Timer_RequestingClient(Handle timer, int client)
{
	CNetChan chan = CNetChan(client);
	if(!chan)
		return Plugin_Continue;
	
	static FileEnum info;
	
	if(CurrentlyRequesting[client] != -1)
	{
		// Client still giving this file
		if((StartedRequestingAt[client] + TIMEOUT_PERIOD) > GetTime())
			return Plugin_Continue;
		
		// We timed out, this can be a case of the client getting stuck.
		// Request a different file to unstuck the client then try again.
		DeleteFile("download/scripts/cheatcodes.txt");
		
		info.Client = client;
		strcopy(info.Filename, sizeof(info.Filename), "scripts/cheatcodes.txt");
		info.Func = INVALID_FUNCTION;
		info.Id = chan.RequestFile(info.Filename);
		RequestListing.PushArray(info);
		
		CurrentlyRequesting[client] = info.Id;
		StartedRequestingAt[client] += 10;
		return Plugin_Continue;
	}

	int length = RequestListing.Length;
	for(int i; i < length; i++)
	{
		RequestListing.GetArray(i, info);
		if(info.Client == client)
		{
			info.Id = chan.RequestFile(info.Filename);
			RequestListing.SetArray(i, info);

			CurrentlyRequesting[client] = info.Id;
			StartedRequestingAt[client] = GetTime();
			float CurrentClientPing = GetClientAvgLatency(client, NetFlow_Outgoing);
			CurrentClientPing *= 2.0; //beacuse it has to go bothways.
			CurrentClientPing += 0.2; //Little buffer for ping issues and differences
			Handle pack;
			CreateDataTimer(CurrentClientPing, Timer_DeniedFileCheck, pack);
			WritePackCell(pack, client); //Client
			WritePackCell(pack, info.Id); //The id that we ask for
			return Plugin_Continue;
		}	
	}

	// No more files to send
	RequestingTimer[client] = null;
	return Plugin_Stop;
}

public Action Timer_DeniedFileCheck(Handle timer, DataPack pack)
{
	pack.Reset();
	int client = pack.ReadCell();
	int id = pack.ReadCell();
	//We can presume the client didnt recieve the file if recieving didnt work out.
	OnFileDeniedInternal(CNetChan(client), id);
	return Plugin_Stop;
}

public MRESReturn OnFileDenied(Address address, DHookParam param)
{
	int id = param.Get(2);
	CNetChan chan = SDKCall(SDKGetNetChannel, address);
	OnFileDeniedInternal(chan, id);
	return MRES_Ignored;
}

void OnFileDeniedInternal(CNetChan chan, int id)
{
	int length = RequestListing.Length;
	for(int i; i < length; i++)
	{
		static FileEnum info;
		RequestListing.GetArray(i, info);
		if(info.Id == id && chan == CNetChan(info.Client))
		{
			if(CurrentlyRequesting[info.Client] == id)
				CurrentlyRequesting[info.Client] = -1;
			
			RequestListing.Erase(i);
			CallRequestFileFinish(info, false);

			if(RequestingTimer[info.Client])
				TriggerTimer(RequestingTimer[info.Client]);
			
			break;
		}
	}
}
static void CallRequestFileFinish(const FileEnum info, bool success)
{
	if(info.Func && info.Func != INVALID_FUNCTION)
	{
		Call_StartFunction(info.Plugin, info.Func);
		Call_PushCell(info.Client);
		Call_PushString(info.Filename);
		Call_PushCell(info.Id);
		Call_PushCell(success);
		Call_PushCell(info.Data);
		Call_Finish();
	}
}

/*
	Sending Files
*/

void StartSendingClient(int client)
{
	if(!SendingTimer[client])
	{
		SendingTimer[client] = CreateTimer(0.1, Timer_SendingClient, client, TIMER_REPEAT);
		TriggerTimer(SendingTimer[client]);
	}
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
		{
			return Plugin_Continue;
		}
		else
		{
			// We finished this file
			int length = SendListing.Length;
			for(int i; i < length; i++)
			{
				static FileEnum info;
				SendListing.GetArray(i, info);
				if(info.Client == client && StrEqual(info.Filename, CurrentlySending[client], false))
				{
					SendListing.Erase(i);
					CallSentFileFinish(info, true);
					break;
				}
			}
		}
		
		CurrentlySending[client][0] = 0;
	}

	int length = SendListing.Length;
	for(int i; i < length; i++)
	{
		static FileEnum info;
		SendListing.GetArray(i, info);
		if(info.Client == client)
		{
			if(chan.SendFile(info.Filename))
			{
				strcopy(CurrentlySending[client], sizeof(CurrentlySending[]), info.Filename);
			}
			else
			{
				// Failed reasons tend to be bad names, bad sizes, etc.
				SendListing.Erase(i);
				CallSentFileFinish(info, false);
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

/*
	Natives
*/

void StartNative()
{
	if(!SendListing)
		ThrowNativeError(SP_ERROR_NATIVE, "Please wait until OnAllPluginsLoaded");
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
	int length = SendListing.Length;
	for(int i; i < length; i++)
	{
		static FileEnum info;
		SendListing.GetArray(i, info);
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

	SendListing.PushArray(info);

	StartSendingClient(info.Client);
	return true;
}

public any Native_RequestFile(Handle plugin, int params)
{
	StartNative();

	FileEnum info;
	info.Client = GetNativeClient(1);
	GetNativeString(2, info.Filename, sizeof(info.Filename));

	info.Plugin = plugin;
	info.Func = GetNativeFunction(3);
	info.Data = GetNativeCell(4);

	RequestListing.PushArray(info);

	StartRequestingClient(info.Client);
	return CurrentlyRequesting[info.Client];
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

public any Native_GetNetChanPtr(Handle plugin, int params)
{
	StartNative();
	
	int client = GetNativeCell(1);
	
	CNetChan chan = CNetChan(client);
	if(!chan)
		return Address_Null;
		
	return chan;
}