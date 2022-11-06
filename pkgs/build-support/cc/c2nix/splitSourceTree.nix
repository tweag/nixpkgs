{
  lib,
}:
/*
Split a source tree into a separate store object for each file.
Based on provided dependency information, output shell commands to link files which belong to one compilation unit from the store into the current directory.

Only those files captured by `dependencyInfo` will be copied to the store.

This can be used to enable file-granular rebuilds that leverage the Nix store's content hashing.

Example:

In the following directory `source`, the files `main.cpp` and `lib/util.c` both include `lib/util.h`.

```shellSession
tree source
```

    source
    ├── lib
    │   ├── util.c
    │   └── util.h
    └── main.cpp

Running `pkgs.c2nix.dependencyInfo` on that directory produces the following output:

```json
{
  "dependencies": {
    "./lib/util.c": [
      "lib/util.c"
    ],
    "./main.cpp": [
      "lib/util.h",
      "main.cpp"
    ]
  }
}
```

The output of `splitSourceTree` with these parameters will then be equivalent to:

```nix
{
  "./lib/util.c" = ''
    mkdir -p lib
    ln -s /nix/store/asdf...-lib-util.c lib/util.c
  '';

  "./main.cpp" = ''
    mkdir -p lib
    ln -s /nix/store/zxcv...-lib-util.h lib/util.h

    mkdir -p .
    ln -s /nix/store/qwer...-main.cpp main.cpp
  '';
}
```

The shell commands can be used to prepare the build for one compilation unit.

Example:

```nix
with import <nixpkgs> {};
let

  # Split the original source tree into separate files.
  files = c2nix.splitSourceTree {
    src = ./source;
    dependencyInfo = ./dependency-info.json;
  };

  # Produce a derivation for each compilation unit.
  compileFile = name: linkSourceFiles: stdenv.mkDerivation {
    inherit name;

    # Use the shell commands provided by `splitSourceTree` to symlink the
    # relevant source files for this compilation unit into the build directory.
    # No `src` attribute needed!
    unpackPhase = ''
      mkdir source
      cd source
      ${linkSourceFiles}
    '';

    # ...
  };
in lib.mapAttrs compileFile files
```
*/
{
  # Source tree to split into separate files in the Nix store
  src,

  # Path to JSON file with dependency information, in the format produced by `c2nix.dependencyInfo`.
  dependencyInfo,
}:
let
  # produce shell commands to symlink each of the `dependencies` of a source
  # `file` from their store path into their relative location in the current
  # directory.
  # as a side effect of evaluating this function, each of `dependencies` will
  # be separately copied to the store from their relative location in `root`.
  # this is what enables file-granular rebuilds.
  linkSourceFiles = root: _: dependencies:
    # compiling a file always requires at least itself
    assert lib.assertMsg (dependencies != []) "c2nix.splitSourceTree ${file}: no source dependencies given";
    lib.strings.concatMapStringsSep "\n" (dep:
      let
        dependencyFile = builtins.path {
          name = lib.strings.sanitizeDerivationName (baseNameOf dep);
          path = root + "/${dep}";
        };
      in ''
        mkdir -p "$(dirname ${lib.escapeShellArg dep})"
        ln -s ${dependencyFile} ${lib.escapeShellArg dep}
      ''
    ) dependencies;
in
lib.mapAttrs (linkSourceFiles src) (lib.importJSON dependencyInfo).dependencies
