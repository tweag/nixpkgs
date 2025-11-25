{
  callPackage,
  lib,
  stdenv,
  fetchurl,
  nixos,
  testers,
  versionCheckHook,
  hello,
  meta,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "hello";
  version = "2.12.2";

  src = fetchurl {
    url = "mirror://gnu/hello/hello-${finalAttrs.version}.tar.gz";
    hash = "sha256-WpqZbcKSzCTc9BHO6H6S9qrluNE72caBm0x6nc4IGKs=";
  };

  # The GNU Hello `configure` script detects how to link libiconv but fails to actually make use of that.
  # Unfortunately, this cannot be a patch to `Makefile.am` because `autoreconfHook` causes a gettext
  # infrastructure mismatch error when trying to build `hello`.
  env = lib.optionalAttrs stdenv.hostPlatform.isDarwin {
    NIX_LDFLAGS = "-liconv";
  };

  doCheck = true;

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
  ];

  # Give hello some install checks for testing purpose.
  postInstallCheck = ''
    stat "''${!outputBin}/bin/${finalAttrs.meta.mainProgram}"
  '';

  passthru.tests = {
    version = testers.testVersion { package = hello; };
  };

  passthru.tests.run = callPackage ./test.nix { hello = finalAttrs.finalPackage; };

  meta = meta.hello // {
    changelog = "https://git.savannah.gnu.org/cgit/hello.git/plain/NEWS?h=v${finalAttrs.version}";
    platforms = lib.platforms.all;
  };
})
