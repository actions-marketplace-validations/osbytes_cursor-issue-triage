#!/usr/bin/env bash
# Encode images from GitHub issue body for Cursor Cloud Agents API v0
# Reads issue body from file argument or stdin, outputs JSON array to stdout
set -euo pipefail

MAX_IMAGES=5
MAX_BYTES=15728640
TIMEOUT=45

issue_body="${1:-}"

if [[ -n "${issue_body}" && -f "${issue_body}" ]]; then
  issue_body="$(cat "${issue_body}")"
elif [[ -n "${issue_body}" ]]; then
  issue_body="$(cat)"
else
  issue_body="$(cat)"
fi

if [[ -z "${issue_body}" ]]; then
  echo "[]"
  exit 0
fi

extract_urls() {
  local text="$1"
  local urls=()
  local seen=()
  
  while IFS= read -r url; do
    if [[ -n "${url}" ]]; then
      local is_dup=0
      for s in "${seen[@]:-}"; do
        if [[ "${s}" == "${url}" ]]; then
          is_dup=1
          break
        fi
      done
      if [[ ${is_dup} -eq 0 ]]; then
        urls+=("${url}")
        seen+=("${url}")
        if [[ ${#urls[@]} -ge ${MAX_IMAGES} ]]; then
          break
        fi
      fi
    fi
  done < <(echo "${text}" | grep -oE '!\[[^]]*\]\([^)]+\)' | sed -E 's/!\[[^]]*\]\((https:\/\/[^)]+)\)/\1/' 2>/dev/null || true)
  
  while IFS= read -r url; do
    if [[ -n "${url}" ]]; then
      local is_dup=0
      for s in "${seen[@]:-}"; do
        if [[ "${s}" == "${url}" ]]; then
          is_dup=1
          break
        fi
      done
      if [[ ${is_dup} -eq 0 ]]; then
        urls+=("${url}")
        seen+=("${url}")
        if [[ ${#urls[@]} -ge ${MAX_IMAGES} ]]; then
          break
        fi
      fi
    fi
  done < <(echo "${text}" | grep -oE '<img[^>]+src=["'"'"']?https://[^"'"'"'>[:space:]]+' | sed -E 's/.*src=["'"'"']?(https:\/\/[^"'"'"'>[:space:]]+).*/\1/' 2>/dev/null || true)
  
  printf '%s\n' "${urls[@]:-}"
}

get_dimensions() {
  local tmp_file="$1"
  local file_output
  file_output="$(file -b "${tmp_file}" 2>/dev/null || echo "")"
  if [[ -z "${file_output}" ]]; then
    echo ""
    return
  fi
  local dims
  dims="$(echo "${file_output}" | grep -oE '[0-9]+ x [0-9]+' | head -1 || echo "")"
  if [[ -z "${dims}" ]]; then
    echo ""
    return
  fi
  local width height
  width="$(echo "${dims}" | awk '{print $1}')"
  height="$(echo "${dims}" | awk '{print $3}')"
  echo "${width}x${height}"
}

fetch_and_encode() {
  local url="$1"
  local tmp_file
  tmp_file="$(mktemp)"
  trap "rm -f '${tmp_file}'" RETURN
  
  if ! curl -sS --max-time "${TIMEOUT}" --location --max-filesize "${MAX_BYTES}" -o "${tmp_file}" "${url}" 2>/dev/null; then
    return 1
  fi
  
  if [[ ! -s "${tmp_file}" ]]; then
    return 1
  fi
  
  local base64_data
  base64_data="$(base64 -w0 "${tmp_file}")"
  
  local dims
  dims="$(get_dimensions "${tmp_file}")"
  
  if [[ -n "${dims}" ]]; then
    local width height
    width="${dims%x*}"
    height="${dims#*x}"
    jq -n --arg data "${base64_data}" --argjson w "${width}" --argjson h "${height}" \
      '{data: $data, dimension: {width: $w, height: $h}}'
  else
    jq -n --arg data "${base64_data}" '{data: $data}'
  fi
}

main() {
  local urls
  urls="$(extract_urls "${issue_body}")"
  
  local images=()
  while IFS= read -r url; do
    if [[ -n "${url}" ]]; then
      local img_json
      if img_json="$(fetch_and_encode "${url}")"; then
        images+=("${img_json}")
      fi
    fi
  done <<< "${urls}"
  
  if [[ ${#images[@]} -eq 0 ]]; then
    echo "[]"
    return 0
  fi
  
  local result="["
  local first=1
  for img in "${images[@]}"; do
    if [[ ${first} -eq 1 ]]; then
      first=0
    else
      result+=","
    fi
    result+="${img}"
  done
  result+="]"
  
  echo "${result}" | jq '.'
}

main
