# Functions for working with file paths, without reading from those paths. Both
# paths (e.g. `/foo/bar`) and strings (e.g. `"/foo/bar"`) are accepted data
# types, though generally strings are returned.
#
# Why is this path library restricted from reading paths?
# Inspecting paths using Nix happens at eval-time, but we don't know what kind of path we have, could also be build-time or runtime
{ lib }:
let
  inherit (builtins)
    storeDir
    ;

  inherit (lib.strings)
    hasSuffix
    stringToCharacters
    concatStringsSep
    isCoercibleToString
    substring
    splitString
    optionalString
    ;

  inherit (lib.lists)
    filter
    isList
    last
    head
    length
    sublist
    init
    ;

  inherit (lib.paths)
    makeSearchPath
    makeSearchPathOutput
    ;
in /* No rec! Add dependencies on this file just above */ {

  isAbsolute = path: lib.strings.hasPrefix "/" (toString path);

  /*
  Handle:
  - Path and string Nix data types
  - Absolute and relative paths (only string data type)
  - Multiple "/" in a row get turned into a single one
    - Question: Should we have a primitive for turning a path into components instead?
    - Also look at: https://doc.rust-lang.org/std/path/struct.PathBuf.html#method.components
  - Removes unnecessary dots like "/./"
  - TODO: Persist trailing slashes or not?
    - Nix doesn't even allow them in the path data type
    - Check other languages (TODO: Link to documentation / arguments)
      - Rust doesn't persist them when normalizing path strings
      - Python doesn't preserve them
      - Haskell does preserve them
    - Check with the Nix community
    - Design minimal path API interface, add examples, let people add edge/test cases
  - Only allows ".."'s at the beginning, so "foo/.." is disallowed and throws an error. Why?
    - Because nobody needs "foo/.."
    - Weird things happen if symlinks are involved
    - Operations like pathHasPrefix don't reliably work anymore without reading symlinks
    - There's no way to resolve symlinks in Nix eval-time paths
    - In addition, this path library is not allowed to interact with the filesystem at all, see the top for motivation

  TODO: Should paths be an internal attribute set structure? We can do a lot more things then:
  - Eventual windows path support
  - Reasonably tracking trailing slashes
  - Reasonably tracking absolute vs relative paths
  - Makes it faster in some cases maybe?
  */
  normalizePath = path:
    # Explain why everything is done the way it is
    let
      allComponents = splitString "/" path;
      hasLeadingSlash = head allComponents == "";
      start = if hasLeadingSlash then 1 else 0;
      hasEndingSlash = last allComponents == "";
      end = length allComponents - (if hasEndingSlash then 1 else 0);
      middleComponents = sublist start (end - start) allComponents;

      withoutDuplicateSlashesAndDots = filter (el: el != "" && el != ".") middleComponents;
      withoutDotDots = lib.foldl' (acc: el:
        if el == ".." && acc != [] && last acc != ".." then throw ".. not fully supported because of nix limitations" else acc ++ [el]
      ) [] withoutDuplicateSlashesAndDots;
      rootAncestor =
        if hasLeadingSlash
        then lib.foldl' (acc: el: if acc == [] && el == ".." then acc else acc ++ [el]) [] withoutDotDots
        else withoutDotDots;
      result = optionalString hasLeadingSlash "/" + concatStringsSep "/" rootAncestor + optionalString hasEndingSlash "/";
    in
      if path == "" then throw "normalizePath: Path is empty"
      else if rootAncestor == [] then
        if hasLeadingSlash then "/"
        else if hasEndingSlash then "./"
        else "."
      else result;

  # TODO: How to design this path library, look at other path library implementations
  # lib.path.isParentOf
  # commonAncestor
  # relativePathComponentsBetween
  # lib.path.join

  /* Normalize path, removing extranous /s

     Type: normalizePath :: string -> string

     Example:
       normalizePath "/a//b///c/"
       => "/a/b/c/"
  */
  #normalizePath = pathLike: toString (/. + pathLike);
  # normalizePath = s: (builtins.foldl' (x: y: if y == "/" && hasSuffix "/" x then x else x+y) "" (stringToCharacters s));

  /* Check whether a value is a store path.

     Example:
       isStorePath "/nix/store/d945ibfx9x185xf04b890y4f9g3cbb63-python-2.7.11/bin/python"
       => false
       isStorePath "/nix/store/d945ibfx9x185xf04b890y4f9g3cbb63-python-2.7.11"
       => true
       isStorePath pkgs.python
       => true
       isStorePath [] || isStorePath 42 || isStorePath {} || …
       => false
  */
  isStorePath = x:
    if !(isList x) && isCoercibleToString x then
      let str = toString x; in
      substring 0 1 str == "/"
      && dirOf str == storeDir
    else
      false;

  /* Construct a Unix-style, colon-separated search path consisting of
     the given `subDir` appended to each of the given paths.

     Type: makeSearchPath :: string -> [string] -> string

     Example:
       makeSearchPath "bin" ["/root" "/usr" "/usr/local"]
       => "/root/bin:/usr/bin:/usr/local/bin"
       makeSearchPath "bin" [""]
       => "/bin"
  */
  makeSearchPath =
    # Directory name to append
    subDir:
    # List of base paths
    paths:
    concatStringsSep ":" (map (path: path + "/" + subDir) (filter (x: x != null) paths));

  /* Construct a Unix-style search path by appending the given
     `subDir` to the specified `output` of each of the packages. If no
     output by the given name is found, fallback to `.out` and then to
     the default.

     Type: string -> string -> [package] -> string

     Example:
       makeSearchPathOutput "dev" "bin" [ pkgs.openssl pkgs.zlib ]
       => "/nix/store/9rz8gxhzf8sw4kf2j2f1grr49w8zx5vj-openssl-1.0.1r-dev/bin:/nix/store/wwh7mhwh269sfjkm6k5665b5kgp7jrk2-zlib-1.2.8/bin"
  */
  makeSearchPathOutput =
    # Package output to use
    output:
    # Directory name to append
    subDir:
    # List of packages
    pkgs: makeSearchPath subDir (map (lib.getOutput output) pkgs);

  /*
  Construct a library search path (such as RPATH) containing the
  libraries for a set of packages

  Example:
    makeLibraryPath [ "/usr" "/usr/local" ]
    => "/usr/lib:/usr/local/lib"
    pkgs = import <nixpkgs> { }
    makeLibraryPath [ pkgs.openssl pkgs.zlib ]
    => "/nix/store/9rz8gxhzf8sw4kf2j2f1grr49w8zx5vj-openssl-1.0.1r/lib:/nix/store/wwh7mhwh269sfjkm6k5665b5kgp7jrk2-zlib-1.2.8/lib"
  */
  makeLibraryPath = makeSearchPathOutput "lib" "lib";

  /* Construct a binary search path (such as $PATH) containing the
     binaries for a set of packages.

     Example:
       makeBinPath ["/root" "/usr" "/usr/local"]
       => "/root/bin:/usr/bin:/usr/local/bin"
  */
  makeBinPath = makeSearchPathOutput "bin" "bin";


}
