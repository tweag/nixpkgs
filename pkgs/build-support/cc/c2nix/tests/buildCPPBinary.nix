{ c2nix, ncurses }:
c2nix.buildCPPBinary {
  name = "example";
  src = ./example-project;
  # TODO: Where should ncurses be? With the use of -MM, both
  # `buildInputs` or `includeInputs` work, which I think
  # resolves the library earlier or later
  buildInputs = [ ncurses ];
  includeInputs = [ ];
  preprocessor_flags = "";
  cflags = "";
  cppflags = "";
  link_flags = "-lstdc++ -lncurses";
  link_attributes = {
    NIX_CFLAGS_LINK = "";
  };
}
