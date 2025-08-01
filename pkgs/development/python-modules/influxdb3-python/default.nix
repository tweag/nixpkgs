{
  lib,
  buildPythonPackage,
  certifi,
  fetchFromGitHub,
  pyarrow,
  python-dateutil,
  pythonOlder,
  reactivex,
  setuptools,
  pandas,
  polars,
  urllib3,
}:

buildPythonPackage rec {
  pname = "influxdb3-python";
  version = "0.14.0";
  pyproject = true;

  disabled = pythonOlder "3.8";

  src = fetchFromGitHub {
    owner = "InfluxCommunity";
    repo = "influxdb3-python";
    tag = "v${version}";
    hash = "sha256-gCLH1MtLYggB3t/+B062w31go5mGf0GELZWhO0DnZy8=";
  };

  postPatch = ''
    # Upstream falls back to a default version if not in a GitHub Actions
    substituteInPlace setup.py \
      --replace-fail "version=get_version()," "version = '${version}',"
  '';

  build-system = [ setuptools ];

  dependencies = [
    certifi
    pyarrow
    python-dateutil
    reactivex
    urllib3
  ];

  optional-dependencies = {
    pandas = [ pandas ];
    polars = [ polars ];
    dataframe = [
      pandas
      polars
    ];
  };

  # Missing ORC support
  # https://github.com/NixOS/nixpkgs/issues/212863
  # nativeCheckInputs = [
  #   pytestCheckHook
  # ];
  #
  # pythonImportsCheck = [
  #   "influxdb_client_3"
  # ];

  meta = with lib; {
    description = "Python module that provides a simple and convenient way to interact with InfluxDB 3.0";
    homepage = "https://github.com/InfluxCommunity/influxdb3-python";
    changelog = "https://github.com/InfluxCommunity/influxdb3-python/releases/tag/${src.tag}";
    license = licenses.asl20;
    maintainers = with maintainers; [ fab ];
  };
}
