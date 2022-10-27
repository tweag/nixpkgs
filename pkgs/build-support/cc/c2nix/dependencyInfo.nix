{
  lib,
  jq,
  writeShellScriptBin,
  runCommandCC,
}:
/*
Produce a JSON file describing dependencies between C or C++ source files within the given `src` directory.

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


Calling `pkgs.c2nix.dependencyInfo` with the arguments `name` for the package name (here: `example`) and `src` for an absolute path to the source directory (here: `$PWD/source`) produces a JSON file as the build result.

```shellSession
nix-build <nixpkgs> -A pkgs.c2nix.dependencyInfo --argstr name example --argsr src $PWD/source
```

    /nix/store/y1m9xhvissgjvzkzjxmrqg7cmmpr5qbh-example-depinfo.json

```shellSession
cat /nix/store/y1m9xhvissgjvzkzjxmrqg7cmmpr5qbh-example-depinfo.json
```

    {
      "version": 2,
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

Example:

When the result of `dependencyInfo` is used directly in the Nix language, this constitutes "Import From Derivation":
<!-- TODO: link to an authoritative definition and explanation of IFD -->
the derivation producing the JSON file has to be built before evaluation can continue.

```nix
let
  pkgs = import <nixpkgs> {};
  dependencies = pkgs.c2nix.dependencyInfo { name = "example"; src = ./source; };
in
# Import From Derivation!
pkgs.lib.importJSON dependencies
```

    [ { dependencies = [ "lib/util.c" ]; name = "./lib/util.c"; } { dependencies = [ "lib/util.h" "main.cpp" ]; name = "./main.cpp"; } ]


TODO: Example like this:
nix-build -E 'dependencyInfo { ... }'
cp result dependency-info.json
nix-build -E 'buildCPP { dependencyInfo = ./dependency-info.json; }' # Not IFD anymore

*/
{
  # Package name
  name,
  # Source directory to analyse for dependencies
  src,
  # Flags to pass to the analysing compiler
  #
  # Type:
  #   [String]
  compilerFlags ? [],
  # File extensions to recognise as C files
  cExtensions ? ["c"],
  # File extensions to recognise as C++ files
  cppExtensions ? ["cpp" "cc"],
}:
assert (
  let
    intersection = lib.intersectLists cExtensions cppExtensions;
  in
    lib.assertMsg (intersection == []) "c2nix.dependencyInfo: File extensions ${lib.head intersection} cannot be in both `cExtensions` and `cppExtensions`."
);
# TODO: Detect extra files in src that aren't a dependency of any module? These aren't too surprising (e.g. an include directory for a
# library that this program only uses part of) so I'm not sure it's worth it.
  let
    processFile = writeShellScriptBin "process" ''
      set -euo pipefail

      result_dir=$1
      shift
      source_file=$1
      shift

      # Remove longest prefix matching "*.", resulting in everything after the
      # last dot
      extension=''${source_file##*.}

      case "$extension" in
      ${lib.concatMapStringsSep " | " lib.escapeShellArg cExtensions})
        COMPILER=$CC
        ;;
      ${lib.concatMapStringsSep " | " lib.escapeShellArg cppExtensions})
        COMPILER=$CXX
        ;;
      *)
        echo "Skipping non-source file $source_file" >&2
        exit 0
      esac

      mkdir -p "$(dirname "$result_dir/$source_file")"

      echo "Determining file dependencies of $source_file with $COMPILER" >&2

      # TODO: Idea: Don't use -MM, but -M, such that dependencies on /nix/store
      # libraries are shown, then make sure to have these libraries as a build
      # input for the files that require them. This way, when those libraries
      # change, only part of the files need to be recompiled.
      # Maybe how to:
      # - Output all store paths in a separate attribute
      # - Use builtins.storePath to attach the corresponding string context
      # - Make the paths a `buildInput` for the individual modules compilation
      # Problem: This doesn't work, because we can't rely on these store paths
      # existing, and we shouldn't write store paths to a JSON file because it
      # couldn't be committed to nixpkgs.

      # -M to output a Make rule for the file's dependencies
      # -MM to exclude system libraries, limits it to only the projects files.
      # -MT to pecify the Make rule target string. Let it be `fixed` because we don't need to know it.
      $COMPILER -MM -MT fixed "$source_file" ${lib.escapeShellArgs compilerFlags} \
        | # Unescape Make escapings \
        sed -z -f "$sedScriptPath" \
        | # Remove the first line containing "fixed:" \
        tail -n+2 \
        | # Sort and remove duplicates, which GCC apparently produces \
        sort -u \
        | # Turn lines into a JSON array \
        jq --raw-input -s --arg path "$source_file" '{ name: $path, dependencies: rtrimstr("\n") | split("\n") }' \
        > "$result_dir"/"$source_file.json"
    '';
  in
    # Dependency information - built at instantiation time!
    runCommandCC "${name}-depinfo.json" {
      nativeBuildInputs = [
        jq
        processFile
      ];

      passAsFile = ["sedScript"];

      # Undo Make rule escaping for a single rule, output all dependencies on a single line
      sedScript = ''
        # Make wraps lines with "\", adding extra spaces around it, separating entries
        s/ \\\n /\n/g
        # On smaller lines, entries are separated by " ", make those newlines too
        s/ /\n/g
        # But now we also replaced "\ " with newlines, which Make uses to escape " ", so undo those!
        s/\\\n/ /g
        # `make` escapes "#" with "\#"
        s/\\#/#/g
        # And "%" with "%%"
        s/%%/%/g
        # Similarly "$" with "$$"
        s/\$\$/$/g
      '';
    } ''
      results=$(mktemp -d)

      cd ${src}

      # Recursively find all files and process them in parallel using the process script
      find -L . -type f -print0 \
        | xargs -0 -L1 -P "$NIX_BUILD_CORES" process "$results"

      # Combine all resulting JSON files into a single one
      find "$results" -type f -print0 \
        | xargs -0 cat \
        | jq --slurp '.' > $out
    ''


