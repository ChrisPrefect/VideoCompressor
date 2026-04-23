# AGENTS.md

## Projektpfade

- Workspace-Ordner: `/Users/Chris/Developer/VideoCompressor`
- Git-/Xcode-Projektroot: `/Users/Chris/Developer/VideoCompressor/VideoCompressor`
- Xcode-Projekt: `/Users/Chris/Developer/VideoCompressor/VideoCompressor/VideoCompressor.xcodeproj`
- Haupt-App-Quellen: `VideoCompressor/`
- Share-Extension-Quellen: `VideoShrinkShare/`
- Gemeinsamer Core: `VideoShrinkCore/`

## Build

Die aktive `xcode-select`-Toolchain kann auf CommandLineTools zeigen. Für Builds direkt Xcode setzen:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project VideoCompressor.xcodeproj -target VideoCompressor -configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
```

Bekannte Projektstruktur:

- Targets: `VideoCompressor`, `VideoShrinkShare`
- Geteiltes Scheme: `VideoShrinkShare`
- Der App-Target `VideoCompressor` baut die Share-Extension als Dependency mit.

`xcodebuild` schreibt in den getrackten lokalen `build/`-Ordner. Nach reinen Verifikationsbuilds Build-Artefakte nicht als Codeänderung behandeln; bei Bedarf nur diese Artefakte aus dem Status entfernen.

## Codec-Entscheidung

Videoexport ist absichtlich HEVC/H.265-only. Keine Codec-Settings, keine Codec-Anzeige und kein H.264-Fallback einführen. Der Writer setzt den Exportcodec direkt in `VideoShrinkCore/Services/Transcoding/ReaderWriterTranscoder.swift`.
