{
  c2nix,
  tests,
}:
c2nix.internal.sourcesForFiles {
  src = ./example-project;
  dependencyInfo = tests.c2nix.dependencyInfo;
}
