# shellcheck shell=bash
# shellcheck disable=SC2155 # Declare and assign separately to avoid masking return values.

# execution guard
[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
    echo "$(basename "${BASH_SOURCE[0]}") must be sourced." >&2
    exit 1
}

# re-source guard
[[ ${_FSA_LIB_INCLUDED:-} ]] && return 0

if [[ -z ${BASH_LIBS_DIR:-} ]]; then
    readonly BASH_LIBS_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
fi

# shellcheck source=./system_lib.bash
source "$BASH_LIBS_DIR/system_lib.bash" || return 1

readonly _FSA_LIB_DEPS=(fsarchiver)
verify_script_dependencies "${_FSA_LIB_DEPS[@]}" || return 1
readonly _FSA_LIB_INCLUDED=1

# shellcheck source=./result_type_lib.bash
source "$BASH_LIBS_DIR/result_type_lib.bash"

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
# fsarchiver_savefs <error-message out> <fsa-file> <fs-dev>
#
fsarchiver_savefs() {
    local fsa_file="$2"
    local fs_dev="$3"

    local threads=$(($(nproc) / 2))
    ((threads < 1)) && threads=1

    local compression_level=3

    local fsa_opts=(
        -o
        -j "$threads"
        -Z "$compression_level"
    )

    local rc

    fsarchiver savefs "${fsa_opts[@]}" "$fsa_file" "$fs_dev"
    rc="$?"

    if ((rc != 0)); then
        originate_error "$1" \
            'fsarchiver savefs failed with exit code %d.\n' "$rc"
        return 1
    fi

    return 0
}

#
# archive_file_system <error-trace | fsa-file out> <file-system> <dst-dir>
#
archive_file_system() {
    local file_system="$2"
    local fsa_dir="$3"

    local tmpvar="$(make_tmpvar)"

    if ! get_device_for_label "$tmpvar" "$file_system"; then
        copy_out_error "$1" "${!tmpvar}"
        return 1
    fi

    local fs_dev="${!tmpvar}"

    local basename="$(date +%F-%H-%M-%S)".fsa
    local fsa_file="$(readlink -f "$fsa_dir/$basename")"
    clear_var "$tmpvar"

    if ! fsarchiver_savefs "$tmpvar" "$fsa_file" "$fs_dev"; then
        forward_error "$1" "${!tmpvar}"
        return 1
    fi

    copy_out_result "$1" "$fsa_file"
    return 0
}
