#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AX_ROOT="$(cd "$SOURCE_ROOT/.." && pwd)"

CANONICAL_RUST_SOURCE_ROOT="$SOURCE_ROOT/rust/xhubd"
RUST_SOURCE_ROOT="${XHUB_RUST_HUB_SOURCE_ROOT:-$CANONICAL_RUST_SOURCE_ROOT}"
BUILD_APP_COMMAND="$SCRIPT_DIR/build_hub_app.command"
INSTALL_APP_COMMAND="$SCRIPT_DIR/install_hub_app.command"
APP_DEST="/Applications/X-Hub.app"
ACTIVE_PACKAGES_ROOT="${XHUB_RUST_ACTIVE_PACKAGES_ROOT:-$HOME/Library/Application Support/AX/rust-hub/packages}"
ACTIVE_CURRENT_LINK="${XHUB_RUST_ACTIVE_CURRENT_LINK:-$HOME/Library/Application Support/AX/rust-hub/current}"
CONTAINER_ACTIVE_PACKAGES_ROOT="${XHUB_RUST_CONTAINER_ACTIVE_PACKAGES_ROOT:-$HOME/Library/Containers/com.rel.flowhub/Data/RELFlowHub/rust-hub/packages}"
CONTAINER_ACTIVE_CURRENT_LINK="${XHUB_RUST_CONTAINER_ACTIVE_CURRENT_LINK:-$HOME/Library/Containers/com.rel.flowhub/Data/RELFlowHub/rust-hub/current}"
ACTIVATE_EMBEDDED_RUST="${XHUB_ACTIVATE_EMBEDDED_RUST:-1}"
ENABLE_AUTHORITY_CUTOVER="${XHUB_ENABLE_RUST_AUTHORITY_CUTOVER:-0}"
ENABLE_PROVIDER_MODEL_PRODUCTION="${XHUB_ENABLE_RUST_PROVIDER_MODEL_PRODUCTION:-$ENABLE_AUTHORITY_CUTOVER}"
ENABLE_XT_LIVE_CUTOVER="${XHUB_ENABLE_RUST_XT_LIVE_CUTOVER:-$ENABLE_AUTHORITY_CUTOVER}"
ENABLE_MEMORY_SKILLS_PRODUCTION="${XHUB_ENABLE_RUST_MEMORY_SKILLS_PRODUCTION:-$ENABLE_AUTHORITY_CUTOVER}"
ENABLE_MEMORY_CONTEXT_GATEWAY="${XHUB_ENABLE_RUST_MEMORY_CONTEXT_GATEWAY:-$ENABLE_MEMORY_SKILLS_PRODUCTION}"
ENABLE_MEMORY_CONTEXT_GATEWAY_REQUIRE="${XHUB_ENABLE_RUST_MEMORY_CONTEXT_GATEWAY_REQUIRE:-0}"
MEMORY_CONTEXT_GATEWAY_PARITY_MAX_AGE_MS="${XHUB_RUST_MEMORY_CONTEXT_GATEWAY_PARITY_MAX_AGE_MS:-600000}"
ENABLE_PROVIDER_KEY_SNAPSHOT="${XHUB_ENABLE_RUST_PROVIDER_KEY_SNAPSHOT:-$ENABLE_PROVIDER_MODEL_PRODUCTION}"
ENABLE_PROVIDER_QUOTA_APPLY="${XHUB_ENABLE_RUST_PROVIDER_QUOTA_APPLY:-$ENABLE_PROVIDER_KEY_SNAPSHOT}"
ENABLE_PROVIDER_QUOTA_SCHEDULER="${XHUB_ENABLE_RUST_PROVIDER_QUOTA_SCHEDULER:-$ENABLE_PROVIDER_QUOTA_APPLY}"
ENABLE_RUST_ML_EXECUTION="${XHUB_ENABLE_RUST_ML_EXECUTION:-0}"
APPLY_ROUTE_PREP="${XHUB_APPLY_RUST_ROUTE_PREP:-1}"
OPEN_AFTER_INSTALL="${XHUB_OPEN_AFTER_INSTALL:-1}"
XT_LIVE_BASE_DIR="${XHUB_RUST_XT_LIVE_BASE_DIR:-$HOME/RELFlowHub}"
CUTOVER_PREP_SUSTAINED_CYCLES="${XHUB_RUST_CUTOVER_PREP_SUSTAINED_CYCLES:-3}"
CUTOVER_PREP_SUSTAINED_INTERVAL_MS="${XHUB_RUST_CUTOVER_PREP_SUSTAINED_INTERVAL_MS:-250}"
CUTOVER_PREP_SUSTAINED_TIMEOUT_MS="${XHUB_RUST_CUTOVER_PREP_SUSTAINED_TIMEOUT_MS:-45000}"
CUTOVER_MAX_SLOW_REQUESTS="${XHUB_RUST_CUTOVER_MAX_SLOW_REQUESTS:-0}"
CUTOVER_MAX_CYCLE_MS="${XHUB_RUST_CUTOVER_MAX_CYCLE_MS:-120000}"
CUTOVER_XT_HEARTBEAT_SOAK_MS="${XHUB_RUST_XT_HEARTBEAT_SOAK_MS:-12000}"
RUST_DAEMON_INSTALL_PROFILE="${XHUB_RUST_INSTALL_DAEMON_PROFILE:-}"
RUST_DAEMON_INSTALL_LABEL="${XHUB_RUST_INSTALL_DAEMON_LABEL:-}"
RUST_DAEMON_INSTALL_RUNTIME_ROOT="${XHUB_RUST_INSTALL_DAEMON_RUNTIME_ROOT:-}"
RUST_DAEMON_INSTALL_PLIST_PATH="${XHUB_RUST_INSTALL_DAEMON_PLIST_PATH:-}"
RUST_HTTP_ACCESS_KEY_FILE="${XHUB_RUST_HTTP_ACCESS_KEY_FILE:-${XHUB_RUST_HUB_ACCESS_KEY_FILE:-}}"

pause_on_failure() {
  if [ "${XHUB_PAUSE_ON_FAILURE:-1}" != "1" ]; then
    return 0
  fi
  if [ -t 0 ]; then
    echo
    read -r -p "Build/install failed. Press Enter to close this window..." _
  fi
}

on_error() {
  local exit_code=$?
  local line_no="${BASH_LINENO[0]:-unknown}"
  echo
  echo "[ERROR] build_install_latest_hub.command failed at line $line_no (exit $exit_code)." >&2
  pause_on_failure
  exit "$exit_code"
}

trap on_error ERR

is_enabled() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

path_realpath_dir() {
  local path="$1"
  if [ -z "$path" ] || [ ! -d "$path" ]; then
    return 1
  fi
  (cd "$path" && pwd -P)
}

external_rust_source_allowed() {
  is_enabled "${XHUB_ALLOW_EXTERNAL_RUST_HUB_PACKAGE:-0}"
}

run_step() {
  local title="$1"
  shift
  echo
  echo "==> $title"
  "$@"
}

launchctl_getenv() {
  launchctl getenv "$1" 2>/dev/null || true
}

launchd_user_domain() {
  printf "gui/%s" "$(id -u)"
}

launchd_service_loaded() {
  local label="$1"
  launchctl print "$(launchd_user_domain)/$label" >/dev/null 2>&1
}

default_daemon_install_plist_path() {
  local profile="$1"
  local label="${2:-com.ax.xhubd.$profile}"
  if [ -n "$RUST_DAEMON_INSTALL_PLIST_PATH" ]; then
    printf "%s" "$RUST_DAEMON_INSTALL_PLIST_PATH"
    return 0
  fi
  printf "%s/Library/LaunchAgents/%s.plist" "$HOME" "$label"
}

plist_env_get() {
  local plist_path="$1"
  local key="$2"
  if [ -z "$plist_path" ] || [ ! -f "$plist_path" ]; then
    return 0
  fi
  /usr/bin/plutil -extract "EnvironmentVariables.$key" raw -o - "$plist_path" 2>/dev/null || true
}

launchctl_or_plist_env() {
  local key="$1"
  local plist_path="${2:-}"
  local value=""
  value="$(launchctl_getenv "$key")"
  if [ -n "$value" ]; then
    printf "%s" "$value"
    return 0
  fi
  plist_env_get "$plist_path" "$key"
}

detect_rust_daemon_profile() {
  if [ -n "$RUST_DAEMON_INSTALL_PROFILE" ]; then
    printf "%s" "$RUST_DAEMON_INSTALL_PROFILE"
    return 0
  fi
  local existing_profile=""
  existing_profile="$(launchctl_getenv XHUB_RUST_DAEMON_PROFILE)"
  if [ -n "$existing_profile" ]; then
    printf "%s" "$existing_profile"
    return 0
  fi
  if launchd_service_loaded "com.ax.xhubd.domain"; then
    printf "domain"
    return 0
  fi
  if launchd_service_loaded "com.ax.xhubd.lan"; then
    printf "lan"
    return 0
  fi
  printf "local"
}

default_daemon_runtime_root() {
  local profile="$1"
  printf "%s/Library/Application Support/AX/rust-hub/%s" "$HOME" "$profile"
}

default_daemon_runtime_access_key_file() {
  local profile="$1"
  local runtime_root="${2:-$(default_daemon_runtime_root "$profile")}"
  printf "%s/config/xhubd_%s_access_key" "$runtime_root" "$profile"
}

seed_daemon_runtime_access_key_file() {
  local profile="$1"
  local runtime_root="${2:-$(default_daemon_runtime_root "$profile")}"
  local source_secret="$RUST_SOURCE_ROOT/secrets/xhubd_${profile}_access_key"
  local runtime_secret=""
  runtime_secret="$(default_daemon_runtime_access_key_file "$profile" "$runtime_root")"
  if [ -f "$runtime_secret" ]; then
    chmod 600 "$runtime_secret" 2>/dev/null || true
    printf "%s" "$runtime_secret"
    return 0
  fi
  if [ -f "$source_secret" ]; then
    mkdir -p "$(dirname "$runtime_secret")"
    cp "$source_secret" "$runtime_secret"
    chmod 600 "$runtime_secret" 2>/dev/null || true
    printf "%s" "$runtime_secret"
    return 0
  fi
}

default_daemon_access_key_file() {
  local profile="$1"
  local plist_path="${2:-$(default_daemon_install_plist_path "$profile")}"
  local runtime_root="${3:-$(default_daemon_runtime_root "$profile")}"
  if [ -n "$RUST_HTTP_ACCESS_KEY_FILE" ]; then
    printf "%s" "$RUST_HTTP_ACCESS_KEY_FILE"
    return 0
  fi
  local source_secret="$RUST_SOURCE_ROOT/secrets/xhubd_${profile}_access_key"
  local runtime_secret=""
  runtime_secret="$(default_daemon_runtime_access_key_file "$profile" "$runtime_root")"
  local env_key_file=""
  env_key_file="$(launchctl_or_plist_env XHUB_RUST_HTTP_ACCESS_KEY_FILE "$plist_path")"
  if [ -n "$env_key_file" ]; then
    if [ "$env_key_file" = "$source_secret" ]; then
      seed_daemon_runtime_access_key_file "$profile" "$runtime_root"
      return 0
    fi
    printf "%s" "$env_key_file"
    return 0
  fi
  env_key_file="$(launchctl_or_plist_env XHUB_RUST_HUB_ACCESS_KEY_FILE "$plist_path")"
  if [ -n "$env_key_file" ]; then
    if [ "$env_key_file" = "$source_secret" ]; then
      seed_daemon_runtime_access_key_file "$profile" "$runtime_root"
      return 0
    fi
    printf "%s" "$env_key_file"
    return 0
  fi
  if [ -f "$runtime_secret" ] || [ -f "$source_secret" ]; then
    seed_daemon_runtime_access_key_file "$profile" "$runtime_root"
  fi
}

latest_rust_package_dir() {
  local latest=""
  latest="$(find "$RUST_SOURCE_ROOT/dist" -maxdepth 1 -type d -name 'rust-hub-*' 2>/dev/null | sort | tail -n 1)"
  if [ -z "$latest" ] || [ ! -d "$latest" ]; then
    return 1
  fi
  (cd "$latest" && pwd)
}

validate_rust_source_root() {
  if [ ! -x "$RUST_SOURCE_ROOT/tools/package_rust_hub.command" ]; then
    echo "[ERROR] Rust Hub package script not found or not executable:" >&2
    echo "  $RUST_SOURCE_ROOT/tools/package_rust_hub.command" >&2
    echo "Set XHUB_RUST_HUB_SOURCE_ROOT if your Rust Hub source root moved." >&2
    exit 1
  fi
  local source_real=""
  local canonical_real=""
  source_real="$(path_realpath_dir "$RUST_SOURCE_ROOT" 2>/dev/null || true)"
  canonical_real="$(path_realpath_dir "$CANONICAL_RUST_SOURCE_ROOT" 2>/dev/null || true)"
  if [ -n "$source_real" ] && [ -n "$canonical_real" ] && [ "$source_real" = "$canonical_real" ]; then
    return 0
  fi
  if external_rust_source_allowed; then
    echo "[warn] Using external Rust Hub source root by explicit opt-in: $RUST_SOURCE_ROOT" >&2
    return 0
  fi
  echo "[ERROR] Refusing external Rust Hub source root: $RUST_SOURCE_ROOT" >&2
  echo "[ERROR] Unified Hub builds must package the Rust kernel from: $CANONICAL_RUST_SOURCE_ROOT" >&2
  echo "[ERROR] Set XHUB_ALLOW_EXTERNAL_RUST_HUB_PACKAGE=1 only for a deliberate one-off diagnostic build." >&2
  exit 1
}

validate_rust_package_dir() {
  local package_dir="$1"
  local package_real=""
  local canonical_real=""
  if [ ! -x "$package_dir/bin/xhubd" ]; then
    echo "[ERROR] Rust Hub package is missing bin/xhubd: $package_dir" >&2
    exit 1
  fi
  package_real="$(path_realpath_dir "$package_dir" 2>/dev/null || true)"
  canonical_real="$(path_realpath_dir "$CANONICAL_RUST_SOURCE_ROOT" 2>/dev/null || true)"
  if [ -n "$package_real" ] && [ -n "$canonical_real" ]; then
    case "$package_real/" in
      "$canonical_real"/dist/rust-hub-*) ;;
      *)
        if ! external_rust_source_allowed; then
          echo "[ERROR] Refusing external Rust Hub package: $package_dir" >&2
          echo "[ERROR] Unified Hub builds must embed packages from: $CANONICAL_RUST_SOURCE_ROOT/dist" >&2
          exit 1
        fi
        ;;
    esac
  fi
  local help_text=""
  help_text="$("$package_dir/bin/xhubd" --help 2>&1 || true)"
  case "$help_text" in
    *"model <inventory|capabilities"*) return 0 ;;
  esac
  echo "[ERROR] Refusing stale Rust Hub package without model capabilities support: $package_dir" >&2
  echo "[ERROR] Repackage with: $CANONICAL_RUST_SOURCE_ROOT/tools/package_rust_hub.command" >&2
  exit 1
}

deploy_active_root_copy() {
  local label="$1"
  local embedded_root="$2"
  local packages_root="$3"
  local current_link="$4"
  local package_name="$5"
  local active_root="$packages_root/$package_name"

  echo "[active-root] Deploying embedded Rust Hub to $label active package root" >&2
  echo "[active-root] Embedded: $embedded_root" >&2
  echo "[active-root] Active:   $active_root" >&2
  mkdir -p "$packages_root"
  mkdir -p "$(dirname "$current_link")"
  rsync -a --delete \
    --exclude '.DS_Store' \
    "$embedded_root/" \
    "$active_root/"

  ln -sfn "$active_root" "$current_link"
  printf "%s" "$active_root"
}

deploy_embedded_rust_root() {
  local embedded_root="$APP_DEST/Contents/Resources/rust-hub"
  if [ ! -f "$embedded_root/bin/xhubd" ] || [ ! -f "$embedded_root/tools/run_rust_hub.command" ]; then
    echo "[ERROR] Installed app does not contain an embedded Rust Hub package:" >&2
    echo "  $embedded_root" >&2
    exit 1
  fi

  local package_name=""
  package_name="$(basename "$RUST_PACKAGE_DIR")"

  ACTIVE_ROOT="$(deploy_active_root_copy "daemon" "$embedded_root" "$ACTIVE_PACKAGES_ROOT" "$ACTIVE_CURRENT_LINK" "$package_name")"
  CONTAINER_ACTIVE_ROOT="$(deploy_active_root_copy "X-Hub container" "$embedded_root" "$CONTAINER_ACTIVE_PACKAGES_ROOT" "$CONTAINER_ACTIVE_CURRENT_LINK" "$package_name")"
  seed_active_root_access_key_files
}

seed_active_root_access_key_file() {
  local source_file="$1"
  local target_root="$2"
  local profile="$3"
  if [ -z "$source_file" ] || [ ! -f "$source_file" ] || [ -z "$target_root" ] || [ ! -d "$target_root" ]; then
    return 0
  fi
  local target_file="$target_root/secrets/xhubd_${profile}_access_key"
  mkdir -p "$(dirname "$target_file")"
  cp "$source_file" "$target_file"
  chmod 600 "$target_file" 2>/dev/null || true
}

seed_active_root_access_key_files() {
  local profile=""
  profile="$(detect_rust_daemon_profile)"
  local runtime_root="${RUST_DAEMON_INSTALL_RUNTIME_ROOT:-$(default_daemon_runtime_root "$profile")}"
  local install_plist_path=""
  install_plist_path="$(default_daemon_install_plist_path "$profile" "${RUST_DAEMON_INSTALL_LABEL:-com.ax.xhubd.$profile}")"
  local access_key_file=""
  access_key_file="$(default_daemon_access_key_file "$profile" "$install_plist_path" "$runtime_root")"
  if [ -z "$access_key_file" ] || [ ! -f "$access_key_file" ]; then
    return 0
  fi
  echo "[active-root] Seeding Rust Hub access-key reference into active package roots" >&2
  seed_active_root_access_key_file "$access_key_file" "${ACTIVE_ROOT:-}" "$profile"
  seed_active_root_access_key_file "$access_key_file" "${CONTAINER_ACTIVE_ROOT:-}" "$profile"
}

activate_embedded_rust_root() {
  if ! is_enabled "$ACTIVATE_EMBEDDED_RUST"; then
    echo "[active-root] Skipping Rust active-root activation (XHUB_ACTIVATE_EMBEDDED_RUST=$ACTIVATE_EMBEDDED_RUST)."
    return 0
  fi

  if [ -z "${ACTIVE_ROOT:-}" ] || [ ! -d "$ACTIVE_ROOT" ]; then
    echo "[ERROR] ACTIVE_ROOT is not ready." >&2
    exit 1
  fi

  local memory_skills_guard_args=()
  if is_enabled "$ENABLE_MEMORY_SKILLS_PRODUCTION"; then
    memory_skills_guard_args=(--require-memory-skills-production)
  fi
  local memory_gateway_guard_args=()
  if is_enabled "$ENABLE_MEMORY_CONTEXT_GATEWAY_REQUIRE"; then
    memory_gateway_guard_args=(--require-memory-gateway-cutover-ready)
  fi

  run_step "Set safe Rust Hub active-root session env" set_safe_rust_session_env

  run_step "Install/restart Rust Hub launchd daemon from active root" install_rust_launchd_daemon

  run_step "Refresh Rust Hub active-root session env after daemon install" set_safe_rust_session_env

  if is_enabled "$APPLY_ROUTE_PREP"; then
    run_step "Enable provider/model route prep only" \
      bash "$ACTIVE_ROOT/tools/route_authority_prep_session.command" \
        --apply \
        --rust-hub-root "$ACTIVE_ROOT" \
        --http-base-url "http://127.0.0.1:50151"
    run_step "Clear provider/model route production env" \
      bash "$ACTIVE_ROOT/tools/route_authority_prep_session.command" --clear-production-env
  else
    run_step "Clear provider/model route production env" \
      bash "$ACTIVE_ROOT/tools/route_authority_prep_session.command" --clear-production-env
  fi

  if is_enabled "$ENABLE_AUTHORITY_CUTOVER"; then
    run_step "Apply explicit Rust authority cutover prep" \
      bash "$ACTIVE_ROOT/tools/active_root_upgrade_apply.command" \
        --apply \
        --target-root "$ACTIVE_ROOT"

    if is_enabled "$ENABLE_PROVIDER_MODEL_PRODUCTION"; then
      run_step "Relaunch X-Hub.app for provider/model prep guard" relaunch_xhub_app

      run_step "Run provider/model route sustained cutover guard" \
        env XHUB_SYSTEM_ROOT="$SOURCE_ROOT" \
        bash "$ACTIVE_ROOT/tools/route_authority_prep_sustained_guard.command" \
          --cycles "$CUTOVER_PREP_SUSTAINED_CYCLES" \
          --interval-ms "$CUTOVER_PREP_SUSTAINED_INTERVAL_MS" \
          --timeout-ms "$CUTOVER_PREP_SUSTAINED_TIMEOUT_MS" \
          --rust-hub-root "$ACTIVE_ROOT" \
          --max-slow-requests "$CUTOVER_MAX_SLOW_REQUESTS" \
          --max-cycle-ms "$CUTOVER_MAX_CYCLE_MS" \
          --model-remote-runs 1 \
          --model-local-runs 1 \
          --scheduler-gate-mode applied \
          "${memory_skills_guard_args[@]}"

      local prep_sustained_report=""
      prep_sustained_report="$(latest_prep_sustained_report "$ACTIVE_ROOT")"
      if [ -z "$prep_sustained_report" ]; then
        echo "[ERROR] No route_authority_prep_sustained_guard report found under $ACTIVE_ROOT/reports" >&2
        exit 1
      fi

      run_step "Apply provider/model Rust production authority" \
        bash "$ACTIVE_ROOT/tools/route_authority_production_session.command" \
          --apply \
          --rust-hub-root "$ACTIVE_ROOT" \
          --http-base-url "http://127.0.0.1:50151" \
          --prep-sustained-report "$prep_sustained_report" \
          --confirm-provider-model-production-authority
    fi

    if is_enabled "$ENABLE_XT_LIVE_CUTOVER"; then
      run_step "Apply XT file IPC live production session" \
        bash "$ACTIVE_ROOT/tools/xt_file_ipc_production_session.command" \
          --apply \
          --rust-hub-root "$ACTIVE_ROOT" \
          --live-base-dir "$XT_LIVE_BASE_DIR" \
          --confirm-live-cutover

      run_step "Restart Rust Hub launchd daemon with live env" \
        install_rust_launchd_daemon
    fi

    run_step "Relaunch X-Hub.app with Rust authority env" relaunch_xhub_app

    if is_enabled "$ENABLE_PROVIDER_MODEL_PRODUCTION"; then
      run_step "Verify provider/model/scheduler Rust production runtime" \
        bash "$ACTIVE_ROOT/tools/route_authority_production_runtime_guard.command" \
          --rust-hub-root "$ACTIVE_ROOT" \
          --http-base-url "http://127.0.0.1:50151" \
          --allow-xt-file-ipc-production \
          "${memory_skills_guard_args[@]}"
    fi

    if is_enabled "$ENABLE_XT_LIVE_CUTOVER"; then
      run_step "Verify XT live heartbeat" \
        bash "$ACTIVE_ROOT/tools/xt_file_ipc_live_heartbeat_soak.command" \
          --duration-ms "$CUTOVER_XT_HEARTBEAT_SOAK_MS" \
          --interval-ms 2000 \
          --max-status-age-ms 5000 \
          --status-read-timeout-ms 3000 \
          --live-base-dir "$XT_LIVE_BASE_DIR" \
          --http-base-url "http://127.0.0.1:50151" \
          "${memory_skills_guard_args[@]}"
    fi

    if is_enabled "$ENABLE_MEMORY_CONTEXT_GATEWAY_REQUIRE"; then
      run_step "Refresh Memory Gateway cutover readiness evidence" \
        bash "$ACTIVE_ROOT/tools/memory_gateway_cutover_smoke.command" \
          --samples 3 \
          --required-samples 3
    fi

    run_step "Verify daemon ops after Rust authority cutover" \
      bash "$ACTIVE_ROOT/tools/daemon_ops_gate.command" \
        --max-slow-requests "$CUTOVER_MAX_SLOW_REQUESTS" \
        "${memory_skills_guard_args[@]}" \
        "${memory_gateway_guard_args[@]}"
  elif is_enabled "$OPEN_AFTER_INSTALL"; then
    run_step "Open installed X-Hub.app" open "$APP_DEST"
  fi
}

install_rust_launchd_daemon() {
  local profile=""
  profile="$(detect_rust_daemon_profile)"
  local label="${RUST_DAEMON_INSTALL_LABEL:-com.ax.xhubd.$profile}"
  local runtime_root="${RUST_DAEMON_INSTALL_RUNTIME_ROOT:-$(default_daemon_runtime_root "$profile")}"
  local install_plist_path=""
  install_plist_path="$(default_daemon_install_plist_path "$profile" "$label")"
  local host="${XHUB_RUST_HUB_HOST:-$(launchctl_or_plist_env XHUB_RUST_HUB_HOST "$install_plist_path")}"
  local port="${XHUB_RUST_HUB_HTTP_PORT:-$(launchctl_or_plist_env XHUB_RUST_HUB_HTTP_PORT "$install_plist_path")}"
  local public_base_url="${XHUB_RUST_HUB_PUBLIC_BASE_URL:-$(launchctl_or_plist_env XHUB_RUST_HUB_PUBLIC_BASE_URL "$install_plist_path")}"
  local public_endpoint="${XHUB_RUST_HUB_PUBLIC_ENDPOINT:-$(launchctl_or_plist_env XHUB_RUST_HUB_PUBLIC_ENDPOINT "$install_plist_path")}"
  if [ -z "$public_endpoint" ]; then
    public_endpoint="$(launchctl_or_plist_env XHUB_RUST_CROSS_NETWORK_PUBLIC_ENDPOINT "$install_plist_path")"
  fi
  local access_key_file=""
  access_key_file="$(default_daemon_access_key_file "$profile" "$install_plist_path" "$runtime_root")"

  host="${host:-127.0.0.1}"
  port="${port:-50151}"

  local args=(
    launchd-install
    --replace-running
    --profile "$profile"
    --host "$host"
    --port "$port"
    --launchd-label "$label"
    --launchd-runtime-root "$runtime_root"
    --install-plist-path "$install_plist_path"
    --launchd-binary-source "$ACTIVE_ROOT/bin/xhubd"
  )

  if [ "$profile" = "domain" ]; then
    args+=(--public-endpoint)
  fi
  if is_enabled "$public_endpoint"; then
    args+=(--public-endpoint)
  fi
  if [ -n "$public_base_url" ]; then
    args+=(--public-base-url "$public_base_url")
  fi
  if [ -n "$access_key_file" ] && [ -f "$access_key_file" ]; then
    args+=(--access-key-file "$access_key_file")
    if [ "$profile" = "domain" ] || is_enabled "${XHUB_RUST_HTTP_REQUIRE_ACCESS_KEY:-$(launchctl_getenv XHUB_RUST_HTTP_REQUIRE_ACCESS_KEY)}"; then
      args+=(--require-access-key)
    fi
  fi

  if [ "$profile" = "domain" ] || [ "$profile" = "lan" ]; then
    local db_path="${HUB_DB_PATH:-$(launchctl_or_plist_env HUB_DB_PATH "$install_plist_path")}"
    local runtime_base_dir="${HUB_RUNTIME_BASE_DIR:-$(launchctl_or_plist_env HUB_RUNTIME_BASE_DIR "$install_plist_path")}"
    local memory_dir="${XHUB_RUST_MEMORY_DIR:-$(launchctl_or_plist_env XHUB_RUST_MEMORY_DIR "$install_plist_path")}"
    local skills_dir="${XHUB_RUST_SKILLS_DIR:-$(launchctl_or_plist_env XHUB_RUST_SKILLS_DIR "$install_plist_path")}"
    [ -n "$db_path" ] && args+=(--db-path "$db_path")
    [ -n "$runtime_base_dir" ] && args+=(--runtime-base-dir "$runtime_base_dir")
    [ -n "$memory_dir" ] && args+=(--memory-dir "$memory_dir")
    [ -n "$skills_dir" ] && args+=(--skills-dir "$skills_dir")
  fi

  echo "[daemon] profile=$profile label=$label runtime_root=$runtime_root" >&2
  echo "[daemon] public_base_url=${public_base_url:-default} access_key_file=${access_key_file:-none}" >&2
  if ! bash "$ACTIVE_ROOT/tools/xhubd_daemon.command" "${args[@]}"; then
    if [ "$profile" != "domain" ] && launchd_service_loaded "com.ax.xhubd.domain"; then
      echo "[daemon] local install failed while domain daemon exists; retrying domain profile" >&2
      RUST_DAEMON_INSTALL_PROFILE=domain install_rust_launchd_daemon
      return $?
    fi
    return 1
  fi
}

latest_prep_sustained_report() {
  local root="$1"
  find "$root/reports" -maxdepth 1 -type f -name 'route_authority_prep_sustained_guard_*.json' 2>/dev/null | sort | tail -n 1
}

relaunch_xhub_app() {
  osascript -e 'tell application "X-Hub" to quit' >/dev/null 2>&1 || true
  sleep 5
  open "$APP_DEST"
  sleep 8
}

open_app_if_needed() {
  if is_enabled "$ACTIVATE_EMBEDDED_RUST"; then
    return 0
  fi
  if is_enabled "$OPEN_AFTER_INSTALL"; then
    run_step "Open installed X-Hub.app" open "$APP_DEST"
  fi
}

set_safe_rust_session_env() {
  launchctl setenv XHUB_RUST_HUB_ROOT "$ACTIVE_ROOT"
  launchctl setenv XHUB_RUST_HUB_RUNNER "$ACTIVE_ROOT/tools/run_rust_hub.command"
  launchctl setenv XHUB_RUST_HUB_HOST "127.0.0.1"
  launchctl setenv XHUB_RUST_HUB_HTTP_PORT "50151"
  launchctl setenv XHUB_RUST_HUB_HTTP_BASE_URL "http://127.0.0.1:50151"
  launchctl setenv XHUB_SYSTEM_ROOT "$SOURCE_ROOT"
  launchctl setenv XHUB_RUST_LOCAL_RUNTIME_SCRIPT "$APP_DEST/Contents/Resources/python_service/relflowhub_local_runtime.py"
  local daemon_profile=""
  daemon_profile="$(detect_rust_daemon_profile)"
  launchctl setenv XHUB_RUST_DAEMON_PROFILE "$daemon_profile"
  local access_key_file=""
  access_key_file="$(default_daemon_access_key_file "$daemon_profile" "$(default_daemon_install_plist_path "$daemon_profile")" "$(default_daemon_runtime_root "$daemon_profile")")"
  if [ -n "$access_key_file" ] && [ -f "$access_key_file" ]; then
    launchctl setenv XHUB_RUST_HTTP_ACCESS_KEY_FILE "$access_key_file"
    launchctl setenv XHUB_RUST_HUB_ACCESS_KEY_FILE "$access_key_file"
  else
    launchctl unsetenv XHUB_RUST_HTTP_ACCESS_KEY_FILE 2>/dev/null || true
    launchctl unsetenv XHUB_RUST_HUB_ACCESS_KEY_FILE 2>/dev/null || true
  fi
  launchctl setenv XHUB_RUST_SCHEDULER_STATUS_READ "1"
  launchctl setenv XHUB_RUST_SCHEDULER_STATUS_REQUIRE_READY "1"
  launchctl setenv XHUB_RUST_SCHEDULER_STATUS_HTTP "1"
  launchctl setenv XHUB_RUST_SCHEDULER_STATUS_HTTP_BASE_URL "http://127.0.0.1:50151"
  launchctl setenv XHUB_RUST_SCHEDULER_STATUS_HTTP_TIMEOUT_MS "750"
  if is_enabled "$ENABLE_AUTHORITY_CUTOVER"; then
    launchctl setenv XHUB_ENABLE_RUST_AUTHORITY_CUTOVER "1"
  else
    launchctl unsetenv XHUB_ENABLE_RUST_AUTHORITY_CUTOVER 2>/dev/null || true
  fi

  if ! is_enabled "$ENABLE_AUTHORITY_CUTOVER"; then
    launchctl setenv XHUB_RUST_SCHEDULER_AUTHORITY "0"
  fi

  if is_enabled "$ENABLE_MEMORY_SKILLS_PRODUCTION"; then
    launchctl setenv XHUB_ALLOW_RUST_MEMORY_SKILLS_PRODUCTION "1"
    launchctl setenv XHUB_RUST_MEMORY_WRITER_AUTHORITY "1"
    launchctl setenv XHUB_RUST_MEMORY_WRITE_AUTHORITY "1"
    launchctl setenv XHUB_RUST_MEMORY_PRODUCTION_AUTHORITY "1"
    launchctl setenv XHUB_RUST_SKILLS_EXECUTION_AUTHORITY "1"
    launchctl setenv XHUB_RUST_SKILLS_PRODUCTION_EXECUTION "1"
    launchctl setenv XHUB_RUST_SKILLS_EXECUTION_PRODUCTION "1"
    launchctl setenv XHUB_RUST_SKILLS_RUNNER_PRODUCTION_AUTHORITY "1"
  else
    for key in \
      XHUB_ALLOW_RUST_MEMORY_SKILLS_PRODUCTION \
      XHUB_RUST_MEMORY_WRITER_AUTHORITY \
      XHUB_RUST_MEMORY_WRITE_AUTHORITY \
      XHUB_RUST_MEMORY_PRODUCTION_AUTHORITY \
      XHUB_RUST_SKILLS_EXECUTION_AUTHORITY \
      XHUB_RUST_SKILLS_PRODUCTION_EXECUTION \
      XHUB_RUST_SKILLS_EXECUTION_PRODUCTION \
      XHUB_RUST_SKILLS_RUNNER_PRODUCTION_AUTHORITY
    do
      launchctl unsetenv "$key" 2>/dev/null || true
    done
  fi

  if is_enabled "$ENABLE_MEMORY_CONTEXT_GATEWAY"; then
    launchctl unsetenv XHUB_RUST_MEMORY_CONTEXT_GATEWAY_SHADOW 2>/dev/null || true
    launchctl setenv XHUB_RUST_MEMORY_CONTEXT_GATEWAY "1"
    launchctl setenv XHUB_RUST_MEMORY_CONTEXT_GATEWAY_PARITY_MAX_AGE_MS "$MEMORY_CONTEXT_GATEWAY_PARITY_MAX_AGE_MS"
    if is_enabled "$ENABLE_MEMORY_CONTEXT_GATEWAY_REQUIRE"; then
      launchctl setenv XHUB_RUST_MEMORY_CONTEXT_GATEWAY_REQUIRE "1"
    else
      launchctl unsetenv XHUB_RUST_MEMORY_CONTEXT_GATEWAY_REQUIRE 2>/dev/null || true
    fi
  else
    for key in \
      XHUB_RUST_MEMORY_CONTEXT_GATEWAY_SHADOW \
      XHUB_RUST_MEMORY_CONTEXT_GATEWAY \
      XHUB_RUST_MEMORY_CONTEXT_GATEWAY_REQUIRE \
      XHUB_RUST_MEMORY_CONTEXT_GATEWAY_PARITY_MAX_AGE_MS
    do
      launchctl unsetenv "$key" 2>/dev/null || true
    done
  fi

  if ! is_enabled "$ENABLE_PROVIDER_MODEL_PRODUCTION"; then
    for key in \
      XHUB_RUST_PROVIDER_ROUTE_PRODUCTION_AUTHORITY \
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PRODUCTION \
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CUTOVER \
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_APPLY \
      XHUB_RUST_MODEL_ROUTE_PRODUCTION_AUTHORITY \
      XHUB_RUST_MODEL_ROUTE_AUTHORITY_PRODUCTION \
      XHUB_RUST_MODEL_ROUTE_AUTHORITY_CUTOVER \
      XHUB_RUST_MODEL_ROUTE_AUTHORITY_APPLY
    do
      launchctl unsetenv "$key" 2>/dev/null || true
    done
  fi

  if is_enabled "$ENABLE_PROVIDER_KEY_SNAPSHOT"; then
    launchctl setenv XHUB_ENABLE_RUST_PROVIDER_KEY_SNAPSHOT "1"
    launchctl setenv XHUB_RUST_PROVIDER_KEY_SNAPSHOT "1"
    launchctl setenv XHUB_RUST_PROVIDER_KEY_SNAPSHOT_HTTP "1"
    launchctl setenv XHUB_RUST_PROVIDER_KEY_SNAPSHOT_HTTP_BASE_URL "http://127.0.0.1:50151"
    launchctl setenv XHUB_RUST_PROVIDER_KEY_SNAPSHOT_FALLBACK_ON_ERROR "1"
  else
    for key in \
      XHUB_ENABLE_RUST_PROVIDER_KEY_SNAPSHOT \
      XHUB_RUST_PROVIDER_KEY_SNAPSHOT \
      XHUB_RUST_PROVIDER_KEY_SNAPSHOT_HTTP \
      XHUB_RUST_PROVIDER_KEY_SNAPSHOT_HTTP_BASE_URL \
      XHUB_RUST_PROVIDER_KEY_SNAPSHOT_FALLBACK_ON_ERROR
    do
      launchctl unsetenv "$key" 2>/dev/null || true
    done
  fi

  if is_enabled "$ENABLE_PROVIDER_QUOTA_APPLY"; then
    launchctl setenv XHUB_ENABLE_RUST_PROVIDER_QUOTA_APPLY "1"
    launchctl setenv XHUB_RUST_PROVIDER_QUOTA_APPLY "1"
    launchctl setenv XHUB_RUST_PROVIDER_QUOTA_APPLY_HTTP "1"
    launchctl setenv XHUB_RUST_PROVIDER_QUOTA_APPLY_HTTP_BASE_URL "http://127.0.0.1:50151"
    launchctl setenv XHUB_RUST_PROVIDER_QUOTA_APPLY_FALLBACK_ON_ERROR "1"
    if is_enabled "$ENABLE_PROVIDER_QUOTA_SCHEDULER"; then
      launchctl setenv XHUB_ENABLE_RUST_PROVIDER_QUOTA_SCHEDULER "1"
      launchctl setenv XHUB_ENABLE_RUST_PROVIDER_QUOTA_PLAN "1"
      launchctl setenv XHUB_ENABLE_RUST_PROVIDER_QUOTA_FAILURE "1"
      launchctl setenv XHUB_RUST_PROVIDER_QUOTA_PLAN "1"
      launchctl setenv XHUB_RUST_PROVIDER_QUOTA_FAILURE "1"
    else
      for key in \
        XHUB_ENABLE_RUST_PROVIDER_QUOTA_SCHEDULER \
        XHUB_ENABLE_RUST_PROVIDER_QUOTA_PLAN \
        XHUB_ENABLE_RUST_PROVIDER_QUOTA_FAILURE \
        XHUB_RUST_PROVIDER_QUOTA_PLAN \
        XHUB_RUST_PROVIDER_QUOTA_FAILURE
      do
        launchctl unsetenv "$key" 2>/dev/null || true
      done
    fi
  else
    for key in \
      XHUB_ENABLE_RUST_PROVIDER_QUOTA_APPLY \
      XHUB_RUST_PROVIDER_QUOTA_APPLY \
      XHUB_RUST_PROVIDER_QUOTA_APPLY_HTTP \
      XHUB_RUST_PROVIDER_QUOTA_APPLY_HTTP_BASE_URL \
      XHUB_RUST_PROVIDER_QUOTA_APPLY_FALLBACK_ON_ERROR \
      XHUB_ENABLE_RUST_PROVIDER_QUOTA_SCHEDULER \
      XHUB_ENABLE_RUST_PROVIDER_QUOTA_PLAN \
      XHUB_ENABLE_RUST_PROVIDER_QUOTA_FAILURE \
      XHUB_RUST_PROVIDER_QUOTA_PLAN \
      XHUB_RUST_PROVIDER_QUOTA_FAILURE
    do
      launchctl unsetenv "$key" 2>/dev/null || true
    done
  fi

  if ! is_enabled "$ENABLE_XT_LIVE_CUTOVER"; then
    for key in \
      XHUB_RUST_XT_FILE_IPC_PRODUCTION_CUTOVER \
      XHUB_RUST_XT_CLASSIC_PRODUCTION_CUTOVER
    do
      launchctl unsetenv "$key" 2>/dev/null || true
    done
  fi

  if is_enabled "$ENABLE_RUST_ML_EXECUTION"; then
    launchctl setenv XHUB_ENABLE_RUST_ML_EXECUTION "1"
    launchctl setenv XHUB_RUST_ML_EXECUTION_AUTHORITY "1"
    launchctl setenv XHUB_RUST_LOCAL_ML_EXECUTION_AUTHORITY "1"
    launchctl setenv XHUB_RUST_ML_EXECUTION_HTTP_BASE_URL "http://127.0.0.1:50151"
    launchctl setenv XHUB_RUST_ML_EXECUTION_FALLBACK_ON_ERROR "0"
  else
    for key in \
      XHUB_ENABLE_RUST_ML_EXECUTION \
      XHUB_RUST_ML_EXECUTION_AUTHORITY \
      XHUB_RUST_LOCAL_ML_EXECUTION_AUTHORITY \
      XHUB_RUST_ML_EXECUTION_HTTP_BASE_URL \
      XHUB_RUST_ML_EXECUTION_FALLBACK_ON_ERROR
    do
      launchctl unsetenv "$key" 2>/dev/null || true
    done
  fi
}

validate_rust_source_root

echo "[config] X-Hub source root: $SOURCE_ROOT"
echo "[config] Rust Hub source root: $RUST_SOURCE_ROOT"
echo "[config] Installed app: $APP_DEST"
echo "[config] Authority cutover: $ENABLE_AUTHORITY_CUTOVER"
echo "[config] Provider/model production: $ENABLE_PROVIDER_MODEL_PRODUCTION"
echo "[config] Memory context gateway primary: $ENABLE_MEMORY_CONTEXT_GATEWAY"
echo "[config] Memory context gateway require: $ENABLE_MEMORY_CONTEXT_GATEWAY_REQUIRE"
echo "[config] Provider key snapshot in Rust: $ENABLE_PROVIDER_KEY_SNAPSHOT"
echo "[config] Provider quota apply in Rust: $ENABLE_PROVIDER_QUOTA_APPLY"
echo "[config] Provider quota scheduler in Rust: $ENABLE_PROVIDER_QUOTA_SCHEDULER"
echo "[config] XT live cutover: $ENABLE_XT_LIVE_CUTOVER"
echo "[config] Rust local ML execution: $ENABLE_RUST_ML_EXECUTION"

run_step "Package latest Rust Hub" bash "$RUST_SOURCE_ROOT/tools/package_rust_hub.command"
RUST_PACKAGE_DIR="$(latest_rust_package_dir)"
validate_rust_package_dir "$RUST_PACKAGE_DIR"
echo "[rust] Latest package: $RUST_PACKAGE_DIR"

run_step "Build X-Hub.app with embedded Rust Hub" \
  env \
    XHUB_EMBED_RUST_HUB=1 \
    XHUB_RUST_HUB_PACKAGE_DIR="$RUST_PACKAGE_DIR" \
    "$BUILD_APP_COMMAND"

run_step "Install X-Hub.app to /Applications" "$INSTALL_APP_COMMAND"

deploy_embedded_rust_root
activate_embedded_rust_root
open_app_if_needed

echo
echo "Done."
echo "Installed app:"
echo "  $APP_DEST"
echo "Embedded Rust Hub:"
echo "  $APP_DEST/Contents/Resources/rust-hub"
echo "Active writable Rust root:"
echo "  ${ACTIVE_ROOT:-not activated}"
echo "X-Hub container active Rust root:"
echo "  ${CONTAINER_ACTIVE_ROOT:-not activated}"
echo
echo "For normal use, open:"
echo "  $APP_DEST"
