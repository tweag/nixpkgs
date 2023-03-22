let

  /*
  - Function for unioning filtered sources together together, either union or extend
  - Function for including exactly those files and directories you want
  - Function for finding files with extensions

  lib.sources.withExtension ./. ".hs"

  # recursively finds subpaths satisfying a condition
  lib.sources.find ./. ({ subpath, type, ... }: true)

  src = union ./. [
    (find ({ extension, ... }: extension == "hs" || extension == "c"))
    ./Makefile
    ./src/foo/bar
    ];

  Instead: What about just listing files?
  Have a function that recursively lists files from a root directory, and another function that converts the list to a filtered source
  But then we'd have to list the entire `.git` directory!
  What about first filtering out everything not necessary?

  src = lib.sources.fromFileList (lib.filesystems.listRecursively ./.)

  A structure that combines recursive listing and filtering

  # Guide to source filtering
  - Limit it to only what git knows of
  - Explicitly only include what you need to improve incrementality
  - If you need a set of files, use recursive listing filters
  - `union` is for `||`, `cleanSourceWith` is for `&&`

  Set of files!
  Plus for effiency: Entire directories




  */


  lib = import ./.;
  /*

  {
    path = <path>;
    type = <filetype>;
    # If type == "directory" and you want to pick individual files, if entries is not specified, all files are included
    (optional) entries.<name> = <self>;
  }

  */

  singleFile = filePath: {
    path = filePath;
    type = "regular";
  };

  recursiveDirectory = directoryPath: {
    path = directoryPath;
    type = "directory";
  };

  pathType = path:
    if dirOf path == path then "directory"
    else (builtins.readDir (dirOf path)).${baseNameOf path};

  singleton = path:
    # TODO: Do the paths need to exist? Kind of required for readDir, but not for source filtering
    assert builtins.pathExists path;
    {
      path = path;
      type = pathType path;
    };

  uproot = set:
  assert dirOf set.path != set.path;
  {
    path = dirOf set.path;
    type = "directory";
    entries.${baseNameOf set.path} = set;
  };

  uprootTo = root: set:
  if root == set.path then set
  else
    assert lib.path.hasPrefix root set.path;
    uprootTo root (uproot set);

  unionSameRoot = list:
    let first = lib.elemAt list 0; in
    assert lib.all (x: x.path == first.path) list;
    assert lib.all (x: x.type == first.type) list;
    {
      path = first.path;
      type = first.type;
    } // lib.optionalAttrs (first.type == "directory" && lib.all (x: x ? entries) list) {
      entries = lib.zipAttrsWith (name: x: unionSameRoot x) (map (x: x.entries) list);
    };


  tryDownroot = set:
    let
      entryName = lib.head (lib.attrNames set.entries);
      entryValue = set.entries.${entryName};
    in
    if set.type != "directory" then set
    else if ! set ? entries then set
    else if lib.length (lib.attrNames set.entries) > 1 then set
    else tryDownroot entryValue;

  intersectionSameRoot = list:
  let
    first = lib.elemAt list 0;
  in ({
    path = first.path;
    type = first.type;
  } // lib.optionalAttrs (first.type == "directory" && lib.any (x: x ? entries) list) {
    entries =
      let
        entriesList = map (x: x.entries) (lib.filter (x: x ? entries) list);
        commonAttrs = lib.foldl' (acc: el: lib.lists.intersectLists acc (lib.attrNames el)) (lib.attrNames (lib.elemAt entriesList 0)) entriesList;
      in lib.genAttrs commonAttrs (name: intersectionSameRoot (map (entries: entries.${name}) entriesList));
  });

  # only directories can be empty
  #empty = directoryPath: {
  #  path = path;
  #  type = "directory";
  #  entries = {};
  #};

  subtractSameRoot = a: b:
  assert a.path == b.path;
  # We can't subtract non-directories
  assert a.type == "directory";
  let
    # Everything is included if the lhs includes everything and the rhs doesn't include anything
    everythingIncluded = ! a ? entries && b ? entries && b.entries == {};

    # Nothing is included if either the lhs doesn't include anything, or the rhs excludes everything
    nothingIncluded = (a ? entries && a.entries == {}) || ! b ? entries;
    #nothingIncluded = (a ? entries || ! b ? entries) && (a.entries == {} || ! b ? entries);

    needsEntries = ! everythingIncluded || nothingIncluded;

    entriesValue =
      if nothingIncluded then {}
      # ! nothingIncluded && (! everythingIncluded || nothingIncluded)
      # ! nothingIncluded && ! everythingIncluded
      # ! ((a ? entries || ! b ? entries) && (a.entries == {} || ! b ? entries)) && ! (! a ? entries && b ? entries && b.entries == {})
      # ((! a ? entries && b ? entries) || (a.entries != {} && b ? entries)) && (a ? entries || ! b ? entries || b.entries != {})

      # (! a ? entries && b ? entries) && a ? entries || (! a ? entries && b ? entries) &&
      # ((! a ? entries && b ? entries) || (a.entries != {} && b ? entries)) && (a ? entries || ! b ? entries || b.entries != {})
      else null;

    lhsEverything = ! a ? entries;
    lhsSomething = a ? entries && a.entries != {};
    lhsNothing = a ? entries && a.entries == {};

    rhsEverything = ! b ? entries;
    rhsSomething = b ? entries && b.entries != {};
    rhsNothing = b ? entries && b.entries == {};

    everything = { };
    lhs = { entries = a.entries; };
    nothing = { entries = {}; };

    entryAttrs =
      # If we start with nothing, or subtract everything, there's nothing left
      if lhsNothing || rhsEverything then nothing
      # We don't subtract anything, nothing to change
      else if rhsNothing then lhs
      # We now know that rhsSomething
      else let
        lhsEntries =
          if lhsEverything
          then
            lib.mapAttrs (name: type:
              {
                path = a.path + ("/" + name);
                type = type;
              }
            ) (builtins.readDir a.path)
          else
            a.entries;

        intersection = lib.mapAttrs (name: rhsEntry:
          if rhsEntry.type != "directory" then null
          else
          let res = subtract lhsEntries.${name} rhsEntry;
          in if res ? entries && res.entries == {} then null else res
        ) (builtins.intersectAttrs lhsEntries b.entries);
      in { entries = builtins.removeAttrs lhsEntries (lib.attrNames b.entries) // lib.filterAttrs (name: value: value != null) intersection; };
      # If an entry is in lhs only -> propagate lhs
      # If an entry is in rhs only -> propagate lhs
      # If an entry is in both -> recurse
  in {
    path = a.path;
    type = "directory";
  } // entryAttrs;

  subtract = a: b: let c = makeCommonRoot [ a b ]; in tryDownroot (subtractSameRoot (lib.elemAt c 0) (lib.elemAt c 1));

  makeCommonRoot = list:
    let
      d = lib.path.difference (lib.listToAttrs (lib.imap0 (i: x: lib.nameValuePair (toString i) x.path) list));
    in map (uprootTo d.commonPrefix) list;

  union = list: unionSameRoot (makeCommonRoot list);


  intersection = list: tryDownroot (intersectionSameRoot (makeCommonRoot list));

  /*
  /home/tweagysil/src/nixpkgs (root directory)
  - lib (directory)
  - flake.nix (regular)
  - nixos (directory)
    - modules (recursive directory)
  */
  pretty = set:
  let
    go = indent: entries:
      lib.concatStrings (lib.mapAttrsToList (name: set:
        "\n${indent}- ${name} (${lib.optionalString (set.type == "directory" && ! set ? entries) "recursive "}${set.type})" +
        lib.optionalString (set.type == "directory" && set ? entries) (go (indent + "  ") set.entries)) entries);
  in
  "${toString set.path} (${lib.optionalString (set.type == "directory" && ! set ? entries) "recursive "}root ${set.type})${lib.optionalString (set.type == "directory" && set ? entries) (go "" set.entries)}";


  # Unioning a directory and a file that's contained in that directory yields just the directory

  example = intersection [
    (union [
      (singleton ./flake.nix)
      (singleton ./sources.nix)
    ])
    (union [
      (singleton ./sources.nix)
      (singleton ./flake.nix)
      (singleton ../notes.md)
      (singleton ../doc)
      (singleton ../doc/overrides.css)
    ])
  ];

  example2 = subtract (union [
    (singleton ./flake.nix)
    (singleton ../other.nix)
    (singleton ../nixos)
  ]) (union [
    (singleton ./kernel.nix)
    (singleton ../nixos/modules/module-list.nix)
  ]);

  # TODO: This should detect that all files from `./.` are there again and not recurse anymore
  # The goal should be that there's only one representation for the same source filtered tree
  example3 = union [
    (subtract (singleton ./.) (singleton ./flake.nix))
    (singleton ./flake.nix)
  ];

  # TODO: singleton should be implicit

  # TODO: The root should be reduced as much as possible at every step
  example4 = subtract
    (union [
      (singleton ./flake.nix)
      (singleton ./modules.nix)
    ])
    (singleton ./flake.nix);


in builtins.trace (pretty example4) null
