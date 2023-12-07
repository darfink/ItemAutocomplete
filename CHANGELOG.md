# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[unreleased]: https://github.com/darfink/ItemAutocomplete/compare/v2.0.5...HEAD
[2.0.5]: https://github.com/darfink/ItemAutocomplete/compare/v2.0.4...v2.0.5
[2.0.4]: https://github.com/darfink/ItemAutocomplete/compare/v2.0.3...v2.0.4
[2.0.3]: https://github.com/darfink/ItemAutocomplete/compare/v2.0.2...v2.0.3
[2.0.2]: https://github.com/darfink/ItemAutocomplete/compare/v2.0.1...v2.0.2
