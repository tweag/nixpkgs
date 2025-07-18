{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  coverage,
  psutil,
  pygments,
  pytest,
  pytest-asyncio,
  setuptools,
  typeguard,
}:

buildPythonPackage rec {
  pname = "TestSlide";
  version = "2.7.1-unstable-2025-01-17"; # this main branch has a .bdd submodule that does not make it into the wheel!
  # version = "2.7.1";  # fails due to typeguard.qualified_name!
  pyproject = true;

  src = fetchFromGitHub {
    owner = "facebook";
    repo = "TestSlide";
    # tag = version;
    # hash = "sha256-M/qUhzbQzm3D6P2aM97z1llghqyi+XAZRZjyY1l+Wv4=";
    rev = "83c180fd784f3831476d853e06a52082b9b30c70";
    hash = "sha256-kHL9jNukMlIvXM13ytrThHdYbJ92bau+W2zJAUl/E5g=";
  };

  # Disable tests that also fail when run outside nixpkgs context,
  # likely due to changes in unpinned dependencies
  patches = [ ./skip_tests.patch ];

  build-system = [ setuptools ];

#   pythonRelaxDeps = [ "typeguard" ];

  dependencies = [
    psutil
    pygments
    typeguard
  ];

  nativeCheckInputs = [
    coverage
    pytest
    pytest-asyncio
  ];

  checkPhase = ''
    runHook preCheck

    coverage run -m unittest \
      --verbose \
      --failfast \
      tests/*_unittest.py

    coverage run -m testslide.executor.cli \
      --format documentation \
      --show-testslide-stack-trace \
      --fail-fast \
      --fail-if-focused \
      tests/*_testslide.py

    PYTHONPATH="$(pwd)/pytest-testslide:$(pwd):$PYTHONPATH" \
    coverage run -m pytest \
      pytest-testslide/tests

    runHook postCheck
  '';

  pythonImportsCheck = [ "testslide" ];

  meta = {
    description = "Test framework for Python that enable unit testing / TDD / BDD to be productive and enjoyable";
    homepage = "https://github.com/facebook/TestSlide";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ jherland ];
  };
}
