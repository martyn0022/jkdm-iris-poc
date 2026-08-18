# Official InterSystems Community image.
#
# Not intersystemsdc/iris-community: that community-maintained image
# runs an "iris-after-start" hook that fails on current builds
# (dbapi.connect wrapper error) and stops the container.
FROM containers.intersystems.com/intersystems/iris-community:latest-em

USER root

# The namespace database lives here rather than under the install's mgr
# directory, which is mode 0700 and not writable by the server
# processes. Creating it there fails quietly: CreateDatabase errors, the
# namespace is still configured against the missing directory, and the
# problem only surfaces on the next instance restart.
RUN mkdir -p /opt/jkdm/db/jkdmpoc /opt/jkdm/db/prototype
COPY src/           /opt/jkdm/src/
COPY prototype-src/ /opt/jkdm/prototype-src/
COPY schema/     /opt/jkdm/schema/
COPY iris.script /opt/jkdm/
COPY web/        /opt/jkdm/web/

RUN chown -R ${ISC_PACKAGE_MGRUSER}:${ISC_PACKAGE_IRISGROUP} /opt/jkdm && \
    chmod 770 /opt/jkdm/db

USER ${ISC_PACKAGE_MGRUSER}

# Load and compile at build time so the container starts ready.
RUN iris start IRIS quietly && \
    iris session IRIS < /opt/jkdm/iris.script && \
    iris stop IRIS quietly

EXPOSE 1972 52773
