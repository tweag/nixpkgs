{ lib }: {
  docs = ''
    The value 10
  '';
  value = 10;

  # Will give a warning in 1 year, error in 2 years, removed in 4 years
  introduced = "2022-07-19";

  # The URL where people can give feedback
  # Will be shown in docs and printed in a warning after the first cycle
  feedbackUrl = "https://...";

  # Either new symbols in a single existing sub-library
  #   lib.experimental.feature-foo.{foo,bar,baz}
  # Or a new sub-library entirely
  #   lib.experimental.feature-bar.*
  # Or a single symbol
  #   lib.experimental.foo

  # Only the functionality needs to be validated in practice, not the name
  # So no need to try to integrate it into `lib` already


}
