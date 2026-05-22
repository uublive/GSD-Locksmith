#!/usr/bin/env bash
# .gsd/locksmith/lib/validate.sh — Validation functions for GSD planning file integrity
#
# Phase:    03-git-merge-validation
# Purpose:  Four validation functions sourced by .githooks/pre-merge-commit
# Provides: check_phase_gaps, check_duplicate_req_ids, check_state_drift, check_stale_refs
#
# Decisions implemented:
#   D-03: Compiler-style error format: file:line: ERROR: message
#   D-04: Every error includes file path, line number, what's wrong, and fix command
#   D-05: All output to stderr; functions return 0 (pass) or non-zero (fail)
#   D-09: Functions return (never exit) so callers can accumulate all errors
#   D-10: Production reads via git show :path; TESTING_MODE=1 reads GSD_TEST_* env vars
#
# Threat mitigations:
#   T-03-01: All git show output quoted with "$var" — never eval; grep/awk treat content as data
#   T-03-04: return not exit; temp files cleaned up unconditionally via rm -f

# Internal verbose logger (mirrors common.sh verbose_log without requiring jq/gh deps)
_validate_verbose_log() {
  [[ -n "${GSD_VERBOSE:-}" ]] && echo "[GSD-VAL] $*" >&2 || true
}

# ---------------------------------------------------------------------------
# VAL-01: check_phase_gaps
# Detects non-sequential phase numbering in ROADMAP.md.
# Returns 0 if phases are sequential; non-zero if any gap found.
# ---------------------------------------------------------------------------
check_phase_gaps() {
  local content
  local errors=0

  if [[ "${TESTING_MODE:-0}" -eq 1 ]]; then
    content="${GSD_TEST_ROADMAP:-}"
  else
    content="$(git show :.planning/ROADMAP.md 2>/dev/null)" || {
      echo ".planning/ROADMAP.md:0: ERROR: file not found in merged state" >&2
      echo "  Fix: ensure .planning/ROADMAP.md is tracked and staged" >&2
      return 1
    }
  fi

  _validate_verbose_log "check_phase_gaps: scanning ROADMAP.md for phase sequence"

  # Extract phase lines with line numbers, detect gaps with awk.
  # BSD awk (macOS) does not support three-argument match() — use split on "Phase ".
  # Input to awk: "LINENUM:rest-of-line" from grep -nE
  # awk extracts phase number from "Phase N:" using split on "Phase " and then split on ":"
  local gap_errors
  gap_errors=$(echo "$content" | \
    grep -nE '^\- \[.\] \*\*Phase [0-9]+:' | \
    awk -F: '{
      # $1 = line number, rest = line content (may contain multiple colons)
      linenum = $1
      # Reconstruct line content (skip linenum field)
      line = ""
      for (i=2; i<=NF; i++) {
        line = line (i==2 ? "" : ":") $i
      }
      # Extract phase number: split on "Phase " and take the integer part
      n = split(line, parts, "Phase ")
      if (n >= 2) {
        phase_num = int(parts[2])
      } else {
        next
      }
      if (NR == 1) {
        prev = phase_num
        next
      }
      expected = prev + 1
      if (phase_num != expected) {
        print ".planning/ROADMAP.md:" linenum ": ERROR: Phase gap -- expected Phase " expected " found Phase " phase_num
        print "  Fix: add Phase " expected " entry before line " linenum ", or renumber phases sequentially"
      }
      prev = phase_num
    }')

  if [[ -n "$gap_errors" ]]; then
    echo "$gap_errors" >&2
    # Count error lines (lines starting with ".planning/") for return code
    errors=$(echo "$gap_errors" | grep -cE '^\.' || true)
  fi

  return "$errors"
}

# ---------------------------------------------------------------------------
# VAL-02: check_duplicate_req_ids
# Detects duplicate REQ-IDs in REQUIREMENTS.md.
# Returns 0 if no duplicates; non-zero (count of duplicate occurrences) if any found.
# ---------------------------------------------------------------------------
check_duplicate_req_ids() {
  local content
  local errors=0

  if [[ "${TESTING_MODE:-0}" -eq 1 ]]; then
    content="${GSD_TEST_REQUIREMENTS:-}"
  else
    content="$(git show :.planning/REQUIREMENTS.md 2>/dev/null)" || {
      echo ".planning/REQUIREMENTS.md:0: ERROR: file not found in merged state" >&2
      echo "  Fix: ensure .planning/REQUIREMENTS.md is tracked and staged" >&2
      return 1
    }
  fi

  _validate_verbose_log "check_duplicate_req_ids: scanning REQUIREMENTS.md for duplicate IDs"

  # Pass 1: find which IDs appear more than once
  local dups
  dups=$(echo "$content" | grep -oE '\*\*[A-Z]+-[0-9]+\*\*' | sed 's/\*\*//g' | sort | uniq -d)

  if [[ -z "$dups" ]]; then
    return 0
  fi

  # Pass 2: for each duplicate ID, find its line numbers.
  # Write errors to temp file to avoid subshell variable loss.
  local tmpfile
  tmpfile=$(mktemp)

  while IFS= read -r dup_id; do
    [[ -z "$dup_id" ]] && continue
    # Find all lines containing this ID
    while IFS=: read -r linenum rest; do
      [[ -z "$linenum" ]] && continue
      echo ".planning/REQUIREMENTS.md:$linenum: ERROR: Duplicate REQ-ID $dup_id" >> "$tmpfile"
      echo "  Fix: rename one occurrence of $dup_id to the next available ID in its category" >> "$tmpfile"
    done < <(echo "$content" | grep -nE "\*\*${dup_id}\*\*")
  done <<< "$dups"

  errors=$(wc -l < "$tmpfile" | tr -d ' ')
  # Halve: each error is 2 lines (error + fix), but we want to count error lines only
  # Actually: count lines matching ": ERROR:" pattern
  errors=$(grep -cE ': ERROR:' "$tmpfile" || true)
  cat "$tmpfile" >&2
  rm -f "$tmpfile"

  return "$errors"
}

# ---------------------------------------------------------------------------
# VAL-03: check_state_drift
# Detects mismatches between STATE.md and ROADMAP.md:
#   Check A: progress.total_phases in STATE.md vs phase count in ROADMAP.md
#   Check B: active **Phase:** N in STATE.md body vs phases present in ROADMAP.md
# Returns 0 if no drift; non-zero if any mismatch found.
# ---------------------------------------------------------------------------
check_state_drift() {
  local state_content roadmap_content
  local errors=0

  if [[ "${TESTING_MODE:-0}" -eq 1 ]]; then
    state_content="${GSD_TEST_STATE:-}"
    roadmap_content="${GSD_TEST_ROADMAP:-}"
  else
    state_content="$(git show :.planning/STATE.md 2>/dev/null)" || {
      echo ".planning/STATE.md:0: ERROR: file not found in merged state" >&2
      echo "  Fix: ensure .planning/STATE.md is tracked and staged" >&2
      return 1
    }
    roadmap_content="$(git show :.planning/ROADMAP.md 2>/dev/null)" || {
      echo ".planning/ROADMAP.md:0: ERROR: file not found in merged state" >&2
      echo "  Fix: ensure .planning/ROADMAP.md is tracked and staged" >&2
      return 1
    }
  fi

  _validate_verbose_log "check_state_drift: comparing STATE.md vs ROADMAP.md"

  # Count actual phases in ROADMAP.md
  local roadmap_phase_count
  roadmap_phase_count=$(echo "$roadmap_content" | grep -cE '^\- \[.\] \*\*Phase [0-9]+:' || true)

  # --- Check A: total_phases in STATE.md YAML frontmatter ---
  local state_total_line
  state_total_line=$(echo "$state_content" | grep -n 'total_phases:' | head -1)

  if [[ -n "$state_total_line" ]]; then
    local state_total_phases
    state_total_phases=$(echo "$state_total_line" | grep -oE '[0-9]+' | tail -1)
    local total_line_num
    total_line_num=$(echo "$state_total_line" | cut -d: -f1)

    if [[ "$state_total_phases" != "$roadmap_phase_count" ]]; then
      echo ".planning/STATE.md:$total_line_num: ERROR: total_phases ($state_total_phases) does not match ROADMAP.md phase count ($roadmap_phase_count)" >&2
      echo "  Fix: update STATE.md progress.total_phases to $roadmap_phase_count" >&2
      errors=$((errors + 1))
    fi
  fi

  # --- Check B: active **Phase:** N in STATE.md body ---
  local active_phase_line
  active_phase_line=$(echo "$state_content" | grep -n '^\*\*Phase:\*\*' | head -1)

  if [[ -n "$active_phase_line" ]]; then
    local active_phase_num
    # Extract the phase number from the value after "**Phase:** " (not the line number prefix)
    active_phase_num=$(echo "$active_phase_line" | sed 's/.*\*\*Phase:\*\*[[:space:]]*//' | grep -oE '^[0-9]+')
    local active_line_num
    active_line_num=$(echo "$active_phase_line" | cut -d: -f1)

    if [[ -n "$active_phase_num" ]]; then
      local phase_exists
      phase_exists=$(echo "$roadmap_content" | \
        grep -cE "^\- \[.\] \*\*Phase ${active_phase_num}:" || true)
      if [[ "$phase_exists" -eq 0 ]]; then
        echo ".planning/STATE.md:$active_line_num: ERROR: Active phase $active_phase_num not found in ROADMAP.md" >&2
        echo "  Fix: update STATE.md **Phase:** to a phase listed in ROADMAP.md ## Phases, or restore Phase $active_phase_num to ROADMAP.md" >&2
        errors=$((errors + 1))
      fi
    fi
  fi

  return "$errors"
}

# ---------------------------------------------------------------------------
# VAL-04: check_stale_refs
# Detects REQ-IDs in PLAN.md frontmatter requirements: field that no longer
# exist in REQUIREMENTS.md.
# Returns 0 if all refs are valid; non-zero if any stale refs found.
# ---------------------------------------------------------------------------
check_stale_refs() {
  local req_content
  local errors=0

  if [[ "${TESTING_MODE:-0}" -eq 1 ]]; then
    req_content="${GSD_TEST_REQUIREMENTS:-}"
  else
    req_content="$(git show :.planning/REQUIREMENTS.md 2>/dev/null)" || {
      echo ".planning/REQUIREMENTS.md:0: ERROR: file not found in merged state" >&2
      echo "  Fix: ensure .planning/REQUIREMENTS.md is tracked and staged" >&2
      return 1
    }
  fi

  _validate_verbose_log "check_stale_refs: scanning PLAN.md files for stale REQ-IDs"

  # Build set of valid REQ-IDs from REQUIREMENTS.md
  local valid_req_ids
  valid_req_ids=$(echo "$req_content" | grep -oE '\*\*[A-Z]+-[0-9]+\*\*' | sed 's/\*\*//g')

  # Write all errors to a temp file (avoid subshell counter loss)
  local tmpfile
  tmpfile=$(mktemp)

  if [[ "${TESTING_MODE:-0}" -eq 1 ]]; then
    # In testing mode: process single plan file from env vars
    local plan_content plan_path
    plan_content="${GSD_TEST_PLAN_CONTENT:-}"
    plan_path="${GSD_TEST_PLAN_PATH:-.planning/phases/test/00-00-PLAN.md}"

    _check_plan_for_stale_refs "$plan_content" "$plan_path" "$valid_req_ids" "$tmpfile"
  else
    # In production: enumerate all PLAN.md files from the git index
    while IFS= read -r plan_path; do
      [[ -z "$plan_path" ]] && continue
      local plan_content
      plan_content="$(git show ":${plan_path}" 2>/dev/null)" || continue
      _check_plan_for_stale_refs "$plan_content" "$plan_path" "$valid_req_ids" "$tmpfile"
    done < <(git ls-files '.planning/phases' | grep -E '[0-9]+-[0-9]+-PLAN\.md$')
  fi

  errors=$(grep -cE ': ERROR:' "$tmpfile" || true)
  cat "$tmpfile" >&2
  rm -f "$tmpfile"

  return "$errors"
}

# Internal helper: check a single plan's frontmatter for stale REQ-ID references.
# Args: $1=plan_content $2=plan_path $3=valid_req_ids_newline_separated $4=tmpfile
_check_plan_for_stale_refs() {
  local plan_content="$1"
  local plan_path="$2"
  local valid_req_ids="$3"
  local tmpfile="$4"

  # Extract REQ-IDs from YAML frontmatter requirements: field.
  # Frontmatter is between the first and second "---" markers.
  # Lines matching "  - [A-Z]+-[0-9]+" in that block are requirement references.
  # awk: track frontmatter block; print NR and the ID when inside block.
  local frontmatter_refs
  frontmatter_refs=$(echo "$plan_content" | awk '
    /^---/ { fm++; next }
    fm >= 2 { exit }
    fm == 1 && /^  - [A-Z]+-[0-9]+/ {
      # Extract just the ID (strip leading whitespace and "- ")
      id = $0
      gsub(/^[[:space:]]*- /, "", id)
      gsub(/[[:space:]]*$/, "", id)
      print NR " " id
    }
  ')

  if [[ -z "$frontmatter_refs" ]]; then
    return 0
  fi

  while IFS=' ' read -r linenum ref_id; do
    [[ -z "$ref_id" ]] && continue
    if ! echo "$valid_req_ids" | grep -qx "$ref_id"; then
      echo "${plan_path}:$linenum: ERROR: Stale REQ-ID reference $ref_id (not in REQUIREMENTS.md)" >> "$tmpfile"
      echo "  Fix: remove '- $ref_id' from requirements: field, or restore $ref_id to REQUIREMENTS.md" >> "$tmpfile"
    fi
  done <<< "$frontmatter_refs"
}
