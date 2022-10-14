{ c2nix, ncurses }:
c2nix.dependencyInfo {
  name = "example";
  src = ./example-project;
  preprocessor_flags = "";
  all_include_dirs = [];
}
