{callPackage}: {
  dependencyInfo = callPackage ./dependencyInfo.nix {};
  buildCPPBinary = callPackage ./buildCPPBinary.nix {};
}
