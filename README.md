# Directory Size Tool

A small macOS app that helps you free up space on your drives. It scans a folder, shows how much disk space each subdirectory takes up, and lets you find and remove large directories and files.

## Features

- **Live scanning:** Pick a folder and the app scans it in the background. A tree table fills in as the scan runs, and you can stop it at any time.
- **Directory tree by size:** Every subdirectory shows the allocated size on disk of everything inside it. The largest come first by default, and you can sort by name or size.
- **File list:** Select a directory to see the files directly inside it, with their size and modification date. You can show or hide the list with **View › Show Files** (⇧⌘Y) or the toolbar button.
- **Finder integration:** Directories and files show their Finder icons. Use the context menu to **Show in Finder**, or double-click a file to open it in its default app.
- **Move to Trash:** Delete a directory or file from the context menu. You're asked to confirm first, the item goes to the Trash, and the sizes in the tree update right away.
- **Recent folders:** The main window remembers the last 10 folders you scanned, so you can scan one again with a double-click. Folders that aren't available, such as ones on a disconnected drive, are dimmed.

## Requirements

- macOS 27 or later
- Xcode 27 or later (to build from source)

## Building and Running

1. Open `DirSizeTool.xcodeproj` in Xcode.
2. Choose a **My Mac** run destination.
3. Build and run (⌘R).

## Usage

1. Click **Scan...** in the main window and choose a folder.
2. A *Directory Size* window opens and starts scanning. The title bar shows the directory being scanned. Click **Abort** to stop early.
3. Expand directories to find what takes up the most space. Select one to see its files.
4. Right-click a directory or file to show it in Finder or move it to the Trash.

Closing the main window quits the app and closes all scan windows.

## Notes

- The app is sandboxed. It can only read folders you've picked in the folder dialog. It keeps access to them with security-scoped bookmarks, so recent folders still work after a restart.
- Sizes are the space actually allocated on disk, not the logical file sizes.
- Symbolic links are not followed, and directories that can't be read are skipped.
