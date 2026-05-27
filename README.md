# Erlang debian packages

CloudAMQP built erlang debian packages. Named `esl-erlang` for compability with `rabbitmq-server` which depends on esl-erlang (or erlang-base, but the multi-package approach is difficult).

Building is done in [Dockerfile](./Dockerfile) and [GitHub Action](.github/workflows/build-all-and-upload.yml) uploads the packages to PackageCloud.

Excluded erlang packages:

* wx
* megaco
* odbc
* java

## Versions

Every [version of Erlang ≥ 24.2 that is released on GitHub](https://github.com/erlang/otp/releases) is built, currently for Ubuntu 22.04, 24.04 and 26.04.

## Caveat

GitHub disables the scheduled workflow if there hasn't been activity in this repository for at least 60 days. Need to manually enable the workflow to resume scheduled runs.

## Install

Install from https://packagecloud.io/cloudamqp/erlang

When sudo is required:

```sh
. /etc/os-release
curl -L https://packagecloud.io/cloudamqp/erlang/gpgkey | gpg --dearmor | sudo tee /etc/apt/keyrings/cloudamqp-erlang.gpg
sudo tee /etc/apt/sources.list.d/cloudamqp-erlang.list << EOF
deb [signed-by=/etc/apt/keyrings/cloudamqp-erlang.gpg] https://packagecloud.io/cloudamqp/erlang/$ID $VERSION_CODENAME main
EOF
sudo apt update
sudo apt install esl-erlang
```

On a bare system, eg. in a container:

```sh
apt update && apt install -y curl gnupg
. /etc/os-release
curl -L https://packagecloud.io/cloudamqp/erlang/gpgkey | gpg --dearmor > /etc/apt/keyrings/cloudamqp-erlang.gpg
tee /etc/apt/sources.list.d/cloudamqp-erlang.list << EOF
deb [signed-by=/etc/apt/keyrings/cloudamqp-erlang.gpg] https://packagecloud.io/cloudamqp/erlang/$ID $VERSION_CODENAME main
EOF
apt update
apt install esl-erlang
```

## Development

To test if a erlang version builds well you can use the `tester` stage in the [Dockerfile](./Dockerfile):

```sh
podman build --target tester --build-arg image=ubuntu:jammy --build-arg erlang_version=26.0 --build-arg rabbitmq_version=3.13.0 .
```

https://depot.dev/ is used for building multi-plaform images on native hardware, the Dockerfile used to be crosscompiling, but not anymore as it increases complexity.
