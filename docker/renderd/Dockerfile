# ==============================================================================
# Helper Stage: Stylesheet Clone & Pruning
# ==============================================================================
FROM ubuntu:26.04@sha256:f3d28607ddd78734bb7f71f117f3c6706c666b8b76cbff7c9ff6e5718d46ff64 AS compiler-stylesheet
RUN apt-get update && apt-get install -y --no-install-recommends git-core ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /root
RUN git clone --branch v6.0.0 https://github.com/openstreetmap-carto/openstreetmap-carto.git --depth 1
WORKDIR /root/openstreetmap-carto
RUN sed -i 's/^--\s*GRANT SELECT ON carto_pois TO <render user>;/GRANT SELECT ON carto_pois TO _renderd;/' common-values.sql && \
    rm -rf .git

# ==============================================================================
# Main Target: Renderer
# ==============================================================================
FROM ubuntu:26.04@sha256:f3d28607ddd78734bb7f71f117f3c6706c666b8b76cbff7c9ff6e5718d46ff64

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN (groupadd -g 1001 _renderd 2>/dev/null || true) && \
    (useradd -u 1001 -g 1001 -m -d /home/_renderd -s /bin/bash _renderd 2>/dev/null || usermod -d /home/_renderd -s /bin/bash _renderd)

COPY NotoEmoji-Regular.ttf /usr/share/fonts/
COPY unifont-Medium.ttf /usr/share/fonts/

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    renderd \
    fonts-hanazono \
    fonts-noto-cjk \
    fonts-noto-hinted \
    fonts-noto-unhinted \
    sudo \
    fonts-unifont && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY renderd.conf /etc/renderd.conf

COPY --from=compiler-stylesheet /root/openstreetmap-carto /home/_renderd/src/openstreetmap-carto-backup

RUN mkdir -p /run/renderd/ /data/style/ /var/cache/renderd/tiles/ /home/_renderd/src/ && \
    chown -R _renderd: /data/ /home/_renderd/src/ /run/renderd /var/cache/renderd/tiles/

COPY renderd-entrypoint.sh /renderd-entrypoint.sh
RUN sed -i 's/\r$//' /renderd-entrypoint.sh && chmod +x /renderd-entrypoint.sh

ENTRYPOINT ["/renderd-entrypoint.sh"]
