# GCS Dashboard Integration: KrakenSDR Triangulator App

**From:** MRA Electrical & Software  
**To:** GCS Subteam (Jason, Chief)  
**Date:** April 2026  
**Branch:** `MRA_Xbee`

---

## Overview

MRA Electrical & Software has developed a companion application called the **KrakenSDR Triangulator App**. It is a browser-based dashboard that processes RF bearing data collected by the KrakenSDR antenna array onboard the UAV and performs real-time geolocation (triangulation) to estimate where a target transmitter is located on the ground.

In short: the KrakenSDR hardware listens for a specific RF signal from the air, and the Triangulator app takes those bearing measurements and computes a **survivor location estimate** (latitude/longitude).

This document describes the integration work needed so the GCS Dashboard can receive and display these survivor location coordinates. It also explains the **two-phase loitering mission profile** that drives the full search-and-locate workflow.

---

## Where Does the Kraken Triangulator Run?

The Kraken Triangulator app is designed to **run on the same GCS laptop** as the GCS Dashboard. It runs as a local web server on `localhost:5050` and opens in a browser tab. On demo day, both the GCS Dashboard and the Kraken Triangulator will be running side-by-side on the GCS laptop.

We will be providing the app as a **bundled standalone executable** (`KrakenTriangulator.exe`). No Python installation or dependency setup is required. Your team just needs to double-click the `.exe` and it launches automatically. We will handle delivering the installer ahead of demo day.

---

## What MRA Needs from GCS (Two Things)

There are **two integration points** between the GCS Dashboard and the Kraken Triangulator:

### 1. Sensor Fusion Data Stream (Pi 5 to GCS Laptop to Kraken App)

The KrakenSDR antenna array on the UAV produces bearing data that is processed into sensor fusion records on the Pi 5. **This data must be streamed from the Pi 5 down to the GCS laptop via XBee** so the Kraken Triangulator app can receive it and perform triangulation.

The Pi 5 already transmits telemetry via XBee through `gcs_translator.py`. The sensor fusion data (bearing angles, GPS positions, signal metadata) must be included in this downlink so it arrives at the GCS laptop where the Kraken Triangulator is listening on `UDP port 5051`.

> **Without this data stream, the Kraken app has nothing to triangulate.** This is the input side of the pipeline.

### 2. Survivor Location Relay (Kraken App to GCS Dashboard to Pi 5)

Once the Kraken Triangulator computes a target location and the MRA operator clicks **TRANSMIT**, the app stores the coordinates locally. **The GCS Dashboard needs to pick up these coordinates** so it can:

1. Display the survivor location on the GCS map
2. Relay the coordinates to the Pi 5 (via XBee) so the autonomy engine receives the target and updates its mission state
3. **Relay the coordinates to other vehicles** (e.g., ERU) as needed

The Dashboard needs to **poll a local REST endpoint** that the Kraken Triangulator exposes. The operator will click TRANSMIT **twice** during a mission: once to refine the search orbit and once to report the final estimated survivor location (see Two-Phase Mission Profile below).

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
| `lat` | `float` or `null` | Estimated survivor latitude (WGS84). `null` if no target yet. |
| `lon` | `float` or `null` | Estimated survivor longitude (WGS84). `null` if no target yet. |
| `spread_m` | `float` | Spatial spread of the estimation cluster in meters. Lower = more confident. |
| `count` | `int` | Number of triangulation hits contributing to this estimate. |
| `timestamp` | `float` | Unix timestamp (seconds) of when the estimate was generated. |

### What the GCS Dashboard Needs to Do

1. **Poll** `GET http://localhost:5050/api/target` every ~2 seconds
2. **Check** if the `timestamp` field has changed since the last poll
3. **When a new target is detected:**
   - Display the survivor location on the GCS map
   - Send a `PatientLocation` command via XBee to the Pi 5

This last step is important because the Pi 5 autonomy engine needs the target coordinates for mission state updates. The `PatientLocation` command (Command ID 5) is already defined in the `gcs-packet` library. It just needs to be called when a new target comes in.

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
                update_survivor_marker(data["lat"], data["lon"])

                # 2. Relay to Pi 5 via XBee
                from Command.PatientLocation import PatientLocation
                cmd = PatientLocation((data["lat"], data["lon"]))
                SendCommand(cmd, Vehicle.MRA)

                print(f"Survivor location received: {data['lat']}, {data['lon']}")
        except Exception:
            pass
        time.sleep(2)

# Start polling in background thread
threading.Thread(target=poll_kraken_target, daemon=True).start()
```

The `PatientLocation` class and `SendCommand` function already exist in the `gcs-infrastructure` library, so there is no new packet format to define.

---

## Two-Phase Loitering Mission Profile

The MRA autonomy engine uses a **time-based, two-phase loiter strategy** to progressively refine the survivor location. The total search window is **8 minutes**. The Kraken Triangulator transmits target coordinates **twice** during a mission, each with a different purpose:

| Transmit | When | Purpose |
|---|---|---|
| **1st TRANSMIT** | ~4 minutes into the mission | **Refine the search orbit.** Provides a coarse estimated location so the autonomy engine can transition to a tighter orbit centered on the estimate. |
| **2nd TRANSMIT** | ~7 minutes into the mission | **Report the final estimated survivor location.** Provides a refined, high-confidence location that the GCS can relay to other vehicles (e.g., ERU). |

> **The mission is time-based.** The Kraken operator and/or GCS operator should keep a stopwatch running from mission start. The 1st transmit should occur at approximately the **4-minute mark** and the 2nd transmit at approximately the **7-minute mark** (leaving ~1 minute buffer before the 8-minute window closes).

### Phase 1: Wide Orbit, Coarse Fix (Minutes 0 to 4)

```
┌──────────────────────────────────────────────────────────────────────┐
│  T=0:00  MRA launches and autonomy engine begins Phase 1.          │
│          UAV flies a wide loitering orbit over the defined         │
│          search area provided by GCS.                              │
│                                                                    │
│  T=0:00 to 4:00  Pi 5 streams sensor fusion data (bearing angles,  │
│          GPS, signal metadata) via XBee down to the GCS laptop.    │
│          The Kraken Triangulator receives this stream and          │
│          continuously performs triangulation.                       │
│                                                                    │
│  T≈4:00  Kraken operator reviews the coarse estimate.              │
│          Clicks TRANSMIT (1st time).                               │
│          PURPOSE: Refine the loiter. Tell the autonomy engine      │
│          where to center the tighter Phase 2 orbit.                │
│                                                                    │
│  ──► GCS Dashboard picks up coarse fix via GET /api/target         │
│  ──► GCS Dashboard sends PatientLocation via XBee to Pi 5          │
│  ──► Autonomy engine updates mission state, transitions to         │
│      Phase 2 (tighter orbit at the coarse fix location)            │
└──────────────────────────────────────────────────────────────────────┘
```

### Phase 2: Tight Orbit, Final Fix (Minutes 4 to 7)

```
┌──────────────────────────────────────────────────────────────────────┐
│  T≈4:00  Autonomy engine commands MRA to fly to the coarse fix     │
│          location and begin a TIGHTER loitering orbit.             │
│                                                                    │
│  T=4:00 to 7:00  Pi 5 continues streaming sensor fusion data.      │
│          Kraken app now receives bearings from a closer vantage    │
│          point with better geometric diversity around the target.  │
│          Triangulation results improve (lower spread, more hits).  │
│                                                                    │
│  T≈7:00  Kraken operator reviews the refined estimate.             │
│          Clicks TRANSMIT (2nd time).                               │
│          PURPOSE: Report the FINAL estimated survivor location.    │
│          This is the coordinate that gets sent to other vehicles.  │
│                                                                    │
│  ──► GCS Dashboard picks up refined fix via GET /api/target        │
│  ──► GCS Dashboard sends PatientLocation via XBee to Pi 5          │
│  ──► GCS Dashboard relays survivor location to other vehicles      │
│  ──► Autonomy engine loiters at final estimated location           │
│                                                                    │
│  T=8:00  Search window closes.                                     │
└──────────────────────────────────────────────────────────────────────┘
```

### What This Means for GCS

The GCS Dashboard's polling logic does **not** need to distinguish between the 1st and 2nd transmit. The API contract is identical for both. Each time the Kraken operator clicks TRANSMIT, a new `timestamp` appears on `GET /api/target`, and the Dashboard relays it to the Pi 5 via `PatientLocation`. The autonomy engine on the Pi 5 handles the phase transitions internally.

The GCS Dashboard should expect to receive **exactly two survivor location updates** per mission:
1. **1st update (~4 min):** Coarse fix. Higher `spread_m`, fewer `count`. Refines the search orbit.
2. **2nd update (~7 min):** Final fix. Lower `spread_m`, higher `count`. This is the **official estimated survivor location** to relay to other vehicles.

---

## Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                      GCS LAPTOP (Ground)                            │
│                                                                     │
│  ┌───────────────────────┐   GET /api/target    ┌────────────────┐  │
│  │ Kraken Triangulator   │ ──────────────────── │  GCS Dashboard │  │
│  │  (localhost:5050)     │  {lat, lon, ...}     │                │  │
│  │                       │                      │  Displays the  │  │
│  │  Processes bearings,  │                      │  survivor fix  │  │
│  │  computes survivor   │                      │  on the map    │  │
│  │                       │                      │                │  │
│  │  [MRA Operator]       │                      │  [GCS Operator]│  │
│  └───────────────────────┘                      └───────┬────────┘  │
│           ▲                                             │           │
│           │ Bearing data arrives                        │           │
│           │ via XBee telemetry                  PatientLocation     │
│           │ (sensor fusion stream)              XBee Command (ID 5)│
│           │                                             │           │
└───────────│─────────────────────────────────────────────│───────────┘
            │                                             │
            │                                             ▼
    ┌───────┴─────────────────────────────────────────────────────┐
    │                     XBee XR 900 (900 MHz)                   │
    │              Bidirectional Air-Ground Link                   │
    └───────┬─────────────────────────────────────────────────────┘
            │                                             │
            │ Telemetry + bearing data (down)              │
            ▼                                             ▼
    ┌─────────────────────────────────────────────────────────────┐
    │                    Raspberry Pi 5 (UAV)                      │
    │                                                              │
    │  ┌──────────────────┐    ┌─────────────────────────────┐    │
    │  │ KrakenSDR        │    │ Autonomy Engine              │    │
    │  │ (bearing data)   │    │                              │    │
    │  │       │          │    │ Phase 1: Wide orbit (500m)   │    │
    │  │       ▼          │    │ Receives 1st PatientLocation │    │
    │  │ gcs_translator.py│    │       ──► transitions to     │    │
    │  │ (XBee telemetry) │    │ Phase 2: Tight orbit (200m)  │    │
    │  │                  │    │ Receives 2nd PatientLocation │    │
    │  │                  │    │       ──► loiters at final   │    │
    │  └──────────────────┘    └─────────────────────────────┘    │
    └─────────────────────────────────────────────────────────────┘
```

---

## Demo Day Operations

On demo day, we envision **two operators working cooperatively** at the GCS station across the full 8-minute search mission:

| Operator | Role | Responsibilities |
|---|---|---|
| **GCS Operator** | Runs the GCS Dashboard | Monitors vehicle telemetry, handles commands (E-stop, etc.), confirms survivor location updates on map, relays final survivor location to other vehicles |
| **Kraken Operator** (MRA) | Runs the Kraken Triangulator | Sets up spatial filters before flight, monitors incoming sensor fusion stream, reviews estimation quality, clicks TRANSMIT at ~4 min (coarse) and ~7 min (final), **keeps a stopwatch** |

### Demo Day Timeline (8-Minute Search Window)

| Time | Step | Action | Who |
|---|---|---|---|
| Pre-flight | 1 | Kraken operator launches `KrakenTriangulator.exe` and draws spatial filter over the defined search area | Kraken Op |
| Pre-flight | 2 | Verify sensor fusion data stream is flowing (Kraken app shows incoming bearing data) | Kraken Op |
| T=0:00 | 3 | MRA launches. **Start the stopwatch.** Autonomy engine begins Phase 1 wide orbit over search area | GCS Op / Kraken Op |
| T=0:00 to 4:00 | 4 | Pi 5 streams sensor fusion data via XBee. Kraken app accumulates bearings and triangulation results | Automatic |
| **T≈4:00** | **5** | **Kraken operator reviews coarse estimate and clicks TRANSMIT (1st time)**. Purpose: refine the search orbit. | **Kraken Op** |
| T≈4:00 | 6 | GCS Dashboard picks up coarse fix, displays on map, relays PatientLocation to Pi 5 via XBee | Automatic |
| T≈4:00 | 7 | Autonomy engine receives coarse fix, updates mission state, transitions to Phase 2 tight orbit | Automatic |
| T=4:00 to 7:00 | 8 | Pi 5 streams fresh sensor fusion data from tighter orbit. Kraken app computes refined estimate | Automatic |
| **T≈7:00** | **9** | **Kraken operator reviews refined estimate and clicks TRANSMIT (2nd time)**. Purpose: report **final estimated survivor location**. | **Kraken Op** |
| T≈7:00 | 10 | GCS Dashboard picks up final fix, updates map, relays to Pi 5 and **other vehicles (e.g., ERU)** | Automatic / GCS Op |
| T≈7:00 | 11 | Autonomy engine loiters at final estimated survivor location | Automatic |
| T=8:00 | 12 | Search window closes | All |

> **Stopwatch is critical.** The mission is time-boxed at 8 minutes. The Kraken operator needs to be aware of the 4 minute and 7 minute marks to ensure transmits happen on schedule. A simple phone stopwatch or timer is sufficient.

MRA Electrical & Software operators will be **present at the GCS station** to provide full operational guidance on the Kraken Triangulator app. The GCS team does not need to learn how to operate it. The GCS Dashboard only needs to read the target coordinates from the local API and display/relay them as described above.

---

## Summary of Action Items

| Owner | Task | Effort |
|---|---|---|
| **GCS Team** | Ensure Pi 5 sensor fusion data stream reaches GCS laptop via XBee (bearing data must arrive at Kraken app's UDP port 5051) | Verify existing pipeline |
| **GCS Team** | Add polling of `GET localhost:5050/api/target` to GCS Dashboard | ~20 lines |
| **GCS Team** | Display survivor location on GCS map when target received (expect 2 updates per mission) | Depends on existing map UI |
| **GCS Team** | Send `PatientLocation` XBee command to Pi 5 when target received | ~3 lines (already in library) |
| **GCS Team** | Relay 2nd (final) survivor location to other vehicles (e.g., ERU) | Depends on existing relay logic |
| **MRA Team** | Deliver `KrakenTriangulator.exe` bundled installer | In progress |
| **MRA Team** | Provide Kraken operator on demo day with stopwatch | Confirmed |

---

## Questions / Joint Testing

We are happy to set up a joint integration test session whenever your team is ready. We can run both apps side-by-side and verify the full pipeline end-to-end:

```
Kraken Triangulator > GCS Dashboard > XBee > Pi 5
```

Reach out to MRA Electrical & Software to schedule a time.
