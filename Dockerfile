ARG image=ubuntu:jammy
FROM --platform=$BUILDPLATFORM ${image} AS builder
ARG BUILDARCH
ARG TARGETARCH
ARG DEBIAN_FRONTEND=noninteractive
RUN dpkg --add-architecture $TARGETARCH && \
    . /etc/os-release && \
    if [ "$ID" = ubuntu ]; then \
        sed -i "s/^deb /deb [arch=$BUILDARCH] /" /etc/apt/sources.list; \
        echo "deb [arch=arm64] http://ports.ubuntu.com/ $VERSION_CODENAME main universe" >> /etc/apt/sources.list; \
        echo "deb [arch=arm64] http://ports.ubuntu.com/ $VERSION_CODENAME-updates main universe" >> /etc/apt/sources.list; \
    fi && \
    apt-get update

RUN apt-get install -y curl build-essential pkg-config ruby binutils autoconf libwxbase3.0-dev \
                       libssl-dev:$TARGETARCH libtinfo-dev:$TARGETARCH zlib1g-dev:$TARGETARCH libsnmp-dev:$TARGETARCH && \
    (ruby -e "exit RUBY_VERSION.to_f > 2.5" || gem install --no-document public_suffix -v 4.0.7) && \
    gem install --no-document fpm
RUN if [ "$TARGETARCH" = arm64 ]; then apt-get install -y crossbuild-essential-arm64 binutils-aarch64-linux-gnu; fi

WORKDIR /tmp/openssl
ARG erlang_version=24.0
# Erlang before 24.2 didn't support libssl3, so statically compile 1.1.1 if no available from the OS
RUN libssl_version=$(dpkg-query --showformat='${Version}' --show libssl-dev); \
    if (dpkg --compare-versions "$erlang_version" ge 20.0 && dpkg --compare-versions "$erlang_version" lt 24.2 && dpkg --compare-versions "$libssl_version" ge 3.0.0); then \
        curl https://www.openssl.org/source/openssl-1.1.1t.tar.gz | tar zx --strip-components=1 && \
        ./Configure no-shared $([ "$TARGETARCH" = arm64 ] && echo "linux-aarch64 --cross-compile-prefix=aarch64-linux-gnu-" || echo "linux-x86_64") && \
        make -j$(nproc) && make install_sw; \
    fi

# Erlang before 20.0 didn't support libssl1.1, so statically compile 1.0.2
RUN if (dpkg --compare-versions "$erlang_version" lt 20.0); then \
        curl https://www.openssl.org/source/old/1.0.2/openssl-1.0.2u.tar.gz | tar zx --strip-components=1 && \
        ./Configure --prefix=/usr/local --openssldir=/usr/local/ssl no-shared $([ "$TARGETARCH" = arm64 ] && echo "linux-aarch64 --cross-compile-prefix=aarch64-linux-gnu-" || echo "linux-x86_64") "-fPIC" && \
        make -j$(nproc) && make install_sw; \
    fi

WORKDIR /tmp/erlang
RUN curl -fL https://api.github.com/repos/erlang/otp/tarball/refs/tags/OTP-${erlang_version} | tar zx --strip-components=1

# erlang before 24.1 requires gcc-9 and autoconf-2.69
RUN if (grep -q jammy /etc/os-release && dpkg --compare-versions "$erlang_version" lt 24.1); then \
        apt-get install -y gcc-9 autoconf2.69 && \
        ln -sf /usr/bin/gcc-9 /usr/bin/gcc && \
        ln -sf /usr/bin/autoconf2.69 /usr/bin/autoconf; \
        if [ "$TARGETARCH" = arm64 ] && [ "$BUILDARCH" != arm64 ]; then \
            apt-get install -y gcc-9-aarch64-linux-gnu && \
            ln -sf /usr/bin/aarch64-linux-gnu-gcc-9 /usr/bin/aarch64-linux-gnu-gcc; \
        fi \
    fi

ARG CFLAGS="-g -O2 -fdebug-prefix-map=/=. -fstack-protector-strong -Wformat -Werror=format-security"
ARG CPPFLAGS="-Wdate-time -D_FORTIFY_SOURCE=2"
ARG LDFLAGS="-Wl,-Bsymbolic-functions -Wl,-z,relro"
ARG ERLC_USE_SERVER=false
RUN ./otp_build autoconf
RUN if [ "$TARGETARCH" = arm64 ]; then \
        ./configure --enable-bootstrap-only && make -j$(nproc); \
    fi
RUN libssl_version=$(dpkg-query --showformat='${Version}' --show libssl-dev); \
    STATIC_OPENSSL=$(dpkg --compare-versions "$erlang_version" lt 20 || (dpkg --compare-versions "$erlang_version" lt 24.2 && dpkg --compare-versions "$libssl_version" ge 3) && echo y); \
    ./configure erl_xcomp_sysroot=/ \
                --prefix=/usr \
                --enable-kernel-poll \
                --enable-shared-zlib \
                --disable-builtin-zlib \
                --disable-sctp \
                --disable-hipe \
                --without-java \
                --without-odbc \
                --without-megaco \
                --without-diameter \
                --without-debugger \
                --without-dialyzer \
                --without-edoc \
                --without-common_test \
                --without-eunit \
                --with-ssl-rpath=no \
                --with-ssl \
                $([ "$TARGETARCH" = arm64 ] && echo "--host=aarch64-linux-gnu --build=$BUILDARCH-linux-gnu") \
                $([ "$STATIC_OPENSSL" = y ] && echo "--with-ssl=/usr/local --disable-dynamic-ssl-lib" || echo --enable-dynamic-ssl-lib) && \
    make -j$(nproc) && \
    make install DESTDIR=/tmp/install && \
    find /tmp/install -type d -name examples | xargs rm -r && \
    find /tmp/install -type f -executable -exec $([ "$TARGETARCH" = arm64 ] && echo aarch64-linux-gnu-)strip {} \;;
# when cross compiling the target version of strip is required

ARG erlang_iteration=1
RUN readelf=$([ "$TARGETARCH" = arm64 ] && echo aarch64-linux-gnu-)readelf; \
    fpm -s dir -t deb \
    --chdir /tmp/install \
    --name esl-erlang \
    --version $erlang_version \
    --architecture $TARGETARCH \
    --epoch 1 \
    --iteration $erlang_iteration \
    --maintainer "CloudAMQP <contact@cloudamqp.com>" \
    --category interpreters \
    --description "Concurrent, real-time, distributed functional language" \
    --url "https://erlang.org" \
    --license "Apache 2.0" \
    --depends "procps" \
    --depends "$($readelf -d $(find /tmp/install/usr -name beam.smp) | awk '/NEEDED/{gsub(/[\[\]]/, "");print $5}' | xargs dpkg -S | cut -d: -f1 | sort -u | paste -sd,)" \
    --conflicts "erlang-asn1,erlang-base,erlang-base-hipe,erlang-common-test,erlang-corba,erlang-crypto,erlang-debugger,erlang-dev,erlang-dialyzer,erlang-diameter,erlang-doc,erlang-edoc,erlang-eldap,erlang-erl-docgen,erlang-et,erlang-eunit,erlang-examples,erlang-ftp,erlang-ic,erlang-ic-java,erlang-inets,erlang-inviso,erlang-jinterface,erlang-manpages,erlang-megaco,erlang-mnesia,erlang-mode,erlang-nox,erlang-observer,erlang-odbc,erlang-os-mon,erlang-parsetools,erlang-percept,erlang-public-key,erlang-reltool,erlang-runtime-tools,erlang-snmp,erlang-src,erlang-ssh,erlang-ssl,erlang-syntax-tools,erlang-tftp,erlang-tools,erlang-webtool,erlang-wx,erlang-xmerl"

#RUN apt-get install -y lintian
#RUN dpkg --info *erlang*.deb
#RUN lintian *erlang*.deb || true

ARG TARGETPLATFORM
FROM --platform=$TARGETPLATFORM ${image} as tester
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y curl
ARG rabbitmq_version=3.7.10
RUN curl -fLO https://github.com/rabbitmq/rabbitmq-server/releases/download/v${rabbitmq_version}/rabbitmq-server_${rabbitmq_version}-1_all.deb || \
    curl -fLO https://github.com/rabbitmq/rabbitmq-server/releases/download/rabbitmq_v$(echo $rabbitmq_version | tr . _)/rabbitmq-server_${rabbitmq_version}-1_all.deb
COPY --from=builder /tmp/erlang/*.deb .
RUN apt-get install -y ./*.deb
RUN erl -noshell -eval 'io:format("~p", [ssl:versions()]), init:stop().'
RUN rabbitmq-server

FROM scratch
COPY --from=builder /tmp/erlang/*.deb .
