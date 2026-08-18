#!/bin/sh
set -e
# Host keys are generated on first boot rather than baked in - a key
# committed to a repo is a key everyone has.
ssh-keygen -A
# Bind-mounted directories arrive owned by whatever the host says.
chown -R dftz /home/dftz/inbound /home/dftz/outbound 2>/dev/null || true
exec /usr/sbin/sshd -D -e
