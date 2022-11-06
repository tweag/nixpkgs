{
  stdenv,
  llvmPackages_13,
  lib,
  clang-tools,
}:
/*
Return a derivation that compiles a single C or C++ object file
*/
{
  # File name
  name,
  # Shell commands to link all required source files into the build directory
  linkSourceFiles,
  compile_attributes,
  buildInputs,
  preprocessor_flags,
  cflags,
  cppflags,
  # For clang-tidy
  clang_tidy_check,
  clang_tidy_args,
  clang_tidy_config,
}:
let
  # TODO: Since we pass all include dirs to the compiler in the compilation derivations, any change to the include path requires rebuilding everything.
  # TODO: Filter only the include directories required for each module
  #include_path = toString (
  #  map (inc: "-I ${inc}") all_include_dirs
  #);

  # We need to tell clang-tidy to use use headers from libc++ instead of GCC's stdc++ that Nix inexplicably defaults to.
  clang_tools_with_libcxx =
    clang-tools.overrideAttrs
    (old: {clang = llvmPackages_13.libcxxClang;});

  is_c = lib.strings.hasSuffix ".c" name;
in
  stdenv.mkDerivation (compile_attributes
    // {
      # The Nix compiler wrappers enable "source fortification" which is a glibc feature that is *documented* as
      # sometimes transforming correct programs into incorrect ones. We turn that off.
      hardeningDisable = ["fortify"];
      # the `.o` suffix is required for C/C++ compilers to run the linker
      name = lib.strings.sanitizeDerivationName "${builtins.baseNameOf name}.o";
      buildInputs = buildInputs;
      # TODO: don't hard-code phases
      phases =
        [ "unpackPhase" "build"]
        ++ (
          if clang_tidy_check && !is_c
          then ["check"]
          else []
      );

      unpackPhase = ''
        mkdir source
        cd source
        ${linkSourceFiles}
      '';

      build = ''
        ${
          if is_c
          then "$CC"
          else "$CXX"
        } -c ${lib.escapeShellArg name} ${lib.escapeShellArgs preprocessor_flags} ${
          if is_c
          then cflags
          else cppflags
        } -o $out
      '';
      # TODO: This depends on clang_tidy even when this phase isn't ran in the end
      check = ''
        ${clang_tools_with_libcxx}/bin/clang-tidy \
        ${clang_tidy_args} \
        ${clang_tidy_config} \
        --use-color \
        --quiet \
        ${lib.escapeShellArg name} \
        -- \
        ${lib.escapeShellArgs preprocessor_flags} \
        ${cppflags} \
        '';
    })
