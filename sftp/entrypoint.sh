#!/bin/sh
set -e
# Host keys are generated on first boot rather than baked in - a key
# committed to a repo is a key everyone has.
ssh-keygen -A
# The bind mount replaces /home/dftz/inbound wholesale, hiding the
# directories the image created at build time. Recreate them here, on
# the mounted volume, so the drop works whatever state the host is in.
mkdir -p /home/dftz/inbound/cusdec /home/dftz/outbound

# Bind-mounted directories arrive owned by whatever the host says.
chown -R dftz /home/dftz/inbound /home/dftz/outbound 2>/dev/null || true
exec /usr/sbin/sshd -D -e
