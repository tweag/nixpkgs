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
# TODO: Detect extra files in src that aren't a dependency of any module? These aren't too surprising (e.g. an include directory for a
# library that this program only uses part of) so I'm not sure it's worth it.
let
  include_path = toString (
    map (inc: "-I ${inc}") all_include_dirs
  );

  processFile = writeShellScriptBin "process" ''
    set -euo pipefail

    source_file=$1
    shift
    result_dir=$1
    shift

    mkdir -p "$(dirname "$result_dir/$source_file")"
    [[ $source_file =~ .*\.c$ ]] && COMPILER=$CC || COMPILER=$CXX

    echo "Determining file dependencies of $source_file with $COMPILER" >&2

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
      jq --raw-input -s --arg path "$source_file" '{ name: $path, dependencies: rtrimstr("\n") | split("\n") }' \
      > "$result_dir"/"$source_file.json"
  '';
# Dependency information - built at instantiation time!
in runCommandCC "${name}.depinfo" {

  nativeBuildInputs = [
    jq
    processFile
  ];

  # TODO: Still needed with -MM?
  buildInputs = includeInputs;

  passAsFile = [ "sedScript" ];

  # Undoes make rule escaping for a single rule, outputting all dependents on a single line
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
  results=$(mktemp -d)

  cd ${src}

  # TODO: Escaping of preprocessor_flags and include_path, both for shell and xargs
  find -L . -type f \( -name '*.c' -or -name '*.cpp' -or -name '*.cc' \) -print0 | sort -z \
    | xargs -0 -L1 -I{} -P "$NIX_BUILD_CORES" process {} "$results" ${preprocessor_flags} ${include_path}

  # Combine all resulting JSON files into a single one
  find "$results" -type f -print0 | xargs -0 cat | jq --slurp '.' > $out

''
