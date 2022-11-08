# Functions for working with file paths
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
    genList
    elemAt
    ;

  inherit (lib.paths)
    makeSearchPath
    makeSearchPathOutput
    ;
in /* No rec! Add dependencies on this file just above */ {

  isAbsolute = path: lib.strings.hasPrefix "/" (toString path);

  split = path:
  let
    # Split the string into its parts using regex for efficiency. This regex
    # matches patterns like "/", "/./", "/././", with arbitrarily many "/"s
    # together. These are the main special cases:
    # - Leading "./" or "/" get split into a leading "." or "" part
    #   respectively
    # - Trailing "/." or "/" get split into a trailing "." or ""
    #   part respectively
    #
    # These are the only cases where "." and "" parts can occur
    parts = builtins.split "/+(\\./+)*" (toString path);

    # `builtins.split` creates a list of 2 * k + 1 elements, containing the k +
    # 1 parts, interleaved with k matches where k is the number of
    # (non-overlapping) matches. This calculation here gets the number of parts
    # back from the list length
    # floor( (2 * k + 1) / 2 ) + 1 == floor( k + 1/2 ) + 1 == k + 1
    partCount = length parts / 2 + 1;

    # To assemble the final list we want to:
    # - Skip a potential leading ".", normalising "./foo" to "foo"
    #   - Don't skip a leading "" though, since it indicates an absolute path
    #     Such a part is later replaced with a "/"
    # - Skip a potential trailing "." or "", normalising "foo/" and "foo/." to
    #   "foo"
    skipStart = if head parts == "." then 1 else 0;
    skipEnd = if last parts == "." || last parts == "" then 1 else 0;

    # We can now know the length of the result by removing the number of
    # skipped parts from the total number
    resultLength = partCount - skipEnd - skipStart;
    # And we can use this to generate the result list directly. Doing it this
    # way over a combination of `filter`, `init` and `tail` makes it more
    # efficient, because we don't allocate any intermediate lists
    result = genList (index:
      let
        # To get to the element we need to add the number of parts we skip and
        # multiply by two due to the interleaved layout of `parts`
        value = elemAt parts ((skipStart + index) * 2);
      in

      # We don't support ".." components
      if value == ".." then
        throw "lib.path.split: Path contains a `..` component, which is not supported due to ambiguity. You can use the command `realpath` at buildtime or runtime instead"

      # This can only happen for the first element, indicating an absolute path
      # Replace it with a "/" so that the first returned element is absolute
      # iff the input path is absolute
      else if value == "" then
        "/"

      # Otherwise just return the part unchanged
      else
        value
    ) resultLength;

  in
    if path == ""
    then throw "lib.path.split: Path is empty"
    else result;

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
