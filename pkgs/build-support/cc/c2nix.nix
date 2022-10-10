# TODO: makeOverridable

{
    pkgs,
    # TODO drop this when it's in nixpkgs main
    sourcesLib ? (import ./pinned_nixpkgs.nix).sources
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

            # Derivations that provide include files, and therefore are dependencies of the dependency analysis step.
            includeInputs,

            # Derivations that are dependencies of the build (currently, both compile and link steps)
            buildInputs,

            # This sets the loader to use the default FHS location and checks that no "too new" glibc version is required.
            # Useful for when you want to build software that will run on non-NixOS systems.
            make_redistributable ? true,

            # If true, runs the `clang-tidy` linter on all source files alongside compilation.
            clang_tidy_check ? false,

            preprocessor_flags,
            cflags,
            cppflags,
            link_flags,
            link_attributes,
            compile_attributes ? {},
        }: buildCPP {
            inherit name src includeSrc stdenv includeInputs buildInputs preprocessor_flags cflags cppflags compile_attributes link_attributes clang_tidy_check;
            make_fhs_compatible = make_redistributable;
            glibc_version_check = make_redistributable;
            outputDir = "bin";
            artifactName = name;
            link_command = ''
                $CC -v -o $out/bin/${name}'';
            inherit link_flags;
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

            # Derivations that provide include files, and therefore are dependencies of the dependency analysis step.
            includeInputs,

            # Derivations that are dependencies of the build (currently, both compile and link steps)
            buildInputs,

            # If true, runs the `clang-tidy` linter on all source files alongside compilation.
            clang_tidy_check ? false,

            preprocessor_flags,
            cflags,
            cppflags,
            compile_attributes ? {},
        }: buildCPP rec {
            inherit name src includeSrc stdenv includeInputs buildInputs preprocessor_flags cflags cppflags compile_attributes clang_tidy_check;
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

            # Derivations that provide include files, and therefore are dependencies of the dependency analysis step.
            includeInputs,

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
            inherit name src includeSrc stdenv includeInputs buildInputs preprocessor_flags cflags cppflags compile_attributes clang_tidy_check link_attributes symbol_leakage_check separateDebugInfo;
            make_fhs_compatible = false;
            glibc_version_check = make_redistributable;
            outputDir = "lib";
            artifactName = "lib${name}.so";
            link_command = ''
                $CC -o $out/lib/lib${name}.so'';
            link_flags = "${link_flags} -shared" + (if version_script!=null then " -Wl,--version-script=" + version_script else "");
        };

    buildCPP =
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
            separateDebugInfo ? true
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
                ( map ( getRelativePathFrom all_src ) includeSrc );

            rel_path = sources.getSubpath all_src;

            # The origin path (typically in the repo, outside the nix store) corresponding to the subpath, rather than the hidden true root, of all_src
            srcOrigin = sources.getOriginalFocusPath all_src;

            # TODO: Since we pass all include dirs to the compiler in the compilation derivations, any change to the include path requires rebuilding everything.
            # We could use the full include path only in the build_dependency_info derivation, and compute the required subset of it for each compilation step.
            include_path = toString (
                map (inc: "-I ${inc}") all_include_dirs
            );

            # Dependency information - built at instantiation time!
            build_dependency_info = stdenv.mkDerivation {
                name = "${name}.depinfo";

                inherit all_src;

                buildInputs = includeInputs;

                phases = ["build"];

                # Note: these need to be separate outputs or else using nix to read the contents of the modules
                #  may (in nix circa 2.7) bring along the context of the dependencies of the other files
                #  which can cause a variety of problems without helping us any.
                # -- Lagoda (with Dave over my shoulder) 2022-03-22
                outputs = ["out" "modules"];

                build = ''
                    mkdir $out
                    cd $all_src
                    PIDS=()
                    for source_file in $(find -L . -type f \( -name '*.c' -or -name '*.cpp' -or -name '*.cc' \) -print | sort); do
                        echo $source_file >> $modules
                        dep_file=$out/$source_file.d
                        dep_dir=''${dep_file%/*}
                        mkdir -p "$dep_dir"
                        [[ $source_file =~ .*\.c$ ]] && COMPILER=$CC || COMPILER=$CXX
                        $COMPILER -M ${preprocessor_flags} ${include_path} $source_file > $dep_file &
                        PIDS+=($!)
                    done
                    wait ''${PIDS[@]}
                '';
            };

            # TODO: Detect extra files in all_src that aren't a dependency of any module? These aren't too surprising (e.g. an include directory for a
            # library that this program only uses part of) so I'm not sure it's worth it.
            modules = splitStringRE "\n" (lib.strings.fileContents build_dependency_info.modules);

            # Return a list of relative paths to files in all_src that the given module build depends on, by reading the .d file from
            # the dependency build and filtering the dependencies that are relative paths (as opposed to paths in the nix store)
            get_module_source_dependencies = name:
                let
                    raw_dependencies = builtins.tail (splitStringRE "[ \\\n]+" (builtins.readFile "${build_dependency_info}/${name}.d"));
                    relative_paths = item:
                        let
                            match = builtins.match "([^/].*)" item;  # Match only relative paths, which require copies
                        in
                            if match == null then
                                []
                            else
                                [ (builtins.elemAt match 0) ];
                in
                    # The unique seems unnecessary at least the vast majority of the time with clang's preprocessor, but we immediately found
                    # a duplicated dependency when using GCC
                    lib.lists.unique (lib.lists.concatMap relative_paths raw_dependencies);

            # Return bash code to link each source dependency of the given module into a (relative) location in the current directory
            # Dependencies on e.g. includeInputs will appear in the .d file as /nix/store paths and be filtered out by get_module_source_dependencies.
            #   We don't need special handling for them - they will also be available at compile time, and if their derivations change
            #   everything will be rebuilt.
            # But we don't want a dependency on the whole `all_src` - that would prevent incremental builds. Instead we take a dependency on
            #   the relevant individual source files by (symbolic) linking them into the current directory in the compile step.
            # This requires converting the relative path (originally in the `all_src` /nix/store path) back into an origin path.
            link_module_dependencies = name:
                let
                    dependencies = get_module_source_dependencies name;
                    origin_path = dep: srcOrigin + ("/" + dep);
                    dirs = lib.lists.unique (map builtins.dirOf dependencies);
                in
                    if (builtins.length dependencies) == 0 then
                        throw "Module ${name}: no source dependencies detected!"   # This is almost certainly a bug, since it must at least depend on its own source file
                    else
                        ''
                            mkdir -p ${ toString dirs }
                            ${
                                lib.strings.concatMapStringsSep "\n" (dep:
                                    "ln -s ${origin_path dep} ${dep}"
                                ) dependencies
                            }
                        '';

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
            compile_module = name:
                let
                    is_c = lib.strings.hasSuffix ".c" name;
                    # We need to tell clang-tidy to use use headers from libc++ instead of GCC's stdc++ that Nix inexplicably defaults to.
                    clang_tools_with_libcxx = pkgs.clang-tools.overrideAttrs
                        (old: { clang = pkgs.llvmPackages_13.libcxxClang; });
                    in
                    stdenv.mkDerivation (compile_attributes // {
                        # The Nix compiler wrappers enable "source fortification" which is a glibc feature that is *documented* as
                        # sometimes transforming correct programs into incorrect ones. We turn that off.
                        hardeningDisable = [ "fortify" ];
                        name = "${builtins.baseNameOf name}.o";
                        buildInputs = buildInputs ++ includeInputs;
                        phases =  ["build"] ++ (if clang_tidy_check && !is_c then ["check"] else []);
                        build = ''
                            mkdir -p source/${rel_path}
                            cd source/${rel_path}
                            ${link_module_dependencies name}
                            ${if is_c then "$CC" else "$CXX"} -c ${name} ${preprocessor_flags} ${if is_c then cflags else cppflags} ${include_path} -o $out
                        '';
                        check = ''
                            ${clang_tools_with_libcxx}/bin/clang-tidy \
                                ${clang_tidy_args} \
                                ${clang_tidy_config} \
                                --use-color \
                                --quiet \
                                ${name} \
                                -- \
                                ${preprocessor_flags} \
                                ${cppflags} \
                                ${include_path}'';
                    });

            object_files = builtins.map compile_module modules;
        in
            stdenv.mkDerivation (link_attributes // {
                inherit name artifactName outputDir make_fhs_compatible;
                phases = ["build" "postFixup"] ++ (if symbol_leakage_check || glibc_version_check then ["check"] else []);
                buildInputs = buildInputs ++ includeInputs;
                outputs = if separateDebugInfo then [ "out" "debug" ] else [ "out" ];

                build = ''
                    echo -e "${link_command} ${toString object_files} ${link_flags}"
                    mkdir -p $out/$outputDir ${if separateDebugInfo then "$debug/$outputDir" else ""}
                    ${link_command} ${toString object_files} ${link_flags}
                '';

                check = ''
                    true
                    ${if symbol_leakage_check then ''
                        echo "checking \`${artifactName}' for symbol leakage..."
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
                        objcopy --only-keep-debug "$out/$outputDir/${artifactName}" "$debug/$outputDir/${artifactName}.debug"
                        strip --strip-debug --strip-unneeded "$out/$outputDir/${artifactName}"
                        objcopy --add-gnu-debuglink="$debug/$outputDir/${artifactName}.debug" "$out/$outputDir/${artifactName}"
                    '' else ""}
                    ${if make_fhs_compatible then "patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 $out/$outputDir/$artifactName" else ""}
                '';

                passthru = {
                    # implementation stuff useful for repl use etc
                    inherit stdenv includeInputs buildInputs modules build_dependency_info pkgs splitStringRE getRelativePathFrom src includeSrc all_src all_include_dirs get_module_source_dependencies link_module_dependencies compile_module object_files;
                };
            });
}
