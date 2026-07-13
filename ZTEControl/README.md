# ZTE Control — MU5001 band / frequency control (iOS)

A native iOS app to control your **own** ZTE MU5001 5G router over its local
Wi-Fi admin interface. Built for the common problem of being in a
weak-coverage area where the router won't hold a connection: it lets you read
live signal quality and **lock the modem to a specific LTE / 5G band** (or
force a network mode) so it stays on the frequency that actually reaches you.

## How it works

The router exposes a local HTTP API (`http://192.168.0.1/goform/...`). The app:

1. **Logs in** with your admin password (ZTE's SHA-256 + `LD` nonce scheme).
2. **Reads status** — network type, active band, RSRP / RSRQ / SINR, cell ID.
3. **Locks bands / mode** — `SET_LOCK_BAND` for LTE + NR band bitmasks, and
   `SET_BEARER_PREFERENCE` for the network mode (4G only, 5G only, etc.),
   including the MD5 `AD` verification token when the firmware requires it.

All traffic stays on the local network; the password is stored in the
Keychain. Nothing is sent anywhere else.

## Using it

1. Connect your phone to the **ZTE MU5001 Wi-Fi**.
2. Open the app → **الإعدادات (Settings)** → enter the admin password
   (usually printed under the device). The host defaults to `192.168.0.1`.
3. **الإشارة (Signal)** shows live quality. Note the RSRP/SINR.
4. **النطاقات (Bands)**: pick a low band (5, 8, 20, 28 — they travel farther
   and penetrate walls better) and tap **تثبيت** (lock). Watch the signal tab;
   try bands until RSRP is highest (closer to 0 is better, e.g. −85 beats
   −105). Tap **إلغاء التثبيت** to return to automatic.

## Firmware differences

ZTE's exact command parameters vary by firmware. Every request and response is
recorded in **السجل (Diagnostics)**. If a lock is rejected, the raw response is
there — copy it and the command can be adjusted. That tab also has a raw
`goformId` sender for troubleshooting.

## Build

XcodeGen generates the project; Codemagic builds an unsigned IPA on push
(see `codemagic.yaml`). Locally: `cd ZTEControl && xcodegen generate`.
