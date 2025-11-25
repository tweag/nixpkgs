let
  lib = import ../../lib;
  namesForShard =
    shard: type:
    if type != "directory" then
      { }
    else
      lib.mapAttrs (name: _: ../by-name + "/${shard}/${name}/meta.toml") (
        builtins.readDir (../by-name + "/${shard}")
      );

  transform =
    meta:
    meta
    // {
      license = lib.licenses.${meta.license};
      maintainers = map (m: lib.maintainers.${m}) meta.maintainers;
    };
in
lib.pipe ../by-name [
  builtins.readDir
  (lib.mapAttrsToList namesForShard)
  lib.attrsets.mergeAttrsList
  (lib.filterAttrs (_: builtins.pathExists))
  (lib.mapAttrs (name: file: transform (lib.importTOML file)))
]
