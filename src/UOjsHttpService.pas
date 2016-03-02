(*
  OJS HTTP SERVICE - Servidor HTTP que implementa a arquitetura REST e retorno
  de dados em JSON. Permite requisições "OPTIONS" que no Delphi são recusadas
  automaticamente.
  Autor: Alan Thales, 07/2015
*)
unit UOjsHttpService;

interface

uses
  Datasnap.DSHTTP, IPPeerAPI, Datasnap.DSCommonServer, Datasnap.DSHTTPCommon,
  System.Classes, Generics.Collections;

type
  TDSHTTPContextHack = class(TDSHTTPContext)
  strict private
    FContext: IIPContext;
    FRequest: TDSHTTPRequestIndy;
    FResponse: TDSHTTPResponseIndy;
  public
    constructor Create(const AContext: IIPContext;
      const ARequestInfo: IIPHTTPRequestInfo;
      const AResponseInfo: IIPHTTPResponseInfo);
    destructor Destroy; override;
    function Connected: Boolean; override;
    property Context: IIPContext read FContext;
    property Request: TDSHTTPRequestIndy read FRequest;
    property Response: TDSHTTPResponseIndy read FResponse;
  end;

  TJsonHttpServer = class(TDSHTTPServer)
  private
    FServer: IIPHTTPServer;
    FDefaultPort: Word;
    FServerSoftware: string;
    FIPImplementationID: string;
    FPeerProcs: IIPPeerProcs;
    function PeerProcs: IIPPeerProcs;
    function GetActive: Boolean;
    function GetDefaultPort: Word;
    procedure SetActive(const Value: Boolean);
    procedure SetDefaultPort(const Value: Word);
    procedure DoIndyCommand(AContext: IIPContext;
      ARequestInfo: IIPHTTPRequestInfo; AResponseInfo: IIPHTTPResponseInfo);
    function GetServerSoftware: string;
    procedure SetServerSoftware(const Value: string);
  protected
    function Decode(Data: string): string; override;
    procedure InitializeServer; virtual;
  public
    constructor Create(const ADSServer: TDSCustomServer; const AIPImplementationID: string = ''); override;
    destructor Destroy; override;
    property Server: IIPHTTPServer read FServer;
    property DefaultPort: Word read GetDefaultPort write SetDefaultPort;
    property Active: Boolean read GetActive write SetActive;
    property ServerSoftware: string read GetServerSoftware write SetServerSoftware;
  end;

  TOjsHttpService = class(TCustomDSHTTPServerTransport)
  private
    FComponentList: TList<TComponent>;
    FCertFiles: TDSCustomCertFiles;
    FDefaultPort: Integer;
    FActive: Boolean;
    {$HINTS OFF}
    procedure RemoveComponent(const AComponent: TDSHTTPServiceComponent);
    procedure AddComponent(const AComponent: TDSHTTPServiceComponent);
    {$HINTS ON}
    procedure SetCertFiles(const AValue: TDSCustomCertFiles);
  protected
    function CreateHttpServer: TDSHTTPServer; override;
    procedure InitializeHttpServer; override;
    procedure HTTPOtherContext(
      AContext: TDSHTTPContext;
      ARequestInfo: TDSHTTPRequest; AResponseInfo: TDSHTTPResponse;
      const ARequest: string; var AHandled: Boolean); virtual;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function GetHttpPort: Word; virtual;
    function GetServerSoftware: string; virtual;
    procedure SetIPImplementationID(const Value: string); override;

    function IsActive: Boolean; virtual;
    procedure SetActive(Status: Boolean); virtual;
    procedure SetHttpPort(const Port: Word); virtual;
    ///<summary>
    ///  Called by the server when it is starting.
    ///</summary>
    procedure Start; override;
    ///<summary>
    ///  Called by the server when it is stoping.
    ///</summary>
    procedure Stop; override;
  published
    { Published declarations }
    ///  <summary> HTTP port </summary>
    [Default(_IPPORT_HTTP)]
    property HttpPort: Word read GetHttpPort write SetHttpPort default _IPPORT_HTTP;
    ///  <summary> REST URL context like in http://my.site.com/datasnap/rest/...
    ///     In the example above rest denotes that the request is a REST request
    ///     and is processed by REST service
    ///  </summary>
    ///  <summary> True to start the service, false to stop it
    ///  </summary>
    [Default(False)]
    property Active: Boolean read IsActive write SetActive default False;
    ///  <summary> Server software, read only
    ///  </summary>
    property ServerSoftware: string read GetServerSoftware;
    /// <summary> X.509 certificates and keys</summary>
    property CertFiles: TDSCustomCertFiles read FCertFiles write SetCertFiles;

    property IPImplementationID;
    property DSContext;
    property RESTContext;
    property CacheContext;
    property OnHTTPTrace;
    property OnFormatResult;
    property Server;
    property DSHostname;
    property DSPort;
    property Filters;
    property AuthenticationManager;
    property CredentialsPassThrough;
    property DSAuthUser;
    property DSAuthPassword;
    property SessionTimeout;
  end;

  procedure Register;

implementation

uses
  SysUtils, Datasnap.DSSession, Datasnap.DSService, Datasnap.DSServerResStrs,
  System.JSON;

procedure Register;
begin
  RegisterComponents('OJS', [TOjsHttpService]);
end;

constructor TJsonHttpServer.Create(const ADSServer: TDSCustomServer;
  const AIPImplementationID: string);
begin
  inherited Create(ADSServer, AIPImplementationID);
  FIPImplementationID := AIPImplementationID;
  FServerSoftware := 'DatasnapHTTPService/2011';
end;

function TJsonHttpServer.Decode(Data: string): string;
begin
  if Data.IndexOf('%') >= 0 then  // Optimization
    Result := PeerProcs.URLDecode(Data)
  else
    Result := Data;
end;

destructor TJsonHttpServer.Destroy;
begin
  inherited;
  FreeAndNil(FServer);
end;

procedure TJsonHttpServer.DoIndyCommand(AContext: IIPContext;
  ARequestInfo: IIPHTTPRequestInfo; AResponseInfo: IIPHTTPResponseInfo);
var
  LContext: TDSHTTPContextHack;
begin
  AResponseInfo.CustomHeaders.AddValue('Access-Control-Allow-Origin', '*');

  if ARequestInfo.Command = 'OPTIONS' then
  begin
    AResponseInfo.CustomHeaders.AddValue('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    AResponseInfo.CustomHeaders.AddValue('Access-Control-Allow-Headers', 'ACCEPT, X-REQUESTED-WITH, CONTENT-TYPE, AUTHORIZATION, PRAGMA');
    AResponseInfo.CustomHeaders.AddValue('Content-Length', '0');
    AResponseInfo.CustomHeaders.AddValue('Content-Type', 'text/plain');
    AResponseInfo.ResponseNo := 200;
    AResponseInfo.CloseConnection := True;
    Exit;
  end;

  LContext := TDSHTTPContextHack.Create(AContext, ARequestInfo, AResponseInfo);

  try
    DoCommand(LContext, LContext.Request, LContext.Response);
  finally
    LContext.Free;
  end;
end;

function TJsonHttpServer.GetActive: Boolean;
begin
  if FServer <> nil then
    Result := FServer.Active
  else
    Result := False;
end;

function TJsonHttpServer.GetDefaultPort: Word;
begin
  if FServer <> nil then
    Result := FServer.DefaultPort
  else
    Result := FDefaultPort;
end;

function TJsonHttpServer.GetServerSoftware: string;
begin
  if FServer <> nil then
    Result := FServer.ServerSoftware
  else
    Result := FServerSoftware;
end;

procedure TJsonHttpServer.InitializeServer;
begin
  if FServer <> nil then
  begin
    FServer.UseNagle := False;
    FServer.KeepAlive := True;
    FServer.ServerSoftware := FServerSoftware;
    FServer.DefaultPort := FDefaultPort;

    FServer.OnCommandGet := Self.DoIndyCommand;
    FServer.OnCommandOther := Self.DoIndyCommand;
  end;
end;

function TJsonHttpServer.PeerProcs: IIPPeerProcs;
begin
  if FPeerProcs = nil then
    FPeerProcs := IPProcs(FIPImplementationID);
  Result := FPeerProcs;
end;

procedure TJsonHttpServer.SetActive(const Value: Boolean);
begin
  if Value and (FServer = nil) then
  begin
    FServer := PeerFactory.CreatePeer(FIPImplementationID, IIPHTTPServer, nil) as IIPHTTPServer;
    InitializeServer;
  end;
  if FServer <> nil then
    FServer.Active := Value;
end;

procedure TJsonHttpServer.SetDefaultPort(const Value: Word);
begin
  if FServer <> nil then
    FServer.DefaultPort := Value
  else
    FDefaultPort := Value;
end;

procedure TJsonHttpServer.SetServerSoftware(const Value: string);
begin
  if FServer <> nil then
    FServer.ServerSoftware := Value
  else
    FServerSoftware := Value;
end;

{ TDSHTTPContextHack }

function TDSHTTPContextHack.Connected: Boolean;
begin
  Result := FContext.Connection.Connected;
end;

constructor TDSHTTPContextHack.Create(const AContext: IIPContext;
  const ARequestInfo: IIPHTTPRequestInfo;
  const AResponseInfo: IIPHTTPResponseInfo);
begin
  inherited Create;
  FContext := AContext;
  FRequest := TDSHTTPRequestIndy.Create(ARequestInfo);
  FResponse := TDSHTTPResponseIndy.Create(AResponseInfo);
end;

destructor TDSHTTPContextHack.Destroy;
begin
  FRequest.Free;
  FResponse.Free;
  inherited;
end;

{ TOjsHttpService }

procedure TOjsHttpService.AddComponent(
  const AComponent: TDSHTTPServiceComponent);
begin
  if FComponentList.IndexOf(AComponent) = -1 then
    FComponentList.Add(AComponent);
end;

constructor TOjsHttpService.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FDefaultPort := _IPPORT_HTTP;
  FComponentList := TList<TComponent>.Create;  // Does not own objects
end;

function TOjsHttpService.CreateHttpServer: TDSHTTPServer;
begin
  Result := TJsonHttpServer.Create(Self.Server, IPImplementationID);
end;

destructor TOjsHttpService.Destroy;
begin
  TDSSessionManager.Instance.TerminateAllSessions(self);
  ServerCloseAllTunnelSessions;
  FreeAndNil(FComponentList);
  inherited;
end;

function TOjsHttpService.GetHttpPort: Word;
begin
  if Assigned(FHttpServer) then
    Result := TJsonHttpServer(FHttpServer).DefaultPort
  else
    Result := FDefaultPort;
end;

function TOjsHttpService.GetServerSoftware: string;
begin
  if not (csLoading in ComponentState) then
    RequiresServer;
  if FHttpServer <> nil then
    Result := TJsonHttpServer(FHttpServer).ServerSoftware
  else
    Result := '';
end;

procedure TOjsHttpService.HTTPOtherContext(AContext: TDSHTTPContext;
  ARequestInfo: TDSHTTPRequest; AResponseInfo: TDSHTTPResponse;
  const ARequest: string; var AHandled: Boolean);
begin

end;

procedure TOjsHttpService.InitializeHttpServer;
begin
  inherited;
  if FCertFiles <> nil then
    FCertFiles.SetServerProperties(FHttpServer);
  TJsonHttpServer(FHttpServer).DefaultPort := FDefaultPort;
  TJsonHttpServer(FHttpServer).Active := FActive;
  TJsonHttpServer(FHttpServer).SessionLifetime := SessionLifetime;
  TJsonHttpServer(FHttpServer).SessionTimeout := SessionTimeout;
end;

function TOjsHttpService.IsActive: Boolean;
begin
  if Assigned(FHttpServer) then
    Result := TJsonHttpServer(FHttpServer).Active
  else
    Result := FActive;
end;

procedure TOjsHttpService.Notification(AComponent: TComponent;
  Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FCertFiles) then
    FCertFiles := nil;
end;

procedure TOjsHttpService.RemoveComponent(
  const AComponent: TDSHTTPServiceComponent);
begin
  if (AComponent <> nil) and (FComponentList <> nil) then
    FComponentList.Remove(AComponent);
end;

procedure TOjsHttpService.SetActive(Status: Boolean);
begin
  if not Status then
    ServerCloseAllTunnelSessions;
  FActive := Status;
  if Assigned(FHttpServer) then
    TJsonHttpServer(FHttpServer).Active := Status
  else if not (csLoading in ComponentState) then
    // Create FHttpServer
    if FActive then
      RequiresServer;
end;

procedure TOjsHttpService.SetCertFiles(const AValue: TDSCustomCertFiles);
begin
  if (AValue <> FCertFiles) then
  begin
    if Assigned(FCertFiles) then
      RemoveFreeNotification(FCertFiles);
    FCertFiles := AValue;
    if Assigned(FCertFiles) then
      FreeNotification(FCertFiles);
  end;
end;

procedure TOjsHttpService.SetHttpPort(const Port: Word);
begin
  FDefaultPort := Port;
  if Assigned(FHttpServer) then
    TJsonHttpServer(FHttpServer).DefaultPort := Port;
end;

procedure TOjsHttpService.SetIPImplementationID(const Value: string);
begin
  if IsActive then
    raise TDSServiceException.Create(sCannotChangeIPImplID);
  inherited SetIPImplementationID(Value);
end;

procedure TOjsHttpService.Start;
begin
  inherited;
  RequiresServer;
  if Assigned(FHttpServer) then
  begin
    // Moved
    //TDSHTTPServerIndy(FHttpServer).Server.UseNagle := False;
    TJsonHttpServer(FHttpServer).Active := True;
  end;
end;

procedure TOjsHttpService.Stop;
begin
  TDSSessionManager.Instance.TerminateAllSessions(self);
  SetActive(False);
  inherited;
end;

end.

