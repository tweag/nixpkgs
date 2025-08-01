# X Window System {#sec-x11}

The X Window System (X11) provides the basis of NixOS' graphical user
interface. It can be enabled as follows:

```nix
{ services.xserver.enable = true; }
```

The X server will automatically detect and use the appropriate video
driver from a set of X.org drivers (such as `vesa` and `intel`). You can
also specify a driver manually, e.g.

```nix
{ services.xserver.videoDrivers = [ "r128" ]; }
```

to enable X.org's `xf86-video-r128` driver.

You also need to enable at least one desktop or window manager.
Otherwise, you can only log into a plain undecorated `xterm` window.
Thus you should pick one or more of the following lines:

```nix
{
  services.xserver.desktopManager.plasma5.enable = true;
  services.xserver.desktopManager.xfce.enable = true;
  services.desktopManager.gnome.enable = true;
  services.xserver.desktopManager.mate.enable = true;
  services.xserver.windowManager.xmonad.enable = true;
  services.xserver.windowManager.twm.enable = true;
  services.xserver.windowManager.icewm.enable = true;
  services.xserver.windowManager.i3.enable = true;
  services.xserver.windowManager.herbstluftwm.enable = true;
}
```

NixOS's default *display manager* (the program that provides a graphical
login prompt and manages the X server) is LightDM. You can select an
alternative one by picking one of the following lines:

```nix
{
  services.displayManager.sddm.enable = true;
  services.displayManager.gdm.enable = true;
}
```

You can set the keyboard layout (and optionally the layout variant):

```nix
{
  services.xserver.xkb.layout = "de";
  services.xserver.xkb.variant = "neo";
}
```

The X server is started automatically at boot time. If you don't want
this to happen, you can set:

```nix
{ services.xserver.autorun = false; }
```

The X server can then be started manually:

```ShellSession
# systemctl start display-manager.service
```

On 64-bit systems, if you want OpenGL for 32-bit programs such as in
Wine, you should also set the following:

```nix
{ hardware.graphics.enable32Bit = true; }
```

## Auto-login {#sec-x11-auto-login}

The x11 login screen can be skipped entirely, automatically logging you
into your window manager and desktop environment when you boot your
computer.

This is especially helpful if you have disk encryption enabled. Since
you already have to provide a password to decrypt your disk, entering a
second password to login can be redundant.

To enable auto-login, you need to define your default window manager and
desktop environment. If you wanted no desktop environment and i3 as your
your window manager, you'd define:

```nix
{ services.displayManager.defaultSession = "none+i3"; }
```

Every display manager in NixOS supports auto-login, here is an example
using lightdm for a user `alice`:

```nix
{
  services.xserver.displayManager.lightdm.enable = true;
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "alice";
}
```

## Running X without a display manager  {#sec-x11-startx}

It is possible to avoid a display manager entirely and starting the X server
manually from a virtual terminal. Add to your configuration:
```nix
{
  services.xserver.displayManager.startx = {
    enable = true;
    generateScript = true;
  };
}
```
then you can start the X server with the `startx` command.

The second option will generate a base `xinitrc` script that will run your
window manager and set up the systemd user session.
You can extend the script using the
[extraCommands](#opt-services.xserver.displayManager.startx.extraCommands)
option, for example:
```nix
{
  services.xserver.displayManager.startx = {
    generateScript = true;
    extraCommands = ''
      xrdb -load .Xresources
      xsetroot -solid '#666661'
      xsetroot -cursor_name left_ptr
    '';
  };
}
```
or, alternatively, you can write your own from scratch in `~/.xinitrc`.

In this case, remember you're responsible for starting the window manager, for
example:
```shell
sxhkd &
bspwm &
```
and if you have enabled some systemd user service, you will probably want to
also add these lines too:
```shell
# import required env variables from the current shell
systemctl --user import-environment DISPLAY XDG_SESSION_ID
# start all graphical user services
systemctl --user start nixos-fake-graphical-session.target
# start the user dbus daemon
dbus-daemon --session --address="unix:path=/run/user/$(id -u)/bus" &
```

## Intel Graphics drivers {#sec-x11--graphics-cards-intel}

The default and recommended driver for Intel Graphics in X.org is `modesetting`
(included in the xorg-server package itself).
This is a generic driver which uses the kernel [mode
setting](https://en.wikipedia.org/wiki/Mode_setting) (KMS) mechanism, it
supports Glamor (2D graphics acceleration via OpenGL) and is actively
maintained, it may perform worse in some cases (like in old chipsets).

There is a second driver, `intel` (provided by the xf86-video-intel package),
specific to older Intel iGPUs from generation 2 to 9. It is not recommended by
most distributions: it lacks several modern features (for example, it doesn't
support Glamor) and the package hasn't been officially updated since 2015.

Third generation and older iGPUs (15-20+ years old) are not supported by the
`modesetting` driver (X will crash upon startup). Thus, the `intel` driver is
required for these chipsets.
Otherwise, the results vary depending on the hardware, so you may have to try
both drivers. Use the option
[](#opt-services.xserver.videoDrivers)
to set one. The recommended configuration for modern systems is:

```nix
{ services.xserver.videoDrivers = [ "modesetting" ]; }
```
::: {.note}
The `modesetting` driver doesn't currently provide a `TearFree` option (this
will become available in an upcoming X.org release), So, without using a
compositor (for example, see [](#opt-services.picom.enable)) you will
experience screen tearing.
:::

If you experience screen tearing no matter what, this configuration was
reported to resolve the issue:

```nix
{
  services.xserver.videoDrivers = [ "intel" ];
  services.xserver.deviceSection = ''
    Option "DRI" "2"
    Option "TearFree" "true"
  '';
}
```

Note that this will likely downgrade the performance compared to
`modesetting` or `intel` with DRI 3 (default).

## Proprietary NVIDIA drivers {#sec-x11-graphics-cards-nvidia}

NVIDIA provides a proprietary driver for its graphics cards that has
better 3D performance than the X.org drivers. It is not enabled by
default because it's not free software. You can enable it as follows:

```nix
{ services.xserver.videoDrivers = [ "nvidia" ]; }
```

If you have an older card, you may have to use one of the legacy drivers:

```nix
{
  hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.legacy_470;
  hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.legacy_390;
  hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.legacy_340;
}
```

You may need to reboot after enabling this driver to prevent a clash
with other kernel modules.

## Touchpads {#sec-x11-touchpads}

Support for Synaptics touchpads (found in many laptops such as the Dell
Latitude series) can be enabled as follows:

```nix
{ services.libinput.enable = true; }
```

The driver has many options (see [](#ch-options)).
For instance, the following disables tap-to-click behavior:

```nix
{ services.libinput.touchpad.tapping = false; }
```

Note: the use of `services.xserver.synaptics` is deprecated since NixOS
17.09.

## GTK/Qt themes {#sec-x11-gtk-and-qt-themes}

GTK themes can be installed either to user profile or system-wide (via
`environment.systemPackages`). To make Qt 5 applications look similar to
GTK ones, you can use the following configuration:

```nix
{
  qt.enable = true;
  qt.platformTheme = "gtk2";
  qt.style = "gtk2";
}
```

## Custom XKB layouts {#custom-xkb-layouts}

It is possible to install custom [ XKB
](https://en.wikipedia.org/wiki/X_keyboard_extension) keyboard layouts
using the option `services.xserver.xkb.extraLayouts`.

As a first example, we are going to create a layout based on the basic
US layout, with an additional layer to type some greek symbols by
pressing the right-alt key.

Create a file called `us-greek` with the following content (under a
directory called `symbols`; it's an XKB peculiarity that will help with
testing):

```
xkb_symbols "us-greek"
{
  include "us(basic)"            // includes the base US keys
  include "level3(ralt_switch)"  // configures right alt as a third level switch

  key <LatA> { [ a, A, Greek_alpha ] };
  key <LatB> { [ b, B, Greek_beta  ] };
  key <LatG> { [ g, G, Greek_gamma ] };
  key <LatD> { [ d, D, Greek_delta ] };
  key <LatZ> { [ z, Z, Greek_zeta  ] };
};
```

A minimal layout specification must include the following:

```nix
{
  services.xserver.xkb.extraLayouts.us-greek = {
    description = "US layout with alt-gr greek";
    languages = [ "eng" ];
    symbolsFile = /yourpath/symbols/us-greek;
  };
}
```

::: {.note}
The name (after `extraLayouts.`) should match the one given to the
`xkb_symbols` block.
:::

Applying this customization requires rebuilding several packages, and a
broken XKB file can lead to the X session crashing at login. Therefore,
you're strongly advised to **test your layout before applying it**:

```ShellSession
$ nix-shell -p xorg.xkbcomp
$ setxkbmap -I/yourpath us-greek -print | xkbcomp -I/yourpath - $DISPLAY
```

You can inspect the predefined XKB files for examples:

```ShellSession
$ echo "$(nix-build --no-out-link '<nixpkgs>' -A xorg.xkeyboardconfig)/etc/X11/xkb/"
```

Once the configuration is applied, and you did a logout/login cycle, the
layout should be ready to use. You can try it by e.g. running
`setxkbmap us-greek` and then type `<alt>+a` (it may not get applied in
your terminal straight away). To change the default, the usual
`services.xserver.xkb.layout` option can still be used.

A layout can have several other components besides `xkb_symbols`, for
example we will define new keycodes for some multimedia key and bind
these to some symbol.

Use the *xev* utility from `pkgs.xorg.xev` to find the codes of the keys
of interest, then create a `media-key` file to hold the keycodes
definitions

```
xkb_keycodes "media"
{
 <volUp>   = 123;
 <volDown> = 456;
}
```

Now use the newly define keycodes in `media-sym`:

```
xkb_symbols "media"
{
 key.type = "ONE_LEVEL";
 key <volUp>   { [ XF86AudioLowerVolume ] };
 key <volDown> { [ XF86AudioRaiseVolume ] };
}
```

As before, to install the layout do

```nix
{
  services.xserver.xkb.extraLayouts.media = {
    description = "Multimedia keys remapping";
    languages = [ "eng" ];
    symbolsFile = /path/to/media-key;
    keycodesFile = /path/to/media-sym;
  };
}
```

::: {.note}
The function `pkgs.writeText <filename> <content>` can be useful if you
prefer to keep the layout definitions inside the NixOS configuration.
:::

Unfortunately, the Xorg server does not (currently) support setting a
keymap directly but relies instead on XKB rules to select the matching
components (keycodes, types, ...) of a layout. This means that
components other than symbols won't be loaded by default. As a
workaround, you can set the keymap using `setxkbmap` at the start of the
session with:

```nix
{
  services.xserver.displayManager.sessionCommands = "setxkbmap -keycodes media";
}
```

If you are manually starting the X server, you should set the argument
`-xkbdir /etc/X11/xkb`, otherwise X won't find your layout files. For
example with `xinit` run

```ShellSession
$ xinit -- -xkbdir /etc/X11/xkb
```

To learn how to write layouts take a look at the XKB [documentation
](https://www.x.org/releases/current/doc/xorg-docs/input/XKB-Enhancing.html#Defining_New_Layouts).
More example layouts can also be found [here
](https://wiki.archlinux.org/index.php/X_KeyBoard_extension#Basic_examples).
