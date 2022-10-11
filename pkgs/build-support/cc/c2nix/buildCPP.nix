{
name,

# Source and/or include files, in the correct relative relationship.
# Automatically filtered for only .c, .cpp, .cc, .h, and .hpp files.
# The build takes place in the focus directory of src, so any flags that refer to paths are relative to that directory.
src,

# Include files from the same repo as src.  Automatically filtered for only .h and .hpp files and combined with src.
# The focus directory of each top-level entry in this array is made an include directory with `-I`.  (`reparent` if this is undesired)
includeSrc ? [],

# Relative to the source root
include_dirs ? [ "." ],

# The environment to use for the build
stdenv ? pkgs.stdenv,

# Derivations that provide include files, and therefore are dependencies of the dependency analysis step.
# TODO: If some derivations are produced by CPP builds, automatically add their headers to `includeSrc` instead to avoid unnecessary dependencies?
includeInputs,

# Derivations that are dependencies of the build (currently, both compile and link steps)
buildInputs,

# Subdirectory of $out and/or $debug to place artifacts in (e.g. "bin" or "lib")
outputDir,

# Basename of the final output artifact
artifactName,

# Sets the loader to the default location used on FHS systems, so that the resulting binary can run on non-NixOS systems.
make_fhs_compatible ? false,

# Checks that the final artifact does not publicly expose any C++ mangled symbol names (this is useful if you're trying to build
# a shared library written in C++, but exposing a pure C interface).
symbol_leakage_check ? false,

# Checks that none of the dependencies of the final artifact pull in glibc version symbols later than `max_glibc_version`.
glibc_version_check ? false,

# If 'glibc_version_check' is set, we will enforce that all glibc version symbols are older than this version.
#TODO Should we combine this and the above `glibc_version_check` parameter?
max_glibc_version ? "2.18.0",

# If true, runs the `clang-tidy` linter on all source files alongside compilation.
clang_tidy_check ? false,

preprocessor_flags,
cflags,
cppflags,
link_command,
link_flags,
link_attributes,
compile_attributes,
separateDebugInfo ? true,
glibc_version_symbols_internal,
splitStringRE,
}: let
    # Assemble a single nix store path with all of the source and includes for the entire build. build_dependency_info will depend
    #   on it, but individual compile steps will not (since it will change whenever anything changes)
    all_src = with sources;
        setName (name + "-source")
            (extend
                (sourceFilesBySuffices src [ ".c" ".cpp" ".h" ".hpp" ".cc" ".cxx" ])
                (map (s: sourceFilesBySuffices s [".h" ".hpp" ".hxx" ]) includeSrc));

    # Returns a relative path such that path == src + (getRelativePathFrom src path)
    # throws an error (via absolutePathComponentsBetween) if the *root* of path is not a prefix of src,
    #   but getRelativePathFrom will generate ../ components if they are already siblings in the same root
    #   (e.g. because src has already been extended with path)
    getRelativePathFrom = src: path:
        let
            clean_src = sources.cleanSourceWith { src=src; };
            clean_path = sources.cleanSourceWith { src=path; };
            relative_to_root = (filesystem.absolutePathComponentsBetween clean_src.origSrc clean_path.origSrc) ++ clean_path.subpath;
            get_relative = a: b:
                if a != [] && b != [] && builtins.head a == builtins.head b then
                    get_relative (builtins.tail a) (builtins.tail b)
                else
                    (map (_:"..") a) ++ b;
            relative_to_src = get_relative clean_src.subpath relative_to_root;
        in
            if relative_to_src!=[] then (lib.concatStringsSep "/" relative_to_src) else ".";

    all_include_dirs = lib.lists.unique
        ( map ( getRelativePathFrom all_src ) includeSrc ); # /nix/store/foo/bar/baz -> ../../foo/bar/baz

    # TODO: is this a no-op?
    # /nix/store/something -> . ?
    rel_path = sources.getSubpath all_src;

    build_dependency_info = import ./dependencyInfo.nix {
      inherit
        all_include_dirs
        preprocessor_flags
        # ...
    ;};

    # TODO: Detect extra files in all_src that aren't a dependency of any module? These aren't too surprising (e.g. an include directory for a
    # library that this program only uses part of) so I'm not sure it's worth it.
    # TODO: If not, could this just be done in Nix without going through a derivation?
    modules = splitStringRE "\n" (lib.strings.fileContents build_dependency_info.modules);

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
    clang_tidy_config = builtins.replaceStrings ["\n"]  [" "] ''
        -config="{
            CheckOptions: [
                {
                    key: performance-unnecessary-value-param.AllowedTypes,
                    value: '^ref_ptr;'
                }
            ]
        }"'';

    # Return a derivation that compiles the given module to an object file
    compile_module = import ./compileModule.nix {
      inherit
        all_include_dirs
        compile_attributes
        preprocessor_flags
      # ...
    ;};

    object_files = builtins.map compile_module modules;
in
    stdenv.mkDerivation (link_attributes // {
        inherit name artifactName outputDir make_fhs_compatible;
        # TODO: don't hard-code phases
        phases = ["build" "postFixup"] ++ (if symbol_leakage_check || glibc_version_check then ["check"] else []);
        buildInputs = buildInputs ++ includeInputs;
        outputs = if separateDebugInfo then [ "out" "debug" ] else [ "out" ];

        build = ''
            # TODO: Escaping..?
            # TODO: Don't use toString on lists, implicit concatenation with " "
            echo -e "${link_command} ${toString object_files} ${link_flags}"
            mkdir -p $out/$outputDir ${if separateDebugInfo then "$debug/$outputDir" else ""}
            ${link_command} ${toString object_files} ${link_flags}
        '';

        check = ''
            true # TODO: check if t
            ${if symbol_leakage_check then ''
                echo "checking \`${artifactName}' for symbol leakage..."
                # TODO: What is "V _Z"??
                ! ${pkgs.binutils-unwrapped}/bin/nm -gD "$out/$outputDir/${artifactName}" | ${pkgs.gnugrep}/bin/grep "V _Z" > /dev/null
            '' else ""}
            ${if glibc_version_check then ''
                echo "checking \`${artifactName}' glibc version symbols..."
                SYMBOL_LIST=$(${glibc_version_symbols_internal "$out/$outputDir/${artifactName}"})
                function version { echo "$@" | ${pkgs.gawk}/bin/awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }'; }
                for sym_ver in $SYMBOL_LIST; do
                    if [ $(version $sym_ver) -gt $(version "${max_glibc_version}") ]; then
                        echo "GLIBC version requirement too high (found version $sym_ver, allowing only up to ${max_glibc_version})"
                        exit 1
                    fi
                done
            '' else ""}
        '';

        postFixup = ''
            true
            ${if separateDebugInfo then ''
                # TODO: check if this is a typical Nixpkgs thing to do, maybe reusable?
                objcopy --only-keep-debug "$out/$outputDir/${artifactName}" "$debug/$outputDir/${artifactName}.debug"
                strip --strip-debug --strip-unneeded "$out/$outputDir/${artifactName}"
                objcopy --add-gnu-debuglink="$debug/$outputDir/${artifactName}.debug" "$out/$outputDir/${artifactName}"
            '' else ""}
            # TODO: Maybe not reasonable for nixpkgs
            # TODO: check if we could repurpose Nix bundlers or otherwise split that out
            ${if make_fhs_compatible then "patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 $out/$outputDir/$artifactName" else ""}
        '';

        passthru = {
          # implementation stuff useful for repl use etc
          # TODO: check what's important to keep here
          inherit
            stdenv
            includeInputs
            buildInputs
            modules
            build_dependency_info
            pkgs
            splitStringRE
            getRelativePathFrom
            src
            includeSrc
            all_src
            all_include_dirs
            get_module_source_dependencies
            link_module_dependencies
            compile_module
            object_files
        };
    });
