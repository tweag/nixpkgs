{ c2nix }:
c2nix.dependencyInfo {
  name = "example";
  src = ./example-project;
  includeInputs = [ ];
  preprocessor_flags = "";
  all_include_dirs = [];
}
