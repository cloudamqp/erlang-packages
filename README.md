# Erlang debian packages

CloudAMQP built erlang debian packages. Named `esl-erlang` for compability with `rabbitmq-server` which depends on esl-erlang (or erlang-base, but the multi-package approach is difficult).

Building is done in [Dockerfile](./Dockerfile) and [GitHub Action](.github/workflows/ci.yml) uploads the packages to to PackageCloud.

Excluded erlang packages:

* wx
* megaco
* odbc
* java

# Install

Install from https://packagecloud.io/cloudamqp/erlang

When sudo is required:

```sh
. /etc/os-release
curl -L https://packagecloud.io/cloudamqp/erlang/gpgkey | gpg --dearmor | sudo tee /usr/share/keyrings/cloudamqp-erlang.gpg
sudo tee /etc/apt/sources.list.d/cloudamqp-erlang.list << EOF
deb [signed-by=/usr/share/keyrings/cloudamqp-erlang.gpg] https://packagecloud.io/cloudamqp/erlang/$ID $VERSION_CODENAME main
EOF
sudo apt update
sudo apt install esl-erlang
```

On a bare system, eg. in a container:

```sh
apt update && apt install -y curl gnupg
. /etc/os-release
curl -L https://packagecloud.io/cloudamqp/erlang/gpgkey | gpg --dearmor > /usr/share/keyrings/cloudamqp-erlang.gpg
tee /etc/apt/sources.list.d/cloudamqp-erlang.list << EOF
deb [signed-by=/usr/share/keyrings/cloudamqp-erlang.gpg] https://packagecloud.io/cloudamqp/erlang/$ID $VERSION_CODENAME main
EOF
apt update
apt install esl-erlang
```

## Development

To test if a erlang version builds well you can use the `tester` stage in the [Dockerfile](./Dockerfile):

```sh
podman build --platform linux/arm64,linux/amd64 --target tester --build-arg image=ubuntu:20.04 --build-arg erlang_version=25.0.1 --build-arg rabbitmq_version=3.11.0 .
```
