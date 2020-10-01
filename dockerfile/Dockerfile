FROM registry.digitalocean.com/cwimmer/alpine:intermediate

LABEL maintainer="Charles A. Wimmer <charles@wimmer.net>"

RUN apk update && \
        apk upgrade --available && \
        rm -rf /var/cache/apk/*

