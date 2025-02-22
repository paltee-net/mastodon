# syntax=docker/dockerfile:1.4
# This needs to be bullseye-slim because the Ruby image is built on bullseye-slim
ARG NODE_VERSION="16.18.1-bullseye-slim"

FROM ghcr.io/moritzheiber/ruby-jemalloc:3.0.6-slim as ruby
FROM node:${NODE_VERSION} as build

COPY --link --from=ruby /opt/ruby /opt/ruby

ENV DEBIAN_FRONTEND="noninteractive" \
    PATH="${PATH}:/opt/ruby/bin"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

WORKDIR /opt/mastodon
COPY Gemfile* package.json yarn.lock /opt/mastodon/

# hadolint ignore=DL3008
RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential \
        ca-certificates \
        git \
        libicu-dev \
        libidn11-dev \
        libpq-dev \
        libjemalloc-dev \
        zlib1g-dev \
        libgdbm-dev \
        libgmp-dev \
        libssl-dev \
        libyaml-0-2 \
        ca-certificates \
        libreadline8 \
        python3 \
        shared-mime-info && \
    bundle config set --local deployment 'true' && \
    bundle config set --local without 'development test' && \
    bundle config set silence_root_warning true && \
    bundle install -j"$(nproc)" && \
    yarn install --pure-lockfile --network-timeout 600000

FROM node:${NODE_VERSION}

ARG UID="991"
ARG GID="991"

COPY --link --from=ruby /opt/ruby /opt/ruby

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND="noninteractive" \
    PATH="${PATH}:/opt/ruby/bin:/opt/mastodon/bin"

# Ignoreing these here since we don't want to pin any versions and the Debian image removes apt-get content after use
# hadolint ignore=DL3008,DL3009
RUN apt-get update && \
    echo "Etc/UTC" > /etc/localtime && \
    groupadd -g "${GID}" mastodon && \
    useradd -l -u "$UID" -g "${GID}" -m -d /opt/mastodon mastodon && \
    apt-get -y --no-install-recommends install whois \
        wget \
        procps \
        libssl1.1 \
        libpq5 \
        ffmpeg \
        libjemalloc2 \
        libicu67 \
        libidn11 \
        libyaml-0-2 \
        file \
        ca-certificates \
        tzdata \
        libreadline8 \
        tini && \
    ln -s /opt/mastodon /mastodon

RUN mkdir ./build-temp && \
    cd ./build-temp && \
    apt-get -y install --no-install-recommends autoconf make gcc pkg-config automake libtool && \
    wget https://github.com/file/file/archive/refs/tags/FILE5_44.tar.gz && \
    tar xzf FILE5_44.tar.gz && \
    cd "$(tar tzf FILE5_44.tar.gz | sed -e 's@/.*@@' | sort | uniq | head -n 1)" && \
    autoreconf --install --force && ./configure && make && make install && \
    apt-get -y remove libmagic-mgc libmagic-dev && \
    cd magic && make install && \
    cd ../../../ && rm -rf ./build-temp

RUN mkdir ./build-temp && \
    cd ./build-temp && \
    wget https://imagemagick.org/archive/ImageMagick.tar.gz && \
    tar xzf ImageMagick.tar.gz && \
    cd "$(tar tzf ImageMagick.tar.gz | sed -e 's@/.*@@' | sort | uniq | head -n 1)" && \
    apt-get -y --no-install-recommends install \
        make gcc g++ pkg-config \
        libjpeg-dev libpng-dev libpng16-16 libltdl-dev libheif-dev libraw-dev libtiff-dev libopenjp2-tools libopenjp2-7-dev libjpeg-turbo-progs libfreetype6-dev libheif-dev libfreetype6-dev libopenexr-dev libwebp-dev libgif-dev && \
    ./configure --with-modules --enable-file-type --with-quantum-depth=32 --with-jpeg=yes --with-png=yes --with-gif=yes --with-webp=yes --with-heic=yes --with-raw=yes --with-tiff=yes --with-openjp2 --with-freetype=yes --with-webp=yes --with-openexr=yes --with-gslib=yes --with-gif=yes --with-perl=yes --with-jxl=yes && \
    make && make install && \
    ldconfig /usr/local/lib && \
    cd ../../ && \
    rm -rf ./build-temp

# Note: no, cleaning here since Debian does this automatically
# See the file /etc/apt/apt.conf.d/docker-clean within the Docker image's filesystem

COPY --chown=mastodon:mastodon . /opt/mastodon
COPY --chown=mastodon:mastodon --from=build /opt/mastodon /opt/mastodon

ENV RAILS_ENV="production" \
    NODE_ENV="production" \
    RAILS_SERVE_STATIC_FILES="true" \
    BIND="0.0.0.0"

# Set the run user
USER mastodon
WORKDIR /opt/mastodon

# Precompile assets
RUN OTP_SECRET=precompile_placeholder SECRET_KEY_BASE=precompile_placeholder rails assets:precompile && \
    yarn cache clean

# Set the work dir and the container entry point
ENTRYPOINT ["/usr/bin/tini", "--"]
EXPOSE 3000 4000
