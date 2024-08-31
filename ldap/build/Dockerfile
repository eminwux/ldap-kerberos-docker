# Start with the debian:bookworm-slim image
FROM debian:bookworm-slim

# Set environment variable to non-interactive
ENV DEBIAN_FRONTEND=noninteractive
ENV INIT=false
ENV LDAP_DEBUG=50
ENV LDAP_BASE_DN=dc=example,dc=com
ENV LDAP_REPLICATOR_PASSWORD=password
ENV LDAP_REPLICATOR_CREDENTIALS=replication
ENV LDAP_CONFIG_PASSWORD=password
ENV LDAP_ADMIN_PASSWORD=password
ENV KERBEROS_LDAP_CONTAINER=cn=krbContainer
ENV KERBEROS_KDC_PASSWORD=password
ENV KERBEROS_KADMIN_PASSWORD=password
ENV KERBEROS_MASTER_PASSWORD=password
ENV KERBEROS_REALM=EXAMPLE.COM

# Remove the specific line from the dpkg configuration file
RUN sed -i '/path-exclude \/usr\/share\/doc\/*/d' /etc/dpkg/dpkg.cfg.d/docker 

# Install necessary packages
RUN apt-get update -yqq && \
    apt-get install -yqq \
    slapd \
    schema2ldif \
    ldap-utils \
    debconf-utils \
    krb5-kdc-ldap \
    vim

# Clean up
RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Backup ldap default configuration
RUN mkdir /app
RUN cp -r /etc/ldap /opt

# Expose LDAP port
EXPOSE 389

# Set the default command
ENTRYPOINT ["/app/entrypoint.sh"]
