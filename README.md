# macmd

`macmd` is a fast two-pane file manager for macOS.

Version: `1.0.1`

## Current features

- two-pane commander layout
- keyboard-first navigation
- Finder-like file icons
- copy, rename, mkdir, trash, permanent delete
- ZIP creation and ZIP browsing
- favorites and locations in the top bar
- FTP, FTPS, and SFTP connections
- FileZilla XML import for saved connections
- open-in-Terminal support
- hidden files toggle and light/dark appearance modes

## Keyboard shortcuts

Use ⌘1 Terminal, ⌘2 ZIP, ⌘3 Open, ⌘4 Edit, ⌘5 Copy,
⌘6 Rename / Move, ⌘7 New Folder, ⌘8 Trash, ⌘9 Switch Pane, and ⌘0 Quit.
Tab still switches panes. Escape dismisses dialogs or requests cancellation
of a running operation. Function keys retain their standard macOS behavior.
The build does not install or modify Karabiner configuration.

The toolbar's `>>` / `<<` button points from the active pane to the other
pane. Click it to open the active pane's location in the other pane.

## Build

```bash
./build.sh
```

Requires Apple Command Line Tools. Full Xcode is not required: the script
compiles directly with `swiftc`, then signs and installs the app and creates
an installer in `dist/`.

The app bundle installs to:

- `~/Applications/macmd.app`

## Changelog

### 1.0.1

- added FTP, FTPS, and SFTP connection support
- added FileZilla XML import
- added a full connection manager for saved remote profiles
- fixed password import from FileZilla base64 exports
- fixed SFTP browsing and remote directory listing parsing
- switched to a single user-managed install in `~/Applications/macmd.app`

### 1.0

- initial public release of `macmd`

## Icon

The application icon uses the Total Commander floppy icon from
https://www.ghisler.com/favicon.ico (Ghisler Software GmbH), as requested.
