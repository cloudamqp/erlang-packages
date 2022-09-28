ARG image=debian:11
FROM --platform=$BUILDPLATFORM ${image} AS builder
WORKDIR /tmp/erlang
ARG BUILDARCH
ARG TARGETARCH
ARG DEBIAN_FRONTEND=noninteractive
RUN dpkg --add-architecture $TARGETARCH && \
    . /etc/os-release && \
    if [ "$ID" = ubuntu ]; then \
        sed -i "s/^deb /deb [arch=$BUILDARCH] /" /etc/apt/sources.list; \
        echo "deb [arch=arm64] http://ports.ubuntu.com/ $VERSION_CODENAME main" >> /etc/apt/sources.list; \
        echo "deb [arch=arm64] http://ports.ubuntu.com/ $VERSION_CODENAME-updates main" >> /etc/apt/sources.list; \
    fi && \
    apt-get update
ARG erlang_version=25.1
RUN LIBSSL_DEV=$(dpkg --compare-versions "${erlang_version}" gt 19.3 && echo libssl-dev || echo libssl1.0-dev); \
    apt-get install -y curl build-essential pkg-config ruby binutils autoconf libwxbase3.0-dev \
                       $LIBSSL_DEV:$TARGETARCH libtinfo-dev:$TARGETARCH zlib1g-dev:$TARGETARCH && \
    gem install --no-document public_suffix -v 4.0.7 && \
    gem install --no-document fpm
RUN curl -fL https://api.github.com/repos/erlang/otp/tarball/refs/tags/OTP-${erlang_version} | tar zx --strip-components=1
RUN ./otp_build autoconf
RUN test "$TARGETARCH" = arm64 && \
    apt-get install -y crossbuild-essential-arm64 binutils-aarch64-linux-gnu && \
    eval "$(dpkg-buildflags --export=sh)" && \
    ./configure --enable-bootstrap-only && make -j$(nproc) || true
RUN eval "$(dpkg-buildflags --export=sh)" && \
    CONF_FLAGS=$([ "$TARGETARCH" = arm64 ] && \
                 echo "--host=aarch64-linux-gnu --build=$BUILDARCH-linux-gnu --disable-jit erl_xcomp_sysroot=/" || \
                 echo "--enable-jit") && \
    ./configure $CONF_FLAGS \
                --prefix=/usr \
                --enable-kernel-poll \
                --enable-dynamic-ssl-lib \
                --enable-shared-zlib \
                --disable-plain-emulator \
                --disable-sctp \
                --disable-builtin-zlib \
                --disable-saved-compile-time \
                --disable-hipe \
                --without-megaco \
                --without-odbc \
                --without-java \
                --without-debugger \
                --without-dialyzer \
                --without-diameter \
                --without-edoc \
                --without-common_test \
                --without-eunit \
                --without-ssh \
                --without-ftp \
                --without-tftp \
                --with-ssl-rpath=no \
                --with-ssl && \
    make -j$(nproc) && \
    make install DESTDIR=/tmp/install && \
    find /tmp/install -type d -name examples | xargs rm -r && \
    find /tmp/install -type f -executable -exec $([ "$TARGETARCH" = arm64 ] && echo "aarch64-linux-gnu-")strip {} \;;
# when cross compiling the target version of strip is required

ARG erlang_iteration=1
RUN . /etc/os-release && \
    LIBSSL_DEV=$(dpkg --compare-versions "${erlang_version}" gt 19.3 && echo libssl-dev || echo libssl1.0-dev); \
    fpm -s dir -t deb \
    --chdir /tmp/install \
    --name esl-erlang \
    --version ${erlang_version} \
    --architecture ${TARGETARCH} \
    --epoch 1 \
    --iteration ${erlang_iteration} \
    --maintainer "84codes AB <contact@cloudamqp.com>" \
    --category interpreters \
    --description "Concurrent, real-time, distributed functional language" \
    --url "https://erlang.org" \
    --license "Apache 2.0" \
    --depends "procps, libc6, libgcc1, libstdc++6, zlib1g" \
    --depends "$(apt-cache depends $LIBSSL_DEV | awk '/Depends: libssl/ {print $2}')" \
    --depends "$(apt-cache depends libtinfo-dev | awk '/Depends: libtinfo/ {print $2}')" \
    --provides "erlang-base" \
    --conflicts "$(apt-cache depends erlang | awk '/:/ {gsub("[<>]", "", $2); print $2}' | paste -sd,)" \
    .

ARG TARGETPLATFORM
FROM --platform=$TARGETPLATFORM ${image} as tester
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y curl lintian
ARG rabbitmq_version=3.11.0
RUN curl -fLO https://github.com/rabbitmq/rabbitmq-server/releases/download/v${rabbitmq_version}/rabbitmq-server_${rabbitmq_version}-1_all.deb || \
    curl -fLO https://github.com/rabbitmq/rabbitmq-server/releases/download/rabbitmq_v$(echo $rabbitmq_version | tr . _)/rabbitmq-server_${rabbitmq_version}-1_all.deb
COPY --from=builder /tmp/erlang/*.deb .
RUN lintian *erlang*.deb || true
RUN dpkg --info *erlang*.deb
RUN apt-get install -y ./*.deb
RUN erl -noshell -eval 'io:format("~p", [ssl:versions()]), init:stop().'
RUN rabbitmq-server

FROM scratch
COPY --from=builder /tmp/erlang/*.deb .
