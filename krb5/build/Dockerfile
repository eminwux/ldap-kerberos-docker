# Start with the debian:bookworm-slim image
FROM debian:bookworm-slim

# Set environment variable to non-interactive
ENV DEBIAN_FRONTEND=noninteractive

ENV INIT=false

ENV KERBEROS_KDC_PASSWORD=password
ENV KERBEROS_KADMIN_PASSWORD=password
ENV KERBEROS_MASTER_PASSWORD=password
ENV KERBEROS_REALM=EXAMPLE.COM

# Install necessary packages
RUN apt-get update -yqq && \
    apt-get install -yqq \
    krb5-admin-server \
    krb5-kdc-ldap \
    netcat-traditional \
    gettext-base \
    procps \
    vim

# Clean up
RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir /app
RUN cp -r /etc/krb5kdc /opt

EXPOSE 88
# Set the default command
ENTRYPOINT ["/app/entrypoint.sh"]
