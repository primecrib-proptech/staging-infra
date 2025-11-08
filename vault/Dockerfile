 FROM hashicorp/vault:1.17
 USER root
 RUN apt-get update -y && \
     apt-get install -y --no-install-recommends curl wget netcat-openbsd postgresql-client gettext-base && \
     apt-get clean && rm -rf /var/lib/apt/lists/*
 USER vault
 COPY entrypoint.sh /vault/entrypoint.sh
 RUN chmod +x /vault/entrypoint.sh