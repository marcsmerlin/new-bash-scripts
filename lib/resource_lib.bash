# shellcheck shell=bash
# shellcheck disable=SC2155 # Declare and assign separately to avoid masking return values.

# execution guard
[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
    echo "$(basename "${BASH_SOURCE[0]}") must be sourced." >&2
    exit 1
}

# re-source guard
[[ ${_RESOURCE_LIB_INCLUDED:-} ]] && return 0
readonly _RESOURCE_LIB_INCLUDED=1

if [[ -z ${BASH_LIBS_DIR:-} ]]; then
    readonly BASH_LIBS_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
fi

# shellcheck source=./system_lib.bash
source "$BASH_LIBS_DIR/system_lib.bash" || return 1

# shellcheck source=./result_type_lib.bash
source "$BASH_LIBS_DIR/result_type_lib.bash" || return 1

#
# This library validates and queries pre-resolution resource specifications.
# It does not mount, probe, or require target existence.
#
# Supported normalized resource forms:
#
#   local:<absolute-path>
#   label:<label>/<absolute-resource-path-without-leading-extra-slash>
#   nfs:<host>/<share>/<absolute-resource-path-without-leading-extra-slash>
#
# Public resource types:
#
#   local
#   label
#   nfs
#

#
# normalize_resource_path <path>
#
normalize_resource_path() {
    local path
    path="$(trim_string "$1")"

    [[ -n $path ]] || {
        printf '/\n'
        return 0
    }

    path="$(realpath -m -- "$path")"

    printf '%s\n' "$path"
}

#
# validate_resource <normalized-resource | error-trace out> <candidate-resource>
#
validate_resource() {
    local candidate
    local type
    local body
    local normalized_path
    local label
    local host
    local share
    local rest

    candidate="$(trim_string "$2")"

    if [[ -z $candidate ]]; then
        originate_error "$1" 'resource is empty'
        return 1
    fi

    case "$candidate" in
    label:*)
        type="label"
        body="${candidate#label:}"

        label="${body%%/*}"
        rest="${body#*/}"

        label="$(trim_string "$label")"
        rest="$(trim_string "$rest")"

        if [[ -z $label || $label == "$body" ]]; then
            originate_error "$1" 'label resource must have form label:<label>/<path>'
            return 1
        fi

        normalized_path="$(normalize_resource_path "/$rest")"
        copy_out_result "$1" "label:$label$normalized_path"
        return 0
        ;;

    nfs:*)
        type="nfs"
        body="${candidate#nfs:}"

        host="${body%%/*}"
        rest="${body#*/}"
        share="${rest%%/*}"
        rest="${rest#*/}"

        host="$(trim_string "$host")"
        share="$(trim_string "$share")"
        rest="$(trim_string "$rest")"

        if [[ -z $host || -z $share || $host == "$body" || $share == "$rest" ]]; then
            originate_error "$1" 'nfs resource must have form nfs:<host>/<share>/<path>'
            return 1
        fi

        normalized_path="$(normalize_resource_path "/$rest")"
        copy_out_result "$1" "nfs:$host/$share$normalized_path"
        return 0
        ;;

    local:*)
        type="local"
        body="${candidate#local:}"
        normalized_path="$(normalize_resource_path "$body")"

        copy_out_result "$1" "local:$normalized_path"
        return 0
        ;;

    *:*)
        originate_error "$1" 'unknown resource type "%s"' "${candidate%%:*}"
        return 1
        ;;

    *)
        normalized_path="$(normalize_resource_path "$candidate")"

        copy_out_result "$1" "local:$normalized_path"
        return 0
        ;;
    esac
}

#
# get_resource_type <normalized-resource>
#
get_resource_type() {
    local resource="$1"

    printf '%s\n' "${resource%%:*}"
}

#
# get_resource_path <normalized-resource>
#
get_resource_path() {
    local resource="$1"
    local type
    local body
    local rest

    type="$(get_resource_type "$resource")"
    body="${resource#*:}"

    case "$type" in
    local)
        printf '%s\n' "$body"
        ;;

    label)
        rest="${body#*/}"
        printf '/%s\n' "$rest"
        ;;

    nfs)
        rest="${body#*/}"
        rest="${rest#*/}"
        printf '/%s\n' "$rest"
        ;;

    *)
        printf '\n'
        ;;
    esac
}

#
# get_resource_label <normalized-resource>
#
get_resource_label() {
    local resource="$1"
    local body="${resource#*:}"

    if [[ $(get_resource_type "$resource") == label ]]; then
        printf '%s\n' "${body%%/*}"
    else
        printf '\n'
    fi
}

#
# get_resource_host <normalized-resource>
#
get_resource_host() {
    local resource="$1"
    local body="${resource#*:}"

    if [[ $(get_resource_type "$resource") == nfs ]]; then
        printf '%s\n' "${body%%/*}"
    else
        printf '\n'
    fi
}

#
# get_resource_share <normalized-resource>
#
get_resource_share() {
    local resource="$1"
    local body="${resource#*:}"
    local rest

    if [[ $(get_resource_type "$resource") == nfs ]]; then
        rest="${body#*/}"
        printf '%s\n' "${rest%%/*}"
    else
        printf '\n'
    fi
}

#
# format_resource_for_display <normalized-resource>
#
format_resource_for_display() {
    printf '%s\n' "$1"
}
