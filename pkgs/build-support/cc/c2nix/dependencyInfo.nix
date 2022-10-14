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
        for source_file in $(find -L . -type f \( -name '*.c' -or -name '*.cpp' -or -name '*.cc' \) -print | sort); do
            echo $source_file >> $modules
            dep_file=$out/$source_file.d
            dep_dir=''${dep_file%/*}
            mkdir -p "$dep_dir"
            [[ $source_file =~ .*\.c$ ]] && COMPILER=$CC || COMPILER=$CXX

            # -M  Instead of outputting the result of
            # preprocessing, output a rule suitable for make
            # describing the dependencies of the main source file.
            # The preprocessor
            # outputs one make rule containing the object file name for
            # that source file, a colon, and the names of all the included
            # files, including those coming from -include or -imacros
            # command-line options
            $COMPILER -M ${preprocessor_flags} ${include_path} $source_file > $dep_file &
            PIDS+=($!)
        done
        # TODO: Use NIX_BUILD_CORES
        wait ''${PIDS[@]}
    '';
}
