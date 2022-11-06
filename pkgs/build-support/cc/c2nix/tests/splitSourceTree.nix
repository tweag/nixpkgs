{
  c2nix,
  tests,
}:
c2nix.splitSourceFiles {
  src = ./example-project;
  dependencyInfo = tests.c2nix.dependencyInfo;
}
