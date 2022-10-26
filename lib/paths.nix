# Functions for working with file paths, without reading from those paths. Both
# paths (e.g. `/foo/bar`) and strings (e.g. `"/foo/bar"`) are accepted data
# types, though generally strings are returned.
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
    ;

  inherit (lib.lists)
    filter
    isList
    ;

  inherit (lib.paths)
    makeSearchPath
    makeSearchPathOutput
    ;
in /* No rec! Add dependencies on this file just above */ {

  /* Normalize path, removing extranous /s

     Type: normalizePath :: string -> string

     Example:
       normalizePath "/a//b///c/"
       => "/a/b/c/"
  */
  normalizePath = s: (builtins.foldl' (x: y: if y == "/" && hasSuffix "/" x then x else x+y) "" (stringToCharacters s));

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

  /* Construct a library search path (such as RPATH) containing the
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
