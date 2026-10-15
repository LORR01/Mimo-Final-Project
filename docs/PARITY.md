Latest 1.1.0+3: [SHARING_AND_NOTIFICATIONS.md](SHARING_AND_NOTIFICATIONS.md) supersedes earlier file/clipboard and simultaneous keyboard limitations below.

# Flutter parity and architecture

Source reference: sibling `prototype made by gpt` at the time of migration (15 October 2026). It is a reference only: the Flutter application has no runtime dependency on that directory.

| Original web feature | Flutter implementation |
|---|---|
| Splash/login/loading | Native Tailscale app login handoff and Agent identity bootstrap; demo login only in explicit demo mode |
| Header/background/mascot | Original local assets, rounded clipping, Material popup overlay above mascot |
| Home telemetry + ORDER | Real metrics; first two per-device pinned Keys, tap ORDER for all four; authenticated Windows keyboard commands |
| Status daily graph | Tooltip/tap hour/minute readout, actual observed Agent uptime in live mode, per-ID fixtures in demo |
| Focus ring/secondary bars | CircularProgressIndicator/LinearProgressIndicator, original metric palette |
| Groups/shortcut deck/add forms | Native forms, edit/delete, pin limit four per device; simultaneous multi-touch PC keyboard, confirm after all contacts release |
| Device discovery | Real Agent/Tailscale CLI adapter by default; injectable fixtures in demo/tests |
| Alias/membership/removal | Typed stable IDs, rename independent of hostname, confirmation, fallback and empty states |
| Clipboard/favorites/categories | Dart collections + native Clipboard API and persisted favorites |
| File chooser/history | file_picker plugin, metadata-only mock transfers; active device target is captured at picker open and revalidated |
| Theme persistence/system mode | ThemeMode + SharedPreferencesAsync |
| Browser localStorage | Separate versioned Flutter preferences; HTML storage is not implicitly imported |
| CSS grid/background/fonts | CustomPainter and bundled fonts/artwork |
| JS render wrappers/event delegation | ChangeNotifier + AnimatedBuilder + Flutter callbacks |
| HTML QA reports | Flutter store/widget tests and exported widget PNGs |

Responsive widget composition is preserved rather than embedding a screenshot of a screen. Material icons and native controls differ slightly from Lucide/browser controls. Text rasterization, OS file dialogs and safe areas differ per target; no claim of pixel-perfect equivalence.

The developer-only web `?dev` drawer and HTML screenshot harness are replaced by Flutter tests and run/debug tooling. They are not application features. Browser-specific DOM IDs/JS compatibility aliases do not exist in Dart.

Live Tailscale discovery, Windows telemetry and authenticated keyboard commands now exist; see ANDROID_AND_COMMANDS.md for setup and limits. File transport and PC clipboard sync remain unimplemented. The companion Agent is Dart with a trusted Windows PowerShell collector and Windows SendInput FFI. There is no Node/Capacitor/WebView application runtime in this folder. Generated Flutter web index/bootstrap files are platform support, not a port of the original JS app.

Typography exception: the GitHub-oriented Flutter port bundles SIL-OFL Lilita One as MimoDisplay instead of the restricted Binate Display file. Poppins and Thai fallback are bundled with their licenses.
