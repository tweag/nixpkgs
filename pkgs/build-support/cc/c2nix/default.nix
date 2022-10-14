/*
TODO:
- [ ] Try it out with a C code sample
- [x] Split it up into multiple files
  - build_dependency_info
  - compile_module
  - Final linking step in buildCPP
  - Top-level functions for buildCPPBinary, buildCPPStaticLibrary, buildCPPSharedLibrary
- [ ] Document the code and interface
  - [ ] Document all parameters for all functions
- [ ] Improve the readibility of the code
- [ ] Improve the workings of the code
- [ ] Write tests
- [ ] Make a list of things to keep in the fork
*/

# TODO: makeOverridable

{
    pkgs,
    callPackage,
    # TODO drop this when it's in nixpkgs main
    lib,
    sourcesLib ? lib,
    # sourcesLib ? (import ./pinned_nixpkgs.nix).sources
}:
let
    inherit (sourcesLib) sources filesystem;

    lib = pkgs.lib;

    # srsly?  lib.splitString dies with "stack overflow" on long-ish lists
    splitStringRE = delim_re: original:
        let
            splits = builtins.split delim_re original;
            len = (builtins.div (builtins.add 1 (builtins.length splits)) 2);
        in
            builtins.genList (i: builtins.elemAt splits (i*2)) len;

    # Use `pkgs.binutils-unwrapped` because LLVM's objdump doesn't correctly handle glibc's versioned symbols
    # The syntax "if SYMS=$(<commands that could have a non-0 exit code>); then echo ...."
    #  is present because grep, if "GLIBC" is not found, will return 1 and therefore cannot be used directly
    glibc_version_symbols_internal = binary_name: ''
        if SYMS=$(${pkgs.binutils-unwrapped}/bin/objdump -T "${binary_name}" | ${pkgs.gawk}/bin/awk '{print $5}' | ${pkgs.gnugrep}/bin/grep GLIBC | ${pkgs.gnused}/bin/sed 's/ *$//g' | ${pkgs.gnused}/bin/sed 's/GLIBC_//' | sort | uniq); then echo "$SYMS" ; else echo ; fi
    '';

in rec {
    inherit sources;

    glibc_version_symbols = glibc_version_symbols_internal "$1";

    dependencyInfo = callPackage ./dependencyInfo.nix {};

    compileModule = callPackage ./compileModule.nix {
      inherit splitStringRE sources;
      # TODO: llvmPackages_13, rebase nixpkgs
      llvmPackages_13 = pkgs.llvmPackages;
    };

    buildCPP = callPackage ./buildCPP.nix {
      inherit sources filesystem splitStringRE glibc_version_symbols_internal;
    };

    buildCPPBinary =
        {
            name,

            # Source and/or include files, in the correct relative relationship.
            # Automatically filtered for only .c, .cpp, .cc, .h, and .hpp files.
            # The build takes place in the focus directory of src, so any flags that refer to paths are relative to that directory.
            src,

            # Include files from the same repo as src.  Automatically filtered for only .h and .hpp files and combined with src.
            # The focus directory of each top-level entry in this array is made an include directory with `-I`.  (`reparent` if this is undesired)
            includeSrc ? [],

            # The environment to use for the build
            stdenv ? pkgs.stdenv,

            # Derivations that are dependencies of the build (currently, both compile and link steps)
            buildInputs,

            # This sets the loader to use the default FHS location and checks that no "too new" glibc version is required.
            # Useful for when you want to build software that will run on non-NixOS systems.
            make_redistributable ? false,

            # If true, runs the `clang-tidy` linter on all source files alongside compilation.
            clang_tidy_check ? false,

            preprocessor_flags,
            cflags,
            cppflags,
            link_flags,
            link_attributes,
            compile_attributes ? {},
        }: buildCPP {
            inherit name src includeSrc buildInputs preprocessor_flags cflags cppflags compile_attributes link_attributes clang_tidy_check;
            make_fhs_compatible = make_redistributable;
            glibc_version_check = make_redistributable;
            outputDir = "bin";
            artifactName = name;
            link_command = ''
                $CC -v -o $out/bin/${name}'';
            inherit link_flags;
            # TODO: this will always build `separateDebugInfo` using the default in `buildCPP` - is this intended?
        };

    buildCPPStaticLibrary =
        {
            name,

            # Source and/or include files, in the correct relative relationship.
            # Automatically filtered for only .c, .cpp, .cc, .h, and .hpp files.
            # The build takes place in the focus directory of src, so any flags that refer to paths are relative to that directory.
            src,

            # Include files from the same repo as src.  Automatically filtered for only .h and .hpp files and combined with src.
            # The focus directory of each top-level entry in this array is made an include directory with `-I`.  (`reparent` if this is undesired)
            includeSrc ? [],

            # The environment to use for the build
            stdenv ? pkgs.stdenv,

            # Derivations that are dependencies of the build (currently, both compile and link steps)
            buildInputs,

            # If true, runs the `clang-tidy` linter on all source files alongside compilation.
            clang_tidy_check ? false,

            preprocessor_flags,
            cflags,
            cppflags,
            compile_attributes ? {},
        }: buildCPP rec {
            inherit name src includeSrc buildInputs preprocessor_flags cflags cppflags compile_attributes clang_tidy_check;
            outputDir = "lib";
            artifactName = "lib${name}.a";
            separateDebugInfo = false;
            make_fhs_compatible = false;
            link_attributes = { postFixup = "true"; };
            link_command = ''
                ar rcs $out/lib/${artifactName}'';
            link_flags = "";
            glibc_version_check = false;
        };

    buildCPPSharedLibrary =
        {
            name,

            # Source and/or include files, in the correct relative relationship.
            # Automatically filtered for only .c, .cpp, .cc, .h, and .hpp files.
            # The build takes place in the focus directory of src, so any flags that refer to paths are relative to that directory.
            src,

            # Include files from the same repo as src.  Automatically filtered for only .h and .hpp files and combined with src.
            # The focus directory of each top-level entry in this array is made an include directory with `-I`.  (`reparent` if this is undesired)
            includeSrc ? [],

            # The environment to use for the build
            stdenv ? pkgs.stdenv,

            # Derivations that are dependencies of the build (currently, both compile and link steps)
            buildInputs,

            # This enables the check that no "too new" glibc version is required
            make_redistributable ? true,

            # This checks that no C++ standard library symbols are publicly exposed
            symbol_leakage_check ? true,

            # If true, runs the `clang-tidy` linter on all source files alongside compilation.
            clang_tidy_check ? false,

            preprocessor_flags,
            cflags,
            cppflags,
            link_flags,
            link_attributes ? {},
            compile_attributes ? {},
            version_script ? null,
            separateDebugInfo ? true
        }: buildCPP {
            inherit name src includeSrc buildInputs preprocessor_flags cflags cppflags compile_attributes clang_tidy_check link_attributes symbol_leakage_check separateDebugInfo;
            make_fhs_compatible = false;
            glibc_version_check = make_redistributable;
            outputDir = "lib";
            artifactName = "lib${name}.so";
            link_command = ''
                $CC -o $out/lib/lib${name}.so'';
            link_flags = "${link_flags} -shared" + (if version_script!=null then " -Wl,--version-script=" + version_script else "");
        };

}
