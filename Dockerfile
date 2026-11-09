# syntax=docker/dockerfile:1
ARG UID=1001
ARG GID=1001
ARG VERSION=latest
ARG RELEASE=0

FROM alpine:3.23.5 AS base

# Create user
ARG UID
RUN adduser -g "" -D $UID -u $UID -G root

RUN --mount=type=cache,sharing=locked,target=/var/cache/apk \
    apk update && apk add curl jq

FROM base AS final

WORKDIR /app

COPY --link --chown=$UID:0 --chmod=775 poorman.sh sample.sh .

USER $UID

CMD ["echo", "Try ./sample.sh"]
