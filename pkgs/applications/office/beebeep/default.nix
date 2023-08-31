{ lib
, fetchzip
, autoPatchelfHook
, libsForQt5
}:
let

  inherit (libsForQt5)
    mkDerivation
    wrapQtAppsHook
    qtbase
    qtmultimedia
    qtx11extras;

in

mkDerivation rec {
  pname = "beebeep";
  version = "5.8.6";

  src = fetchzip {
    url = "https://netix.dl.sourceforge.net/project/beebeep/Linux/beebeep-${version}-qt5-amd64.tar.gz";
    sha256 = "sha256-YDgFRXFBM1tjLP99mHYJadgccHJYYPAZ1kqR+FngLKU=";
  };

  nativeBuildInputs = [
    (removeAttrs wrapQtAppsHook [ "__spliced" ])
    autoPatchelfHook
  ];

  buildInputs = [
    qtbase
    qtmultimedia
    qtx11extras
  ];

  installPhase = ''
    mkdir -p $out/bin
    cp * $out/bin
  '';

  meta = with lib; {
    homepage = "https://www.beebeep.net/";
    description = "BeeBEEP is the free office messenger that is indispensable in all those places where privacy and security are an essential requirement.";
    platforms = platforms.linux;
    license = licenses.gpl2Only;
    maintainers = with maintainers; [ mglolenstine ];
  };
}
