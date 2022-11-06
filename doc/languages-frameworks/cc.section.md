# C/C++ {#sec-cc}

C and C++ packages can be built with [`stdenv.mkDerivation`](#chap-stdenv).
This is the most established and convenient method, and it is used throughout within Nixpkgs.

To build C or C++ projects with special requirements, the following tools are available.

## c2nix {#c2nix}

`c2nix` allows incremental builds of C or C++ projects with file granularity.

It works as follows:

1. Break down the given source tree into a compilation unit for each object file
1. Copy each source file to the Nix store separately
1. Build each object file in a separate derivation
1. Link object files

When source files change, since each is now a distinct dependency tracked by Nix, only affected derivations will be rebuilt.
The space and build time savings from this method come at the cost of increased evaluation time.

Producing a dependency graph of the source files can be done automatically, but requires Import From Derivation in that case.
This is because the analysis step happens in a derivation that produces a file from which to generate the derivations for each object file.

To avoid Import From Derivation, that file can be pre-generated and used like a regular build dependency.
Note though that it has to be re-generated each time the dependency structure changes.

### `pkgs.buildCPPBinary` {#c2nix-buildCPPBinary}

Build a C or C++ binary.

#### Arguments

`name` _(string)_

: Package name

`src` _(path)_

: Directory with source or header files, in the correct relative relationship.

  Any flags (from `*_flags` attributes) that refer to paths will be taken as relative to that directory.

  Only the following file types are considered:

  - `.c`
  - `.cpp`
  - `.cc`
  - `.h`
  - `.hpp`

`dependencyInfo` _(path)_

: Path to JSON file with dependency information, as produced by `c2nix.dependencyInfo`.

  This file is generated automatically using Import From Derivation if the argument is unset.
  To avoid Import From Derivation, pre-generate the file with `c2nix.dependencyInfo`.

    *Default:* `null`

`stdenv` _(attribute set)_

: The environment to use for the build.

    *Default:* `pkgs.stdenv`

`buildInputs` _(list of derivations)_

: Derivations that are dependencies of the build.
  Currently, these are used for both compile and link steps.

`make_redistributable` _(bool)_

: Build the package such that it will run on systems without Nix.

  This will set the [loader] to use the default [FHS] location and check that the required `glibc` version is not "to new".

    *Default:* `true`

[loader]: https://en.m.wikipedia.org/wiki/Dynamic_loading
[FHS]: https://en.m.wikipedia.org/wiki/Filesystem_Hierarchy_Standard

`clang_tidy_check` _(bool)_

: Run the `clang-tidy` linter on all source files alongside compilation.

    *Default:* `false`

`preprocessor_flags` _(list of strings)_

: Flags to pass to the C or C++ preprocessor.

`cflags` _(list of strings)_

: Flags to pass to the C compiler. Will only be used for files with the `.c` extension.

`cppflags` _(list of strings)_

: Flags to pass to the C++ compiler. Will be used for files other than with the `.c` extension.

`link_flags`

: Flags to pass to the linker.

`link_attributes`

: Additional attributes to pass to the underlying `stdenv.mkDerivation` when linking compiled modules.

`compile_attributes` _(attribute set)_

: Additional attributes to pass to the underlying `stdenv.mkDerivation` when compiling each module.

### `pkgs.buildCPPStaticLibrary` {#c2nix-buildCPPStaticLibrary}

Build a C or C++ statically linked library.

#### Arguments

`name` _(string)_

: Package name

`src` _(path)_

: Directory with source or header files, in the correct relative relationship.

  Any flags (from `*_flags` attributes) that refer to paths will be taken as relative to that directory.

  Only the following file types are considered:

  - `.c`
  - `.cpp`
  - `.cc`
  - `.h`
  - `.hpp`

`dependencyInfo` _(path)_

: Path to JSON file with dependency information, as produced by `c2nix.dependencyInfo`.

  This file is generated automatically using Import From Derivation if the argument is unset.
  To avoid Import From Derivation, pre-generate the file with `c2nix.dependencyInfo`.

    *Default:* `null`

`stdenv` _(attribute set)_

: The environment to use for the build.

    *Default:* `pkgs.stdenv`

`buildInputs` _(list of derivations)_

: Derivations that are dependencies of the build.
  Currently, these are used for both compile and link steps.

`clang_tidy_check` _(bool)_

: Run the `clang-tidy` linter on all source files alongside compilation.

    *Default:* `false`

`preprocessor_flags` _(list of strings)_

: Flags to pass to the C or C++ preprocessor.

`cflags` _(list of strings)_

: Flags to pass to the C compiler. Mutually exclusive with `cppflags`.

`cppflags` _(list of strings)_

: Flags to pass to the C++ compiler. Mutually exclusive with `cflags`.

`compile_attributes` _(attribute set)_

: Additional attributes to pass to the underlying `stdenv.mkDerivation` when compiling each module.

[version script]: https://www.gnu.org/software/gnulib/manual/html_node/LD-Version-Scripts.html

### `pkgs.buildCPPSharedLibrary` {#c2nix-buildCPPSharedLibrary}

Build a C or C++ shared library.

#### Arguments

`name` _(string)_

: Package name

`src` _(path)_

: Directory with source or header files, in the correct relative relationship.

  Any flags (from `*_flags` attributes) that refer to paths will be taken as relative to that directory.

  Only the following file types are considered:

  - `.c`
  - `.cpp`
  - `.cc`
  - `.h`
  - `.hpp`

`dependencyInfo` _(path)_

: Path to JSON file with dependency information, as produced by `c2nix.dependencyInfo`.

  This file is generated automatically using Import From Derivation if the argument is unset.
  To avoid Import From Derivation, pre-generate the file with `c2nix.dependencyInfo`.

    *Default:* `null`

`stdenv` _(attribute set)_

: The environment to use for the build.

    *Default:* `pkgs.stdenv`

`buildInputs` _(list of derivations)_

: Derivations that are dependencies of the build.
  Currently, these are used for both compile and link steps.

`make_redistributable` _(bool)_

: Build the package such that it will run on systems without Nix.

  This will set the [loader] to use the default [FHS] location and check that the required `glibc` version is not "to new".

    *Default:* `true`

[loader]: https://en.m.wikipedia.org/wiki/Dynamic_loading
[FHS]: https://en.m.wikipedia.org/wiki/Filesystem_Hierarchy_Standard

`symbol_leakage_check` _(bool)_

: Check that the final artifact does not publicly expose any C++ mangled symbol names.
  This is useful if you're trying to build a shared library written in C++ which exposes a pure C interface.

    *Default:* `true`

`clang_tidy_check` _(bool)_

: Run the `clang-tidy` linter on all source files alongside compilation.

    *Default:* `false`

`preprocessor_flags` _(list of strings)_

: Flags to pass to the C or C++ preprocessor.

`cflags` _(list of strings)_

: Flags to pass to the C compiler. Mutually exclusive with `cppflags`.

`cppflags` _(list of strings)_

: Flags to pass to the C++ compiler. Mutually exclusive with `cflags`.

`link_flags`

: Flags to pass to the linker.

`link_attributes`

: Additional attributes to pass to the underlying `stdenv.mkDerivation` when linking compiled modules.

`compile_attributes` _(attribute set)_

: Additional attributes to pass to the underlying `stdenv.mkDerivation` when compiling each module.

`version_script` _(path)_

: Path to [version script] for the linker to use

`separateDebugInfo` _(bool)_

: Build an additional `debug` derivation output. See [](#stdenv-separateDebugInfo).

    *Default:* `true`

[version script]: https://www.gnu.org/software/gnulib/manual/html_node/LD-Version-Scripts.html
