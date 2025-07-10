{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  coverage,
  psutil,
  pygments,
  pytestCheckHook,
  setuptools,
  typeguard,
}:

buildPythonPackage rec {
  pname = "TestSlide";
  version = "2.7.1-unstable-2025-01-17";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "facebook";
    repo = "TestSlide";
    rev = "83c180fd784f3831476d853e06a52082b9b30c70";
    hash = "sha256-kHL9jNukMlIvXM13ytrThHdYbJ92bau+W2zJAUl/E5g=";
  };

  build-system = [ setuptools ];

  pythonRelaxDeps = [ "typeguard" ];

  dependencies = [
    psutil
    pygments
    typeguard
  ];

  nativeCheckInputs = [
    coverage
  ];

  checkPhase = ''
    runHook preCheck

    coverage run -m unittest --verbose --failfast tests/*_unittest.py

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
