/*
TODO: Output JSON instead of .d file
*/
{
stdenv,
jq,
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

    passAsFile = [ "sedScript" ];

    nativeBuildInputs = [
      jq
    ];

    sedScript = ''
      # `make` wraps lines with "\", adding extra spaces around it, separating entries
      s/ \\\n /\n/g
      # On smaller lines, entries are separated by " ", make those newlines too
      s/ /\n/g
      # But now we also replaced "\ " with newlines, which `make` uses to escape " ", so undo those!
      s/\\\n/ /g
      # `make` escapes "#" with "\#"
      s/\\#/#/g
      # And "%" with "%%"
      s/%%/%/g
      # Similarly "$" with "$$"
      s/\$\$/$/g
    '';

    build = ''
        mkdir $out
        cd $all_src
        PIDS=()
        while IFS= read -r -d $'\0' source_file; do
            echo "$source_file" >> $modules
            json_file=$out/$source_file.json
            mkdir -p "$(dirname "$out/$source_file")"
            [[ $source_file =~ .*\.c$ ]] && COMPILER=$CC || COMPILER=$CXX

            {
              # -M to output make rule of the files dependencies
              # -MM instead to not include system libraries, limits it to only the projects files
              # -MT to specify the make rule target string, let it be fixed because we don't need to know it
              $COMPILER -MM -MT fixed ${preprocessor_flags} ${include_path} "$source_file" \
                | # Unescape makefile escapings \
                sed -z -f "$sedScriptPath" \
                | # Remove the first line containing "fixed:" \
                tail -n+2 \
                | # Sort and remove duplicates, which GCC apparently produces \
                sort -u \
                | # Turn lines into a JSON array \
                jq --raw-input -s 'rtrimstr("\n") | split("\n")' \
                > "$json_file"
            } &
            # TODO: Maybe use -MG?
            # -MG In conjunction with an option such as -M requesting
            # dependency generation, -MG assumes missing header files are
            # generated files and adds them to the dependency list without
            # raising an error.  The dependency filename is taken directly from
            # the "#include" directive without prepending any path.

            PIDS+=($!)
        done < <(find -L . -type f \( -name '*.c' -or -name '*.cpp' -or -name '*.cc' \) -print0 | sort -z)
        # TODO: Use NIX_BUILD_CORES
        # TODO: Fail if any background process fails
        wait ''${PIDS[@]}
    '';
}
