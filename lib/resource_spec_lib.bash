# shellcheck shell=bash
# shellcheck disable=SC2155 # Declare and assign separately to avoid masking return values.
# shellcheck disable=SC2181 # Check exit code directly with e.g. `if mycmd;`, not indirectly with `$?`.

# execution guard
[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
    echo "$(basename "${BASH_SOURCE[0]}") must be sourced." >&2
    exit 1
}

# re-source guard
[[ ${_RESOURCE_SPEC_LIB_INCLUDED:-} ]] && return 0
readonly _RESOURCE_SPEC_LIB_INCLUDED=1

if [[ -z ${BASH_LIBS_DIR:-} ]]; then
    readonly BASH_LIBS_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
fi

# shellcheck source=./system_lib.bash
source "$BASH_LIBS_DIR/system_lib.bash"
(($? == 0 )) || return 1

# shellcheck source=./result_type_lib.bash
source "$BASH_LIBS_DIR/result_type_lib.bash"
(($? == 0 )) || return 1

#
# Normalized resource-spec forms:
#
#   local:<absolute-path>
#   label:<label>/<absolute-resource-spec-root-without-leading-extra-slash>
#   nfs:<host>/<share>/<absolute-resource-spec-root-without-leading-extra-slash>
#
# Public resource_spec types:
#
#   local
#   label
#   nfs
#

#
# normalize_resource_spec_root <root-path>
#
normalize_resource_spec_root() {
    local root
    root="$(trim_string "$1")"

    [[ -n $root ]] || {
        printf '/\n'
        return 0
    }

    root="$(realpath -m -- "$root")"

    printf '%s\n' "$root"
}

#
# validate_resource_spec <normalized-resource-spec | error-trace out> <candidate-resource-spec>
#
validate_resource_spec() {
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
        originate_error "$1" 'resource_spec is empty'
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
            originate_error "$1" 'label resource_spec must have form label:<label>/<path>'
            return 1
        fi

        normalized_path="$(normalize_resource_spec_root "/$rest")"
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
            originate_error "$1" 'nfs resource_spec must have form nfs:<host>/<share>/<path>'
            return 1
        fi

        normalized_path="$(normalize_resource_spec_root "/$rest")"
        copy_out_result "$1" "nfs:$host/$share$normalized_path"
        return 0
        ;;

    local:*)
        type="local"
        body="${candidate#local:}"
        normalized_path="$(normalize_resource_spec_root "$body")"

        copy_out_result "$1" "local:$normalized_path"
        return 0
        ;;

    *:*)
        originate_error "$1" 'unknown resource_spec type "%s"' "${candidate%%:*}"
        return 1
        ;;

    *)
        normalized_path="$(normalize_resource_spec_root "$candidate")"

        copy_out_result "$1" "local:$normalized_path"
        return 0
        ;;
    esac
}

#
# resource_spec_type <normalized-resource-spec>
#
resource_spec_type() {
    local resource_spec="$1"

    printf '%s\n' "${resource_spec%%:*}"
}

#
# resource_spec_root <normalized-resource-spec>
#
resource_spec_root() {
    local resource_spec="$1"
    local type
    local body
    local rest

    type="$(resource_spec_type "$resource_spec")"
    body="${resource_spec#*:}"

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
# resource_spec_local_file_path <resource-spec> <leaf-name>
#
resource_spec_local_file_path() {
    printf '%s/%s\n' \
        "$(resource_spec_root "$1")" \
        "$2"
}

#
# resource_spec_label <normalized-resource-spec>
#
resource_spec_label() {
    local resource_spec="$1"
    local body="${resource_spec#*:}"

    if [[ $(resource_spec_type "$resource_spec") == label ]]; then
        printf '%s\n' "${body%%/*}"
    else
        printf '\n'
    fi
}

#
# resource_spec_host <normalized-resource-spec>
#
resource_spec_host() {
    local resource_spec="$1"
    local body="${resource_spec#*:}"

    if [[ $(resource_spec_type "$resource_spec") == nfs ]]; then
        printf '%s\n' "${body%%/*}"
    else
        printf '\n'
    fi
}

#
# resource_spec_share <normalized-resource-spec>
#
resource_spec_share() {
    local resource_spec="$1"
    local body="${resource_spec#*:}"
    local rest

    if [[ $(resource_spec_type "$resource_spec") == nfs ]]; then
        rest="${body#*/}"
        printf '%s\n' "${rest%%/*}"
    else
        printf '\n'
    fi
}

#
# format_resource_spec_for_display <normalized-resource-spec>
#
format_resource_spec_for_display() {
    printf '%s\n' "$1"
}
