#!/usr/bin/env bash
# LAHIS host bootstrap (step 3)
# Contract: ../CONTRACT.md
#
# Prepares ONE Ubuntu machine (AWS EC2 practice or bare metal) for the one-box stack.
# Does NOT start containers, migrate, or pull app images.
#
# Usage (as root or with passwordless/sudo):
#   sudo ./scripts/bootstrap-host.sh
#   sudo DEPLOY_USER=ubuntu ./scripts/bootstrap-host.sh
#   sudo BUNDLE_SRC=/path/to/lahis-deployment ./scripts/bootstrap-host.sh
#
# Idempotent: safe to re-run.

set -euo pipefail

DEPLOY_ROOT="${DEPLOY_ROOT:-/opt/lahis}"
DATA_ROOT="${DATA_ROOT:-/data}"
ENV_NAME="${ENV_NAME:-staging}"
DEPLOY_USER="${DEPLOY_USER:-}"
BUNDLE_SRC="${BUNDLE_SRC:-}"
INSTALL_DOCKER="${INSTALL_DOCKER:-1}"
CONFIGURE_UFW="${CONFIGURE_UFW:-0}"
# Set CONFIGURE_UFW=1 to open 80/443 (and leave OpenSSH allowed). Off by default
# so practice boxes are not reconfigured without operator intent.

log() { printf '+ %s\n' "$*"; }
warn() { printf '! %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "run as root (e.g. sudo $0)"
  fi
}

detect_os() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    OS_ID="${ID:-}"
    OS_VERSION_ID="${VERSION_ID:-}"
  else
    die "cannot read /etc/os-release (Ubuntu LTS required)"
  fi
  case "${OS_ID}" in
    ubuntu) log "OS: Ubuntu ${OS_VERSION_ID}" ;;
    debian) warn "Debian detected; script targets Ubuntu LTS — proceed carefully" ;;
    *) die "unsupported OS '${OS_ID}'; use Ubuntu 22.04/24.04 LTS" ;;
  esac
}

resolve_bundle_src() {
  if [[ -n "${BUNDLE_SRC}" ]]; then
    [[ -d "${BUNDLE_SRC}" ]] || die "BUNDLE_SRC not a directory: ${BUNDLE_SRC}"
    return
  fi
  # If script lives inside a checkout that already has compose.yml, use that tree.
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local candidate
  candidate="$(cd "${script_dir}/.." && pwd)"
  if [[ -f "${candidate}/compose.yml" && -f "${candidate}/.env.example" ]]; then
    BUNDLE_SRC="${candidate}"
    log "BUNDLE_SRC defaulted to script parent: ${BUNDLE_SRC}"
  else
    warn "no BUNDLE_SRC; will only create directories (place deploy files into ${DEPLOY_ROOT} later)"
    BUNDLE_SRC=""
  fi
}

create_directories() {
  log "creating deploy and data directories"
  mkdir -p "${DEPLOY_ROOT}"
  mkdir -p \
    "${DATA_ROOT}/pg" \
    "${DATA_ROOT}/redis" \
    "${DATA_ROOT}/minio" \
    "${DATA_ROOT}/backups" \
    "${DATA_ROOT}/caddy/data" \
    "${DATA_ROOT}/caddy/config"
  chmod 755 "${DEPLOY_ROOT}" "${DATA_ROOT}"
  # Postgres image runs as uid 70 (alpine) or 999 depending on image; leave ownership
  # to first container start unless we know the image uid. MinIO/redis similar.
  # Operators may need: chown for postgis if permission errors appear on first boot.
}

write_env_marker() {
  log "writing ${DEPLOY_ROOT}/ENV_NAME=${ENV_NAME}"
  printf '%s\n' "${ENV_NAME}" >"${DEPLOY_ROOT}/ENV_NAME"
  chmod 644 "${DEPLOY_ROOT}/ENV_NAME"
}

sync_bundle() {
  if [[ -z "${BUNDLE_SRC}" ]]; then
    return
  fi
  if [[ "$(cd "${BUNDLE_SRC}" && pwd)" == "$(cd "${DEPLOY_ROOT}" 2>/dev/null && pwd || true)" ]]; then
    log "bundle already at DEPLOY_ROOT; skip rsync"
    return
  fi
  log "syncing deploy bundle ${BUNDLE_SRC} → ${DEPLOY_ROOT}"
  # Do not clobber existing secrets or RELEASE pins on re-run
  rsync -a \
    --exclude '.env' \
    --exclude 'RELEASE' \
    --exclude '.git' \
    --exclude '.DS_Store' \
    "${BUNDLE_SRC}/" "${DEPLOY_ROOT}/"
}

seed_env_and_release() {
  if [[ ! -f "${DEPLOY_ROOT}/.env" ]]; then
    if [[ -f "${DEPLOY_ROOT}/.env.example" ]]; then
      log "seeding ${DEPLOY_ROOT}/.env from .env.example (CHANGE SECRETS before up)"
      cp "${DEPLOY_ROOT}/.env.example" "${DEPLOY_ROOT}/.env"
      chmod 600 "${DEPLOY_ROOT}/.env"
    else
      warn "no .env.example at ${DEPLOY_ROOT}; create .env manually"
    fi
  else
    log ".env already exists; leaving unchanged"
    chmod 600 "${DEPLOY_ROOT}/.env" 2>/dev/null || true
  fi

  if [[ ! -f "${DEPLOY_ROOT}/RELEASE" ]]; then
    if [[ -f "${DEPLOY_ROOT}/RELEASE.example" ]]; then
      log "seeding ${DEPLOY_ROOT}/RELEASE from RELEASE.example (pin digests before real deploy)"
      cp "${DEPLOY_ROOT}/RELEASE.example" "${DEPLOY_ROOT}/RELEASE"
      chmod 644 "${DEPLOY_ROOT}/RELEASE"
    else
      warn "no RELEASE.example; create RELEASE manually"
    fi
  else
    log "RELEASE already exists; leaving unchanged"
  fi
}

ensure_deploy_user() {
  if [[ -z "${DEPLOY_USER}" ]]; then
    # Prefer the user who invoked sudo
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
      DEPLOY_USER="${SUDO_USER}"
    else
      warn "DEPLOY_USER not set and no SUDO_USER; skip docker group membership"
      return
    fi
  fi
  if ! id "${DEPLOY_USER}" &>/dev/null; then
    die "DEPLOY_USER '${DEPLOY_USER}' does not exist"
  fi
  log "ensuring ${DEPLOY_USER} can use docker and own ${DEPLOY_ROOT} config files"
  usermod -aG docker "${DEPLOY_USER}" 2>/dev/null || warn "could not add ${DEPLOY_USER} to docker group (is docker installed?)"
  chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "${DEPLOY_ROOT}" || true
  # Data dirs often need root/container uids; keep root-owned for now
}

install_prereqs() {
  log "installing apt prerequisites"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    rsync \
    jq \
    uidmap
}

install_docker() {
  if [[ "${INSTALL_DOCKER}" != "1" ]]; then
    log "INSTALL_DOCKER=${INSTALL_DOCKER}; skip docker install"
    return
  fi
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    log "docker + compose already present: $(docker --version)"
    docker compose version
    return
  fi

  log "installing Docker Engine + Compose plugin (official Docker apt repo)"
  install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
  fi

  local arch codename
  arch="$(dpkg --print-architecture)"
  # shellcheck source=/dev/null
  . /etc/os-release
  codename="${VERSION_CODENAME:-jammy}"

  cat >/etc/apt/sources.list.d/docker.list <<EOF
deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${codename} stable
EOF

  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
  log "docker installed: $(docker --version)"
  docker compose version
}

configure_ufw() {
  if [[ "${CONFIGURE_UFW}" != "1" ]]; then
    log "CONFIGURE_UFW=0; skip firewall changes"
    return
  fi
  if ! command -v ufw >/dev/null 2>&1; then
    apt-get install -y ufw
  fi
  log "configuring ufw: allow OpenSSH, 80, 443"
  ufw allow OpenSSH
  ufw allow 80/tcp
  ufw allow 443/tcp
  # Do not force enable if user has custom policy; only enable if inactive
  if ufw status | grep -q "Status: inactive"; then
    warn "enabling ufw (default deny incoming)"
    ufw --force enable
  else
    log "ufw already active; rules added"
  fi
  ufw status verbose || true
}

print_summary() {
  cat <<EOF

============================================================
LAHIS host bootstrap complete (step 3)
============================================================
DEPLOY_ROOT:  ${DEPLOY_ROOT}
DATA_ROOT:    ${DATA_ROOT}
ENV_NAME:     $(cat "${DEPLOY_ROOT}/ENV_NAME" 2>/dev/null || echo missing)
DEPLOY_USER:  ${DEPLOY_USER:-"(none)"}

Created/ensured:
  ${DEPLOY_ROOT}/
  ${DATA_ROOT}/{pg,redis,minio,backups,caddy}
  ${DEPLOY_ROOT}/ENV_NAME
  ${DEPLOY_ROOT}/.env        (if missing; chmod 600 — edit secrets)
  ${DEPLOY_ROOT}/RELEASE     (if missing — pin digests before real deploy)

NOT done by this script (later steps):
  - docker compose up
  - migrations
  - MinIO bucket bootstrap
  - DNS / TLS verification
  - smoke tests

Next operator steps:
  1. Edit secrets:  sudo nano ${DEPLOY_ROOT}/.env
  2. Pin images:    sudo nano ${DEPLOY_ROOT}/RELEASE
  3. Ensure DNS A/AAAA for lahis.ohtk.org, api.lahis.ohtk.org, *.api..., minio...
  4. (Later) first boot: compose up data plane → migrate → apps → proxy
  5. Re-login if you were added to the docker group:  newgrp docker

Verify docker (as deploy user after re-login):
  docker run --rm hello-world
  cd ${DEPLOY_ROOT} && docker compose config >/dev/null && echo compose-ok
============================================================
EOF
}

main() {
  require_root
  detect_os
  resolve_bundle_src
  install_prereqs
  install_docker
  create_directories
  sync_bundle
  write_env_marker
  seed_env_and_release
  ensure_deploy_user
  configure_ufw
  print_summary
}

main "$@"
