FROM debian:stretch-slim

# Dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libzmq5 \
    libgmp10 \
    netbase \
  && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /workdir/log

ENV LC_ALL C.UTF-8
ENV LANG C.UTF-8

ENV TZ=Europe/Moscow
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
RUN ldconfig

# Copy app
COPY mq-jobcontrol /workdir/
COPY config.json /workdir/

WORKDIR /workdir

# Defaults. Can be set as: docker run .. -e "config=config.json", etc.
ENV config "config.json"

ENTRYPOINT /workdir/mq-jobcontrol -f ${config}
