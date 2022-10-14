{
jq,
writeShellScriptBin,
runCommandCC,
}:
{
name,
src,
includeInputs,
all_include_dirs,
preprocessor_flags,
}:
let
  include_path = toString (
    map (inc: "-I ${inc}") all_include_dirs
  );

  processFile = writeShellScriptBin "process" ''
    set -euo pipefail

    source_file=$1
    shift

    echo "$source_file" >> $modules
    json_file=$out/$source_file.json
    mkdir -p "$(dirname "$out/$source_file")"
    [[ $source_file =~ .*\.c$ ]] && COMPILER=$CC || COMPILER=$CXX

    echo "Processing $source_file with $COMPILER to $json_file" >&2

    # -M to output make rule of the files dependencies
    # -MM instead to not include system libraries, limits it to only the projects files
    # -MT to specify the make rule target string, let it be fixed because we don't need to know it
    $COMPILER -MM -MT fixed "$source_file" "$@" \
      | # Unescape makefile escapings \
      sed -z -f "$sedScriptPath" \
      | # Remove the first line containing "fixed:" \
      tail -n+2 \
      | # Sort and remove duplicates, which GCC apparently produces \
      sort -u \
      | # Turn lines into a JSON array \
      jq --raw-input -s 'rtrimstr("\n") | split("\n")' \
      > "$json_file"
  '';
# Dependency information - built at instantiation time!
in runCommandCC "${name}.depinfo" {

  # Note: these need to be separate outputs or else using nix to read the contents of the modules
  #  may (in nix circa 2.7) bring along the context of the dependencies of the other files
  #  which can cause a variety of problems without helping us any.
  # -- Lagoda (with Dave over my shoulder) 2022-03-22

  # out: one dependency info file per source file, containing Make rules
  # modules: file containing list of source files, one per line
  outputs = ["out" "modules"];

  nativeBuildInputs = [
    jq
    processFile
  ];

  # TODO: Still needed with -MM?
  buildInputs = includeInputs;

  passAsFile = [ "sedScript" ];

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
} ''
  mkdir $out
  touch $modules

  cd ${src}

  # TODO: Escaping of preprocessor_flags and include_path, both for shell and xargs
  find -L . -type f \( -name '*.c' -or -name '*.cpp' -or -name '*.cc' \) -print0 | sort -z \
    | xargs -0 -L1 -I{} -P "$NIX_BUILD_CORES" process {} ${preprocessor_flags} ${include_path}
''
