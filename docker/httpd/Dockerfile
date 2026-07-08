FROM ubuntu:24.04

# Prevent interactive prompts during installation
ENV DEBIAN_FRONTEND=noninteractive

# Install Apache and clean up package caches to keep the image small
RUN apt-get update && apt-get install -y \
    apache2 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Configure Apache to run in the foreground safely
ENV APACHE_RUN_USER=www-data
ENV APACHE_RUN_GROUP=www-data
ENV APACHE_LOG_DIR=/var/log/apache2
ENV APACHE_PID_FILE=/var/run/apache2/apache2.pid
ENV APACHE_RUN_DIR=/var/run/apache2
ENV APACHE_LOCK_DIR=/var/lock/apache2

# Ensure runtime directories exist
RUN mkdir -p $APACHE_RUN_DIR $APACHE_LOCK_DIR $APACHE_LOG_DIR

# Expose the standard unencrypted HTTP port
EXPOSE 80

# Start Apache in the foreground
CMD ["/usr/sbin/apache2", "-D", "FOREGROUND"]
