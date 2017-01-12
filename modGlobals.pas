unit modGlobals;

interface

uses
  windows, messages;

//type
//  TmodOBDProtocolFamily = (modOBDProtocolFamily_CAN, modOBDProtocolFamily_SAE_J1850, modOBDProtocolFamily_J1939,
//    modOBDProtocolFamily_Custom);
//
//type
//  TmodOBDProtocol = (modOBDProtocol_Auto, modOBDProtocol_SAE_J1850_PWM, modOBDProtocol_SAE_J1850_VPW, modOBDProtocol_ISO_9141_2,
//    modOBDProtocol_ISO_14230_4_KWP_SI, modOBDProtocol_ISO_14230_4_KWP_FI, modOBDProtocol_ISO_15765_4_CAN_11_500,
//    modOBDProtocol_ISO_15765_4_CAN_29_500, modOBDProtocol_ISO_15765_4_CAN_11_250, modOBDProtocol_ISO_15765_4_CAN_29_250,
//    modOBDProtocol_SAE_J1939_CAN_29_250, modOBDProtocol_USER1_CAN_11_125, modOBDProtocol_USER1_CAN_11_50);

const

  // data constants
  BMW_DATA_ECU_MAGIC = 6000014350977617741;
  BMW_DATA_ECU_FILE_VERSION = 1;

  // max com ports searched [1..n]
  MOD_COM_MAX = 16;
  MOD_COM_MAX_BYTES = 4096;
  MOD_COM_IO_TIMEOUT = 3000;
  MOD_COM_IO_MAX_REPEAT = 1;
  MOD_COM_IO_MAX_WAIT_TIME = 400; //in ms
  MOD_COM_IO_MAX_WAIT_TIME_SEND = 500; //in ms
  MOD_COM_IO_FLOOD_DANGER_THRESHOLD = 15;
  MOD_COM_ELM_HEARTBEAT_INTERVALL = 20; // seconds

  BMW_TASK_MAX_CYLCE_COUNT = 250;

  //MOD_ELM_MAX_PAYLOAD_LENGTH = 4095;

  // messaging system
  MOD_MSG_BASE = WM_APP + 1024;

  // messages to mainform

  // raw COM connection
  MOD_MSG_COM_SEARCH_START = MOD_MSG_BASE + 1;
  MOD_MSG_COM_SEARCH_STOP = MOD_MSG_BASE + 2;
  MOD_MSG_COM_SEARCH_FOUND = MOD_MSG_BASE + 3;

  // COM port connection messages
  MOD_MSG_COM_DISCONNECTED = MOD_MSG_BASE + 4;
  MOD_MSG_COM_CONNECTION_REFUSED = MOD_MSG_BASE + 5;
  MOD_MSG_COM_CONNECTION_OK = MOD_MSG_BASE + 6;

  // recieved message
  MOD_MSG_COM_MSG = MOD_MSG_BASE + 7;
  MOD_MSG_COM_MSG_SENT = MOD_MSG_BASE + 8;

  // too many packets are in queue, slow down!
  // wparam contains current amount of packets in out queue
  MOD_MSG_COM_MSG_FLOOD_DANGER = MOD_MSG_BASE + 9;

  // We are on normal packet levels again, you can kick it up a notch
  MOD_MSG_COM_MSG_FLOOD_DRIED = MOD_MSG_BASE + 10;

  // there was an error sending a packet!
  MOD_MSG_COM_MSG_SEND_ERROR = MOD_MSG_BASE + 11;

  // there was an error reading a packet.
  // wparam contains index of error entry in ELMInterface
  MOD_MSG_COM_MSG_RECV_ERROR = MOD_MSG_BASE + 12;
  MOD_OBD_MAX_PAYLOAD_LENGTH = 256;


//  // elm interpreter
//
//  // found an ELM chip
//  MOD_MSG_COM_ELM_FOUND = MOD_MSG_BASE + 100;
//
//  // recieved ELM version
//  MOD_MSG_COM_ELM_CORRECT_VERSION = MOD_MSG_BASE + 101;
//
//  // ELM ready for car interaction
//  MOD_MSG_COM_ELM_READY = MOD_MSG_BASE + 102;
//
//  // There was a fatal parsing error in one message. Tread with caution!
//  MOD_MSG_COM_ELM_PARSING_ERROR = MOD_MSG_BASE + 103;
//
//  // ELM successfully found protocol version!
//  // contains protocol ID in wparam.
//  MOD_MSG_COM_ELM_FOUND_PROTOCOL = MOD_MSG_BASE + 104;
//
//  // ELM cannot connect to CAN bus. Car is probably not in ignition.
//  MOD_MSG_COM_ELM_CANNOT_CONNECT_TO_CANBUS = MOD_MSG_BASE + 105;
//
//  // ELM said there was a CAN error. Message is pretty much same as MOD_MSG_COM_ELM_CANNOT_CONNECT_TO_CANBUS,
//  // but for debugging I have chosen to seperate them.
//  MOD_MSG_COM_ELM_CAN_ERROR = MOD_MSG_BASE + 106;
//
//  // ELM failed to find protocol version!
//  // this is fatal.
//  MOD_MSG_COM_ELM_FOUND_PROTOCOL_FAILED = MOD_MSG_BASE + 107;
//
//  // You forgot to handle a message type (TmodELMMessageType), you dork.
//  MOD_MSG_COM_ELM_UNKNOWN_MESSAGE_TYPE = MOD_MSG_BASE + 108;
//
//  // ELM interface message source isn't set! FATAL error.
//  MOD_MSG_COM_ELM_INTERFACE_NO_MESSAGE_SRC = MOD_MSG_BASE + 109;
//
//  // ELM interface message dest isn't set! FATAL error.
//  MOD_MSG_COM_ELM_INTERFACE_NO_MESSAGE_DEST = MOD_MSG_BASE + 110;
//
//  // this acts as a heartbeat message!
//  // recieved voltage from ELM
//  MOD_MSG_COM_ELM_VOLTAGE = MOD_MSG_BASE + 199;


  // obd related messages

  // ELM recieved a raw OBD message!
  MOD_MSG_OBD_RECIEVED = MOD_MSG_BASE + 200;

  // The message was parsed successfully by Car interface!
  MOD_MSG_OBD_PARSED = MOD_MSG_BASE + 201;

  // The message was NOT parsed by Car interface!
  MOD_MSG_OBD_PARSE_ERROR = MOD_MSG_BASE + 202;

  // task related messages

  // task started
  MOD_MSG_TASK_STARTED = MOD_MSG_BASE + 500;
  // task finished
  MOD_MSG_TASK_FINISHED = MOD_MSG_BASE + 501;
  // task error
  MOD_MSG_TASK_ERROR = MOD_MSG_BASE + 502;
  // all tasks processed
  MOD_MSG_TASK_ALL_FINISHED = MOD_MSG_BASE + 503;

  // car related messages
  // GOT full vin
  MOD_MSG_CAR_GOT_VIN = MOD_MSG_BASE + 1000;

implementation

{ TmodELMData }

end.

