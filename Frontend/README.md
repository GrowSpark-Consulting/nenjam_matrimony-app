

Before writing any Flutter code:

1. Read the complete Stitch design.
2. Measure every spacing, radius, font size, elevation, and padding.
3. Create a component plan.
4. Then implement the UI.

If any information is missing from Stitch, ask me before making assumptions.

Do not hallucinate the design.








# nenjam_matrimony

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Development: running on a physical Android device (USB)

`Frontend/.env.dev` points `API_BASE_URL` at `http://127.0.0.1:3000` — no
Wi-Fi/LAN IP. To reach the local backend from a phone connected over USB,
run `scripts/dev/start_dev.ps1` from the repo root (or the **Start
Development** VS Code task / `F5` via `.vscode/launch.json`), which starts
the backend and sets up `adb reverse tcp:3000 tcp:3000` in one step.

See [`docs/development/android-usb-debugging.md`](../docs/development/android-usb-debugging.md)
for the full guide and manual-step fallback.
