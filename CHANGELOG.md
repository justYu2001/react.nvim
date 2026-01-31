# Changelog

## [0.10.0](https://github.com/justYu2001/react.nvim/compare/v0.9.0...v0.10.0) (2026-01-31)


### Features

* generate event handler code action ([#28](https://github.com/justYu2001/react.nvim/issues/28)) ([fbd0e76](https://github.com/justYu2001/react.nvim/commit/fbd0e769ae6db35826094a9dc6204ce708d79874))
* infer event handler type from arrow functions ([#24](https://github.com/justYu2001/react.nvim/issues/24)) ([46c273d](https://github.com/justYu2001/react.nvim/commit/46c273d6f1e6759d083745d42c8938e9d4d6ffef))
* infer type from function variables for prop introduction code action ([#25](https://github.com/justYu2001/react.nvim/issues/25)) ([c9e7789](https://github.com/justYu2001/react.nvim/commit/c9e77897daa63d5a2753dba43fd3df865036b71d))


### Bug Fixes

* show prop rename menu only for rename code actoin ([#27](https://github.com/justYu2001/react.nvim/issues/27)) ([12f2146](https://github.com/justYu2001/react.nvim/commit/12f2146cab4181e87a2651d10e7a51c23da567d6))

## [0.9.0](https://github.com/justYu2001/react.nvim/compare/v0.8.0...v0.9.0) (2026-01-30)


### Features

* infer prop type from jsx context ([#21](https://github.com/justYu2001/react.nvim/issues/21)) ([db0999f](https://github.com/justYu2001/react.nvim/commit/db0999f5c5b26f182f3956450b289856ba45739c))


### Bug Fixes

* props menu only for React components ([#23](https://github.com/justYu2001/react.nvim/issues/23)) ([68c1c5b](https://github.com/justYu2001/react.nvim/commit/68c1c5b4e3d48e746375f027fac7a3f4e26f2f13))

## [0.8.0](https://github.com/justYu2001/react.nvim/compare/v0.7.0...v0.8.0) (2026-01-28)


### Features

* component usage rename (same file) ([#18](https://github.com/justYu2001/react.nvim/issues/18)) ([e3f9705](https://github.com/justYu2001/react.nvim/commit/e3f97057bce89306ea0618ba8a7efe3e74534010))
* cross-file bidirectional component rename ([#20](https://github.com/justYu2001/react.nvim/issues/20)) ([5c0a564](https://github.com/justYu2001/react.nvim/commit/5c0a5647a985a03163bcbf07151e4553827f7b7f))

## [0.7.0](https://github.com/justYu2001/react.nvim/compare/v0.6.0...v0.7.0) (2026-01-26)


### Features

* useCallback wrapper code action ([#16](https://github.com/justYu2001/react.nvim/issues/16)) ([59281fe](https://github.com/justYu2001/react.nvim/commit/59281fe01b2f77d84f2c763720075e74db18e50d))

## [0.6.0](https://github.com/justYu2001/react.nvim/compare/v0.5.0...v0.6.0) (2026-01-17)


### Features

* bidirectional component-props rename ([#14](https://github.com/justYu2001/react.nvim/issues/14)) ([f694354](https://github.com/justYu2001/react.nvim/commit/f69435496105914705a010a67a1bf535cc17938b))

## [0.5.0](https://github.com/justYu2001/react.nvim/compare/v0.4.0...v0.5.0) (2026-01-17)


### Features

* event handler props fallback to `() => void` ([#12](https://github.com/justYu2001/react.nvim/issues/12)) ([bdaee86](https://github.com/justYu2001/react.nvim/commit/bdaee86d4f6db9eb243e06a2870900bc5539567e))
* implement 'introduce prop' code action ([#10](https://github.com/justYu2001/react.nvim/issues/10)) ([34dd753](https://github.com/justYu2001/react.nvim/commit/34dd753b786e8e47069eb7aa8de1b1faf0519683))


### Bug Fixes

* add props skips helpers ([#13](https://github.com/justYu2001/react.nvim/issues/13)) ([48d59e0](https://github.com/justYu2001/react.nvim/commit/48d59e0378ef522a8faf2f2c765235c1b30b9972))

## [0.4.0](https://github.com/justYu2001/react.nvim/compare/v0.3.0...v0.4.0) (2026-01-16)


### Features

* add direct/alias choice menu for props rename ([#8](https://github.com/justYu2001/react.nvim/issues/8)) ([1a4aad2](https://github.com/justYu2001/react.nvim/commit/1a4aad2d88f5696abb1e4ad09e44d2e6e50deabb))

## [0.3.0](https://github.com/justYu2001/react.nvim/compare/v0.2.0...v0.3.0) (2026-01-13)


### Features

* **code-action:** add undefined variable to props ([#6](https://github.com/justYu2001/react.nvim/issues/6)) ([0881d5e](https://github.com/justYu2001/react.nvim/commit/0881d5e3811511289ce2d6dbeb56d5c708e31ce8))

## [0.2.0](https://github.com/justYu2001/react.nvim/compare/v0.1.0...v0.2.0) (2026-01-10)


### Features

* add JSX text objects it/at ([#3](https://github.com/justYu2001/react.nvim/issues/3)) ([1b8e30b](https://github.com/justYu2001/react.nvim/commit/1b8e30b882bed7850c6bde054add233908010907))


### Bug Fixes

* **textobjects:** ensure tree is parsed before finding JSX nodes ([#5](https://github.com/justYu2001/react.nvim/issues/5)) ([aecdc42](https://github.com/justYu2001/react.nvim/commit/aecdc42e009d080bd2dc5db4d1b7048168929a96))

## [0.1.0](https://github.com/justYu2001/react.nvim/compare/v0.0.0...v0.1.0) (2026-01-10)


### Features

* sync useState state and setter renaming ([#1](https://github.com/justYu2001/react.nvim/issues/1)) ([7e4f28e](https://github.com/justYu2001/react.nvim/commit/7e4f28e741555a1a3818d3d1bc8d916d7653715f))
