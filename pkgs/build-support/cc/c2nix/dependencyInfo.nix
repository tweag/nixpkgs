/*
TODO: Output JSON instead of .d file
*/
{
stdenv,
}:
{
name,
src,
includeInputs,
all_include_dirs,
preprocessor_flags,
}:
let
  all_src = src;

  include_path = toString (
      map (inc: "-I ${inc}") all_include_dirs
  );
in
# Dependency information - built at instantiation time!
stdenv.mkDerivation {
    name = "${name}.depinfo";

    # TODO: can we use `src` and `unpack = false`?
    inherit all_src;

    buildInputs = includeInputs;

    phases = ["build"];

    # Note: these need to be separate outputs or else using nix to read the contents of the modules
    #  may (in nix circa 2.7) bring along the context of the dependencies of the other files
    #  which can cause a variety of problems without helping us any.
    # -- Lagoda (with Dave over my shoulder) 2022-03-22

    # out: one dependency info file per source file, containing Make rules
    # modules: file containing list of source files, one per line
    outputs = ["out" "modules"];

    build = ''
        mkdir $out
        cd $all_src
        PIDS=()
        while IFS= read -r -d $'\0' source_file; do
            echo "$source_file" >> $modules
            dep_file=$out/$source_file.d
            dep_dir=''${dep_file%/*}
            mkdir -p "$dep_dir"
            [[ $source_file =~ .*\.c$ ]] && COMPILER=$CC || COMPILER=$CXX

            # -M to output make rule of the files dependencies
            # -MF to specify the file to output to
            # -MT to specify the make rule target string, let it be fixed because we don't need to know it
            $COMPILER -M -MF "$dep_file" -MT fixed ${preprocessor_flags} ${include_path} "$source_file" &
            # TODO: Maybe use -MG?
            # -MG In conjunction with an option such as -M requesting
            # dependency generation, -MG assumes missing header files are
            # generated files and adds them to the dependency list without
            # raising an error.  The dependency filename is taken directly from
            # the "#include" directive without prepending any path.

            PIDS+=($!)
        done < <(find -L . -type f \( -name '*.c' -or -name '*.cpp' -or -name '*.cc' \) -print0 | sort -z)
        # TODO: Use NIX_BUILD_CORES
        wait ''${PIDS[@]}
    '';
}
