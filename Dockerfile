ARG TERRAFORM_VERSION=1.13.4
ARG TERRAGRUNT_VERSION=0.91.4

FROM debian:bookworm-slim
SHELL ["/bin/bash","-o","pipefail","-c"]
ARG DEBIAN_FRONTEND=noninteractive

ARG TERRAFORM_VERSION
ARG TERRAGRUNT_VERSION

WORKDIR /app

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      wget \
      unzip \
      git \
      gnupg \
      lsb-release \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
      | gpg --dearmor -o /usr/share/keyrings/microsoft-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/microsoft-archive-keyring.gpg] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" \
      > /etc/apt/sources.list.d/azure-cli.list && \
    apt-get update && \
    apt-get install -y azure-cli && \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    TF_URL="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"; \
    TF_SUMS_URL="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS"; \
    cd /tmp; \
    curl -fsSLo terraform_${TERRAFORM_VERSION}_linux_amd64.zip "${TF_URL}"; \
    curl -fsSLo terraform_SHA256SUMS "${TF_SUMS_URL}"; \
    grep "linux_amd64.zip" terraform_SHA256SUMS | sha256sum -c -; \
    unzip terraform_${TERRAFORM_VERSION}_linux_amd64.zip -d /usr/local/bin/; \
    rm -f terraform_${TERRAFORM_VERSION}_linux_amd64.zip terraform_SHA256SUMS; \
    chmod +x /usr/local/bin/terraform

RUN set -eux; \
    TG_URL="https://github.com/gruntwork-io/terragrunt/releases/download/v${TERRAGRUNT_VERSION}/terragrunt_linux_amd64"; \
    TG_SHA_URL="https://github.com/gruntwork-io/terragrunt/releases/download/v${TERRAGRUNT_VERSION}/SHA256SUMS"; \
    cd /tmp; \
    curl -fsSLo terragrunt_linux_amd64 "${TG_URL}"; \
    curl -fsSLo terragrunt_SHA256SUMS "${TG_SHA_URL}"; \
    grep "terragrunt_linux_amd64" terragrunt_SHA256SUMS | sha256sum -c -; \
    mv terragrunt_linux_amd64 /usr/local/bin/terragrunt; \
    chmod +x /usr/local/bin/terragrunt; \
    rm -f terragrunt_SHA256SUMS

RUN apt-get remove -y wget unzip gnupg lsb-release && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

RUN useradd -m -u 10001 appuser && chown -R appuser:appuser /app
USER appuser
