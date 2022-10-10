{
  lib,
  compile_attributes,
  buildInputs,
  includeInputs,
  preprocessor_flags,
  cflags,
  cppflags,
  include_path,
  splitStringRE,
  # Input from previous step
  build_dependency_info,

  # For clang-tidy
  clang-tools,
  llvmPackages_13,
  clang_tidy_check,
  clang_tidy_args,
  clang_tidy_config,
}:
name:
let
    # Return a list of relative paths to files in all_src that the given module build depends on, by reading the .d file from
    # the dependency build and filtering the dependencies that are relative paths (as opposed to paths in the nix store)
    # TODO: where does it even find Nix store paths?
    # TODO: At derivation build time, output a different format, e.g. JSON, so we don't need to do parsing in Nix
    get_module_source_dependencies =
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
      "ln -s ${origin_path dep} ${dep}"
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
    name = "${builtins.baseNameOf name}.o";
    buildInputs = buildInputs ++ includeInputs;
    # TODO: don't hard-code phases
    phases =  ["build"] ++ (if clang_tidy_check && !is_c then ["check"] else []);
    build = ''
    mkdir -p source/${rel_path}
    cd source/${rel_path}
    ${link_module_dependencies}
    ${if is_c then "$CC" else "$CXX"} -c ${name} ${preprocessor_flags} ${if is_c then cflags else cppflags} ${include_path} -o $out
    '';
    # TODO: This depends on clang_tidy even when this phase isn't ran in the end
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
})
