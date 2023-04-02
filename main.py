from awscrt import mqtt
import sys
import logging
from logging.handlers import TimedRotatingFileHandler
import time
import serial
import threading
from uuid import uuid4
import json
import command_line_utils as command_line_utils

cmdUtils = command_line_utils.CommandLineUtils("PubSub - Send and recieve messages through an MQTT connection.")
cmdUtils.add_common_mqtt_commands()
cmdUtils.add_common_topic_message_commands()
cmdUtils.add_common_proxy_commands()
cmdUtils.add_common_logging_commands()
cmdUtils.register_command("speed_threshold", "25", "Speed threshold in mph.", type=int)
cmdUtils.register_command("key", "<path>", "Path to your key in PEM format.", True, str)
cmdUtils.register_command("cert", "<path>", "Path to your client certificate in PEM format.", True, str)
cmdUtils.register_command("port", "<int>", "Connection port. AWS IoT supports 443 and 8883 (optional, default=auto).", type=int)
cmdUtils.register_command("client_id", "<str>", "Client ID to use for MQTT connection (optional, default='test-*').", default="test-" + str(uuid4()))
cmdUtils.register_command("is_ci", "<str>", "If present the sample will run in CI mode (optional, default='None')")
cmdUtils.get_args()

received_count = 0
received_all_event = threading.Event()
is_ci = cmdUtils.get_command("is_ci", None) != None

logging.basicConfig(
  handlers=[
    TimedRotatingFileHandler(
      'speed-radar.log', 
      when="midnight", 
      backupCount=30
    )
  ],
  level=logging.INFO,
  format='%(asctime)s %(levelname)s PID_%(process)d %(message)s'
)

logging.info("Speed threshold set to: " + str(cmdUtils.get_command("speed_threshold")) + " mph")
logging.info("AWS IoT Core API endpoint: " + str(cmdUtils.get_command("endpoint")))
logging.info("AWS IoT Core ca_file: " + str(cmdUtils.get_command("ca_file")))
logging.info("AWS IoT Core cert: " + str(cmdUtils.get_command("cert")))
logging.info("AWS IoT Core key: " + str(cmdUtils.get_command("key")))
logging.info("AWS IoT Core client_id: " + str(cmdUtils.get_command("client_id")))
logging.info("AWS IoT Core topic: " + str(cmdUtils.get_command("topic")))

# Callback when connection is accidentally lost.
def on_connection_interrupted(connection, error, **kwargs):
    logging.info("Connection interrupted. error: {}".format(error))

# Callback when an interrupted connection is re-established.
def on_connection_resumed(connection, return_code, session_present, **kwargs):
    logging.info("Connection resumed. return_code: {} session_present: {}".format(return_code, session_present))

    if return_code == mqtt.ConnectReturnCode.ACCEPTED and not session_present:
        logging.info("Session did not persist. Resubscribing to existing topics...")
        resubscribe_future, _ = connection.resubscribe_existing_topics()

        # Cannot synchronously wait for resubscribe result because we're on the connection's event-loop thread,
        # evaluate result with a callback instead.
        resubscribe_future.add_done_callback(on_resubscribe_complete)

def on_resubscribe_complete(resubscribe_future):
        resubscribe_results = resubscribe_future.result()
        logging.info("Resubscribe results: {}".format(resubscribe_results))

        for topic, qos in resubscribe_results['topics']:
            if qos is None:
                sys.exit("Server rejected resubscribe to topic: {}".format(topic))

# Callback when the subscribed topic receives a message
def on_message_received(topic, payload, dup, qos, retain, **kwargs):
    logging.info("Received message from topic '{}': {}".format(topic, payload))
    global received_count
    received_count += 1
    if received_count == cmdUtils.get_command("count"):
        received_all_event.set()

def send_serial_cmd(print_prefix, command):
    """
    function for sending serial commands to the OPS module
    """
    data_for_send_str = command
    data_for_send_bytes = str.encode(data_for_send_str)
    logging.info(print_prefix + command)
    ser.write(data_for_send_bytes)
    # initialize message verify checking
    ser_message_start = '{'
    ser_write_verify = False
    # print out module response to command string
    while not ser_write_verify:
        data_rx_bytes = ser.readline()
        data_rx_length = len(data_rx_bytes)
        if data_rx_length != 0:
            data_rx_str = str(data_rx_bytes)
            if data_rx_str.find(ser_message_start):
                ser_write_verify = True

ser = serial.Serial(
    port='/dev/ttyACM0',
    baudrate=9600,
    parity=serial.PARITY_NONE,
    stopbits=serial.STOPBITS_ONE,
    bytesize=serial.EIGHTBITS,
    timeout=1,
    writeTimeout=2
)
ser.flushInput()
ser.flushOutput()

# constants for the OPS module
Ops_Speed_Output_Units = ['US', 'UK', 'UM', 'UC']
Ops_Speed_Output_Units_lbl = ['mph', 'km/h', 'm/s', 'cm/s']
Ops_Blanks_Pref_Zero = 'BZ'
Ops_Sampling_Frequency = 'SX'
Ops_Transmit_Power = 'PX'
Ops_Threshold_Control = 'MX'
Ops_Module_Information = '??'
Ops_Overlook_Buffer = 'OZ'

# initialize the OPS module
send_serial_cmd("Overlook buffer: ", Ops_Overlook_Buffer)
send_serial_cmd("Set Speed Output Units: ", Ops_Speed_Output_Units[0])
send_serial_cmd("Set Sampling Frequency: ", Ops_Sampling_Frequency)
send_serial_cmd("Set Transmit Power: ", Ops_Transmit_Power)
send_serial_cmd("Set Threshold Control: ", Ops_Threshold_Control)
send_serial_cmd("Set Blanks Preference: ", Ops_Blanks_Pref_Zero)
# send_serial_cmd("Module Information: ", Ops_Module_Information)

def ops_get_speed(speed_threshold):
    """
    capture speed reading from OPS module
    """
    speed_available = False
    Ops_rx_bytes = ser.readline()
    # check for speed information from OPS module
    Ops_rx_bytes_length = len(Ops_rx_bytes)
    if Ops_rx_bytes_length != 0:
        Ops_rx_str = str(Ops_rx_bytes)
        # print("RX:"+Ops_rx_str)
        if Ops_rx_str.find('{') == -1:
            # speed data found
            try:
                Ops_rx_float = float(Ops_rx_bytes)
                speed_available = True
            except ValueError:
                logging.warning("Unable to convert to a number the string: " + Ops_rx_str)
                speed_available = False

    if speed_available == True:
        speed_rnd = round(Ops_rx_float)

        if abs(speed_rnd) > int(speed_threshold):
            logging.info("Object detected, speed: " + format(float(speed_rnd),'f') + " mph" )

            # message = "{} [{}]".format(message_string, float(speed_rnd))

            return speed_rnd
        return 0
    return 0

def publish_speed(speed_rnd):
    logging.info("Publishing speed to topic '{}': {}".format(message_topic, str(int(abs(speed_rnd)))))
    message_json = json.dumps(
        {
            "time": int(time.time()),
            "speed": int(abs(speed_rnd)),
        }, indent=2
    )
    mqtt_connection.publish(
        topic=message_topic,
        payload=message_json,
        qos=mqtt.QoS.AT_LEAST_ONCE)

if __name__ == "__main__":
    mqtt_connection = cmdUtils.build_mqtt_connection(on_connection_interrupted, on_connection_resumed)

    if is_ci == False:
        logging.info("Connecting to {} with client ID '{}'...".format(
            cmdUtils.get_command(cmdUtils.m_cmd_endpoint), cmdUtils.get_command("client_id")))
    else:
        logging.info("Connecting to endpoint with client ID")
    connect_future = mqtt_connection.connect()

    # Future.result() waits until a result is available
    connect_future.result()
    logging.info("Connected!")

    message_count = cmdUtils.get_command("count")
    message_topic = cmdUtils.get_command(cmdUtils.m_cmd_topic)
    message_string = cmdUtils.get_command(cmdUtils.m_cmd_message)

    # Subscribe
    logging.info("Subscribing to topic '{}'...".format(message_topic))
    subscribe_future, packet_id = mqtt_connection.subscribe(
        topic=message_topic,
        qos=mqtt.QoS.AT_LEAST_ONCE,
        callback=on_message_received)

    subscribe_result = subscribe_future.result()
    logging.info("Subscribed with {}".format(str(subscribe_result['qos'])))

    previous_detected_positive = {
        "time": int(time.time()),
        "speed": 0
    }

    previous_detected_negative = {
        "time": int(time.time()),
        "speed": 0
    }

    current_reading = 0

    while True:
        current_reading = int(ops_get_speed(str(cmdUtils.get_command("speed_threshold"))))

        if current_reading < 0:
            if current_reading < previous_detected_negative["speed"]:
                previous_detected_negative = {
                    "time": int(time.time()),
                    "speed": current_reading
                } 
        elif current_reading > 0:
            if current_reading > previous_detected_positive["speed"]:
                previous_detected_positive = {
                    "time": int(time.time()),
                    "speed": current_reading
                } 
        elif current_reading == 0:
            if previous_detected_positive["speed"] > 0:
                if int(time.time()) - previous_detected_positive["time"] > 1:
                    publish_speed(previous_detected_positive["speed"])
                    previous_detected_positive = {
                        "time": int(time.time()),
                        "speed": 0
                    }
            if previous_detected_negative["speed"] < 0:
                if int(time.time()) - previous_detected_negative["time"] > 1:
                    publish_speed(previous_detected_negative["speed"])
                    previous_detected_negative = {
                        "time": int(time.time()),
                        "speed": 0
                    }
                

