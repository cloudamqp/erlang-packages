ARG image=debian:11
FROM --platform=$BUILDPLATFORM ${image} AS builder
WORKDIR /tmp/erlang
ARG BUILDARCH
ARG TARGETARCH
ARG DEBIAN_FRONTEND=noninteractive
RUN dpkg --add-architecture $TARGETARCH && \
    apt-get update && \
    apt-get install -y curl build-essential pkg-config ruby binutils \
                       libssl-dev:$TARGETARCH ncurses-dev:$TARGETARCH libsctp-dev:$TARGETARCH && \
    gem install --no-document public_suffix -v 4.0.7 && \
    gem install --no-document fpm
ARG erlang_version=25.1
RUN curl -L "https://github.com/erlang/otp/releases/download/OTP-${erlang_version}/otp_src_${erlang_version}.tar.gz" | tar zx --strip-components=1
RUN eval "$(dpkg-buildflags --export=sh)" && ./configure --enable-bootstrap-only && make
RUN test "$TARGETARCH" = "arm64" && apt-get install -y gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu || true
RUN eval "$(dpkg-buildflags --export=sh)" && \
    ./configure $([ "$TARGETARCH" = "arm64" ] && echo "--host=aarch64-linux-gnu --build=$BUILDARCH-linux-gnu --disable-jit erl_xcomp_sysroot=/") \
                --prefix=/usr \
                --enable-dirty-schedulers \
                --enable-dynamic-ssl-lib \
                --enable-kernel-poll \
                --enable-sctp \
                --disable-builtin-zlib \
                --disable-saved-compile-time \
                --without-wx \
                --without-megaco \
                --without-odbc \
                --without-java \
                --with-ssl && \
    make -j$(nproc) && \
    make install DESTDIR=/tmp/install && \
    find /tmp/install -type d -name examples | xargs rm -r && \
    find /tmp/install -type f -executable -exec $([ "$TARGETARCH" = "arm64" ] && echo "aarch64-linux-gnu-")strip {} \;;
# when cross compiling the target version of strip is required

ARG erlang_iteration=1
RUN . /etc/os-release && \
    fpm -s dir -t deb \
    --chdir /tmp/install \
    --name esl-erlang \
    --package-name-suffix ${VERSION_CODENAME} \
    --version ${erlang_version} \
    --architecture ${TARGETARCH} \
    --epoch 1 \
    --iteration ${erlang_iteration} \
    --maintainer "84codes AB <contact@cloudamqp.com>" \
    --category interpreters \
    --description "Concurrent, real-time, distributed functional language" \
    --url "https://erlang.org" \
    --license "Apache 2.0" \
    --depends "procps, libc6, libncurses5, libgcc1, libstdc++6, libsctp1" \
    --depends "$(apt-cache depends libssl-dev | awk '/Depends:/ {print $2}')" \
    $(for pkg in erlang-base-hipe erlang-base erlang-dev erlang-appmon erlang-asn1 erlang-common-test erlang-corba erlang-crypto erlang-debugger erlang-dialyzer erlang-docbuilder erlang-edoc erlang-erl-docgen erlang-et erlang-eunit erlang-gs erlang-ic erlang-inets erlang-inviso erlang-mnesia erlang-observer erlang-os-mon erlang-parsetools erlang-percept erlang-pman erlang-public-key erlang-reltool erlang-runtime-tools erlang-snmp erlang-ssh erlang-ssl erlang-syntax-tools erlang-test-server erlang-toolbar erlang-tools erlang-tv erlang-typer erlang-webtool erlang-xmerl; do echo "--conflicts $pkg --replaces $pkg --provides $pkg"; done) \
    .
#RUN dpkg --info *.deb
#RUN apt-get install -y lintian
#RUN lintian *.deb

FROM --platform=$TARGETPLATFORM ${image} as tester
COPY --from=builder /tmp/erlang/*.deb .
RUN apt-get update && apt-get install -y wget
RUN wget --content-disposition "https://packagecloud.io/rabbitmq/rabbitmq-server/packages/debian/bullseye/rabbitmq-server_3.11.0-1_all.deb/download.deb?distro_version_id=207"
RUN apt-get install -y ./*.deb
RUN rabbitmq-server

FROM scratch
COPY --from=builder /tmp/erlang/*.deb .
