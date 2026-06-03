# shellcheck shell=bash
# shellcheck disable=SC2155 # Declare and assign separately to avoid masking return values.
# shellcheck disable=SC2181 # Check exit code directly with e.g. `if mycmd;`, not indirectly with `$?`.

# re-source guard
[[ ${_rspec_lib_included:-} ]] && return 0
readonly _rspec_lib_included=1

if [[ -z ${BASH_LIBS_DIR:-} ]]; then
    readonly BASH_LIBS_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
fi

# shellcheck source=./system_lib.bash
source "$BASH_LIBS_DIR/system_lib.bash"
(($? == 0)) || return 1

# shellcheck source=./result_type_lib.bash
source "$BASH_LIBS_DIR/result_type_lib.bash"
(($? == 0)) || return 1

#
# Normalized rspec forms:
#
#   local:<absolute-path>
#   label:<label>/<absolute-rspec-path-without-leading-extra-slash>
#   cifs:<host>/<share>/<absolute-rspec-path-without-leading-extra-slash>
#
# Public rspec types:
#
#   local
#   label
#   cifs
#

#
# _rspec_normalize_path <path>
#
_rspec_normalize_path() {
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
# rspec_normalize <normalized-rspec | error-trace out> <candidate-rspec>
#
rspec_normalize() {
    local candidate
    local body
    local path
    local label
    local host
    local share
    local rest

    candidate="$(trim_string "$2")"

    if [[ -z $candidate ]]; then
        originate_error "$1" 'rspec is empty.'
        return 1
    fi

    case "$candidate" in

    label:*)
        body="${candidate#label:}"

        label="${body%%/*}"

        if [[ $label == "$body" ]]; then
            rest=''
        else
            rest="${body#*/}"
        fi

        label="$(trim_string "$label")"
        rest="$(trim_string "$rest")"

        if [[ -z $label ]]; then
            originate_error "$1" \
                'rspec of type "label" must have the form label:<label> or label:<label>/<path>'
            return 1
        fi

        path="$(_rspec_normalize_path "/$rest")"
        copy_out_result "$1" "label:$label$path"
        return 0
        ;;

    cifs:*)
        body="${candidate#cifs:}"

        host="${body%%/*}"
        rest="${body#*/}"

        if [[ $host == "$body" ]]; then
            originate_error "$1" \
                'rspec of type "cifs" must have form cifs:<host>/<share> or cifs:<host>/<share>/<path>'
            return 1
        fi

        share="${rest%%/*}"

        if [[ $share == "$rest" ]]; then
            rest=''
        else
            rest="${rest#*/}"
        fi

        host="$(trim_string "$host")"
        share="$(trim_string "$share")"
        rest="$(trim_string "$rest")"

        if [[ -z $host || -z $share ]]; then
            originate_error "$1" \
                'rspec of type "cifs" must have form cifs:<host>/<share> or cifs:<host>/<share>/<path>'
            return 1
        fi

        path="$(_rspec_normalize_path "/$rest")"
        copy_out_result "$1" "cifs:$host/$share$path"
        return 0
        ;;

    *:*)
        originate_error "$1" 'Unknown rspec type "%s"' "${candidate%%:*}"
        return 1
        ;;

    *)
        path="$(_rspec_normalize_path "$candidate")"

        copy_out_result "$1" "local:$path"
        return 0
        ;;
    esac
}

#
# rspec_type <rspec>
#
rspec_type() {
    local rspec="$1"

    printf '%s\n' "${rspec%%:*}"
}

#
# rspec_path <rspec>
#
rspec_path() {
    local rspec="$1"
    local type
    local body
    local rest

    type="$(rspec_type "$rspec")"
    body="${rspec#*:}"

    case "$type" in
    local)
        printf '%s\n' "$body"
        ;;

    label)
        rest="${body#*/}"
        printf '/%s\n' "$rest"
        ;;

    cifs)
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
# rspec_label <rspec>
#
rspec_label() {
    local rspec="$1"
    local body="${rspec#*:}"

    if [[ $(rspec_type "$rspec") == label ]]; then
        printf '%s\n' "${body%%/*}"
    else
        printf '\n'
    fi
}

#
# rspec_host <rspec>
#
rspec_host() {
    local rspec="$1"
    local body="${rspec#*:}"

    if [[ $(rspec_type "$rspec") == cifs ]]; then
        printf '%s\n' "${body%%/*}"
    else
        printf '\n'
    fi
}

#
# rspec_share <rspec>
#
rspec_share() {
    local rspec="$1"
    local body="${rspec#*:}"
    local rest

    if [[ $(rspec_type "$rspec") == cifs ]]; then
        rest="${body#*/}"
        printf '%s\n' "${rest%%/*}"
    else
        printf '\n'
    fi
}

#
# rspec_format <rspec>
#
rspec_format() {
    printf '%s\n' "$1"
}

#
# rspec_extend_path <rspec> <extension>
#
# Usage note: extended_rspec="$(rspec_extend_path "$original_rspec" 'marc/Videos')"
#
rspec_extend_path() {
    local rspec="$1"
    local extension="$2"
    local type
    local path

    type="$(rspec_type "$rspec")"
    path="$(_rspec_normalize_path "$(rspec_path "$rspec")/$extension")"

    case "$type" in
    local)
        printf 'local:%s\n' "$path"
        ;;
    label)
        printf 'label:%s%s\n' "$(rspec_label "$rspec")" "$path"
        ;;
    cifs)
        printf 'cifs:%s/%s%s\n' \
            "$(rspec_host "$rspec")" \
            "$(rspec_share "$rspec")" \
            "$path"
        ;;
    esac
}
