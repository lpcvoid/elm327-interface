unit modELMMessage;

interface

uses windows, strutils, sysutils, types, modELMTypes;

const
  MOD_ELM_TERMINATOR_CHAR = $3E; // >
  MOD_ELM_SEND_TERMINATOR_CHAR = $D; // carriage return
  MOD_ELM_ERROR_CHAR = $3F; // ?
  MOD_ELM_CONFIRMATION_STRING = 'OK';
  MOD_ELM_SEARCHING_STRING = 'SEARCHING...';
  MOD_ELM_MSG_UNABLE_TO_CONNECT = 'UNABLE TO CONNECT';
  MOD_ELM_MSG_CAN_ERROR = 'CAN ERROR';
  MOD_ELM_MSG_NO_DATA = 'NO DATA';
  MOD_ELM_MSG_BUFFER_FULL = 'BUFFER FULL';

  // ELM messages = AT messages
  // OBD messages = messages for car
type
  TmodELMMessageMode = (modELMMessageType_OBD, modELMMessageType_ELM);

type
  TmodELMMessageType = (mod_elmmt_OBD, mod_elmmt_ATFE, mod_elmmt_ATRV, mod_elmmt_ATZ, mod_elmmt_ATE, mod_elmmt_ATL, mod_elmmt_ATSP, mod_elmmt_ATDPN,
    mod_elmmt_ATH, mod_elmmt_ATCEA, mod_elmmt_ATFCSH, mod_elmmt_ATFCSD, mod_elmmt_ATPB, mod_elmmt_ATCRA, mod_elmmt_ATSH, mod_elmmt_ATFCSM, mod_elmmt_ATCM,
    mod_elmmt_ATCF, mod_elmmt_ATBI);

type
  TmodELMMessageString = Ansistring;

  // none - message is empty
  // okay - message is correctly terminated
  // incomplete - there is no terminator from ELM, incomplete message, wait for rest
type
  TmodMessageState = (modMessageState_none, modMessageState_okay, modMessageState_incomplete);

type
  TmodELMMessage = record
    msg: TmodELMMessageString;
    msg_mode: TmodELMMessageMode;
    msg_type: TmodELMMessageType;
    elm_param_state: TmodELMInterfaceParameterState;

    // reset this message to some default valu
    procedure Reset();

    // ELM can use this info to speed up requests
    function GetPacketState(): TmodMessageState;
    // adds another packet to the end of this one.
    // if message type doesn't match, then false is returned.
    function AddContents(other_msg: TmodELMMessage): boolean;
    // sets message, and terminates message correctly for the ELM chip.
    procedure SetMessage(msg: TmodELMMessageString);
    // removes string from message.
    // also removes newline if present.
    procedure RemoveString(echo_string: TmodELMMessageString);
    // removes terminator char from end of string, if present.
    procedure RemoveTerminator();
    // removes newlines and carriage retuns from message
    procedure RemoveNewlinesCarriageReturns();
    // remove trailing whitespace
    procedure TrimWhitespace();
    // splits message into array of strings based on delimiter
    function SplitByDelimiter(delimiter: Ansistring): TStringDynArray;
    // splits message into array of ints. It is up to the caller to make sure message can be converted to int.
    function SplitIntoIntsByDelimiter(delimiter: Ansistring): TIntegerDynArray;
    // attempts to parse content into a float.
    // used for extracting voltage and stuff.
    function ToFloat(): single;

    // wrapper methods for simple data evaluations
    function ContainsString(str: TmodELMMessageString): boolean;
  end;

implementation

{ TmodELMMessage }

function TmodELMMessage.AddContents(other_msg: TmodELMMessage): boolean;
begin
  if (other_msg.msg_mode = self.msg_mode) and (other_msg.msg_type = other_msg.msg_type) then
  begin
    self.msg := self.msg + other_msg.msg;
    result := true;
  end
  else
  begin
    result := false;
  end;
end;

function TmodELMMessage.ContainsString(str: TmodELMMessageString): boolean;
begin
  result := ContainsStr(self.msg, str);
end;

function TmodELMMessage.GetPacketState: TmodMessageState;
var
  indx_last_char: integer;
begin
  if (length(msg) = 0) then
  begin
    result := modMessageState_none;
    exit;
  end;

  if (length(msg) > 0) then
  begin
    indx_last_char := length(msg);
    if (msg[indx_last_char] = ansichar(MOD_ELM_TERMINATOR_CHAR)) then
      result := modMessageState_okay
      // message has content, and is terminated correctly
    else
      result := modMessageState_incomplete; // message has content, but is missing the terminator!
  end;
end;

procedure TmodELMMessage.RemoveString(echo_string: TmodELMMessageString);
begin
  self.msg := StringReplace(self.msg, echo_string, '', [rfReplaceAll, rfIgnoreCase]);
end;

procedure TmodELMMessage.RemoveNewlinesCarriageReturns;
begin
  self.msg := StringReplace(self.msg, #10, '', [rfReplaceAll, rfIgnoreCase]);
  self.msg := StringReplace(self.msg, #13, '', [rfReplaceAll, rfIgnoreCase]);
end;

procedure TmodELMMessage.RemoveTerminator;
begin
  if (self.GetPacketState() = modMessageState_okay) then
  begin
    if (self.msg[length(self.msg)] = ansichar(MOD_ELM_TERMINATOR_CHAR)) then
    begin
      SetLength(self.msg, length(self.msg) - 1);
    end;
  end;
end;

procedure TmodELMMessage.Reset;
begin
  msg := '';
end;

procedure TmodELMMessage.SetMessage(msg: TmodELMMessageString);
begin
  // ELM messages need to be terminated by a single carriage return character
  self.msg := msg + ansichar(MOD_ELM_SEND_TERMINATOR_CHAR);
end;

function TmodELMMessage.SplitByDelimiter(delimiter: Ansistring): TStringDynArray;
begin
  result := SplitString(self.msg, delimiter);
end;

function TmodELMMessage.SplitIntoIntsByDelimiter(delimiter: Ansistring): TIntegerDynArray;
var
  pre: TStringDynArray;
  i: integer;
begin
  pre := self.SplitByDelimiter(delimiter);

  SetLength(result, length(pre));
  for i := 0 to length(pre) - 1 do
  begin
    result[i] := strtoint('$' + pre[i]);
  end;

end;

function TmodELMMessage.ToFloat(): single;
begin
  try
    result := StrToFloat(self.msg);
  except
    result := 0.0;
  end;
end;

procedure TmodELMMessage.TrimWhitespace;
begin
  self.msg := Trim(self.msg);
end;

end.
