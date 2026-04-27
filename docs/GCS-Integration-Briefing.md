# GCS Dashboard Integration — KrakenSDR Triangulator App

**From:** MRA Electrical & Software  
**To:** GCS Subteam (Jason, Chief)  
**Date:** April 2026  
**Branch:** `MRA_Xbee`

---

## Overview

MRA Electrical & Software has developed a companion application called the **KrakenSDR Triangulator App**. It is a browser-based dashboard that processes RF bearing data collected by the KrakenSDR antenna array onboard the UAV and performs real-time geolocation (triangulation) to estimate where a target transmitter is located on the ground.

In short: the KrakenSDR hardware listens for a specific RF signal from the air, and the Triangulator app takes those bearing measurements and computes a **patient location estimate** (latitude/longitude).

This document describes the integration work needed so the GCS Dashboard can receive and display these patient location coordinates.

---

## Where Does the Kraken Triangulator Run?

The Kraken Triangulator app is designed to **run on the same GCS laptop** as the GCS Dashboard. It runs as a local web server on `localhost:5050` and opens in a browser tab. On demo day, both the GCS Dashboard and the Kraken Triangulator will be running side-by-side on the GCS laptop.

We will be providing the app as a **bundled standalone executable** (`KrakenTriangulator.exe`) — no Python installation or dependency setup required. Your team just needs to double-click the `.exe` and it launches automatically. We will handle delivering the installer ahead of demo day.

---

## What MRA Needs from GCS (Code Change)

Once the Kraken Triangulator computes a target location and the MRA operator clicks **TRANSMIT**, the app stores the coordinates locally. **The GCS Dashboard needs to pick up these coordinates** so it can:

1. Display the patient location on the GCS map
2. Relay the coordinates to the Pi 5 (via XBee) so the autonomy engine has the target

The integration is straightforward — the Dashboard needs to **poll a local REST endpoint** that the Kraken Triangulator exposes.

### API Endpoint

```
GET http://localhost:5050/api/target
```

### Response Format

```json
{
  "lat": 34.0592725,
  "lon": -117.8215643,
  "spread_m": 45.2,
  "count": 8,
  "timestamp": 1745783421.52
}
```

| Field | Type | Description |
|---|---|---|
| `lat` | `float` or `null` | Estimated patient latitude (WGS84). `null` if no target yet. |
| `lon` | `float` or `null` | Estimated patient longitude (WGS84). `null` if no target yet. |
| `spread_m` | `float` | Spatial spread of the estimation cluster in meters. Lower = more confident. |
| `count` | `int` | Number of triangulation hits contributing to this estimate. |
| `timestamp` | `float` | Unix timestamp (seconds) of when the estimate was generated. |

### What the GCS Dashboard Needs to Do

1. **Poll** `GET http://localhost:5050/api/target` every ~2 seconds
2. **Check** if the `timestamp` field has changed since the last poll
3. **When a new target is detected:**
   - Display the patient location on the GCS map
   - Send a `PatientLocation` command via XBee to the Pi 5

This last step is important because the Pi 5 autonomy engine needs the target coordinates for mission state updates. The `PatientLocation` command (Command ID 5) is already defined in the `gcs-packet` library — it just needs to be called when a new target comes in.

### Pseudocode (~20 lines)

```python
import requests
import time
import threading

_last_target_ts = 0

def poll_kraken_target():
    global _last_target_ts
    while True:
        try:
            resp = requests.get("http://localhost:5050/api/target", timeout=1)
            data = resp.json()
            if data.get("timestamp") and data["timestamp"] > _last_target_ts:
                _last_target_ts = data["timestamp"]

                # 1. Display on GCS map
                update_patient_marker(data["lat"], data["lon"])

                # 2. Relay to Pi 5 via XBee
                from Command.PatientLocation import PatientLocation
                cmd = PatientLocation((data["lat"], data["lon"]))
                SendCommand(cmd, Vehicle.MRA)

                print(f"Patient location received: {data['lat']}, {data['lon']}")
        except Exception:
            pass
        time.sleep(2)

# Start polling in background thread
threading.Thread(target=poll_kraken_target, daemon=True).start()
```

The `PatientLocation` class and `SendCommand` function already exist in the `gcs-infrastructure` library, so there is no new packet format to define.

---

## Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    GCS LAPTOP (Ground)                       │
│                                                              │
│  ┌──────────────────────┐    GET /api/target   ┌──────────┐ │
│  │  Kraken Triangulator │ ──────────────────── │   GCS    │ │
│  │   (localhost:5050)   │   {lat, lon, ...}    │Dashboard │ │
│  │                      │                      │          │ │
│  │  [MRA Operator]      │                      │ [GCS Op] │ │
│  └──────────────────────┘                      └────┬─────┘ │
│                                                     │       │
└─────────────────────────────────────────────────────│───────┘
                                                      │
                                          PatientLocation
                                          XBee Command (ID 5)
                                                      │
                                              ┌───────▼───────┐
                                              │   XBee XR 900 │
                                              │   (900 MHz)   │
                                              └───────┬───────┘
                                                      │
                                              ┌───────▼───────┐
                                              │  Raspberry Pi 5│
                                              │ (Autonomy Eng.)│
                                              └───────────────┘
```

---

## Demo Day Operations

On demo day, we envision **two operators working cooperatively** at the GCS station:

| Operator | Role | Responsibilities |
|---|---|---|
| **GCS Operator** | Runs the GCS Dashboard | Monitors vehicle telemetry, handles commands (E-stop, etc.), confirms patient location on map |
| **Kraken Operator** (MRA) | Runs the Kraken Triangulator | Sets up spatial filters, adjusts signal processing settings, monitors bearing data, clicks TRANSMIT when estimate is ready |

MRA Electrical & Software operators will be **present at the GCS station** to provide full operational guidance on the Kraken Triangulator app. The GCS team does not need to learn how to operate it — the GCS Dashboard only needs to read the target coordinates from the local API and display/relay them as described above.

---

## Summary of Action Items

| Owner | Task | Effort |
|---|---|---|
| **GCS Team** | Add polling of `GET localhost:5050/api/target` to GCS Dashboard | ~20 lines |
| **GCS Team** | Display patient location on GCS map when target received | Depends on existing map UI |
| **GCS Team** | Send `PatientLocation` XBee command to Pi 5 when target received | ~3 lines (already in library) |
| **MRA Team** | Deliver `KrakenTriangulator.exe` bundled installer | In progress |
| **MRA Team** | Provide operators on demo day for Kraken app | Confirmed |

---

## Questions / Joint Testing

We are happy to set up a joint integration test session whenever your team is ready. We can run both apps side-by-side and verify the full pipeline end-to-end:

```
Kraken Triangulator → GCS Dashboard → XBee → Pi 5
```

Reach out to MRA Electrical & Software to schedule a time.
