{ callPackage }: {
  dependencyInfo = callPackage ./dependencyInfo.nix {};
  sourcesForFiles = callPackage ./sourcesForFiles.nix {};
}
