{
  stdenv,
  sources,
  llvmPackages_13,
  lib,
  clang-tools,
}:
/*
Return a derivation that compiles a single C or C++ object file
*/
{
  name,
  # TODO: `all_src`, `dependencies`, and `rel_path` should be processed beforehand and the result passed as `src`
  all_src,
  dependencies,
  rel_path,
  compile_attributes,
  buildInputs,
  preprocessor_flags,
  cflags,
  cppflags,
  all_include_dirs,
  # For clang-tidy
  clang_tidy_check,
  clang_tidy_args,
  clang_tidy_config,
}:
let
  # TODO: Since we pass all include dirs to the compiler in the compilation derivations, any change to the include path requires rebuilding everything.
  # TODO: Filter only the include directories required for each module
  include_path = toString (
    map (inc: "-I ${inc}") all_include_dirs
  );

  /*
  Create a copy of each original source file in the Nix store, and
  symlink it to its corresponding relative location in the current directory.
  NOTE: This is what enables incremental builds with file-level granularity.

  TODO: This produces bash code right now. Maybe this should be a build hook?
  */
  link_module_dependencies =
  {
    # Name of source file to compile
    #
    # Type:
    #   Path
    #
    # Example:
    #   "main.cpp"
    name,

    # Dependencies of the source file to compile, including itself, as produced by `c2nix.compileModule`
    #
    # Example
    #   [ "main.cpp" "lib/utils.h" ]
    #
    # Type:
    #   [String]
    dependencies,
    src,
  }:


  # nativeBuildInputs = [ someSetupHook ];
  # someSetupHookArg = 10

  /*
  Requirements for ideal nixpkgs upstreamedness:
  - Incremental, changing one file doesn't require everything to be recompiled
  - (optional) No IFD, nixpkgs hydra

  For use in nixpkgs itself, needs to work with things like:
    src = fetchFromGitHub {
    };
  To make that work (without IFD), we need:
  - A JSON file committed to nixpkgs containing the C dependency info (for Nix to create the static derivation graph)
  - A JSON file committed to nixpkgs containing all file hashes (granularSource proposal)

  fixed-output derivation for a single file, depending on fetchFromGitHub for the entire repository

  builtins.path
  pkgs.granularSource._path
  pkgs.granularSource._pathSymlinks { ... }

  pkgs.fixedOutputDerivationForSpecificFile { jsonFile = ...; src = ...; subpath = "foo/bar"; }

  fixedOutputDeriationFromJSON.path {
    filter = ...;
  }

  lib.sources
  TODO: Write down why we'd decide to write an alternative builtins.path so we
  can change the underlying primitive lib.sources uses, therefore reusing all
  of lib.sources for eval time and build time

  Ask client: Do you want this JSON pinning build-time granular sources thing
  to be reusable for any other incremental build tooling for other languages
  (in nixpkgs or elsewhere), or for now just local to c2nix

  TODO: Make a draft PR for granular source proposal
  */

    if (builtins.length dependencies) == 0
    # This is almost certainly a bug, since it must at least depend on its own source file
    then throw "Module ${name}: no source dependencies detected!"
    else ''
      mkdir -p ${toString (lib.lists.unique (map builtins.dirOf dependencies))}
      ${
        lib.strings.concatMapStringsSep "\n" (
          dep: "ln -s ${builtins.path {
            # We don't want a dependency on the whole `all_src` - that would prevent incremental builds.
            # Therefore use the relative path to `dep`, but within the original `src` directory.
            # That is typically part of the source repository, and *not* in the Nix store.
            # Referencing the original source will create another, separate copy of `dep` in the Nix store.
            path = src + ("/" + dep);
            name = "source";
          }} ${lib.escapeShellArg dep}"
        )
        dependencies
      }
    '';

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
        [ "configurePhase" "build"]
        ++ (
          if clang_tidy_check && !is_c
          then ["check"]
          else []
        );
      configurePhase = ''
        mkdir -p source/${lib.escapeShellArg rel_path}
        cd source/${lib.escapeShellArg rel_path}
        ${link_module_dependencies { inherit name dependencies; src = sources.getOriginalFocusPath all_src; }}
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
        } ${include_path} -o $out
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
        ${include_path}'';
    })
