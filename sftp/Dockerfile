# DFTZ partner SFTP drop.
#
# Built rather than pulled: atmoz/sftp publishes linux/amd64 only, so
# on Apple silicon it needs Rosetta and starts slower. alpine is
# multi-arch, so this runs natively everywhere.
FROM alpine:3.20

RUN apk add --no-cache openssh-server

# The partner account. Chroot requires /home/dftz itself to be
# root-owned and not group-writable; the drop directories underneath
# are the user's, because IRIS deletes each file after pulling it and
# writes acknowledgements back.
RUN adduser -D -u 1001 -s /sbin/nologin dftz \
    && echo 'dftz:dftz_poc' | chpasswd \
    && mkdir -p /home/dftz/inbound/cusdec /home/dftz/outbound \
    && chown root:root /home/dftz \
    && chmod 755 /home/dftz

COPY sshd_config /etc/ssh/sshd_config
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22
CMD ["/entrypoint.sh"]
