# shellcheck shell=bash
# shellcheck disable=SC2155 # Declare and assign separately to avoid masking return values.
# shellcheck disable=SC2181 # Check exit code directly with e.g. `if mycmd;`, not indirectly with `$?`.

# re-source guard
[[ ${_FILE_SYSTEM_LIB_INCLUDED:-} ]] && return 0
readonly _FILE_SYSTEM_LIB_INCLUDED=1

if [[ -z ${BASH_LIBS_DIR:-} ]]; then
    readonly BASH_LIBS_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
fi

# shellcheck source=./result_type_lib.bash
source "$BASH_LIBS_DIR/result_type_lib.bash"
(($? == 0 )) || return 1

#
# get_device_for_label <device | error> <label>
#
get_device_for_label() {
    local label="$2"
    local device_path="/dev/disk/by-label/$label"

    # resolved device path should be a symlink
    if [[ ! -L "$device_path" ]]; then
        originate_error "$1" 'device labeled "%s" does not exist' "$label"
        return 1
    fi

    # return the resolved path (e.g., /dev/sdc1)
    copy_out_result "$1" "$(readlink -f "$device_path")"
    return 0
}

#
# make_tmpdir <temp-directory | error-message out>
#
make_tmpdir() {
    local tmpvar="$(make_tmpvar)"
    local mktemp_cmd=(mktemp --directory)

    capture_output "$tmpvar" "${mktemp_cmd[@]}" || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    copy_out_result "$1" "${!tmpvar}"
    return 0
}

#
# get_user_home <home-directory | error-trace out> <user-name>
#
get_user_home() {
    local user="$2"

    [[ -n $user ]] || {
        originate_error "$1" 'User name is empty.'
        return 1
    }

    local entry

    entry="$(getent passwd "$user")" || {
        originate_error "$1" 'No such user: "%s".' "$user"
        return 1
    }

    local home

    IFS=: read -r _ _ _ _ _ home _ <<< "$entry"
    copy_out_result "$1" "$home"
    return 0
}
