FROM debian:bookworm-slim

LABEL maintainer="shelgeyr"
LABEL description="gpsd + chrony GPS time server for Unraid"
LABEL org.opencontainers.image.source="https://github.com/shelgeyr/cothimich"
LABEL org.opencontainers.image.url="https://github.com/shelgeyr/cothimich"

ENV DEBIAN_FRONTEND=noninteractive

# Prevent services from auto-starting during apt install
RUN printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d \
    && chmod +x /usr/sbin/policy-rc.d

RUN apt-get update && apt-get install -y --no-install-recommends \
    gpsd \
    gpsd-clients \
    chrony \
    socat \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Remove the policy override now that packages are installed
RUN rm -f /usr/sbin/policy-rc.d

# Create runtime directories with correct ownership
RUN mkdir -p /run/chrony /var/lib/chrony /var/log/chrony /run/gpsd \
    && chown -R _chrony:_chrony /run/chrony /var/lib/chrony /var/log/chrony \
    && chmod 750 /run/chrony \
    && chmod 755 /var/lib/chrony /var/log/chrony

# Copy configs
COPY chrony.conf /etc/chrony/chrony.conf
COPY gpsd.conf /etc/default/gpsd
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

EXPOSE 2947/tcp
EXPOSE 123/udp

ENTRYPOINT ["/entrypoint.sh"]
