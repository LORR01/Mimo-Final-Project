# Mimo PC Agent (Windows)

1. Extract the entire zip. Keep `mimo-agent.exe`, `tool/` and `build/` together.
2. Install the official Tailscale Windows app and sign in to the same account used on your Android phone.
3. Open `Start Mimo Agent.cmd` and keep it running. This enables authenticated keyboard commands plus clipboard reading and file receiving (--enable-sharing). For telemetry only, open a terminal in this folder and run `mimo-agent.exe` without flags.
4. In a separate terminal, expose the Agent privately:

```powershell
tailscale serve --bg --https=8443 http://127.0.0.1:8765
```

If Tailscale requests account-side Serve/HTTPS enabling, follow its link. Do not replace other existing services or use Funnel. If port 8443 is already occupied, check `tailscale serve status` before changing anything.

On Android, install Mimo and the official Tailscale app. Connect Tailscale, then use Mimo's Tailscale login button. The APK built for the development PC contains that PC's gateway URL. Version 1.0.1+2 has no Agent URL form in the normal app flow. For a different first PC, rebuild the APK with -AgentUrl set to the URL reported by Serve. Additional PCs need their own Agent/Serve at the standard port 8443.

Keyboard commands affect the focused window on the PC. Only choose shortcuts you intend to send. Windows UAC, locked desktops and higher-integrity applications may reject input; this Agent does not bypass that protection. It accepts typed key chords, not shell commands. Enabling commands trusts the PC owner's authenticated Tailscale devices; it is not a separate per-Android-app authorization system.

NVIDIA load and temperature are read from the same GPU using its installed nvidia-smi. CPU temperature requires a real sensor provider such as LibreHardwareMonitor running with appropriate Windows administrator permission. Without a provider, Mimo shows no reading and explains setup; it never invents a temperature. Do not disable Windows security protections to force a sensor driver to work.

Private pairing fallback and observed usage are created in `.local/agent/` beside this executable. Keep this data private. No Tailscale API token is required. The zip contains no session, pairing code or personal history. The web assets are the Flutter release build; Clipboard retrieval and file receiving are enabled by --enable-sharing. Received files are stored in Downloads/Mimo. Clipboard history/attachments expire after30 minutes in memory; Windows clipboard and user-saved files are not deleted. See SHARING_AND_NOTIFICATIONS.md in the source repository.

If port 8765 is occupied, stop the existing Mimo Agent before starting a second copy. Close the console or press Ctrl+C to stop the Agent. Serve is a separate persistent Tailscale setting; stop only Mimo's proxy with `tailscale serve --https=8443 off` when appropriate.

Use the Agent packaged with the 1.0.1+2 login fix: older Agents reject Android peers when the installed CLI omits MachineAuthorized. APK-only replacement does not fix that backend bug.

Version 1.1.1+4: Favorites (including attachments) are permanent in .local/agent/favorites until unpinned or deleted. Unpin starts a fresh30-minute TTL. Back up this private folder if moving the Agent; never include it in a public package. The new APK requires this updated Agent for Favorite persistence.
