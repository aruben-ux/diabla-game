---
description: "Export the Godot .pck, upload to server, and restart. Use when the user says deploy, ship, push to server, or upload."
agent: "agent"
tools: ["execute"]
---

Run all three steps in sequence. Stop and report if any step fails.

1. **Export** the Linux .pck:
   ```
   & "C:\Users\adlyt\AppData\Local\Temp\8539eb99-1494-4559-b2e7-d37befe687f9_Godot_v4.6.1-stable_win64.exe.zip.7f9\Godot_v4.6.1-stable_win64.exe" --headless --export-pack "Linux" F:\Godot\diabla\diabla.pck
   ```

2. **Upload** to the Hetzner VPS:
   ```
   scp F:\Godot\diabla\diabla.pck root@5.78.206.166:/opt/diabla/diabla.pck
   ```

3. **Kill** any running game instance so new games use the updated pack:
   ```
   ssh root@5.78.206.166 "pkill -f 'godot-server.*diabla.pck' || true; echo 'Deploy complete — new games will use updated pack'"
   ```

After all steps succeed, confirm with a short summary.
