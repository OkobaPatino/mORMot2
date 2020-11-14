/// Asynchronous RTSP Relay/Proxy over HTTP
// - this unit is a part of the Open Source Synopse mORMot framework 2,
// licensed under a MPL/GPL/LGPL three license - see LICENSE.md
unit mormot.net.rtsphttp;

{
  *****************************************************************************

   RTSP Stream Tunnelling over HTTP as defined by Apple at https://goo.gl/CX6VA3
   - Low-level HTTP and RTSP Connections
   - RTSP over HTTP Tunnelling 

  *****************************************************************************

  Encapsulate a RTSP TCP/IP duplex video stream into two HTTP links,
  one POST for upgoing commands, and one GET for downloaded video.

  Thanks to TAsynchServer, it can handle thousands on concurrent streams,
  with minimal resources, in a cross-platform way.

}

interface

{$I ..\mormot.defines.inc}

uses
  sysutils,
  classes,
  mormot.core.base,
  mormot.core.os,
  mormot.core.rtti,
  mormot.core.data,
  mormot.core.text,
  mormot.core.unicode,
  mormot.core.datetime,
  mormot.core.buffers,
  mormot.core.threads,
  mormot.core.log,
  mormot.core.test, // this unit includes its own regression tests
  mormot.net.sock,
  mormot.net.http,
  mormot.net.client,
  mormot.net.server,
  mormot.net.asynch;


{ ******************** Low-level HTTP and RTSP Connections }

type
  /// holds a HTTP POST connection for RTSP proxy
  // - as used by the TRTSPOverHTTPServer class
  TPostConnection = class(TAsynchConnection)
  protected
    fRtspTag: TPollSocketTag;
    // redirect the POST base-64 encoded command to the RTSP socket
    function OnRead(
      Sender: TAsynchConnections): TPollAsynchSocketOnRead; override;
    // will release the associated TRtspConnection instance
    procedure BeforeDestroy(Sender: TAsynchConnections); override;
  end;

  /// holds a RTSP connection for HTTP GET proxy
  // - as used by the TRTSPOverHTTPServer class
  TRtspConnection = class(TAsynchConnection)
  protected
    fGetBlocking: TCrtSocket;
    // redirect the RTSP socket input to the GET content
    function OnRead(
      Sender: TAsynchConnections): TPollAsynchSocketOnRead; override;
    // will release the associated blocking GET socket
    procedure BeforeDestroy(Sender: TAsynchConnections); override;
  end;



{ ******************** RTSP over HTTP Tunnelling }

type
  /// exceptions raised by this unit
  ERTSPOverHTTP = class(ESynException);

  /// implements RTSP over HTTP asynchronous proxy
  // - the HTTP transport is built from two separate HTTP GET and POST requests
  // initiated by the client; the server then binds the connections to form a
  // virtual full-duplex connection - see https://goo.gl/CX6VA3 for reference
  // material about this horrible, but widely accepted, Apple hack
  TRTSPOverHTTPServer = class(TAsynchServer)
  protected
    fRtspServer, fRtspPort: RawUTF8;
    fPendingGet: TRawUTF8List;
    function GetHttpPort: RawUTF8;
    // creates TPostConnection and TRtspConnection instances for a given stream
    function ConnectionCreate(aSocket: TNetSocket; const aRemoteIp: RawUTF8;
      out aConnection: TAsynchConnection): boolean; override;
  public
    /// initialize the proxy HTTP server forwarding specified RTSP server:port
    constructor Create(const aRtspServer, aRtspPort, aHttpPort: RawUTF8;
      aLog: TSynLogClass; const aOnStart, aOnStop: TOnNotifyThread;
      aOptions: TAsynchConnectionsOptions = []); reintroduce;
    /// shutdown and finalize the server
    destructor Destroy; override;
    /// convert a rtsp://.... URI into a http://... proxy URI
    // - will reuse the rtsp public server name, but change protocol to http://
    // and set the port to RtspPort
    function RtspToHttp(const RtspURI: RawUTF8): RawUTF8;
    /// convert a http://... proxy URI into a rtsp://.... URI
    function HttpToRtsp(const HttpURI: RawUTF8): RawUTF8;
    /// perform some basic regression and benchmark testing on a running server
    procedure RegressionTests(test: TSynTestCase; clientcount, steps: integer);
    /// the associated RTSP server address
    property RtspServer: RawUTF8
      read fRtspServer;
    /// the associated RTSP server port
    property RtspPort: RawUTF8
      read fRtspPort;
    /// the bound HTTP port
    property HttpPort: RawUTF8
      read GetHttpPort;
  end;




implementation



{ ******************** Low-level HTTP and RTSP Connections }

{ TRtspConnection }

function TRtspConnection.OnRead(
  Sender: TAsynchConnections): TPollAsynchSocketOnRead;
begin
  if acoVerboseLog in Sender.Options then
    Sender.LogVerbose(self, 'Frame forwarded', fSlot.readbuf);
  if fGetBlocking.TrySndLow(pointer(fSlot.readbuf), length(fSlot.readbuf)) then
  begin
    Sender.Log.Add.Log(sllDebug, 'OnRead % RTSP forwarded % bytes to GET',
      [Handle, length(fSlot.readbuf)], self);
    result := sorContinue;
  end
  else
  begin
    Sender.Log.Add.Log(sllDebug,
      'OnRead % RTSP failed send to GET -> close % connection',
      [Handle, RemoteIP], self);
    result := sorClose;
  end;
  fSlot.readbuf := '';
end;

procedure TRtspConnection.BeforeDestroy(Sender: TAsynchConnections);
begin
  fGetBlocking.Free;
  inherited BeforeDestroy(Sender);
end;


{ TPostConnection }

function TPostConnection.OnRead(
  Sender: TAsynchConnections): TPollAsynchSocketOnRead;
var
  decoded: RawByteString;
  rtsp: TAsynchConnection;
begin
  result := sorContinue;
  decoded := Base64ToBinSafe(TrimControlChars(fSlot.readbuf));
  if decoded = '' then
    exit; // maybe some pending command chars
  fSlot.readbuf := '';
  rtsp := Sender.ConnectionFindLocked(fRtspTag);
  if rtsp <> nil then
  try
    Sender.Write(rtsp, decoded); // asynch sending to RTSP server
    Sender.Log.Add.Log(sllDebug, 'OnRead % POST forwarded RTSP command [%]',
      [Handle, decoded], self);
  finally
    Sender.Unlock;
  end
  else
  begin
    Sender.Log.Add.Log(sllDebug, 'OnRead % POST found no rtsp=%',
      [Handle, fRtspTag], self);
    result := sorClose;
  end;
end;

procedure TPostConnection.BeforeDestroy(Sender: TAsynchConnections);
begin
  Sender.ConnectionRemove(fRtspTag); // disable associated RTSP and GET sockets
  inherited BeforeDestroy(Sender);
end;



{ ******************** RTSP over HTTP Tunnelling }


{ TRTSPOverHTTPServer }

constructor TRTSPOverHTTPServer.Create(
  const aRtspServer, aRtspPort, aHttpPort: RawUTF8; aLog: TSynLogClass;
  const aOnStart, aOnStop: TOnNotifyThread; aOptions: TAsynchConnectionsOptions);
begin
  fLog := aLog;
  fRtspServer := aRtspServer;
  fRtspPort := aRtspPort;
  fPendingGet := TRawUTF8List.Create([fObjectsOwned, fCaseSensitive]);
  inherited Create(
    aHttpPort, aOnStart, aOnStop, TPostConnection, 'rtsp/http', aLog, aOptions);
end;

destructor TRTSPOverHTTPServer.Destroy;
var
  log: ISynLog;
begin
  log := fLog.Enter(self, 'Destroy');
  inherited Destroy;
  fPendingGet.Free;
end;

type
  TProxySocket = class(THttpServerSocket)
  protected
    fExpires: cardinal;
  published
    property Method;
    property URL;
    property RemoteIP;
  end;

const
  RTSP_MIME = 'application/x-rtsp-tunnelled';

function TRTSPOverHTTPServer.ConnectionCreate(aSocket: TNetSocket;
  const aRemoteIp: RawUTF8; out aConnection: TAsynchConnection): boolean;
var
  log: ISynLog;
  sock, get, old: TProxySocket;
  cookie: RawUTF8;
  res: TNetResult;
  rtsp: TNetSocket;
  i, found: PtrInt;
  postconn: TPostConnection;
  rtspconn: TRtspConnection;
  now: cardinal;

  procedure PendingDelete(i: integer; const reason: RawUTF8);
  begin
    if log <> nil then
      log.Log(sllDebug, 'ConnectionCreate rejected %', [reason], self);
    fPendingGet.Delete(i);
  end;

begin
  aConnection := nil;
  get := nil;
  result := false;
  log := fLog.Enter('ConnectionCreate(%)', [aSocket], self);
  try
    sock := TProxySocket.Create(nil);
    try
      sock.AcceptRequest(aSocket, nil);
      sock.RemoteIP := aRemoteIp;
      sock.CreateSockIn; // faster header process (released below once not needed)
      if (sock.GetRequest({withBody=}false, {headertix=}0) = grHeaderReceived) and
         (sock.URL <> '') then
      begin
        if log <> nil then
          log.Log(sllTrace, 'ConnectionCreate received % % %',
            [sock.Method, sock.URL, sock.HeaderGetText], self);
        cookie := sock.HeaderGetValue('X-SESSIONCOOKIE');
        if cookie = '' then
          exit;
        fPendingGet.Safe.Lock;
        try
          found := -1;
          now := mormot.core.os.GetTickCount64 shr 10;
          for i := fPendingGet.Count - 1 downto 0 do
          begin
            old := fPendingGet.ObjectPtr[i];
            if now > old.fExpires then
            begin
              if log <> nil then
                log.Log(sllTrace, 'ConnectionCreate deletes deprecated %',
                  [old], self);
              fPendingGet.Delete(i);
            end
            else if fPendingGet[i] = cookie then
              found := i;
          end;
          if IdemPropNameU(sock.Method, 'GET') then
          begin
            if found >= 0 then
              PendingDelete(found, 'duplicated')
            else
            begin
              sock.Write(FormatUTF8(
                'HTTP/1.0 200 OK'#13#10 +
                'Server: % %'#13#10 +
                'Connection: close'#13#10 +
                'Date: Thu, 19 Aug 1982 18:30:00 GMT'#13#10 +
                'Cache-Control: no-store'#13#10 +
                'Pragma: no-cache'#13#10 +
                'Content-Type: ' + RTSP_MIME + #13#10#13#10,
                [ExeVersion.ProgramName, ExeVersion.Version.DetailedOrVoid]));
              sock.fExpires := now + 60 * 15; // deprecated after 15 minutes
              sock.CloseSockIn; // we won't use it any more
              fPendingGet.AddObject(cookie, sock);
              sock := nil; // will be in fPendingGet until POST arrives
              result := true;
            end;
          end
          else if IdemPropNameU(sock.Method, 'POST') then
          begin
            if found < 0 then
            begin
              if log <> nil then
                log.Log(sllDebug, 'ConnectionCreate rejected on unknonwn %',
                  [sock], self)
            end
            else if not IdemPropNameU(sock.ContentType, RTSP_MIME) then
              PendingDelete(found, sock.ContentType)
            else
            begin
              get := fPendingGet.Objects[found];
              fPendingGet.Objects[found] := nil; // will be owned by rtspinstance
              fPendingGet.Delete(found);
              sock.Sock := TNetSocket(-1); // disable Close on sock.Free -> handled in pool
            end;
          end;
        finally
          fPendingGet.Safe.UnLock;
        end;
      end
      else if log <> nil then
        log.Log(sllDebug, 'ConnectionCreate: ignored invalid %', [sock], self);
    finally
      sock.Free;
    end;
    if get = nil then
      exit;
    if not get.SockConnected then
    begin
      if log <> nil then
        log.Log(sllDebug, 'ConnectionCreate: GET disconnected %',
          [get.Sock], self);
      exit;
    end;
    res := NewSocket(
      fRtspServer, fRtspPort, nlTCP, {bind=}false, 1000, 1000, 1000, 0, rtsp);
    if res <> nrOK then
      raise ERTSPOverHTTP.CreateUTF8('No RTSP server on %:% (%)',
        [fRtspServer, fRtspPort, ToText(res)^]);
    postconn := TPostConnection.Create(aRemoteIp);
    rtspconn := TRtspConnection.Create(aRemoteIp);
    if not inherited ConnectionAdd(aSocket, postconn) or
       not inherited ConnectionAdd(rtsp, rtspconn) then
      raise ERTSPOverHTTP.CreateUTF8('inherited %.ConnectionAdd(%) % failed',
        [self, aSocket, cookie]);
    aConnection := postconn;
    postconn.fRtspTag := rtspconn.Handle;
    rtspconn.fGetBlocking := get;
    if not fClients.Start(rtspconn) then
      exit;
    get := nil;
    result := true;
    if log <> nil then
      log.Log(sllTrace,
        'ConnectionCreate added get=% post=%/% and rtsp=%/% for %',
        [rtspconn.fGetBlocking.Sock, aSocket, aConnection.Handle, rtsp,
         rtspconn.Handle, cookie], self);
  except
    if log <> nil then
      log.Log(sllDebug, 'ConnectionCreate(%) failed', [aSocket], self);
    get.Free;
  end;
end;

procedure TRTSPOverHTTPServer.RegressionTests(test: TSynTestCase;
  clientcount, steps: integer);
type
  TReq = record
    get: THttpSocket;
    post: TCrtSocket;
    stream: TCrtSocket;
    session: RawUTF8;
  end;
var
  streamer: TCrtSocket;
  req: array of TReq;
  rmax, r, i: PtrInt;
  text: RawUTF8;
  log: ISynLog;
begin
  // here we follow the steps and content stated by https://goo.gl/CX6VA3
  log := fLog.Enter(self, 'Tests');
  if (self = nil) or
     (fRtspServer <> '127.0.0.1') then
    test.Check(false, 'expect a running proxy on 127.0.0.1')
  else
  try
    rmax := clientcount - 1;
    streamer := TCrtSocket.Bind(fRtspPort);
    try
      if log <> nil then
        log.Log(sllCustom1, 'RegressionTests % GET', [clientcount], self);
      SetLength(req, clientcount);
      for r := 0 to rmax do
        with req[r] do
        begin
          session := TSynTestCase.RandomIdentifier(20 + r and 15);
          get := THttpSocket.Open('localhost', fServer.Port);
          get.Write(
            'GET /sw.mov HTTP/1.0'#13#10 +
            'User-Agent: QTS (qtver=4.1;cpu=PPC;os=Mac 8.6)'#13#10 +
            'x-sessioncookie: ' + session + #13#10 +
            'Accept: ' + RTSP_MIME + #13#10 +
            'Pragma: no-cache'#13#10 +
            'Cache-Control: no-cache'#13#10#13#10);
          get.SockRecvLn(text);
          test.Check(text = 'HTTP/1.0 200 OK');
          get.GetHeader(false);
          test.Check(hfConnectionClose in get.HeaderFlags);
          test.Check(get.SockConnected);
          test.Check(get.ContentType = RTSP_MIME);
        end;
      if log <> nil then
        log.Log(sllCustom1, 'RegressionTests % POST', [clientcount], self);
      for r := 0 to rmax do
        with req[r] do
        begin
          post := TCrtSocket.Open('localhost', fServer.Port);
          post.Write('POST /sw.mov HTTP/1.0'#13#10 +
            'User-Agent: QTS (qtver=4.1;cpu=PPC;os=Mac 8.6)'#13#10 +
            'x-sessioncookie: ' + session + #13#10 +
            'Content-Type: ' + RTSP_MIME + #13#10 +
            'Pragma: no-cache'#13#10 +
            'Cache-Control: no-cache'#13#10 +
            'Content-Length: 32767'#13#10 +
            'Expires: Sun, 9 Jan 1972 00:00:00 GMT'#13#10#13#10);
          stream := streamer.AcceptIncoming;
          if stream = nil then
          begin
            test.Check(false);
            exit;
          end;
          test.Check(get.SockConnected);
          test.Check(post.SockConnected);
        end;
      for i := 0 to steps do
      begin
        if log <> nil then
          log.Log(sllCustom1, 'RegressionTests % RUN #%', [clientcount, i], self);
        // send a RTSP command once in a while to the POST request
        if i and 7 = 0 then
        begin
          for r := 0 to rmax do
            req[r].post.Write(
              'REVTQ1JJQkUgcnRzcDovL3R1Y2tydS5hcHBsZS5jb20vc3cubW92IFJUU1AvMS4w'#13#10 +
              'DQpDU2VxOiAxDQpBY2NlcHQ6IGFwcGxpY2F0aW9uL3NkcA0KQmFuZHdpZHRoOiAx'#13#10 +
              'NTAwMDAwDQpBY2NlcHQtTGFuZ3VhZ2U6IGVuLVVTDQpVc2VyLUFnZW50OiBRVFMg'#13#10 +
              'KHF0dmVyPTQuMTtjcHU9UFBDO29zPU1hYyA4LjYpDQoNCg==');
          for r := 0 to rmax do
            test.check(req[r].stream.SockReceiveString =
              'DESCRIBE rtsp://tuckru.apple.com/sw.mov RTSP/1.0'#13#10 +
              'CSeq: 1'#13#10 +
              'Accept: application/sdp'#13#10 +
              'Bandwidth: 1500000'#13#10 +
              'Accept-Language: en-US'#13#10 +
              'User-Agent: QTS (qtver=4.1;cpu=PPC;os=Mac 8.6)'#13#10#13#10);
        end;
        // stream output should be redirected to the GET request
        for r := 0 to rmax do
          req[r].stream.Write(req[r].session);
        for r := 0 to rmax do
          with req[r] do
            test.check(get.SockReceiveString = session);
      end;
      if log <> nil then
        log.Log(sllCustom1, 'RegressionTests % SHUTDOWN', [clientcount], self);
    finally
      // first half deletes POST first, second half deletes GET first
      for r := 0 to rmax shr 1 do
        req[r].post.Free;
      req[0].stream.Free; // validates remove POST when RTSP already down
      for r := (rmax shr 1) + 1 to rmax do
        req[r].get.Free;
      for r := 0 to rmax shr 1 do
        req[r].get.Free;
      for r := (rmax shr 1) + 1 to rmax do
        req[r].post.Free;
      Sleep(10); // warning: waits typically 10-15 ms on Windows
      for r := 1 to rmax do
        req[r].stream.Free;
      streamer.Free;
    end;
  except
    on E: Exception do
      test.Check(false, E.ClassName);
  end;
end;

function TRTSPOverHTTPServer.GetHttpPort: RawUTF8;
begin
  if self <> nil then
    result := fServer.Port
  else
    result := '';
end;

function TRTSPOverHTTPServer.RtspToHttp(const RtspURI: RawUTF8): RawUTF8;
var
  uri: TUri;
begin
  if (self <> nil) and
     IdemPChar(pointer(RtspURI), 'RTSP://') and
     uri.From(copy(RtspURI, 8, maxInt), fRtspPort) and
     IdemPropNameU(uri.Port, fRtspPort) then
    FormatUTF8('http://%:%/%', [uri.Server, fServer.Port, uri.Address], result)
  else
    result := RtspURI;
end;

function TRTSPOverHTTPServer.HttpToRtsp(const HttpURI: RawUTF8): RawUTF8;
var
  uri: TUri;
begin
  if (self <> nil) and
     uri.From(HttpURI, fServer.Port) and
     IdemPropNameU(uri.Port, fServer.Port) then
    FormatUTF8('rtsp://%:%/%', [uri.Server, fRtspPort, uri.Address], result)
  else
    result := HttpURI;
end;


end.
