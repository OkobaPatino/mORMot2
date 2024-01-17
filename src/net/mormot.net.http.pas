/// HTTP/HTTPS Abstract Process Classes and Definitions
// - this unit is a part of the Open Source Synopse mORMot framework 2,
// licensed under a MPL/GPL/LGPL three license - see LICENSE.md
unit mormot.net.http;

{
  *****************************************************************************

   HTTP/HTTPS Abstract Process Classes and Definitions
   - Shared HTTP Constants and Functions
   - Reusable HTTP State Machine
   - THttpSocket Implementing HTTP over plain sockets
   - Abstract Server-Side Types used e.g. for Client-Server Protocol
   - HTTP Server Logging/Monitoring Processors

  *****************************************************************************

}

interface

{$I ..\mormot.defines.inc}

uses
  sysutils,
  classes,
  mormot.core.base,
  mormot.core.os,
  mormot.core.unicode,
  mormot.core.text,
  mormot.core.rtti,
  mormot.core.buffers,
  mormot.core.datetime,
  mormot.core.data,
  mormot.core.zip,
  mormot.net.sock;


{ ******************** Shared HTTP Constants and Functions }

type
  /// event used to compress or uncompress some data during HTTP protocol
  // - should always return the protocol name for ACCEPT-ENCODING: header
  // e.g. 'gzip' or 'deflate' for standard HTTP format, but you can add
  // your own (like 'synlz')
  // - the data is compressed (if Compress=TRUE) or uncompressed (if
  // Compress=FALSE) in the Data variable (i.e. it is modified in-place)
  // - to be used with THttpSocket.RegisterCompress method
  THttpSocketCompress = function(var Data: RawByteString; Compress: boolean): RawUtf8;

  /// used to maintain a list of known compression algorithms
  THttpSocketCompressRec = record
    /// the compression name, as in ACCEPT-ENCODING: header (gzip,deflate,synlz)
    Name: RawUtf8;
    /// the function handling compression and decompression
    Func: THttpSocketCompress;
    /// the size in bytes after which compress will take place
    // - will be 1024 e.g. for 'zip' or 'deflate'
    // - could be 0 e.g. when encrypting the content, meaning "always compress"
    CompressMinSize: integer;
    /// a priority on which the compression is applied - highest is favored
    Priority: integer;
  end;

  /// list of known compression algorithms
  THttpSocketCompressRecDynArray = array of THttpSocketCompressRec;

  /// identify some items in a list of known compression algorithms
  // - filled from ACCEPT-ENCODING: header value
  THttpSocketCompressSet = set of 0..31;

  /// tune the 'synopsebin' protocol
  // - pboCompress will compress all frames payload using SynLZ
  // - pboNoLocalHostCompress won't compress frames on the loopback (127.0.0.1)
  // - pboNoLocalHostEncrypt won't encrypt frames on the loopback (127.0.0.1)
  TWebSocketProtocolBinaryOption = (
    pboSynLzCompress,
    pboNoLocalHostCompress,
    pboNoLocalHostEncrypt);

  /// how TWebSocketProtocolBinary implements the 'synopsebin' protocol
  // - should match on both client and server ends
  TWebSocketProtocolBinaryOptions = set of TWebSocketProtocolBinaryOption;

/// adjust HTTP body compression according to the supplied 'CONTENT-TYPE'
// - will detect most used compressible content (like 'text/*' or
// 'application/json') from OutContentType
procedure CompressContent(Accepted: THttpSocketCompressSet;
  const Handled: THttpSocketCompressRecDynArray; const OutContentType: RawUtf8;
  var OutContent: RawByteString; var OutContentEncoding: RawUtf8);

/// enable a give compression function for a HTTP link
function RegisterCompressFunc(var Comp: THttpSocketCompressRecDynArray;
  CompFunction: THttpSocketCompress; var AcceptEncoding: RawUtf8;
  CompMinSize, CompPriority: integer): RawUtf8;

/// decode 'CONTENT-ENCODING: ' parameter from registered compression list
function ComputeContentEncoding(const Compress: THttpSocketCompressRecDynArray;
  P: PUtf8Char): THttpSocketCompressSet;

/// search for a given compression function
function CompressIndex(const Compress: THttpSocketCompressRecDynArray;
  CompFunction: THttpSocketCompress): PtrInt;


/// compute the 'Authorization: Bearer ####' HTTP header of a given token value
function AuthorizationBearer(const AuthToken: RawUtf8): RawUtf8;

/// will remove most usual HTTP headers which are to be recomputed on sending
// - as used e.g. during TPublicRelay process from mormot.net.relay
function PurgeHeaders(const headers: RawUtf8): RawUtf8;

/// search, copy and remove a given HTTP header
// - FindNameValue() makes search&copy, but this function also REMOVES the header
procedure ExtractHeader(var headers: RawUtf8; const upname: RawUtf8;
  out res: RawUtf8);

/// 'HEAD' and 'OPTIONS' methods would be detected and return true
// - will check only the first four chars for efficiency
function HttpMethodWithNoBody(const method: RawUtf8): boolean;
  {$ifdef HASINLINE} inline; {$endif}

/// encode some text into a mime header compatible value
// - see https://tools.ietf.org/html/rfc2047
function MimeHeaderEncode(const header: RawUtf8): RawUtf8;

/// quick check for case-sensitive 'GET' HTTP method name
// - see also HttpMethodWithNoBody()
function IsGet(const method: RawUtf8): boolean;
  {$ifdef HASINLINE} inline; {$endif}

/// quick check for case-sensitive 'HEAD' HTTP method name
// - see also HttpMethodWithNoBody()
function IsHead(const method: RawUtf8): boolean;
  {$ifdef HASINLINE} inline; {$endif}

/// quick check for case-sensitive 'POST' HTTP method name
function IsPost(const method: RawUtf8): boolean;
  {$ifdef HASINLINE} inline; {$endif}

/// quick check for case-sensitive 'PUT' HTTP method name
function IsPut(const method: RawUtf8): boolean;
  {$ifdef HASINLINE} inline; {$endif}

/// quick check for case-sensitive 'DELETE' HTTP method name
function IsDelete(const method: RawUtf8): boolean;
  {$ifdef HASINLINE} inline; {$endif}

/// quick check for case-sensitive 'OPTIONS' HTTP method name
function IsOptions(const method: RawUtf8): boolean;
  {$ifdef HASINLINE} inline; {$endif}

/// could be used e.g. in OnBeforeBody() callback to allow a GET /favicon.ico
function IsUrlFavIcon(P: PUtf8Char): boolean;
  {$ifdef HASINLINE} inline; {$endif}

/// naive detection of most used bots from a HTTP User-Agent string
// - meant to be fast, with potentially a lot of false negatives: please do not
// hesitate to send us feedback as pull requests
function IsHttpUserAgentBot(const UserAgent: RawUtf8): boolean;

/// decode a given parameter from an Url, in any position, into UTF-8 text
// - P^ should be either nil or point to P^ = '?'
// - UpperName should follow the UrlDecodeValue() format, e.g. 'NAME='
function UrlDecodeParam(P: PUtf8Char; const UpperName: RawUtf8;
  out Value: RawUtf8): boolean; overload;

/// decode a given parameter from an Url, in any position, into a 32-bit cardinal
// - UpperName should follow the UrlDecodeCardinal() format, e.g. 'COUNT='
function UrlDecodeParam(P: PUtf8Char; const UpperName: RawUtf8;
  out Value: cardinal): boolean; overload;

/// decode a given parameter from an Url, in any position, into a 64-bit Int64
// - UpperName should follow the UrlDecodeInt64() format, e.g. 'ID='
function UrlDecodeParam(P: PUtf8Char; const UpperName: RawUtf8;
  out Value: Int64): boolean; overload;

/// extract a 64-bit value from a 'Range: xxx-xxx ' input
// - returned P^ points to the first non digit char - not as GetNextItemQWord()
function GetNextRange(var P: PUtf8Char): Qword;

const
  /// pseudo-header containing the current Synopse mORMot framework version
  XPOWEREDNAME = 'X-Powered-By';

  /// the full text of the current Synopse mORMot framework version
  // - we don't supply full version number with build revision
  // (as SYNOPSE_FRAMEWORK_VERSION), to reduce potential attacker knowledge
  XPOWEREDVALUE = SYNOPSE_FRAMEWORK_NAME + ' 2';


{ ******************** Reusable HTTP State Machine }

type
  /// the machine states of THttpRequestContext processing
  THttpRequestState = (
    hrsNoStateMachine,
    hrsGetCommand,
    hrsGetHeaders,
    hrsGetBodyChunkedHexFirst,
    hrsGetBodyChunkedHexNext,
    hrsGetBodyChunkedData,
    hrsGetBodyChunkedDataVoidLine,
    hrsGetBodyChunkedDataLastLine,
    hrsGetBodyContentLength,
    hrsWaitProcessing,
    hrsWaitAsyncProcessing,
    hrsSendBody,
    hrsResponseDone,
    hrsUpgraded,
    hrsErrorPayloadTooLarge,
    hrsErrorRejected,
    hrsErrorMisuse,
    hrsErrorUnsupportedFormat,
    hrsErrorUnsupportedRange,
    hrsErrorAborted,
    hrsErrorShutdownInProgress);

  /// set of states for THttpRequestContext processing
  THttpRequestStates = set of THttpRequestState;

  /// customize THttpRequestContext process
  THttpRequestOptions = set of (
    hroHeadersUnfiltered);

  /// map the presence of some HTTP headers for THttpRequestContext.HeaderFlags
  // - separated from THttpRequestReponseFlags so that they would both be stored
  // and accessed as a single byte - which is faster than word on Intel CPUs
  // - do not modify unless you fix the associated ToText() overloaded function
  THttpRequestHeaderFlags = set of (
    nfHeadersParsed,
    hfTransferChunked,
    hfConnectionClose,
    hfConnectionUpgrade,
    hfConnectionKeepAlive,
    hfExpect100,
    hfHasRemoteIP,
    hfHasAuthorization);

  /// map the output state for THttpRequestContext.ResponseFlags
  // - separated from THttpRequestHeaderFlags so that they would both be stored
  // and accessed as a single byte - which is faster than word on Intel CPUs
  THttpRequestReponseFlags = set of (
    rfAcceptRange,
    rfWantRange,
    rfRange,
    rfHttp10,
    rfContentStreamNeedFree,
    rfAsynchronous);

  PHttpRequestContext = ^THttpRequestContext;

  /// raw information used during THttpRequestContext header parsing
  TProcessParseLine = record
    P: PUtf8Char;
    Len: PtrInt;
    Line: PUtf8Char;
    LineLen: PtrInt;
  end;

  /// low-level reusable State Machine to parse and process any HTTP content
  // - shared e.g. by all our (web)socket-based HTTP client and server classes
  // - reduce memory allocations as much as possible, and parse the most used
  // headers in explicit fields
  {$ifdef USERECORDWITHMETHODS}
  THttpRequestContext = record
  {$else}
  THttpRequestContext = object
  {$endif USERECORDWITHMETHODS}
  private
    ContentLeft: Int64;
    ContentPos: PByte;
    ContentEncoding, CommandUriInstance, LastHost: RawUtf8;
    CommandUriInstanceLen: PtrInt;
    procedure SetRawUtf8(var res: RawUtf8; P: pointer; PLen: PtrInt;
      nointern: boolean);
    function ProcessParseLine(var st: TProcessParseLine): boolean;
      {$ifdef HASINLINE} inline; {$endif}
    procedure GetTrimmed(P, P2: PUtf8Char; L: PtrInt; var result: RawUtf8;
      nointern: boolean = false);
      {$ifdef HASINLINE} inline; {$endif}
    function ValidateRange: boolean;
  public
    // reusable buffers for internal process - do not use
    Head, Process: TRawByteStringBuffer;
    /// the current state of this HTTP context
    State: THttpRequestState;
    /// map the presence of some HTTP headers, retrieved during ParseHeader
    HeaderFlags: THttpRequestHeaderFlags;
    /// some flags used when sending the response
    ResponseFlags: THttpRequestReponseFlags;
    /// customize the HTTP process
    Options: THttpRequestOptions;
    /// could be set so that ParseHeader/GetTrimmed will intern RawUtf8 values
    Interning: PRawUtf8InterningSlot;
    /// will contain the first header line on client side
    // - 'HTTP/1.0 200 OK' for a GET response after Get() e.g.
    // - THttpServerSocket will use it, but THttpAsyncServer won't
    CommandResp: RawUtf8;
    /// the HTTP method parsed from first header line, e.g. 'GET'
    CommandMethod: RawUtf8;
    /// the HTTP URI parsed from first header line, e.g. '/path/to/resource'
    CommandUri: RawUtf8;
    /// will contain all header lines after all ParseHeader
    // - use HeaderGetValue() to get one HTTP header item value by name
    Headers: RawUtf8;
    /// same as HeaderGetValue('CONTENT-TYPE'), but retrieved during ParseHeader
    ContentType: RawUtf8;
    /// same as HeaderGetValue('ACCEPT-ENCODING'), but retrieved during ParseHeader
    AcceptEncoding: RawUtf8;
    /// same as HeaderGetValue('HOST'), but retrieved during ParseHeader
    Host: RawUtf8;
    /// same as HeaderGetValue('USER-AGENT'), but retrieved during ParseHeader
    UserAgent: RawUtf8;
    /// same as HeaderGetValue('UPGRADE'), but retrieved during ParseHeader
    Upgrade: RawUtf8;
    /// same as HeaderGetValue('REFERER'), but retrieved during ParseHeader
    Referer: RawUtf8;
    /// same as FindNameValue(aInHeaders, HEADER_BEARER_UPPER, ...),
    // but retrieved during ParseHeader
    // - is the raw Token, excluding 'Authorization: Bearer ' trailing chars
    // - if hsrAuthorized is set, THttpServerSocketGeneric.Authorization() will
    // put the authenticated User name in this field
    BearerToken: RawUtf8;
    /// decoded 'Range: bytes=..' start value - default is 0
    // - e.g. 1024 for 'Range: bytes=1024-1025'
    // - equals -1 in case on unsupported multipart range requests
    RangeOffset: Int64;
    /// decoded 'Range: bytes=...' end value - default is -1 (until end of file)
    // - e.g. 2 for 'Range: bytes=1024-1025'
    // - e.g. -1 for 'Range: bytes=1024-'
    // - contains size for CompressContentAndFinalizeHead Content-Range: header
    RangeLength: Int64;
    /// will contain the data retrieved from the server, after all ParseHeader
    Content: RawByteString;
    /// same as HeaderGetValue('CONTENT-LENGTH'), but retrieved during ParseHeader
    // - is overridden with real Content length during HTTP body retrieval
    ContentLength: Int64;
    /// stream-oriented alternative to the Content in-memory buffer
    // - is typically a TFileStreamEx
    ContentStream: TStream;
    /// same as HeaderGetValue('SERVER-INTERNALSTATE'), but retrieved by ParseHeader
    // - proprietary header, used with our RESTful ORM access
    ServerInternalState: integer;
    /// the known Content-Encoding compression methods
    Compress: THttpSocketCompressRecDynArray;
    /// supported Content-Encoding compression methods as sent to the other side
    CompressAcceptEncoding: RawUtf8;
    /// index of protocol in Compress[], from Accept-encoding
    CompressAcceptHeader: THttpSocketCompressSet;
    /// same as HeaderGetValue('CONTENT-ENCODING'), but retrieved by ParseHeader
    // and mapped into the Compress[] array
    CompressContentEncoding: integer;
    /// reset this request context to be used without any ProcessInit/Read/Write
    procedure Clear;
    /// parse a HTTP header text line into Header and fill internal properties
    // - with default HeadersUnFiltered=false, only relevant headers are retrieved:
    // use directly the ContentLength/ContentType/ServerInternalState/Upgrade
    // and HeaderFlags fields since HeaderGetValue() would return ''
    // - force HeadersUnFiltered=true to store all headers including the
    // connection-related fields, but increase memory and reduce performance
    procedure ParseHeader(P: PUtf8Char; PLen: PtrInt;
      HeadersUnFiltered: boolean = false);
    /// to be called once all ParseHeader lines have been done to fill Headers
    // - also set CompressContentEncoding/CompressAcceptHeader from Compress[]
    // and Content-Encoding header value
    procedure ParseHeaderFinalize;
    /// parse Command into CommandMethod/CommandUri fields
    function ParseCommand: boolean;
    /// search a value from the internal parsed Headers
    // - supplied aUpperName should be already uppercased:
    // HeaderGetValue('CONTENT-TYPE')='text/html', e.g.
    // - note that GetHeader(HeadersUnFiltered=false) will set ContentType field
    // but let HeaderGetValue('CONTENT-TYPE') return ''
    function HeaderGetValue(const aUpperName: RawUtf8): RawUtf8;
      {$ifdef HASINLINE} inline; {$endif}
    /// search if a value exists from the internal parsed Headers
    function HeaderHasValue(const aUpperName: RawUtf8): boolean;
      {$ifdef HASINLINE} inline; {$endif}
    /// initialize ContentStream/ContentLength from a given file name
    // - if CompressGz is set, would also try for a cached local FileName+'.gz'
    function ContentFromFile(const FileName: TFileName; CompressGz: integer): boolean;
    /// uncompress Content according to CompressContentEncoding header
    procedure UncompressData;
    /// (re)initialize the HTTP Server state machine for ProcessRead/ProcessWrite
    procedure ProcessInit(InStream: TStream);
      {$ifdef HASINLINE} inline; {$endif}
    /// receiving socket entry point of our asynchronous HTTP Server
    // - to be called with the incoming bytes from the socket receive buffer
    // - caller should have checked that current State is in HTTP_REQUEST_READ
    // - returns true if a new State was reached, or false if some more
    // input is needed
    function ProcessRead(var st: TProcessParseLine): boolean;
    /// compress Content according to CompressAcceptHeader, adding headers
    // - e.g. 'Content-Encoding: synlz' header if compressed using synlz
    // - and if Content is not '', will add 'Content-Type: ' header
    // - always compute ContentLength and add a 'Content-Length: ' header
    // - then append small content (<MaxSizeAtOnce) to result if possible, and
    // refresh the final State to hrsSendBody/hrsResponseDone
    function CompressContentAndFinalizeHead(MaxSizeAtOnce: integer): PRawByteStringBuffer;
    /// body sending socket entry point of our asynchronous HTTP Server
    // - to be called when some bytes could be written to output socket
    procedure ProcessBody(var Dest: TRawByteStringBuffer; MaxSize: PtrInt);
    /// should be done when the HTTP Server state machine is done
    // - will check and process hfContentStreamNeedFree flag
    procedure ProcessDone;
      {$ifdef HASINLINE} inline; {$endif}
  end;

const
  /// when THttpRequestContext.State is expected some ProcessRead() data
  HTTP_REQUEST_READ =
    [hrsGetCommand,
     hrsGetHeaders,
     hrsGetBodyChunkedHexFirst,
     hrsGetBodyChunkedHexNext,
     hrsGetBodyChunkedData,
     hrsGetBodyChunkedDataVoidLine,
     hrsGetBodyContentLength];

  /// when THttpRequestContext.State is expected some ProcessWrite() data
  HTTP_REQUEST_WRITE =
    [hrsSendBody];


function ToText(st: THttpRequestState): PShortString; overload;
function ToText(hf: THttpRequestHeaderFlags): TShort8; overload;
function ToText(csp: TCrtSocketPending): PShortString; overload;
function ToText(tls: TCrtSocketTlsAfter): PShortString; overload;
function ToText(mak: TMacAddressKind): PShortString; overload;


{ ******************** THttpSocket Implementing HTTP over plain sockets }

type
  /// exception class raised during HTTP process
  EHttpSocket = class(ESynException);

  /// parent of THttpClientSocket and THttpServerSocket classes
  // - contain properties for implementing HTTP/1.1 using the Socket API
  // - handle chunking of body content
  // - can optionaly compress and uncompress on the fly the data, with
  // standard gzip/deflate or custom (synlz) protocols
  THttpSocket = class(TCrtSocket)
  protected
    /// to call GetBody only once
    fBodyRetrieved: boolean;
    /// fill the internal state and flags to their default/void values
    procedure HttpStateReset;
    procedure CompressDataAndWriteHeaders(const OutContentType: RawUtf8;
      var OutContent: RawByteString; OutStream: TStream);
  public
    /// the whole context of the HTTP request
    Http: THttpRequestContext;
    /// retrieve the HTTP headers into Headers[] and fill most properties below
    // - with default HeadersUnFiltered=false, only relevant headers are retrieved:
    // use directly the ContentLength/ContentType/ServerInternalState/Upgrade
    // and HeaderFlags fields since HeaderGetValue() would return ''
    // - force HeadersUnFiltered=true to store all headers including the
    // connection-related fields, but increase memory and reduce performance
    function GetHeader(HeadersUnFiltered: boolean = false): boolean;
    /// retrieve the HTTP body (after uncompression if necessary)
    // - into Content or DestStream
    procedure GetBody(DestStream: TStream = nil);
    /// add an header 'name: value' entry
    procedure HeaderAdd(const aValue: RawUtf8);
    /// set all Header values at once, from CRLF delimited text
    // - won't parse the ContentLength/ContentType/ServerInternalState/Upgrade
    // and HeaderFlags fields
    procedure HeaderSetText(const aText: RawUtf8; const aForcedContentType: RawUtf8 = '');
    /// finalize all Http.Headers values
    // - you can optionally specify a value to be added as 'RemoteIP: ' header
    // - default GetHeader(HeadersUnFiltered=false) won't include the connection
    // related headers like ContentLength/ContentType/ServerInternalState/Upgrade
    procedure HeadersPrepare(const aRemoteIP: RawUtf8);
    /// HeaderGetValue('CONTENT-TYPE')='text/html', e.g.
    // - supplied aUpperName should be already uppercased
    // - note that GetHeader(HeadersUnFiltered=false) will set ContentType field
    // but let HeaderGetValue('CONTENT-TYPE') return ''
    function HeaderGetValue(const aUpperName: RawUtf8): RawUtf8;
      {$ifdef HASINLINE} inline; {$endif}
    /// will register a compression algorithm
    // - used e.g. to compress on the fly the data, with standard gzip/deflate
    // or custom (synlz) protocols
    // - returns true on success, false if this function or this
    // ACCEPT-ENCODING: header was already registered
    // - you can specify a minimal size (in bytes) before which the content won't
    // be compressed (1024 by default, corresponding to a MTU of 1500 bytes)
    // - the first registered algorithm will be the prefered one for compression
    // within each priority level (the lower aPriority first)
    function RegisterCompress(aFunction: THttpSocketCompress;
      aCompressMinSize: integer = 1024; aPriority: integer = 10): boolean;
  end;



{ ******************** Abstract Server-Side Types e.g. for Client-Server Protocol }

type
  {$M+} // to have existing RTTI for published properties
  THttpServerRequestAbstract = class;
  {$M-}

  /// a genuine identifier for a given client connection on server side
  // - maps e.g. http.sys ID, or a genuine 31-bit sequence increasing counter,
  // or the 'X-Conn-ID' header value behind a nginx reverse proxy
  THttpServerConnectionID = Int64;

  /// a dynamic array of client connection identifiers, e.g. for broadcasting
  THttpServerConnectionIDDynArray = array of THttpServerConnectionID;

  /// an opaque connection-specific pointers identifier with a strong type
  // - each THttpAsyncConnection or THttpServerSocket raw connection instance
  // maintains those two abstract PtrUInt tags, as a fConnectionOpaque field
  // - match TRestServerConnectionOpaque as defined in mormot.rest.core
  THttpServerConnectionOpaque = record
    /// pointer-sized tag reserved to mORMot (e.g. to idenfity a REST session)
    ValueInternal: PtrUInt;
    /// pointer-sized tag free for the end-user code
    // - could be used to avoid a lookup to a ConnectionID-indexed dictionary
    ValueExternal: PtrUInt;
  end;
  /// reference to an opaque connection-specific pointer identifier
  // - may be nil if unsupported, e.g. by the http.sys servers
  PHttpServerConnectionOpaque = ^THttpServerConnectionOpaque;

  /// the server-side available authentication schemes
  // - as used by THttpServerRequest.AuthenticationStatus
  // - hraNone..hraKerberos will match low-level HTTP_REQUEST_AUTH_TYPE enum as
  // defined in HTTP 2.0 API
  THttpServerRequestAuthentication = (
    hraNone,
    hraFailed,
    hraBasic,
    hraDigest,
    hraNtlm,
    hraNegotiate,
    hraKerberos);

  /// available THttpServerRequest connection attributes
  // - hsrHttps is set if the communication was made over HTTPS
  // - hsrSecured if the transmission is encrypted or in-process, using
  // e.g. HTTPS/TLS or our proprietary AES/ECDHE algorithm over WebSockets
  // - hsrWebsockets if communication was made using WebSockets
  // - hsrInProcess when run from the same process, i.e. on server side
  // - hsrConnectionUpgrade when "connection: upgrade" appears within headers
  // - hsrAuthorized when a valid "authorization:" header is set (and
  // THttpRequestContext.BearerToken is filled with the authorized User)
  // - hsrHttp10 is set if the connection is of old HTTP/1.0 level
  // - should exactly match TRestUriParamsLowLevelFlag in mormot.rest.core
  THttpServerRequestFlag = (
    hsrHttps,
    hsrSecured,
    hsrWebsockets,
    hsrInProcess,
    hsrConnectionUpgrade,
    hsrAuthorized,
    hsrHttp10);

  /// the THttpServerRequest connection attributes
  THttpServerRequestFlags = set of THttpServerRequestFlag;

  /// event handler used by THttpServerGeneric.OnRequest, OnBeforeRequest and
  // OnAfterRequest
  // - Ctxt defines both input and output parameters
  // - result of the function is the HTTP status/error code (200 if OK, e.g.)
  TOnHttpServerRequest = function(Ctxt: THttpServerRequestAbstract): cardinal of object;

  /// raw parameter type of TOnHttpServerAfterResponse
  // - THttpServerRequest instance has already been reset in mormot.net.async
  // - we use such a record with pointer fields to minimize the stack size
  // and avoid any ref-count when passing RawUtf8 values between event callbacks
  TOnHttpServerAfterResponseContext = record
    User, Method, Host, Url, Referer, UserAgent, RemoteIP: pointer; // = RawUtf8
    Connection: THttpServerConnectionID;
    Flags: THttpServerRequestFlags;
    StatusCode: cardinal;
    ElapsedMicroSec: Int64;
    Received, Sent: QWord;
  end;

  /// event handler used by THttpServerGeneric.OnAfterResponse property
  // - main purpose is to apply post-response e.g. logging or real-time analysis
  // using THttpAfterResponse classes (e.g. THttpLogger or THttpAnalyzer)
  TOnHttpServerAfterResponse = procedure(
    const Context: TOnHttpServerAfterResponseContext) of object;

  /// event handler used by THttpServerGeneric.OnBeforeBody property
  // - if defined, is called just before the body is retrieved from the client
  // - supplied parameters reflect the current input state, and could be
  // modified on the fly to adapt to the expected behavior
  // - aBearerToken is either the "Authorization: Bearer xxxx" token, or
  // the authenticated user name if the hsrAuthorized flag is set
  // - should return HTTP_SUCCESS=200 to continue the process, or an HTTP error
  // code (e.g. HTTP_FORBIDDEN or HTTP_PAYLOADTOOLARGE) to reject the request
  // - returning HTTP_UNAUTHORIZED triggers the internal authentication process
  // available on some servers (e.g. THttpApiServer or THttpAsyncServer)
  TOnHttpServerBeforeBody = function(var aUrl, aMethod, aInHeaders,
    aInContentType, aRemoteIP, aBearerToken: RawUtf8; aContentLength: Int64;
    aFlags: THttpServerRequestFlags): cardinal of object;

  /// event handler used by THttpServer.Process to send a local file
  // when STATICFILE_CONTENT_TYPE content-type is returned by the service
  // - can be defined e.g. to use NGINX X-Accel-Redirect header
  // - should return true if the Context has been modified to serve the file, or
  // false so that the file will be manually read and sent from memory
  // - any exception during process will be returned as a HTTP_NOTFOUND page
  TOnHttpServerSendFile = function(Context: THttpServerRequestAbstract;
    const LocalFileName: TFileName): boolean of object;

  {$M+}
  /// abstract generic input/output structure used for HTTP server requests
  // - URL/Method/InHeaders/InContent properties are input parameters
  // - OutContent/OutContentType/OutCustomHeader are output parameters
  // - this abstract class may be used in communication protocols, without
  // the need to add mormot.net.server.pas dependency
  THttpServerRequestAbstract = class
  protected
    fRemoteIP,
    fUrl,
    fMethod,
    fInHeaders,
    fInContentType,
    fAuthenticatedUser,
    fHost,
    fAuthBearer,
    fUserAgent,
    fOutContentType,
    fOutCustomHeaders,
    fRespReason: RawUtf8;
    fInContent,
    fOutContent: RawByteString;
    fConnectionID: THttpServerConnectionID;
    fConnectionFlags: THttpServerRequestFlags;
    fAuthenticationStatus: THttpServerRequestAuthentication;
    fRespStatus: integer;
    fConnectionThread: TThread;
    fConnectionOpaque: PHttpServerConnectionOpaque;
    fUrlParamPos: PUtf8Char; // may be set by TUriTreeNode.LookupParam
    fRouteNode: TRadixTreeNodeParams; // is a TUriTreeNode
    fRouteName: pointer; // set by TUriTreeNode.LookupParam
    fRouteValuePosLen: TIntegerDynArray; // [pos1,len1,...] pairs in fUri
    function GetRouteValuePosLen(const Name: RawUtf8;
      var Value: TValuePUtf8Char): boolean;
    function GetRouteValue(const Name: RawUtf8): RawUtf8;
      {$ifdef HASINLINE} inline; {$endif}
  public
    /// prepare an incoming request from a parsed THttpRequestContext
    // - will set input parameters URL/Method/InHeaders/InContent/InContentType
    // - won't reset other parameters: should come after a plain Create or
    // an explicit THttpServerRequest.Recycle()
    procedure Prepare(const aHttp: THttpRequestContext; const aRemoteIP: RawUtf8;
      aAuthorize: THttpServerRequestAuthentication); overload;
    /// prepare an incoming request from explicit values
    // - could be used for non-HTTP execution, e.g. from a WebSockets link
    procedure Prepare(const aUrl, aMethod, aInHeaders: RawUtf8;
      const aInContent: RawByteString; const aInContentType, aRemoteIP: RawUtf8); overload;
      {$ifdef HASINLINE} inline; {$endif}
    /// append some lines to the InHeaders input parameter
    procedure AddInHeader(AppendedHeader: RawUtf8);
    /// append some values to the OutCustomHeaders output parameter
    // - will maintain CRLF between lines, but not on the last line
    procedure AddOutHeader(const Values: array of const);
    /// input parameter containing the caller message body
    // - e.g. some GET/POST/PUT JSON data can be specified here
    property InContent: RawByteString
      read fInContent write fInContent;
    /// output parameter to be set to the response message body
    property OutContent: RawByteString
      read fOutContent write fOutContent;
    /// the thread which owns the connection of this execution context
    // - may be nil, depending on the HTTP server used
    // - depending on the HTTP server used, may not follow ConnectionID
    property ConnectionThread: TThread
      read fConnectionThread;
    /// some HTTP servers support a per-connection pointer storage
    // - may be nil if unsupported, e.g. by the http.sys servers
    // - could be used to avoid a lookup to a ConnectionID-indexed dictionary
    property ConnectionOpaque: PHttpServerConnectionOpaque
      read fConnectionOpaque;
    /// returns the TUriRouter <parameter> value parsed from URI as text
    // - Name lookup is case-sensitive
    // - is the default property to this function, so that you could write
    // ! Ctxt['param']
    property RouteValue[const Name: RawUtf8]: RawUtf8
      read GetRouteValue; default;
    /// returns the TUriRouter <parameter> value parsed from URI as Int64
    // - Name lookup is case-sensitive
    function RouteInt64(const Name: RawUtf8; out Value: Int64): boolean;
    /// returns the TUriRouter <parameter> value parsed from URI as RawUtf8
    // - Name lookup is case-sensitive
    function RouteUtf8(const Name: RawUtf8; out Value: RawUtf8): boolean;
    /// check a TUriRouter <parameter> value parsed from URI
    // - both Name lookup and value comparison are case-sensitive
    function RouteEquals(const Name, ExpectedValue: RawUtf8): boolean;
    /// retrieve and decode an URI-encoded parameter as UTF-8 text
    // - UpperName should follow the UrlDecodeValue() format, e.g. 'NAME='
    function UrlParam(const UpperName: RawUtf8; out Value: RawUtf8): boolean; overload;
    /// retrieve and decode an URI-encoded parameter as 32-bit unsigned cardinal
    // - UpperName should follow the UrlDecodeCardinal() format, e.g. 'COUNT='
    function UrlParam(const UpperName: RawUtf8; out Value: cardinal): boolean; overload;
    /// retrieve and decode an URI-encoded parameter as 64-bit signed Int64
    // - UpperName should follow the UrlDecodeInt64() format, e.g. 'ID='
    function UrlParam(const UpperName: RawUtf8; out Value: Int64): boolean; overload;
    /// set the OutContent and OutContentType fields with the supplied JSON
    procedure SetOutJson(const Json: RawUtf8); overload;
      {$ifdef HASINLINE} inline; {$endif}
    /// set the OutContent and OutContentType fields with the supplied JSON
    procedure SetOutJson(const Fmt: RawUtf8; const Args: array of const); overload;
    /// set the OutContent and OutContentType fields with the supplied text
    procedure SetOutText(const Fmt: RawUtf8; const Args: array of const;
      const ContentType: RawUtf8 = TEXT_CONTENT_TYPE);
  published
    /// input parameter containing the caller URI
    property Url: RawUtf8
      read fUrl write fUrl;
    /// input parameter containing the caller method (GET/POST...)
    property Method: RawUtf8
      read fMethod write fMethod;
    /// input parameter containing the caller message headers
    property InHeaders: RawUtf8
      read fInHeaders write fInHeaders;
    // input parameter defining the caller message body content type
    property InContentType: RawUtf8
      read fInContentType write fInContentType;
    /// output HTTP response status
    property RespStatus: integer
      read fRespStatus write fRespStatus;
    /// output parameter to define the reponse message body content type
    // - if OutContentType is STATICFILE_CONTENT_TYPE (i.e. '!STATICFILE'),
    // then OutContent is the UTF-8 file name of a file to be sent to the
    // client via http.sys or NGINX's X-Accel-Redirect header (faster than
    // local buffering/sending)
    // - if OutContentType is NORESPONSE_CONTENT_TYPE (i.e. '!NORESPONSE'), then
    // the actual transmission protocol may not wait for any answer - used
    // e.g. for WebSockets
    property OutContentType: RawUtf8
      read fOutContentType write fOutContentType;
    /// output parameter to be sent back as the response message header
    // - e.g. to set Content-Type/Location
    property OutCustomHeaders: RawUtf8
      read fOutCustomHeaders write fOutCustomHeaders;
    /// the client remote IP, as specified to Prepare()
    property RemoteIP: RawUtf8
      read fRemoteIP write fRemoteIP;
    /// the "Host" HTTP header token, as specified to Prepare()
    property Host: RawUtf8
      read fHost write fHost;
    /// the "Bearer" HTTP header token, as specified to Prepare()
    property AuthBearer: RawUtf8
      read fAuthBearer write fAuthBearer;
    /// the "User-Agent" HTTP header token, as specified to Prepare()
    property UserAgent: RawUtf8
      read fUserAgent write fUserAgent;
    /// the ID of the connection which called this execution context
    // - e.g. mormot.net.websocket's TWebSocketProcess.NotifyCallback method
    // would use this property to specify the client connection to be notified
    // - is set as an Int64 to match http.sys ID type, but will be an
    // increasing 31-bit integer sequence for (web)socket-based servers
    property ConnectionID: THttpServerConnectionID
      read fConnectionID;
    /// define how the client is connected
    property ConnectionFlags: THttpServerRequestFlags
      read fConnectionFlags write fConnectionFlags;
    /// contains the THttpServer-side authentication status
    // - e.g. when using http.sys authentication with HTTP API 2.0
    property AuthenticationStatus: THttpServerRequestAuthentication
      read fAuthenticationStatus write fAuthenticationStatus;
    /// contains the THttpServer-side authenticated user name, UTF-8 encoded
    // - e.g. when using http.sys authentication with HTTP API 2.0, the
    // domain user name is retrieved from the supplied AccessToken
    // - could also be set by the THttpServerGeneric.Request() method, after
    // proper authentication, so that it would be logged as expected
    property AuthenticatedUser: RawUtf8
      read fAuthenticatedUser write fAuthenticatedUser;
  end;
  {$M-}

  /// store a list of IPv4 which should be rejected at connection
  // - more tuned than TIPBan for checking just after accept()
  // - used e.g. to implement hsoBan40xIP or THttpPeerCache instable
  // peers list (with a per-minute resolution)
  // - the DoRotate method should be called every second
  THttpAcceptBan = class(TSynPersistent)
  protected
    fSafe: TOSLightLock; // almost never on contention, no R/W needed
    fCount, fLastSec: integer;
    fIP: array of TCardinalDynArray; // one [0..fMax] IP array per second
    fSeconds, fMax, fWhiteIP: cardinal;
    fRejected, fTotal: Int64;
    function IsBannedRaw(ip4: cardinal): boolean;
    procedure SetMax(Value: cardinal);
    procedure SetSeconds(Value: cardinal);
    procedure SetIP;
  public
    /// initialize the thread-safe storage process
    // - banseconds should be a power-of-two <= 128
    // - maxpersecond is the maximum number of banned IPs remembered per second
    constructor Create(banseconds: cardinal = 4; maxpersecond: cardinal = 1024;
      banwhiteip: cardinal = cLocalhost32); reintroduce;
    /// finalize this storage
    destructor Destroy; override;
    /// register an IP4 to be rejected
    function BanIP(ip4: cardinal): boolean; overload;
    /// register an IP4 to be rejected
    function BanIP(const ip4: RawUtf8): boolean; overload;
      {$ifdef HASINLINE} inline; {$endif}
    /// fast check if this IP4 is to be rejected
    function IsBanned(const addr: TNetAddr): boolean; overload;
      {$ifdef HASINLINE} inline; {$endif}
    /// fast check if this IP4 is to be rejected
    function IsBanned(ip4: cardinal): boolean; overload;
      {$ifdef HASINLINE} inline; {$endif}
    /// register an IP4 if status in >= 400 (but not 401 HTTP_UNAUTHORIZED)
    function ShouldBan(status, ip4: cardinal): boolean; overload;
      {$ifdef HASINLINE} inline; {$endif}
    /// register an IP4 if status in >= 400 (but not 401 HTTP_UNAUTHORIZED)
    function ShouldBan(status: cardinal; const ip4: RawUtf8): boolean; overload;
      {$ifdef HASINLINE} inline; {$endif}
    /// to be called every second to remove deprecated bans from the list
    // - implemented via a round-robin list of per-second banned IPs
    // - if you call it at another pace (e.g. every minute), then the list
    // Time-To-Live will follow this unit of time instead of seconds
    procedure DoRotate;
    /// a 32-bit IP4 which should never be banned
    // - is set to cLocalhost32, i.e. 127.0.0.1, by default
    property WhiteIP: cardinal
      read fWhiteIP write fWhiteIP;
    /// how many seconds a banned IP4 should be rejected
    // - should be a power of two, up to 128, with a default of 4 - the closed
    // power of two is selected if the Value is not an exact match
    // - if set, any previous banned IP will be flushed
    property Seconds: cardinal
      read fSeconds write SetSeconds;
    /// how many IP can be banned per second
    // - used to reduce memory allocation and O(n) search speed
    // - over this limit, BanIP() will store and replace at the last position
    // - assign 0 to disable the banning feature
    // - if set, any previous banned IP will be flushed
    property Max: cardinal
      read fMax write SetMax;
  published
    /// total number of accept() rejected by IsBanned()
    property Rejected: Int64
      read fRejected;
    /// total number of banned IP4 since the beginning
    property Total: Int64
      read fTotal;
    /// current number of banned IP4
    property Count: integer
      read fCount;
  end;

type
  /// most used tuning options for a modern and safe HTTP/HTTPS Server
  // - over the years, a lot of expectations where added to the basic behavior
  // of a HTTP server, e.g. for better security or interoperability: we define
  // a set of well-known behaviors
  // - flags used e.g. by TWebServerLocal, or mORMot 2 Boilerplate project
  TWebServerBehavior = (

    /// Allow cross-origin requests.
    // - see https://enable-cors.org https://www.w3.org/TR/cors
    // https://developer.mozilla.org/en-US/docs/Web/HTTP/Access_control_CORS
    // - Warning: Do not use this without understanding the consequences.
    // This will permit access from any other website.
    // Instead of using this file, consider using a specific rule such as
    // allowing access based on (sub)domain: "subdomain.example.com"
    wsbAllowCrossOrigin,

    /// Send the CORS header for images when browsers request it
    // - see
    // https://developer.mozilla.org/en-US/docs/Web/HTML/CORS_enabled_image
    // https://blog.chromium.org/2011/07/using-cross-domain-images-in-webgl-and.html
    // - use TWebServerLocal.FileTypesImage to specify the actual file types
    wsbAllowCrossOriginImages,

    /// Allow cross-origin access to web fonts
    // - see https://developers.google.com/fonts/docs/troubleshooting
    // - use TWebServerLocal.FileTypesFont to specify file types
    wsbAllowCrossOriginFonts,

    /// Allow cross-origin access to the timing information for all resources
    // - If a resource isn't served with a 'Timing-Allow-Origin' header that would
    // allow its timing information to be shared with the document, some of the
    // attributes of the 'PerformanceResourceTiming' object will be set to zero.
    // - see https://www.w3.org/TR/resource-timing/
    // https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Timing-Allow-Origin
    // https://www.stevesouders.com/blog/2014/08/21/resource-timing-practical-tips/
    wsbAllowCrossOriginTiming,

    /// Set content for HTTP 400 "Bad Request" response code equals to '/404'
    wsbDelegateBadRequestTo404,

    /// Set content for HTTP 401 "Unauthorized" response code equals to '/404'
    wsbDelegateUnauthorizedTo404,

    /// Set content for HTTP 403 "Forbidden" response code equals to '/404'
    wsbDelegateForbiddenTo404,

    /// Set content for HTTP 404 "Not Found" response code equals to '/404'
    wsbDelegateNotFoundTo404,

    /// Set content for HTTP 405 "Not Allowed" response code equals to '/404'
    wsbDelegateNotAllowedTo404,

    /// Set content for HTTP 406 "Not Acceptable" response code equals to '/404'
    wsbDelegateNotAcceptableTo404,

    /// Set Internet Explorer XUA Document mode
    // - Force Internet Explorer 8/9/10 to render pages in the highest mode
    // available in various cases when it may not.
    // - Warning: since Internet Explorer 11, document modes are deprecated.
    // If your business still relies on older web apps and services that were
    // designed for older versions of Internet Explorer, you might want to
    // consider enabling 'Enterprise Mode' throughout your company.
    // - see https://hsivonen.fi/doctype/#ie8
    // https://msdn.microsoft.com/en-us/library/ie/bg182625.aspx#docmode
    // https://blogs.msdn.microsoft.com/ie/2014/04/02/stay-up-to-date-with-enterprise-mode-for-internet-explorer-11/
    // https://msdn.microsoft.com/en-us/library/ff955275.aspx
    wsbSetXuaCompatible,

    // Serve resources with the proper media types (f.k.a. MIME types)
    // - use TWebServerGlobal.ForceMimeTypes/ForceMimeTypesExt to set the MIME types
    // - see http://www.iana.org/assignments/media-types
    // https://svn.apache.org/repos/asf/httpd/httpd/trunk/docs/conf/mime.types
    // https://developer.mozilla.org/en-US/docs/Web/HTTP/Basics_of_HTTP/MIME_types
    wsbForceMimeType,

    // Serve all resources labeled as 'text/html' or 'text/plain'
    // with the media type 'charset' parameter set to 'UTF-8'
    wsbForceTextUtf8Charset,

    /// Serve the specified file types with the media type 'charset' parameter
    // set to 'UTF-8'
    // - use TWebServerLocal.FileTypesRequiredCharSet to setup file types
    wsbForceUtf8Charset,

    /// Redirect from 'http://' to the 'https://' version of the URL
    wsbForceHttps,

    /// Forcing 'https://' in the context of Let's Encrypt (ACME)
    // - If you're using cPanel AutoSSL or the Let's Encrypt webroot method it
    // will fail to validate the certificate if validation requests are
    // redirected to HTTPS. Turn on the condition(s) you need.
    // - see https://www.iana.org/assignments/well-known-uris/well-known-uris.xhtml
    //  https://tools.ietf.org/html/draft-ietf-acme-acme-12
    // $ /.well-known/acme-challenge/
    // $ /.well-known/cpanel-dcv/[\w-]+$
    // $ /.well-known/pki-validation/[A-F0-9]{32}\.txt(?:\ Comodo\ DCV)?$
    // - The next simplified patterns are used:
    // $ /.well-known/acme-challenge/*
    // $ /.well-known/cpanel-dcv/*
    // $ /.well-known/pki-validation/*
    wsbForceHttpsExceptLetsEncrypt,

    /// Protect website against clickjacking
    // - The example below sends the 'X-Frame-Options' response header with the
    // value 'DENY', informing browsers not to display the content of the web
    // page in any frame.
    // - This might not be the best setting for everyone. You should read about
    // the other two possible values the 'X-Frame-Options' header field can
    // have: 'SAMEORIGIN' and 'ALLOW-FROM'.
    // https://tools.ietf.org/html/rfc7034#section-2.1.
    // - Keep in mind that while you could send the 'X-Frame-Options' header for
    // all of your website's pages, this has the potential downside that it
    // forbids even non-malicious framing of your content (e.g.: when users
    // visit your website using a Google Image Search results page).
    // - Nonetheless, you should ensure that you send the 'X-Frame-Options' header
    // for all pages that allow a user to make a state-changing operation
    // (e.g: pages that contain one-click purchase links, checkout or
    // bank-transfer confirmation pages, pages that make permanent configuration
    // changes, etc.).
    // - Sending the 'X-Frame-Options' header can also protect your website
    // against more than just clickjacking attacks.
    // - see https://cure53.de/xfo-clickjacking.pdf.
    // https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/X-Frame-Options
    // https://tools.ietf.org/html/rfc7034
    // https://blogs.msdn.microsoft.com/ieinternals/2010/03/30/combating-clickjacking-with-x-frame-options/
    // https://www.owasp.org/index.php/Clickjacking
    wsbSetXFrameOptions,

    /// Block access to all hidden files and directories except for the
    // visible content from within the '/.well-known/' hidden directory
    // - These types of files usually contain user preferences or the preserved
    // state of a utility, and can include rather private places like, for
    // example, the '.git' or '.svn' directories.
    // - The '/.well-known/' directory represents the standard (RFC 5785) path
    // prefix for "well-known locations" (e.g.: '/.well-known/manifest.json',
    // '/.well-known/keybase.txt'), and therefore, access to its visible content
    // should not be blocked.
    // - see https://www.mnot.net/blog/2010/04/07/well-known
    // https://tools.ietf.org/html/rfc5785
    wsbDelegateHidden,

    /// Block access to files that can expose sensitive information
    // - By default, block access to backup and source files that may be left by
    // some text editors and can pose a security risk when anyone has access to
    // them. see https://feross.org/cmsploit/
    //  - Use TWebServerLocal.FileTypesBlocked to specify file types
    // that might end up on your production server and can expose sensitive
    // information about your website. These files may include:
    // configuration files, files that contain metadata about the project
    // (e.g.: project dependencies, build scripts, etc.).
    // - use TWebServerLocal.FileTypesBlocked to specify file types
    // - this option also blocks any URL paths ended with '~' or '#'
    wsbDelegateBlocked,

    /// Prevent some browsers from MIME-sniffing the response
    // - This reduces exposure to drive-by download attacks and cross-origin data
    // leaks, and should be left uncommented, especially if the server is
    // serving user-uploaded content or content that could potentially be
    // treated as executable by the browser.
    // - see https://mimesniff.spec.whatwg.org/
    // https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/X-Content-Type-Options
    // https://blogs.msdn.microsoft.com/ie/2008/07/02/ie8-security-part-v-comprehensive-protection/
    wsbPreventMimeSniffing,

    /// Protect website reflected Cross-Site Scripting (XSS) attacks
    // - Try to re-enable the cross-site scripting (XSS) filter built into
    // most web browsers.
    // - The filter is usually enabled by default, but in some cases, it may
    // be disabled by the user. However, in Internet Explorer, for example,
    // it can be re-enabled just by sending the  'X-XSS-Protection' header
    // with the value of '1'.
    // - Prevent web browsers from rendering the web page if a potential
    // reflected (a.k.a non-persistent) XSS attack is detected by the filter.
    // - By default, if the filter is enabled and browsers detect a reflected
    // XSS attack, they will attempt to block the attack by making the
    // smallest possible modifications to the returned web page.
    // - Unfortunately, in some browsers (e.g.: Internet Explorer), this
    // default behavior may allow the XSS filter to be exploited. Therefore,
    // it's better to inform browsers to prevent the rendering of the page
    // altogether, instead of attempting to modify it.
    // - warning: Do not rely on the XSS filter to prevent XSS attacks! Ensure that you
    // are taking all possible measures to prevent XSS attacks, the most
    // obvious being: validating and sanitizing your website's inputs.
    // - see https://hackademix.net/2009/11/21/ies-xss-filter-creates-xss-vulnerabilities
    // https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/X-XSS-Protection
    // https://blogs.msdn.microsoft.com/ie/2008/07/02/ie8-security-part-iv-the-xss-filter/
    // https://blogs.msdn.microsoft.com/ieinternals/2011/01/31/controlling-the-xss-filter/
    // https://www.owasp.org/index.php/Cross-site_Scripting_%28XSS%29
    // - use TWebServerLocal.FileTypesAsset to exclude some file types
    wsbEnableXssFilter,

    /// Set a strict Referrer Policy to mitigate information leakage.
    // - The 'Referrer-Policy' header is included in responses for resources
    // that are able to request (or navigate to) other resources.
    // - This includes the commonly used resource types:
    // HTML, CSS, XML/SVG, PDF documents, scripts and workers.
    // - To prevent referrer leakage entirely, specify the 'no-referrer' value
    // instead. Note that the effect could impact analytics metrics negatively.
    // - // To check your Referrer Policy, you can use an online service, such as:
    // https://securityheaders.com/
    // https://observatory.mozilla.org/
    // https://scotthelme.co.uk/a-new-security-header-referrer-policy/
    // https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Referrer-Policy
    // - use TWebServerLocal.ReferrerPolicy and
    // TWebServerLocal.ReferrerPolicyContentTypes properties
    wsbEnableReferrerPolicy,

    /// Prevent the HTTP Server from responding to 'TRACE' HTTP requests
    // - The TRACE method, while seemingly harmless, can be successfully leveraged
    // in some scenarios to steal legitimate users' credentials.
    // - Modern browsers now prevent TRACE requests being made via JavaScript,
    // however, other ways of sending TRACE requests with browsers have been
    // discovered, such as using Java.
    // - see https://tools.ietf.org/html/rfc7231#section-4.3.8
    // https://www.owasp.org/index.php/Cross_Site_Tracing
    // https://www.owasp.org/index.php/Test_HTTP_Methods_(OTG-CONFIG-006)
    // https://httpd.apache.org/docs/current/mod/core.html#traceenable
    wsbDisableTraceMethod,

    /// Remove the 'X-Powered-By' response header that:
    // - is set by some frameworks and server-side languages (e.g.: ASP.NET, PHP),
    // and its value contains information about them (e.g.: their name, version
    // number)
    // - doesn't provide any value to users, contributes to header bloat, and in
    // some cases, the information it provides can expose vulnerabilities
    // - If you can, you should disable the 'X-Powered-By' header from the
    //     language/framework level (e.g.: for PHP, you can do that by setting
    //     'expose_php = off' in 'php.ini').
    // - see https://php.net/manual/en/ini.core.php#ini.expose-php
    wsbDeleteXPoweredBy,

    /// Force compression for mangled 'Accept-Encoding' request headers
    // - see https://calendar.perfplanet.com/2010/pushing-beyond-gzipping
    // https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Accept-Encoding
    // - use TWebServerLocal.MangledEncodingHeaders and
    // TWebServerLocal.MangledEncodingHeaderValues properties
    wsbFixMangledAcceptEncoding,

    /// Map the specified filename extensions to the GZip encoding type
    // - to let the HTTP Server serve the file types with the appropriate
    // 'Content-Encoding' response header (do note that this will NOT make
    // HTTP Server compress them!).
    // - If these files types would be served without an appropriate
    // 'Content-Encoding' response header, client applications (e.g.: browsers)
    // wouldn't know that they first need to uncompress the response, and thus,
    // wouldn't be able to understand the content.
    // - see https://httpd.apache.org/docs/current/mod/mod_mime.html#addencoding
    // https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Encoding
    // - use TWebServerLocal.FileTypesForceGZipHeader to setup file types
    wsbForceGZipHeader,

    /// Allow static assets to be cached by proxy servers
    wsbSetCachePublic,

    /// Allow static assets to be cached only by browser,
    // but not by intermediate proxy servers
    wsbSetCachePrivate,

    /// disable Content transformation
    // - Prevent intermediate caches or proxies (such as those used by mobile
    // network providers) and browsers data-saving features from modifying
    // the website's content using the 'cache-control: no-transform' directive.
    // - see https://tools.ietf.org/html/rfc7234#section-5.2.2.4
    // https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Cache-Control
    // - warning: Carefully consider the impact on your visitors before disabling
    // content transformation. These transformations are performed to
    // improve the experience for data- and cost-constrained users
    // (e.g. users on a 2G connection).
    // - You can test the effects of content transformation applied by
    // Google's Lite Mode by visiting:
    // https://googleweblight.com/i?u=https://www.example.com
    // https://support.google.com/webmasters/answer/6211428
    // https://developers.google.com/speed/pagespeed/module/configuration#notransform
    wsbSetCacheNoTransform,

    /// Allow static assets to be validated with server before return cached copy
    wsbSetCacheNoCache,

    /// Allow static assets not to be cached
    wsbSetCacheNoStore,

    /// Allow static assets to be cached strictly following the server rules
    wsbSetCacheMustRevalidate,

    /// Add 'max-age' value based on content-type/expires mapping
    // - i.e. serve resources with a far-future expiration date.
    // - warning: If you don't control versioning with filename-based cache
    // busting, you should consider lowering the cache times to something like
    // one week.
    // - see https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Expires
    // https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Cache-Control
    // - use TWebServerLocal.Expires options to control expirations
    wsbSetCacheMaxAge,

    /// Use ETag / If-None-Match caching
    // - see https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/ETag
    // https://developer.yahoo.com/performance/rules.html#etags
    // https://tools.ietf.org/html/rfc7232#section-2.3
    wsbEnableCacheByETag,

    /// Use Last-Modified/If-Modified-Since caching
    // - see https://developer.yahoo.com/performance/rules.html#etags
    // https://tools.ietf.org/html/rfc7232#section-2.3
    wsbEnableCacheByLastModified,

    /// Serve resources with a far-future expiration date
    // - If you don't control versioning with filename-based cache busting, you
    // should consider lowering the cache times to something like one week.
    // - see https://httpd.apache.org/docs/current/mod/mod_expires.html
    // https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Cache-Control
    // https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Expires
    // - use TWebServerLocal.Expires property
    wsbSetExpires,

    /// Enables filename-based cache busting
    // - i.e. removes all query path of the URL '/style.css?v231' to '/style.css'
    wsbEnableCacheBusting,

    /// Filename-based cache busting
    // - i.e. removes infix query path of the URL '/style.123456.css' to '/style.css'
    // - if you're not using a build process to manage your filename version
    // revving, you might want to consider enabling the following directives.
    // - to understand why this is important and even a better solution than
    // using something like '*.css?v231', please see:
    // https://www.stevesouders.com/blog/2008/08/23/revving-filenames-dont-use-querystring/
    wsbEnableCacheBustingBeforeExt,

    /// Remove 'Server-InternalState' HTTP header
    wsbDeleteServerInternalState,

    // Delete content generation for '' and '/' URLs to '/index.html'
    wsbDelegateRootToIndex,

    /// Instead of index.html rendering the inherited "/Default" URL will be called
    // - allows to inject custom IMVCApplication.Default() interface method
    wsbDelegateIndexToInheritedDefault,

    /// Instead of 404.html rendering the inherited "/404" URL will be called
    // - allows to inject custom IMVCApplication._404() interface method
    wsbDelegate404ToInherited_404,

    /// Add 'Vary: Accept-Encoding' header for assets with GZip/Brotli encoding
    wsbVaryAcceptEncoding
  );

  /// set of tuning options for a modern and safe HTTP/HTTPS Web Server
  // - flags used e.g. by TWebServerLocal, or the mORMot 2 Boilerplate project
  TWebServerBehaviors = set of TWebServerBehavior;

  /// Suppressing or forcing the 'www.' host prefix at the beginning of URLs
  // - The same content should never be available under two different URLs,
  // especially not with and without 'www.' at the beginning.
  // This can cause SEO problems (duplicate content), and therefore, you should
  // choose one of the alternatives and redirect the other one.
  // - The rule assumes by default that both HTTP and HTTPS environments are
  // available for redirection. If your SSL certificate could not handle one
  // of the domains used during redirection, you should turn the condition on.
  // - wsrOff: won't suppress or force 'www.' at the beginning of URLs
  // - wsrSuppress: suppress the 'www.' at the beginning of URLs,
  // redirecting e.g. www.example.com into example.com
  // - wsrForce: forces the 'www.' at the beginning of URLs,
  // redirecting e.g. example.com into www.example.com
  // - Be aware that wsrForce might not be a good idea if you use "real"
  // subdomains for certain parts of your website
  TWebServerRewrite = (
    wsrOff,
    wsrSuppress,
    wsrForce);

  /// how to implement HTTP Strict Transport Security (HSTS) redirection
  // - If a user types 'example.com' in their browser, even if the server redirects
  // them to the secure version of the website, that still leaves a window of
  // opportunity (the initial HTTP connection) for an attacker to downgrade or
  // redirect the request.
  // - The HSTS header ensures that a browser only connects to your server
  // via HTTPS, regardless of what the users type in the browser's address bar.
  // - Be aware that Strict Transport Security is not revokable and you must
  // ensure being able to serve the site over HTTPS for the duration you've
  // specified in the 'max-age' directive. When you don't have a valid TLS
  // connection anymore (e.g. due to an expired TLS certificate) your visitors
  // will see a nasty error message even when attempting to connect over HTTP.
  // - wshOff: do not provide any HSTS header
  // - wshOn: add regular 'max-age=31536000' HSTS header value
  // - wshIncludeSubDomains: add 'max-age=31536000; includeSubDomains' HSTS header
  // - wshIncludeSubDomainsPreload: add
  // 'max-age=31536000; includeSubDomains; preload' HSTS header
  // - see https://tools.ietf.org/html/rfc6797#section-6.1
  // https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Strict-Transport-Security
  // https://www.html5rocks.com/en/tutorials/security/transport-layer-security/
  // https://blogs.msdn.microsoft.com/ieinternals/2014/08/18/strict-transport-security/
  // https://hstspreload.org/
  TWebServerHsts = (
    wshOff,
    wshOn,
    wshIncludeSubDomains,
    wshIncludeSubDomainsPreload);

  /// how to implement DNS Prefetch Control
  // - DNS prefetching is a feature by which browsers proactively perform
  // domain name resolution on both links that the user may choose to follow
  // as well as URLs for items referenced by the document, including images,
  // CSS, JavaScript, and so forth.
  // - This prefetching is performed in the background, so that the DNS is
  // likely to have been resolved by the time the referenced items are needed.
  // This reduces latency when the user clicks a link.
  // - wsdPrefetchNone: do not add 'X-DNS-Prefetch-Control' header
  // - wsdPrefetchOff: turn off DNS Prefetch
  // - wsdPrefetchOn: turn on DNS Prefetch (default)
  // - see https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/X-DNS-Prefetch-Control
  TWebServerDpc = (
    wsdPrefetchNone,
    wsdPrefetchOff,
    wsdPrefetchOn);

  /// the known encoding/compression schemes for a Web Server
  // - THttpServerGeneric.RegisterCompress can support any kind of compression
  // using a callback function; but we define here the most used encodings in
  // current browsers, e.g. to be able to cache content or hashes at runtime
  // - wseIdentity means no compression
  // - wseGZip will use the well-known GZip encoding (via libdeflate if available)
  // - wseBrotli is reserved for future use (e.g. mORMot 2 Boilerplate project)
  TWebServerEncoding = (
    wseIdentity,
    wseGZip,
    wseBrotli);
  /// the known encoding/compression schemes for a Web Server
  TWebServerEncodings = set of TWebServerEncoding;

  /// define the security parameters for a Web Server for a given route
  // - is defined as a record so that it could be assigned and processed per URI
  // - values will be assigned by reference, so with minimal memory consumption
  // - FileTypes*[] are ordered TWordDynArray indexes to TWebServerGlobal.MimeType[]
  TWebServerLocal = record
    /// most used tuning options for a modern and safe HTTP/HTTPS Server
    Behaviors: TWebServerBehaviors;
    /// how to handle the 'www.' host prefix at the beginning of URLs
    Rewrite: TWebServerRewrite;
    /// how to implement HTTP Strict Transport Security (HSTS) redirection
    Hsts: TWebServerHsts;
    /// how to implement DNS Prefetch Control
    Dpc: TWebServerDpc;
    /// file extension ordered indexes for wsbAllowCrossOriginImages behavior
    FileTypesImage: TWordDynArray;
    /// file extension ordered indexes for wsbAllowCrossOriginFonts behavior
    FileTypesFont: TWordDynArray;
    /// file extension ordered indexes for wsbForceUtf8Charset behavior
    FileTypesRequiredCharSet: TWordDynArray;
    /// file extension ordered indexes for wsbDelegateBlocked behavior
    FileTypesBlocked: TWordDynArray;
    /// file extension ordered indexes for wsbForceGZipHeader behavior
    FileTypesForceGZipHeader: TWordDynArray;
    /// supported Referrer Policy for wsbEnableReferrerPolicy behavior
    ReferrerPolicy: RawUtf8;
    /// content types for wsbEnableReferrerPolicy behavior
    ReferrerPolicyContentTypes: TWordDynArray;
    /// headers for wsbFixMangledAcceptEncoding behavior
    MangledEncodingHeaders: TRawUtf8DynArray;
    /// values for wsbFixMangledAcceptEncoding behavior
    MangledEncodingHeaderValues: TRawUtf8DynArray;
    /// expiration for wsbSetCacheMaxAge and wsbSetExpires behaviors
    ExpiresDefault: integer;
    /// content-types for wsbSetCacheMaxAge and wsbSetExpires behaviors
    ExpiresContentTypes: TRawUtf8DynArray;
    /// values for wsbSetCacheMaxAge and wsbSetExpires behaviors
    ExpiresValues: TCardinalDynArray;
  end;

  /// information about a given file extension of a supported mime type
  // - as stored in TWebServerGlobal.MimeType[]
  TWebServerMimeType = record
    /// file extensions of supported mime types, excluding initial '.' character
    Extension: RawUtf8;
    /// specific mime type for wsbForceMimeType behavior
    ForceMimeType: RawUtf8;
  end;
  /// information about all known file extensions of supported mime types
  // - as stored in TWebServerGlobal.MimeType[]
  TWebServerMimeTypeDynArray = array of TWebServerMimeType;

  /// define the security parameters common to all Web Servers
  TWebServerGlobal = class(TSynPersistent)
  protected
    fMimeType: TWebServerMimeTypeDynArray;
    fMimeTypeCount: integer;
    fMimeTypes: TDynArrayHashed;
  public
    /// initialize this instance
    constructor Create; override;
    /// quickly returns the index of a MimeType[] entry from this file extension
    function FindMimeType(Extension: PUtf8Char): PtrInt;
      {$ifdef HASINLINE} inline; {$endif}
    /// search then add if not existing of a file extension
    // - returns the index of the matching MimeType[] entry
    function AddIfNeeded(const Extension: RawUtf8): PtrInt;
    /// search (or add) a file extension, then insert its index in a
    // TWordDynArray sorted array
    // - used e.g. to fill TWebServerLocal behavior-enabled properties
    function AddToIndexes(var Indexes: TSortedWordArray;
      const Extension: RawUtf8): PtrInt;
    /// process a request using the specified local parameters
    // - should return 0 to continue processing, or a result code to stop any
    // further response computation, and return the current output state
    function Request(Context: THttpServerRequestAbstract;
      const Local: TWebServerLocal): cardinal;
    /// file extensions of supported mime types for wsbForceMimeType behavior
    // - see also https://github.com/jshttp/mime-db/blob/master/db.json
    // - TWebServerLocal.FileTypes*[] TWordDynArray contains indexes to this
    // - warning: length(MimeType) is the capacity - use MimeTypeCount
    property MimeType: TWebServerMimeTypeDynArray
      read fMimeType;
    /// how many file extensions are currently known
    property MimeTypeCount: integer
      read fMimeTypeCount;
  end;


{ ******************** HTTP Server Logging/Monitoring Processors }

const
  /// THttpLogger.Parse() text matching the nginx predefined "combined" format
  LOGFORMAT_COMBINED = '$remote_addr - $remote_user [$time_local] ' +
    '"$request" $status $body_bytes_sent "$http_referer" "$http_user_agent"';

type
  /// HTTP server abstract parent for Logger / Analyzer
  // - do not use this abstract class but e.g. THttpLogger or THttpAnalyzer
  // - can merge several THttpAfterResponse instances via the OnContinue property
  // - OnIdle() should be called every few seconds for background process
  // - Append() match TOnHttpServerAfterResponse as real-time source of data
  THttpAfterResponse = class(TSynPersistent)
  protected
    fSafe: TOSLightLock;
    fOnContinue: THttpAfterResponse;
  public
    /// initialize this instance
    constructor Create; override;
    /// finalize this instance
    destructor Destroy; override;
    /// to be overriden e.g. to flush the logs to disk or consolidate counters
    // - likely to be executed every few seconds from a THttpServerGeneric
    procedure OnIdle(tix64: Int64); virtual; abstract;
    /// process the supplied request information
    // - thread-safe method matching TOnHttpServerAfterResponse signature, to
    // be applied directly as a THttpServerGeneric.OnAfterResponse callback
    procedure Append(const Context: TOnHttpServerAfterResponseContext);  virtual; abstract;
    /// overriden Append() and OnIdle() methods will call this event
    // - so that you can cascade e.g. both THttpLogger and THttpAnalyzer
    property OnContinue: THttpAfterResponse
      read fOnContinue write fOnContinue;
  end;

  /// supported THttpLoger place holders
  // - matches nginx log module naming, with some additional fields
  // - values are provided as TOnHttpServerAfterResponse event parameters
  // - variable names in format string uses RTTI e.g. '$uri" for hlvUri
  // - hlvBody_Bytes_Sent equals hlvBytes_Sent with current implementation
  // - hlvBytes_Sent is the number of bytes sent to a client
  // - hlvConnection is the THttpServerConnectionID
  // - hlvConnection_Flags is the CSV of supplied THttpServerRequestFlags
  // - hlvConnection_Upgrade is "upgrade" when "connection: upgrade" in headers
  // - hlvDocument_Uri equals hlvUri value
  // - hlvElapsed is the request processing time as text (e.g. '1.2s')
  // - hlvElapsedMSec is the request processing time in milliseconds
  // - hlvElapsedUSec is the request processing time in microseconds
  // - hlvHostName is the "Host:" header value
  // - hlvHttp_Referer is the "Referer:" header value
  // - hlvHttp_User_Agent is the "User-Agent:" header value
  // - hlvHttps is "on" if the connection operates in HTTPS mode
  // - hlvMsec is current time in seconds with milliseconds resolution
  // - hlvReceived is the request size from the client, as text
  // - hlvRemote_Addr is the client IP address
  // - hlvRemote_User is the user name supplied if hsrAuthorized is set
  // - hlvRequest is the full original request line
  // - hlvRequest_Hash is a crc32c hash of Flags, Host, Method and Url values
  // - hlvRequest_Length is the number of bytes received from the client
  // (including headers and request body)
  // - hlvRequest_Method is usually "GET" or "POST"
  // - hlvRequest_Time is processing time in seconds with milliseconds resolution
  // - hlvRequest_Uri is the full original request line with arguments
  // - hlvScheme is either "HTTP" or "HTTPS"
  // - hlvSent is the response size sent back to the client, as text
  // - hlvServer_Protocol is either "HTTP/1.0" or "HTTP/1.1"
  // - hlvStatus is the response status code (e.g. "200" or "404")
  // - hlvTime_Epoch is the UTC time as seconds since the Unix Epoch
  // - hlvTime_EpochMSec is the UTC time as milliseconds since the Unix Epoch
  // - hlvTime_Iso8601 is the UTC (not local) time in the ISO 8601 standard format
  // - hlvTime_Local is the UTC (not local) time in the Commong Log (NCSA) format
  // - hlvTime_Http is the UTC (not local) time in the HTTP human-readable format
  // - hlvUri is the normalized current URI, i.e. without any ?... parameter
  THttpLogVariable = (
    hlvUnknown,
    hlvBody_Bytes_Sent,
    hlvBytes_Sent,
    hlvConnection,
    hlvConnection_Flags,
    hlvConnection_Upgrade,
    hlvDocument_Uri,
    hlvElapsed,
    hlvElapsedMSec,
    hlvElapsedUSec,
    hlvHostName,
    hlvHttp_Referer,
    hlvHttp_User_Agent,
    hlvHttps,
    hlvMsec,
    hlvReceived,
    hlvRemote_Addr,
    hlvRemote_User,
    hlvRequest,
    hlvRequest_Hash,
    hlvRequest_Length,
    hlvRequest_Method,
    hlvRequest_Time,
    hlvRequest_Uri,
    hlvScheme,
    hlvSent,
    hlvServer_Protocol,
    hlvStatus,
    hlvStatus_Text,
    hlvTime_Epoch,
    hlvTime_EpochMSec,
    hlvTime_Iso8601,
    hlvTime_Local,
    hlvTime_Http,
    hlvUri);

  /// set of supported THttpLoger place holders, matching nginx log module naming
  THttpLogVariables = set of THttpLogVariable;

  /// store an array of HTTP log variables, ready to be rendered by THttpLoger
  // - hlvUnknown is used to define a text place holder
  THttpLogVariableDynArray = array of THttpLogVariable;

  /// exception class raised by THttpLogger
  EHttpLogger = class(ESynException);

  THttpLogger = class;

  /// define how THttpLogger/THttpLoggerWriter do rotate its content
  THttpLoggerRotate = (
    hlrUndefined,
    hlrDaily,
    hlrWeekly,
    hlrAfter1MB,
    hlrAfter10MB,
    hlrAfter32MB,
    hlrAfter100MB);

  /// a per-host TTextDateWriter stream class used by THttpLogger
  THttpLoggerWriter = class(TTextDateWriter)
  protected
    fHost: RawUtf8;
    fOwner: THttpLogger;
    fFileName: TFileName;
    fRotating: TLightLock;
    fRotate: THttpLoggerRotate;
    fRotateFiles: integer;
    fRotateTix10: cardinal;
    fRotateDate: integer; // = next Trunc(NowUtc)
    fLastWriteToStreamTix10: cardinal;
    procedure TryRotate(Tix10: cardinal);
    procedure SetRotateDate;
    procedure DoRotate;
    procedure WriteToStream(data: pointer; len: PtrUInt); override;
  public
    /// initialize a TTextDateWriter instance for THttpLogger
    constructor Create(aOwner: THttpLogger; const aHost: RawUtf8;
      aRotate: THttpLoggerRotate; aRotateFiles: integer); reintroduce;
    /// finalize this instance
    destructor Destroy; override;
    /// the associated lowercased Host name of this writer
    // - equals '' for the main access.log writer
    property Host: RawUtf8
      read fHost;
    /// the file name of this .log instance
    property FileName: TFileName
      read fFileName;
  end;
  /// dynamic array used by THttpLogger to store its per-host log writers
  THttpLoggerWriterDynArray = array of THttpLoggerWriter;

  /// HTTP server responses log format parser and interpreter
  // - Format, DestFolder and DefineHost() allow to setup the logging process
  // - once parsed, log can be emitted by Append() with very high performance
  // - Append() match TOnHttpServerAfterResponse as real-time source of data
  // - OnIdle() should be called every few seconds for background log writing
  // - can perform per-host logging, and destination files rotation
  THttpLogger = class(THttpAfterResponse)
  protected
    fWriterSingle: TTextDateWriter; // from CreateWithWriter/CreateWithFile
    fWriterHostSafe: TLightLock;
    fWriterHost: THttpLoggerWriterDynArray; // from Create + DefineHost
    fWriterHostLast: TTextDateWriter;
    fFormat, fLineFeed: RawUtf8;
    fVariable: THttpLogVariableDynArray;
    fUnknownPosLen: TIntegerDynArray; // matching hlvUnknown occurence
    fVariables: THttpLogVariables;
    fDestFolder, fDestMainLog: TFileName;
    fFlags: set of (ffOwnWriterSingle);
    fDefaultRotate: THttpLoggerRotate;
    fDefaultRotateFiles: integer;
    procedure SetFormat(const aFormat: RawUtf8);
    procedure SetDestFolder(const aFolder: TFileName);
    function GetPerHostFileName(const aHost: RawUtf8): TFileName; virtual;
    function GetWriter(Tix10: cardinal; const Host: RawUtf8): TTextDateWriter;
  public
    /// initialize this multi-host logging instance
    // - this is how THttpServerGeneric initializes its own logging system
    // - caller should next set DestFolder and Format, then optionally DefineHost()
    constructor Create; override;
    /// initialize this instance to generate log content into a TTextDateWriter
    // - mainly used for internal testing purposes
    constructor CreateWithWriter(aWriter: TTextDateWriter;
      const aFormat: RawUtf8 = LOGFORMAT_COMBINED);
    /// initialize this instance to generate a new log file
    // - if you need basic logging abilities - not used by THttpServerGeneric
    constructor CreateWithFile(const aFileName: TFileName;
      const aFormat: RawUtf8 = LOGFORMAT_COMBINED);
    /// finalize this instance
    destructor Destroy; override;
    /// overriden to flush the logs to disk
    procedure OnIdle(tix64: Int64); override;
    /// parse a HTTP server log format string
    // - returns '' on success, or an error message on invalid input
    // - recognized $variable names match trimmed THttpLogVariable enumeration
    // - the Format property will call this method and raise EHttpLogger on error
    function Parse(const aFormat: RawUtf8): RawUtf8; virtual;
    /// register a HTTP host to process its own log file
    // - you can customize its rotation process, if needed
    // - fails if CreateWithWriter or CreateWithFile constructors were used
    procedure DefineHost(const aHost: RawUtf8;
      aRotate: THttpLoggerRotate = hlrUndefined;
      aRotateFiles: integer = -1); virtual;
    /// append a request information to the destination log file
    // - thread-safe method matching TOnHttpServerAfterResponse signature, to
    // be applied directly as a THttpServerGeneric.OnAfterResponse callback
    procedure Append(const Context: TOnHttpServerAfterResponseContext); override;
    /// retrieve the main parameters from another THttpLogger instance
    procedure CopyParams(Another: THttpLogger);
    /// customize the log line feed pattern
    // - matches the operating system value by default (CR or CRLF)
    property LineFeed: RawUtf8
      read fLineFeed write fLineFeed;
    /// low-level access to the parsed log format state machine
    // - mainly used for internal testing purposes
    property Variable: THttpLogVariableDynArray
      read fVariable;
    /// low-level access to the parsed log format used variables
    // - mainly used for internal testing purposes
    property Variables: THttpLogVariables
      read fVariables;
    /// low-level access to the main destination TTextWriter instance
    // - as specified in CreateWithWriter/CreateWithFile constructors
    // - mainly used for internal testing purposes
    property WriterSingle: TTextDateWriter
      read fWriterSingle;
    /// low-level access to the per-host destination TTextWriter instance
    // - mainly used for internal testing purposes
    property WriterHost: THttpLoggerWriterDynArray
      read fWriterHost;
  published
    /// direct access to the log output format
    // - if not supplied in Create() you can assign a format at runtime via this
    // property to call Parse() - raising EHttpLogger on error
    // - recognized $variable names match trimmed THttpLogVariable enumeration,
    // so will follow most of nginx log module naming convention
    // - equals by default LOGFORMAT_COMBINED, i.e. the "combined" log format
    property Format: RawUtf8
      read fFormat write SetFormat;
    /// where the log files will be stored, if not supplied in CreateWithFile()
    // - one main DestFolder + DestMainLog - 'access.log' by default - (rotated)
    // file will be maintained
    // - if not defined, GetSystemPath(spLog) will be used
    // - DefineHost() could generate additional per Host (rotated) log file
    // - not used if CreateWithWriter or CreateWithFile constructors were called
    property DestFolder: TFileName
      read fDestFolder write SetDestFolder;
    /// the log file name to be used in DestFolder for the main log file
    // - equals 'access.log' by default, just like nginx
    // - DefineHost() will use the 'hostname.log' pattern for its own log files
    property DestMainLog: TFileName
      read fDestMainLog write fDestMainLog;
    /// define when log file rotation should occur
    // - default value is hlrAfter10MB
    // - you can customize this in DefineHost() optional aRotate parameter
    // - not used if CreateWithWriter or CreateWithFile constructors were called
    property DefaultRotate: THttpLoggerRotate
      read fDefaultRotate write fDefaultRotate;
    /// how many log files are kept by default, including the main file
    // - default value is 9, i.e. to generate 'xxx.1.gz' up to 'xxx.9.gz'
    // - setting 0 would disable the whole rotation process
    // - you can customize this in DefineHost() optional aRotateFiles parameter
    // - not used if CreateWithWriter or CreateWithFile constructors were called
    property DefaultRotateFiles: integer
      read fDefaultRotateFiles write fDefaultRotateFiles;
  end;

  /// exception raised by THttpAnalyzer related classes
  EHttpAnalyzer = class(ESynException);

  /// each kind of counters covered by THttpAnalyzer / THttpMetrics
  // - i.e. HTTP verbs, HTTP status codes, UserAgent or HTTP scheme or auth
  // - you can interpolate hasDesktop/hasHttp/hasUnAuthorized-like counters as
  // ! Diff(state[hasAny], state[hasMobile/hasHttps/hasAuthorized])
  THttpAnalyzerScope = (
    hasAny,
    hasGet,
    hasHead,
    hasPost,
    hasPut,
    hasDelete,
    hasOptions,
    has1xx,
    has2xx,
    has3xx,
    has4xx,
    has5xx,
    hasMobile,
    hasBot,
    hasHttps,
    hasAuthorized);

  /// the kind of counters covered by THttpAnalyzer / THttpMetrics
  THttpAnalyzerScopes = set of THttpAnalyzerScope;

  /// possible time periods used for THttpAnalyzer data consolidation
  // - hapCurrent, hapYear and hapAll are only available in THttpAnalyzer context
  // - TOnHttpAnalyzerSave and THttpMetrics handle hapMinute..hapMonth only
  THttpAnalyzerPeriod = (
    hapCurrent,
    hapMinute,
    hapHour,
    hapDay,
    hapMonth,
    hapYear,
    hapAll);
  /// the time periods used for THttpAnalyzer consolidation
  THttpAnalyzerPeriods = set of THttpAnalyzerPeriod;

  /// count unit for THttpAnalyzer information as 64-bit unsigned integer
  THttpAnalyzerTotal = type QWord;
  /// size unit for THttpAnalyzer information in bytes
  THttpAnalyzerBytes = type QWord;

  /// define a THttpAnalyzerScope counter state, may be after consolidation
  // - counters are maintained by period and by scope, and are cumulative
  // - each record consumes 32 bytes of memory on all platforms
  {$ifdef USERECORDWITHMETHODS}
  THttpAnalyzerState = record
  {$else}
  THttpAnalyzerState = object
  {$endif USERECORDWITHMETHODS}
    /// number of requests processed for this counter
    Count: THttpAnalyzerTotal;
    /// resolution-variable time measured for processing this counter
    // - excludes the incoming request communication, but include actual
    // computation and response transmission
    // - actual unit depends on the Period involved: hapCurrent as microsec,
    // hapMinute/hapHour/hapDay/hapAll as millisec, hapMonth/hapYear as sec
    // - use TimeMicroSec() function to retrieve the actual value
    Time: cardinal;
    /// approximate/relative number of unique IPs concerned by this counter
    // - only populated if THttpAnalyzer.UniqueIPDepth is set to a hash bitsize
    // - for hapMinute, this field is computed using a hashtable of IPs,
    // so should be considered as a somewhat good approximation of the reality
    // - for periods longer than hapMinute, this field is the sum of numbers
    // of unique IPs per minute for all nested minutes, so is relevant to compare
    // values in the same period only (e.g. divided by the number of collected
    // minutes to get the average unique IP count per minute)
    // - it should always considered as a relative number, not an absolute number
    UniqueIP: cardinal;
    /// number of bytes received from the client for this counter requests
    Read: THttpAnalyzerBytes;
    /// number of bytes written back to the client for this counter responses
    Write: THttpAnalyzerBytes;
    /// fill all field values with 0
    procedure Clear;
      {$ifdef HASINLINE} inline; {$endif}
    /// copy all field values from another counter state
    procedure From(const Another: THttpAnalyzerState);
      {$ifdef HASINLINE} inline; {$endif}
    /// add all field values from another counter state
    procedure Add(const Another: THttpAnalyzerState);
      {$ifdef HASINLINE} inline; {$endif}
    /// substract all field values from another counter state
    procedure Sub(const Another: THttpAnalyzerState);
      {$ifdef HASINLINE} inline; {$endif}
    /// returns the processing time as MicroSeconds
    // - computed from the 32-bit Time field, with the Period unit
    function TimeMicroSec(Period: THttpAnalyzerPeriod): QWord;
      {$ifdef HASINLINE} inline; {$endif}
  end;

  /// pointer to a given counter
  PHttpAnalyzerState = ^THttpAnalyzerState;
  /// information about all possible counters
  THttpAnalyzerStates = array[THttpAnalyzerScope] of THttpAnalyzerState;
  /// pointer to information about all possible counters
  PHttpAnalyzerStates = ^THttpAnalyzerStates;
  /// a dynamic array of counters information
  THttpAnalyzerStateDynArray = array of THttpAnalyzerState;

  /// store all consolidated states in a Round-Robin manner
  THttpAnalyzerConsolidated = array[THttpAnalyzerPeriod] of THttpAnalyzerStates;

  /// transient in-memory storage of THttpAnalyzer states to be persisted
  // - map all the information to be persisted on disk as CSV, binary or SQL
  // - each record consumes 40 bytes of memory on all platforms
  {$ifdef USERECORDWITHMETHODS}
  THttpAnalyzerToSave = record
  {$else}
  THttpAnalyzerToSave = object
  {$endif USERECORDWITHMETHODS}
    /// the timestamp of the data consolidation - from UnixTimeMinimalUtc()
    // - use the DateTime method to retrieve an usable value
    Date: cardinal;
    /// the resolution time period (hapMinute .. hapAll)
    Period: THttpAnalyzerPeriod;
    /// the corresponding counter
    Scope: THttpAnalyzerScope;
    {$ifndef USERECORDWITHMETHODS}
    _padding: word; // needed on Delphi 7
    {$endif USERECORDWITHMETHODS}
    /// the whole information about this counter in this Period at Date
    State: THttpAnalyzerState;
    /// wrap UnixTimeToDateTime(Date + UNIXTIME_MINIMAL) to return a TDateTime
    function DateTime: TDateTime;
     {$ifdef HASINLINE} inline; {$endif}
  end;
  /// a pointer to a THttpAnalyzerToSave memory
  PHttpAnalyzerToSave = ^THttpAnalyzerToSave;
  /// a dynamic array of THttpAnalyzerToSave
  THttpAnalyzerToSaveDynArray = array of THttpAnalyzerToSave;
  /// a wrapper to THttpAnalyzerToSave items
  THttpAnalyzerToSaveArray = array[
    0 .. (MaxInt div SizeOf(THttpAnalyzerToSave)) - 1] of THttpAnalyzerToSave;
  /// a pointer to THttpAnalyzerToSave items
  PHttpAnalyzerToSaveArray = ^THttpAnalyzerToSaveArray;

  /// event callback signature to persist THttpAnalyzer information
  // - is called with State.Period in hapMinute..hapMonth range
  TOnHttpAnalyzerSave = procedure(
    const State: THttpAnalyzerToSaveDynArray) of object;

  /// HTTP server real-time responses consolidation
  // - will gather at real time the main information about HTTP requests,
  // then consolidate the data in main time periods
  // - this does not replace a full log parsing/monitoring solution, but could
  // give good hints about the current server status, with no third-party tool
  // - OnIdle() should be called every few seconds for background process
  // - Append() match TOnHttpServerAfterResponse as real-time source of data
  // - OnSave() event could be assigned e.g. to a THttpAnalyzerPersistAbstract
  THttpAnalyzer = class(THttpAfterResponse)
  protected
    fTracked, fSaved: THttpAnalyzerScopes;
    fModified: boolean; // for UpdateSuspendFile
    fOnSave: TOnHttpAnalyzerSave;
    fSuspendFile: TFileName;
    fState: THttpAnalyzerConsolidated;
    fUniqueIPDepth: cardinal;
    fUniqueIP: array[THttpAnalyzerScope] of TByteDynArray;
    fToSave: record
      Count: integer;
      State: THttpAnalyzerToSaveDynArray;
    end;
    fSuspendFileAutoSaveMinutes: cardinal;
    fSuspendFileAutoSaveTix, fLastConsolidate: cardinal;
    fConsolidateNextTime: array[hapMinute .. hapYear] of TDateTime;
    procedure SetUniqueIPDepth(value: cardinal);
    procedure ComputeConsolidateTime(last: THttpAnalyzerPeriod; ref: TDateTime);
    procedure Consolidate(tixsec: cardinal);
    procedure DoAppend(const new: THttpAnalyzerState; s: THttpAnalyzerScope);
    procedure DoSave;
  public
    /// initialize this HTTP server analyzer instance
    // - you can specify an optional file name to persist the current counters
    // state as compressed binary, which will be read in the constructor
    // and written in Destroy or via UpdateSuspendFile/SuspendFileSaveMinutes
    constructor Create(const aSuspendFile: TFileName = '';
      aSuspendFileSaveMinutes: integer = 1); reintroduce;
    /// finalize this instance, with proper persistence of the pending counters
    destructor Destroy; override;
    /// overriden to consolidate the counters and optionally persist them
    // - this callback is likely to be executed every second from a THttpServer
    procedure OnIdle(tix64: Int64); override;
    /// append a request information to the internal counters
    // - thread-safe method matching TOnHttpServerAfterResponse signature, to
    // be applied directly as a THttpServerGeneric.OnAfterResponse callback
    procedure Append(const Context: TOnHttpServerAfterResponseContext); override;
    /// retrieve the current state for a given period and scope
    // - consolidate hapMinute..hapYear values up to the requested Period
    // - this method is thread-safe
    procedure Get(Period: THttpAnalyzerPeriod; Scope: THttpAnalyzerScope;
      out State: THttpAnalyzerState);
    /// force persistence of the pending counters
    procedure UpdateSuspendFile;
    /// a power-of-two bits size in range 2048..65536 for UniqueIP detection
    // - is the bits size of a per-THttpAnalyzerScope hash table
    // - set to 0 by default, to disable this feature
    // - should be set to a value bigger than the maximum number of unique IP,
    // since by design, THttpAnalyzerState.UniqueIP could never exceed this
    property UniqueIPDepth: cardinal
      read fUniqueIPDepth write SetUniqueIPDepth;
    /// the frequency on which OnIdle() calls UpdateSuspendFile
    // - set to 0 to be disabled
    property SuspendFileAutoSaveMinutes: cardinal
      read fSuspendFileAutoSaveMinutes;
    /// direct access to the current state since the beginning
    // - this property is not thread-safe, and does not include hapCurrent
    // pending values: use Get() instead
    property Total: THttpAnalyzerStates
      read fState[hapAll];
    /// event handler used to persist the information
    property OnSave: TOnHttpAnalyzerSave
      read fOnSave write fOnSave;
  published
    /// define which THttpAnalyzerScopes fields are to be tracked
    property Tracked: THttpAnalyzerScopes
      read fTracked write fTracked;
    /// define which THttpAnalyzerScopes fields are to be sent to OnSave()
    property Saved: THttpAnalyzerScopes
      read fSaved write fSaved;
    /// just a redirection to the number of requests since the beginning
    property TotalRequests: THttpAnalyzerTotal
      read fState[hapAll, hasAny].Count;
    /// just a redirection to the millisecond time processing since the beginning
    property TotalTime: cardinal
      read fState[hapAll, hasAny].Time;
  end;

  /// abstract parent class used to persist THttpAnalyzer information in files
  THttpAnalyzerPersistAbstract = class(TSynPersistent)
  protected
    fFileName: TFileName;
  public
    /// intitialize this persistence instance
    constructor Create(const aFileName: TFileName); reintroduce; virtual;
  published
    /// the current persistent file name
    property FileName: TFileName
      read fFileName;
  end;

  /// class allowing to persist THttpAnalyzer information into a CSV file
  // - output will have Date,Period,Scope,Count,Time,Read,Write columns
  THttpAnalyzerPersistCsv = class(THttpAnalyzerPersistAbstract)
  public
    /// this is the main callback of persistence, matching THttpAnalyser.OnSave
    // - will persist the state items as CSV rows
    procedure OnSave(const State: THttpAnalyzerToSaveDynArray);
  end;

  /// class allowing to persist THttpAnalyzer information into a JSON file
  // - format will be a JSON array of THttpAnalyzerToSave JSON objects as
  // $ {"d":"xxx","p":x,"s":x,"c":x,"t":x,"r":x,"w":x}
  // with "p" and "s" fields being ord(THttpAnalyzerPeriod/THttpAnalyzerScope)
  THttpAnalyzerPersistJson = class(THttpAnalyzerPersistAbstract)
  public
    /// this is the main callback of persistence, matching THttpAnalyser.OnSave
    // - will persist the state items as JSON objects
    procedure OnSave(const State: THttpAnalyzerToSaveDynArray);
  end;

  /// class allowing to persist THttpAnalyzer information into a binary file
  // - output will just be raw THttpAnalyzerToSave array memory layout with no
  // encoding nor compression involved
  // - is likely to be persisted in hapMinute resolution up to one month (28MB)
  // - to be further aggregated and searched by THttpMetrics.AddFromBinary()
  THttpAnalyzerPersistBinary = class(THttpAnalyzerPersistAbstract)
  public
    /// this is the main callback of persistence, matching THttpAnalyser.OnSave
    procedure OnSave(const State: THttpAnalyzerToSaveDynArray);
  end;

  /// metadata as decoded by THttpMetrics.LoadHeader() class function
  THttpMetricsHeader = record
    /// how many events are in this file
    Count: cardinal;
    /// events counter per time period
    Period: array[hapMinute .. hapMonth] of cardinal;
    /// the timestamp of the first event in this file
    First: TDateTime;
    /// the timestamp of the last event in this file
    Last: TDateTime;
    /// the compression algorithm used with THttpMetrics.SaveToFile()
    Algo: TAlgoCompress;
    /// the crc32c of all data rows - could be used e.g. to compare files
    Crc: cardinal;
    /// the binary size of the internal format extensions stored with the data
    // - <> 0 if THttpMetrics.GetExtensions/SetExtensions were overriden
    ExtensionSize: cardinal;
    /// some custom text or JSON, as set to THttpMetrics.Metadata field
    Metadata: RawUtf8;
  end;

  /// exception class raised during THttpMetrics process
  EHttpMetrics = class(ESynException);

  /// class used to read/write and search persisted THttpAnalyzer information
  // - you can aggregate several input files, then persist the metrics using our
  // optimized .mhm file encoding ("mhm" for "mORMot HTTP Metrics")
  // - Find() method allows to quickly retrieve any range of information for
  // a given time period and metric type
  // - supports up to 10,485,760 metrics per instance (see HTTPMETRICS_MAXCOUNT)
  THttpMetrics = class(TSynPersistent)
  protected
    fSafe: TLightLock;
    fCount: integer;
    fPeriodLastCount: integer;
    fState: TRawByteStringGroup; // avoid in-memory fragmentation
    fDynArray: TDynArray;
    // by design, about 60 of 61 items are actual hapMinute values: no index
    fPeriod: array[hapHour .. hapMonth] of record
      Index: TIntegerDynArray;
      Count: PtrInt;
    end;
    fLastRangeToIndex: record // naive but efficient e.g. from a dashboard
      sta, sto, ista, isto: cardinal;
    end;
    fMetadata: RawUtf8;
    procedure CreateDynArray;
    procedure GetExtensions(out data: RawByteString); virtual;
    function SetExtensions(const data: TValueResult): boolean; virtual;
    function StateAsCompactArray: PDynArray; // compact and set fDynArray
      {$ifdef HASINLINE} inline; {$endif}
    procedure ResetPeriodIndex;
    procedure CreatePeriodIndex;
    function RangeToIndex(start, stop: TDateTime;
      out istart, istop: integer): PHttpAnalyzerToSaveArray;
    function RangeToPeriodIndex(period: THttpAnalyzerPeriod;
      start, stop: integer; out pstart, pstop: PInteger): integer;
  public
    /// release all stored data
    procedure Clear;
    /// append a FileName content in the THttpAnalyzerPersistBinary format
    function AddFromBinary(const FileName: TFileName): boolean;
    /// append a memory buffer in the THttpAnalyzerPersistBinary format
    function AddFromBuffer(const Buffer: RawByteString): boolean;
    {
    /// append a FileName content in .log or .log.gz format
    // - instantiate THttpLogger/THttpAnalyzer instances to parse and decode
    function AddFromLog(const FileName: TFileName;
      const Format: RawUtf8 = LOGFORMAT_COMBINED): boolean;
    }
    /// persist all metrics into a file in our optimized .mhm binary format
    // - use variable-length integer encoding, then optional compression
    // - keep default Algo = nil if you don't want to compress the content
    procedure SaveToFile(const Dest: TFileName; Algo: TAlgoCompress);
    /// load .mhm file content as generated by SaveToFile() persistence
    // - will first clear any previous data, then uncompress and decode the file
    function LoadFromFile(const Source: TFileName): boolean;
    /// persist all this data in our optimized binary encoding
    // - i.e. with variable-length integer encoding, but no compression
    procedure SaveToWriter(Dest: TBufferWriter);
    /// load the data from SaveToWriter() memory content
    function LoadFromReader(var Source: TFastReader): boolean;
    /// this is the main callback of persistence, matching THttpAnalyser.OnSave
    // - will add the saved states to the internal in-memory storage
    procedure OnSave(const State: THttpAnalyzerToSaveDynArray);
    /// direct access to the internal stored data - from Row in [0..Count-1]
    // - make a thread-safe copy of the data
    function GetState(Row: integer; out State: THttpAnalyzerToSave): boolean;
    /// raw thread-unsafe access to the data - to be protected with Safe.Lock
    function Get(Row: integer): PHttpAnalyzerToSave;
      {$ifdef HASINLINE} inline; {$endif}
    /// search for a Period/Scope information for a given time range
    // - Period could be in OnSave() range, i.e. hapMinute .. hapMonth
    // - very fast, using per-Period indexes for hapHour .. hapMonth
    function Find(Start, Stop: TDateTime; Period: THttpAnalyzerPeriod;
      Scope: THttpAnalyzerScope): THttpAnalyzerToSaveDynArray;
    /// class function able to retrieve the metadata of our optimized binary format
    class function LoadHeader(const FileName: TFileName;
      out Info: THttpMetricsHeader): boolean;
    /// some custom text persisted in our SaveToFile/LoadFromFile header
    // - you can specify here e.g. some human-readable description of the
    // file content, as plain text or JSON
    property Metadata: RawUtf8
      read fMetadata write fMetadata;
    /// access to the thread-safety NOT reentrant lock
    property Safe: TLightLock
      read fSafe write fSafe;
  published
    /// how many rows are currently in State[] memory buffer
    property Count: integer
      read fCount;
  end;

const
  /// time unit for THttpAnalyzerState.Time values
  // - hapCurrent are stored as microseconds, hapMinute/hapHour/hapDay/hapAll
  // as milliseconds, and hapMonth/hapYear as seconds
  // - as used when inlining the THttpAnalyzerState.TimeMicroSec method
  HTTPANALYZER_TIMEUNIT: array[THttpAnalyzerPeriod] of cardinal = (
    1,        // hapCurrent
    1000,     // hapMinute
    1000,     // hapHour
    1000,     // hapDay
    1000000,  // hapMonth
    1000000,  // hapYear
    1000);    // hapAll

  /// we support up to 10,485,760 metrics per THttpMetrics instance
  // - i.e. 400MB of continuous memory buffer for its internal storage
  // - one year of minute-resolution data uses around 320MB (60*24*365*16*40)
  // - hapMinute should be better stored per month - i.e. up to 28MB
  // - allow to maintain two bufers (compressed + uncompressed) even on Win32
  HTTPMETRICS_MAXCOUNT = (400 shl 20) div SizeOf(THttpAnalyzerToSave);

  /// low level magic marker in THttpMetrics .mhm binary files
  // - may not be at the beginning of the file, if compression was enabled: use
  // rather THttpMetrics.LoadHeader if you want to identify .mhm files
  HTTPMETRICS_MAGIC: string[23] = 'mORMotAnalyzerV1'#26;


function ToText(s: THttpAnalyzerScope): PShortString; overload;
function ToText(p: THttpAnalyzerPeriod): PShortString; overload;
function ToText(v: THttpLogVariable): PShortString; overload;
function ToText(r: THttpLoggerRotate): PShortString; overload;



implementation


{ ******************** Shared HTTP Constants and Functions }

function AuthorizationBearer(const AuthToken: RawUtf8): RawUtf8;
begin
  if AuthToken = '' then
    result := ''
  else
    result := 'Authorization: Bearer ' + AuthToken;
end;

const
  TOBEPURGED: array[0..9] of PAnsiChar = (
    'CONTENT-',
    'CONNECTION:',
    'KEEP-ALIVE:',
    'TRANSFER-',
    'X-POWERED',
    'USER-AGENT',
    'REMOTEIP:',
    'HOST:',
    'ACCEPT:',
    nil);

function PurgeHeaders(const headers: RawUtf8): RawUtf8;
var
  pos, len: array[byte] of word;
  n, purged, i, l, tot: PtrInt;
  P, next: PUtf8Char;
begin
  n := 0;
  tot := 0;
  purged := 0;
  // put all allowed headers in pos[]/len[]
  P := pointer(headers);
  if length(headers) shr 16 = 0 then // defined as word
    while P <> nil do
    begin
      if P^ = #0 then
        break;
      next := GotoNextLine(P);
      if IdemPPChar(P, @TOBEPURGED) < 0 then
      begin
        if n = high(len) then
          break;
        pos[n] := P - pointer(headers);
        l := next - P;
        if next = nil then
          if purged = 0 then
            break
          else
            l := StrLen(P);
        inc(tot, l);
        len[n] := l;
        inc(n);
      end
      else
        inc(purged);
      P := next;
    end;
  // recreate an expurgated headers set
  if purged = 0 then
    // nothing to purge
    result := headers
  else if tot = 0 then
    // genocide
    result := ''
  else
  begin
    // allocate at once and append all non-purged headers
    FastSetString(result, nil, tot);
    P := pointer(result);
    for i := 0 to n - 1 do
    begin
      MoveFast(PByteArray(headers)[{%H-}pos[i]], P^, {%H-}len[i]);
      inc(P, len[i]);
    end;
    assert(P - pointer(result) = tot);
  end;
end;

function IdemPCharNotVoid(p: PByteArray; up: PByte; toup: PByteArray): boolean;
  {$ifdef HASINLINE}inline;{$endif}
var
  u: byte;
begin
  // slightly more efficient than plain IdemPChar() - we don't check p/up=nil
  result := false;
  dec(PtrUInt(p), PtrUInt(up));
  repeat
    u := up^;
    if u = 0 then
      break;
    if toup[p[PtrUInt(up)]] <> u then
      exit;
    inc(up);
  until false;
  result := true;
end;

procedure ExtractHeader(var headers: RawUtf8; const upname: RawUtf8;
  out res: RawUtf8);
var
  i, j, k: PtrInt;
begin
  if (headers = '') or
      (upname = '') then
    exit;
  i := 1;
  repeat
    // find end of current line
    k := length(headers) + 1;
    for j := i to k - 1 do
      if headers[j] < ' ' then
      begin
        k := j;
        break;
      end;
    // check the header name
    if IdemPCharNotVoid(@PByteArray(headers)[i - 1], pointer(upname), @NormToUpper) then
    begin
      j := i;
      inc(i, length(upname));
      TrimCopy(headers, i, k - i, res);
      while true do // delete also ending #13#10
        if (headers[k] = #0) or
           (headers[k] >= ' ') then
          break
        else
          inc(k);
      delete(headers, j, k - j); // and remove
      exit;
    end;
    // go to next line
    i := k;
    while headers[i] < ' ' do
      if headers[i] = #0 then
        exit
      else
        inc(i);
  until false;
end;

function MimeHeaderEncode(const header: RawUtf8): RawUtf8;
begin
  if IsAnsiCompatible(header) then
    // US-ASCII don't need any conversion in the RFC, but only 7-bit in practice
    result := header
  else
    result := '=?UTF-8?B?' + BinToBase64(header) + '?=';
end;

function HttpMethodWithNoBody(const method: RawUtf8): boolean;
var
  c: cardinal;
begin
  c := PCardinal(method)^;
  result := (((c xor cardinal(ord('H') + ord('E') shl 8 + ord('A') shl 16 +
                     ord('D') shl 24)) and $dfdfdfdf) = 0) or
            (((c xor cardinal(ord('O') + ord('P') shl 8 + ord('T') shl 16 +
                     ord('I') shl 24)) and $dfdfdfdf) = 0);
end;

function IsGet(const method: RawUtf8): boolean;
begin
  result := PCardinal(method)^ = ord('G') + ord('E') shl 8 + ord('T') shl 16;
end;

function IsPost(const method: RawUtf8): boolean;
begin
  result := PCardinal(method)^ =
    ord('P') + ord('O') shl 8 + ord('S') shl 16 + ord('T') shl 24;
end;

function IsPut(const method: RawUtf8): boolean;
begin
  result := PCardinal(method)^ =
    ord('P') + ord('U') shl 8 + ord('T') shl 16;
end;

function IsDelete(const method: RawUtf8): boolean;
begin
  result := PCardinal(method)^ =
    ord('D') + ord('E') shl 8 + ord('L') shl 16 + ord('E') shl 24;
end;

function IsOptions(const method: RawUtf8): boolean;
begin
  result := PCardinal(method)^ =
    ord('O') + ord('P') shl 8 + ord('T') shl 16 + ord('I') shl 24;
end;

function IsHead(const method: RawUtf8): boolean;
begin
  result := PCardinal(method)^ =
    ord('H') + ord('E') shl 8 + ord('A') shl 16 + ord('D') shl 24;
end;


function IsUrlFavIcon(P: PUtf8Char): boolean;
begin
  result := (P <> nil) and
        (PCardinalArray(P)[0] =
           ord('/') + ord('f') shl 8 + ord('a') shl 16 + ord('v') shl 24) and
        (PCardinalArray(P)[1] =
           ord('i') + ord('c') shl 8 + ord('o') shl 16 + ord('n') shl 24) and
        (PCardinalArray(P)[2] =
           ord('.') + ord('i') shl 8 + ord('c') shl 16 + ord('o') shl 24) and
        (P[12] = #0);
end;

function IsHttpUserAgentBot(const UserAgent: RawUtf8): boolean;
var
  url, i: PtrInt;
begin
  // we used https://github.com/monperrus/crawler-user-agents as starting reference
  result := false;
  url := PosEx('//', UserAgent);
  if url = 0 then
    exit; // a browser usually has no http://... reference within
  i := PosEx('.com/', UserAgent, url);
  if i = 0 then
    i := PosEx('.org/', UserAgent, url);
  if i <> 0 then
     case PCardinal(@PByteArray(UserAgent)[i + 4])^ and $00ffffff of
       // Googlebot/2.1 (+http://www.google.com/bot.html)
       ord('b') + ord('o') shl 8 + ord('t') shl 16,
       // Mozilla/5.0 (compatible; adidxbot/2.0;  http://www.bing.com/bingbot.htm)
       ord('b') + ord('i') shl 8 + ord('n') shl 16,
       // Mozilla/5.0 (compatible; Yahoo! Slurp; http://help.yahoo.com/help/us/ysearch/slurp)
       ord('h') + ord('e') shl 8 + ord('l') shl 16,
       // adidxbot/1.1 (+http://search.msn.com/msnbot.htm)
       ord('m') + ord('s') shl 8 + ord('n') shl 16,
       // Speedy Spider (http://www.entireweb.com/about/search_tech/speedy_spider/
       ord('a') + ord('b') shl 8 + ord('o') shl 16,
       // Mozilla/5.0 (compatible; Baiduspider/2.0; +http://www.baidu.com/search/spider.html)
       // Mozilla/5.0 (compatible; coccoc/1.0; +http://help.coccoc.com/searchengine)
       ord('s') + ord('e') shl 8 + ord('a') shl 16,
       // DuckDuckBot/1.0; (+http://duckduckgo.com/duckduckbot.html)
       ord('d') + ord('u') shl 8 + ord('c') shl 16,
       // Mozilla/5.0 (compatible; Applebot/0.3; +http://www.apple.com/go/applebot
       ord('g') + ord('o') shl 8 + ord('/') shl 16,
       // Mozilla/5.0 (compatible; AhrefsBot/6.1; +http://ahrefs.com/robot/)
       ord('r') + ord('o') shl 8 + ord('b') shl 16:
         result := true;
     else
       case PCardinal(@PByteArray(UserAgent)[i - 4])^ and $00ffffff of
         // serpstatbot/1.0 (advanced backlink tracking bot; http://serpstatbot.com/;)
         ord('b') + ord('o') shl 8 + ord('t') shl 16:
           result := true;
       end;
     end;
end;

function ByPriority(const A, B): integer;
begin
  result := CompareInteger(THttpSocketCompressRec(A).Priority,
                           THttpSocketCompressRec(B).Priority);
end;

function RegisterCompressFunc(var Comp: THttpSocketCompressRecDynArray;
  CompFunction: THttpSocketCompress; var AcceptEncoding: RawUtf8;
  CompMinSize, CompPriority: integer): RawUtf8;
var
  i, n: PtrInt;
  dummy: RawByteString;
  algo: RawUtf8;
begin
  result := '';
  if @CompFunction = nil then
    exit;
  n := length(Comp);
  algo := CompFunction(dummy, {compress}true); // just retrieve algo name
  for i := 0 to n - 1 do
    with Comp[i] do
      if Name = algo then
      begin
        // already set
        if @Func = @CompFunction then
          CompressMinSize := CompMinSize; // update size parameter
        exit;
      end;
  if n = SizeOf(THttpSocketCompressSet) * 8 then
    exit; // CompressAcceptHeader has 0..31 bits
  SetLength(Comp, n + 1);
  with Comp[n] do
  begin
    Name := algo;
    @Func := @CompFunction;
    CompressMinSize := CompMinSize;
    Priority := (CompPriority shl 14) or n; // by CompPriority, then call order
  end;
  DynArray(TypeInfo(THttpSocketCompressRecDynArray), Comp).Sort(ByPriority);
  if AcceptEncoding = '' then
    AcceptEncoding := 'Accept-Encoding: ' + algo
  else
    AcceptEncoding := AcceptEncoding + ',' + algo;
  result := algo;
end;

const
  _CONTENTCOMP: array[0..3] of PUtf8Char = (
    'TEXT/',
    'IMAGE/',
    'APPLICATION/',
    nil);
  _CONTENTIMG: array[0..2] of PUtf8Char = (
    'SVG',
    'X-ICO',
    nil);
  _CONTENTAPP: array[0..4] of PUtf8Char = (
    'JSON',
    'XML',
    'JAVASCRIPT',
    'VND.API+JSON',
    nil);

procedure CompressContent(Accepted: THttpSocketCompressSet;
  const Handled: THttpSocketCompressRecDynArray; const OutContentType: RawUtf8;
  var OutContent: RawByteString; var OutContentEncoding: RawUtf8);
var
  i, OutContentLen: integer;
  compressible: boolean;
  OutContentTypeP: PUtf8Char absolute OutContentType;
begin
  if (integer(Accepted) <> 0) and
     (OutContentType <> '') and
     (Handled <> nil) then
  begin
    OutContentLen := length(OutContent);
    case IdemPPChar(OutContentTypeP, @_CONTENTCOMP) of
      0:
        compressible := true;
      1:
        compressible := IdemPPChar(OutContentTypeP + 6, @_CONTENTIMG) >= 0;
      2:
        compressible := IdemPPChar(OutContentTypeP + 12, @_CONTENTAPP) >= 0;
    else
      compressible := false;
    end;
    for i := 0 to length(Handled) - 1 do
      if i in Accepted then
        with Handled[i] do
          if (CompressMinSize = 0) or // 0 means "always" (e.g. for encryption)
             (compressible and
              (OutContentLen >= CompressMinSize)) then
          begin
            // compression of the OutContent + update header
            OutContentEncoding := Func(OutContent, true);
            exit; // first in fCompress[] is prefered
          end;
  end;
  OutContentEncoding := '';
end;

function ComputeContentEncoding(const Compress: THttpSocketCompressRecDynArray;
  P: PUtf8Char): THttpSocketCompressSet;
var
  i, len: PtrInt;
  Beg: PUtf8Char;
begin
  integer(result) := 0;
  if P <> nil then
    repeat
      while P^ in [' ', ','] do
        inc(P);
      Beg := P; // 'gzip;q=1.0, deflate' -> Name='gzip' then 'deflate'
      while not (P^ in [';', ',', #0]) do
        inc(P);
      len := P - Beg;
      if len <> 0 then
        for i := 0 to length(Compress) - 1 do
          if IdemPropNameU(Compress[i].Name, Beg, len) then
            include(result, i);
      while not (P^ in [',', #0]) do
        inc(P);
    until P^ = #0;
end;

function CompressIndex(const Compress: THttpSocketCompressRecDynArray;
  CompFunction: THttpSocketCompress): PtrInt;
begin
  for result := 0 to length(Compress) - 1 do
    if @Compress[result].Func = @CompFunction then
      exit;
  result := -1;
end;

function HttpChunkToHex32(p: PAnsiChar): integer;
var
  v0, v1: byte;
begin
  // note: chunk is not regular two-chars-per-byte hexa since may have odd len
  result := 0;
  if p <> nil then
  begin
    while p^ = ' ' do
      inc(p); // trim left
    repeat
      v0 := ConvertHexToBin[ord(p[0])];
      if v0 = 255 then
        break; // not in '0'..'9','a'..'f' -> trim right
      v1 := ConvertHexToBin[ord(p[1])];
      inc(p);
      if v1 = 255 then
      begin
        result := (result shl 4) or v0; // odd number of hexa chars input
        break;
      end;
      result := (result shl 8) or (integer(v0) shl 4) or v1;
      inc(p);
    until false;
  end;
end;

function UrlDecodeParam(P: PUtf8Char; const UpperName: RawUtf8;
  out Value: RawUtf8): boolean;
begin
  if P <> nil then
  begin
    result := true;
    inc(P);
    repeat
      if UrlDecodeValue(P, UpperName, Value, @P) then
        exit;
    until P = nil;
  end;
  result := false;
end;

function UrlDecodeParam(P: PUtf8Char; const UpperName: RawUtf8;
  out Value: cardinal): boolean;
begin
  if P <> nil then
  begin
    result := true;
    inc(P);
    repeat
      if UrlDecodeCardinal(P, UpperName, Value, @P) then
        exit;
    until P = nil;
  end;
  result := false;
end;

function UrlDecodeParam(P: PUtf8Char; const UpperName: RawUtf8;
  out Value: Int64): boolean;
begin
  if P <> nil then
  begin
    result := true;
    inc(P);
    repeat
      if UrlDecodeInt64(P, UpperName, Value, @P) then
        exit;
    until P = nil;
  end;
  result := false;
end;

function GetNextRange(var P: PUtf8Char): Qword;
var
  c: PtrUInt;
begin
  result := 0;
  if P <> nil then
    repeat
      c := byte(P^) - 48;
      if c > 9 then
        break
      else
        result := result * 10 + Qword(c);
      inc(P);
    until false;
end;


{ ******************** Reusable HTTP State Machine }

{ THttpRequestContext }

procedure THttpRequestContext.Clear;
begin
  Head.Reset;
  Process.Reset;
  State := hrsNoStateMachine;
  HeaderFlags := [];
  ResponseFlags := [];
  Options := [];
  Headers := '';
  ContentType := '';
  Upgrade := '';
  BearerToken := '';
  UserAgent := '';
  Referer := '';
  RangeOffset := 0;
  RangeLength := -1;
  Content := '';
  ContentLength := -1;
  ServerInternalState := 0;
  CompressContentEncoding := -1;
  integer(CompressAcceptHeader) := 0;
end;

procedure THttpRequestContext.GetTrimmed(P, P2: PUtf8Char; L: PtrInt;
  var result: RawUtf8; nointern: boolean);
begin
  while (P^ > #0) and
        (P^ <= ' ') do
    inc(P); // trim left
  if L >= 0 then
    dec(L, P - P2)
  else
    L := StrLen(P);
  repeat
    if (L = 0) or
       (P[L - 1] > ' ') then
      break;
    dec(L); // trim right
  until false;
  SetRawUtf8(result, P, L, nointern);
end;

function THttpRequestContext.ValidateRange: boolean;
var
  tosend: Int64;
begin
  if RangeOffset >= ContentLength then
    result := false // invalid offset: return error or void response
  else
  begin
    tosend := RangeLength;
    if (tosend < 0) or // -1 for end of file 'Range: 1024-'
       (RangeOffset + tosend > ContentLength) then
      tosend := ContentLength - RangeOffset; // truncate
    RangeLength := ContentLength; // contains size for Content-Range: header
    ContentLength := tosend;
    include(ResponseFlags, rfRange);
    result := true;
  end;
end;

procedure THttpRequestContext.ParseHeader(P: PUtf8Char; PLen: PtrInt;
  HeadersUnFiltered: boolean);
var
  i, len: PtrInt;
  P1, P2: PUtf8Char;
begin
  if P = nil then
    exit; // avoid unexpected GPF in case of wrong usage
  P2 := P;
  // standard headers are expected to be pure A-Z chars: fast lowercase search
  // - or $20 makes conversion to a-z lowercase, but won't affect - / : chars
  // - the worse case may be some false positive, which won't hurt unless
  // your network architecture suffers from HTTP request smuggling
  // - much less readable than cascaded IdemPPChar(), but slightly faster ;)
  case PCardinal(P)^ or $20202020 of
    ord('c') + ord('o') shl 8 + ord('n') shl 16 + ord('t') shl 24:
      if PCardinal(P + 4)^ or $20202020 =
        ord('e') + ord('n') shl 8 + ord('t') shl 16 + ord('-') shl 24 then
        // 'CONTENT-'
        case PCardinal(P + 8)^ or $20202020 of
          ord('l') + ord('e') shl 8 + ord('n') shl 16 + ord('g') shl 24:
            if PCardinal(P + 12)^ or $20202020 =
              ord('t') + ord('h') shl 8 + ord(':') shl 16 + ord(' ') shl 24 then
            begin
              // 'CONTENT-LENGTH:'
              ContentLength := GetInt64(P + 16);
              if not HeadersUnFiltered then
                exit;
            end;
          ord('t') + ord('y') shl 8 + ord('p') shl 16 + ord('e') shl 24:
            if P[12] = ':' then
            begin
              // 'CONTENT-TYPE:'
              P := GotoNextNotSpace(P + 13);
              if (PCardinal(P)^ or $20202020 =
                ord('a') + ord('p') shl 8 + ord('p') shl 16 + ord('l') shl 24) and
                 (PCardinal(P + 11)^ or $20202020 =
                ord('/') + ord('j') shl 8 + ord('s') shl 16 + ord('o') shl 24) then
              begin
                // 'APPLICATION/JSON'
                ContentType := JSON_CONTENT_TYPE_VAR;
                if not HeadersUnFiltered then
                  exit; // '' in headers means JSON for our REST server
              end
              else
              begin
                GetTrimmed(P, P2, PLen, ContentType);
                if ContentType = '' then
                  // 'CONTENT-TYPE:' is searched by HEADER_CONTENT_TYPE_UPPER
                  exit;
              end;
            end;
          ord('e') + ord('n') shl 8 + ord('c') shl 16 + ord('o') shl 24:
            if (Compress <> nil) and
               (PCardinal(P + 12)^ or $20202020 =
                ord('d') + ord('i') shl 8 + ord('n') shl 16 + ord('g') shl 24) and
               (P[16] = ':') then
            begin
              // 'CONTENT-ENCODING:'
              P := GotoNextNotSpace(P + 17);
              P1 := P;
              while P^ > ' ' do
                inc(P); // no control char should appear in any header
              len := P - P1;
              if len <> 0 then
                for i := 0 to length(Compress) - 1 do
                  if IdemPropNameU(Compress[i].Name, P1, len) then
                  begin
                    CompressContentEncoding := i; // will handle e.g. gzip
                    if not HeadersUnFiltered then
                      exit;
                    break;
                  end;
            end;
        end;
    ord('h') + ord('o') shl 8 + ord('s') shl 16 + ord('t') shl 24:
      if P[4] = ':' then
      begin
        // 'HOST:'
        inc(P, 5);
        while (P^ > #0) and
              (P^ <= ' ') do
          inc(P); // trim left
        if (LastHost <> '') and
           (StrComp(pointer(P), pointer(LastHost)) = 0) then
          Host := LastHost // optimistic approach
        else
        begin
          GetTrimmed(P, P2, PLen, Host);
          if LastHost = '' then
            LastHost := Host; // thread-safe cache for next reused call
        end;
        // always add to headers - 'host:' sometimes parsed directly
      end;
    ord('c') + ord('o') shl 8 + ord('n') shl 16 + ord('n') shl 24:
      if (PCardinal(P + 4)^ or $20202020 =
          ord('e') + ord('c') shl 8 + ord('t') shl 16 + ord('i') shl 24) and
        (PCardinal(P + 8)^ or $20202020 =
          ord('o') + ord('n') shl 8 + ord(':') shl 16 + ord(' ') shl 24) then
      begin
        // 'CONNECTION: '
        inc(P, 12);
        case PCardinal(P)^ or $20202020 of
          ord('c') + ord('l') shl 8 + ord('o') shl 16 + ord('s') shl 24:
            begin
              // 'CONNECTION: CLOSE'
              include(HeaderFlags, hfConnectionClose);
              if not HeadersUnFiltered then
                exit;
            end;
          ord('u') + ord('p') shl 8 + ord('g') shl 16 + ord('r') shl 24:
            begin
              // 'CONNECTION: UPGRADE'
              include(HeaderFlags, hfConnectionUpgrade);
              if not HeadersUnFiltered then
                exit;
            end;
          ord('k') + ord('e') shl 8 + ord('e') shl 16 + ord('p') shl 24:
            if (PCardinal(P + 4)^ or $20202020 =
                ord('-') + ord('a') shl 8 + ord('l') shl 16 + ord('i') shl 24) and
               (PWord(P + 8)^ or $2020 = ord('v') + ord('e') shl 8) then
            begin
              // 'CONNECTION: KEEP-ALIVE'
              include(HeaderFlags, hfConnectionKeepAlive);
              inc(P, 10);
              if P^ = ',' then
              begin
                repeat
                  inc(P);
                until P^ <> ' ';
                if PCardinal(P)^ or $20202020 =
                  ord('u') + ord('p') shl 8 + ord('g') shl 16 + ord('r') shl 24 then
                  // 'CONNECTION: KEEP-ALIVE, UPGRADE'
                  include(HeaderFlags, hfConnectionUpgrade);
              end;
              if not HeadersUnFiltered then
                exit;
            end;
        end;
      end;
    ord('a') + ord('c') shl 8 + ord('c') shl 16 + ord('e') shl 24:
      if (PCardinal(P + 4)^ or $20202020 =
        ord('p') + ord('t') shl 8 + ord('-') shl 16 + ord('e') shl 24) and
         (PCardinal(P + 8)^ or $20202020 =
        ord('n') + ord('c') shl 8 + ord('o') shl 16 + ord('d') shl 24) and
         (PCardinal(P + 12)^ or $20202020 =
        ord('i') + ord('n') shl 8 + ord('g') shl 16 + ord(':') shl 24) then
        begin
           // 'ACCEPT-ENCODING:'
          GetTrimmed(P + 17, P2, PLen, AcceptEncoding);
          if not HeadersUnFiltered then
            exit;
        end;
    ord('u') + ord('s') shl 8 + ord('e') shl 16 + ord('r') shl 24:
      if (PCardinal(P + 4)^ or $20202020 =
        ord('-') + ord('a') shl 8 + ord('g') shl 16 + ord('e') shl 24) and
         (PCardinal(P + 8)^ or $20202020 =
        ord('n') + ord('t') shl 8 + ord(':') shl 16 + ord(' ') shl 24) then
      begin
        // 'USER-AGENT:'
        GetTrimmed(P + 11, P2, PLen, UserAgent);
        if not HeadersUnFiltered then
          exit;
      end;
    ord('s') + ord('e') shl 8 + ord('r') shl 16 + ord('v') shl 24:
      if (PCardinal(P + 4)^ or $20202020 =
        ord('e') + ord('r') shl 8 + ord('-') shl 16 + ord('i') shl 24) and
         (PCardinal(P + 8)^ or $20202020 =
        ord('n') + ord('t') shl 8 + ord('e') shl 16 + ord('r') shl 24) and
         (PCardinal(P + 12)^ or $20202020 =
        ord('n') + ord('a') shl 8 + ord('l') shl 16 + ord('s') shl 24) and
         (PCardinal(P + 16)^ or $20202020 =
        ord('t') + ord('a') shl 8 + ord('t') shl 16 + ord('e') shl 24) and
         (P[20] = ':') then
      begin
        // 'SERVER-INTERNALSTATE:'
        inc(P, 21);
        ServerInternalState := GetCardinal(P);
        if not HeadersUnFiltered then
          exit;
      end;
    ord('e') + ord('x') shl 8 + ord('p') shl 16 + ord('e') shl 24:
      if (PCardinal(P + 4)^ or $20202020 =
        ord('c') + ord('t') shl 8 + ord(':') shl 16 + ord(' ') shl 24) and
         (PCardinal(P + 8)^ =
        ord('1') + ord('0') shl 8 + ord('0') shl 16 + ord('-') shl 24) then
      begin
        // 'Expect: 100-continue'
        include(HeaderFlags, hfExpect100);
        if not HeadersUnFiltered then
          exit;
      end;
    ord('a') + ord('u') shl 8 + ord('t') shl 16 + ord('h') shl 24:
      if (PCardinal(P + 4)^ or $20202020 =
        ord('o') + ord('r') shl 8 + ord('i') shl 16 + ord('z') shl 24) and
         (PCardinal(P + 8)^ or $20202020 =
        ord('a') + ord('t') shl 8 + ord('i') shl 16 + ord('o') shl 24) then
      begin
        include(HeaderFlags, hfHasAuthorization);
        if (PCardinal(P + 12)^ or $20202020 =
          ord('n') + ord(':') shl 8 + ord(' ') shl 16 + ord('b') shl 24) and
           (PCardinal(P + 16)^ or $20202020 =
          ord('e') + ord('a') shl 8 + ord('r') shl 16 + ord('e') shl 24) and
           (PWord(P + 20)^ or $2020 = ord('r') + ord(' ') shl 8) then
          // 'AUTHORIZATION: BEARER '
          GetTrimmed(P + 22, P2, PLen, BearerToken, {nointern=}true);
        // always allow FindNameValue(..., HEADER_BEARER_UPPER, ...) search
      end;
    ord('r') + ord('a') shl 8 + ord('n') shl 16 + ord('g') shl 24:
      if (PCardinal(P + 4)^ or $20202020 =
        ord('e') + ord(':') shl 8 + ord(' ') shl 16 + ord('b') shl 24) and
         (PCardinal(P + 8)^ or $20202020 =
        ord('y') + ord('t') shl 8 + ord('e') shl 16 + ord('s') shl 24) and
         (P[12] = '=') then
        if rfWantRange in ResponseFlags then
          State := hrsErrorUnsupportedRange // no multipart range
        else
        begin
          // 'RANGE: BYTES='
          P1 := GotoNextNotSpace(P + 13); // use pointer on stack
          RangeOffset := GetNextRange(P1);
          if P1^ = '-' then
          begin
            inc(P1);
            if P1^ in ['0'..'9'] then
            begin
              // "Range: bytes=0-499" -> start=0, len=500
              RangeLength := Int64(GetNextRange(P1)) - RangeOffset + 1;
              if RangeLength < 0 then
                RangeLength := 0;
            end;
            // "bytes=1000-" -> start=1000, keep RangeLength=-1 to eof
            if P1^ = ',' then
              State := hrsErrorUnsupportedRange // no multipart range
            else
              include(ResponseFlags, rfWantRange);
           end
          else
            State := hrsErrorUnsupportedRange;
          if not HeadersUnFiltered then
            exit;
        end;
    ord('u') + ord('p') shl 8 + ord('g') shl 16 + ord('r') shl 24:
      if PCardinal(P + 4)^ or $00202020 =
        ord('a') + ord('d') shl 8 + ord('e') shl 16 + ord(':') shl 24 then
      begin
        // 'UPGRADE:'
        GetTrimmed(P + 8, P2, PLen, Upgrade);
        if not HeadersUnFiltered then
          exit;
      end;
    ord('r') + ord('e') shl 8 + ord('f') shl 16 + ord('e') shl 24:
      if PCardinal(P + 4)^ or $00202020 =
        ord('r') + ord('e') shl 8 + ord('r') shl 16 + ord(':') shl 24 then
      begin
        // 'REFERER:'
        GetTrimmed(P + 8, P2, PLen, Referer, {nointern=}true);
        if not HeadersUnFiltered then
          exit;
      end;
    ord('t') + ord('r') shl 8 + ord('a') shl 16 + ord('n') shl 24:
      if IdemPChar(P + 4, 'SFER-ENCODING: CHUNKED') then
      begin
        // 'TRANSFER-ENCODING: CHUNKED'
        include(HeaderFlags, hfTransferChunked);
        if not HeadersUnFiltered then
          exit;
      end;
  end;
  // store meaningful headers into WorkBuffer, if not already there
  if PLen < 0 then
    PLen := StrLen(P2);
  Head.Append(P2, PLen);
  Head.AppendCRLF;
end;

function THttpRequestContext.HeaderGetValue(const aUpperName: RawUtf8): RawUtf8;
begin
  FindNameValue(Headers, pointer(aUpperName), result{%H-}, false, ':');
end;

function THttpRequestContext.HeaderHasValue(const aUpperName: RawUtf8): boolean;
begin
  result := FindNameValue(pointer(Headers), pointer(aUpperName)) <> nil;
end;

procedure THttpRequestContext.ParseHeaderFinalize;
begin
  if nfHeadersParsed in HeaderFlags then
    exit;
  include(HeaderFlags, nfHeadersParsed);
  Head.AsText(Headers, {ForRemoteIP=}40, {usemainbuffer=}Interning <> nil);
  Head.Reset;
  if Compress <> nil then
    if AcceptEncoding <> '' then
      CompressAcceptHeader :=
        ComputeContentEncoding(Compress, pointer(AcceptEncoding));
end;

var
  _GETVAR, _POSTVAR, _HEADVAR: RawUtf8;

function THttpRequestContext.ParseCommand: boolean;
var
  P, B: PUtf8Char;
  L: PtrInt;
begin
  result := false;
  if nfHeadersParsed in HeaderFlags then
    exit;
  P := pointer(CommandUri);
  if P = nil then
    exit;
  case PCardinal(P)^ of
    ord('G') + ord('E') shl 8 + ord('T') shl 16 + ord(' ') shl 24:
      begin
        CommandMethod := _GETVAR; // optimistic
        inc(P, 4);
      end;
    ord('P') + ord('O') shl 8 + ord('S') shl 16 + ord('T') shl 24:
      begin
        CommandMethod := _POSTVAR;
        inc(P, 5);
      end;
    ord('H') + ord('E') shl 8 + ord('A') shl 16 + ord('D') shl 24:
      begin
        CommandMethod := _HEADVAR; // allow quick 'HEAD' search per pointer
        inc(P, 5);
      end;
  else
    begin
      B := P;
      while true do
        if P^ = ' ' then
          break
        else if P^ = #0 then
          exit
        else
          inc(P);
      L := P - B;
      if L > 10 then
        exit; // clearly invalid input (method name should be short)
      SetRawUtf8(CommandMethod, B, L, {nointern=}false);
      inc(P);
    end;
  end;
  B := P;
  while true do
    if P^ = ' ' then
      break
    else if P^ = #0 then
      exit
    else
      inc(P);
  L := P - B;
  MoveFast(B^, pointer(CommandUri)^, L); // in-place extract URI from Command
  FakeLength(CommandUri, L);
  if (PCardinal(P + 1)^ <>
       ord('H') + ord('T') shl 8 + ord('T') shl 16 + ord('P') shl 24) or
     (PCardinal(P + 5)^ and $ffffff <>
       ord('/') + ord('1') shl 8 + ord('.') shl 16) then
    exit;
  if P[8] <> '1' then
    include(ResponseFlags, rfHttp10);
  if not (hfConnectionClose in HeaderFlags) then
    if not (hfConnectionKeepAlive in HeaderFlags) and // allow HTTP1.0+keepalive
       (rfHttp10 in ResponseFlags) then // HTTP/1.1 is keep-alive by default
      include(HeaderFlags, hfConnectionClose); // standard HTTP/1.0
  result := true;
end;

procedure THttpRequestContext.UncompressData;
begin
  if cardinal(CompressContentEncoding) < cardinal(length(Compress)) then
  begin
    if Compress[CompressContentEncoding].Func(Content, false) = '' then
      // invalid content
      raise EHttpSocket.CreateUtf8('% UncompressData failed',
        [Compress[CompressContentEncoding].Name]);
    ContentLength := length(Content); // uncompressed Content-Length
  end;
end;

procedure THttpRequestContext.ProcessInit(InStream: TStream);
begin
  Clear;
  ContentStream := InStream;
  ContentLeft := 0;
  State := hrsGetCommand;
end;

procedure THttpRequestContext.SetRawUtf8(var res: RawUtf8;
  P: pointer; PLen: PtrInt; nointern: boolean);
begin
  if (Interning <> nil) and
     (PLen < 256) and
     not nointern then
    Interning^.UniqueFromBuffer(res, P, PLen, InterningHasher(0, P, PLen))
  else
    FastSetString(res, P, PLen);
end;

function THttpRequestContext.ProcessParseLine(var st: TProcessParseLine): boolean;
var
  Len: PtrInt;
  P: PUtf8Char;
begin
  Len := ByteScanIndex(pointer(st.P), st.Len, 13); // fast SSE2 or FPC IndexByte
  if PtrUInt(Len) < PtrUInt(st.Len) then // we just ignore the following #10
  begin
    P := st.P;
    st.Line := P;
    P[Len] := #0; // replace ending CRLF by #0
    st.LineLen := Len;
    inc(Len, 2);  // if 2nd char is not #10, parsing will fail as expected
    inc(st.P, Len);
    dec(st.Len, Len);
    result := true;
    // now we have the next full line in st.Line/st.LineLen
  end
  else
    result := false; // not enough input
end;

function THttpRequestContext.ProcessRead(var st: TProcessParseLine): boolean;
var
  previous: THttpRequestState;
begin
  result := false; // not enough input
  if st.Len = 0 then
    exit;
  previous := State;
  repeat
    case State of
      hrsGetCommand:
        if ProcessParseLine(st) then
        begin
          if Interning = nil then
            FastSetString(CommandUri, st.Line, st.LineLen)
          else
          begin
            // no real interning, but CommandUriInstance buffer reuse
            if st.LineLen > CommandUriInstanceLen then
            begin
              CommandUriInstanceLen := st.LineLen + 256;
              FastSetString(CommandUriInstance, nil, CommandUriInstanceLen);
            end;
            CommandUri := CommandUriInstance; // COW memory buffer reuse
            MoveFast(st.Line^, pointer(CommandUri)^, st.LineLen);
            FakeLength(CommandUri, st.LineLen);
          end;
          State := hrsGetHeaders;
        end
        else
          exit; // not enough input
      hrsGetHeaders:
        if ProcessParseLine(st) then
          if st.LineLen <> 0 then
            // Headers continue as long as text lines appear
            ParseHeader(st.Line, st.LineLen, hroHeadersUnfiltered in Options)
          else
            // void line: we reached end of headers
            if hfTransferChunked in HeaderFlags then
              // process chunked body
              State := hrsGetBodyChunkedHexFirst
            else if ContentLength > 0 then
              // regular process with explicit content-length
              State := hrsGetBodyContentLength
              // note: old HTTP/1.0 format with no Content-Length is unsupported
              // because officially not defined in HTTP/1.1 RFC2616 4.3
            else
              // no body
              State := hrsWaitProcessing
        else
          exit;
      hrsGetBodyChunkedHexFirst,
      hrsGetBodyChunkedHexNext:
        if ProcessParseLine(st) then
        begin
          ContentLeft := HttpChunkToHex32(PAnsiChar(st.Line));
          if ContentLeft <> 0 then
          begin
            if ContentStream = nil then
            begin
              // reserve appended chunk size to Content memory buffer
              SetLength(Content, length(Content) + ContentLeft);
              ContentPos := @PByteArray(Content)[length(Content)];
            end;
            inc(ContentLength, ContentLeft);
            State := hrsGetBodyChunkedData;
          end
          else
            State := hrsGetBodyChunkedDataLastLine;
        end
        else
          exit;
      hrsGetBodyChunkedData:
        begin
          if st.Len < ContentLeft then
            st.LineLen := st.Len
          else
            st.LineLen := ContentLeft;
          if ContentStream <> nil then
            ContentStream.WriteBuffer(st.P^, st.LineLen)
          else
          begin
            MoveFast(st.P^, ContentPos^, st.LineLen);
            inc(ContentPos, st.LineLen);
          end;
          dec(ContentLeft, st.LineLen);
          if ContentLeft = 0 then
            State := hrsGetBodyChunkedDataVoidLine
          else
            exit;
        end;
      hrsGetBodyChunkedDataVoidLine:
        if ProcessParseLine(st) then // chunks end with a void line
          State := hrsGetBodyChunkedHexNext
        else
          exit;
      hrsGetBodyChunkedDataLastLine:
        if ProcessParseLine(st) then // last chunk
          if st.Len <> 0 then
            State := hrsErrorUnsupportedFormat // should be no further input
          else
            State := hrsWaitProcessing
        else
          exit;
      hrsGetBodyContentLength:
        begin
          if ContentLeft = 0 then
            ContentLeft := ContentLength;
          if st.Len < ContentLeft then
            st.LineLen := st.Len
          else
            st.LineLen := ContentLeft;
          if ContentStream = nil then
          begin
            if Content = '' then // we need to allocate the result memory buffer
            begin
              if ContentLength > 1 shl 30 then // 1 GB mem chunk is fair enough
              begin
                State := hrsErrorPayloadTooLarge; // avoid memory overflow
                result := true;
                exit;
              end;
              SetLength(Content, ContentLength);
              ContentPos := pointer(Content);
            end;
            MoveFast(st.P^, ContentPos^, st.LineLen);
            inc(ContentPos, st.LineLen);
          end
          else
            ContentStream.WriteBuffer(st.P^, st.LineLen);
          dec(st.Len, st.LineLen);
          dec(ContentLeft, st.LineLen);
          if ContentLeft = 0 then
            if st.Len <> 0 then
              State := hrsErrorUnsupportedFormat // should be no further input
            else
              State := hrsWaitProcessing
          else
            exit;
        end;
    else
      State := hrsErrorMisuse; // out of context State for input
    end;
  until (State <> previous) and
        ((State = hrsGetBodyChunkedHexFirst) or
         (State = hrsGetBodyContentLength) or
         (State >= hrsWaitProcessing));
  result := true; // notify the next main state change
end;

function THttpRequestContext.CompressContentAndFinalizeHead(
  MaxSizeAtOnce: integer): PRawByteStringBuffer;
begin
  // same logic than THttpSocket.CompressDataAndWriteHeaders below
  if (integer(CompressAcceptHeader) <> 0) and
     (ContentStream = nil) then // no stream compression (yet)
    CompressContent(CompressAcceptHeader, Compress, ContentType,
      Content, ContentEncoding);
  // method will return a buffer to be sent
  result := @Head;
  // handle response body with optional range support
  if rfAcceptRange in ResponseFlags then
    result^.AppendShort('Accept-Ranges: bytes'#13#10);
  if ContentStream = nil then
  begin
    ContentPos := pointer(Content); // for ProcessBody below
    ContentLength := length(Content);
    if rfWantRange in ResponseFlags then
      if not (rfRange in ResponseFlags) then // not already from ContentFromFile
        if ValidateRange then
          inc(ContentPos, RangeOffset) // rfRange has just been set
        else
          ContentLength := 0; // invalid range: return void response
    // ContentStream<>nil did set ContentLength/rfRange in ContentFromFile
  end;
  if rfRange in ResponseFlags then
  begin
    // Content-Range: bytes 0-1023/146515
    result^.AppendShort('Content-Range: bytes ');
    result^.Append(RangeOffset);
    result^.Append('-');
    result^.Append(RangeOffset + ContentLength - 1);
    result^.Append('/');
    result^.Append(RangeLength); // = FileSize after ContentFromFile()
    result^.AppendCRLF;
  end;
  // finalize headers
  if ContentEncoding <> '' then
  begin
    result^.AppendShort('Content-Encoding: ');
    result^.Append(ContentEncoding);
    result^.AppendCRLF;
  end;
  result^.AppendShort('Content-Length: ');
  result^.Append(ContentLength);
  result^.AppendCRLF;
  if (ContentType <> '') and
     (ContentType[1] <> '!') then
  begin
    result^.AppendShort('Content-Type: ');
    result^.Append(ContentType);
    result^.AppendCRLF;
  end;
  if hfConnectionClose in HeaderFlags then
    result^.AppendShort('Connection: Close'#13#10#13#10) // end with a void line
  else
  begin
    if rfHttp10 in ResponseFlags then // implicit with HTTP/1.1
      result^.AppendShort('Connection: Keep-Alive'#13#10);
    if CompressAcceptEncoding <> '' then
    begin
      result^.Append(CompressAcceptEncoding);
      result^.AppendCRLF;
    end;
    result^.AppendCRLF;
  end;
  // try to send both headers and body in a single socket syscal
  Process.Reset;
  if pointer(CommandMethod) = pointer(_HEADVAR) then
    // return only the headers
    State := hrsResponseDone
  else
    // there is a body to send
    if ContentStream = nil then
      if (ContentLength = 0) or
         result^.TryAppend(ContentPos, ContentLength) then
        // single socket send() is possible (small body appended to headers)
        State := hrsResponseDone
      else
      begin
        if ContentLength + Head.Len < MaxSizeAtOnce then
        begin
          // single socket send() is possible (body fits in the sending buffer)
          Process.Reserve(Head.Len + ContentLength);
          Process.Append(Head.Buffer, Head.Len);
          Process.Append(ContentPos, ContentLength);
          Content := ''; // release ASAP
          Head.Reset;
          result := @Process; // DoRequest will use Process
          State := hrsResponseDone;
        end
        else
          // async huge body sent using Write polling
          State := hrsSendBody;
      end
    else
      // ContentStream <> nil requires async body sending
      State := hrsSendBody; // send the ContentStream out by chunks
end;

procedure THttpRequestContext.ProcessBody(
  var Dest: TRawByteStringBuffer; MaxSize: PtrInt);
var
  P: pointer;
begin
  // THttpAsyncConnection.DoRequest did send the headers: now send body chunks
  if State <> hrsSendBody then
    exit;
  // send in the background, using polling up to MaxSize (256KB typical)
  if ContentLength < MaxSize then
    MaxSize := ContentLength;
  if MaxSize > 0 then
  begin
    if ContentStream <> nil then
    begin
      P := Process.Reserve(MaxSize);
      MaxSize := ContentStream.Read(P^, MaxSize);
      Dest.Append(P, MaxSize);
    end
    else
    begin
      Dest.Append(ContentPos, MaxSize);
      inc(ContentPos, MaxSize);
    end;
    dec(ContentLength, MaxSize);
  end
  else if ContentLength = 0 then
    // we just finished background ProcessWrite of the last chunk
    State := hrsResponseDone
  else
    // paranoid check
    raise EHttpSocket.CreateUtf8('ProcessWrite: len=%', [MaxSize]);
end;

procedure THttpRequestContext.ProcessDone;
begin
  if rfContentStreamNeedFree in ResponseFlags then
    FreeAndNilSafe(ContentStream);
end;

function THttpRequestContext.ContentFromFile(
  const FileName: TFileName; CompressGz: integer): boolean;
var
  gz: TFileName;
begin
  Content := '';
  if (CompressGz >= 0) and
     (CompressGz in CompressAcceptHeader) and
     (pointer(CommandMethod) <> pointer(_HEADVAR)) and
     not (rfWantRange in ResponseFlags) then
  begin
    // try locally cached gzipped static content
    gz := FileName + '.gz';
    ContentLength := FileSize(gz);
    if ContentLength > 0 then
    begin
      // there is an already-compressed .gz file to send away
      ContentStream := TFileStreamEx.Create(gz, fmOpenReadDenyNone);
      ContentEncoding := 'gzip';
      include(ResponseFlags, rfContentStreamNeedFree);
      result := true;
      exit; // only use ContentStream to bypass recompression
    end;
  end;
  ContentLength := FileSize(FileName);
  result := ContentLength <> 0;
  if result and
     (rfWantRange in ResponseFlags) then
    if not ValidateRange then
      result := false; // invalid offset
  if not result then
    // there is no such file available, or range clearly wrong
    exit;
  include(ResponseFlags, rfAcceptRange);
  ContentStream := TFileStreamEx.Create(FileName, fmOpenReadDenyNone);
  if RangeOffset <> 0 then
    ContentStream.Seek(RangeOffset, soBeginning);
  if (ContentLength < 1 shl 20) and
     (pointer(CommandMethod) <> pointer(_HEADVAR)) then
  begin
    // smallest files (up to 1MB) in temp memory (and maybe compress them)
    SetLength(Content, ContentLength);
    ContentStream.Read(pointer(Content)^, ContentLength);
    FreeAndNilSafe(ContentStream);
  end
  else
  begin
    // stream existing big file by chunks (also used for HEAD or Range)
    include(ResponseFlags, rfContentStreamNeedFree);
  end;
end;


function ToText(st: THttpRequestState): PShortString;
begin
  result := GetEnumName(TypeInfo(THttpRequestState), ord(st));
end;

function ToText(csp: TCrtSocketPending): PShortString;
begin
  result := GetEnumName(TypeInfo(TCrtSocketPending), ord(csp));
end;

function ToText(tls: TCrtSocketTlsAfter): PShortString;
begin
  result := GetEnumName(TypeInfo(TCrtSocketTlsAfter), ord(tls));
end;

function ToText(mak: TMacAddressKind): PShortString;
begin
  result := GetEnumName(TypeInfo(TMacAddressKind), ord(mak));
end;


{ ******************** THttpSocket Implementing HTTP over plain sockets }

{ THttpSocket }

procedure THttpSocket.CompressDataAndWriteHeaders(const OutContentType: RawUtf8;
  var OutContent: RawByteString; OutStream: TStream);
var
  OutContentEncoding: RawUtf8;
  len: Int64;
begin
  if (integer(Http.CompressAcceptHeader) <> 0) and
     (OutStream = nil) then // no stream compression (yet)
  begin
    CompressContent(Http.CompressAcceptHeader, Http.Compress, OutContentType,
      OutContent, OutContentEncoding);
    if OutContentEncoding <> '' then
      SockSend(['Content-Encoding: ', OutContentEncoding]);
  end;
  if OutStream = nil then
    len := length(OutContent)
  else
    len := OutStream.Size;
  SockSend(['Content-Length: ', len]); // needed even 0
  if (OutContentType <> '') and
     (OutContentType[1] <> '!') then
    SockSend(['Content-Type: ', OutContentType]);
end;

procedure THttpSocket.HttpStateReset;
begin
  Http.Clear;
  fBodyRetrieved := false;
end;

const
  _FLAGS: PAnsiChar = 'ptcuk1if';

function ToText(hf: THttpRequestHeaderFlags): TShort8;
var
  b: cardinal;
  P, R: PAnsiChar;
  L: PtrInt;
begin
  b := byte(hf);
  L := 0;
  P := _FLAGS;
  R := @result;
  repeat
    if b and 1 <> 0 then
    begin
      inc(L);
      R[L] := P^;
    end;
    inc(P);
    b := b shr 1;
  until b = 0;
  R[0] := AnsiChar(L);
end;

function THttpSocket.GetHeader(HeadersUnFiltered: boolean): boolean;
var
  s: RawUtf8;
  err: integer;
  line: array[0..4095] of AnsiChar; // avoid most memory allocations
begin
  // parse the headers
  result := false;
  HttpStateReset;
  if SockIn <> nil then
    repeat
      {$I-}
      readln(SockIn^, line);
      err := ioresult;
      if err <> 0 then
        raise EHttpSocket.CreateUtf8('%.GetHeader error=%', [self, err]);
      {$I+}
      if line[0] = #0 then
        break; // HTTP headers end with a void line
      Http.ParseHeader(@line, {linelen=}-1, HeadersUnFiltered);
      if Http.State <> hrsNoStateMachine then
        exit; // error
    until false
  else
    repeat
      SockRecvLn(s);
      if s = '' then
        break;
      Http.ParseHeader(pointer(s), length(s), HeadersUnFiltered);
      if Http.State <> hrsNoStateMachine then
        exit; // error
    until false;
  // finalize the headers
  result := true;
  Http.ParseHeaderFinalize; // compute all meaningful headers
  if Assigned(OnLog) then
    OnLog(sllTrace, 'GetHeader % % flags=% len=% %', [Http.CommandMethod,
      Http.CommandUri, ToText(Http.HeaderFlags), Http.ContentLength,
      Http.ContentType], self);
end;

procedure THttpSocket.GetBody(DestStream: TStream);
var
  line: RawUtf8;
  chunkline: array[0..31] of AnsiChar; // 32 bits chunk length in hexa
  chunk: RawByteString;
  len32, err: integer;
  len64: Int64;
begin
  fBodyRetrieved := true;
  Http.Content := '';
  if DestStream <> nil then
    if (cardinal(Http.CompressContentEncoding) < cardinal(length(Http.Compress))) then
      raise EHttpSocket.CreateUtf8('%.GetBody(%) does not support compression',
        [self, DestStream]);
  {$I-}
  // direct read bytes, as indicated by Content-Length or Chunked
  if hfTransferChunked in Http.HeaderFlags then
  begin
    // Content-Length header should be ignored when chunked by RFC 2616 #4.4.3
    Http.ContentLength := 0;
    repeat // chunks decoding loop
      if SockIn <> nil then
      begin
        readln(SockIn^, chunkline); // use of a static PChar is faster
        err := ioresult;
        if err <> 0 then
          raise EHttpSocket.CreateUtf8('%.GetBody chunked ioresult=%', [self, err]);
        len32 := HttpChunkToHex32(chunkline); // get chunk length in hexa
      end
      else
      begin
        SockRecvLn(line);
        len32 := HttpChunkToHex32(pointer(line)); // get chunk length in hexa
      end;
      if len32 = 0 then
      begin
        SockRecvLn; // ignore next line (normally void)
        break; // reached the end of input stream
      end;
      if DestStream <> nil then
      begin
        if length({%H-}chunk) < len32 then
          SetString(chunk, nil, len32 + len32 shr 3); // +shr 3 to avoid realloc
        SockInRead(pointer(chunk), len32);
        DestStream.WriteBuffer(pointer(chunk)^, len32);
      end
      else
      begin
        SetLength(Http.Content, Http.ContentLength + len32); // reserve space for this chunk
        SockInRead(@PByteArray(Http.Content)[Http.ContentLength], len32); // append data
      end;
      inc(Http.ContentLength, len32);
      SockRecvLn; // ignore next #13#10
    until false;
  end
  else if Http.ContentLength > 0 then
    // read Content-Length header bytes
    if DestStream <> nil then
    begin
      len32 := 256 shl 10; // not chunked: use a 256 KB temp buffer
      if Http.ContentLength < len32 then
        len32 := Http.ContentLength;
      SetLength(chunk, len32);
      len64 := Http.ContentLength;
      repeat
        if len32 > len64 then
          len32 := len64;
        SockInRead(pointer(chunk), len32);
        DestStream.WriteBuffer(pointer(chunk)^, len32);
        dec(len64, len32);
      until len64 = 0;
    end
    else
    begin
      SetLength(Http.Content, Http.ContentLength); // not chuncked: direct read
      SockInRead(pointer(Http.Content), Http.ContentLength);
    end
  else if Http.ContentLength < 0 then // -1 means no Content-Length header
  begin
    // no Content-Length neither chunk -> read until the connection is closed
    // also for HTTP/1.1: https://www.rfc-editor.org/rfc/rfc7230#section-3.3.3
    if Assigned(OnLog) then
      OnLog(sllTrace, 'GetBody deprecated loop', [], self);
    // body = either Content-Length or Transfer-Encoding (HTTP/1.1 RFC2616 4.3)
    if SockIn <> nil then // client loop for compatibility with oldest servers
      while not eof(SockIn^) do
      begin
        readln(SockIn^, line);
        if Http.Content = '' then
          Http.Content := line
        else
          Http.Content := Http.Content + #13#10 + line;
      end;
    Http.ContentLength := length(Http.Content); // update Content-Length
    if DestStream <> nil then
    begin
      DestStream.WriteBuffer(pointer(Http.Content)^, Http.ContentLength);
      Http.Content := '';
    end;
    exit;
  end;
  // optionaly uncompress content
  if Http.CompressContentEncoding >= 0 then
    Http.UncompressData;
  if Assigned(OnLog) then
    OnLog(sllTrace, 'GetBody len=%', [Http.ContentLength], self);
  if SockIn <> nil then
  begin
    err := ioresult;
    if err <> 0 then
      raise EHttpSocket.CreateUtf8('%.GetBody ioresult2=%', [self, err]);
  end;
  {$I+}
end;

procedure THttpSocket.HeaderAdd(const aValue: RawUtf8);
begin
  if aValue <> '' then
    Http.Headers := NetConcat([Http.Headers, aValue, #13#10]);
end;

procedure THttpSocket.HeaderSetText(const aText: RawUtf8;
  const aForcedContentType: RawUtf8);
begin
  if aText = '' then
    Http.Headers := ''
  else if aText[length(aText) - 1] <> #10 then
    Http.Headers := aText + #13#10
  else
    Http.Headers := aText;
  if (aForcedContentType <> '') and
     (FindNameValue(pointer(aText), 'CONTENT-TYPE:') = nil) then
    Http.Headers := NetConcat([Http.Headers, 'Content-Type: ', aForcedContentType, #13#10]);
end;

procedure THttpSocket.HeadersPrepare(const aRemoteIP: RawUtf8);
begin
  if (aRemoteIP <> '') and
     not (hfHasRemoteIP in Http.HeaderFlags) then
  begin
    // Http.ParseHeaderFinalize did reserve 40 bytes for fast realloc
    Http.Headers := NetConcat([Http.Headers, 'RemoteIP: ', aRemoteIP, #13#10]);
    include(Http.HeaderFlags, hfHasRemoteIP);
  end;
end;

function THttpSocket.HeaderGetValue(const aUpperName: RawUtf8): RawUtf8;
begin
  result := Http.HeaderGetValue(aUpperName);
end;

function THttpSocket.RegisterCompress(aFunction: THttpSocketCompress;
  aCompressMinSize, aPriority: integer): boolean;
begin
  result := RegisterCompressFunc(Http.Compress, aFunction,
    Http.CompressAcceptEncoding, aCompressMinSize, aPriority) <> '';
end;


{ ******************** Abstract Server-Side Types e.g. for Client-Server Protocol }

{ THttpServerRequestAbstract }

procedure THttpServerRequestAbstract.Prepare(
  const aUrl, aMethod, aInHeaders: RawUtf8; const aInContent: RawByteString;
  const aInContentType, aRemoteIP: RawUtf8);
begin
  // Create or Recycle() would have zeroed other fields
  fRemoteIP := aRemoteIP;
  fUrl := aUrl;
  fMethod := aMethod;
  fInHeaders := aInHeaders;
  fInContentType := aInContentType;
  fInContent := aInContent;
end;

procedure THttpServerRequestAbstract.Prepare(const aHttp: THttpRequestContext;
  const aRemoteIP: RawUtf8; aAuthorize: THttpServerRequestAuthentication);
begin
  fRemoteIP := aRemoteIP;
  fUrl := aHttp.CommandUri;
  fMethod := aHttp.CommandMethod;
  fInHeaders := aHttp.Headers;
  fInContentType := aHttp.ContentType;
  fHost := aHttp.Host;
  if hsrAuthorized in fConnectionFlags then
  begin
    // reflect the current valid "authorization:" header
    fAuthenticationStatus := aAuthorize;
    fAuthenticatedUser := aHttp.BearerToken; // set by fServer.Authorization()
  end
  else
    fAuthBearer := aHttp.BearerToken;
  fUserAgent := aHttp.UserAgent;
  fInContent := aHttp.Content;
end;

procedure THttpServerRequestAbstract.AddInHeader(AppendedHeader: RawUtf8);
begin
  TrimSelf(AppendedHeader);
  if AppendedHeader <> '' then
    if fInHeaders = '' then
      fInHeaders := AppendedHeader
    else
      fInHeaders := NetConcat([fInHeaders, #13#10, AppendedHeader]);
end;

procedure THttpServerRequestAbstract.AddOutHeader(const Values: array of const);
begin
  AppendLine(fOutCustomHeaders, Values);
end;

function THttpServerRequestAbstract.GetRouteValuePosLen(const Name: RawUtf8;
  var Value: TValuePUtf8Char): boolean;
var
  i: PtrInt;
  v: PIntegerArray;
begin
  result := false;
  Value.Text := nil;
  Value.Len := 0;
  if (self = nil) or
     (Name = '') or
     (fRouteName = nil) then
    exit;
  i := FindNonVoidRawUtf8(fRouteName, pointer(Name), length(Name),
                          PDALen(PAnsiChar(fRouteName) - _DALEN)^ + _DAOFF);
  if i < 0 then
    exit;
  v := @fRouteValuePosLen[i * 2]; // one [pos,len] pair in fUrl
  Value.Text := PUtf8Char(pointer(fUrl)) + v[0];
  Value.Len := v[1];
  result := true;
end;

function THttpServerRequestAbstract.GetRouteValue(const Name: RawUtf8): RawUtf8;
var
  v: TValuePUtf8Char;
begin
  GetRouteValuePosLen(Name, v);
  v.ToUtf8(result);
end;

function THttpServerRequestAbstract.RouteInt64(const Name: RawUtf8;
  out Value: Int64): boolean;
var
  v: TValuePUtf8Char;
begin
  result := GetRouteValuePosLen(Name, v);
  if result then
    Value := v.ToInt64;
end;

function THttpServerRequestAbstract.RouteUtf8(const Name: RawUtf8;
  out Value: RawUtf8): boolean;
var
  v: TValuePUtf8Char;
begin
  result := GetRouteValuePosLen(Name, v);
  if result then
    v.ToUtf8(Value);
end;

function THttpServerRequestAbstract.RouteEquals(
  const Name, ExpectedValue: RawUtf8): boolean;
var
  v: TValuePUtf8Char;
begin
  result := GetRouteValuePosLen(Name, v) and
            (CompareBuf(ExpectedValue, v.Text, v.Len) = 0);
end;

function THttpServerRequestAbstract.UrlParam(const UpperName: RawUtf8;
  out Value: RawUtf8): boolean;
begin
  if fUrlParamPos = nil then // may have been set by TUriTreeNode.LookupParam
    fUrlParamPos := PosChar(pointer(Url), '?');
  result := UrlDecodeParam(fUrlParamPos, UpperName, Value);
end;

function THttpServerRequestAbstract.UrlParam(const UpperName: RawUtf8;
  out Value: cardinal): boolean;
begin
  if fUrlParamPos = nil then
    fUrlParamPos := PosChar(pointer(Url), '?');
  result := UrlDecodeParam(fUrlParamPos, UpperName, Value);
end;

function THttpServerRequestAbstract.UrlParam(const UpperName: RawUtf8;
  out Value: Int64): boolean;
begin
  if fUrlParamPos = nil then
    fUrlParamPos := PosChar(pointer(Url), '?');
  result := UrlDecodeParam(fUrlParamPos, UpperName, Value);
end;

procedure THttpServerRequestAbstract.SetOutJson(const Json: RawUtf8);
begin
  fOutContent := Json;
  fOutContentType := JSON_CONTENT_TYPE_VAR;
end;

procedure THttpServerRequestAbstract.SetOutJson(const Fmt: RawUtf8;
  const Args: array of const);
begin
  FormatUtf8(Fmt, Args, RawUtf8(fOutContent));
  fOutContentType := JSON_CONTENT_TYPE_VAR;
end;

procedure THttpServerRequestAbstract.SetOutText(
  const Fmt: RawUtf8; const Args: array of const; const ContentType: RawUtf8);
begin
  FormatUtf8(Fmt, Args, RawUtf8(fOutContent));
  fOutContentType := ContentType;
end;


{ THttpAcceptBan }

constructor THttpAcceptBan.Create(
  banseconds, maxpersecond, banwhiteip: cardinal);
begin
  fMax := maxpersecond;
  SetSeconds(banseconds);
  fWhiteIP := banwhiteip;
  fSafe.Init;
end;

destructor THttpAcceptBan.Destroy;
begin
  inherited Destroy;
  fSafe.Done;
end;

procedure THttpAcceptBan.SetMax(Value: cardinal);
begin
  fSafe.Lock;
  try
    fMax := Value;
    SetIP;
  finally
    fSafe.UnLock;
  end;
end;

procedure THttpAcceptBan.SetSeconds(Value: cardinal);
var
  v: cardinal;
begin
  v := 128; // don't consume too much memory
  while (Value < v) and
        (v > 1) do
    v := v shr 1; // find closest power of two
  fSafe.Lock;
  try
    fSeconds := v;
    SetIP;
  finally
    fSafe.UnLock;
  end;
end;

procedure THttpAcceptBan.SetIP;
var
  i: PtrInt;
begin
  fCount := 0;
  fLastSec := 0;
  fIP := nil;
  if fMax = 0 then
    exit;
  SetLength(fIP, fSeconds); // fIP[secs,0]=count fIP[secs,1..fMax]=ips
  for i := 0 to fSeconds - 1 do
    SetLength(fIP[i], fMax + 1);
end;

function THttpAcceptBan.BanIP(ip4: cardinal): boolean;
var
  P: PCardinalArray;
begin
  if (self = nil) or
     (ip4 = 0) or
     (ip4 = fWhiteIP) then
   result := false
  else
  begin
    fSafe.Lock; // very quick O(1) process in the lock
    if fMax <> 0 then
      {$ifdef HASFASTTRYFINALLY}
      try
      {$else}
      begin
      {$endif HASFASTTRYFINALLY}
        P := pointer(fIP[fLastSec]); // fIP[secs,0]=count fIP[secs,1..fMax]=ips
        if P[0] < fMax then
        begin
          inc(P[0]);
          inc(fCount);
        end;
        P[P[0]] := ip4;
        inc(fTotal);
      {$ifdef HASFASTTRYFINALLY}
      finally
      {$endif HASFASTTRYFINALLY}
        fSafe.UnLock;
      end;
    result := true;
  end;
end;

function THttpAcceptBan.BanIP(const ip4: RawUtf8): boolean;
var
  c: cardinal;
begin
  result := (self <> nil) and
            NetIsIP4(pointer(ip4), @c) and
             ({%H-}c <> 0) and
             (c <> fWhiteIP) and
             BanIP(c);
end;

function THttpAcceptBan.IsBanned(const addr: TNetAddr): boolean;
var
  ip4: cardinal;
begin
  result := false;
  if (self = nil) or
     (fCount = 0) then
    exit;
  ip4 := addr.IP4;
  if (ip4 = 0) or
     (ip4 = fWhiteIP) then
    exit;
  result := IsBannedRaw(ip4);
end;

function THttpAcceptBan.IsBanned(ip4: cardinal): boolean;
begin
  result := (self <> nil) and
            (fCount <> 0) and
            (ip4 <> 0) and
            (ip4 <> fWhiteIP) and
            IsBannedRaw(ip4);
end;

function THttpAcceptBan.IsBannedRaw(ip4: cardinal): boolean;
var
  s: ^PCardinalArray;
  P: PCardinalArray;
  n: cardinal;
  cnt: PtrInt;
begin
  result := false;
  fSafe.Lock; // O(n) process, but from the main accept() thread only
  {$ifdef HASFASTTRYFINALLY}
  try
  {$else}
  begin
  {$endif HASFASTTRYFINALLY}
    s := pointer(fIP); // fIP[secs,0]=count fIP[secs,1..fMax]=ips
    n := fSeconds;
    if n <> 0 then
      repeat
        P := s^;
        inc(s);
        cnt := P[0];
        if (cnt <> 0) and
           IntegerScanExists(@P[1], cnt, ip4) then // O(n) SSE2 asm on Intel
        begin
          inc(fRejected);
          result := true;
          break;
        end;
        dec(n);
      until n = 0;
  {$ifdef HASFASTTRYFINALLY}
  finally
  {$endif HASFASTTRYFINALLY}
    fSafe.UnLock;
  end;
end;

function THttpAcceptBan.ShouldBan(status, ip4: cardinal): boolean;
begin
  result := (self <> nil) and
            ((status = HTTP_BADREQUEST) or     // disallow 400,402..xxx
             (status > HTTP_UNAUTHORIZED)) and // allow 401 response
            BanIP(ip4)
end;

function THttpAcceptBan.ShouldBan(status: cardinal; const ip4: RawUtf8): boolean;
begin
  result := (self <> nil) and
            ((status = HTTP_BADREQUEST) or     // disallow 400,402..xxx
             (status > HTTP_UNAUTHORIZED)) and // allow 401 response
            BanIP(ip4)
end;

procedure THttpAcceptBan.DoRotate;
var
  n: PtrInt;
  p: PCardinal;
begin
  if (self = nil) or
     (fCount = 0) then
    exit;
  fSafe.Lock; // very quick O(1) process
  try
    if fCount <> 0 then
    begin
      n := fSeconds - 1;         // power of two bitmask
      n := (fLastSec + 1) and n; // per-second round robin
      fLastSec := n;
      p := @fIP[n][0]; // fIP[secs,0]=count fIP[secs,1..fMax]=ips
      dec(fCount, p^);
      p^ := 0;         // the oldest slot becomes the current (no memory move)
    end;
  finally
    fSafe.UnLock;
  end;
end;


{ TWebServerGlobal }

constructor TWebServerGlobal.Create;
begin
  inherited Create;
  fMimeTypes.InitSpecific(TypeInfo(TWebServerMimeTypeDynArray), fMimeType,
    ptPUtf8Char, @fMimeTypeCount, {caseinsensitive=}true);
  // index TWebServerMimeType.Extension as ptPUtf8Char for FindMimeType()
end;

function TWebServerGlobal.FindMimeType(Extension: PUtf8Char): PtrInt;
begin
  result := fMimeTypes.FindHashed(Extension); // search as PUtf8Char
end;

function TWebServerGlobal.AddIfNeeded(const Extension: RawUtf8): PtrInt;
var
  added: boolean;
begin
  result := -1;
  if Extension = '' then
    exit;
  result := fMimeTypes.FindHashedForAdding(Extension, added);
  if added then
    fMimeType[result].Extension := Extension;
end;

function TWebServerGlobal.AddToIndexes(var Indexes: TSortedWordArray;
  const Extension: RawUtf8): PtrInt;
begin
  result := AddIfNeeded(Extension);
  if (result >= 0) and
     (result <= high(word)) then
    Indexes.Add(result);
end;

function TWebServerGlobal.Request(Context: THttpServerRequestAbstract;
  const Local: TWebServerLocal): cardinal;
begin
  result := 0; // should continue the process

end;



{ ******************** HTTP Server Logging/Monitoring Processors }

{ THttpAfterResponse }

constructor THttpAfterResponse.Create;
begin
  fSafe.Init;
end;

destructor THttpAfterResponse.Destroy;
begin
  inherited Destroy;
  fSafe.Done;
end;


{ THttpLoggerWriter }

procedure THttpLoggerWriter.SetRotateDate;
var
  dt: TDateTime;
  day: integer;
begin
  dt := NowUtc; // no local date/time because it may go back in time
  day := Trunc(dt);
  case fRotate of
    hlrDaily:
      // trigger next day just after UTC midnight
      fRotateDate := day + 1;
    hlrWeekly:
      // Sunday is DayOfWeek 1, Saturday is 7
      fRotateDate := day + 8 - DayOfWeek(dt); // next Sunday after UTC midnight
  end;
end;

procedure THttpLoggerWriter.TryRotate(Tix10: cardinal);
var
  needrotate: boolean;
begin
  // quickly check if we need to rotate this .log file
  if (fStream = nil) or
     not fRotating.TryLock then
    exit; // avoid race condition (paranoid)
  needrotate := fTotalFileSize >= 100 shl 20; // force always above 100MB
  case fRotate of
    hlrDaily,
    hlrWeekly:
      if Tix10 >= fRotateTix10 then
      begin
        fRotateTix10 := Tix10 + 60 * 60; // check fRotateDate every hour
        if Trunc(NowUtc) >= fRotateDate then
        begin
          SetRotateDate; // always prepare next rotation date
          needrotate := TextLength <> 0; // something to rotate
        end;
      end;
    hlrAfter1MB:
      needrotate := fTotalFileSize >= 1 shl 20;
    hlrAfter10MB:
      needrotate := fTotalFileSize >= 10 shl 20;
    hlrAfter32MB:
      needrotate := fTotalFileSize >= 32 shl 20;
  end; // hlrAfter100MB + hlrUndefined = above 100MB
  if needrotate then
  try
    // rotate the file now - in a dedicated method
    DoRotate;
  finally
    fRotating.UnLock; // eventual release
  end
  else
    fRotating.UnLock; // quick execution path if nothing to rotate
end;

procedure THttpLoggerWriter.DoRotate;
var
  fn: array of TFileName;
  tocompress: TFileName;
  i, old: PtrInt;
begin
  fOwner.fSafe.Lock;
  try
    // close this .log file
    FlushFinal;
    FreeAndNil(fStream);
    if fRotateFiles > 0 then
    begin
      // perform file rotations similar to the standard logrotate tool
      SetLength(fn, fRotateFiles); // = 9 by default
      old := 0;
      for i := fRotateFiles downto 1 do
      begin
        fn[i - 1] := FormatString('%.%.gz', [fFileName, i]);
        if (old = 0) and
           FileExists(fn[i - 1]) then
          old := i;
      end;
      if old = fRotateFiles then
        DeleteFile(fn[old - 1]);         // delete e.g. 'xxx.9.gz'
      for i := fRotateFiles - 1 downto 1 do
        RenameFile(fn[i - 1], fn[i]);    // e.g. 'xxx.8.gz' -> 'xxx.9.gz'
      tocompress := fFileName + '.tmp';
      RenameFile(fFileName, tocompress); // 'xxx' -> 'xxx.tmp'
    end;
    // create a new .log file with the same file name
    fStream := TFileStreamEx.Create(fFileName, fmCreate or fmShareDenyWrite);
    CancelAll;
  finally
    fOwner.fSafe.UnLock;
  end;
  // compress 'xxx.tmp' -> 'xxx.1.gz' outside the main lock
  if tocompress <> '' then
    try
      GZFile(tocompress, fn[0], {level=}1); // may use libdeflate
    finally
      DeleteFile(tocompress);
    end;
end;

procedure THttpLoggerWriter.WriteToStream(data: pointer; len: PtrUInt);
begin
  // no need of THttpLogger.OnIdle to flush this log file within this second
  fLastWriteToStreamTix10 := GetTickCount64 shr 10;
  // perform the actual flush to disk
  inherited WriteToStream(data, len);
end;

constructor THttpLoggerWriter.Create(aOwner: THttpLogger; const aHost: RawUtf8;
  aRotate: THttpLoggerRotate; aRotateFiles: integer);
begin
  fHost := aHost;
  fOwner := aOwner;
  fRotate := aRotate;
  fFileName := fOwner.GetPerHostFileName(aHost);
  inherited Create(TFileStreamEx.CreateWrite(fFileName), 65536);
  fCustomOptions := [twoNoWriteToStreamException,
                     twoFlushToStreamNoAutoResize,
                     twoStreamIsOwned];
  SetRotateDate;
end;

destructor THttpLoggerWriter.Destroy;
begin
  FlushFinal;
  inherited Destroy;
end;


{ THttpLogger }

constructor THttpLogger.Create;
begin
  inherited Create;  // fSafe.Init
  fLineFeed := CRLF; // default operating-system dependent Line Feed
  fDefaultRotate := hlrAfter10MB;
  fDefaultRotateFiles := 9;
  fDestMainLog := 'access.log';
end;

constructor THttpLogger.CreateWithWriter(aWriter: TTextDateWriter;
  const aFormat: RawUtf8);
var
  err: RawUtf8;
begin
  Create;
  fWriterSingle := aWriter;
  if aFormat = '' then
    exit; // format will be supplied later
  err := Parse(aFormat);
  if err <> '' then
    raise EHttpLogger.CreateUtf8('%.Create: %', [self, err]);
end;

constructor THttpLogger.CreateWithFile(const aFileName: TFileName;
  const aFormat: RawUtf8);
begin
  fFlags := [ffOwnWriterSingle];
  CreateWithWriter(TTextDateWriter.CreateOwnedFileStream(aFileName, 65536), aFormat);
end;

destructor THttpLogger.Destroy;
var
  i: PtrInt;
begin
  inherited Destroy;
  if fWriterSingle <> nil then
    fWriterSingle.FlushFinal;
  if ffOwnWriterSingle in fFlags then
    FreeAndNilSafe(fWriterSingle);
  for i := 0 to high(fWriterHost) do
    FreeAndNilSafe(fWriterHost[i]);
end;

procedure THttpLogger.OnIdle(tix64: Int64);
var
  i: PtrInt;
  tix10: cardinal;
begin
  // optionally merge calls
  if Assigned(fOnContinue) then
    fOnContinue.OnIdle(tix64);
  // flush the log file(s) if needed
  if (fWriterHost = nil) and
     (fWriterSingle = nil) then
    exit; // nothing to process
  fSafe.Lock;
  try
    // force write to disk at least every second
    if fWriterSingle <> nil then
      fWriterSingle.FlushFinal;
    if (fWriterHost <> nil) and
       fWriterHostSafe.TryLock then
      try
        tix10 := tix64 shr 10;
        for i := 0 to length(fWriterHost) - 1 do
          with fWriterHost[i] do
            if fLastWriteToStreamTix10 <> tix10 then
              FlushFinal; // no TryRotate(tix10) since may be slow
      finally
        fWriterHostSafe.UnLock;
      end;
  finally
    fSafe.UnLock;
  end;
end;

function THttpLogger.GetPerHostFileName(const aHost: RawUtf8): TFileName;
begin
  if fDestFolder = '' then
    fDestFolder := GetSystemPath(spLog); // default if not customized
  result := fDestFolder;
  if aHost = '' then
    result := result + fDestMainLog
  else
    result := FormatString('%%.log', [result, LowerCase(aHost)]);
end;

function THttpLogger.GetWriter(
  Tix10: cardinal; const Host: RawUtf8): TTextDateWriter;
var
  n: integer;
  p: ^THttpLoggerWriter;
begin
  // quickly retrieve the corresponding instance
  result := fWriterSingle;
  if result <> nil then
    exit;
  if Host <> '' then
  begin
    result := fWriterHostLast; // pointer-sized variables are atomic
    if (result <> nil) and     // naive but efficient cache
       IdemPropNameU(THttpLoggerWriter(result).Host, Host) then
    begin
      THttpLoggerWriter(result).TryRotate(Tix10);
      exit;
    end;
  end;
  // lookup of this Host in the internal WriteHost[] list
  fWriterHostSafe.Lock;
  p := pointer(fWriterHost);
  if p = nil then
    // no previous DefineHost() call: set WriterHost[0] = access.log instance
    try
      result := THttpLoggerWriter.Create(
                  self, '', fDefaultRotate, fDefaultRotateFiles);
      ObjArrayAdd(fWriterHost, result);
    finally
      fWriterHostSafe.UnLock;
    end
  else
  begin
    // search for any matching THttpLoggerWriter.Host value
    result := p^; // p^ = WriterHost[0] = access.log as default
    if Host <> '' then
    begin
      n := PDALen(PAnsiChar(p) - _DALEN)^ + _DAOFF;
      repeat
        inc(p);
        dec(n);
        if n = 0 then
          break;
        if IdemPropNameU(p^.Host, Host) then
        begin
          result := p^; // found log instance for this Host name
          fWriterHostLast := result;
          break;
        end;
      until false;
    end;
    fWriterHostSafe.UnLock;
    THttpLoggerWriter(result).TryRotate(Tix10); // outside the lock
  end;
end;

procedure THttpLogger.DefineHost(const aHost: RawUtf8;
  aRotate: THttpLoggerRotate; aRotateFiles: integer);
var
  i: PtrInt;
  w: THttpLoggerWriter;
  h: RawUtf8;
begin
  h := OnlyChar(LowerCase(aHost), ['a'..'z', '0'..'9', '.', '%']);
  if (h = '') or
     (fWriterSingle <> nil) then
    raise EHttpLogger.CreateUtf8('Unexpected %.DefineHost(%)', [self, aHost]);
  fWriterHostSafe.Lock;
  try
    if fWriterHost = nil then
      // first call: we need to set WriterHost[0] = access.log
      ObjArrayAdd(fWriterHost, THttpLoggerWriter.Create(
             self, '', fDefaultRotate, fDefaultRotateFiles))
    else
      // search if we need to update a previous DefineHost()
      for i := 1 to length(fWriterHost) - 1 do
      begin
        w := fWriterHost[i];
        if IdemPropNameU(w.Host, h) then
        begin
          if aRotateFiles >= 0 then
            w.fRotateFiles := aRotateFiles;
          if aRotate <> hlrUndefined then
            w.fRotate := aRotate;
          w.SetRotateDate;
          exit;
        end;
      end;
    // add a new definition for this specific host
    if aRotate = hlrUndefined then
      aRotate := fDefaultRotate;
    if aRotateFiles < 0 then
      aRotateFiles := fDefaultRotateFiles;
    w := THttpLoggerWriter.Create(self, h, aRotate, aRotateFiles);
    ObjArrayAdd(fWriterHost, w);
  finally
    fWriterHostSafe.UnLock;
  end;
end;

procedure THttpLogger.SetFormat(const aFormat: RawUtf8);
var
  err: RawUtf8;
begin
  err := Parse(aFormat);
  if err <> '' then
    raise EHttpLogger.CreateUtf8('%.SetFormat: % in [%]', [self, err, aFormat]);
end;

procedure THttpLogger.SetDestFolder(const aFolder: TFileName);
begin
  if (fWriterHost <> nil) or
     (fWriterSingle <> nil) then
    raise EHttpLogger.CreateUtf8(
      'Impossible to set %.DestFolder once started', [self]);
  fDestFolder := EnsureDirectoryExists(aFolder, EHttpLogger);
  if not IsDirectoryWritable(fDestFolder, [idwExcludeWinSys]) then
    // better fail ASAP
    raise EHttpLogger.CreateUtf8('Not writable %.DestFolder = %', [self, aFolder]);
end;

function THttpLogger.Parse(const aFormat: RawUtf8): RawUtf8;
var
  p, start: PUtf8Char;
  v: integer;
begin
  // reset any previous format
  fVariable := nil;
  fVariables := [];
  fUnknownPosLen := nil;
  // actually parse the input
  result := 'No Format';
  if aFormat = '' then
    exit;
  result := 'Format is too long';
  if length(aFormat) shr 16 <> 0 then
    exit; // fUnknownPosLen[] are encoded as two 16-bit values
  result := '';
  fFormat := aFormat;
  p := pointer(aFormat);
  repeat
    start := p;
    while not (p^ in [#0, '$']) do
      inc(p);
    if p <> start then
    begin
      SetLength(fVariable, length(fVariable) + 1); // append 0 = hlvUnknown
      AddInteger(fUnknownPosLen, (start - pointer(aFormat)) +  // 16-bit pos
                                 ((p - start) shl 16))         // 16-bit len
    end;
    if p^ = #0 then
      break;
    inc(p); // ignore '$'
    start := p;
    while tcIdentifier in TEXT_CHARS[p^] do
      inc(p);
    v := GetEnumNameValueTrimmed(TypeInfo(THttpLogVariable), start, p - start);
    if v <= 0 then
    begin
      FormatUtf8('Unknown $% variable', [start], result);
      break;
    end;
    SetLength(fVariable, length(fVariable) + 1);
    fVariable[high(fVariable)] := THttpLogVariable(v);
    include(fVariables, THttpLogVariable(v));
  until false;
  // reset internal state on error parsing
  if result = '' then
    exit;
  fFormat := '';
  fVariable := nil;
  fVariables := [];
  fUnknownPosLen := nil;
end;

procedure THttpLogger.Append(const Context: TOnHttpServerAfterResponseContext);
var
  n: integer;
  tix10: cardinal;
  l: PtrInt;
  v: ^THttpLogVariable;
  poslen: PWordArray; // pos1,len1, pos2,len2, ... 16-bit pairs
  wr: TTextDateWriter;
const
  SCHEME: array[boolean] of string[7]  = ('http', 'https');
  HTTP:   array[boolean] of string[15] = ('HTTP/1.1', 'HTTP/1.0');
begin
  // optionally merge calls
  if Assigned(fOnContinue) then
    fOnContinue.Append(Context);
  if fVariable = nil then // nothing to process
    exit;
  // retrieve the output stream for the expected .log file
  tix10 := GetTickCount64 shr 10;
  wr := GetWriter(tix10, RawUtf8(Context.Host));
  if (wr = nil) or
     (wr.Stream = nil) then
    exit;
  // very efficient log generation with no transient memory allocation
  v := pointer(fVariable);
  n := length(fVariable);
  poslen := pointer(fUnknownPosLen); // 32-bit array into 16-bit pos,len pairs
  fSafe.Lock;
  {$ifdef HASFASTTRYFINALLY}
  try
  {$else}
  begin
    // code within the loop should not raise exceptions
  {$endif HASFASTTRYFINALLY}
    repeat
      case v^ of // compile as a fast lookup table jump on FPC
        hlvUnknown: // plain text
          begin
            wr.AddNoJsonEscape(@PByteArray(fFormat)[poslen^[0]], poslen^[1]);
            poslen := @poslen^[2]; // next pos,len pair
          end;
        hlvBody_Bytes_Sent, // no body size by now
        hlvBytes_Sent:
          wr.AddQ(Context.Sent);
        hlvConnection:
          wr.AddQ(Context.Connection); // Connection ID (or Serial)
        hlvConnection_Flags:
          PRttiInfo(TypeInfo(THttpServerRequestFlag))^.
            EnumBaseType^.GetSetNameJsonArray(
              wr, byte(Context.Flags), ',', #0, {fullasstar=}false, {trim=}true);
        hlvConnection_Upgrade:
          if hsrConnectionUpgrade in Context.Flags then
            wr.AddShorter('upgrade');
        hlvDocument_Uri,
        hlvUri:
          if Context.Url <> nil then
          begin
            l := PosExChar('?', RawUtf8(Context.Url)) - 1; // exclude arguments
            if l < 0 then
              l := length(RawUtf8(Context.Url));
            wr.AddUrlNameNormalize(Context.Url, l); // URL decode + // normalize
          end;
        hlvElapsed:
          wr.AddShort(MicroSecToString(Context.ElapsedMicroSec));
        hlvElapsedUSec:
          wr.AddQ(Context.ElapsedMicroSec);
        hlvElapsedMSec,
        hlvRequest_Time: // no socket communication time included by now
          if Context.ElapsedMicroSec < 1000 then
            wr.Add('0') // less than 1 ms
          else
            wr.AddSeconds(QWord(Context.ElapsedMicroSec) div 1000);
        hlvHostName:
          if (Context.Host = nil) or
             ((PClass(wr)^ = THttpLoggerWriter) and
              (THttpLoggerWriter(wr).Host <> '')) then
            wr.Add('-') // no need to write $hostname in a per-host log
          else
            wr.AddString(RawUtf8(Context.Host));
        hlvHttp_Referer:
          if Context.Referer = nil then
            wr.Add('-')
          else
            wr.AddString(RawUtf8(Context.Referer));
        hlvHttp_User_Agent:
          if Context.UserAgent = nil then
            wr.Add('-')
          else
            wr.AddString(RawUtf8(Context.UserAgent));
        hlvHttps:
          if hsrHttps in Context.Flags then
            wr.AddShorter('on');
        hlvMsec:
          wr.AddSeconds(UnixMSTimeUtcFast);
        hlvReceived:
          wr.AddShort(KBNoSpace(Context.Received));
        hlvRemote_Addr:
          if Context.RemoteIP = nil then
            wr.AddShort('127.0.0.1')
          else
            wr.AddString(RawUtf8(Context.RemoteIP));
        hlvRemote_User:
          if Context.User = nil then
            wr.Add('-')
          else
            wr.AddString(RawUtf8(Context.User));
        hlvRequest:
          begin
            wr.AddString(RawUtf8(Context.Method));
            wr.Add(' ');
            wr.AddString(RawUtf8(Context.Url)); // full request = not normalized
            wr.Add(' ');
            wr.AddShorter(HTTP[hsrHttp10 in Context.Flags]);
          end;
        hlvRequest_Hash:
            wr.AddUHex(crc32c(crc32c(crc32c(byte(Context.Flags),
              Context.Host, length(RawUtf8(Context.Host))),
              Context.Method, length(RawUtf8(Context.Method))),
              Context.Url, length(RawUtf8(Context.Url))));
        hlvRequest_Length:
          wr.AddQ(Context.Received);
        hlvRequest_Method:
          wr.AddString(RawUtf8(Context.Method));
        hlvRequest_Uri:
          wr.AddString(RawUtf8(Context.Url)); // include arguments
        hlvScheme:
          wr.AddShorter(SCHEME[hsrHttps in Context.Flags]);
        hlvSent:
          wr.AddShort(KBNoSpace(Context.Sent));
        hlvServer_Protocol:
           wr.AddShorter(HTTP[hsrHttp10 in Context.Flags]);
        hlvStatus:
          wr.AddU(Context.StatusCode);
        hlvStatus_Text:
          wr.AddShort(StatusCodeToShort(Context.StatusCode));
        hlvTime_Epoch:
          wr.AddQ(UnixTimeUtc);
        hlvTime_EpochMSec:
          wr.AddQ(UnixMSTimeUtcFast);
        // dates are all in UTC/GMT as it should on any safe server process
        hlvTime_Iso8601:
          wr.AddCurrentIsoDateTime({local=}false, {ms=}false, 'T', 'Z');
        hlvTime_Local:
          wr.AddCurrentNcsaLogTime({local=}false, '+0000');
        hlvTime_Http:
          wr.AddCurrentHttpTime({local=}false, 'GMT');
      end;
      inc(v);
      dec(n);
    until n = 0;
    wr.AddString(fLineFeed);
    if (PClass(wr)^ = THttpLoggerWriter) and
       (THttpLoggerWriter(wr).fLastWriteToStreamTix10 <> tix10) then
      wr.FlushFinal; // force write to disk at least every second
  {$ifdef HASFASTTRYFINALLY}
  finally
  {$endif HASFASTTRYFINALLY}
    fSafe.UnLock;
  end;
end;

procedure THttpLogger.CopyParams(Another: THttpLogger);
begin
  if (self = nil) or
     (Another = nil) or
     (fWriterHost <> nil) or // too late
     (fWriterSingle <> nil) then
    exit;
  SetDestFolder(Another.DestFolder);
  SetFormat(Another.Format);
  LineFeed := Another.LineFeed;
  DefaultRotate := Another.DefaultRotate;
  DefaultRotateFiles := Another.DefaultRotateFiles;
end;


{ THttpAnalyzerState }

procedure THttpAnalyzerState.Clear;
begin
  Count    := 0;
  Time     := 0;
  UniqueIP := 0;
  Read     := 0;
  Write    := 0;
end;

procedure THttpAnalyzerState.From(const Another: THttpAnalyzerState);
begin
  Count    := Another.Count;
  Time     := Another.Time;
  UniqueIP := Another.UniqueIP;
  Read     := Another.Read;
  Write    := Another.Write;
end;

procedure THttpAnalyzerState.Add(const Another: THttpAnalyzerState);
begin
  inc(Count,    Another.Count);
  inc(Time,     Another.Time);
  inc(UniqueIP, Another.UniqueIP);
  inc(Read,     Another.Read);
  inc(Write,    Another.Write);
end;

procedure THttpAnalyzerState.Sub(const Another: THttpAnalyzerState);
begin
  dec(Count,    Another.Count);
  dec(Time,     Another.Time);
  dec(UniqueIP, Another.UniqueIP);
  dec(Read,     Another.Read);
  dec(Write,    Another.Write);
end;

function THttpAnalyzerState.TimeMicroSec(Period: THttpAnalyzerPeriod): QWord;
begin
  result := Time;
  if Period > hapCurrent then
    result := result * HTTPANALYZER_TIMEUNIT[Period];
end;


{ THttpAnalyzerToSave }

function THttpAnalyzerToSave.DateTime: TDateTime;
begin
  result := (Int64(Date) + UNIXTIME_MINIMAL) / SecsPerDay + UnixDateDelta;
end;


{ THttpAnalyzer }

constructor THttpAnalyzer.Create(const aSuspendFile: TFileName;
  aSuspendFileSaveMinutes: integer);
var
  tmp: RawByteString;
  gz: TGZRead;
  fromgz: TUnixTime;
  tix: cardinal;
begin
  inherited Create; // fSafe.Init
  fTracked := [low(THttpAnalyzerScope) .. high(THttpAnalyzerScope)];
  fSaved := fTracked;
  fSuspendFile := aSuspendFile;
  fSuspendFileAutoSaveMinutes := aSuspendFileSaveMinutes;
  fromgz := 0;
  tmp := StringFromFile(fSuspendFile);
  if (tmp <> '') and
     (length(tmp) <= SizeOf(fState)) and
     gz.Init(pointer(tmp), length(tmp)) and
     (gz.uncomplen32 = SizeOf(fState)) then
    if gz.ToBuffer(@fState) then
      fromgz := FileAgeToUnixTimeUtc(fSuspendFile)
    else
      FillcharFast(fState, SizeOf(fState), 0);
  ComputeConsolidateTime(hapAll, fromgz);
  tix := GetTickCount64 div 1000;
  if fromgz <> 0 then
    Consolidate(tix); // consolidate old data
  if fSuspendFileAutoSaveMinutes <> 0 then
    fSuspendFileAutoSaveTix := tix + fSuspendFileAutoSaveMinutes * 60;
end;

destructor THttpAnalyzer.Destroy;
var
  p: THttpAnalyzerPeriod;
  now: TDateTime;
begin
  if Assigned(fOnSave) then
  begin
    // persist any pending data still currently in memory buffers
    now := NowUtc;
    for p := low(fConsolidateNextTime) to high(fConsolidateNextTime) do
      fConsolidateNextTime[p] := now; // force consolidation
    Consolidate(0);
    DoSave;
  end;
  if fModified and
     (fSuspendFile <> '') then
    UpdateSuspendFile;
  inherited Destroy;
end;

procedure THttpAnalyzer.SetUniqueIPDepth(value: cardinal);
var
  s: THttpAnalyzerScope;
begin
  if value <> fUniqueIPDepth then
    case value of
      0, 2048, 4096, 8192, 16384, 32768, 65536: // -1 = hash bitmask
        begin
          fSafe.Lock;
          try
            fUniqueIPDepth := value;
            Finalize(fUniqueIP);  // release up to 120KB with max value=65536
            value := value shr 3; // from bits to bytes
            if value <> 0 then
              for s := low(fUniqueIP) to high(fUniqueIP) do
                SetLength(fUniqueIP[s], value);
          finally
            fSafe.UnLock;
          end;
        end
    else
      raise EHttpAnalyzer.CreateUtf8('Invalid %.UniqueDepth=%', [self, value]);
    end;
end;

procedure THttpAnalyzer.ComputeConsolidateTime(
  last: THttpAnalyzerPeriod; ref: TDateTime);
var
  now, t: TSynSystemTime;
begin
  if last < hapMinute then
    exit;
  if ref <> 0 then
    now.FromDateTime(ref) // from SuspendFile .gz
  else
    now.FromNowUtc; // e.g. '2022-10-31T14:23:19.000' is the current time
  now.MilliSecond := 0;
  t := now;
  t.Second := 60;
  t.Normalize;  // e.g. '2022-10-31T14:24:00.000' = start of next minute
  fConsolidateNextTime[hapMinute] := t.ToDateTime;
  if last = hapMinute then
    exit;
  t := now;
  t.Second := 0;
  t.Minute := 60;
  t.Normalize;  // e.g. '2022-10-31T15:00:00.000' = start of next hour
  fConsolidateNextTime[hapHour] := t.ToDateTime;
  if last = hapHour then
    exit;
  t := now;
  t.Second := 0;
  t.Minute := 0;
  t.Hour := 24;
  t.Normalize;  // e.g. '2022-11-01T00:00:00.000' = start of next day
  fConsolidateNextTime[hapDay] := t.ToDateTime;
  if last = hapDay then
    exit;
  t := now;
  t.Second := 0;
  t.Minute := 0;
  t.Hour := 0;
  t.Day := t.DaysInMonth + 1;
  t.Normalize; // e.g. '2022-11-01T00:00:00.000' = start of next month
  fConsolidateNextTime[hapMonth] := t.ToDateTime;
  if last = hapMonth then
    exit;
  t := now;
  t.Second := 0;
  t.Minute := 0;
  t.Hour := 0;
  t.Day := 1;
  t.Month := 13;
  t.Normalize; // e.g. '2023-01-01T00:00:00.000' = start of next year
  fConsolidateNextTime[hapYear] := t.ToDateTime;
end;

procedure THttpAnalyzer.Consolidate(tixsec: cardinal);
var
  p, last: THttpAnalyzerPeriod;
  s: THttpAnalyzerScope;
  savenow: cardinal;
  now: TDateTime;
  ps, ns, al: PHttpAnalyzerState;
  prev, next: PHttpAnalyzerStates;
begin
  // called once per second
  fLastConsolidate := tixsec;
  last := pred(hapMinute);
  now := NowUtc;
  savenow := 0;
  prev := @fState[hapCurrent];
  next := prev;
  al := pointer(@fState[hapAll]);
  for p := low(fConsolidateNextTime) to high(fConsolidateNextTime) do
    if now >= fConsolidateNextTime[p] then
    begin
      // this is consolidation time for this hapMinute..hapYear period
      last := p;
      inc(next);
      ps := pointer(prev);
      ns := pointer(next);
      for s := low(s) to high(s) do
      begin
        if ps^.Count <> 0 then
        begin
          // we have some data to aggregate to this counter
          fModified := true; // for UpdateSuspendFile
          case p of // see HTTPANALYZER_TIMEUNIT[]
            hapMinute:
              begin
                ps^.Time := ps^.Time div 1000; // hapMinute..hapDay in millisec
                al^.Add(ps^); // hapAll updated during hapMinute, in millisec
              end;
            hapMonth:
              ps^.Time := ps^.Time div 1000; // hapMonth/hapYear in sec
          end;
          ns^.Add(ps^);
          // persist previous level before cleaning ps^
          if Assigned(fOnSave) and
             (p < hapYear) and  // OnSave() called in hapMinute..hapMonth range
             (s in fSaved) then
            with fToSave do
            begin
              // persistence is done in the background from fToSave.State[]
              if savenow = 0 then // lock once for the whole method
                savenow := DateTimeToUnixTime(now) - UNIXTIME_MINIMAL;
              if Count = length(State) then
                SetLength(State, NextGrow(Count));
              with State[Count] do
              begin
                Date := savenow;   // as UnixTimeMinimalUtc
                Period := p; // store previous level = hapMinute..hapMonth
                Scope := s;
                State.From(ps^);
              end;
              inc(Count);
            end;
          // reset previous level for a new period
          if (al = nil) and
             (ps^.UniqueIP <> 0) then // clear hapCurrent IP hashtable (max 8KB)
            FillCharFast(pointer(fUniqueIP[s])^, fUniqueIPDepth shr 3, 0);
          ps^.Clear;
        end;
        inc(ns);
        inc(ps);
        if al <> nil then
          inc(al);
      end;
      prev := next;
      al := nil;
    end
    else
      break; // actual computation is done only once per minute
  if last >= hapMinute then
    ComputeConsolidateTime(last, 0);
end;

procedure THttpAnalyzer.DoSave;
var
  tmp: THttpAnalyzerToSaveDynArray;
begin
  // quick retrieve the pending states to persist
  if not Assigned(fOnSave) or
     (fToSave.Count = 0) then
    exit;
  fSafe.Lock;
  try
    with fToSave do
      if Count <> 0 then
      begin
        tmp := copy(State, 0, Count); // use local copy to release lock ASAP
        Count := 0;
      end;
  finally
    fSafe.UnLock;
  end;
  // execute the actual persistence callback outside of the lock
  if tmp <> nil then
    fOnSave(tmp);
end;

procedure THttpAnalyzer.UpdateSuspendFile;
begin
  if (fSuspendFile <> '') and
     not fModified then
    exit;
  fModified := false;
  fSafe.Lock;
  try
    // just save the current state blob as .gz with fastest compression level
    FileFromString(GZWrite(@fState, SizeOf(fState), {level=}1), fSuspendFile);
  finally
    fSafe.UnLock;
  end;
end;

procedure THttpAnalyzer.DoAppend(const new: THttpAnalyzerState;
  s: THttpAnalyzerScope);
var
  p: pointer;
  cur: PHttpAnalyzerState;
begin
  cur := @fState[hapCurrent][s];
  inc(cur^.Count, new.Count);
  inc(cur^.Time,  new.Time);
  inc(cur^.Read,  new.Read);
  inc(cur^.Write, new.Write);
  if new.UniqueIP = 0 then // hash bit index
    exit; // no valid RemoteIP, or UniqueIPDepth is 0
  p := pointer(fUniqueIP[s]);
  if GetBitPtr(p, new.UniqueIP) then // this IP was already included
    exit;
  inc(cur^.UniqueIP);         // first time observed in this scope
  SetBitPtr(p, new.UniqueIP); // mark the bit in the hash table
end;

function ToScope(Text: PUtf8Char; out Scope: THttpAnalyzerScope): boolean;
begin
  result := false;
  case PCardinal(Text)^ of // case-sensitive test in occurence order
    ord('G') + ord('E') shl 8 + ord('T') shl 16:
      Scope := hasGet;
    ord('P') + ord('O') shl 8 + ord('S') shl 16 + ord('T') shl 24:
      Scope := hasPost;
    ord('P') + ord('U') shl 8 + ord('T') shl 16:
      Scope := hasPut;
    ord('H') + ord('E') shl 8 + ord('A') shl 16 + ord('D') shl 24:
      Scope := hasHead;
    ord('D') + ord('E') shl 8 + ord('L') shl 16 + ord('E') shl 24:
      Scope := hasDelete;
    ord('O') + ord('P') shl 8 + ord('T') shl 16 + ord('I') shl 24:
      Scope := hasOptions;
  else
    exit;
  end;
  result := true;
end;

procedure THttpAnalyzer.Append(const Context: TOnHttpServerAfterResponseContext);
var
  tix, crc, i: cardinal;
  s: THttpAnalyzerScope;
  new: THttpAnalyzerState;
begin
  // optionally merge calls
  if Assigned(fOnContinue) then
    fOnContinue.Append(Context);
  // prepare the information to be merged
  if fTracked = [] then
    exit; // nothing to process here
  fModified := true; // for UpdateSuspendFile
  tix := GetTickCount64 div 1000;
  new.Count := 1;
  new.Time := Context.ElapsedMicroSec; // Time unit is microsec for hapCurrent
  new.UniqueIP := 0;
  if (Context.RemoteIP <> nil) and
     (fUniqueIPDepth <> 0) then
  begin
    crc := DefaultHasher(0, Context.RemoteIP, length(RawUtf8(Context.RemoteIP)));
    crc := crc and (fUniqueIPDepth - 1); // power-of-two modulo
    if crc = 0 then
      crc := 1;
    new.UniqueIP := crc; // store bit index
  end;
  new.Read := Context.Received;
  new.Write := Context.Sent;
  fSafe.Lock;
  try
    // integrate request information to the current state
    DoAppend(new, hasAny);
    if (Context.Method <> nil) and
       (fTracked * [hasGet .. hasOptions] <> []) and
       ToScope(Context.Method, s) and
       (s in fTracked) then
      DoAppend(new, s);
    if fTracked * [has1xx .. has5xx] <> [] then
    begin
      i := (Context.StatusCode div 100) - 1; // 1xx..5xx -> 0..4
      if i < 5 then
      begin
        s := THttpAnalyzerScope(byte(has1xx) + i);
        if s in fTracked then
          DoAppend(new, s);
      end;
    end;
    if Context.UserAgent <> nil then
    begin
      if hasMobile in fTracked then
        // browser/OS detection using the User-Agent is a very tricky context
        // https://developer.mozilla.org/en-US/docs/Web/HTTP/Browser_detection_using_the_user_agent
        // we only detect mobile devices, which seems fair enough
        if PosEx('Mobile', RawUtf8(Context.UserAgent)) > 0 then
          DoAppend(new, hasMobile);
      if hasBot in fTracked then
        // bots detection is not easier, but our naive patterns seem good enough
        if IsHttpUserAgentBot(RawUtf8(Context.UserAgent)) then
          DoAppend(new, hasBot);
    end;
    if (hsrHttps in Context.Flags) and
       (hasHttps in fTracked) then
      DoAppend(new, hasHttps);
    if (hsrAuthorized in Context.Flags) and
       (hasAuthorized in fTracked) then
      DoAppend(new, hasAuthorized);
    // do proper consolidation if needed
    if tix <> fLastConsolidate then
      Consolidate(tix); // called once per second, compute once per minute
  finally
    fSafe.UnLock;
  end;
end;

procedure THttpAnalyzer.OnIdle(tix64: Int64);
var
  tix: cardinal;
begin
  // optionally merge calls
  if Assigned(fOnContinue) then
    fOnContinue.OnIdle(tix64);
  // THttpAnalyzer specific process
  tix := tix64 div 1000;
  if tix <> fLastConsolidate then
  begin
    // data consolidation once a second
    fSafe.Lock;
    try
      if tix <> fLastConsolidate then
        Consolidate(tix);
    finally
      fSafe.UnLock;
    end;
  end;
  // background persistence once a hapMinute consolidation did occur
  if Assigned(fOnSave) and
     (fToSave.Count <> 0) then
    DoSave;
  // background state persistence once SuspendFileAutoSaveMinutes
  if fModified and
     (fSuspendFileAutoSaveTix <> 0) and
     (tix > fSuspendFileAutoSaveTix) then
  begin
    fSuspendFileAutoSaveTix := tix + fSuspendFileAutoSaveMinutes * 60;
    UpdateSuspendFile;
  end;
end;

procedure THttpAnalyzer.Get(Period: THttpAnalyzerPeriod;
  Scope: THttpAnalyzerScope; out State: THttpAnalyzerState);
var
  p: THttpAnalyzerPeriod;
begin
  // same value carry propagation algorithm than in Consolidate()
  fSafe.Lock;
  try
    {%H-}State.From(fState[hapCurrent][Scope]);
    if Period = hapCurrent then
      exit;
    State.Time := State.Time div 1000; // hapMinute..hapDay/hapAll in millisec
    if Period = hapAll then
      State.Add(fState[hapAll][Scope])
    else
      for p := hapMinute to Period do // hapMinute..hapYear consolidation
      begin
        if p = hapMonth then
          State.Time := State.Time div 1000; // hapMonth/hapYear in sec
        State.Add(fState[p][Scope]);
      end;
  finally
    fSafe.UnLock;
  end;
end;


{ THttpAnalyzerPersistAbstract }

constructor THttpAnalyzerPersistAbstract.Create(const aFileName: TFileName);
begin
  inherited Create;
  fFileName := ExpandFileName(aFileName);
end;


{ THttpAnalyzerPersistCsv }

var
  _SCOPE: array[THttpAnalyzerScope] of RawUtf8;

const
  _PERIOD: array[THttpAnalyzerPeriod] of string[3] = (
    ',?,', ',m,', ',h,', ',D,', ',M,', ',Y,', ',*,');

procedure THttpAnalyzerPersistCsv.OnSave(
  const State: THttpAnalyzerToSaveDynArray);
var
  n: integer;
  p: PHttpAnalyzerToSave;
  t: TSynSystemTime;
  f: TStream;
  w: TTextDateWriter;
  tmp: TSynTempBuffer;
begin
  if _SCOPE[hasAny] = '' then
    GetEnumTrimmedNames(TypeInfo(THttpAnalyzerScope), @_SCOPE);
  if (State <> nil) and
     (fFileName <> '') then
  try
    f := TFileStreamEx.CreateWrite(fFileName);
    try
      w := TTextDateWriter.Create(f, @tmp, SizeOf(tmp));
      try
        if f.Seek(0, soEnd) = 0 then // append or write header
          w.AddShort('Date,Period,Scope,Count,Time,Read,Write'#13#10);
        n := length(State);
        p := pointer(State);
        repeat
          t.FromDateTime(p^.DateTime);
          t.Second := 0; // seconds part is irrelevant
          if PCardinal(@t.Hour)^ = 0 then // Hour:Minute = 0 ?
            t.AddIsoDate(w) // time part is irrelevant
          else
            t.AddIsoDateTime(w, {ms=}false, {first=}' ');
          w.AddShorter(_PERIOD[p^.Period]);
          w.AddString(_SCOPE[p^.Scope]);
          w.Add(',');
          w.AddQ(p^.State.Count);
          w.Add(',');
          w.AddQ(p^.State.Time);
          w.Add(',');
          w.AddQ(p^.State.Read);
          w.Add(',');
          w.AddQ(p^.State.Write);
          w.AddCR;
          inc(p);
          dec(n);
        until n = 0;
        w.FlushFinal;
      finally
        w.Free;
      end;
    finally
      f.Free;
    end;
  except
    fFileName := ''; // ignore any write error in the callback, but don't retry
  end;
end;


{ THttpAnalyzerPersistJson }

procedure THttpAnalyzerPersistJson.OnSave(
  const State: THttpAnalyzerToSaveDynArray);
var
  n: integer;
  existing: Int64;
  p: PHttpAnalyzerToSave;
  t: TSynSystemTime;
  f: TStream;
  w: TTextDateWriter;
  tmp: TSynTempBuffer;
begin
  // {"d":"xxx","p":x,"s":x,"c":x,"t":x,"r":x,"w":x}
  if (State <> nil) and
     (fFileName <> '') then
  try
    f := TFileStreamEx.CreateWrite(fFileName);
    try
      existing := f.Seek(0, soEnd);
      if existing <> 0 then
        f.Seek(existing - 1, soBeginning); // rewind ending ']'
      w := TTextDateWriter.Create(f, @tmp, SizeOf(tmp));
      try
        if existing = 0 then
          w.Add('[', #10); // open new JSON array
        n := length(State);
        p := pointer(State);
        repeat
          w.AddShorter('{"d":"');
          t.FromDateTime(p^.DateTime);
          t.Second := 0; // seconds part is irrelevant
          if PCardinal(@t.Hour)^ = 0 then // Hour:Minute = 0 ?
            t.AddIsoDate(w) // time part is irrelevant
          else
            t.AddIsoDateTime(w, {ms=}false); // true Iso-8601 date/time
          w.AddShorter('","p":');
          w.AddU(ord(p^.Period));
          w.AddShorter(',"s":');
          w.AddU(ord(p^.Scope));
          w.AddShorter(',"c":');
          w.AddQ(p^.State.Count);
          w.AddShorter(',"t":');
          w.AddQ(p^.State.Time);
          w.AddShorter(',"r":');
          w.AddQ(p^.State.Read);
          w.AddShorter(',"w":');
          w.AddQ(p^.State.Write);
          w.Add('}');
          dec(n);
          if n = 0 then
            break;
          w.Add(',', #10);
          inc(p);
        until false;
        w.Add(']'); // close the JSON array
        w.FlushFinal;
      finally
        w.Free;
      end;
    finally
      f.Free;
    end;
  except
    fFileName := ''; // ignore any write error in the callback, but don't retry
  end;
end;


{ THttpAnalyzerPersistBinary }

procedure THttpAnalyzerPersistBinary.OnSave(
  const State: THttpAnalyzerToSaveDynArray);
var
  f: TStream;
begin
  if (State <> nil) and
     (fFileName <> '') then
  try
    f := TFileStreamEx.CreateWrite(fFileName);
    try
      f.Seek(0, soEnd); // just append
      f.WriteBuffer(pointer(State)^, length(State) * SizeOf(State[0]));
    finally
      f.Free;
    end;
  except
    fFileName := ''; // ignore any write error in the callback, but don't retry
  end;
end;


{ THttpMetrics }

function THttpMetrics.Get(Row: integer): PHttpAnalyzerToSave;
begin
  // caller should have made Safe.Lock
  result := fState.Find(Row * SizeOf(result^), SizeOf(result^));
end;

procedure THttpMetrics.CreateDynArray;
var
  p: pointer;
begin
  // caller should have made Safe.Lock
  fState.Compact; // ensure everything linear in fState.Values[0].Value
  p := nil;
  if fState.Count <> 0 then
    p := @fState.Values[0].Value;
  fDynArray.InitSpecific(TypeInfo(THttpAnalyzerToSaveDynArray), p^, ptCardinal);
  fDynArray.UseExternalCount(@fCount); // set after Init() to avoid Count=0
  fDynArray.Sorted := true; // ordered by THttpAnalyzerToSave.Date (ptCardinal)
end;

function THttpMetrics.StateAsCompactArray: PDynArray;
begin
  // caller should have made Safe.Lock
  if (fState.Count <> 1) or    // need compaction
     not fDynArray.Sorted then // never initialized
    CreateDynArray;
  result := @fDynArray;
end;

procedure THttpMetrics.ResetPeriodIndex;
var
  p: THttpAnalyzerPeriod;
begin
  fPeriodLastCount := 0;
  for p := low(fPeriod) to high(fPeriod) do
    fPeriod[p].Count := 0;    // keep Index[] buffer for next CreatePeriodIndex
  fLastRangeToIndex.sta := 0; // reset RangeToIndex() last result
end;

procedure THttpMetrics.CreatePeriodIndex;
var
  p: PHttpAnalyzerToSave;
  i: integer;
begin
  // caller should have made Safe.Lock
  if fCount = 0 then
    exit;
  p := StateAsCompactArray^.Value^;
  inc(p, fPeriodLastCount);
  for i := fPeriodLastCount to fCount - 1 do
  begin
    case p^.Period of // OnSave() should be in hapMinute..hapMonth range
      hapMinute:
        ; // not indexed
      hapCurrent,
      hapYear,
      hapAll: // paranoid
        raise EHttpMetrics.Create('Unexpected period');
    else // hapHour .. hapMonth
      with fPeriod[p^.Period] do
      begin
        if Count = length(Index) then
          SetLength(Index, NextGrow(Count));
        Index[Count] := i;
        inc(Count);
      end;
    end;
    inc(p);
  end;
  fPeriodLastCount := fCount;
end;

function THttpMetrics.RangeToIndex(start, stop: TDateTime;
  out istart, istop: integer): PHttpAnalyzerToSaveArray;
var
  startdate, stopdate: cardinal;
begin
  // caller should have made Safe.Lock
  result := StateAsCompactArray^.Value^; // compact if needed
  // convert UTC TDateTime into UnixTimeMinimalUtc timestamps
  startdate := DateTimeToUnixTime(start) - UNIXTIME_MINIMAL;
  stopdate  := DateTimeToUnixTime(stop)  - UNIXTIME_MINIMAL;
  // just return the last result if possible
  with fLastRangeToIndex do
    if (sta <> 0) and
       (startdate = sta) and
       (stopdate = sto) then
    begin
      istart := ista;
      istop := isto;
      exit;
    end;
  // retrieve the per-date boundaries using O(log(count)) binary search
  fDynArray.FastLocateSorted(startdate, istart);
  fDynArray.FastLocateSorted(stopdate, istop);
  // save for next request on the same exact time range - e.g. from a DashBoard
  with fLastRangeToIndex do
  begin
    sta := startdate;
    sto := stopdate;
    ista := istart;
    isto := istop;
  end;
end;

function THttpMetrics.RangeToPeriodIndex(period: THttpAnalyzerPeriod;
  start, stop: integer; out pstart, pstop: PInteger): integer;
begin
  // caller should have made Safe.Lock and insured period in hapHour..hapMonth
  if not (period in [hapHour..hapMonth]) then
    raise EHttpMetrics.CreateUtf8(
      'Unexpected %. RangeToPeriodIndex(%)', [self, ToText(period)^]);
  if fPeriodLastCount < fCount then
    CreatePeriodIndex; // refresh indexes if needed
  with fPeriod[period] do // hapHour .. hapMonth
  begin
    start := FastSearchIntegerSorted(pointer(Index), Count - 1, start);
    pstart := @Index[start];
    stop := FastSearchIntegerSorted(pointer(Index), Count - 1, stop);
    pstop := @Index[stop];
  end;
  result := stop - start; // returns the number of indexes in pstart..pstop
end;

procedure THttpMetrics.Clear;
begin
  fSafe.Lock;
  try
    fCount := 0;
    fState.Clear;
    fDynArray.Sorted := false; // force CreateDynArray
    ResetPeriodIndex;
    fMetadata := '';
  finally
    fSafe.UnLock;
  end;
end;

function THttpMetrics.AddFromBuffer(const Buffer: RawByteString): boolean;
var
  unsorted: boolean;
  n, c: integer;
begin
  result := false;
  n := length(Buffer) div SizeOf(THttpAnalyzerToSave);
  if (n = 0) or
     (n * SizeOf(THttpAnalyzerToSave) <> length(Buffer)) then
    exit;
  fSafe.Lock;
  try
    c := fCount;
    if n + c > HTTPMETRICS_MAXCOUNT then
      exit; // too much data
    fDynArray.Sorted := false; // force CreateDynArray
    unsorted := (c <> 0) and
                (Get(c - 1)^.Date > PHttpAnalyzerToSave(Buffer)^.Date);
    fState.Add(Buffer);
    inc(fCount, n);
    if unsorted then
    begin
      StateAsCompactArray^.Sort; // should not happen - better safe than sorry
      ResetPeriodIndex;
    end
    else if fState.Count > 256 then
      CreateDynArray; // aggregate blocks to reduce fragmentation
    fLastRangeToIndex.sta := 0; // reset RangeToIndex() last result
    result := true;
  finally
    fSafe.UnLock;
  end;
end;

function THttpMetrics.AddFromBinary(const FileName: TFileName): boolean;
var
  size: Int64;
  n: integer; // 32-bit support only in TRawByteStringGroup
  tmp: RawByteString;
begin
  result := false;
  size := FileSize(FileName);
  if size = 0 then
    exit; // void
  n := size div SizeOf(THttpAnalyzerToSave);
  if (n * SizeOf(THttpAnalyzerToSave) <> size) or
     (fCount + n > HTTPMETRICS_MAXCOUNT) then
    exit; // incorrect size or too much data
  tmp := StringFromFile(FileName);
  if length(tmp) = size then
    result := AddFromBuffer(tmp);
end;

procedure THttpMetrics.OnSave(const State: THttpAnalyzerToSaveDynArray);
var
  n: integer;
  tmp: RawByteString;
begin
  n := length(State);
  if (n = 0) or
     (fCount + n > HTTPMETRICS_MAXCOUNT) then
    exit; // no data or too much data
  FastSetRawByteString(tmp, pointer(State), n * SizeOf(State[0]));
  AddFromBuffer(tmp);
end;

procedure THttpMetrics.SaveToFile(const Dest: TFileName; Algo: TAlgoCompress);
var
  w: TBufferWriter;
  tmp: TTextWriterStackBuffer;
begin
  if Algo = nil then
    w := TBufferWriter.Create(Dest) // direct-to-fly persistence
  else
    w := TBufferWriter.Create(tmp); // in-memory persistence before compression
  try
    SaveToWriter(w);
    if Algo <> nil then
      FileFromString(Algo.Compress(w.FlushTo, {trigger=}2048), Dest);
  finally
    w.Free;
  end;
end;

function THttpMetrics.LoadFromFile(const Source: TFileName): boolean;
var
  tmp: RawByteString;
  algo: TAlgoCompress;
  rd: TFastReader;
begin
  result := false;
  tmp := StringFromFile(Source);
  if length(tmp) < 23 then
    exit;
  if PQWord(tmp)^ <> PQWord(@HTTPMETRICS_MAGIC[1])^ then
  begin
    algo := TAlgoCompress.Algo(tmp);
    if algo = nil then
      exit; // unknown algorithm
    tmp := algo.Decompress(tmp);
  end;
  rd.Init(tmp);
  result := LoadFromReader(rd);
end;

procedure THttpMetrics.GetExtensions(out data: RawByteString);
begin
  // may be overriden with additional data
end;

function THttpMetrics.SetExtensions(const data: TValueResult): boolean;
begin
  result := true; // decoding success
end;

procedure THttpMetrics.SaveToWriter(Dest: TBufferWriter);
var
  p: THttpAnalyzerPeriod;
  s: PHttpAnalyzerToSave;
  n, diff: PtrInt;
  prevdate: cardinal;
  extensions: RawByteString; // variable data field for backward compatibility
  w: PByte;
begin
  fSafe.Lock;
  try
    // save header
    Dest.Write(@HTTPMETRICS_MAGIC[1], ord(HTTPMETRICS_MAGIC[0]));
    Dest.WriteVarUInt32(fCount);
    Dest.Write(fMetadata);
    if fCount = 0 then
      exit;
    if fPeriodLastCount < fCount then
      CreatePeriodIndex; // refresh indexes count and verify s^.Period range
    for p := low(fPeriod) to high(fPeriod) do // hapHour .. hapMonth
      Dest.WriteVarUInt32(fPeriod[p].Count);  // avoid realloc in LoadFromReader
    s := StateAsCompactArray^.Value^;
    n := fCount;
    Dest.Write4(s^.Date);                                 // first date
    Dest.Write4(PHttpAnalyzerToSaveArray(s)[n - 1].Date); // last date
    GetExtensions(extensions);
    Dest.Write4(crc32c(crc32c(0, pointer(extensions), length(extensions)),
                              pointer(s), n * SizeOf(s^))); // anti-tampering
    // additional extensions data, included in the crc
    Dest.Write(extensions);
    // save main data, encoded from fState
    prevdate := 0;
    repeat
      diff := s^.Date - prevdate; // delta encoding of the increasing Date field
      if diff < 0 then
        raise EHttpMetrics.CreateUtf8('%.SaveToWriter: unsorted dates', [self]);
      w := ToVarUInt32(diff, Dest.DirectWriteReserve(SizeOf(s^) * 2));
      prevdate := s^.Date;
      w^ := ord(s^.Period) - 1 + ord(s^.Scope) shl 3; // Period+Scope as 1 byte
      inc(w);
      Dest.DirectWriteReserved(ToVarUInt64(s^.State.Write,
                               ToVarUInt64(s^.State.Read,
                               ToVarUInt64(s^.State.Time,
                               ToVarUInt64(s^.State.Count, w)))));
      inc(s);
      dec(n)
    until n = 0;
    // indexes will be recreated on the fly during data reading
  finally
    fSafe.UnLock;
  end;
end;

function THttpMetrics.LoadFromReader(var Source: TFastReader): boolean;
var
  p: THttpAnalyzerPeriod;
  s: PHttpAnalyzerToSave;
  mlen, i, n: integer;
  rd: PByte;
  firstdate, lastdate, prevdate, crc: cardinal;
  peek: PtrUInt;
  extensions: TValueResult; // variable field for backward compatibility
begin
  // always reset any previous stored data
  result := false;
  Clear;
  // read header
  mlen := ord(HTTPMETRICS_MAGIC[0]);
  if (Source.RemainingLength <= PtrUInt(mlen)) or
     not CompareMem(Source.Next(mlen), @HTTPMETRICS_MAGIC[1], mlen) then
    exit;
  fSafe.Lock;
  try
    n := Source.VarUInt32;
    if (n > HTTPMETRICS_MAXCOUNT) or
       not Source.VarUtf8Safe(fMetadata) then
      exit;
    if n = 0 then
      exit;
    fCount := n;
    fPeriodLastCount := n;
    for p := low(fPeriod) to high(fPeriod) do // hapHour .. hapMonth
      with fPeriod[p] do
      begin
        Count := Source.VarUInt32;
        Index := nil;
        SetLength(Index, Count); // pre-allocate all indexes
      end;
    firstdate := Source.Next4;
    lastdate  := Source.Next4;
    crc := Source.Next4;
    // additional extensions, included in the crc
    if not Source.VarBlobSafe(extensions) or
       not SetExtensions(extensions) then // method could be overriden
      exit;
    // read and decode main data into fState
    if (Source.RemainingLength < PtrUInt(fCount) * 6) or
       not Source.PeekVarUInt32(peek) or
       (peek <> firstdate) then
      exit;
    fState.Add(nil, fCount * SizeOf(s^)); // pre-allocate all data
    prevdate := 0;
    s := StateAsCompactArray.Value^;
    rd := pointer(Source.P); // use a faster PByte within the loop
    i := 0;
    repeat
      inc(prevdate, FromVarUInt32(rd)); // delta decoding
      s^.Date := prevdate;
      s^.Period := THttpAnalyzerPeriod((rd^ and 7) + 1); // single byte
      s^.Scope  := THttpAnalyzerScope(rd^ shr 3);
      inc(rd);
      s^.State.Count := FromVarUInt64(rd);
      s^.State.Time  := FromVarUInt64(rd);
      s^.State.Read  := FromVarUInt64(rd);
      s^.State.Write := FromVarUInt64(rd);
      if s^.Period >= low(fPeriod) then
        with fPeriod[s^.Period] do
        begin
          Index[Count] := i; // decode and index in a single pass
          inc(Count);
        end;
      if PtrUInt(rd) > PtrUInt(Source.Last) then
        exit; // check read overflow once per row
      inc(i);
      inc(s);
    until i = fCount;
    // quickly check data consistency
    if prevdate <> lastdate then
      exit;
    for p := low(fPeriod) to high(fPeriod) do
      with fPeriod[p] do
        if length(Index) <> Count then
          exit;
    // ensure decoded data was not tampered
    result := crc32c(crc32c(0, extensions.Ptr, extensions.Len),
                            fDynArray.Value^, fCount * SizeOf(s^)) = crc;
  finally
    fSafe.UnLock;
    if not result then
      Clear;
  end;
end;

class function THttpMetrics.LoadHeader(const FileName: TFileName;
  out Info: THttpMetricsHeader): boolean;
var
  f: THandle;
  mlen, len: PtrInt;
  last, first: cardinal;
  p: THttpAnalyzerPeriod;
  rd: TFastReader;
  tmp: array[0..4095] of AnsiChar; // first 4KB should be enough (with metadata)
  unc: array[0..6143] of AnsiChar; // partially decompressed content
begin
  FastRecordClear(@Info, TypeInfo(THttpMetricsHeader));
  result := false;
  // read (and decompress if needed) the first file chunk
  f := FileOpen(FileName, fmOpenReadDenyNone);
  if not ValidHandle(f) then
    exit;
  len := FileRead(f, tmp, SizeOf(tmp));
  FileClose(f);
  mlen := ord(HTTPMETRICS_MAGIC[0]);
  if len <= mlen then
    exit;
  if PQWord(@tmp)^ = PQWord(@HTTPMETRICS_MAGIC[1])^ then
    // seems to be non-compressed content
    {%H-}rd.Init(@tmp, len)
  else
  begin
    // partial decompression of the first 4KB file chunk
    Info.Algo := TAlgoCompress.Algo(@tmp, len);
    len := Info.Algo.DecompressPartial(@tmp, @unc, len, SizeOf(tmp), SizeOf(unc));
    if len < mlen then
      exit; // decompression failed
    {%H-}rd.Init(@unc, len);
  end;
  // retrieve information from the header
  if not CompareMem(rd.Next(mlen), @HTTPMETRICS_MAGIC[1], mlen) or
     not rd.VarUInt32Safe(Info.Count) or
     (Info.Count > HTTPMETRICS_MAXCOUNT) or
     not rd.VarUtf8Safe(Info.Metadata) then
    exit;
  if Info.Count <> 0 then
  begin
    Info.Period[hapMinute] := Info.Count;
    for p := hapHour to hapMonth do
      if rd.VarUInt32Safe(Info.Period[p]) then
        dec(Info.Period[hapMinute], Info.Period[p]) // adjust
      else
        exit;
    if not rd.CopySafe(@first, SizeOf(first)) or
       not rd.CopySafe(@last,  SizeOf(last)) or
       not rd.CopySafe(@Info.Crc, SizeOf(Info.Crc)) or
       not rd.VarUInt32Safe(Info.ExtensionSize) then // get VarBlob() length
      exit;
    Info.First := UnixTimeToDateTime(first + UNIXTIME_MINIMAL);
    Info.Last  := UnixTimeToDateTime(last + UNIXTIME_MINIMAL);
  end;
  result := true;
end;

function THttpMetrics.GetState(Row: integer;
  out State: THttpAnalyzerToSave): boolean;
begin
  result := false;
  if cardinal(Row) >= cardinal(fCount) then
    exit;
  fSafe.Lock;
  fState.FindMove(Row * SizeOf(State), SizeOf(State), @State);
  fSafe.UnLock;
  result := true;
end;

function THttpMetrics.Find(Start, Stop: TDateTime; Period: THttpAnalyzerPeriod;
  Scope: THttpAnalyzerScope): THttpAnalyzerToSaveDynArray;
var
  ndxStart, ndxStop: integer;
  count, capacity: PtrInt;
  si, pi: PInteger;
  p, s: PHttpAnalyzerToSave;
  v: PHttpAnalyzerToSaveArray;

  procedure ResultGrow;
  begin
    if count = 0 then
      capacity := 40 // generous initial allocation (1600 bytes)
    else
      capacity := NextGrow(capacity);
    SetLength(result, capacity);
  end;

begin
  result := nil;
  if not (Period in [hapMinute .. hapMonth]) then
    exit; // OnSave() has been done in this range only
  count := 0;
  capacity := 0;
  fSafe.Lock;
  try
    // retrieve the per-date boundaries
    if fCount = 0 then
      exit;
    v := RangeToIndex(Start, Stop, ndxStart, ndxStop);
    if ndxStart >= ndxStop then
      exit;
    // perform the actual (indexed) search
    if Period = hapMinute then
    begin
      // hapMinute: brute force search within this s <= x < p time range
      s := @v[ndxStart];
      p := @v[ndxStop];
      while PtrUInt(s) < PtrUInt(p) do
      begin
        if (s^.Period = Period) and
           (s^.Scope = Scope) then
        begin
          if count = capacity then
            ResultGrow;
          result[count] := s^;
          inc(count);
        end;
        inc(s);
      end;
    end
    else
    begin
      // hapHour..hapMonth: search using the index of this Period
      RangeToPeriodIndex(Period, ndxStart, ndxStop, si, pi);
      while PtrUInt(si) < PtrUInt(pi) do
      begin
        s := @v[si^];
        if s^.Scope = Scope then
        begin
          if count = capacity then
            ResultGrow;
          result[count] := s^;
          inc(count);
        end;
        inc(si);
      end;
    end;
  finally
    fSafe.UnLock;
  end;
  if result <> nil then
    DynArrayFakeLength(result, count);
end;


function ToText(s: THttpAnalyzerScope): PShortString;
begin
  result := GetEnumName(TypeInfo(THttpAnalyzerScope), ord(s));
end;

function ToText(p: THttpAnalyzerPeriod): PShortString;
begin
  result := GetEnumName(TypeInfo(THttpAnalyzerPeriod), ord(p));
end;

function ToText(v: THttpLogVariable): PShortString;
begin
  result := GetEnumName(TypeInfo(THttpLogVariable), ord(v));
end;

function ToText(r: THttpLoggerRotate): PShortString;
begin
  result := GetEnumName(TypeInfo(THttpLoggerRotate), ord(r));
end;



initialization
  assert(SizeOf(THttpAnalyzerToSave) = 40);
  _GETVAR :=  'GET';
  _POSTVAR := 'POST';
  _HEADVAR := 'HEAD';

finalization

end.

