# Granular build-time sources

Support for file-level granular sources. Like `builtins.path` with filter support but at build-time.

## Use cases

- Build-time source filtering without duplicating files in the Nix store
- fetchIndividualFromGitHub?, useful for e.g. nerdfonts
- Patching can be very cheap, essentially [lazy trees](https://github.com/NixOS/nix/pull/6530) but at build time
- Patch a build without having to rebuild everything. `pkgs.individualFiles.patch`?
- Overriding with just `src = some/local/source` should not do a rebuild if the version matches, but also only minimal rebuilds if you change a file!

## `pkgs.granularSource.pin args`

Pins the files of a derivation by writing the hashes and types of all files to a JSON file in a derivation.
The resulting file is suitable to be passed to `pkgs.granularSource.create`, either as a derivation (which then leads to IFD, disallowed in nixpkgs), or as a file path when copied locally.

Arguments:
- `src`: The derivation whose files to pin.
- `hashAlgo`: The hashing algorithm to use, either `sha256` or `sha512`.

Returns a derivation for a JSON file with the following format:
```json
{
  "treeHashes": {
    "<someFile>": {
      "type": "file",
      "hash": "sha256-1rCVS1wK2D9lL22rbmdE6Wg2PwXRZxgFw8CVqnw3txM="
    },
    "<someDir>": {
      "type": "directory",
      "entries": {
        "<someNestedFile>": {
          "type": "file",
          "hash": "sha256-5rAeSHaY8qfcdxHvb9XWZCYX35hYBssalFbZiYjoJV0="
        }
      }
    },
    "<someSymlink>": {
      "type": "symlink",
      "target": "<somePath>"
    }
  }
}
```

The hashes use the [SRI hash](https://www.srihash.org/) format.

## `pkgs.granularSource.create args`

This function turns a derivation and associated granular file information generated using `pkgs.granularSource.pin` into a source value that can be used with the `pkgs.granularSource.lib` functions.

Implementation note: Just use `pkgs.granularSource.{_path,_pathSymlinks}` with a filter that always returns true, therefore returning the derivation files unchanged.

Arguments:
- `src`: Derivation whose files to use as the source
- `pinFile`: Path to file generated using `pkgs.granularSource.pin`.
  This file is imported at evaluation time, meaning that if this file is a derivation path, import-from-derivation is necessary.
  To prevent that, copy the pregenerated file to a project-local path.
- `symlink`: Whether files should be symlinked instead of copied, defaults to `false`.
  Enabling this requires less store space, but increases access time and might mess up some tools.

In nixpkgs this can be used for builders that can benefit from file-level build granularity, such as `c2nix.buildCPP` like this:

```
c2nix.buildCPP {
  src = granularSource.create {
    path = fetchFromGitHub { ... };
    pinFile = ./pinFile.json;
  };
}
```

Implementation note: `buildCPP` needs to use the `pkgs.granularSource.lib` functions with `src` to make use of the additional granularity.

## (internal) `pkgs.granularSource._path args`

Like [`builtins.path`](https://nixos.org/manual/nix/stable/language/builtins.html?highlight=builtins.path#builtins-path), but for derivation paths.
Only files not removed by the `filter` will have an influence on the output hash.
Falls back to `builtins.path` if `path` is not a derivation.

All arguments are optional except `path`:

- `path`: The underlying derivation. Needs to be a value returned from `pkgs.granularSource.create`.
- `name` (optional): The name of the derivation.
- `filter` (optional): A function of the type expected by [`builtins.filterSource`](https://nixos.org/manual/nix/stable/language/builtins.html?highlight=builtins.path#builtins-filterSource), with the same semantics.

The result is a derivation containing the files from `path` but filtered according to `filter`.

Note: The `recursive` and `sha256` argument of `builtins.path` are not implemented because they aren't needed for the `lib.sources` interface.

Implementation note: This function needs to implement validation of the hashes.

## (internal) `pkgs.granularSource._pathSymlinks args`

Like `pkgs.granularSource._path`, but it creates symlinks to the original source instead of copying the files.

## `pkgs.granularSource.lib`

Same functions as `lib.sources` but acting on granular build-time sources created using `pkgs.granularSource.create`.

Implementation note: Allow `lib.sources` to be generic over the `builtins.path` used.

## `lib.sources.{setSubpath,limitToSubpath}`

These functions are from my proposal in [the source combinators PR](https://github.com/NixOS/nixpkgs/pull/112083#pullrequestreview-1137855532), these would be useful to get individual files from the granular source.






