# Packages by name

The structure of this directory maps almost directly to top-level package attributes.
This is the recommended way to add new packages to Nixpkgs [when possible](#restrictions).

## The structure

The top-level package attribute `pkgs.${name}` may be defined in this directory by creating the file `pkgs/by-name/${shard}/${name}/package.nix`, where `shard = toLower (substring 0 2 name)` is the lowercased first two letters of `name`.
This file is automatically added as a top-level attribute defined as `pkgs.${name} = pkgs.callPackage pkgs/by-name/${shard}/${name}/package.nix { }`.

This `package.nix` file must define [a function](https://nixos.org/manual/nix/stable/language/constructs.html#functions) that defines a derivation for the package as follows:
- The argument is an attribute set pattern defining the [`.override` interface](https://nixos.org/manual/nixpkgs/stable/#sec-pkg-override) for the resulting package:
  - Attributes matching top-level `pkgs.*` attributes, such as `stdenv`, `lib` or `libpng`.
    By default the top-level `pkgs.*` attribute values of the same name are passed.
    This may be adjusted if necessary by redefining `pkgs.${name}` in [`pkgs/top-level/all-packages.nix`](../top-level/all-packages.nix) as `pkgs.${name} = pkgs.callPackage pkgs/by-name/${shard}/${name}/package.nix customArguments`.
    This is the only mechanism to get access to other derivations and package [builders](https://nixos.org/manual/nixpkgs/stable/#part-builders).
  - Attributes with an explicit default that don't have a matching top-level attribute, such as `enableGui ? false` or `enableClient ? true`.
    This allows exposing options to customise the package.
- The return value is [a derivation](https://nixos.org/manual/nixpkgs/stable/#function-library-lib.attrsets.isDerivation), such as a value returned from a [builder](https://nixos.org/manual/nixpkgs/stable/#part-builders) like `stdenv.mkDerivation` or `python3Packages.buildPythonApplication`.

### Restrictions

There's some limitations as to what can be defined using this structure, all of which are either not possible structurally or explicitly checked using CI, see [tests](#tests):
- Only top-level attributes.
  This excludes attributes from other package sets like `pkgs.pythonPackages.*`.
- Only [derivations](https://nixos.org/manual/nixpkgs/stable/#function-library-lib.attrsets.isDerivation)
  This excludes attributes like `pkgs.fetchFromGitHub`.
- Only values defined using `pkgs.callPackage`.
  This excludes attributes like `termdown = pkgs.python3Packages.callPackage`, or aliases like `python3 = pkgs.python310`.
- Furthermore, packages defined in this structure are required to not access any paths outside their own `pkgs/by-name/${shard}/${name}` directory.

## Example

The top-level package `pkgs.foo` may be declared in `pkgs/by-name/fo/foo/package.nix` with a Nix expression as follows:
```nix
{
  # These attributes have a matching `pkgs.*` attribute, which are passed by default
  lib,
  stdenv,
  libbar,
  # This attribute doesn't exist in `pkgs.*`, so we add an explicit default
  enableBar ? false,
}:
# This uses the standard environment derivation builder to return a derivation
stdenv.mkDerivation {
  pname = "foo";
  version = "0.1";
  buildInputs = lib.optional enableBar libbar;
  makeFlags = lib.optional enableBar "BAR=1";
  # ...
}
```

This automatically declares `pkgs.foo` as `pkgs.callPackage pkgs/by-name/fo/foo/package.nix { }`.

### Changing implicit attribute defaults

The above expression is called using these arguments by default:
```nix
{
  lib = pkgs.lib;
  stdenv = pkgs.stdenv;
  libbar = pkgs.libbar;
}
```

But if the package needs e.g. `pkgs.libbar_2` instead, you can change the default `libbar` attribute argument by adding a definition as follows to [`pkgs/top-level/all-packages.nix`](../top-level/all-packages.nix):
```nix
libfoo = callPackage ../by-name/li/libfoo/package.nix {
  libbar = libbar_2;
};
```

This allows maintaining the same `.override (prev: { libbar = ...; })` interface for package consumers.

## Tests

TODO
