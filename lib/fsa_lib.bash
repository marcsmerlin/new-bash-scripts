# shellcheck shell=bash
# shellcheck disable=SC2155 # Declare and assign separately to avoid masking return values.
# shellcheck disable=SC2181 # Check exit code directly with e.g. `if mycmd;`, not indirectly with `$?`.

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
(($? == 0)) || return 1

# shellcheck source=./file_system_lib.bash
source "$BASH_LIBS_DIR/file_system_lib.bash"
(($? == 0)) || return 1

#
# fsarchiver_archinfo <error-trace out> <fsa-file>
#
fsarchiver_archinfo() {
    local fsa_file="$2"
    local rc

    fsarchiver archinfo "$fsa_file"
    rc="$?"

    if ((rc != 0)); then
        originate_error "$1" \
            'fsarchiver archinfo has failed with error code %d.\n' \
            "$rc"
        return 1
    fi

    return 0
}

#
# fsarchiver_savefs <error-trace out> <fsa-file> <fs-dev>
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
# make_fsa_file_name <file-system>
#
make_fsa_file_name() {
    local file_system="$1"
    printf '%s_%s_%s.fsa\n' \
        "$file_system" \
        "$(date +%F)" \
        "$(date +%H-%M)"
}

#
# archive_file_system_to_directory <error-trace | fsa-file out> <file-system> <dst-dir>
#
archive_file_system_to_directory() {
    local file_system="$2"
    local fsa_dir="$3"

    local tmpvar="$(make_tmpvar)"

    if ! get_device_for_label "$tmpvar" "$file_system"; then
        copy_out_error "$1" "${!tmpvar}"
        return 1
    fi

    local fs_dev="${!tmpvar}"

    local fsa_file_name="$(make_fsa_file_name "$file_system")"
    local fsa_file_path="$(readlink -f "$fsa_dir/$fsa_file_name")"

    if ! fsarchiver_savefs "$tmpvar" "$fsa_file_path" "$fs_dev"; then
        forward_error "$1" "${!tmpvar}"
        return 1
    fi

    copy_out_result "$1" "$fsa_file_path"
    return 0
}
