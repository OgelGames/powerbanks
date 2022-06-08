# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.4] - 2022-06-08

### Added

- Support for Technic Plus tool API.

### Fixed

- Replaced deprecated item metadata access.

## [1.0.3] - 2020-12-20

### Changed

- Losslessly optimized textures.

### Fixed

- Replaced deprecated `current_name` formspec element.

## [1.0.2] - 2020-10-12

### Added

- Translation support.
- French translation.

### Fixed

- Crash that can happen because of an engine bug in Minetest 5.3.0 and earlier.

## [1.0.1] - 2020-04-05

### Changed

- Switched to using `technic.pretty_num` instead of `technic.EU_string` for compatibility.
- Small changes to README to improve readability.
- Node now drops empty powerbank instead of nothing if it gets dug (though this should never happen normally).

### Fixed

- Duplication bug with nodes that take the wielded itemstack on right-click (such as `xdecor` item frames).

## 1.0.0 - 2019-12-14

- Initial versioned release.

[Unreleased]: https://github.com/OgelGames/powerbanks/compare/v1.0.4...HEAD
[1.0.3]: https://github.com/OgelGames/powerbanks/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/OgelGames/powerbanks/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/OgelGames/powerbanks/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/OgelGames/powerbanks/compare/v1.0.0...v1.0.1
