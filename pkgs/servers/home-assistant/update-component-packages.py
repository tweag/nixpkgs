#! /usr/bin/env nix-shell
#! nix-shell -i python3 -p "python3.withPackages (ps: with ps; [ packaging rich ])" -p pyright ruff isort
#
# This script downloads Home Assistant's source tarball.
# Inside the homeassistant/components directory, each integration has an associated manifest.json,
# specifying required packages and other integrations it depends on:
#
#     {
#       "requirements": [ "package==1.2.3" ],
#       "dependencies": [ "component" ]
#     }
#
# By parsing the files, a dictionary mapping integrations to requirements and dependencies is created.
# For all of these requirements and the dependencies' requirements,
# nixpkgs' python3Packages are searched for appropriate names.
# Then, a Nix attribute set mapping integration name to dependencies is created.

import json
import os
import pathlib
import re
import subprocess
import sys
import tarfile
import tempfile
from functools import reduce
from io import BytesIO
from typing import Any, Dict, List, Optional, Set
from urllib.request import urlopen

from packaging import version as Version
from packaging.version import InvalidVersion
from rich.console import Console
from rich.table import Table

COMPONENT_PREFIX = "homeassistant.components"
PKG_SET = "home-assistant.python.pkgs"

# If some requirements are matched by multiple or no Python packages, the
# following can be used to choose the correct one
PKG_PREFERENCES = {
    "fiblary3": "fiblary3-fork",  # https://github.com/home-assistant/core/issues/66466
    "HAP-python": "hap-python",
    "ha-av": "av",
    "numpy": "numpy",
    "ollama-hass": "ollama",
    "paho-mqtt": "paho-mqtt",
    "sentry-sdk": "sentry-sdk",
    "slackclient": "slack-sdk",
    "SQLAlchemy": "sqlalchemy",
    "tensorflow": "tensorflow",
    "yt-dlp": "yt-dlp",
}

# Some dependencies are loaded dynamically at runtime, and are not
# mentioned in the manifest files.
EXTRA_COMPONENT_DEPS = {
    "conversation": [
        "intent"
    ],
    "default_config": [
        "backup",
    ],
}

# Sometimes we have unstable versions for libraries that are not
# well-maintained. This allows us to mark our weird version as newer
# than a certain wanted version
OUR_VERSION_IS_NEWER_THAN = {
    "blinkstick": "1.2.0",
    "gps3": "0.33.3",
    "pybluez": "0.22",
}



def run_sync(cmd: List[str]) -> None:
    print(f"$ {' '.join(cmd)}")
    process = subprocess.run(cmd)

    if process.returncode != 0:
        sys.exit(1)


def get_version() -> str:
    with open(os.path.dirname(sys.argv[0]) + "/default.nix") as f:
        # A version consists of digits, dots, and possibly a "b" (for beta)
        if match := re.search('hassVersion = "([\\d\\.b]+)";', f.read()):
            return match.group(1)
        raise RuntimeError("hassVersion not in default.nix")


def parse_components(version: str = "master"):
    components = {}
    components_with_tests = []
    with tempfile.TemporaryDirectory() as tmp:
        with urlopen(
            f"https://github.com/home-assistant/home-assistant/archive/{version}.tar.gz"
        ) as response:
            tarfile.open(fileobj=BytesIO(response.read())).extractall(tmp, filter="data")
        # Use part of a script from the Home Assistant codebase
        core_path = os.path.join(tmp, f"core-{version}")

        for entry in os.scandir(os.path.join(core_path, "tests/components")):
            if entry.is_dir():
                components_with_tests.append(entry.name)

        sys.path.append(core_path)
        from script.hassfest.model import Config, Integration  # type: ignore
        config = Config(
            root=pathlib.Path(core_path),
            specific_integrations=None,
            action="generate",
            requirements=False,
        )
        integrations = Integration.load_dir(config.core_integrations_path, config)
        for domain in sorted(integrations):
            integration = integrations[domain]
            if extra_deps := EXTRA_COMPONENT_DEPS.get(integration.domain):
                integration.dependencies.extend(extra_deps)
            if not integration.disabled:
                components[domain] = integration.manifest

    return components, components_with_tests


# Recursively get the requirements of a component and its dependencies
def get_reqs(components: Dict[str, Dict[str, Any]], component: str, processed: Set[str]) -> Set[str]:
    requirements = set(components[component].get("requirements", []))
    deps = components[component].get("dependencies", [])
    deps.extend(components[component].get("after_dependencies", []))
    processed.add(component)
    for dependency in deps:
        if dependency not in processed:
            requirements.update(get_reqs(components, dependency, processed))
    return requirements


def repository_root() -> str:
    return os.path.abspath(sys.argv[0] + "/../../../..")


# For a package attribute and and an extra, check if the package exposes it via passthru.optional-dependencies
def has_extra(package: str, extra: str):
    cmd = [
        "nix-instantiate",
        repository_root(),
        "-A",
        f"{package}.optional-dependencies.{extra}",
    ]
    try:
        subprocess.run(
            cmd,
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except subprocess.CalledProcessError:
        return False
    return True


def dump_packages() -> Dict[str, Dict[str, str]]:
    # Store a JSON dump of Nixpkgs' python3Packages
    output = subprocess.check_output(
        [
            "nix-env",
            "-f",
            repository_root(),
            "-qa",
            "-A",
            PKG_SET,
            "--arg", "config", "{ allowAliases = false; }",
            "--json",
        ]
    )
    return json.loads(output)


def name_to_attr_path(req: str, packages: Dict[str, Dict[str, str]]) -> Optional[str]:
    if req in PKG_PREFERENCES:
        return f"{PKG_SET}.{PKG_PREFERENCES[req]}"
    attr_paths = []
    names = [req]
    # E.g. python-mpd2 is actually called python3.6-mpd2
    # instead of python-3.6-python-mpd2 inside Nixpkgs
    if req.startswith("python-") or req.startswith("python_"):
        names.append(req[len("python-") :])
    for name in names:
        # treat "-" and "_" equally
        name = re.sub("[-_]", "[-_]", name)
        # python(minor).(major)-(pname)-(version or unstable-date)
        # we need the version qualifier, or we'll have multiple matches
        # (e.g. pyserial and pyserial-asyncio when looking for pyserial)
        pattern = re.compile(f"^python\\d+\\.\\d+-{name}-(?:\\d|unstable-.*)", re.I)
        for attr_path, package in packages.items():
            if pattern.match(package["name"]):
                attr_paths.append(attr_path)
    # Let's hope there's only one derivation with a matching name
    assert len(attr_paths) <= 1, f"{req} matches more than one derivation: {attr_paths}"
    if attr_paths:
        return attr_paths[0]
    else:
        return None


def get_pkg_version(attr_path: str, packages: Dict[str, Dict[str, str]]) -> Optional[str]:
    pkg = packages.get(attr_path, None)
    if not pkg:
        return None
    return pkg["version"]


def main() -> None:
    packages = dump_packages()
    version = get_version()
    print("Generating component-packages.nix for version {}".format(version))
    components, components_with_tests = parse_components(version=version)
    build_inputs = {}
    outdated = {}
    for component in sorted(components.keys()):
        attr_paths = []
        extra_attrs = []
        missing_reqs = []
        reqs = sorted(get_reqs(components, component, set()))
        for req in reqs:
            # Some requirements are specified by url, e.g. https://example.org/foobar#xyz==1.0.0
            # Therefore, if there's a "#" in the line, only take the part after it
            req = req[req.find("#") + 1 :]
            name, required_version = req.split("==", maxsplit=1)
            # Strip conditions off version constraints e.g. "1.0; python<3.11"
            required_version = required_version.split(";").pop(0)
            # Split package name and extra requires
            extras = []
            if name.endswith("]"):
                extras = name[name.find("[")+1:name.find("]")].split(",")
                name = name[:name.find("[")]
            attr_path = name_to_attr_path(name, packages)
            if attr_path:
                if our_version := get_pkg_version(attr_path, packages):
                    attr_name = attr_path.split(".")[-1]
                    attr_outdated = False
                    try:
                        Version.parse(our_version)
                    except InvalidVersion:
                        print(f"Attribute {attr_name} has invalid version specifier {our_version}", file=sys.stderr)

                        # allow specifying that our unstable version is newer than some version
                        if newer_than_version := OUR_VERSION_IS_NEWER_THAN.get(attr_name):
                            attr_outdated = Version.parse(newer_than_version) < Version.parse(required_version)
                        else:
                            attr_outdated = True
                    else:
                        attr_outdated = Version.parse(our_version) < Version.parse(required_version)
                    finally:
                        if attr_outdated:
                            outdated[attr_name] = {
                              'wanted': required_version,
                              'current': our_version
                            }
            if attr_path is not None:
                # Add attribute path without "python3Packages." prefix
                pname = attr_path[len(PKG_SET + "."):]
                attr_paths.append(pname)
                for extra in extras:
                    # Check if package advertises extra requirements
                    extra_attr = f"{pname}.optional-dependencies.{extra}"
                    if has_extra(attr_path, extra):
                        extra_attrs.append(extra_attr)
                    else:
                        missing_reqs.append(extra_attr)

            else:
                missing_reqs.append(name)
        else:
            build_inputs[component] = (attr_paths, extra_attrs, missing_reqs)

    outpath = os.path.dirname(sys.argv[0]) + "/component-packages.nix"
    with open(outpath, "w") as f:
        f.write("# Generated by update-component-packages.py\n")
        f.write("# Do not edit!\n\n")
        f.write("{\n")
        f.write(f'  version = "{version}";\n')
        f.write("  components = {\n")
        for component, deps in build_inputs.items():
            available, extras, missing = deps
            f.write(f'    "{component}" = ps: with ps; [')
            if available:
                f.write("\n      " + "\n      ".join(sorted(available)))
            f.write("\n    ]")
            if extras:
                f.write("\n    ++ " + "\n    ++ ".join(sorted(extras)))
            f.write(";")
            if len(missing) > 0:
                f.write(f" # missing inputs: {' '.join(sorted(missing))}")
            f.write("\n")
        f.write("  };\n")
        f.write("  # components listed in tests/components for which all dependencies are packaged\n")
        f.write("  supportedComponentsWithTests = [\n")
        for component, deps in build_inputs.items():
            available, extras, missing = deps
            if len(missing) == 0 and component in components_with_tests:
                f.write(f'    "{component}"' + "\n")
        f.write("  ];\n")
        f.write("}\n")

    run_sync(["nixfmt", outpath])

    supported_components = reduce(lambda n, c: n + (build_inputs[c][2] == []),
                                  components.keys(), 0)
    total_components = len(components)
    print(f"{supported_components} / {total_components} components supported, "
          f"i.e. {supported_components / total_components:.2%}")

    if outdated:
        table = Table(title="Outdated dependencies")
        table.add_column("Package")
        table.add_column("Current")
        table.add_column("Wanted")
        for package, version in sorted(outdated.items()):
            table.add_row(package, version['current'], version['wanted'])

        console = Console()
        console.print(table)


if __name__ == "__main__":
    run_sync(["pyright", __file__])
    run_sync(["ruff", "check", "--ignore=E501", __file__])
    run_sync(["isort", __file__])
    main()
