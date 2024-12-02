{ hello }:
hello.overrideAttrs (old: {
  name = "not-actually-hello";
})
