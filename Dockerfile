FROM ubuntu:focal as build

ARG PYTHON_MAJOR_VERSION=3
ARG PYTHON_MINOR_VERSION=8
ARG REQUIRED_PACKAGES="python${PYTHON_MAJOR_VERSION}.${PYTHON_MINOR_VERSION}-minimal libpython${PYTHON_MAJOR_VERSION}.${PYTHON_MINOR_VERSION}-minimal libpython${PYTHON_MAJOR_VERSION}.${PYTHON_MINOR_VERSION}-stdlib  python${PYTHON_MAJOR_VERSION}-distutils nodejs=14.* openjdk-11-jdk-headless=11.0.11* graphviz ttf-dejavu fontconfig"


ENV ROOTFS /build/rootfs
ENV BUILD_DEBS /build/debs
ENV DEBIAN_FRONTEND=noninteractive

# Build pre-requisites
RUN bash -c 'mkdir -p ${BUILD_DEBS} ${ROOTFS}/{bin,sbin,usr/share,usr/bin,usr/sbin,usr/lib,/usr/local/bin,etc,container_user_home}'

# Fix permissions
RUN chown -Rv 100:root $BUILD_DEBS

# Install pre-requisites
RUN apt-get update \
        && apt-get -y install apt-utils locales build-essential cmake python3 python3-pip curl coreutils

# Get nodejs
RUN curl -sL https://deb.nodesource.com/setup_14.x | bash - && \
      apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 23E7166788B63E1E && \
      echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list && \
      apt-get update && \
      apt-get -y install yarn

# Build environment
RUN apt-get install -y ca-certificates \
      && update-ca-certificates

# Unpack required packges to rootfs
RUN cd ${BUILD_DEBS} \
  && for pkg in $REQUIRED_PACKAGES; do \
       apt-get download $pkg \
         && apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances --no-pre-depends -i $pkg | grep -v jre-headless | grep '^[a-zA-Z0-9]' | xargs apt-get download ; \
     done
RUN if [ "x$(ls ${BUILD_DEBS}/)" = "x" ]; then \
      echo No required packages specified; \
    else \
      for pkg in ${BUILD_DEBS}/*.deb; do \
        echo Unpacking $pkg; \
        dpkg -x $pkg ${ROOTFS}; \
      done; \
    fi

# Move /sbin out of the way
RUN mv ${ROOTFS}/sbin ${ROOTFS}/sbin.orig \
      && mkdir -p ${ROOTFS}/sbin \
      && for b in ${ROOTFS}/sbin.orig/*; do \
           echo 'cmd=$(basename ${BASH_SOURCE[0]}); exec /sbin.orig/$cmd "$@"' > ${ROOTFS}/sbin/$(basename $b); \
           chmod +x ${ROOTFS}/sbin/$(basename $b); \
         done

COPY entrypoint.sh ${ROOTFS}/usr/local/bin/entrypoint.sh
RUN chmod +x ${ROOTFS}/usr/local/bin/entrypoint.sh

RUN yarn global add npm --prefix /usr
RUN npm install --unsafe-perm --force --prefix ${ROOTFS}/usr -g @techdocs/cli@0.8.6
RUN pip3 install --upgrade --root ${ROOTFS} --force-reinstall mkdocs-techdocs-core==0.*

RUN curl -o plantuml.jar -L http://sourceforge.net/projects/plantuml/files/plantuml.1.2021.12.jar/download && \
      echo "a3d10c17ab1158843a7a7120dd064ba2eda4363f  plantuml.jar" | sha1sum -c - && \
      mv plantuml.jar ${ROOTFS}/usr/local/plantuml.jar && \
      echo $'#!/bin/sh\n\njava -jar '/usr/local/plantuml.jar' ${@}' >> /usr/local/bin/plantuml && \
      chmod 755 /usr/local/bin/plantuml

FROM actions/bash:5.0-2
LABEL maintainer = "ilja+docker@bobkevic.com"

ARG ROOTFS=/build/rootfs

ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8

COPY --from=build ${ROOTFS} /

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
