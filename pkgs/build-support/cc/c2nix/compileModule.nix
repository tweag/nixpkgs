{
  stdenv,
  splitStringRE,
  sources,
  llvmPackages_13,
  lib,
  clang-tools,
}:
{
  all_src,
  rel_path,
  compile_attributes,
  buildInputs,
  includeInputs,
  preprocessor_flags,
  cflags,
  cppflags,
  all_include_dirs,
  # Input from previous step
  build_dependency_info,

  # For clang-tidy
  clang_tidy_check,
  clang_tidy_args,
  clang_tidy_config,
}:
name:
let

    # TODO: Since we pass all include dirs to the compiler in the compilation derivations, any change to the include path requires rebuilding everything.
    # TODO: Filter only the include directories required for each module
    include_path = toString (
        map (inc: "-I ${inc}") all_include_dirs
    );

    get_module_source_dependencies = lib.importJSON (build_dependency_info + "/${name}.json");

    # The origin path (typically in the repo, outside the nix store) corresponding to the subpath, rather than the hidden true root, of all_src
    srcOrigin = sources.getOriginalFocusPath all_src;

    # Return bash code to symlink each source dependency of the given module into a (relative) location in the current directory
    # Dependencies on e.g. includeInputs will appear in the .d file as /nix/store paths and be filtered out by get_module_source_dependencies.
    #   We don't need special handling for them - they will also be available at compile time, and if their derivations change
    #   everything will be rebuilt.
    # But we don't want a dependency on the whole `all_src` - that would prevent incremental builds. Instead we take a dependency on
    #   the relevant individual source files by (symbolic) linking them into the current directory in the compile step.
    # This requires converting the relative path (originally in the `all_src` /nix/store path) back into an origin path.
    link_module_dependencies =
    let
      dependencies = get_module_source_dependencies;
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
      "ln -s ${builtins.path { path = origin_path dep; name = "source"; }} ${lib.escapeShellArg dep}"
      ) dependencies
    }
    '';
    # We need to tell clang-tidy to use use headers from libc++ instead of GCC's stdc++ that Nix inexplicably defaults to.
    clang_tools_with_libcxx = clang-tools.overrideAttrs
      (old: { clang = llvmPackages_13.libcxxClang; });

    is_c = lib.strings.hasSuffix ".c" name;

in
stdenv.mkDerivation (compile_attributes // {
    # The Nix compiler wrappers enable "source fortification" which is a glibc feature that is *documented* as
    # sometimes transforming correct programs into incorrect ones. We turn that off.
    hardeningDisable = [ "fortify" ];
    name = lib.strings.sanitizeDerivationName "${builtins.baseNameOf name}.o";
    buildInputs = buildInputs ++ includeInputs;
    # TODO: don't hard-code phases
    phases =  ["build"] ++ (if clang_tidy_check && !is_c then ["check"] else []);
    build = ''
    mkdir -p source/${lib.escapeShellArg rel_path}
    cd source/${lib.escapeShellArg rel_path}
    ${link_module_dependencies}
    ${if is_c then "$CC" else "$CXX"} -c ${lib.escapeShellArg name} ${preprocessor_flags} ${if is_c then cflags else cppflags} ${include_path} -o $out
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
    ${preprocessor_flags} \
    ${cppflags} \
    ${include_path}'';
})
