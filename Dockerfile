ARG image=ubuntu:jammy
FROM ${image} AS builder
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update

RUN apt-get install -y curl build-essential pkg-config ruby binutils autoconf \
                       libssl-dev libtinfo-dev zlib1g-dev libsnmp-dev && \
    gem install --no-document fpm

ARG erlang_version=25.3
WORKDIR /tmp/erlang
RUN curl -fL https://api.github.com/repos/erlang/otp/tarball/refs/tags/OTP-${erlang_version} | tar zx --strip-components=1

# gcc 15+ defaults to C23, where bool/true/false are reserved keywords; older
# Erlang uses them as identifiers, so pin the C standard to gnu17
ARG CFLAGS="-std=gnu17 -g -O2 -fdebug-prefix-map=/=. -fstack-protector-strong -Wformat -Werror=format-security"
ARG CPPFLAGS="-Wdate-time -D_FORTIFY_SOURCE=2"
ARG LDFLAGS="-Wl,-Bsymbolic-functions -Wl,-z,relro"
ARG ERLC_USE_SERVER=false
RUN ./otp_build autoconf
# gcc 14+ rejects the implicit int and implicit declarations that older OTP
# configure tests use (e.g. "working poll()"), so those tests fail silently.
# -fpermissive restores gcc 13 behaviour; older gcc errors on it under -Werror.
RUN permissive=$([ "$(gcc -dumpversion | cut -d. -f1)" -ge 14 ] && \
                 { dpkg --compare-versions "$erlang_version" lt 26.2.5.7 || \
                   { dpkg --compare-versions "$erlang_version" ge 27 && \
                     dpkg --compare-versions "$erlang_version" lt 27.2.1; }; } && \
                 echo -fpermissive); \
    ./configure CFLAGS="$CFLAGS $permissive" \
                erl_xcomp_sysroot=/ \
                --prefix=/usr \
                --enable-kernel-poll \
                --enable-shared-zlib \
                --disable-builtin-zlib \
                --disable-sctp \
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
                --enable-dynamic-ssl-lib && \
    make -j$(nproc) && \
    make install DESTDIR=/tmp/install && \
    find /tmp/install -type d -name examples | xargs rm -r && \
    find /tmp/install -type f -executable -exec strip {} \;;

# RabbitMQ reads max_fds from the fallback poller; select() caps it at 1024
RUN ./bin/erl -noshell -eval 'poll = proplists:get_value(primary, hd(erlang:system_info(check_io))), init:stop().'

ARG erlang_iteration=1
RUN mkdir debian && touch debian/control; \
    DEPS=$(dpkg-shlibdeps -O -e $(find /tmp/install/usr -name beam.smp) 2> /dev/null); \
    SHLIBS_PREFIX="shlibs:Depends="; \
    fpm -s dir -t deb \
    --chdir /tmp/install \
    --name esl-erlang \
    --version $erlang_version \
    --epoch 1 \
    --iteration $erlang_iteration \
    --maintainer "CloudAMQP <contact@cloudamqp.com>" \
    --category interpreters \
    --description "Concurrent, real-time, distributed functional language" \
    --url "https://erlang.org" \
    --license "Apache 2.0" \
    --depends "procps" \
    --depends "${DEPS#$SHLIBS_PREFIX}" \
    --conflicts "erlang-asn1,erlang-base,erlang-base-hipe,erlang-common-test,erlang-corba,erlang-crypto,erlang-debugger,erlang-dev,erlang-dialyzer,erlang-diameter,erlang-doc,erlang-edoc,erlang-eldap,erlang-erl-docgen,erlang-et,erlang-eunit,erlang-examples,erlang-ftp,erlang-ic,erlang-ic-java,erlang-inets,erlang-inviso,erlang-jinterface,erlang-manpages,erlang-megaco,erlang-mnesia,erlang-mode,erlang-nox,erlang-observer,erlang-odbc,erlang-os-mon,erlang-parsetools,erlang-percept,erlang-public-key,erlang-reltool,erlang-runtime-tools,erlang-snmp,erlang-src,erlang-ssh,erlang-ssl,erlang-syntax-tools,erlang-tftp,erlang-tools,erlang-webtool,erlang-wx,erlang-xmerl"

#RUN apt-get install -y lintian
#RUN dpkg --info *erlang*.deb
#RUN lintian *erlang*.deb || true

FROM ${image} AS tester
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y curl
ARG rabbitmq_version=3.12.14
RUN curl -fLO https://github.com/rabbitmq/rabbitmq-server/releases/download/v${rabbitmq_version}/rabbitmq-server_${rabbitmq_version}-1_all.deb
COPY --from=builder /tmp/erlang/*.deb .
RUN apt-get install -y ./*.deb
RUN erl -noshell -eval 'io:format("~p", [ssl:versions()]), init:stop().'
# rabbitmq-server runs in the foreground; start it detached, wait for boot, stop.
# await_startup exits non-zero right away until the node has registered, so retry it
RUN rabbitmq-server -detached && \
    timeout 120 sh -c 'until rabbitmqctl -q await_startup; do sleep 1; done' && \
    rabbitmqctl stop

FROM scratch
COPY --from=builder /tmp/erlang/*.deb .
