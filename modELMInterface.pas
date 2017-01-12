unit modELMInterface;

(*

  Some notes on the ELM interface.
  We do not need a recv queue. Each message that is sent makes ELMInterface wait for a response. This is not TCP/IP, where we can
  Juggle aroubnd messages as we please - COM is a bit more.... special needs child.

  Flow graph :

  ELMInterface is in state modELMState_Idle, no packets in send queue
  Send queue is checked, if it contains a packet, we send it
  Packet is sent, ELMInterface us set to waiting state (modELMState_awaiting_response)
  ELMInterface awaits arriving packet, it does not send any more until the request is answered
  Packet arrives, ELMInterface handles it, sets state to idle
  repeat


*)

interface

uses windows, modComPort, strutils, modGlobals, system.Generics.Collections, dateutils, sysutils,
  modELMMessage,
  swooshMessageSender, modELMTypes, classes;

type
  TmodELMInterface = class

  private
    // queue of packets to be sent.
    _sendqueue: TQueue<TmodELMMessage>;
    // last packet that was sent.
    _last_sent_packet: TmodELMMessage;
    // last recieved packet.
    _last_recv_packet: TmodELMMessage;
    // cleaned last recieved message
    // this already has all the whitespace and terminator crap removed
    _last_recv_cleaned_packet: TmodELMMessage;
    // last OBD message recieved!
    _last_recv_obd_packet: TmodELMMessage;

    // if incomplete packets re recieved, they are added to this list. The next packet that ends in a terminator
    // will have all these combined into one, and this list will be cleared.
    // this is a defence against fragmented packets that may happen on large amounts of data.
    _packet_fragments: TList<TmodELMMessage>;

    // pointer to method that the interface gets its message data from.
    // this is used for debugging, so we can set other sources than the real COM port.
    _interface_msg_src: TmodELMMessageDataSource;

    // same thing as above, just for destination.
    _interface_msg_dest: TmodELMMessageDataDest;

    // array of protocolled errors
    _error_list: TList<TmodComPortError>;

    // current state of ELM interface
    _state: TmodELMState;

    // com port that we are working with
    _com_port: TmodComPort;

    // message sender for messages
    _msg_sender: TswooshMessageSender;

    // last timestamp of a standard packet/message
    _last_elm_message: int64;

    // log of messages
    _message_log: TStringList;

    // message id counter
    _message_id_counter: cardinal;




    // ELM data

    _requested_parameters: TmodELMInterfaceRequestedParameters;
    _parameter_state: TmodELMInterfaceParameterState;

    // current voltage that ELM is getting
    _voltage: single;
    // voltage, as string like it was sent.
    _voltage_string: ansistring;
    // version of ELM
    _version: single;
    // current, active protocol
    _protocol: TmodOBDProtocol;
    // version string
    _version_string: ansistring;

    function GetTimestamp(): int64;

    // Handles the last ELM message.
    function HandleLastELMMessage(): boolean;

    // converts a dword to a 3 nibble 11 bit value, like 6f1
    function ToCAN11Bit(value: cardinal): ansistring;

    // combines a last recieved packet with terminator with packets that are in fragment list.
    // returns a combined packet, clears fragment list.
    function CombineFragments(last_packet: TmodELMMessage): TmodELMMessage;

  public

    constructor Create(msg_send: TswooshMessageSender);
    destructor Destroy; override;

    function GetMessageRecvCounter(): cardinal;

    procedure SetDataSourcesToCOM();
    procedure SetDataSource(src: TmodELMMessageDataSource);
    procedure SetDataDest(dest: TmodELMMessageDataDest);

    function IsConnected(): boolean;

    procedure SetCOMPort(com_port: TmodComPort);

    function GetSendQueueCount(): cardinal;

    function GetInterfaceState(): TmodELMState;
    function GetMessageLog(): TStringList;

    procedure ProcessMessages();

    // ELM methods
    procedure RequestVoltage(); // ATRV
    procedure ResetHard(); // ATZ
    procedure SetEchoState(echo: boolean); // ATEx; x = 1/0
    procedure ForgetEvents(); // ATFE
    procedure SetLineFeedState(linefeeds: boolean); // ATLx; x = 1/0
    procedure SetProtocol(protocol: TmodOBDProtocol); // ATSPx; x = TmodELMProtocol; page 25
    procedure DescribeProtocolNumber(); // atdpn
    procedure SetHeaderState(headers: boolean); // athx
    procedure SetHeader(can_11_bit: cardinal);
    procedure BypassInitSequence();

    procedure SetCanFilter(filter: cardinal);
    procedure SetCanMask(mask: cardinal);
    procedure SetCanExtendedAddress(addr: byte); // at CEA xx
    procedure SetCanFlowControlMode(mode: TmodELMInterfaceCANFlowControlMode); // at fc sm xx
    procedure SetCanFlowControlHeader(hdr: cardinal); // AT FC SH xxx
    procedure SetCanFlowControlData(db: TmodELMInterfaceCANFlowControlDatabytes); // AT FC SD xx xx xx xx
    procedure SetProtocolBOptions(flags, baud_rate_divisor: byte); // AT PB xx xx
    procedure SetRecieveAddressFilter(addr: cardinal); // AT CRA xxx
    // wrapper methods

    /// <summary>
    /// Resets adapter. Sends lots of extra init commands.
    /// </summary>
    procedure SetupAdapter();

    /// <summary>
    /// Attempts to find protocol. Sets protocol type flag.
    /// </summary>
    procedure FindProtocol();

    /// <summary>
    /// Resets Interface.
    /// Doesn't send any commands.
    /// Emptys sendqueue and resets data to 0.
    /// </summary>
    procedure ResetInterface();



    // utility methods

    function GetError(indx: integer): TmodComPortError;
    procedure SendPacket(packet: TmodELMMessage);
    procedure SendOBDMessage(msg: TmodELMMessageString);
    function GetLastPacket(): TmodELMMessage;
    function GetLastPacketCleaned(): TmodELMMessage;
    function GetLastSendPacket(): TmodELMMessage;
    function GetLastRecvOBDPacket(): TmodELMMessage;

    // ELM data properties
    property ELMVoltage: single read _voltage write _voltage;
    property ELMVoltageString: ansistring read _voltage_string write _voltage_string;
    property ELMVersion: single read _version write _version;
    property ELMProtocol: TmodOBDProtocol read _protocol write _protocol;
    property ELMVersionString: ansistring read _version_string write _version_string;

    // CAN data properties
    property ParameterState: TmodELMInterfaceParameterState read _parameter_state write _parameter_state;
  end;

implementation

{ TmodELMInterpreter }

constructor TmodELMInterface.Create(msg_send: TswooshMessageSender);
begin

  _msg_sender := msg_send;

  _message_id_counter := 0;

  _message_log := TStringList.Create;

  _sendqueue := TQueue<TmodELMMessage>.Create;
  _error_list := TList<TmodComPortError>.Create;

  _packet_fragments := TList<TmodELMMessage>.Create;

  _state := modELMState_Idle;

  self._voltage := 0.0;
  self._version := 0.0;
  self._protocol := modOBDProtocol_Auto;

  sysutils.FormatSettings.DecimalSeparator := '.';

  _last_elm_message := 0;

  _interface_msg_src := nil;
  _interface_msg_dest := nil;

end;

destructor TmodELMInterface.Destroy;
begin
  _sendqueue.free;
  _error_list.free;
  _packet_fragments.free;
  inherited;
end;

procedure TmodELMInterface.BypassInitSequence;
var
  packet: TmodELMMessage;
begin
  packet.SetMessage('ATBI');
  packet.msg_mode := modELMMessageType_ELM;
  packet.msg_type := mod_elmmt_ATBI;
  self.SendPacket(packet);
end;

function TmodELMInterface.CombineFragments(last_packet: TmodELMMessage): TmodELMMessage;
var
  pck_first: TmodELMMessage;
  i: integer;
begin
  // first fragment is base
  pck_first := _packet_fragments[0];

  // add all other fragments to this packet, in correct order
  for i := 1 to _packet_fragments.Count - 1 do
  begin
    pck_first.AddContents(_packet_fragments[i]);
  end;

  // add final packet
  pck_first.AddContents(last_packet);

  // clear all fragments. They have been processed.
  _packet_fragments.Clear;

  result := pck_first;
end;

procedure TmodELMInterface.DescribeProtocolNumber;
var
  packet: TmodELMMessage;
begin
  packet.SetMessage('ATDPN');
  packet.msg_mode := modELMMessageType_ELM;
  packet.msg_type := mod_elmmt_ATDPN;
  self.SendPacket(packet);
end;

procedure TmodELMInterface.ForgetEvents;
var
  packet: TmodELMMessage;
begin
  packet.SetMessage('ATFE');
  packet.msg_mode := modELMMessageType_ELM;
  packet.msg_type := mod_elmmt_ATFE;
  self.SendPacket(packet);
end;

function TmodELMInterface.GetError(indx: integer): TmodComPortError;
begin
  if (indx >= 0) and (indx < _error_list.Count) then
    result := _error_list[indx];
end;

function TmodELMInterface.GetInterfaceState: TmodELMState;
begin
  result := _state;
end;

function TmodELMInterface.GetLastPacketCleaned: TmodELMMessage;
begin
  result := _last_recv_cleaned_packet;
end;

function TmodELMInterface.GetLastRecvOBDPacket: TmodELMMessage;
begin
  result := _last_recv_obd_packet;
end;

function TmodELMInterface.GetLastPacket: TmodELMMessage;
begin
  result := _last_recv_packet;
end;

function TmodELMInterface.GetLastSendPacket: TmodELMMessage;
begin
  result := _last_sent_packet;
end;

function TmodELMInterface.GetSendQueueCount: cardinal;
begin
  result := _sendqueue.Count;
end;

function TmodELMInterface.GetMessageLog: TStringList;
begin
  result := _message_log;
end;

function TmodELMInterface.GetMessageRecvCounter: cardinal;
begin
  result := _message_id_counter;
end;

function TmodELMInterface.GetTimestamp: int64;
begin
  result := DateTimeToUnix(Now());
end;

function TmodELMInterface.HandleLastELMMessage: boolean;
var
  pck: TmodELMMessage;
begin

  result := false;

  pck := _last_recv_packet;
  // We have last sent message, and last recieved message.
  // each message contains no echos.
  // on to epic string parsing

  // first, we want to remove any echo that may be in the message.
  // this is done by checking if the message starts with the payload of the last sent packet.
  pck.RemoveString(_last_sent_packet.msg);

  // remove terminator char if it's present. We don't need it anymore at this stage.
  pck.RemoveTerminator();

  // remove newlines and carriage returns
  pck.RemoveNewlinesCarriageReturns();

  // remove whitespace before and after message
  pck.TrimWhitespace();

  // set this now clean message as last cleaned message.
  _last_recv_cleaned_packet := pck;

  // check if result is NO DATA.
  // NO DATA is actually not an error.
  // Can mean car was busy, or ECU doesn't have requested data, or there was a higher priority can message...
  // fact is, entirely irrelevant for us.
  // we return true, but simply don't tell mainform that there's an obd message to handle.
  // this would normally happen in a few lines.
  if (pck.ContainsString(MOD_ELM_MSG_NO_DATA)) then
  begin
    result := true;
    exit;
  end;

  // check if the response is a question mark. If it is, we can return instantly!
  if (pck.ContainsString(ansichar(MOD_ELM_ERROR_CHAR))) then
  begin
    result := false;
    exit;
  end;

  // check if response contains buffer full.
  if (pck.ContainsString(MOD_ELM_MSG_BUFFER_FULL)) then
  begin
    result := false;
    exit;
  end;

  // we need to check if message is a CAN error!
  if (pck.ContainsString(MOD_ELM_MSG_CAN_ERROR)) then
  begin
    result := false;
    self._msg_sender.SendMessage(MOD_MSG_COM_ELM_CAN_ERROR);
    exit;
  end;

  // also, we need to check every message if it starts with "SEARCHING...", because that
  // will happen if we set protocol to auto.
  // message will come with next regular OBD command
  if (pck.ContainsString(MOD_ELM_SEARCHING_STRING)) then
  begin
    // okay, we have a full protocol search answer. Let's see what it returned.
    // basically, it's enough to search for a few possibilities :

    if (pck.ContainsString(MOD_ELM_MSG_UNABLE_TO_CONNECT)) then
    begin
      result := false;
      self._msg_sender.SendMessage(MOD_MSG_COM_ELM_CANNOT_CONNECT_TO_CANBUS);
      exit;
    end;

    // if none of the errors happened, we simply remove the "searching..." string.
    pck.RemoveString(MOD_ELM_SEARCHING_STRING);

  end;

  // finally, let's handle message.
  // after this point, we can even change contents of packet.
  // it has already been copied to _last_recv_cleaned_packet in case we need a base one again.
  case pck.msg_type of

    mod_elmmt_OBD:
      begin
        // we have an obd message!
        _last_recv_obd_packet := _last_recv_cleaned_packet;
        self._msg_sender.SendMessage(MOD_MSG_OBD_RECIEVED);
        result := true;
      end;

    mod_elmmt_ATCEA:
      begin
        // IF ATCEA is sent without an addr parameter, it is deactivated
        if (self._requested_parameters.at_cea > -1) then
        begin
          self._parameter_state.can_addressing_mode := modELMAddrMode_Extended;
          self._parameter_state.can_ext_addressing_address := self._requested_parameters.at_cea;
        end
        else
          self._parameter_state.can_addressing_mode := modELMAddrMode_Normal;
        result := pck.ContainsString(MOD_ELM_CONFIRMATION_STRING);
      end;

    mod_elmmt_ATFCSM:
      begin
        self._parameter_state.can_flow_control_mode := _requested_parameters.at_fc_sm;
        result := pck.ContainsString(MOD_ELM_CONFIRMATION_STRING);
      end;

    mod_elmmt_ATCM:
      begin
        self._parameter_state.can_mask := _requested_parameters.at_cm;
        result := pck.ContainsString(MOD_ELM_CONFIRMATION_STRING);
      end;

    mod_elmmt_ATCF:
      begin
        self._parameter_state.can_filter := _requested_parameters.at_cf;
        result := pck.ContainsString(MOD_ELM_CONFIRMATION_STRING);
      end;

    mod_elmmt_ATFCSH:
      begin
        self._parameter_state.can_flow_control_header := _requested_parameters.at_fc_sh;
        result := pck.ContainsString(MOD_ELM_CONFIRMATION_STRING);
      end;

    mod_elmmt_ATFCSD:
      begin
        self._parameter_state.can_flow_control_data_bytes := _requested_parameters.at_fc_sd;
        result := pck.ContainsString(MOD_ELM_CONFIRMATION_STRING);
      end;

    mod_elmmt_ATBI:
      begin
        result := pck.ContainsString(MOD_ELM_CONFIRMATION_STRING);
      end;

    mod_elmmt_ATSH:
      begin
        self._parameter_state.can_header := _requested_parameters.at_sh;
        result := pck.ContainsString(MOD_ELM_CONFIRMATION_STRING);
      end;

    mod_elmmt_ATPB:
      begin
        self._parameter_state.protocol_b_options := _requested_parameters.at_pb;
        result := pck.ContainsString(MOD_ELM_CONFIRMATION_STRING);
      end;

    mod_elmmt_ATCRA:
      begin
        self._parameter_state.can_recv_address_filter := _requested_parameters.at_cra;
        result := pck.ContainsString(MOD_ELM_CONFIRMATION_STRING);
      end;

    mod_elmmt_ATRV:
      begin
        // parse voltage
        // remove "V" from end
        self.ELMVoltageString := pck.msg;
        pck.RemoveString('V');
        self.ELMVoltage := pck.ToFloat();
        self._msg_sender.SendMessage(MOD_MSG_COM_ELM_VOLTAGE);
        result := true;
      end;

    mod_elmmt_ATZ:
      begin
        if (pck.ContainsString('ELM327')) then
        begin
          self.ELMVersionString := pck.msg;
          pck.RemoveString('ELM327 v');
          self.ELMVersion := pck.ToFloat();
          self._msg_sender.SendMessage(MOD_MSG_COM_ELM_FOUND);
          result := true;
        end;

      end;

    mod_elmmt_ATE:
      begin
        // echo state
        // probably contains OK
        result := pck.ContainsString(MOD_ELM_CONFIRMATION_STRING);
      end;

    mod_elmmt_ATL:
      begin
        // linebreak state
        // probably contains OK, TODO
        result := pck.ContainsString(MOD_ELM_CONFIRMATION_STRING);
      end;

    mod_elmmt_ATSP:
      begin
        // set protocol. This is important!
        result := pck.ContainsString(MOD_ELM_CONFIRMATION_STRING);
      end;

    mod_elmmt_ATFE:
      begin
        // forget events.
        result := pck.ContainsString(MOD_ELM_CONFIRMATION_STRING);
      end;

    mod_elmmt_ATH:
      begin
        // set headers
        result := pck.ContainsString(MOD_ELM_CONFIRMATION_STRING);
      end;

    mod_elmmt_ATDPN:
      begin
        // 2 forms can happen :
        // Ax
        // x
        // x = protocol number
        // A means auto mode found a certain protocol
        if (length(pck.msg) > 0) then
        begin
          if (pck.msg[1] = 'A') then
          begin
            if (length(pck.msg) = 2) then
              self.ELMProtocol := TmodOBDProtocol(StrToInt(pck.msg[2]));
          end
          else
          begin
            self.ELMProtocol := TmodOBDProtocol(StrToInt(pck.msg[1]));
          end;
        end;

        if (self.ELMProtocol <> modOBDProtocol_Auto) then
        begin
          // if everythign went well, we should now not be in automatic mode anymore.
          // it should now be on some protocol that it deemed fitting, and not on 0 (auto).

          // set this protocol, remove Auto.
          self.SetProtocol(self.ELMProtocol);
          // ELM is ready, we have protocol!
          self._msg_sender.SendMessage(MOD_MSG_COM_ELM_READY);
          self._msg_sender.SendMessage(MOD_MSG_COM_ELM_FOUND_PROTOCOL, byte(self.ELMProtocol));

          result := true;
        end
        else
        begin
          // protocol detection failed - ELM is still in auto mode,
          // which means that it had problems setting a specific protocol for us to use.
          // notify mainform of this.
          self._msg_sender.SendMessage(MOD_MSG_COM_ELM_FOUND_PROTOCOL_FAILED);
          result := false;
        end;

      end;

  else
    begin

    end;

  end;

end;

function TmodELMInterface.IsConnected: boolean;
begin
  if (Assigned(self._com_port)) then
  begin
    result := (_com_port.GetComportState() <> modComPort_Disconnected);
  end
  else
    result := false;

end;

procedure TmodELMInterface.ProcessMessages;
var
  packet: TmodELMMessage;
  ret_send, ret_recv: integer;
begin

  // check if we need to send keepalive (ATRV)
  if ((self.GetTimestamp() - _last_elm_message) > MOD_COM_ELM_HEARTBEAT_INTERVALL) then
  begin
    self.RequestVoltage();
    _last_elm_message := self.GetTimestamp();
  end;

  // check if we need to send messages
  // we only send if state is idle (not awaiting a response), and of course if we have one.
  // also, com port should not be in pending state.
  if ((_sendqueue.Count > 0) and (_state = modELMState_Idle)
    { and (_com_port.GetComportState = modComPort_Connected) } ) then
  begin
    if (_sendqueue.Count > MOD_COM_IO_FLOOD_DANGER_THRESHOLD) then
    begin
      // notify mainform that we have to slow the fuck down with messages!
      self._msg_sender.SendMessage(MOD_MSG_COM_MSG_FLOOD_DANGER, _sendqueue.Count);
    end;

    if (Assigned(self._interface_msg_dest)) then
    begin
      packet := _sendqueue.Dequeue();

      ret_send := self._interface_msg_dest(packet.msg);
      if (ret_send > 0) or (ret_send = MOD_COM_RESULT_PENDING) then
      begin

        {$IFDEF DEBUG}
        _message_log.Add('SEND:' + packet.msg);
        {$ENDIF}
        {$IFDEF DEBUG}
        self._msg_sender.SendMessage(MOD_MSG_COM_MSG_SENT, ret_send);
        {$ENDIF}
        // we are waiting for response to this message!
        _state := modELMState_awaiting_response;
        // set this packet to be the last one we sent
        _last_sent_packet := packet;

      end
      else
      begin
        if (ret_send = MOD_COM_RESULT_ERROR) then
        begin
          _error_list.Add(_com_port.GetErrorState());
          self._msg_sender.SendMessage(MOD_MSG_COM_MSG_SEND_ERROR, _error_list.Count - 1);
        end;
      end;

    end
    else
    begin
      self._msg_sender.SendMessage(MOD_MSG_COM_ELM_INTERFACE_NO_MESSAGE_DEST);
    end;

  end;

  // now check if we have a message incomming!
  if (Assigned(_interface_msg_src)) then
  begin
    ret_recv := self._interface_msg_src(packet.msg);

    if (ret_recv > 0) or (ret_recv = MOD_COM_RESULT_PENDING) then
    begin
      {$IFDEF DEBUG}
      _message_log.Add('RECV:' + packet.msg);
      _message_log.SaveToFile('log.txt');
      {$ENDIF}
      // this packet is a response to the last sent message, so it is obviously of the same type!
      packet.msg_mode := _last_sent_packet.msg_mode;
      packet.msg_type := _last_sent_packet.msg_type;

      // We need to check what's up with this packet!
      case packet.GetPacketState() of
        modMessageState_none:
          begin
            // the packet is simply empty. Not bad, continue.
          end;

        modMessageState_okay:
          begin

            // first, we need to check if there are any packet fragments in the fragment list.
            // If we have fragments, then they came before this one.
            // that means we need to add them up, and combine into a final packet.
            if (_packet_fragments.Count > 0) then
              packet := CombineFragments(packet);

            // capitalize packet message
            packet.msg := UpperCase(packet.msg);

            // give it a copy of current elm paremeter state.
            // this is important when wanting to parse the message later on.
            // for example, the setting of can addressing mode is important.
            packet.elm_param_state := self._parameter_state;

            // set this packet to be the one we recived last
            _last_recv_packet := packet;
            // set time of this recv packet
            _last_elm_message := GetTimestamp();
            // finally, handle that packet.
            if (self.HandleLastELMMessage()) then
            begin
              inc(_message_id_counter);
              {$IFDEF DEBUG}
              // notify mainform that we recieved a packet!
              // This only gets sent if it was handled correctly
              self._msg_sender.SendMessage(MOD_MSG_COM_MSG, ret_recv);
              {$ENDIF}
            end
            else
            begin
              // This is a bad error.
              self._msg_sender.SendMessage(MOD_MSG_COM_ELM_PARSING_ERROR);
            end;

            // Set ELMInterpreter state back to idle. We are ready to recieve next packet.
            _state := modELMState_Idle;

          end;

        modMessageState_incomplete:
          begin
            // add this packet to the fragment list.
            // first we set the message type though!
            packet.msg_mode := _last_sent_packet.msg_mode;
            packet.msg_type := _last_sent_packet.msg_type;
            _packet_fragments.Add(packet);
            // continue. Someday a terminated packet will come in!
          end;

      end;

    end
    else
    begin

      if (ret_recv = MOD_COM_RESULT_ERROR) then
      begin
        _error_list.Add(_com_port.GetErrorState());
        self._msg_sender.SendMessage(MOD_MSG_COM_MSG_RECV_ERROR, _error_list.Count - 1);
      end;
    end;

  end
  else
  begin
    self._msg_sender.SendMessage(MOD_MSG_COM_ELM_INTERFACE_NO_MESSAGE_SRC);
  end;

end;

procedure TmodELMInterface.RequestVoltage;
var
  packet: TmodELMMessage;
begin
  packet.SetMessage('ATRV');
  packet.msg_mode := modELMMessageType_ELM;
  packet.msg_type := mod_elmmt_ATRV;
  self.SendPacket(packet);
end;

procedure TmodELMInterface.SetupAdapter;
var
  packet: TmodELMMessage;
begin
  // do a hard reset
  self.ResetHard;
  // get voltage
  self.RequestVoltage;
  // deactivate echo
  self.SetEchoState(false);
  // deactivate linefeeds, who needs those
  self.SetLineFeedState(false);
  // we also want headers!
  self.SetHeaderState(true);

  // last :
  // attempt to find protocol!
  // self.FindProtocol();
end;

function TmodELMInterface.ToCAN11Bit(value: cardinal): ansistring;
begin
  result := IntToHex(value, 3);
  // result := system.Delete(result, 1, 1);
end;

procedure TmodELMInterface.FindProtocol;
begin
  // set protocol to auto
  self.SetProtocol(modOBDProtocol_Auto);
  // send an OBD message that should work on all cars.
  // namely service 1 pid 0 - get capabilities range 0-0x20
  // ELM seraches for protocol with this message
  self.SendOBDMessage('0100');
  // now, we want to have this protocol described!
  self.DescribeProtocolNumber();
end;

procedure TmodELMInterface.ResetHard;
var
  packet: TmodELMMessage;
begin
  packet.SetMessage('ATZ');
  packet.msg_mode := modELMMessageType_ELM;
  packet.msg_type := mod_elmmt_ATZ;
  self.SendPacket(packet);
end;

procedure TmodELMInterface.ResetInterface;
begin
  _message_log.Clear;
  _packet_fragments.Clear;
  _error_list.Clear;
  _sendqueue.Clear;
  _last_elm_message := 0;
  _last_sent_packet.Reset;
  _last_recv_packet.Reset;
  _last_recv_cleaned_packet.Reset;
  _last_recv_obd_packet.Reset;
  _state := modELMState_Idle;
end;

procedure TmodELMInterface.SendOBDMessage(msg: TmodELMMessageString);
var
  pck: TmodELMMessage;
begin
  pck.SetMessage(msg);
  pck.msg_mode := modELMMessageType_OBD;
  pck.msg_type := mod_elmmt_OBD;
  self.SendPacket(pck);
end;

procedure TmodELMInterface.SendPacket(packet: TmodELMMessage);
begin
  _sendqueue.Enqueue(packet);
end;

procedure TmodELMInterface.SetCanExtendedAddress(addr: byte);
var
  packet: TmodELMMessage;
begin
  self._requested_parameters.at_cea := addr;
  packet.SetMessage('ATCEA' + IntToHex(addr, 2));
  packet.msg_mode := modELMMessageType_ELM;
  packet.msg_type := mod_elmmt_ATCEA;
  self.SendPacket(packet);

end;

procedure TmodELMInterface.SetCanFilter(filter: cardinal);
var
  packet: TmodELMMessage;
begin
  self._requested_parameters.at_cf := filter;
  packet.SetMessage('ATCF' + ToCAN11Bit(filter));
  packet.msg_mode := modELMMessageType_ELM;
  packet.msg_type := mod_elmmt_ATCF;
  self.SendPacket(packet);
end;

procedure TmodELMInterface.SetCanFlowControlData(db: TmodELMInterfaceCANFlowControlDatabytes);
var
  packet: TmodELMMessage;
  strbytes: ansistring;
  i: integer;
begin

  Assert(db.byte_count <= 5);

  self._requested_parameters.at_fc_sd := db;
  strbytes := '';
  for i := 0 to db.byte_count - 1 do
    strbytes := strbytes + IntToHex(db.bytes[i], 2);
  packet.SetMessage('ATFCSD' + strbytes);
  packet.msg_mode := modELMMessageType_ELM;
  packet.msg_type := mod_elmmt_ATFCSD;
  self.SendPacket(packet);
end;

procedure TmodELMInterface.SetCanFlowControlHeader(hdr: cardinal);
var
  packet: TmodELMMessage;
begin
  self._requested_parameters.at_fc_sh := hdr;
  packet.SetMessage('ATFCSH' + ToCAN11Bit(hdr));
  packet.msg_mode := modELMMessageType_ELM;
  packet.msg_type := mod_elmmt_ATFCSH;
  self.SendPacket(packet);
end;

procedure TmodELMInterface.SetCanFlowControlMode(mode: TmodELMInterfaceCANFlowControlMode);
var
  packet: TmodELMMessage;
begin
  self._requested_parameters.at_fc_sm := mode;
  packet.SetMessage('ATFCSM' + Inttostr(byte(mode)));
  packet.msg_mode := modELMMessageType_ELM;
  packet.msg_type := mod_elmmt_ATFCSM;
  self.SendPacket(packet);

end;

procedure TmodELMInterface.SetCanMask(mask: cardinal);
var
  packet: TmodELMMessage;
begin
  self._requested_parameters.at_cm := mask;
  packet.SetMessage('ATCM' + ToCAN11Bit(mask));
  packet.msg_mode := modELMMessageType_ELM;
  packet.msg_type := mod_elmmt_ATCM;
  self.SendPacket(packet);

end;

procedure TmodELMInterface.SetCOMPort(com_port: TmodComPort);
begin
  // set interface message source to COM port by default!
  _com_port := com_port;
  self.SetDataSourcesToCOM;
end;

procedure TmodELMInterface.SetDataDest(dest: TmodELMMessageDataDest);
begin
  _interface_msg_dest := dest;
end;

procedure TmodELMInterface.SetDataSource(src: TmodELMMessageDataSource);
begin
  _interface_msg_src := src;
end;

procedure TmodELMInterface.SetDataSourcesToCOM;
begin
  _interface_msg_src := _com_port.Recv;
  _interface_msg_dest := _com_port.Send;
end;

procedure TmodELMInterface.SetEchoState(echo: boolean);
var
  packet: TmodELMMessage;
begin
  if (echo) then
    packet.SetMessage('ATE1')
  else
    packet.SetMessage('ATE0');

  packet.msg_mode := modELMMessageType_ELM;
  packet.msg_type := mod_elmmt_ATE;
  self.SendPacket(packet);
end;

procedure TmodELMInterface.SetHeader(can_11_bit: cardinal);
var
  packet: TmodELMMessage;
begin
  _requested_parameters.at_sh := can_11_bit;
  packet.SetMessage('ATSH' + ToCAN11Bit(can_11_bit));
  packet.msg_mode := modELMMessageType_ELM;
  packet.msg_type := mod_elmmt_ATSH;
  self.SendPacket(packet);

end;

procedure TmodELMInterface.SetHeaderState(headers: boolean);
var
  packet: TmodELMMessage;
begin
  if (headers) then
    packet.SetMessage('ATH1')
  else
    packet.SetMessage('ATH0');
  packet.msg_mode := modELMMessageType_ELM;
  packet.msg_type := mod_elmmt_ATH;
  self.SendPacket(packet);
end;

procedure TmodELMInterface.SetLineFeedState(linefeeds: boolean);
var
  packet: TmodELMMessage;
begin
  if (linefeeds) then
    packet.SetMessage('ATL1')
  else
    packet.SetMessage('ATL0');
  packet.msg_mode := modELMMessageType_ELM;
  packet.msg_type := mod_elmmt_ATL;
  self.SendPacket(packet);
end;

procedure TmodELMInterface.SetProtocol(protocol: TmodOBDProtocol);
var
  packet: TmodELMMessage;
begin
  packet.SetMessage('ATSP' + IntToHex(byte(protocol), 1));
  packet.msg_mode := modELMMessageType_ELM;
  packet.msg_type := mod_elmmt_ATSP;
  self.SendPacket(packet);
end;

procedure TmodELMInterface.SetProtocolBOptions(flags, baud_rate_divisor: byte);
var
  packet: TmodELMMessage;
begin
  _requested_parameters.at_pb.flags := flags;
  _requested_parameters.at_pb.baudrate_divisor := baud_rate_divisor;
  packet.SetMessage('ATPB' + IntToHex(flags, 2) + IntToHex(baud_rate_divisor, 2));
  packet.msg_mode := modELMMessageType_ELM;
  packet.msg_type := mod_elmmt_ATPB;
  self.SendPacket(packet);

end;

procedure TmodELMInterface.SetRecieveAddressFilter(addr: cardinal);
var
  packet: TmodELMMessage;
begin
  _requested_parameters.at_cra := addr;
  packet.SetMessage('ATCRA' + ToCAN11Bit(addr));
  packet.msg_mode := modELMMessageType_ELM;
  packet.msg_type := mod_elmmt_ATCRA;
  self.SendPacket(packet);

end;

{ TmodELMData }

end.
