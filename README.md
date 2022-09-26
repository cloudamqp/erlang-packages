# Erlang debian packages

CloudAMQP built erlang debian packages. Named `esl-erlang` for compability with `rabbitmq-server` which depends on esl-erlang (or erlang-base, but the multi-package approach is difficult). The difference is that this package doesn't include wx (GUI support).

Install from https://packagecloud.io/cloudamqp/erlang

Building is done in [Dockerfile](./Dockerfile) and [GitHub Action](.github/workflows/ci.yml) uploads the packages to to PackageCloud.
