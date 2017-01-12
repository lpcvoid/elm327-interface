unit modComPort;

interface

uses
  windows, modGlobals, dateutils, sysutils, System.Generics.Collections;

const
  MOD_COM_RESULT_ERROR = -1;
  MOD_COM_RESULT_NOTHING = -2;
  MOD_COM_RESULT_PENDING = -3;

  // error types that indicate what function failed!
type
  TmodComError = (modComPort_NoError, modComPort_CreateFile,
    modComPort_SetCommTimeouts, modComPort_CreateIoCompletionPort,
    modComPort_GetCommState, modComPort_SetCommState, modComPort_SetCommMask,
    modComPort_WriteFile, modComPort_ReadFile);

type
  TmodComPortState = (modComPort_Disconnected, modComPort_Connected,
    modComPort_Pending_Send, modComPort_Pending_Recv);

type
  TmodComPortParameters = packed record
    baud: Integer;
    parity_bits: Integer;
    stop_bits: Integer;
  end;

type
  TmodComPortError = record
    error_time: Int64; // unix timestamp
    error_state: TmodComError;
    error_code: Integer;
  end;

type
  TmodComPort = class
  public
    constructor Create(name: string);
    destructor Destroy; override;
    function GetComPortName(): string;
    function GetComPortHandle(): THandle;
    function GetErrorState(): TmodComPortError;
    procedure SetComPortParameters(params: TmodComPortParameters);
    function Connect(): Boolean;
    function Disconnect(): Boolean;
    function Send(var data: TArray<Byte>): Integer;
    function Recv(var data: TArray<Byte>; len: Integer = MOD_COM_MAX_BYTES): Integer;
    procedure SetComPortState(state: TmodComPortState);
    function GetComportState(): TmodComPortState;
    procedure Purge;
  private
    _name: string;
    _com_handle: THandle;
    _comm_timeouts: TCommTimeouts;
    _dcb: TDCB;
    _overlapped_read: TOverlapped;
    _overlapped_write: TOverlapped;
    _last_send_operation_byte_count: Integer;
    _last_recv_operation_byte_count: Integer;

    // statistics
    _stat_bytes_sent: Cardinal;
    _stat_bytes_recv: Cardinal;
    _params: TmodComPortParameters;
    _state: TmodComPortState;
    // on error, this gets set.
    _error: TmodComPortError;
    // so we don't need to create this on stack every time
    _recv_buf: array[0..MOD_COM_MAX_BYTES - 1] of Byte;
    procedure SetError(state: TmodComError; error_code: Integer);
  end;

implementation

{ TmodComPort }

function TmodComPort.Connect: Boolean;
var
  com_addr: WideString;
begin
  Result := True;
  _com_handle := INVALID_HANDLE_VALUE;
  com_addr := '\\.\' + _name;
  _com_handle := CreateFile(@com_addr[1], GENERIC_READ or GENERIC_WRITE, 0, // must be opened with exclusive-access
    0, // default security attributes
    OPEN_EXISTING, // must use OPEN_EXISTING
    FILE_FLAG_OVERLAPPED, // we want overlapped communication
    0); // hTemplate must be NULL for comm devices

  if (_com_handle = INVALID_HANDLE_VALUE) then
  begin
    SetError(modComPort_CreateFile, GetLastError());
    Result := False;
    Exit;
  end;

  // http://msdn.microsoft.com/en-us/library/windows/desktop/aa363190%28v=vs.85%29.aspx
  // readfile and writefile returns immediately
  _comm_timeouts.ReadIntervalTimeout := MAXDWORD;
  _comm_timeouts.ReadTotalTimeoutMultiplier := 0;
  _comm_timeouts.ReadTotalTimeoutConstant := 0;
  _comm_timeouts.WriteTotalTimeoutMultiplier := 0;
  _comm_timeouts.WriteTotalTimeoutConstant := 0;

  if (SetCommTimeouts(_com_handle, _comm_timeouts) <> True) then
  begin
    SetError(modComPort_SetCommTimeouts, GetLastError());
    Result := False;
    Exit;
  end;

  if (GetCommState(_com_handle, _dcb) = False) then
  begin
    SetError(modComPort_GetCommState, GetLastError());
    Result := False;
    Exit;
  end;

  _dcb.BaudRate := CBR_115200;
  _dcb.Parity := NOPARITY;
  _dcb.StopBits := ONESTOPBIT;
  _dcb.ByteSize := 8;

  if (SetCommState(_com_handle, _dcb) = False) then
  begin
    SetError(modComPort_SetCommState, GetLastError());
    Result := False;
    Exit;
  end;

  // we only want to recieve events that indicate reading and writing. No control stuff.
  if (SetCommMask(_com_handle, EV_TXEMPTY or EV_RXCHAR) = False) then
  begin
    SetError(modComPort_SetCommMask, GetLastError());
    Result := False;
    Exit;
  end;

  Self.Purge;

  // set port state to connected
  Self._state := modComPort_Connected;

  // reset statistics
  _stat_bytes_sent := 0;
  _stat_bytes_recv := 0;
end;

constructor TmodComPort.Create(name: string);
begin
  _name := name;
  _state := modComPort_Disconnected;
  _com_handle := INVALID_HANDLE_VALUE;

  // NULL error state
  ZeroMemory(@_error, SizeOf(TmodComPortError));

  // NULL overlapped structure
  ZeroMemory(@_overlapped_read, SizeOf(TOverlapped));
  ZeroMemory(@_overlapped_write, SizeOf(TOverlapped));

  _last_send_operation_byte_count := 0;
  _last_recv_operation_byte_count := 0;
end;

destructor TmodComPort.Destroy;
begin
  inherited;

  Self.Disconnect();
end;

function TmodComPort.Disconnect: Boolean;
begin
  if (_com_handle <> INVALID_HANDLE_VALUE) then
  begin
    CancelIo(_com_handle);
    CloseHandle(_com_handle);
  end;
  _com_handle := INVALID_HANDLE_VALUE;
  _state := modComPort_Disconnected;
  Result := True;
end;

function TmodComPort.GetComPortHandle: THandle;
begin
  Result := _com_handle;
end;

function TmodComPort.GetComPortName: string;
begin
  Result := _name;
end;

function TmodComPort.GetComportState: TmodComPortState;
var
  handled_bytes: Cardinal;
begin
  GetOverlappedResult(_com_handle, _overlapped_read, handled_bytes, False);
  if (_last_recv_operation_byte_count = handled_bytes) then
  begin
    GetOverlappedResult(_com_handle, _overlapped_write, handled_bytes, False);
    if (_last_send_operation_byte_count = handled_bytes) then
    begin
      _state := modComPort_Connected;
    end;
  end;
  Result := _state;
end;

function TmodComPort.GetErrorState: TmodComPortError;
begin
  Result := _error;
end;

procedure TmodComPort.Purge;
begin
  PurgeComm(_com_handle, PURGE_RXABORT or PURGE_RXCLEAR or PURGE_TXABORT or
    PURGE_TXCLEAR);
end;

function TmodComPort.Recv(var data: TArray<Byte>; len: Integer): Integer;
var
  recv_count: Cardinal;
  last_error: Integer;
begin
  // create a new overlapped finish event
  ZeroMemory(@_overlapped_read, SizeOf(TOverlapped));
  // _overlapped_read.hEvent := CreateEvent(0, true, false, 0);
  try

    if (ReadFile(_com_handle, _recv_buf[0], len, recv_count, @_overlapped_read)) then
    begin
      if (recv_count > 0) then
      begin
        SetLength(data, recv_count);
        CopyMemory(@data[0], @_recv_buf[0], recv_count);

        _last_recv_operation_byte_count := recv_count;
        Result := _last_recv_operation_byte_count;

        Inc(_stat_bytes_recv, recv_count);

      end
      else
      begin
        begin
          //there is no error, simply returned zero
        end;
        SetLength(data, 0);
        Result := MOD_COM_RESULT_NOTHING;
      end;
    end
    else
    begin
      last_error := GetLastError();
      // TODO: Maybe we need to also check with GetCommMask()?
      if (last_error = ERROR_IO_PENDING) then
      begin
        // now get the result. Wait for event object to signal. (last param)
        // GetOverlappedResult(_com_handle, _overlapped_read, recv_count, true);
        Result := MOD_COM_RESULT_PENDING;
        _state := modComPort_Pending_Recv;
      end
      else
      begin
        SetError(modComPort_ReadFile, last_error);
        Result := MOD_COM_RESULT_ERROR;
      end;
    end;

  finally
    // CloseHandle(_overlapped_read.hEvent);
  end;

end;

function TmodComPort.Send(var data: TArray<Byte>): Integer;
var
  bytes_written, byte_len: Cardinal;
  last_error: Integer;
begin
  // create event that signals end of write
  ZeroMemory(@_overlapped_write, SizeOf(TOverlapped));
  // _overlapped_write.hEvent := CreateEvent(0, true, false, 0);
  try
    byte_len := Length(data);
    if (WriteFile(_com_handle, data[0], byte_len, bytes_written, @_overlapped_write)) then
    begin
      _last_send_operation_byte_count := bytes_written;
      Result := _last_send_operation_byte_count;
      Inc(_stat_bytes_sent, bytes_written);
      _state := modComPort_Connected;
    end
    else
    begin
      last_error := GetLastError();
      // TODO: Maybe we need to also check with GetCommMask()?
      if (last_error = ERROR_IO_PENDING) then
      begin
        // GetOverlappedResult(_com_handle, _overlapped_write, bytes_written, true);
        Result := MOD_COM_RESULT_PENDING;
        _state := modComPort_Pending_Send;
      end
      else
      begin
        SetError(modComPort_WriteFile, last_error);
        Result := MOD_COM_RESULT_ERROR;
      end;
    end;

  finally
    // CloseHandle(_overlapped_write.hEvent);
  end;
end;

procedure TmodComPort.SetComPortParameters(params: TmodComPortParameters);
begin
  _params := params;
end;

procedure TmodComPort.SetComPortState(state: TmodComPortState);
begin

  _state := state;
end;

procedure TmodComPort.SetError(state: TmodComError; error_code: Integer);
begin
  _error.error_state := state;
  _error.error_code := error_code;
  _error.error_time := DateTimeToUnix(Now());
end;

end.


