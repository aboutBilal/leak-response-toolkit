# syntax=docker/dockerfile:1
# The toolkit with every dependency, ready to run anywhere Docker runs.
#
#   docker run --rm -v "$PWD:/repo" ghcr.io/aboutbilal/leak-response-toolkit audit /repo
#   docker run --rm -v "$PWD:/repo" ghcr.io/aboutbilal/leak-response-toolkit scan /repo     (report: ./secrets-report.json)
#   docker run --rm -v "$PWD:/work" -w /work ghcr.io/aboutbilal/leak-response-toolkit hunt --since 2026-01-01 owner/repo
#   (results are written to the mounted folder; add -e GITHUB_TOKEN for higher API limits)
#
# Built on the official gitleaks image, so scans use the same pinned gitleaks as CI.
FROM ghcr.io/gitleaks/gitleaks:v8.30.1@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f

RUN apk add --no-cache bash coreutils curl jq util-linux-misc ca-certificates \
 && git config --system --add safe.directory '*' \
 && adduser -D -u 10001 leak

COPY --chown=root:root leak LICENSE /opt/leak-response-toolkit/
COPY --chown=root:root scripts/ /opt/leak-response-toolkit/scripts/
COPY --chown=root:root templates/ /opt/leak-response-toolkit/templates/
COPY --chown=root:root prevention/ /opt/leak-response-toolkit/prevention/
RUN ln -s /opt/leak-response-toolkit/leak /usr/local/bin/leak

ENV HOME=/tmp
USER 10001
WORKDIR /repo
ENTRYPOINT ["leak"]
CMD ["help"]

LABEL org.opencontainers.image.title="Leak Response Toolkit" \
      org.opencontainers.image.description="Prevent secret leaks and respond in minutes: scan, audit, hunt copies, report." \
      org.opencontainers.image.source="https://github.com/aboutBilal/leak-response-toolkit" \
      org.opencontainers.image.licenses="MIT"
