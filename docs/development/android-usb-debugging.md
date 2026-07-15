# Android USB Debugging with ADB Reverse

This is the standard way to run the Nenjam Matrimony Flutter app on a
**physical Android phone** against your **local backend** during development.

It replaces the old workflow of hardcoding your machine's current Wi-Fi LAN
IP (e.g. `192.168.168.109`) into `Frontend/.env.dev`.

## Why this is better than a Wi-Fi IP

| | Wi-Fi IP (old) | `adb reverse` (new) |
|---|---|---|
| Breaks when you change networks / DHCP renews | Yes — every time | No — always `127.0.0.1` |
| Breaks when phone and PC are on different Wi-Fi (e.g. laptop on VPN, phone on guest network) | Yes | No — doesn't use Wi-Fi at all |
| Requires editing `.env.dev` per developer / per network | Yes | No — same value for everyone |
| Needs firewall to allow inbound LAN connections to your backend port | Yes | No — traffic never leaves the USB cable |
| Failure mode when unreachable | **Silent hang** — the phone's TCP SYN to a stale/wrong IP is dropped with no response, so Dio just waits until its own `connectTimeout` fires (currently 15s in `AppConstants.apiConnectTimeout`) | Fails fast — if the reverse mapping isn't set up, the connection is refused immediately |

That last row matters: a stale Wi-Fi IP that the phone can no longer reach
doesn't look like a network error — it looks exactly like a hung backend,
because the OS never sends back a RST/ICMP-unreachable for a silently
unroutable address. `adb reverse` removes that whole class of bug, since
`127.0.0.1:3000` on the phone is always tunneled straight to `127.0.0.1:3000`
on your PC over the USB cable, regardless of what network either device is on.

## How it works

`adb reverse tcp:3000 tcp:3000` tells the Android device: "any connection
your apps make to `127.0.0.1:3000` should be forwarded, over USB, to
`127.0.0.1:3000` on the host computer running `adb`." From the app's point of
view it is talking to `localhost` — it has no idea the request is actually
being tunneled to your PC.

This is why `Frontend/.env.dev`'s `API_BASE_URL` is set to
`http://127.0.0.1:3000` — as long as the reverse mapping is active, that
address is always correct, on any network, for any developer's machine.

## One command (recommended)

`scripts/dev/start_dev.ps1` does everything below in one step: starts the
backend, waits for it to actually be listening on port 3000, checks the
device, runs `adb reverse`, and confirms the whole path works end-to-end
via `GET /health`. Run it directly, or via the **Start Development** VS
Code task (`.vscode/tasks.json`) — which is also wired up as the
`preLaunchTask` for the `Nenjam (USB / dev)` launch config, so `F5` alone
is enough.

To tear down: `scripts/dev/stop_dev.ps1` (removes the `tcp:3000` reverse
mapping and stops the backend process), or the **Stop Development** task.

The manual steps below are the fallback these scripts automate — useful to
understand what's happening, or to debug when the script itself fails.

## Prerequisites

- A physical Android phone with **Developer Options** and **USB debugging**
  enabled (Settings → About Phone → tap "Build Number" 7 times → Developer
  Options → enable "USB debugging").
- The phone connected to your PC via USB, with the "Allow USB debugging?"
  prompt accepted on the phone.
- `adb` installed and on your `PATH`. It ships with the Android SDK
  Platform-Tools, normally installed alongside Android Studio at:
  `%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe`
  If `adb` isn't recognized in your terminal, add that folder to your `PATH`.
- The Nenjam backend running locally on port `3000` (`pnpm start:dev` from
  `backend/`).

## Step-by-step

1. **Check the phone is detected:**

   ```
   adb devices
   ```

   You should see your device listed with state `device` (not `unauthorized`
   or `offline`). If it says `unauthorized`, check the phone screen for the
   USB debugging permission prompt.

2. **Set up the reverse mapping** (do this every time you reconnect the
   phone or restart `adb`):

   ```
   adb reverse tcp:3000 tcp:3000
   ```

   Or just run `scripts/dev/setup_android_usb.bat`, which does this for you
   with device/adb checks.

3. **Verify the mapping is active:**

   ```
   adb reverse --list
   ```

   Expected output: `<device-serial> tcp:3000 tcp:3000`

4. **Run the Flutter app** as usual (`flutter run`, or via your IDE). It
   will connect to `http://127.0.0.1:3000` per `Frontend/.env.dev`, which
   `adb reverse` tunnels to your backend.

## Verifying everything works

- `adb devices` — phone shows as `device`.
- `adb reverse --list` — shows `tcp:3000 tcp:3000` for your device.
- In the Flutter app, trigger any screen that calls the backend (e.g. sign
  in, or a registration step). It should respond immediately — no 15-second
  hang.
- Check the backend terminal — you should see the incoming request logged
  (route mapped, guard/controller logs, etc.) at the same moment you trigger
  the action in the app.
- From your PC: `curl http://127.0.0.1:3000/health` should return
  `{"status":"ok",...}` — this is what `start_dev.ps1` checks automatically.
- If you want to sanity check outside the app: `adb shell` into the device
  and run `curl http://127.0.0.1:3000/health` — you should get the same
  response (not a timeout), since the phone's shell is also subject to the
  reverse mapping.
- In debug builds, the app itself checks `/health` shortly after startup
  and shows a red "Backend unreachable" / "Backend unhealthy" banner if
  something's wrong, with a checklist and a Retry button (see
  `Frontend/lib/core/network/backend_connectivity_checker.dart`). Note it
  can't tell apart "backend not running" vs. "adb reverse missing" vs. "USB
  unplugged" — those look identical from the phone's side — so it lists all
  three.

## Removing the mapping

When you're done, or want to reset:

```
adb reverse --remove-all
```

Or run `scripts/dev/remove_android_usb.bat`.

## Common troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `adb: command not found` | Platform-tools not on `PATH` | Add `%LOCALAPPDATA%\Android\Sdk\platform-tools` to `PATH`, restart terminal |
| `adb devices` shows nothing | USB debugging not enabled, cable is charge-only, or drivers missing | Enable USB debugging, try a different (data-capable) cable/port, install OEM USB drivers |
| `adb devices` shows `unauthorized` | Phone hasn't approved the RSA key prompt yet | Look at the phone screen and tap "Allow"; if the prompt never appears, revoke USB debugging authorizations in Developer Options and reconnect |
| `adb devices` shows `offline` | Stale ADB server state | Run `adb kill-server` then `adb start-server`, reconnect |
| App still times out after `adb reverse` | Backend isn't actually running on port 3000, or the reverse mapping was cleared (e.g. phone was unplugged/replugged, `adb` server restarted) | Confirm backend is running (`pnpm start:dev`), re-run `adb reverse tcp:3000 tcp:3000` |
| `adb reverse --list` is empty after it worked before | Reconnecting the USB cable or restarting `adb` clears reverse mappings — they are **not** persistent | Re-run the setup script/command after every reconnect |
| Multiple devices connected, `adb reverse` fails with "more than one device" | `adb` needs a target when multiple devices/emulators are attached | `adb -s <device-serial> reverse tcp:3000 tcp:3000` (get the serial from `adb devices`) |

## Reference commands

```
adb devices                     # list connected devices and their state
adb reverse tcp:3000 tcp:3000   # forward phone's 127.0.0.1:3000 -> PC's 127.0.0.1:3000
adb reverse --list              # show active reverse mappings
adb reverse --remove-all        # clear all reverse mappings
```
