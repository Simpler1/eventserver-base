# syntax=docker/dockerfile:1
ARG ZM_VERSION=main
ARG ES_VERSION=master

#####################################################################
#                                                                   #
# Download ES                                                       #
#                                                                   #
#####################################################################
FROM alpine:latest AS eventserverdownloader
ARG ES_VERSION
WORKDIR /eventserverdownloader

RUN set -x \
    && apk add git \
    && git clone https://github.com/ZoneMinder/zmeventnotification.git . \
    && git checkout ${ES_VERSION}

#####################################################################
#                                                                   #
# Convert rootfs to LF using dos2unix                               #
# Alleviates issues when git uses CRLF on Windows                   #
#                                                                   #
#####################################################################
FROM alpine:latest as rootfs-converter
WORKDIR /rootfs

RUN set -x \
    && apk add --repository=http://dl-cdn.alpinelinux.org/alpine/edge/community/ \
        dos2unix

COPY root .
RUN set -x \
    && find . -type f -print0 | xargs -0 -n 1 -P 4 dos2unix \
    && chmod -R +x *

#####################################################################
#                                                                   #
# Install ES                                                        #
# Apply changes to default ES config                                #
#                                                                   #
#####################################################################
FROM ghcr.io/zoneminder-containers/zoneminder-base:${ZM_VERSION}
ARG ES_VERSION

RUN set -x \
    && apt-get update \
    && apt-get install -y \
        build-essential \
        libjson-perl \
    && PERL_MM_USE_DEFAULT=1 \
    && yes | perl -MCPAN -e "install Net::WebSocket::Server" \
    && yes | perl -MCPAN -e "install LWP::Protocol::https" \
    && yes | perl -MCPAN -e "install Config::IniFiles" \
    && yes | perl -MCPAN -e "install Time::Piece" \
    && yes | perl -MCPAN -e "install Net::MQTT::Simple" \
    && apt-get remove --purge -y \
        build-essential \
    && rm -rf /var/lib/apt/lists/*

RUN --mount=type=bind,target=/tmp/eventserver,source=/eventserverdownloader,from=eventserverdownloader,rw \
    set -x \
    && apt update \
    && apt install -y \
        python3 \
        python3-pip \
        vim \
    && rm /usr/lib/python3.*/EXTERNALLY-MANAGED \
    && pip install pyzm \
    && pip install opencv-python \
    && cd /tmp/eventserver \
    && mkdir -p /etc/zm \
#    && TARGET_CONFIG=/zoneminder/defaultconfiges \
    && MAKE_CONFIG_BACKUP='' \
        ./install.sh \
            --install-es \
            --install-hook \
            --install-config \
            --no-interactive \
            --no-pysudo \
            --hook-config-upgrade \
    && mkdir -p /zoneminder/estools \
    && cp ./tools/* /zoneminder/estools

# https://stackoverflow.com/a/16987794
# Set variables in initial secrets.ini
RUN set -x \
   && sed -i "/^\[secrets\]$/,/^\[/ s|^ES_CERT_FILE.*=.*|ES_CERT_FILE=/config/ssl/fullchain.pem|" /etc/zm/secrets.ini \
   && sed -i "/^\[secrets\]$/,/^\[/ s|^ES_KEY_FILE.*=.*|ES_KEY_FILE=/config/ssl/privkey.pem|" /etc/zm/secrets.ini

# Set variables in initial zmeventnotification.ini
RUN set -x \
    && sed -i "/^\[general\]$/,/^\[/ s|^secrets.*=.*|secrets=/config/secrets.ini|" /etc/zm/zmeventnotification.ini \
    && sed -i "/^\[fcm\]$/,/^\[/ s|^token_file.*=.*|token_file=/config/tokens.txt|" /etc/zm/zmeventnotification.ini \
    && sed -i "/^\[customize\]$/,/^\[/ s|^console_logs.*=.*|console_logs=yes|" /etc/zm/zmeventnotification.ini \
    && sed -i "/^\[customize\]$/,/^\[/ s|^use_hooks.*=.*|use_hooks=yes|" /etc/zm/zmeventnotification.ini \
    && sed -i "/^\[network\]$/,/^\[/ s|^.*address.*=.*|address=192.168.1.20|" /etc/zm/zmeventnotification.ini \
    && sed -i "/^\[auth\]$/,/^\[/ s|^enable.*=.*|enable=yes|" /etc/zm/zmeventnotification.ini

# Set variables in initial objectconfig.ini
RUN set -x \
    && sed -i "/^\[general\]$/,/^\[/ s|^secrets.*=.*|secrets=/config/secrets|" /etc/zm/objectconfig.ini

# Copy custom configuration files
COPY ./config/zmeventnotification.ini /etc/zm/
COPY ./config/objectconfig.ini /etc/zm/
COPY ./config/zm.conf /etc/zm/
COPY ./config/conf.d /etc/zm/conf.d/

# This actually sets the user and group to 911, but it seems to work.
# RUN set -x \
#     && chown -R www-data:www-data /etc/zm \
#     && chown -R www-data:www-data /var/lib/zmeventnotification

# Copy rootfs
COPY --from=rootfs-converter /rootfs /

ENV \
    ES_DEBUG_ENABLED=1 \
    ES_COMMON_NAME=localhost \
    ES_ENABLE_AUTH=0 \
    ES_ENABLE_DHPARAM=1 \
    USE_SECURE_RANDOM_ORG=1

LABEL \
    com.github.simpler1.es_version=${ES_VERSION}

EXPOSE 443/tcp
EXPOSE 9000/tcp
