# syntax = docker/dockerfile:1.2
FROM continuumio/miniconda3:latest
LABEL Name=jupyterserver Version=0.0.1
SHELL ["/bin/bash", "-c"]
RUN rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache
RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt \
    echo "Updating conda" 1>&2 \
    && apt-get update -y \
    && apt-get upgrade -y \
    && apt-get install -y gcc g++ make libunwind8 curl libcurl4-openssl-dev libssl-dev \
    && conda upgrade --all \
    && conda update -n base -c defaults conda -y \
    && echo "Installed: $(conda --version)" 1>&2
RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt \
    echo "Installing Base Jupyter" 1>&2 \
    && conda install -y jupyterlab ipykernel ipyparallel ipywidgets ipympl notebook \
    && conda install -y -c conda-forge ipyvolume bqplot calysto_bash allthekernels \
    && pip3 install calysto_scheme \
    && python3 -m calysto_scheme install 2>&1\
    && echo "Installed: Base Jupyter" 1>&2
ARG NODE_VERSION=15
ENV NODE_VERSION=${NODE_VERSION}
RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt \
    echo "Installing Node.JS" 1>&2 \
    && set -o pipefail \
    && (curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -) \
    && apt-get install -y nodejs \
    && npm install -g npm \
    && echo "Installed: Node.JS $(node --version)" 1>&2
RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt \
    echo "Installing node-based kernels (Typescript and Javascript)" 1>&2 \
    && npm install -g tslab \
    && tslab install --version \
    && tslab install --python=python3 \
    && conda install -y zeromq \
    && npm install -g ijavascript \
    && ijsinstall \
    && echo "Installed: node-based kernels (Typescript and Javascript)" 1>&2
RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt \
    echo "Installing R" 1>&2 \
    && conda install -y r-base r-repr r-irkernel r-irdisplay \
    && echo "Installed: R" 1>&2
RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt \
    echo "Installing BeakerX" 1>&2 \
    && conda install -y -c conda-forge ipywidgets beakerx \
    && jupyter nbextension enable beakerx --py --sys-prefix \
    && echo "Installed: BeakerX" 1>&2
# BeakerX will install JDK 8
ARG JDK_VERSION=8
ARG JDK_TYPE=hotspot-jre
ENV JDK_VERSION=${JDK_VERSION}
ENV JDK_TYPE=${JDK_TYPE}
RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt \
    if [ "${JDK_VERSION}" != 8 ]; then \
        echo "Installing Java" 1>&2 \
        && . /etc/os-release \
        && apt-get install -y wget apt-transport-https gnupg \
        && set -o pipefail \
        && (wget -qO - https://adoptopenjdk.jfrog.io/adoptopenjdk/api/gpg/key/public | apt-key add -) \
        && (echo "deb https://dl.bintray.com/sbt/debian /" | tee -a /etc/apt/sources.list.d/sbt.list ) \
        && (curl -sL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x2EE0EA64E40A89B84B2DF73499E82A75642AC823" | apt-key add -) \
        && (echo "deb https://adoptopenjdk.jfrog.io/adoptopenjdk/deb ${VERSION_CODENAME:-${UBUNTU_CODENAME}} main" | tee /etc/apt/sources.list.d/adoptopenjdk.list) \
        && apt-get update -y \
        && apt-get install sbt \
        && apt-get install -y adoptopenjdk-${JDK_VERSION}-${JDK_TYPE} \
        && echo Installed: $(java -version 2>&1) 1>&2 ; \
    else \
        echo "Skipped: Java" 1>&2 ; \
    fi
# Installs, but can't find the kernel's classes at runtime.
ARG INSTALL_ALMOND=NO
ENV INSTALL_ALMOND=${INSTALL_ALMOND}
RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt \
    if [ "${INSTALL_ALMOND}"  == "YES" ]; then \
        echo "Installing Almond Scala kernel" 1>&2 \
        && conda install -y -c conda-forge sbt \
        && set -o pipefail \
        && curl -Lo coursier https://git.io/coursier-cli \
        && chmod +x coursier \
        &&  (./coursier launch --fork almond:0.11.0 --scala 2.13 -- --install --global 2>&1 | egrep -v '^Download') \
        && rm -f coursier \
        && echo "Installed Almond Scala kernel" 1>&2 ; \
    else \
        echo "Almond Skipped" 1>&2 ; \
    fi
# Installs, but adds 1.77 GB to the build.
ARG INSTALL_SCILAB=NO
ENV INSTALL_SCILAB=${INSTALL_SCILAB}
RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt \
    if [ "${INSTALL_SCILAB}" == "YES" ]; then \
        echo "Installing scilab" 1>&2 \
        && conda install -y -c conda-forge scilab \
        && pip3 install scilab_kernel \
        && echo "Installed: Scilab" 1>&2 ; \
    else \
        echo "Scilab Skipped" 1>&2; \
    fi
# Gets 210 conflicts...
#RUN echo "Installing Octave" 1>&2 \
#    && conda install -y -c conda-forge octave octave_kernel \
#    && echo "Installed: Octave" 1>&2
# Can't install jupyterlab-sos because it downgrades nodejs, breaking the jupyterlab build.
RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt \
    echo "Installing SoS Workflows" \
    && conda install -y -c conda-forge sos sos-pbs sos-notebook sos-papermill sos-bash sos-matlab sos-python sos-r \
    && echo "Installed: SoS Workflows"
RUN echo "Adding jupyter user and group" \
    && groupadd -r jupyter \
    && useradd --no-log-init -r -g jupyter jupyter
RUN echo "Building Jupyter web application with Nodejs $(node --version)" 1>&2 \
    && jupyter kernelspec list \
    && (jupyter lab build --minimize=False --dev-build=False || (cat /tmp/*.log 1>&2; exit 1))\
    && echo "Jupyter build Complete, creating final image" 1>&2
ENV JUPYTER_PORT=8888
USER jupyter:jupyter
WORKDIR /home/jupyter
ENTRYPOINT [ "/opt/conda/bin/jupyter", "lab", "--port=8888", "--notebook-dir=/home/jupyter", "--ip=0.0.0.0" ]
EXPOSE 8888