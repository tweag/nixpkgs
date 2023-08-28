{ lib }:
{
  latestKnownNixOSChannelInfo = lib.importJSON ./pin.json;

  latestKnownNixOSChannel = fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/tarball/${lib.channel.latestKnownNixOSChannelInfo.rev}";
    sha256 = lib.channel.latestKnownNixOSChannelInfo.sha256;
  };
}
