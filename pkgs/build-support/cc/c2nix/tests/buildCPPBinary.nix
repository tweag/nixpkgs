{ c2nix, ncurses }:
c2nix.buildCPPBinary {
  name = "example";
  src = ./example-project;
  buildInputs = [ ncurses ];
  preprocessor_flags = [];
  cflags = "";
  cppflags = "";
  link_flags = "-lstdc++ -lncurses";
  link_attributes = {
    NIX_CFLAGS_LINK = "";
  };
}
