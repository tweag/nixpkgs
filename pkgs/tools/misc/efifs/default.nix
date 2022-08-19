{ stdenv
, lib
, edk2
, fetchFromGitHub
, python3
, nasm
}:
let
  version = "1.8";

  targetArch =
    if stdenv.isi686 then
      "IA32"
    else if stdenv.isx86_64 then
      "X64"
    else if stdenv.isAarch64 then
      "AARCH64"
    else
      throw "Unsupported architecture";

  efifsSrc = fetchFromGitHub {
    owner = "pbatard";
    repo = "efifs";
    rev = "v${version}";
    fetchSubmodules = true;
    sha256 = "sha256-+hao8m6H+Qi+isJZBMBSXYF1xSaAYtTepIY9n6LEWV0=";
  };
in
edk2.mkDerivation "EfiFsPkg/EfiFsPkg.dsc" {
  pname = "efifs";
  inherit version;

  postUnpack = ''
    echo "unpacking ${efifsSrc} to ${edk2.src.name}/EfiFsPkg"
    cp -r ${efifsSrc} ${edk2.src.name}/EfiFsPkg
  '';

  preConfigure = ''
    (chmod -R u+w EfiFsPkg; cd EfiFsPkg/grub; patch -p1 < ../0001-GRUB-fixes.patch)
  '';

  PYTHON_COMMAND = "${python3}/bin/python";

  nativeBuildInputs = [ nasm ];

  preBuild = ''
    patchShebangs --build ./EfiFsPkg/set_grub_cpu.sh
    ./EfiFsPkg/set_grub_cpu.sh ${targetArch}
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    install -D Build/EfiFs/*/${targetArch}/*.efi $out
    runHook postInstall
  '';

  meta = with lib; {
    description = "EfiFs - EFI File System Drivers";
    homepage = "https://efi.akeo.ie";
    license = licenses.gpl3Plus;
    platforms = edk2.meta.platforms;
  };
}
