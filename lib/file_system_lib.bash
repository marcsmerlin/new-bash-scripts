# shellcheck shell=bash
# shellcheck disable=SC2155 # Declare and assign separately to avoid masking return values.

# execution guard
[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
    echo "$(basename "${BASH_SOURCE[0]}") must be sourced." >&2
    exit 1
}

# re-source guard
[[ ${_FILE_SYSTEM_LIB_INCLUDED:-} ]] && return 0
readonly _FILE_SYSTEM_LIB_INCLUDED=1

if [[ -z ${BASH_LIBS_DIR:-} ]]; then
    readonly BASH_LIBS_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
fi

# shellcheck source=./result_type_lib.bash
source "$BASH_LIBS_DIR/result_type_lib.bash" || return 1

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
