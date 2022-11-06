{
  pkgs,
  # The environment to use for the build
  stdenv ? pkgs.stdenv,
  c2nix,
  lib,
  # TODO: why do we need that here?
  glibc_version_symbols_internal,
}:
/*
Build a C or C++ project
*/
{
  # Package name

  # Type:
  #   String
  name,

  # Directory with source or header files, in the correct relative relationship.
  #
  # Any flags (from `*_flags` attributes) that refer to paths will be taken as relative to that directory.
  #
  # Only the following file types are considered:
  #
  # - `.c`
  # - `.cpp`
  # - `.cc`
  # - `.h`
  # - `.hpp`
  #
  # Type:
  #   Path
  src,

  # Path to JSON file with dependency information, as produced by `c2nix.dependencyInfo`.
  #
  # This file is generated automatically using Import From Derivation if the argument is unset.
  # To avoid Import From Derivation, pre-generate the file with `c2nix.dependencyInfo`.
  dependencyInfo ? null,

  # Derivations that are dependencies of the build.
  # Currently, these are used for both compile and link steps.
  #
  # Type:
  #   [Derivation]
  buildInputs,

  # Subdirectory of `$out` or `$debug` to place build artifacts in
  #
  # Type:
  #   String
  #
  # Example:
  #   "bin"
  #
  # Example:
  #   "lib"
  outputDir,

  # Basename of the final output artifact
  #
  # Type:
  #   String
  #
  # Example:
  #   "lib{name}.a"
  artifactName,

  # Build the package such that it will run on systems without Nix.
  #
  # This will set the [loader] to use the default [FHS] location and check that the required `glibc` version is not "to new".
  #
  # [loader]: https://en.m.wikipedia.org/wiki/Dynamic_loading
  # [FHS]: https://en.m.wikipedia.org/wiki/Filesystem_Hierarchy_Standard
  make_fhs_compatible ? false,

  # Check that the final artifact does not publicly expose any C++ mangled symbol names.
  # This is useful if you're trying to build a shared library written in C++ which exposes a pure C interface.
  symbol_leakage_check ? false,

  # Check that none of the dependencies of the final artifact require `glibc` version symbols later than `max_glibc_version`.
  glibc_version_check ? false,

  # If 'glibc_version_check` is set, enforce that all `glibc` version symbols are older than this version.
  # TODO: Should we combine this and the above `glibc_version_check` parameter?
  # TODO: This version seems quite arbitrary - can we at least document a reason for it, otherwise tie it to something more high-level?
  max_glibc_version ? "2.18.0",

  # Run the `clang-tidy` linter on all source files alongside compilation.
  clang_tidy_check ? false,

  # Flags to pass to the C or C++ preprocessor.
  #
  # Type:
  #   [String]
  preprocessor_flags,

  # Flags to pass to the C compiler. Will only be used for files with the `.c` extension.
  #
  # Type:
  #   [String]
  cflags,

  # Flags to pass to the C++ compiler. Will be used for files other than with the `.c` extension.
  #
  # Type:
  #   [String]
  cppflags,
  # Command to use to link object files.
  #
  # Type:
  #   String
  #
  # Example:
  #   "$CC -v -o $out/bin/${name}"
  link_command,

  # Flags to pass to the linker.
  #
  # Type:
  #   [String]

  link_flags,

  # Additional attributes to pass to the underlying `stdenv.mkDerivation` when linking compiled modules.
  link_attributes,

  # Additional attributes to pass to the underlying `stdenv.mkDerivation` when compiling each module.
  compile_attributes,

  # Build an additional `debug` derivation output. See [](#stdenv-separateDebugInfo).
  #
  # [version script]: https://www.gnu.org/software/gnulib/manual/html_node/LD-Version-Scripts.html
  # TODO: is this default intended?
  separateDebugInfo ? true,
}: let

  sourceFiles = c2nix.splitSourceTree {
    inherit src;
    dependencyInfo = if dependencyInfo != null then dependencyInfo else
      # Import From Derivation!
      c2nix.dependencyInfo {
        inherit name src;
        compilerFlags = preprocessor_flags;
      };
  };

  objectFiles = lib.mapAttrs (name: linkSourceFiles:
    c2nix.compileModule {
      inherit
        name
        linkSourceFiles
        compile_attributes
        buildInputs
        preprocessor_flags
        cflags
        cppflags
        clang_tidy_check
        clang_tidy_args
        clang_tidy_config
        ;
    }
  ) sourceFiles;


  # TODO: this should be *a* parameter. Should it be *the* parameter?
  clang_tidy_checks = builtins.concatStringsSep "," [
    # Disable all checks and explicitly re-enable some.
    "-*"
    "bugprone-fold-init-type"
    "bugprone-implicit-widening-of-multiplication-result"
    "bugprone-macro-parentheses"
    "bugprone-narrrowing-conversions"
    "bugprone-suspicious-string-compare"
    "clang-analyzer-apiModeling.*"
    "clang-analyzer-core.NullDereference"
    "clang-analyzer-deadcode.*"
    "clang-analyzer-nullability.*"
    "clang-analyzer-security.*"
    "clang-analyzer-unix.*"
    "clang-analyzer-valist.*"
    "hicpp-use-emplace"
    "hicpp-noexcept-move"
    "modernize-raw-string-literal"
    "modernize-use-auto"
    "modernize-use-default-member-init"
    "modernize-use-emplace"
    "modernize-use-equals-default"
    "modernize-use-override"
    "modernize-loop-convert"
    "modernize-pass-by-value"
    "performance-faster-string-find"
    "performance-for-range-copy"
    "performance-inefficient-string-concatenation"
    "performance-inefficient-vector-operation"
    "performance-unnecessary-value-param"
    "readability-redundant-member-init"
  ];

  clang_tidy_args = "-checks='${clang_tidy_checks}' -warnings-as-errors='${clang_tidy_checks}'";

  clang_tidy_config = builtins.replaceStrings ["\n"] [" "] ''
    -config="{
        CheckOptions: [
            {
                key: performance-unnecessary-value-param.AllowedTypes,
                value: '^ref_ptr;'
            }
        ]
    }"'';
in
  stdenv.mkDerivation (link_attributes
    // {
      inherit name artifactName outputDir make_fhs_compatible;
      # TODO: don't hard-code phases
      phases =
        ["build" "postFixup"]
        ++ (
          if symbol_leakage_check || glibc_version_check
          then ["check"]
          else []
        );
      buildInputs = buildInputs;
      outputs =
        if separateDebugInfo
        then ["out" "debug"]
        else ["out"];

      build = ''
        # TODO: Escaping..?
        # TODO: Don't use toString on lists, implicit concatenation with " "
        echo -e "${link_command} ${toString (lib.attrValues objectFiles)} ${link_flags}"
        mkdir -p $out/$outputDir ${
          if separateDebugInfo
          then "$debug/$outputDir"
          else ""
        }
        ${link_command} ${toString (lib.attrValues objectFiles)} ${link_flags}
      '';

      check = ''
        true # TODO: check if this is necessary
        ${
          if symbol_leakage_check
          then ''
            echo "checking \`${artifactName}' for symbol leakage..."
            # TODO: What is "V _Z"??
            ! ${pkgs.binutils-unwrapped}/bin/nm -gD "$out/$outputDir/${artifactName}" | ${pkgs.gnugrep}/bin/grep "V _Z" > /dev/null
          ''
          else ""
        }
        ${
          if glibc_version_check
          then ''
            echo "checking \`${artifactName}' glibc version symbols..."
            SYMBOL_LIST=$(${glibc_version_symbols_internal "$out/$outputDir/${artifactName}"})
            function version { echo "$@" | ${pkgs.gawk}/bin/awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }'; }
            for sym_ver in $SYMBOL_LIST; do
                if [ $(version $sym_ver) -gt $(version "${max_glibc_version}") ]; then
                    echo "GLIBC version requirement too high (found version $sym_ver, allowing only up to ${max_glibc_version})"
                    exit 1
                fi
            done
          ''
          else ""
        }
      '';

      postFixup = ''
        true
        ${
          if separateDebugInfo
          then ''
            # TODO: check if this is a typical Nixpkgs thing to do, maybe reusable?
            objcopy --only-keep-debug "$out/$outputDir/${artifactName}" "$debug/$outputDir/${artifactName}.debug"
            strip --strip-debug --strip-unneeded "$out/$outputDir/${artifactName}"
            objcopy --add-gnu-debuglink="$debug/$outputDir/${artifactName}.debug" "$out/$outputDir/${artifactName}"
          ''
          else ""
        }
        # TODO: Maybe not reasonable for nixpkgs
        # TODO: check if we could repurpose Nix bundlers or otherwise split that out
        ${
          if make_fhs_compatible
          then "patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 $out/$outputDir/$artifactName"
          else ""
        }
      '';

      passthru = {
        # implementation stuff useful for repl use etc
        # TODO: check what's important to keep here
        inherit
          stdenv
          buildInputs
          dependencyInfo
          pkgs
          src
          objectFiles
          ;
      };
    })
