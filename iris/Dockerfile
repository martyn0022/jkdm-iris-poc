# Official InterSystems Community image.
#
# NOT intersystemsdc/iris-community - that community-maintained image
# runs an "iris-after-start" hook which fails on current builds
# (dbapi.connect wrapper error) and takes the container down with it.
FROM containers.intersystems.com/intersystems/iris-community:latest-em

USER root

# The namespace database lives here rather than under the install's
# mgr directory. IRIS cannot create a subdirectory in mgr (it is mode
# 0700 and the server processes are not the session user), and the
# failure is quiet: CreateDatabase errors, the namespace is still
# configured pointing at the missing directory, and the whole thing
# only appears to work until the instance restarts.
RUN mkdir -p /opt/jkdm/db/jkdmpoc /opt/jkdm/db/prototype
COPY src/           /opt/jkdm/src/
COPY prototype-src/ /opt/jkdm/prototype-src/
COPY schema/     /opt/jkdm/schema/
COPY iris.script /opt/jkdm/

RUN chown -R ${ISC_PACKAGE_MGRUSER}:${ISC_PACKAGE_IRISGROUP} /opt/jkdm && \
    chmod 770 /opt/jkdm/db

USER ${ISC_PACKAGE_MGRUSER}

# Load and compile at build time so the container starts ready.
RUN iris start IRIS quietly && \
    iris session IRIS < /opt/jkdm/iris.script && \
    iris stop IRIS quietly

EXPOSE 1972 52773
