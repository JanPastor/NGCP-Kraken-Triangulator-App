# GCS Dashboard Integration — KrakenSDR Triangulator App

**From:** MRA Electrical & Software  
**To:** GCS Subteam (Jason, Chief)  
**Date:** April 2026  
**Branch:** `MRA_Xbee`

---

## Overview

MRA Electrical & Software has developed a companion application called the **KrakenSDR Triangulator App**. It is a browser-based dashboard that processes RF bearing data collected by the KrakenSDR antenna array onboard the UAV and performs real-time geolocation (triangulation) to estimate where a target transmitter is located on the ground.

In short: the KrakenSDR hardware listens for a specific RF signal from the air, and the Triangulator app takes those bearing measurements and computes a **patient location estimate** (latitude/longitude).

This document describes the integration work needed so the GCS Dashboard can receive and display these patient location coordinates. It also explains the **two-phase loitering mission profile** that drives the full search-and-locate workflow.

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

## Two-Phase Loitering Mission Profile

The MRA autonomy engine uses a **two-phase loiter strategy** to progressively refine the patient location. The Kraken Triangulator transmits target coordinates **twice** during a mission — once per phase — and each transmission drives a mission state transition on the Pi 5.

### Phase 1 — Wide Orbit (Coarse Fix)

```
┌──────────────────────────────────────────────────────────────────────┐
│  UAV flies a wide loitering orbit (~500 m radius) over the         │
│  general search area. The KrakenSDR collects RF bearings from      │
│  multiple angles around the orbit.                                 │
│                                                                    │
│  The Kraken Triangulator processes these bearings and produces     │
│  a COARSE first-pass estimate of the patient location.             │
│                                                                    │
│  The Kraken operator reviews the estimate and clicks TRANSMIT.     │
│  ──► GCS Dashboard picks up the target via GET /api/target         │
│  ──► GCS Dashboard sends PatientLocation via XBee to Pi 5          │
│  ──► Autonomy engine receives the coarse fix and transitions       │
│      the mission state to PHASE 2                                  │
└──────────────────────────────────────────────────────────────────────┘
```

### Phase 2 — Tight Orbit (Refined Fix)

```
┌──────────────────────────────────────────────────────────────────────┐
│  The autonomy engine commands the UAV to fly to the coarse fix     │
│  location and begin a TIGHTER loitering orbit (~200 m radius).     │
│                                                                    │
│  The KrakenSDR continues collecting bearings, now from a closer    │
│  vantage point with better geometric diversity.                    │
│                                                                    │
│  The Kraken Triangulator receives this newer stream of sensor      │
│  fusion data and computes a REFINED second-pass estimate with      │
│  higher confidence (lower spread_m, higher count).                 │
│                                                                    │
│  The Kraken operator reviews and clicks TRANSMIT again.            │
│  ──► GCS Dashboard picks up the updated target                     │
│  ──► GCS Dashboard sends PatientLocation via XBee to Pi 5          │
│  ──► Autonomy engine receives the refined fix and transitions      │
│      to LOITER around the final estimated location                 │
└──────────────────────────────────────────────────────────────────────┘
```

### What This Means for GCS

The GCS Dashboard's polling logic does **not** need to distinguish between Phase 1 and Phase 2 — the API contract is identical for both transmissions. Each time the Kraken operator clicks TRANSMIT, a new `timestamp` appears on `GET /api/target`, and the Dashboard relays it to the Pi 5 via `PatientLocation`. The autonomy engine on the Pi 5 handles the phase transitions internally.

The GCS Dashboard should expect to receive **up to two patient location updates** per mission. The second update will generally have a lower `spread_m` value (tighter cluster, higher confidence) than the first.

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
│  │  Processes bearings,  │                      │  patient fix   │  │
│  │  computes patient fix │                      │  on the map    │  │
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

On demo day, we envision **two operators working cooperatively** at the GCS station across the full two-phase mission:

| Operator | Role | Responsibilities |
|---|---|---|
| **GCS Operator** | Runs the GCS Dashboard | Monitors vehicle telemetry, handles commands (E-stop, etc.), confirms patient location updates on map, monitors mission phase transitions |
| **Kraken Operator** (MRA) | Runs the Kraken Triangulator | Sets up spatial filters before flight, monitors incoming bearing data during both orbits, reviews estimation quality, clicks TRANSMIT at end of Phase 1 (coarse fix) and again at end of Phase 2 (refined fix) |

### Typical Demo Day Timeline

| Step | Action | Who |
|---|---|---|
| 1 | Kraken operator draws spatial filter over general search area | Kraken Op |
| 2 | UAV launches and autonomy engine begins Phase 1 wide orbit | Automatic |
| 3 | Kraken app accumulates bearings and triangulation results | Automatic |
| 4 | Kraken operator reviews Phase 1 estimate and clicks **TRANSMIT** | Kraken Op |
| 5 | GCS Dashboard picks up coarse fix, displays on map, relays to Pi 5 | GCS Op (automatic) |
| 6 | Autonomy engine transitions to Phase 2 tight orbit at coarse fix | Automatic |
| 7 | Kraken app accumulates refined bearings from closer orbit | Automatic |
| 8 | Kraken operator reviews Phase 2 estimate and clicks **TRANSMIT** | Kraken Op |
| 9 | GCS Dashboard picks up refined fix, updates map, relays to Pi 5 | GCS Op (automatic) |
| 10 | Autonomy engine loiters at final estimated patient location | Automatic |

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
