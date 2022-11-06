/*
TODO:
- [ ] Try it out with a C code sample
- [x] Split it up into multiple files
  - build_dependency_info
  - compile_module
  - Final linking step in buildCPP
  - Top-level functions for buildCPPBinary, buildCPPStaticLibrary, buildCPPSharedLibrary
- [ ] Document the code and interface
  - [ ] Document all parameters for all functions (markdown)
    - [x] dependencyInfo
    - [ ] compileModule
    - [x] buildCPP
    - [x] buildCPPBinary
    - [x] buildCPPSharedLibrary
    - [x] buildCPPStaticLibrary
  - [ ] stopgap until we have coherent rendering of code comments:
        duplicate documentation between manual section and code comments
- [ ] Improve the readibility of the code
- [ ] Improve the workings of the code
- [ ] Write tests
- [ ] Make a list of things to keep in the fork
*/
# TODO: makeOverridable
{
  pkgs,
  callPackage,
  callPackages,
  # TODO drop this when it's in nixpkgs main
  lib,
  makeSetupHook,
}: let

  lib = pkgs.lib;

  # Use `pkgs.binutils-unwrapped` because LLVM's objdump doesn't correctly handle glibc's versioned symbols
  # The syntax "if SYMS=$(<commands that could have a non-0 exit code>); then echo ...."
  #  is present because grep, if "GLIBC" is not found, will return 1 and therefore cannot be used directly
  glibc_version_symbols_internal = binary_name: ''
    if SYMS=$(${pkgs.binutils-unwrapped}/bin/objdump -T "${binary_name}" | ${pkgs.gawk}/bin/awk '{print $5}' | ${pkgs.gnugrep}/bin/grep GLIBC | ${pkgs.gnused}/bin/sed 's/ *$//g' | ${pkgs.gnused}/bin/sed 's/GLIBC_//' | sort | uniq); then echo "$SYMS" ; else echo ; fi
  '';
in rec {

  # TODO: does this have to be exported?
  glibc_version_symbols = glibc_version_symbols_internal "$1";

  # TODO (@fricklerhandwerk): this should not be exported
  compileModule = callPackage ./compileModule.nix {
    # TODO: llvmPackages_13, rebase nixpkgs
    llvmPackages_13 = pkgs.llvmPackages;
  };

  /*
  TODO: Parameters documented in

    /languages-frameworks/cc.section.md#c2nix-buildCPPBinary

  */
  buildCPPBinary = {
    name,
    src,
    # includeSrc ? [],
    stdenv ? pkgs.stdenv,
    buildInputs,
    make_redistributable ? false,
    clang_tidy_check ? false,
    preprocessor_flags,
    cflags,
    cppflags,
    link_flags,
    link_attributes,
    compile_attributes ? {},
  }:
    buildCPP {
      inherit name src buildInputs preprocessor_flags cflags cppflags compile_attributes link_attributes clang_tidy_check;
      make_fhs_compatible = make_redistributable;
      glibc_version_check = make_redistributable;
      outputDir = "bin";
      artifactName = name;
      link_command = ''
        $CC -v -o $out/bin/${name}'';
      inherit link_flags;
      # TODO: this will always build `separateDebugInfo` using the default in `buildCPP` - is this intended?
    };

  /*
  TODO: Parameters documented in

    /languages-frameworks/cc.section.md#c2nix-buildCPPStaticLibrary

  */
  buildCPPStaticLibrary = {
    name,
    src,
    # includeSrc ? [],
    stdenv ? pkgs.stdenv,
    buildInputs,
    clang_tidy_check ? false,
    preprocessor_flags,
    cflags,
    cppflags,
    compile_attributes ? {},
  }:
    buildCPP rec {
      inherit name src buildInputs preprocessor_flags cflags cppflags compile_attributes clang_tidy_check;
      outputDir = "lib";
      artifactName = "lib${name}.a";
      separateDebugInfo = false;
      make_fhs_compatible = false;
      link_attributes = {postFixup = "true";};
      link_command = ''
        ar rcs $out/lib/${artifactName}'';
      link_flags = "";
      glibc_version_check = false;
    };

  /*
  TODO: Parameters documented in

    /languages-frameworks/cc.section.md#c2nix-buildCPPSharedLibrary

  */
  buildCPPSharedLibrary = {
    name,
    src,
    # includeSrc ? [],
    stdenv ? pkgs.stdenv,
    buildInputs,
    make_redistributable ? true,
    symbol_leakage_check ? true,
    clang_tidy_check ? false,
    preprocessor_flags,
    cflags,
    cppflags,
    link_flags,
    link_attributes ? {},
    compile_attributes ? {},
    version_script ? null,
    separateDebugInfo ? true,
  }:
    buildCPP {
      inherit name src buildInputs preprocessor_flags cflags cppflags compile_attributes clang_tidy_check link_attributes symbol_leakage_check separateDebugInfo;
      make_fhs_compatible = false;
      glibc_version_check = make_redistributable;
      outputDir = "lib";
      artifactName = "lib${name}.so";
      link_command = ''
        $CC -o $out/lib/lib${name}.so'';
      link_flags =
        "${link_flags} -shared"
        + (
          if version_script != null
          then " -Wl,--version-script=" + version_script
          else ""
        );
    };

  # TODO (@fricklerhandwerk): figure out how to render documentation for the following

  dependencyInfo = callPackage ./dependencyInfo.nix {};

  splitSourceTree = callPackage ./splitSourceTree.nix {};

  buildCPP = callPackage ./buildCPP.nix {
    inherit glibc_version_symbols_internal;
  };
}
