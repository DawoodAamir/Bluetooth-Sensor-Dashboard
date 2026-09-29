# Hardware verification

The simulator supports the explicit demo path. Real sensor compatibility requires a Bluetooth LE peripheral advertising service `180D` and notifying characteristic `2A37`.

## Manual matrix

- First use: deny Bluetooth permission; confirm that the state explains how to enable it.
- Bluetooth off: scan; verify the state and retry after enabling Bluetooth.
- No devices: wait for the 12-second scan timeout.
- Wake a sensor and scan: verify device name and signal, then connect.
- Check heart rate against the sensor’s companion display. Optional `180F` / `2A19` battery data may be absent.
- Move out of range: confirm disconnect feedback and retained readings.
- Stop during connection: verify cleanup, then reconnect.
- Background the app: confirm the foreground session ends.
- Export real and demo sessions: verify the source labels are different.
- Send truncated notifications with a test peripheral: confirm error handling.

Record the sensor model, firmware, iPhone model, and iOS version for each successful hardware run. No hardware compatibility claim is made until this matrix is completed.

## Packet format

The parser follows the [Bluetooth SIG Heart Rate Service](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/HRS_v1.0/out/en/index-en.html): little-endian 8/16-bit rate, optional contact flags, energy expended, and RR values in 1/1024-second units. It accepts reserved flag bits without assigning them meaning, but rejects extra unexplained bytes and incomplete fields.

Scanning is limited to the heart-rate service using [Core Bluetooth service filtering](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/scanforperipherals(withservices:options:)). There is no background mode or automatic reconnection.
