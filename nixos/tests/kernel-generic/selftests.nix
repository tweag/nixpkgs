args: linuxPackages:
(import ../make-test-python.nix (
  { pkgs, lib, ... }:
  let
    kernelTests = linuxPackages.kernel.overrideAttrs (old: {
      dontInstall = true;
      dontFixup = true;

      doCheck = true;

      checkTarget = "kselftest";

      checkInputs = with pkgs; [
        liburing
        libnl
        bpftrace
        libcap
      ];

      preCheck = ''
        patchShebangs ../tools/testing/selftests
      '';
    });
  in
  {
    name = "kernel-${linuxPackages.kernel.version}-selftests";
    meta = with pkgs.lib.maintainers; {
      maintainers = [
        joaosreis
      ];
    };

    nodes.machine =
      { config, ... }:
      {
        boot.kernelPackages = linuxPackages;

        # Building the kernel and its selftests in-VM needs far more resources
        # than the test defaults provide (the defaults overflow the disk/RAM
        # during unpackPhase, causing "No space left on device").
        virtualisation = {
          diskSize = 32 * 1024; # MB
          memorySize = 16 * 1024; # MB
          cores = 8;
        };

        environment.systemPackages = [
          (pkgs.writeShellScriptBin "run-kernel-selftests" ''
            # Restore the kernel build environment. Because the kernel uses
            # __structuredAttrs, these are plain (non-exported) shell variables,
            # so we must run the build in this same shell rather than exec'ing a
            # fresh builder (which would lose them, leaving e.g. $stdenv empty).
            source ${kernelTests.inputDerivation}
            ${lib.getExe' pkgs.coreutils "mkdir"} -p "$NIX_BUILD_TOP"
            cd "$NIX_BUILD_TOP"
            # Run the derivation build in-process (mirrors source-stdenv.sh)
            source "$stdenv/setup"
            genericBuild
          '')
          pkgs.systemd
        ];
      };

    testScript = ''
      machine.succeed("systemd-cat -t TEST -p notice run-kernel-selftests")
    '';
  }
) args)
