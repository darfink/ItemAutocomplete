# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.2.0] - 2026-11-08

### Added

- Compatibility with World of Warcraft: Forever (1.60.1, interface 16001)
- Compatibility with the retail client (12.1.5, interface 120105)
- Items can be searched whilst the item database updates, the menu displays
  the update's progress
- Add-on list icon

### Changed

- The item database is queried at the pace the server answers, rather than as
  fast as possible. Unanswered queries are retried, and the scan pauses in
  combat and resumes after a logout
- Queries the server never answers (e.g. Forever's hidden items) no longer
  hold up the scan. Such items, and items the server refuses, are queried
  again after a patch, daily on Forever, and weekly elsewhere
- After a patch, only items missing from the database are queried, rather than
  rebuilding it
- The item database is shared by every realm of a client, and stores names
  rather than links, which shrinks the saved variables considerably
- Searches reject non-matching items without decoding their names, and narrow
  down the previous results whilst typing
- Equally scored results favour the shorter name
- The menu opens below the chat edit box when there's no room above it, and
  stays on screen

### Fixed

- Keyboard navigation no longer triggers blocked action errors in combat on
  retail, where key propagation cannot be changed in combat
- Entering a selection without any results no longer errors
- An item of the Wrath item ranges was never scanned

## [2.1.0] - 2026-08-15

### Added

- Compatibility with the Burning Crusade Anniversary client (2.5.6)
- Item database covers the Burning Crusade item range

### Changed

- Item ID ranges are measured against the client's own item table rather than
  estimated, which adds roughly 3800 items on Burning Crusade and extends the
  Classic range from 24283 to 24358
- Season of Discovery covers every seasonal item the client knows of, rather
  than stopping at 217704

### Fixed

- Database updates no longer query the server for item IDs that do not exist.
  The existence check relied on `C_Item.DoesItemExistByID`, which answers true
  for every ID (WoWUIBugs #449), so roughly a third of each update was spent on
  items the client had never heard of

- Addon no longer errors on load now that `GetAddOnMetadata` and `GetItemInfo`
  only exist under `C_AddOns` and `C_Item`
- Chat integration works again on Classic Era 1.15.9, where the edit box
  handlers `ChatEdit_OnTextChanged` and `ChatEdit_OnEditFocusLost` were replaced
  by mixin methods
- Options panel registers with the Settings API, via updated Ace3 libraries

## [2.0.8] - 2025-11-07

### Fixed

- Compatibility with Classic Anniversary

## [2.0.7] - 2023-02-07

###

- New SoD items

## [2.0.6] - 2023-12-20

### Added

- New SoD items

## [2.0.5] - 2023-12-07

### Added

- Compatibility with SoD
- Compatibility with WOTLK
- Added new WOTLK items

## [2.0.4] - 2021-11-30

### Added

- Compatibility with SoM

### Fixed

- Backdrop error introduced by latest classic version

## [2.0.3] - 2021-09-05

### Added

- Added new BCC items

## [2.0.2] - 2021-06-14

### Added

- Added configurable option for items searched per frame.
- Added configurable option for number of items displayed.
- Added filter to remove unused ("UNUSED") developer items.
- Added filter to remove placeholder ("PH") developer items.

### Fixed

- Fixed configuration page not working on BCC.
- Prevented item queries from running when updating database.

### Changed

- Updated dependency versions.
- Improved item query implementation, resulting in 3x faster results.
- Changed default no. of items searched/frame from 1500 -> 2000.

[unreleased]: https://github.com/darfink/ItemAutocomplete/compare/v2.2.0...HEAD
[2.2.0]: https://github.com/darfink/ItemAutocomplete/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/darfink/ItemAutocomplete/compare/v2.0.8...v2.1.0
[2.0.8]: https://github.com/darfink/ItemAutocomplete/compare/v2.0.7...v2.0.8
[2.0.7]: https://github.com/darfink/ItemAutocomplete/compare/v2.0.6...v2.0.7
[2.0.6]: https://github.com/darfink/ItemAutocomplete/compare/v2.0.5...v2.0.6
[2.0.5]: https://github.com/darfink/ItemAutocomplete/compare/v2.0.4...v2.0.5
[2.0.4]: https://github.com/darfink/ItemAutocomplete/compare/v2.0.3...v2.0.4
[2.0.3]: https://github.com/darfink/ItemAutocomplete/compare/v2.0.2...v2.0.3
[2.0.2]: https://github.com/darfink/ItemAutocomplete/compare/v2.0.1...v2.0.2
