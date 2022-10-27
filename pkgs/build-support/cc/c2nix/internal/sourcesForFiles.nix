{
  lib,
  c2nix,
}:
{
  src,
  dependencyInfo ? null,
}:
lib.mapAttrs (file: dependencies:
  # This is almost certainly a bug, since it must at least depend on its own source file
  assert lib.assertMsg (dependencies != []) "c2nix.sourceForFile ${file}: no source dependencies detected!";
  lib.strings.concatMapStringsSep "\n" (dep:
    let
      # We don't want a dependency on the whole `all_src` - that would prevent incremental builds.
      # Therefore use the relative path to `dep`, but within the original `src` directory.
      # That is typically part of the source repository, and *not* in the Nix store.
      # Referencing the original source will create another, separate copy of `dep` in the Nix store.
      dependencyFile = builtins.path {
        name = lib.strings.sanitizeDerivationName (baseNameOf dep);
        path = src + "/${dep}";
      };
    in ''
      mkdir -p "$(dirname ${lib.escapeShellArg dep})"
      ln -s ${dependencyFile} ${lib.escapeShellArg dep}''
  ) dependencies
) (lib.importJSON dependencyInfo).dependencies
