{ lib }:
let
  releaseParts =
    let
      m = builtins.match "([0-9]+)\\.([0-9]+)" lib.trivial.release;
    in
    if m == null then
      throw "Invalid release"
    else
      {
        year = 2000 + lib.toIntBase10 (lib.elemAt m 0);
        month = lib.toIntBase10 (lib.elemAt m 1);
      };

  x = lib.mapAttrs' (componentName: _:
    let
      name = lib.removeSuffix ".nix" componentName;
      imported = import (lib.path.append ./features componentName) { inherit lib; };

      introducedParts =
        let
          m = builtins.match "([0-9]+)-([0-9]+)-([0-9]+)" imported.introduced;
        in
        if m == null then
          throw "Invalid date"
        else
          {
            year = lib.toIntBase10 (lib.elemAt m 0);
            month = lib.toIntBase10 (lib.elemAt m 1);
          };

      # The number of months since it was introduced in unstable
      availableMonths =
        12 * (releaseParts.year - introducedParts.year)
        + (releaseParts.month - introducedParts.month);

      # Release at 2020-01, introduced 2020-02
      # Until next release at 2020-07, months is 5       id
      # Until next release at 2021-01, months is 11      id
      # Until next release at 2021-07, months is 17      warn
      # Until next release at 2022-01, months is 23      warn

      # Release at 2020-01, introduced 2020-07
      # Until next release at 2020-07, months is 0       id
      # Until next release at 2021-01, months is 6       id
      # Until next release at 2021-07, months is 12      warn
      # Until next release at 2022-01, months is 18      warn

      # id if months < 12
      # warn if months < 24
      # throw if more
      phase =
        if availableMonths < 12 then
          "id"
        else if availableMonths < 24 then
          "warn"
        else
          "throw";

      value = availableMonths;
    in
    lib.nameValuePair name {
      inherit availableMonths imported;
    }
  ) (builtins.readDir ./features);
in
x
