{
  lib,
  stdenv,
  jq,
}:
{
  derivation
}:
let

  # Fixed-output derivations may not reference other paths, which means that
  # for a fixed-output derivation, the corresponding inputDerivation should
  # *not* be fixed-output. To achieve this we simply delete the attributes that
  # would make it fixed-output.
  deleteFixedOutputRelatedAttrs = lib.flip removeAttrs [
    "outputHashAlgo"
    "outputHash"
    "outputHashMode"
  ];
in
# A derivation that always builds successfully and whose runtime
# dependencies are the original derivations build time dependencies
# This allows easy building and distributing of all derivations
# needed to enter a nix-shell with
#   nix-build shell.nix -A inputDerivation
# TODO: This now only works for structuredAttrs, fix it for the other case
derivation (
  deleteFixedOutputRelatedAttrs derivationArg
  // {
    name = "inputDerivation${lib.optionalString (derivationArg ? name) "-${derivationArg.name}"}";
    # This always only has one output
    outputs = [ "out" ];

    builder = stdenv.shell;

    # The builtin `declare -p` dumps all bash and environment variables,
    # which is where all build input references end up (e.g. $PATH for
    # binaries). By writing this to $out, Nix can find and register
    # them as runtime dependencies (since Nix greps for store paths
    # through $out to find them). Using placeholder for $out works with
    # and without structuredAttrs.
    # This build script does not use setup.sh or stdenv, to keep
    # the env most pristine. This gives us a very bare bones env,
    # hence the extra/duplicated compatibility logic and "pure bash" style.
    args = [
      "-c"
      /* bash */ ''
        set -euo pipefail
        PATH=${lib.makeBinPath stdenv.initialPath}
        source "$NIX_ATTRS_SH_FILE"

        out=''${outputs[out]}
        mkdir "$out"

        # cp without cp
        cp -v "$NIX_ATTRS_SH_FILE" "$out/attrs.sh"
        cp -v "$NIX_ATTRS_JSON_FILE" "$out/attrs.json"

        # TODO: If used with iptables, the resulting iptables binary does not actually run..
        ln -vs ${lib.escapeShellArg (builtins.toFile "reproduce.sh" ''
          #!${stdenv.shell}
          set -euo pipefail

          PATH=${lib.makeBinPath stdenv.initialPath}

          # TODO: Consider cleaning
          # TODO: Test buildDir too
          outputsDir=$(realpath "''${1:-$(mktemp -d)}")
          buildDir=$(realpath "''${2:-$(mktemp -d)}")
          cores=$(nproc)
          mkdir -p "$outputsDir"



          scriptDir=$(dirname -- "''${BASH_SOURCE[0]}")

          cat "$scriptDir/attrs.sh" - > "$buildDir/.attrs.sh" <<FOF
          declare name=${lib.escapeShellArg derivationArg.name}
          declare builder=${lib.escapeShellArg derivationArg.builder}
          declare -A outputs=(${lib.concatMapStringsSep " " (output: "[${output}]=$outputsDir/${output}") (derivationArg.outputs or [ "out" ])})
          FOF
          # TODO: Finish JSON mirroring

          # Separate script for the clean environment with -c
          exec -c bash "$scriptDir/.reproduce.sh" "$cores" "$buildDir"
        '')} "$out/reproduce.sh"

        ln -vs ${lib.escapeShellArg (builtins.toFile ".reproduce.sh" ''
          export HOME="/homeless-shelter"
          export PATH="/path-not-set"
          export NIX_ATTRS_SH_FILE=$2/.attrs.sh
          export NIX_ATTRS_JSON_FILE=$2/.attrs.json
          export NIX_BUILD_CORES=$1
          export NIX_BUILD_TOP=$2
          export NIX_LOG_FD="2"
          export NIX_STORE="${builtins.storeDir}"
          export TEMP="$2"
          export TEMPDIR="$2"
          export TMP="$2"
          export TMPDIR="$2"

          cd "$2"

          # TODO: Handle spaces in arguments, while still making sure that paths work
          exec "${derivationArg.builder}" ${lib.concatMapStringsSep " " (s: "${s}") derivationArg.args}
        '')} "$out/.reproduce.sh"

        chmod +x $out/reproduce.sh $out/.reproduce.sh
      ''
    ];
        #jq \
        #  --arg name ${lib.escapeShellArg derivationArg.name} '.name |= $name' $out/attrs.json > "$tmp/.attrs.json"
  }
  // (
    # inputDerivation produces the inputs; not the outputs, so any
    # restrictions on what used to be the outputs don't serve a purpose
    # anymore.
    if __structuredAttrs then
      {
        outputChecks = { };
      }
    else
      {
        allowedReferences = null;
        allowedRequisites = null;
        disallowedReferences = [ ];
        disallowedRequisites = [ ];
      }
  )
)
