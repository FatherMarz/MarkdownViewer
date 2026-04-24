# MarkdownViewer

A simple native macOS app for viewing and editing Markdown files. Opens `.md` files with a live rendered preview, built with SwiftUI + WebKit.

<img src="https://img.shields.io/badge/macOS-13%2B-blue" alt="macOS 13+"> <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift 5.9">

## Features

- **Three view modes**: Preview, Edit, or Split (edit + preview side by side)
- **Live rendering** via [marked.js](https://marked.js.org/) with GitHub-Flavored Markdown
- **Syntax highlighting** in code blocks via [highlight.js](https://highlightjs.org/)
- **Synchronized scrolling** in split mode
- **Custom find + replace** with Aa / W / .* toggles (case, whole word, regex) — highlights matches in both panes simultaneously
- **Native editor** — NSTextView with New York serif 15pt, generous line height, undo, spell check, find bar
- **Right-snap window** — opens at full height on the right half of the screen
- **Tabbed windows** — additional files open as tabs in the existing window
- **Auto light/dark theme** — follows system appearance
- **Default `.md` handler** — double-click any Markdown file in Finder to open here

## Build

Requires Xcode Command Line Tools.

```bash
./build.sh
```

Produces `build/MarkdownViewer.app`.

## Install

```bash
./install.sh
```

This copies the app to `/Applications`, registers it with Launch Services, and sets it as the default handler for `.md` / `.markdown` files.

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘F | Find |
| ⌥⌘F | Find and Replace |
| ⌘G / ⇧⌘G | Next / Previous match |
| Esc | Close find bar |
| ⌘S | Save |
| ⌘N | New document |
| ⌘O | Open |
| ⌘= / ⌘- | Zoom in / out (also: pinch on trackpad) |
| ⌘0 | Actual size |

## Project Layout

```
Sources/App.swift          # SwiftUI app, document, views, find bar
Resources/viewer.html      # WebKit preview template (marked.js, highlight.js)
Scripts/make-icon.swift    # Generates AppIcon.icns from SF Symbol
Info.plist                 # Bundle config, document types
build.sh                   # Compile + bundle + ad-hoc sign
install.sh                 # Install to /Applications + set as default
```

## Customization

- **Editor font**: edit `editorFont()` in `Sources/App.swift`
- **App icon**: edit the SF Symbol name in `Scripts/make-icon.swift`
- **Window width**: edit `snapToRight()` in `Sources/App.swift`

## License

MIT
