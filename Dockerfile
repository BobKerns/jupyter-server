# syntax = docker/dockerfile:1.2

## Dockerfile for building a unified jupyterlab server.
## Be sure to allocate a sufficient amount of memory to docker, as the minify step in building
## jupyterlab extensions is a real memory hog.

FROM debian:latest as methane
# Conda version and SHA254 from https://conda.io/en/latest/miniconda_hashes.html
# Python version is constrained to 3.7 by BeakerX, and to <3.9 by several packages
ARG PYTHON_VERSION=3.7
# Be sure to set CONDA_SH256 to the hash corresponding to the CONDA_VERSION and PYTHON_VERSION
ARG CONDA_VERSION=4.9.2
ARG CONDA_SH256=79510c6e7bd9e012856e25dcb21b3e093aa4ac8113d9aa7e82a86987eabe1c31
# Make the arguments available as environment variables.
ENV CONDA_VERSION=${CONDA_VERSION}
ENV PYTHON_VERSION=${PYTHON_VERSION}
# Default shell (dash) doesn't support set -o pipefail.
SHELL ["/bin/bash", "-c"]

# Don't build in root
WORKDIR /home/jupyter

# Configure
RUN 1>&2 echo "Adding jupyter user and group" \
    && groupadd -r jupyter \
    && useradd --no-log-init -r -g jupyter jupyter \
    && mkdir /jupyter \
    && mkdir /jupyter/user \
    && mkdir /jupyter/content \
    && chown -R jupyter:jupyter . \
    && chown -R jupyter:jupyter /jupyter \
    && chmod a-w /jupyter

RUN rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt \
    1>&2 echo "Installing base dependencies" \
    && apt-get update \
    && apt-get install -y \
        gcc \
        g++ \
        make \
        libunwind8 \
        curl \
        wget \
        libcurl4-openssl-dev \
        libssl-dev \
        rsync \
    && 1>&2 echo "Installed: base dependencies"

RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt \
    1>&2 echo "Installing conda ${CONDA_VERSION}" \
    && wget --quiet https://repo.anaconda.com/miniconda/Miniconda3-py${PYTHON_VERSION/./}_${CONDA_VERSION}-Linux-x86_64.sh -O miniconda.sh \
    && echo "${CONDA_SH256}  miniconda.sh" > miniconda.sha256 \
    && if ! sha256sum --status -c miniconda.sha256; then \
        1>&2 echo "conda checksums did not match." ; \
        exit 1; \
    fi \
    && mkdir -p /opt \
    && sh miniconda.sh -b -p /opt/conda \
    && rm miniconda.sh miniconda.sha256 \
    && ln -s /opt/conda/etc/profile.d/conda.sh /etc/profile.d/conda.sh \
    && echo ". /opt/conda/etc/profile.d/conda.sh" >> ~/.bashrc \
    && echo "conda activate base" >> ~/.bashrc \
    && find /opt/conda/ -follow -type f -name '*.a' -delete \
    && find /opt/conda/ -follow -type f -name '*.js.map' -delete \
    && /opt/conda/bin/conda clean -afy \
    && find /opt/conda \! -type l \! \( -perm -660 -user jupyter -group jupyter \) -exec chmod u+rw,g+rw {} + -exec chown jupyter:jupyter {} + \
    && 1>&2 echo "Installed: $(/opt/conda/bin/conda --version)"

ENV PATH=/opt/conda/bin:$PATH

RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt \
    1>&2 echo "Installing Base Jupyter" \
    && conda install -y \
        jupyterlab \
        ipykernel \
        ipyparallel \
        ipywidgets \
        ipympl \
        notebook \
    && conda install -y -c conda-forge \
        ipyvolume \
        bqplot \
        calysto_bash \
        allthekernels \
    && pip3 install \
        calysto_scheme \
    && python3 -m calysto_scheme install 2>&1 \
    && conda clean -t -y \
    && conda clean -p -y \
    && find /opt/conda \! -type l \! \( -perm -660 -user jupyter -group jupyter \) -exec chmod u+rw,g+rw {} + -exec chown jupyter:jupyter {} + \
    && 1>&2 echo "Installed: Base Jupyter"

ARG NODE_VERSION=15
ENV NODE_VERSION=${NODE_VERSION}
RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt \
    1>&2 echo "Installing Node.JS" \
    && set -o pipefail \
    && (curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -) \
    && apt-get install -y \
        nodejs \
    && npm install -g \
        npm \
    && 1>&2 echo "Installed: Node.JS $(node --version)"

RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt \
    1>&2 echo "Installing node-based kernels (Typescript and Javascript)" \
    && npm install -g \
        tslab \
    && tslab install --python=python3 \
    && conda install -y \
        zeromq \
    && npm install -g \
        ijavascript \
    && ijsinstall \
    && conda clean -t -y \
    && conda clean -p -y \
    && find /opt/conda \! -type l \! \( -perm -660 -user jupyter -group jupyter \) -exec chmod u+rw,g+rw {} + -exec chown jupyter:jupyter {} + \
    && 1>&2 echo "Installed: node-based kernels (Typescript and Javascript)"

RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt \
    1>&2 echo "Installing R" \
    && apt-get install -y \
        libcairo2-dev \
    && conda install -y \
        r-base \
        r-repr \
        r-irkernel \
        r-irdisplay \
    && conda clean -t -y \
    && conda clean -p -y \
    && find /opt/conda \! -type l \! \( -perm -660 -user jupyter -group jupyter \) -exec chmod u+rw,g+rw {} + -exec chown jupyter:jupyter {} + \
    && 1>&2 echo "Installed: R"

ARG INSTALL_BEAKERX=NO
ENV INSTALL_BEAKERX=${INSTALL_BEAKERX}
RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt \
    if [ "${INSTALL_BEAKERX}" == "YES" ]; then \
        1>&2 echo "Installing BeakerX" \
        && conda install -y -c conda-forge \
            ipywidgets \
            bottle \
        && npm install \
            @types/three \
            typescript \
        && (conda install -y -c beakerx \
            beakerx_tabledisplay=2.1.0 \
            beakerx_all || ( \
                1>&1 cat /tmp/*.log \
                exit 1)) \
        && conda clean -t -y \
        && conda clean -p -y \
        && find /opt/conda \! -type l \! \( -perm -660 -user jupyter -group jupyter \) -exec chmod u+rw,g+rw {} + -exec chown jupyter:jupyter {} + \
        && 1>&2 echo "Installed: BeakerX" \
    else \
        echo "BeakerX not installed."; \
    fi

# BeakerX will install JDK 8
ARG JDK_VERSION=8
ARG JDK_TYPE=hotspot-jre
ENV JDK_VERSION=${JDK_VERSION}
ENV JDK_TYPE=${JDK_TYPE}
RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt \
    if [ "${JDK_VERSION}" != 8 || "${INSTALL_BEAKERX}" != "YES" ]; then \
        1>&2 echo "Installing Java" \
        && . /etc/os-release \
        && apt-get install -y \
            wget \
            apt-transport-https \
            gnupg \
        && set -o pipefail \
        && (wget -qO - https://adoptopenjdk.jfrog.io/adoptopenjdk/api/gpg/key/public | apt-key add -) \
        && (echo "deb https://dl.bintray.com/sbt/debian /" | tee -a /etc/apt/sources.list.d/sbt.list ) \
        && (curl -sL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x2EE0EA64E40A89B84B2DF73499E82A75642AC823" | apt-key add -) \
        && (echo "deb https://adoptopenjdk.jfrog.io/adoptopenjdk/deb ${VERSION_CODENAME:-${UBUNTU_CODENAME}} main" | tee /etc/apt/sources.list.d/adoptopenjdk.list) \
        && apt-get update -y \
        && apt-get install \
            sbt \
        && apt-get install -y \
            adoptopenjdk-${JDK_VERSION}-${JDK_TYPE} \
        && 1>&2 echo "Installed: $(java -version 2>&1)" ; \
    else \
        1>&2 echo "Skipped: Java" ; \
    fi

# Installs, but can't find the kernel's classes at runtime.
ARG INSTALL_ALMOND=NO
ENV INSTALL_ALMOND=${INSTALL_ALMOND}
RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt \
    if [ "${INSTALL_ALMOND}"  == "YES" ]; then \
        1>&2 echo "Installing Almond Scala kernel" \
        && conda install -y -c conda-forge \
            sbt \
        && set -o pipefail \
        && curl -Lo coursier https://git.io/coursier-cli \
        && chmod +x coursier \
        &&  (./coursier launch --fork almond:0.11.0 --scala 2.13 -- --install --global 2>&1 | egrep -v '^Download') \
        && rm -f coursier \
        && conda clean -t -y \
        && conda clean -p -y \
        && find /opt/conda \! -type l \! \( -perm -660 -user jupyter -group jupyter \) -exec chmod u+rw,g+rw {} + -exec chown jupyter:jupyter {} + \
        && 1>&2 echo "Installed Almond Scala kernel" ; \
    else \
        1>&2 echo "Almond Skipped" ; \
    fi

# Installs, but adds 1.77 GB to the build.
ARG INSTALL_SCILAB=NO
ENV INSTALL_SCILAB=${INSTALL_SCILAB}
RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt \
    if [ "${INSTALL_SCILAB}" == "YES" ]; then \
        1>&2 echo "Installing scilab" \
        && conda install -y -c conda-forge \
            scilab \
        && pip3 install \
            scilab_kernel \
        && conda clean -t -y \
        && conda clean -p -y \
        && find /opt/conda \! -type l \! \( -perm -660 -user jupyter -group jupyter \) -exec chmod u+rw,g+rw {} + -exec chown jupyter:jupyter {} + \
        && 1>&2 echo "Installed: Scilab" ; \
    else \
        1>&2 echo "Scilab Skipped" ; \
    fi

# Gets 210 conflicts...
#RUN echo "Installing Octave" 1>&2 \
#    && conda install -y -c conda-forge octave octave_kernel \
#    && echo "Installed: Octave" 1>&2
# Can't install jupyterlab-sos because it downgrades nodejs, breaking the jupyterlab build.
RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt \
    1>&2 echo "Installing SoS Workflows" \
    && conda install -y -c conda-forge \
        sos \
        sos-pbs \
        sos-notebook \
        sos-papermill \
        sos-bash \
        sos-matlab \
        sos-python \
        sos-r \
    && conda clean -t -y \
    && conda clean -p -y \
    && find /opt/conda \! -type l \! \( -perm -660 -user jupyter -group jupyter \) -exec chmod u+rw,g+rw {} + -exec chown jupyter:jupyter {} + \
    && 1>&2 echo "Installed: SoS Workflows"

RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt \
    1>&2 echo "Installing Renderers and extensions" \
    && conda install -c conda-forge -y \
        ipyleaflet \
        pythreejs \
        ipydatawidgets \
    && pip install \
        ipyturtle2 \
    #    jupyterlab_hdf \
    && jupyter labextension install --no-build @krassowski/jupyterlab_go_to_definition \
    && jupyter labextension install --no-build @jupyter-widgets/jupyterlab-manager \
    && jupyter labextension install --no-build jupyterlab-datawidgets \
    && jupyter labextension install --no-build jupyter-leaflet \
    && jupyter labextension install --no-build @jupyterlab/geojson-extension \
    && jupyter labextension install --no-build @jupyterlab/fasta-extension \
    # && jupyter labextension install --no-build @jupyterlab/github \
    # && jupyter labextension install --no-build @jupyterlab/hdf5 \
    && jupyter labextension install --no-build jupyterlab-spreadsheet \
    && jupyter labextension install --no-build ipyturtle2 \
    && conda clean -t -y \
    && conda clean -p -y \
    && find /opt/conda \! -type l \! \( -perm -660 -user jupyter -group jupyter \) -exec chmod u+rw,g+rw {} + -exec chown jupyter:jupyter {} + \
    && 1>&2 echo "Installed: Renderers and extensions"

RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt \
    1>&2 echo "Building Jupyter web application with Nodejs $(node --version)" \
    && jupyter kernelspec list \
    && jupyter labextension list \
    && (jupyter lab build --minimize=False --dev-build=False || (cat /tmp/*.log 1>&2; exit 1))\
    && find /opt/conda \! -type l \! \( -perm -660 -user jupyter -group jupyter \) -exec chmod u+rw,g+rw {} + -exec chown jupyter:jupyter {} + \
    && jupyter notebook --generate-config \
    && 1>&2 echo "Jupyter build Complete, creating final image"

WORKDIR /home/jupyter
COPY jupyter_server_config.json .jupyter/jupyter_server_config.json
WORKDIR /jupyter
COPY content content

RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt \
    1>&2 echo "Set content permissions and ownership" \
    && chown -R jupyter:jupyter /home/jupyter /jupyter \
    && chmod a-w -R /jupyter \
    && chmod a+w -R /home/jupyter \
    && 1>&2 ls -al /home/jupyter \
    && 1>&2 echo "Content installed."

FROM methane
LABEL Name=jupyterlab-server Version=0.0.1
ENV JUPYTER_PORT=8888
WORKDIR /jupyter
USER jupyter:jupyter
CMD [ "lab", "--port=8888", "--notebook-dir=/jupyter/user", "--ip=0.0.0.0" ]
ENTRYPOINT [ "/bin/bash", "-c", \
    "(test -z \"${NODEPLOY}\"  && \
    (rsync -r --exclude=content/examples/examples --exclude='.Trash-*' content/examples/ /jupyter/user/examples/; rsync -u content/README.md /jupyter/user/README.md));\
    /opt/conda/bin/jupyter \"$@\"", "--" ]
EXPOSE 8888