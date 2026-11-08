# Duplicate Finder Roadmap

A macOS app that finds **exact** duplicate files in a prioritized list of folders and
moves the unwanted copies to the Trash, with undo.

## Steps

1. **Folder list** ✅
   Drag in folders or add them with the picker, reorder by priority, persist them as
   security-scoped bookmarks.
2. **Scanner** (in progress)
   Walk the folders, group by size, then a prefix hash, then a full SHA-256. Progress and
   cancel. Skip symlinks, packages, hidden and empty files; never count a file (or hard
   link) twice. Tested against `Fixtures/` via `swift test`.
3. **Results view**
   Duplicate groups showing the original and its duplicates with their locations.
   "Select all duplicates" auto-selects by priority. Per-group override of which file
   to keep. Show in Finder and Quick Look.
4. **Trash + undo**
   Move selected files to the Trash and keep a persistent log (original path to trash
   path) so a cleanup can be undone, even after a relaunch. Confirmation shows the count
   and space freed.
5. **Rules & settings**
   Full control over the keep-priority rules, plus exclusions.
6. **Polish**
   Performance on large folders, richer progress, keyboard shortcuts, accessibility.
7. **App Store prep**
   Sandbox audit, app icon, signing/notarization, privacy manifest, listing.

## TODO (Rules & settings)

- [ ] **Nested folders: most specific folder wins.** A file takes the priority of the
      deepest listed folder that contains it, regardless of list order. This lets a
      subfolder be promoted *or* demoted relative to its parent. (Until then the scanner
      assigns a file to the first listed folder it was found in.)
- [ ] **Row labels for nested folders.** E.g. "Inside Primary · overrides its priority"
      and "Contains Projects (listed separately)".
- [ ] **Configurable tiebreak rules** (order and on/off) for files within the same folder:
      1. shallower path, 2. cleaner name (no "copy", "(1)"), 3. oldest date,
      4. alphabetical path.
- [ ] **Exclusions:** hidden files, packages/bundles, minimum size, file extensions,
      specific subfolders.
