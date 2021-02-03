# Dockerfile to build docker-compose for aarch64
FROM arm64v8/python:3.9.1-buster as builder

ENV LANG C.UTF-8
# https://github.com/docker/compose/releases
ENV DOCKER_COMPOSE_VER 1.28.2
ENV DOCKER_COMPOSE_COMMIT "6763035"
# https://pypi.org/project/PyInstaller/#history
ENV PYINSTALLER_VER 4.2
# https://pypi.org/project/six/#history
ENV SIX_VER 1.15.0
# https://pypi.org/project/PyNaCl/#history
ENV PYNACL_VERSION 1.4.0

RUN apt-get update && apt-get install -qq --no-install-recommends unzip && pip install --upgrade pip && pip install six==$SIX_VER

# Compile the pyinstaller "bootloader"
# https://pyinstaller.readthedocs.io/en/stable/bootloader-building.html
WORKDIR /build/pyinstallerbootloader
RUN curl -fsSL https://github.com/pyinstaller/pyinstaller/releases/download/v$PYINSTALLER_VER/PyInstaller-$PYINSTALLER_VER.tar.gz | tar xvz >/dev/null \
    && cd PyInstaller*/bootloader \
    && python3 ./waf all

# Download docker-compose
WORKDIR /build/dockercompose
RUN curl -fsSL https://github.com/docker/compose/archive/$DOCKER_COMPOSE_VER.zip > $DOCKER_COMPOSE_VER.zip \
    && unzip $DOCKER_COMPOSE_VER.zip

# We need to patch pynacl because of https://github.com/pyca/pynacl/issues/553
COPY PyNaCl-remove-check.patch PyNaCl-remove-check.patch
RUN cd compose-$DOCKER_COMPOSE_VER && pip download --dest "/tmp/packages" -r requirements.txt -r requirements-build.txt wheel && cd .. && \
    wget -qO pynacl.tar.gz https://github.com/pyca/pynacl/archive/${PYNACL_VERSION}.tar.gz && \
    mkdir pynacl && tar --strip-components=1 -xvf pynacl.tar.gz -C pynacl && rm pynacl.tar.gz && \
    cd pynacl && \
    git apply ../PyNaCl-remove-check.patch && \
    python3 setup.py sdist && \
    cp -f dist/PyNaCl-${PYNACL_VERSION}.tar.gz /tmp/packages/ && \
    cd ../compose-$DOCKER_COMPOSE_VER && rm -rf ../pynacl && \
    pip install --no-index --find-links /tmp/packages -r requirements.txt -r requirements-build.txt && rm -rf /tmp/packages

RUN cd compose-$DOCKER_COMPOSE_VER \
    && echo ${DOCKER_COMPOSE_COMMIT} > compose/GITSHA \
    && pyinstaller docker-compose.spec \
    && mkdir /dist \
    && mv dist/docker-compose /dist/docker-compose

FROM arm64v8/alpine:3.13.1

COPY --from=builder /dist/docker-compose /tmp/docker-compose

# Copy out the generated binary
VOLUME /dist
CMD /bin/cp /tmp/docker-compose /dist/docker-compose