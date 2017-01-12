unit modELMTypes;

interface

type
  TmodELMMessageDataSource = function(var data: ansistring): integer of object;

type
  TmodELMMessageDataDest = function(data: ansistring): integer of object;

type
  TmodELMState = (modELMState_Idle, modELMState_awaiting_response);

  // normal - normal operation.
  // cleaner - just clean everything passed to you. Don't interpret it.
type
  TmodELMInterfaceOperationMode = (modELMOpMode_normal, modELMOpMode_cleaner);

  // Normal - normal addressing : [ident] [pci] [data]
  // extended - extended addressing [ident] [addr] [pci] [data]
type
  TmodELMInterfaceAddressingMode = (modELMAddrMode_Normal, modELMAddrMode_Extended);

  (*

    modELMCANFlowControlMode_ELM_provided (0)
    ~~~~~~~~~~~~~~~~~
    ELM provides ID and Data bits
    User provides nothing

    modELMCANFlowControlMode_User_Provided (1)
    ~~~~~~~~~~~~~~~~~
    user provides both, ELM nothing

    modELMCANFlowControlMode_Shared (2)
    ~~~~~~~~~~~~~~~~~
    ELM - id bits
    user - data bytes

  *)
type
  TmodELMInterfaceCANFlowControlMode = (modELMCANFlowControlMode_ELM_provided, modELMCANFlowControlMode_User_Provided,
    modELMCANFlowControlMode_Shared);

  (*
    Single 	type = 3 	(0 = Clear To Send, 1 = Wait, 2 = Overflow/abort) 	0 = remaining "frames" to be sent without flow control or delay 	<= 127, separation time in milliseconds.
    Single 	type = 3 	(0 = Clear To Send, 1 = Wait, 2 = Overflow/abort) 	> 0 send number of "frames" before waiting for the next flow control frame 	0xF1 to 0xF9, 100 to 900 microseconds.

  *)

type
  TmodELMInterfaceCANFlowControlDatabytes = record
    // flow controll message can have between one and 5 data bytes, inclusive
    byte_count: byte;
    bytes: array [0 .. 4] of byte;
  end;

type
  TmodELMInterfaceProtocolBOptions = record
    flags: byte;
    baudrate_divisor: byte;
  end;

  // (*
  // modELM_msg_result_success
  // - Message parsing was a success
  // *)
  // type
  // TmodELMMessageHandleResult = (modELM_msg_result_success, modELM_msg_result_ignore, modELM_msg_result_error);

  // things that have been requested, but we have not recieved conformation for yet.
type
  TmodELMInterfaceRequestedParameters = record
    at_cea: byte;
    at_fc_sh: cardinal;
    at_fc_sd: TmodELMInterfaceCANFlowControlDatabytes;
    at_pb: TmodELMInterfaceProtocolBOptions;
    at_cra: cardinal;
    at_sh: cardinal;
    at_fc_sm: TmodELMInterfaceCANFlowControlMode;
    at_cm: cardinal;
    at_cf: cardinal;
  end;

type
  TmodELMInterfaceParameterState = record
    // header setting
    can_header: cardinal;
    // can filter bits
    can_filter: cardinal;
    // can mask bits
    can_mask: cardinal;
    // CAN state
    can_addressing_mode: TmodELMInterfaceAddressingMode;
    // can extended addressing address
    can_ext_addressing_address: byte;
    // can flow control mode
    can_flow_control_mode: TmodELMInterfaceCANFlowControlMode;
    // can flow control header
    can_flow_control_header: cardinal;
    // can flow control data bytes
    can_flow_control_data_bytes: TmodELMInterfaceCANFlowControlDatabytes;
    // protocol B options
    protocol_b_options: TmodELMInterfaceProtocolBOptions;
    // can recieve address filter
    can_recv_address_filter: cardinal;
  end;

implementation

end.
