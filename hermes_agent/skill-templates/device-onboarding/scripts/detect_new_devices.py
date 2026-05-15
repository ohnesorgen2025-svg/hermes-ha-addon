#!/usr/bin/env python3
"""
Zigbee2MQTT New Device Detector
Standalone script that connects to MQTT, fetches the Z2M device list,
compares against known devices, and outputs new device notifications.

Designed for cron execution with no_agent=True (watchdog pattern).
Empty stdout = nothing to report. Non-empty stdout = new device notification.
"""

import json
import os
import sys
import time

# --- Configuration ---
KNOWN_DEVICES_FILE = os.path.expanduser("~/.hermes/device_onboarding/known_devices.json")
MQTT_HOST = os.environ.get("MQTT_HOST", "core-mosquitto")
MQTT_PORT = int(os.environ.get("MQTT_PORT", "1883"))
MQTT_USER = os.environ.get("MQTT_USER", "")
MQTT_PASSWORD = os.environ.get("MQTT_PASSWORD", "")

# Fallback: read from .env file if env vars are empty
if not MQTT_HOST or MQTT_HOST == "localhost":
    env_path = os.path.expanduser("~/.hermes/.env")
    if os.path.exists(env_path):
        with open(env_path, "r") as f:
            for line in f:
                line = line.strip()
                if "=" in line and not line.startswith("#"):
                    key, val = line.split("=", 1)
                    key = key.strip()
                    val = val.strip()
                    if key == "MQTT_HOST" and not MQTT_HOST:
                        MQTT_HOST = val
                    elif key == "MQTT_PORT" and MQTT_PORT == 1883:
                        MQTT_PORT = int(val)
                    elif key == "MQTT_USER" and not MQTT_USER:
                        MQTT_USER = val
                    elif key == "MQTT_PASSWORD" and not MQTT_PASSWORD:
                        MQTT_PASSWORD = val


def load_known_devices():
    if os.path.exists(KNOWN_DEVICES_FILE):
        with open(KNOWN_DEVICES_FILE, "r") as f:
            return set(json.load(f))
    return set()


def save_known_devices(ieee_addresses):
    os.makedirs(os.path.dirname(KNOWN_DEVICES_FILE), exist_ok=True)
    with open(KNOWN_DEVICES_FILE, "w") as f:
        json.dump(sorted(list(ieee_addresses)), f, indent=2)


def fetch_z2m_devices():
    """Connect to MQTT, request Z2M bridge devices, return device list."""
    import paho.mqtt.client as mqtt

    devices_data = {}
    received = {"bridge_info": False, "devices_list": False}
    result = []

    def on_connect(client, userdata, flags, rc, properties=None):
        if rc == 0:
            # Subscribe to Z2M bridge devices topic
            client.subscribe("zigbee2mqtt/bridge/devices")
            # Request device list by publishing to bridge/devices/get
            client.publish("zigbee2mqtt/bridge/devices/get", payload="")
        else:
            print(f"MQTT connection failed with code {rc}", file=sys.stderr)
            sys.exit(1)

    def on_message(client, userdata, msg):
        topic = msg.topic
        payload = msg.payload.decode("utf-8", errors="replace")
        if topic == "zigbee2mqtt/bridge/devices":
            try:
                devices_data["devices"] = json.loads(payload)
                received["devices_list"] = True
            except json.JSONDecodeError:
                pass

    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="z2m_device_detector")
    if MQTT_USER:
        client.username_pw_set(MQTT_USER, MQTT_PASSWORD)
    client.on_connect = on_connect
    client.on_message = on_message

    try:
        client.connect(MQTT_HOST, MQTT_PORT, 60)
    except Exception as e:
        print(f"MQTT connection error: {e}", file=sys.stderr)
        sys.exit(1)

    client.loop_start()
    timeout = 10  # seconds
    start = time.time()
    while not received["devices_list"] and (time.time() - start) < timeout:
        time.sleep(0.5)
    client.loop_stop()
    client.disconnect()

    if "devices" in devices_data:
        result = devices_data["devices"]
        # Also save current devices to file for debugging
        current_path = os.path.expanduser("~/.hermes/device_onboarding/current_devices.json")
        os.makedirs(os.path.dirname(current_path), exist_ok=True)
        with open(current_path, "w") as f:
            json.dump(result, f, indent=2, ensure_ascii=False)

    return result


def main():
    known = load_known_devices()
    devices = fetch_z2m_devices()

    if not devices:
        # Couldn't fetch devices - silent
        print("")
        return

    new_devices = []
    for dev in devices:
        ieee = dev.get("ieee_address", "")
        dev_type = dev.get("type", "")
        # Skip coordinator and already-known devices
        if dev_type == "Coordinator" or ieee in known:
            continue
        new_devices.append(dev)

    if not new_devices:
        print("")
        return

    # Build notification message
    lines = []
    for dev in new_devices:
        definition = dev.get("definition", {}) or {}
        description = definition.get("description", "Unbekanntes Gerät")
        vendor = definition.get("vendor", "Unbekannt")
        model = definition.get("model", "Unbekannt")
        ieee = dev.get("ieee_address", "")
        friendly = dev.get("friendly_name", ieee)
        power = dev.get("power_source", "Unbekannt")

        lines.append(f"✅ Neues Gerät: {description}")
        lines.append(f"  Hersteller: {vendor} | Modell: {model}")
        lines.append(f"  IEEE: {ieee} | Name: {friendly} | Strom: {power}")
        lines.append("---")

    # Remove trailing separator
    if lines and lines[-1] == "---":
        lines.pop()

    print("\n".join(lines))

    # Mark new devices as known
    for dev in new_devices:
        known.add(dev.get("ieee_address", ""))
    save_known_devices(known)


if __name__ == "__main__":
    main()
