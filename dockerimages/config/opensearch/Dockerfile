# =====================================================================
# OpenSearch image for Magento / MageOS development.
# Thin layer over the official image that bakes in the two analysis
# plugins Magento requires (unicode tokenisation + phonetic search).
# The official image has no OPENSEARCH_PLUGINS env hook, so the plugins
# have to be installed at build time. Version comes from .env via the
# OPENSEARCH_VERSION build arg in compose.yaml.
# =====================================================================
ARG OPENSEARCH_VERSION=3.9.0
FROM opensearchproject/opensearch:${OPENSEARCH_VERSION}

RUN bin/opensearch-plugin install --batch analysis-icu analysis-phonetic
