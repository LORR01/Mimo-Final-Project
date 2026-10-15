# Canva asset provenance

Design reviewed: https://canva.link/x5i3plrq8qpf9js

All 21 pages were opened and visually inspected on 14 October 2026 (Asia/Bangkok).

The current header uses `room-header-original.png`, a 1600 × 900 background exported from the visible image on Canva page 5. Its Canva media identity is `91c5f1ee-ddfc-4c3b-85b4-8e13a5bb57da`. This is the prepared room background, without UI baked in. The earlier square `room-clean.webp` is retained but no longer used.

Revision assets were downloaded from the original rendered Canva elements, not cropped from screenshots:

- `mimo-peeking-original.png`: 544 × 800, Canva page 5, Lined Doodle Speechless Fox Emote. CSS crops the body at the header edge.
- `mimo-crying-original.png`: 500 × 800, Canva page 11, Lined Doodle Crying Fox Emote. CSS crops the body at the card edge.
- `profile-original.png`, `settings-original.png`, `bell-original.png`: original header icon elements.
- `computer-original.png`: original Hand Drawn Desktop Computer Illustration, 200 × 172.
- `mimo-shy-original.png`, `chat-original.png`, `wifi-original.png`, `devices-original.png`, `face-original.png`: original Canva page 10 elements, composed in HTML/CSS instead of scaling a cropped screenshot of the entire card.

No replacement illustrations or mascot SVGs were drawn. Other inherited assets are retained for reference.

The font export attempt through pageAssets failed in the first revision. This revision successfully downloaded the observed font URLs directly from font-public.canva.com and stores the files locally:

- `../fonts/Poppins-Regular.woff2`: family YAFdJjbTu24, Regular.
- `../fonts/Poppins-Bold.woff2`: family YAFdJjbTu24, Bold.
- `../fonts/BinateDisplay-Bold.woff2`: family YAFcfxF61Ps, Bold.

Visible Canva text styles confirmed Poppins 400/700 for greeting and clipboard headings, and Binate Display 700 for metric numbers. Chrome tests confirm both families load from the local files.

## Flutter migration (15 October 2026)

Image files were copied unchanged to assets/art. Poppins WOFF2 source files were converted to TTF without changing outlines for native Flutter support; their metadata identifies SIL OFL. The Poppins OFL is included in assets/fonts.

Binate Display was NOT included in the Flutter repository: embedded metadata identifies Monotype software and restricts redistribution. Metrics use Lilita One (SIL OFL) from https://github.com/google/fonts/tree/main/ofl/lilitaone, bundled as the MimoDisplay family. This is a deliberate typography difference for the GitHub-oriented port, not an assertion of an equivalent Binate license.

Noto Sans Thai variable TTF is from https://github.com/google/fonts/tree/main/ofl/notosansthai, used as a bundled fallback. Its OFL is included. All font license files are in assets/fonts.

The historical font paths above refer to the original HTML prototype, not Flutter pubspec assets. Canva artwork remains user-supplied reference material; this provenance file does not grant an independent public redistribution license for that artwork. No blanket license has been invented for third-party assets.

Launcher update 2026-10-16: assets/branding/mimo-launcher.png is an imagegen-generated Mimo mascot/monitor icon based on existing mascot artwork, selected by the user (round orange glasses, cheerful face, no smartphone). Android/iOS/web icon sizes are deterministic exports through flutter_launcher_icons. Prior artwork rights are not altered by this generation. Prompt and selection history: docs/design/README.md.
