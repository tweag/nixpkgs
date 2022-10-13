{ c2nix }:
c2nix.buildCPPBinary {
  name = "example";
  src = ./example-project;
  buildInputs = [ ];
  includeInputs = [ ];
  preprocessor_flags = "";
  cflags = "";
  cppflags = "";
  link_flags = "";
  link_attributes = {
    NIX_CFLAGS_LINK = "";
  };
}
