
######
## Prototype UC San Diego Datahub/DSMLP Matlab-enabled container
## 11/2022 agt@ucsd.edu

FROM ucsdets/datahub-base-notebook:2022.1-stable
# Could be: #FROM ucsdets/scipy-ml-notebook:2022.1-stable

# Adding additional Ubuntu packages or pip/conda packages?  See "additional local customization" below

# Which MATLAB release to install in the container, and where.
# Use lower case to specify the release, for example: ARG MATLAB_RELEASE=r2021b
ARG MATLAB_RELEASE=r2022a
ARG MATLAB_INSTALL_DIR=/opt/matlab/${MATLAB_RELEASE}

# Specify which products (Matlab, toolboxes) to be installed using "mpm": 
#        https://github.com/mathworks-ref-arch/matlab-dockerfile/blob/main/MPM.md
# In brief: toolbox name format retains capitalization, replaces spaces with underlines.
# Warning: these toolboxes can be huge.  Keep an eye on image size.
ARG MATLAB_PRODUCTS="MATLAB Statistics_and_Machine_Learning_Toolbox"

# See notes in matlab-deps Dockerfile regarding additional dependencies for specific Toolboxes:
#     https://github.com/mathworks-ref-arch/container-images/blob/main/matlab-deps/r2022b/ubuntu20.04/Dockerfile
#  Add these to ./additional-matlab-dependencies.txt

# Include docs/examples. Comment out to omit.
ARG MATLAB_DOC="--doc"

#############################################
# Few user-servicable parts between this line 
# and "additional local customization" section at end.

USER root

# Targeting a new OS will likely require updates to commands below
ARG TARGET_MATLAB_OS="ubuntu20.04"

# Ensure our base Datahub image matches Matlab target
RUN . /etc/os-release;  [ "${ID}${VERSION_ID}" = "$TARGET_MATLAB_OS" ] || \
	( echo "Mismatch between base Datahub OS ${ID}${VERSION_ID} & target Matlab OS ${TARGET_MATLAB_OS}!!"; exit 1 )

##########################################################
# Pull matlab-deps container base OS package deps (Many of these dependencies already exist in our container)
ARG MATLABDEPS_BASE_DEPS=https://raw.githubusercontent.com/mathworks-ref-arch/container-images/main/matlab-deps/${MATLAB_RELEASE}/${TARGET_MATLAB_OS}/base-dependencies.txt

RUN curl -L -s -o /tmp/base-dependencies.txt ${MATLABDEPS_BASE_DEPS} \
	&& apt-get update && apt-get install --no-install-recommends -y `cat /tmp/base-dependencies.txt` \
	&& apt-get clean && apt-get -y autoremove && rm -rf /var/lib/apt/lists/* 

##########################################################
# Additional packages & config needed for Web usage (gleaned from 'docker history mathworks/matlab:r2022b')
COPY additional-matlab-dependencies.txt /tmp/additional-matlab-dependencies.txt
RUN apt-get update && apt-get install --no-install-recommends -y `cat /tmp/additional-matlab-dependencies.txt`     && apt-get clean && apt-get -y autoremove && rm -rf /var/lib/apt/lists/* 
RUN mkdir -p "/usr/share/X11/xkb"

##########################################################
# Patch Ubuntu for GLIBC bz-19329 (thread creation vs shared library loading race)
# Pulled from mathworks/matlab-deps:r2022a  
# See: https://github.com/mathworks/build-glibc-bz-19329-patch
# IMPORTANT: This must be executed after any glibc updates 
RUN mkdir -p /packages
WORKDIR /packages
RUN export DEBIAN_FRONTEND=noninteractive &&    \
	wget -q https://github.com/mathworks/build-glibc-bz-19329-patch/releases/download/ubuntu-focal/all-packages.tar.gz && \
	tar -x -f all-packages.tar.gz --exclude glibc-*.deb --exclude libc6-dbg*.deb && \
	apt-get install --yes --no-install-recommends ./*.deb && \
	rm -fr /packages 
WORKDIR /

###############################
# Commands below cherrypicked from matlab-docker/Dockerfile
# Copyright 2019 - 2022 The MathWorks, Inc.

# Run mpm to install MATLAB in the target location and delete the mpm installation afterwards.
# If mpm fails to install successfully then output the logfile to the terminal, otherwise cleanup.
RUN wget -q https://www.mathworks.com/mpm/glnxa64/mpm \ 
    && chmod +x mpm \
    && ionice -c 3 ./mpm install \
    --release=${MATLAB_RELEASE} \
    --destination=${MATLAB_INSTALL_DIR} \
    --products ${MATLAB_PRODUCTS} \
    ${MATLAB_DOC} \
    || (echo "MPM Installation Failure. See below for more information:" && cat /tmp/mathworks_root.log && false) \
    && rm -f mpm /tmp/mathworks_root.log \
    && ln -s ${MATLAB_INSTALL_DIR}/bin/matlab /usr/local/bin/matlab 

# The following environment variables allow MathWorks to understand how this MathWorks 
# product (MATLAB Dockerfile) is being used. This information helps us make MATLAB even better. 
# Your content, and information about the content within your files, is not shared with MathWorks. 
# To opt out of this service, delete the environment variables defined in the following line. 
# See the Help Make MATLAB Even Better section in the accompanying README to learn more: 
# https://github.com/mathworks-ref-arch/matlab-dockerfile#help-make-matlab-even-better
ENV MW_DDUX_FORCE_ENABLE=true MW_CONTEXT_TAGS=MATLAB:DOCKERFILE:V1

#########
#### Matlab-specific local customization:
# Setup our /opt/conda environment for proxying Matlab & running Matlab from Python
RUN python3 -m pip install matlab-proxy jupyter-matlab-proxy 
RUN ( cd ${MATLAB_INSTALL_DIR}/extern/engines/python && python setup.py install )

# Supplement our runtime path, datahub-specific
RUN mkdir -p -m 0755 /etc/datahub-profile.d && \
	echo "export PATH=${MATLAB_INSTALL_DIR}/bin:\${PATH}" > /etc/datahub-profile.d/matlab-path.sh

##################################################################
# additional local customization 
#
# Your course/context specific tweaks (e.g. conda/pip install) go here 
#
# e.g.
#
# RUN apt-get -y install htop
# RUN pip install --no-cache-dir \
#     keras==2.6.0 \
#     tensorflow==2.8 \
#     tensorflow-gpu==2.8 && \
#     fix-permissions $CONDA_DIR && \
#     fix-permissions /home/$NB_USER


RUN pip install imatlab && python -mimatlab install
RUN conda install --freeze-installed --yes \
    sos sos-notebook jupyterlab-sos sos-python sos-bash -c conda-forge

## END:
## Reset back to unprivileged default user
USER jovyan

