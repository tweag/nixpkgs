{ pkgs, lib, ... }:

{
  name = "util-linux";
  meta = with pkgs.lib.maintainers; {
    maintainers = [
      balsoft
      joaosreis
    ];
  };

  nodes.machine =
    { ... }:
    let
      util-linux-with-check = pkgs.util-linux.overrideAttrs (_: {
        nativeCheckInputs = [
          pkgs.e2fsprogs
          pkgs.systemd
          pkgs.util-linux
          pkgs.which
        ];

        preCheck = ''
          patchShebangs tests

          sed -i "s|#!/bin/bash|#!${pkgs.bash}/bin/bash|" tests/ts/mount/special

          sed -i "s|/bin/false|${lib.getExe' pkgs.coreutils "false"}|" tests/helpers/test_enosys.c

          make check-programs
        '';
        checkPhase = ''
          runHook preCheck

          exclude=(
            # su is not built
            su/shell
          )
          ./tests/run.sh \
            --show-diff \
            --use-system-commands \
            --exclude="''${exclude[*]}"
          runHook postCheck
        '';
        doCheck = true;

        # Save some resources by not installing
        dontInstall = true;
        dontFixup = true;
        dontBuild = true;
      });
    in
    {
      networking.useDHCP = false;

      networking.interfaces = lib.mkForce { };

      environment.systemPackages = [
        (pkgs.writeShellScriptBin "util-linux-test" ''
          source ${util-linux-with-check.inputDerivation}
          ${lib.getExe' pkgs.coreutils "mkdir"} -p "$NIX_BUILD_TOP"
          cd "$PWD"
          # Run the derivation build
          exec "$_derivation_original_builder" $_derivation_original_args
        '')
      ];

      virtualisation.memorySize = 4096;
      # virtualisation.cores >= 2 needed for chrt tests
      virtualisation.cores = 2;

      users = {
        enforceIdUniqueness = false;

        users = {
          user1 = {
            uid = 1;
            group = "user1";
          };
          user2 = {
            uid = 2;
            group = "user2";
          };
        };

        groups = {
          user1.gid = 1;
          user2.gid = 2;
        };
      };
    };

  testScript = ''
    start_all()

    machine.wait_for_unit("multi-user.target")

    # needed for mount/special tests
    machine.succeed("mkdir /sbin")

    machine.succeed("systemd-cat -t TEST -p notice util-linux-test")
  '';
}
