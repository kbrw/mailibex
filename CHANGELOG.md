# Changelog

## [Unreleased]

## [0.2.1] (2024-03-12)

### Fixed

- Added erl_interface to extra_application to have it in the environment of the
  Iconv compiler task. (Breaking change from Elixir 1.15)

## [0.2.0]

### Changed

- Contribution from [@jschoch](https://github.com/github/jschoch): Escaping multipart boundary before interpolating it with the splitting regex.
- Removed a compilation flag in the NIF task (-lerl_inteface was removed in OTP23 following previous versions deprecations)
- Changed all deprecated function calls to suggested ones
- Cleaned up warnings to be compatible with elixir 1.15

## [0.1.6] (2020-12-15)

---

[unreleased]: https://github.com/kbrw/mailibex/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/kbrw/mailibex/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/kbrw/mailibex/compare/v0.1.6...v0.2.0
[0.1.6]: https://github.com/kbrw/mailibex/compare/fbf11cd...v0.1.6
