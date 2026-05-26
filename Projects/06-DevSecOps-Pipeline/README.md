# Project 6: DevSecOps Pipeline — Security at Every Stage

## Overview
Implement a complete DevSecOps pipeline that integrates security scanning, secrets detection, SBOM generation, image signing, and Kubernetes admission control to enforce policy at deployment time.

**Skills**: gitleaks, Semgrep, Trivy, Cosign, Syft, Kyverno, OPA/Gatekeeper, Falco, GitHub Actions

---

## Security Gate Map
```
┌─────────────────────────────────────────────────────────────────┐
│                    SECURITY GATES                               │
│                                                                 │
│  PRE-COMMIT         CI                 CD              RUNTIME  │
│  ──────────         ──                 ──              ───────  │
│  gitleaks     →  Semgrep SAST    →  Trivy scan  →  Falco       │
│  detect-secrets  Snyk SCA           SBOM generate   Kyverno    │
│  pre-commit      License check       Cosign sign    NetworkPol │
│  hooks           Coverage gate       OPA verify     PSA        │
│                  Checkov IaC         Kyverno admit             │
└─────────────────────────────────────────────────────────────────┘
```

---

## Project Structure
```
06-DevSecOps-Pipeline/
├── .github/
│   └── workflows/
│       ├── devsecops.yml           # Main security pipeline
│       └── sbom-weekly-rescan.yml  # Scheduled re-scan
├── .pre-commit-config.yaml
├── app/                            # Sample Python app
├── Dockerfile
├── k8s/
│   ├── kyverno/
│   │   ├── policy-require-labels.yaml
│   │   ├── policy-disallow-latest-tag.yaml
│   │   ├── policy-require-signed-images.yaml
│   │   └── policy-restrict-registries.yaml
│   └── falco/
│       └── custom-rules.yaml
└── scripts/
    ├── verify-image.sh
    └── audit-report.sh
```

---

## Step 1: Pre-Commit Hooks

**.pre-commit-config.yaml**
```yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.2
    hooks:
      - id: gitleaks
        name: Detect secrets with gitleaks

  - repo: https://github.com/Yelp/detect-secrets
    rev: v1.4.0
    hooks:
      - id: detect-secrets
        name: Detect secrets with detect-secrets
        args: ["--baseline", ".secrets.baseline"]

  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.5.0
    hooks:
      - id: check-yaml
      - id: check-json
      - id: check-merge-conflict
      - id: no-commit-to-branch
        args: [--branch, main, --branch, production]

  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.88.0
    hooks:
      - id: terraform_fmt
      - id: terraform_validate
      - id: terraform_tflint

  - repo: local
    hooks:
      - id: semgrep-pre-commit
        name: Semgrep quick scan
        entry: semgrep scan --config=p/python --error --quiet
        language: system
        types: [python]
        pass_filenames: true
```

---

## Step 2: Main DevSecOps Pipeline

**.github/workflows/devsecops.yml**
```yaml
name: DevSecOps Pipeline

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

env:
  REGISTRY: ghcr.io
  IMAGE: ${{ github.repository }}

jobs:

  # ── 1. SAST & SCA ─────────────────────────────────────────────
  code-security:
    name: SAST + SCA + License
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Semgrep SAST
        uses: semgrep/semgrep-action@v1
        with:
          config: >-
            p/python
            p/django
            p/secrets
            p/owasp-top-ten
        env:
          SEMGREP_APP_TOKEN: ${{ secrets.SEMGREP_APP_TOKEN }}

      - name: Snyk SCA
        uses: snyk/actions/python-3.10@master
        with:
          args: --severity-threshold=high --fail-on=all
        env:
          SNYK_TOKEN: ${{ secrets.SNYK_TOKEN }}

      - name: License check (forbidden licenses)
        run: |
          pip install pip-licenses
          pip-licenses --fail-on "GPL;AGPL;LGPL" --format=plain-vertical

  # ── 2. IaC Security ───────────────────────────────────────────
  iac-security:
    name: IaC Scanning
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Checkov scan
        uses: bridgecrewio/checkov-action@master
        with:
          directory: .
          output_format: sarif
          output_file_path: checkov-results.sarif
          soft_fail: false

      - uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: checkov-results.sarif

      - name: kubesec scan
        run: |
          find k8s/ -name "*.yaml" -not -path "*/kyverno/*" | while read f; do
            echo "Scanning: $f"
            SCORE=$(curl -sf "https://v2.kubesec.io/scan" -X POST --data-binary @"$f" \
              | jq -r '.[0].score')
            echo "Score: $SCORE for $f"
            if [[ "$SCORE" -lt 0 ]]; then
              echo "FAILED: $f has negative security score"
              exit 1
            fi
          done

  # ── 3. Container Build + Scan ─────────────────────────────────
  container-security:
    name: Build + Scan + Sign
    needs: [code-security, iac-security]
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
      id-token: write
      security-events: write

    steps:
      - uses: actions/checkout@v4

      - uses: docker/setup-buildx-action@v3

      - name: Login to registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build image
        id: build
        uses: docker/build-push-action@v5
        with:
          context: .
          push: false
          load: true
          tags: ${{ env.REGISTRY }}/${{ env.IMAGE }}:${{ github.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Trivy — fail on CRITICAL
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ env.REGISTRY }}/${{ env.IMAGE }}:${{ github.sha }}
          format: sarif
          output: trivy-results.sarif
          severity: CRITICAL
          exit-code: 1
          ignore-unfixed: true

      - uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: trivy-results.sarif

      - name: Trivy — HIGH severity report (non-blocking)
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ env.REGISTRY }}/${{ env.IMAGE }}:${{ github.sha }}
          format: table
          severity: HIGH
          exit-code: 0

      - name: Generate SBOM with Syft
        uses: anchore/sbom-action@v0
        with:
          image: ${{ env.REGISTRY }}/${{ env.IMAGE }}:${{ github.sha }}
          format: spdx-json
          output-file: sbom.spdx.json

      - name: Scan SBOM with Grype
        uses: anchore/scan-action@v3
        with:
          sbom: sbom.spdx.json
          fail-build: true
          severity-cutoff: critical

      - name: Push image (main branch only)
        if: github.ref == 'refs/heads/main'
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: ${{ env.REGISTRY }}/${{ env.IMAGE }}:${{ github.sha }}
          cache-from: type=gha

      - name: Sign image with Cosign (keyless)
        if: github.ref == 'refs/heads/main'
        uses: sigstore/cosign-installer@v3

      - name: Sign and attach SBOM
        if: github.ref == 'refs/heads/main'
        run: |
          cosign sign --yes \
            "${{ env.REGISTRY }}/${{ env.IMAGE }}:${{ github.sha }}"
          cosign attach sbom --sbom sbom.spdx.json \
            "${{ env.REGISTRY }}/${{ env.IMAGE }}:${{ github.sha }}"
        env:
          COSIGN_EXPERIMENTAL: "1"

  # ── 4. Security Report ────────────────────────────────────────
  security-summary:
    name: Security Summary
    needs: [container-security]
    if: always()
    runs-on: ubuntu-latest
    steps:
      - name: Post security summary to PR
        if: github.event_name == 'pull_request'
        uses: actions/github-script@v7
        with:
          script: |
            const needs = ${{ toJSON(needs) }};
            const jobs = Object.entries(needs);
            let summary = "## Security Gate Results\n\n| Check | Status |\n|-------|--------|\n";
            for (const [name, job] of jobs) {
              const icon = job.result === 'success' ? '✅' : '❌';
              summary += `| ${name} | ${icon} ${job.result} |\n`;
            }
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: summary
            });
```

---

## Step 3: Kyverno Policies

**k8s/kyverno/policy-disallow-latest-tag.yaml**
```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-latest-tag
  annotations:
    policies.kyverno.io/title: Disallow Latest Tag
    policies.kyverno.io/severity: medium
    policies.kyverno.io/description: >
      Prohibit using :latest tag since it makes tracing which image
      version is running impossible. Require explicit version tags.
spec:
  validationFailureAction: Enforce
  rules:
    - name: check-image-tag
      match:
        any:
          - resources:
              kinds: [Pod]
              namespaces: [production, staging]
      validate:
        message: "Image tag ':latest' is not allowed. Use an explicit version tag."
        foreach:
          - list: "request.object.spec.containers"
            deny:
              conditions:
                any:
                  - key: "{{ element.image }}"
                    operator: Equals
                    value: "*:latest"
                  - key: "{{ element.image }}"
                    operator: NotContains
                    value: ":"
```

**k8s/kyverno/policy-restrict-registries.yaml**
```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: restrict-image-registries
spec:
  validationFailureAction: Enforce
  rules:
    - name: validate-registries
      match:
        any:
          - resources:
              kinds: [Pod]
              namespaces: [production, staging]
      validate:
        message: "Images must come from approved registries: ghcr.io/myorg or registry.company.com"
        foreach:
          - list: "request.object.spec.containers"
            deny:
              conditions:
                all:
                  - key: "{{ element.image }}"
                    operator: NotLike
                    value: "ghcr.io/myorg/*"
                  - key: "{{ element.image }}"
                    operator: NotLike
                    value: "registry.company.com/*"
```

---

## Step 4: Falco Custom Runtime Rules

**k8s/falco/custom-rules.yaml**
```yaml
- rule: Shell Spawned in Production Container
  desc: Alert when a shell is launched inside a production namespace container
  condition: >
    spawned_process
    and container.id != host
    and k8s.ns.name = "production"
    and (proc.name = bash or proc.name = sh or proc.name = zsh)
    and not proc.pname = entrypoint.sh
  output: >
    Shell launched in production container
    (user=%user.name command=%proc.cmdline container=%container.name
     pod=%k8s.pod.name namespace=%k8s.ns.name)
  priority: CRITICAL
  tags: [container, shell, production]

- rule: Unexpected Network Outbound from Database Pod
  desc: Database pods should not initiate outbound connections
  condition: >
    outbound
    and container.id != host
    and k8s.deployment.name contains "postgres"
    and not (fd.sport = 5432 or fd.sport = 5433)
  output: >
    Unexpected outbound connection from database pod
    (command=%proc.cmdline connection=%fd.name pod=%k8s.pod.name)
  priority: WARNING
  tags: [network, database]

- rule: Sensitive File Read in Container
  desc: Detect reading of sensitive files like credentials or keys
  condition: >
    open_read
    and container.id != host
    and (fd.name startswith /etc/shadow
         or fd.name startswith /root/.ssh
         or fd.name contains "id_rsa"
         or fd.name contains ".env")
  output: >
    Sensitive file read in container
    (file=%fd.name command=%proc.cmdline container=%container.name pod=%k8s.pod.name)
  priority: ERROR
  tags: [file, credentials]
```

---

## Step 5: Image Verification Script

**scripts/verify-image.sh**
```bash
#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:?Usage: $0 IMAGE_REFERENCE}"

echo "Verifying signature for: $IMAGE"
cosign verify \
  --certificate-identity-regexp="https://github.com/myorg/*" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  "$IMAGE" | jq -r '.[0].optional.Subject // "No subject"'

echo "Verifying SBOM attachment..."
cosign verify-attestation \
  --certificate-identity-regexp="https://github.com/myorg/*" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  --type="spdxjson" \
  "$IMAGE" | jq -r '.payload | @base64d | fromjson | .predicate.name'

echo "Scanning SBOM for vulnerabilities..."
cosign download sbom "$IMAGE" | grype - --fail-on critical

echo "All checks passed for $IMAGE"
```

---

## Learning Outcomes
- [ ] Configure pre-commit hooks with gitleaks and detect-secrets
- [ ] Run Semgrep SAST with OWASP Top 10 rules in CI
- [ ] Scan container images with Trivy and fail CI on CRITICAL CVEs
- [ ] Generate SBOMs with Syft and scan them with Grype
- [ ] Sign images with Cosign keyless signing (OIDC-based)
- [ ] Enforce image policies at admission with Kyverno
- [ ] Write Falco rules for runtime anomaly detection

## Interview Talking Points
> "I implemented security gates at every pipeline stage. Pre-commit hooks prevent secrets from ever entering version control. In CI, Semgrep runs SAST checks against OWASP Top 10 patterns, Snyk scans all dependencies for CVEs, and Trivy fails the build on CRITICAL container vulnerabilities. Every built image gets a Syft-generated SBOM attached via Cosign's keyless signing — the signature is tied to the GitHub Actions OIDC token, so no long-lived keys are needed. At the Kubernetes admission layer, Kyverno enforces that only signed images from approved registries are deployed, and that no `:latest` tags are used in production. Falco watches for runtime anomalies like shell execution in production containers."
