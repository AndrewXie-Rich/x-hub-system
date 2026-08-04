#!/usr/bin/env bash

xterminal_release_codesign_registry() {
  local repository_root="$1"
  printf '%s\n' "$repository_root/release/trusted_codesign_team_ids.txt"
}

xterminal_assert_release_codesign_identity() {
  local identity="${1:-}"
  if [ -z "$identity" ] || [ "$identity" = "-" ]; then
    echo "[XT SIGN] Formal release requires a non-ad-hoc codesign identity." >&2
    return 1
  fi
}

xterminal_assert_release_codesign_registry() {
  local repository_root="$1"
  local registry=""
  registry="$(xterminal_release_codesign_registry "$repository_root")"
  if [ ! -f "$registry" ] || [ -L "$registry" ] || \
     ! git -C "$repository_root" ls-files --error-unmatch \
       release/trusted_codesign_team_ids.txt >/dev/null 2>&1; then
    echo "[XT SIGN] Tracked Team ID registry is missing: $registry" >&2
    return 1
  fi
  if ! awk '
    /^[[:space:]]*(#|$)/ { next }
    { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$registry"; then
    echo "[XT SIGN] Team ID registry has no approved publisher." >&2
    return 1
  fi
}

xterminal_verify_pinned_codesign() {
  local artifact="$1"
  local repository_root="$2"
  local deep="${3:-0}"
  local registry=""
  local details=""
  local team_id=""
  local -a verify_args=(--verify --strict)

  if [ "$deep" = "1" ]; then
    verify_args+=(--deep)
  elif [ "$deep" != "0" ]; then
    echo "[XT SIGN] Invalid deep-verification flag: $deep" >&2
    return 1
  fi
  if [ ! -e "$artifact" ] || [ -L "$artifact" ]; then
    echo "[XT SIGN] Artifact must exist and must not be a symlink: $artifact" >&2
    return 1
  fi

  registry="$(xterminal_release_codesign_registry "$repository_root")"
  xterminal_assert_release_codesign_registry "$repository_root"
  if ! codesign "${verify_args[@]}" "$artifact"; then
    echo "[XT SIGN] codesign verification failed: $artifact" >&2
    return 1
  fi
  details="$(codesign -d --verbose=4 "$artifact" 2>&1)"
  team_id="$(
    printf '%s\n' "$details" \
      | awk -F= '/^TeamIdentifier=/ { print $2; exit }'
  )"
  if [ -z "$team_id" ] || [ "$team_id" = "not set" ]; then
    echo "[XT SIGN] Signed artifact has no Developer Team ID: $artifact" >&2
    return 1
  fi
  if ! awk '
    /^[[:space:]]*(#|$)/ { next }
    {
      value = $0
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      if (value == expected) found = 1
    }
    END { exit(found ? 0 : 1) }
  ' expected="$team_id" "$registry"; then
    echo "[XT SIGN] Team ID is not in the tracked trust registry: $team_id" >&2
    return 1
  fi
  printf '%s\n' "$team_id"
}
