# ./vault/Dockerfile
FROM hashicorp/vault:1.17

USER root
RUN apt-get update && apt-get install -y postgresql-client && rm -rf /var/lib/apt/lists/*
USER vault

ENTRYPOINT ["/bin/sh", "/vault/entrypoint.sh"]
