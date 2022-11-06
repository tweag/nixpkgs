{callPackage}: {
  dependencyInfo = callPackage ./dependencyInfo.nix {};
  sourcesForFiles = callPackage ./splitSourceTree.nix {};
  buildCPPBinary = callPackage ./buildCPPBinary.nix {};
}
