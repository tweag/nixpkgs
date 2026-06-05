{
  lib,
  stdenv,
  rtpPath,
  toVimPlugin,
}:

{
  addRtp = drv: lib.warn "`addRtp` is deprecated, does nothing." drv;

  buildVimPlugin =
    {
      name ? "${attrs.pname}-${attrs.version}",
      src,
      unpackPhase ? "",
      configurePhase ? ":",
      buildPhase ? ":",
      preInstall ? "",
      postInstall ? "",
      path ? ".",
      addonInfo ? null,
      meta ? { },
      ...
    }@attrs:
    let
      pos = builtins.unsafeGetAttrPos "pname" attrs;
      drv = stdenv.mkDerivation (
        attrs
        // {
          name = lib.warnIf (attrs ? vimprefix) "The 'vimprefix' is now hardcoded in toVimPlugin" name;

          __structuredAttrs = true;
          inherit
            unpackPhase
            configurePhase
            buildPhase
            addonInfo
            preInstall
            postInstall
            ;

          installPhase = ''
            runHook preInstall

            target=$out/${rtpPath}/${path}
            mkdir -p $out/${rtpPath}
            cp -r . $target

            runHook postInstall
          '';

          meta = {
            platforms = lib.platforms.all;
          }
          // meta
          // lib.optionalAttrs (pos.file == toString ../generated.nix || pos.file == toString ../cocPlugins.nix) {
            isGenerated = true;
          };
        }
      );
    in
    toVimPlugin drv;

}
