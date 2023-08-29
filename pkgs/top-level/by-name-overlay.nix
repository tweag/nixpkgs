/*
Internal Nixpkgs file, it may be removed or changed at any point without warning.
Read all package files from a by-name package directory.
No validity checks are done, instead this function is optimised for performance.
See ../by-name/README.md for more details.
Type: Path -> AttrsOf Path
Example:
  import ./read-by-name.nix ../by-name
  => {
    hello = ../by-name/he/hello/package.nix;
    hey = ../by-name/he/hey/package.nix;
    foo = ../by-name/fo/foo/package.nix;
  }
*/
let
  baseDirectory = ../by-name;

  # Because of Nix's `import` cache, importing lib is "free"
  lib = import ../../lib;

  inherit (builtins)
    readDir
    ;

  inherit (lib.attrsets)
    mapAttrs
    mapAttrsToList
    mergeAttrsList
    ;

  # Package files for a single shard
  # Type: String -> String -> AttrsOf Path
  namesForShard = shard: type:
    if type != "directory" then
      # Ignore non-directories. Technically only README.md is allowed as a file in the base directory, so we could alternatively:
      # - Assume that README.md is the only file and change the condition to `shard == "README.md"` for a minor performance improvement.
      #   This would however cause very poor error messages if there's other files.
      # - Ensure that README.md is the only file, throwing a better error message if that's not the case.
      #   However this would make for a poor code architecture, because one type of error would have to be duplicated in the validity checks and here.
      # Additionally in either of those alternatives, we would have to duplicate the hardcoding of "README.md"
      { }
    else
      mapAttrs
        (name: _: baseDirectory + "/${shard}/${name}/package.nix")
        (readDir (baseDirectory + "/${shard}"));

  packageFiles = mergeAttrsList (mapAttrsToList namesForShard (readDir baseDirectory));
in
self: super:
mapAttrs (name: file:
  self.callPackage file { }
) packageFiles
