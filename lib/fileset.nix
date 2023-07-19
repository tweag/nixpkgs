{ lib }:
let
  # TODO: Derive property tests from https://en.wikipedia.org/wiki/Algebra_of_sets

  inherit (builtins)
    isAttrs
    isList
    isPath
    isString
    pathExists
    readDir
    typeOf
    ;

  inherit (lib.attrsets)
    attrValues
    mapAttrs
    ;

  inherit (lib.filesystem)
    pathType
    ;

  inherit (lib.lists)
    all
    commonPrefix
    drop
    elemAt
    foldl'
    head
    imap0
    length
    range
    tail
    ;

  inherit (lib.path)
    append
    splitRoot
    hasPrefix
    removePrefix
    ;

  inherit (lib.path.subpath)
    components
    ;

  inherit (lib.sources)
    cleanSourceWith
    ;

  inherit (lib.strings)
    isCoercibleToString
    ;

  inherit (lib.path.subpath)
    join
    ;

  # Internal file set structure:
  #
  # # A set of files
  # <fileset> = {
  #   _type = "fileset";
  #
  #   # The base path, only files under this path can be represented
  #   # Always a directory
  #   _base = <path>;
  #
  #   # A tree representation of all included files
  #   _tree = <tree>;
  # };
  #
  # # A directory entry value
  # <tree> =
  #   # A nested directory
  #   <directory>
  #
  #   # A nested file
  #   | <file>
  #
  #   # A removed file or directory
  #   # This is represented like this instead of removing the entry from the attribute set because:
  #   # - It improves laziness
  #   # - It allows keeping the attribute set as a `builtins.readDir` cache
  #   | null
  #
  # # A directory
  # <directory> =
  #   # The inclusion state for every directory entry
  #   { <name> = <tree>; }
  #
  #   # All files in a directory, recursively.
  #   # Semantically this is equivalent to `builtins.readDir path`, but lazier, because
  #   # operations that don't require the entry listing can avoid it.
  #   # This string is chosen to be compatible with `builtins.readDir` for a simpler implementation
  #   "directory";
  #
  # # A file
  # <file> =
  #   # A file with this filetype
  #   # These strings match `builtins.readDir` for a simpler implementation
  #   "regular" | "symlink" | "unknown"

  # Create a fileset structure
  # Type: Path -> <tree> -> <fileset>
  _create = base: tree: {
    _type = "fileset";
    # All attributes are internal
    _base = base;
    _tree = tree;
    # Double __ to make it be evaluated and ordered first
    __noEval = throw ''
      Directly evaluating a file set is not supported. Use `lib.fileset.toSource` to turn it into a usable source instead.
    '';
  };

  # Create a file set from a path
  # Type: Path -> <fileset>
  _singleton = path:
    let
      type = pathType path;
    in
    if type == "directory" then
      _create path type
    else
      # Always coerce to a directory
      # If we don't do this we run into problems like:
      # - What should `toSource { base = ./default.nix; fileset = difference ./default.nix ./default.nix; }` do?
      #   - Importing an empty directory wouldn't make much sense because our `base` is a file
      #   - Neither can we create a store path containing nothing at all
      #   - The only option is to throw an error that `base` should be a directory
      # - Should `fileFilter (file: file.name == "default.nix") ./default.nix` run the predicate on the ./default.nix file?
      #   - If no, should the result include or exclude ./default.nix? In any case, it would be confusing and inconsistent
      #   - If yes, it needs to consider ./. to have influence the filesystem result, because file names are part of the parent directory, so filter would change the necessary base
      _create (dirOf path)
        (_nestTree
          (dirOf path)
          [ (baseNameOf path) ]
          type
        );

  # Coerce a value to a fileset
  # Type: String -> String -> Any -> <fileset>
  _coerce = function: context: value:
    if value._type or "" == "fileset" then
      value
    else if ! isPath value then
      if value._isLibCleanSourceWith or false then
        throw ''
          lib.fileset.${function}: Expected ${context} to be a path, but it's a value produced by `lib.sources` instead.
              Such a value is only supported when converted to a file set using `lib.fileset.fromSource`.''
      else if isCoercibleToString value then
        throw ''
          lib.fileset.${function}: Expected ${context} to be a path, but it's a string-coercible value instead, possibly a Nix store path.
              Such a value is not supported, `lib.fileset` only supports local file filtering.''
      else
        throw "lib.fileset.${function}: Expected ${context} to be a path, but got a ${typeOf value}."
    else if ! pathExists value then
      throw "lib.fileset.${function}: Expected ${context} \"${toString value}\" to be a path that exists, but it doesn't."
    else
      _singleton value;

  # Nest a tree under some further components
  # Type: Path -> [ String ] -> <tree> -> <tree>
  _nestTree = targetBase: extraComponents: tree:
    let
      recurse = index: focusPath:
        if index == length extraComponents then
          tree
        else
          let
            focusedName = elemAt extraComponents index;
          in
          mapAttrs
            (name: _:
              if name == focusedName then
                recurse (index + 1) (append focusPath name)
              else
                null
            )
            (readDir focusPath);
    in
    recurse 0 targetBase;

  # Expand "directory" to { <name> = <tree>; }
  # Type: Path -> <directory> -> { <name> = <tree>; }
  _directoryEntries = path: value:
    if isAttrs value then
      value
    else
      readDir path;

  # The following table is a bit complicated, but it nicely explains the
  # corresponding implementations, here's the legend:
  #
  # lhs\rhs: The values for the left hand side and right hand side arguments
  # null: null, an excluded file/directory
  # attrs: satisfies `isAttrs value`, an explicitly listed directory containing nested trees
  # dir: "directory", a recursively included directory
  # str: "regular", "symlink" or "unknown", a filetype string
  # rec: A result computed by recursing
  # -: Can't occur because one argument is a directory while the other is a file
  # <number>: Indicates that the result is computed by the branch with that number

  # The union of two <tree>'s
  # Type: <tree> -> <tree> -> <tree>
  #
  # lhs\rhs |   null  |   attrs |   dir |   str |
  # ------- | ------- | ------- | ----- | ----- |
  # null    | 2 null  | 2 attrs | 2 dir | 2 str |
  # attrs   | 3 attrs | 1 rec   | 2 dir |   -   |
  # dir     | 3 dir   | 3 dir   | 2 dir |   -   |
  # str     | 3 str   |   -     |   -   | 2 str |
  _unionTree = lhs: rhs:
    # Branch 1
    if isAttrs lhs && isAttrs rhs then
      mapAttrs (name: _unionTree lhs.${name}) rhs
    # Branch 2
    else if lhs == null || isString rhs then
      rhs
    # Branch 3
    else
      lhs;

  # Coerce and normalise the bases of multiple file set values passed to user-facing functions
  # Type: String -> [ { context :: String, value :: Any } ] -> { commonBase :: Path, trees :: [ <tree> ] }
  _normaliseBase = function: list:
    let
      processed = map ({ context, value }:
        let
          fileset = _coerce function context value;
          baseParts = splitRoot fileset._base;
        in {
          inherit fileset context;
          baseRoot = baseParts.root;
          baseComponents = components baseParts.subpath;
        }
      ) list;

      first = head processed;

      commonComponents = foldl' (components: el:
        if first.baseRoot != el.baseRoot then
          throw "lib.fileset.${function}: Expected file sets to have the same filesystem root, but ${first.context} has root \"${toString first.baseRoot}\" while ${el.context} has root \"${toString el.baseRoot}\"."
        else
          commonPrefix components el.baseComponents
      ) first.baseComponents (tail processed);

      commonBase =
        append first.baseRoot
          (join commonComponents);

      commonComponentsLength = length commonComponents;

      trees = map (value:
        _nestTree
          commonBase
          (drop commonComponentsLength value.baseComponents)
          value.fileset._tree
      ) processed;
    in
    {
      inherit commonBase trees;
    };

in {

  /*
  Import a file set into the Nix store, making it usable inside derivations.
  Return a source-like value that can be coerced to a Nix store path.

  This function takes an attribute set with these attributes as an argument:

  - `root` (required): The local path that should be the root of the result.
    `fileset` must not be influenceable by paths outside `root`, meaning `lib.fileset.getInfluenceBase fileset` must be under `root`.

    Warning: Setting `root` to `lib.fileset.getInfluenceBase fileset` directly would make the resulting Nix store path file structure dependent on how `fileset` is declared.
    This makes it non-trivial to predict where specific paths are located in the result.

  - `fileset` (required): The set of files to import into the Nix store.
    Use the other `lib.fileset` functions to define `fileset`.
    Only directories containing at least one file are included in the result, unless `extraExistingDirs` is used to ensure the existence of specific directories even without any files.

  - `extraExistingDirs` (optional, default `[]`): Additionally ensure the existence of these directory paths in the result, even they don't contain any files in `fileset`.

  Type:
    toSource :: {
      root :: Path,
      fileset :: FileSet,
      extraExistingDirs :: [ Path ] ? [ ],
    } -> SourceLike
  */
  toSource = { root, fileset, extraExistingDirs ? [ ] }:
    let
      maybeFileset = fileset;
    in
    let
      fileset = _coerce "toSource" "`fileset` attribute" maybeFileset;

      # Directories that recursively have no files in them will always be `null`
      sparseTree =
        let
          recurse = focusPath: tree:
            if tree == "directory" || isAttrs tree then
              let
                entries = _directoryEntries focusPath tree;
                sparseSubtrees = mapAttrs (name: recurse (append focusPath name)) entries;
                values = attrValues sparseSubtrees;
              in
              if all isNull values then
                null
              else if all isString values then
                "directory"
              else
                sparseSubtrees
            else
              tree;
          resultingTree = recurse fileset._base fileset._tree;
          # The fileset's _base might be below the root of the `toSource`, so we need to lift the tree up to `root`
          extraRootNesting = components (removePrefix root fileset._base);
        in _nestTree root extraRootNesting resultingTree;

      sparseExtendedTree =
        if ! isList extraExistingDirs then
          throw "lib.fileset.toSource: Expected the `extraExistingDirs` attribute to be a list, but it's a ${typeOf extraExistingDirs} instead."
        else
          lib.foldl' (tree: i:
            let
              dir = elemAt extraExistingDirs i;

              # We're slightly abusing the internal functions and structure to ensure that the extra directory is represented in the sparse tree.
              value = mapAttrs (name: value: null) (readDir dir);
              extraTree = _nestTree root (components (removePrefix root dir)) value;
              result = _unionTree tree extraTree;
            in
            if ! isPath dir then
              throw "lib.fileset.toSource: Expected all elements of the `extraExistingDirs` attribute to be paths, but element at index ${toString i} is a ${typeOf dir} instead."
            else if ! pathExists dir then
              throw "lib.fileset.toSource: Expected all elements of the `extraExistingDirs` attribute to be paths that exist, but the path at index ${toString i} \"${toString dir}\" does not."
            else if pathType dir != "directory" then
              throw "lib.fileset.toSource: Expected all elements of the `extraExistingDirs` attribute to be paths pointing to directories, but the path at index ${toString i} \"${toString dir}\" points to a file instead."
            else if ! hasPrefix root dir then
              throw "lib.fileset.toSource: Expected all elements of the `extraExistingDirs` attribute to be paths under the `root` attribute \"${toString root}\", but the path at index ${toString i} \"${toString dir}\" is not."
            else
              result
          ) sparseTree (range 0 (length extraExistingDirs - 1));

      rootComponentsLength = length (components (splitRoot root).subpath);

      # This function is called often for the filter, so it should be fast
      inSet = components:
        let
          recurse = index: localTree:
            if index == length components then
              localTree != null
            else if localTree ? ${elemAt components index} then
              recurse (index + 1) localTree.${elemAt components index}
            else
              localTree == "directory";
        in recurse rootComponentsLength sparseExtendedTree;

    in
    if ! isPath root then
      if root._isLibCleanSourceWith or false then
        throw ''
          lib.fileset.toSource: Expected attribute `root` to be a path, but it's a value produced by `lib.sources` instead.
              Such a value is only supported when converted to a file set using `lib.fileset.fromSource` and passed to the `fileset` attribute, where it may also be combined using other functions from `lib.fileset`.''
      else if isCoercibleToString root then
        throw ''
          lib.fileset.toSource: Expected attribute `root` to be a path, but it's a string-like value instead, possibly a Nix store path.
              Such a value is not supported, `lib.fileset` only supports local file filtering.''
      else
        throw "lib.fileset.toSource: Expected attribute `root` to be a path, but it's a ${typeOf root} instead."
    else if ! pathExists root then
      throw "lib.fileset.toSource: Expected attribute `root` \"${toString root}\" to be a path that exists, but it doesn't."
    else if pathType root != "directory" then
      throw "lib.fileset.toSource: Expected attribute `root` \"${toString root}\" to be a path pointing to a directory, but it's pointing to a file instead."
    else if ! hasPrefix root fileset._base then
      throw "lib.fileset.toSource: Expected attribute `fileset` to not be influenceable by any paths outside `root`, but `lib.fileset.getInfluenceBase fileset` \"${toString fileset._base}\" is outside `root`."
    else
      cleanSourceWith {
        name = "source";
        src = root;
        filter = pathString: _: inSet (components "./${pathString}");
      };

  /*
  The file set containing all files that are in either of two given file sets.
  See also [Union (set theory)](https://en.wikipedia.org/wiki/Union_(set_theory)).

  As with all the file set functions that accept file sets as arguments, they also accept paths by [coercing them to file sets](#sec-fileset-path-coercion).

  Type:
    union :: FileSet -> FileSet -> FileSet

  Example:
    # The single file `Makefile` and all files recursively in the `src` directory
    union ./Makefile ./src

    # Combine the above with all files recursively in the `tests` directory
    # For this the `unions` function would be better though
    union (union ./Makefile ./src) ./tests
  */
  union = lhs: rhs:
    let
      normalised = _normaliseBase "union" [
        {
          context = "first argument";
          value = lhs;
        }
        {
          context = "second argument";
          value = rhs;
        }
      ];
    in
    _create normalised.commonBase
      (_unionTree
        (elemAt normalised.trees 0)
        (elemAt normalised.trees 1)
      );

  /*
  The file set containing all files that are in any of the given file sets.
  See also [Union (set theory)](https://en.wikipedia.org/wiki/Union_(set_theory)).

  As with all the file set functions that accept file sets as arguments, they also accept paths by [coercing them to file sets](#sec-fileset-path-coercion).

  Type:
    unions :: [FileSet] -> FileSet

  Example:
    unions [
      # Include the single file `Makefile` in the current directory
      # This errors if the file doesn't exist
      ./Makefile

      # Also recursively include all files in the `src/code` directory
      # If this directory is empty this has no effect
      ./src/code

      # Also include the files `run.sh` and `unit.c` from the `tests` directory
      ./tests/run.sh
      ./tests/unit.c

      # Actually let's include the entire `tests` directory
      # The above lines can be removed without affecting the result
      ./tests

      # Include the `LICENSE` file from the parent directory
      ../LICENSE
    ]
  */
  unions = list:
    let
      annotated = imap0 (i: el: {
        context = "element ${toString i} of the argument";
        value = el;
      }) list;

      normalised = _normaliseBase "unions" annotated;

      tree = foldl' _unionTree (head normalised.trees) (tail normalised.trees);
    in
    if ! isList list then
      throw "lib.fileset.unions: Expected argument to be a list, but got a ${typeOf list}."
    else if list == [ ] then
      throw "lib.fileset.unions: Expected argument to be a list with at least one element, but it contains no elements."
    else
      _create normalised.commonBase tree;
}
