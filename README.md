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

## Build

```bash
swift build
./build.sh
```

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
