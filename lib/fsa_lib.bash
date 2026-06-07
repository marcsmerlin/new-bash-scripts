# shellcheck shell=bash
# shellcheck disable=SC2155 # Declare and assign separately to avoid masking return values.
# shellcheck disable=SC2181 # Check exit code directly with e.g. `if mycmd;`, not indirectly with `$?`.

# re-source guard
[[ ${_fsa_lib_included:-} ]] && return 0

if [[ -z ${BASH_LIBS_DIR:-} ]]; then
    readonly BASH_LIBS_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
fi

# shellcheck source=./system_lib.bash
source "$BASH_LIBS_DIR/system_lib.bash" || return 1

readonly _fsa_lib_deps=(fsarchiver)
verify_script_dependencies "${_fsa_lib_deps[@]}" || return 1
readonly _fsa_lib_included=1

# shellcheck source=./result_type_lib.bash
source "$BASH_LIBS_DIR/result_type_lib.bash"
(($? == 0)) || return 1

# shellcheck source=./rspec_lib.bash
source "$BASH_LIBS_DIR/rspec_lib.bash"
(($? == 0)) || return 1

# shellcheck source=./mspec_lib.bash
source "$BASH_LIBS_DIR/mspec_lib.bash"
(($? == 0)) || return 1

# shellcheck source=./picker_lib.bash
source "$BASH_LIBS_DIR/picker_lib.bash"
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

    local tmpvar="$(make_tmpvar)"
    local rc

    sudo_context_capture "$tmpvar" \
        fsarchiver savefs "${fsa_opts[@]}" "$fsa_file" "$fs_dev"

    rc="$?"

    ((rc == 0)) || {
        originate_error "$1" "${!tmpvar}"
        return 1
    }

    return 0
}

#
# is_fsa_file <file-name>
#
is_fsa_file() {
    [[ -f "$1" && "$1" == *.fsa ]]
}

#
# _make_fsa_file_name <file-system>
#
_make_fsa_file_name() {
    local file_system="$1"
    printf '%s_%s_%s.fsa\n' \
        "$file_system" \
        "$(date +%F)" \
        "$(date +%H-%M-%S)"
}

#
# create_fsa_file <error-trace | fsa-file-rspec out> <file-system> <resource-spec>
#
create_fsa_file() {
    local file_system="$2"
    local rspec="$3"
    local tmpvar="$(make_tmpvar)"

    get_device_for_label "$tmpvar" "$file_system" || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    local fs_dev="${!tmpvar}"
    local fsa_file_name="$(_make_fsa_file_name "$file_system")"

    mspec_temp_mount_rspec "$tmpvar" "$rspec" 'create-if-missing' || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    local mspec="${!tmpvar}"
    local fsa_file_path="$(mspec_file_path "$mspec" "$fsa_file_name")"

    fsarchiver_savefs "$tmpvar" "$fsa_file_path" "$fs_dev" || {
        local trigger_error="${!tmpvar}"

        defer_forward_error "$1" \
            "$trigger_error" \
            mspec_release "$mspec"

        return 1
    }

    sudo_chown "$tmpvar" "$fsa_file_path" || {
        local trigger_error="${!tmpvar}"

        defer_forward_error "$1" \
            "$trigger_error" \
            mspec_release "$mspec"

        return 1
    }

    mspec_release "$tmpvar" "$mspec" || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    copy_out_result "$1" "$(rspec_extend_path "$rspec" "$fsa_file_name")"
    return 0
}

#
# inspect_fsa_directory_with_filter <error-trace out> <resource-spec> <filter>
#
inspect_fsa_directory_with_filter() {
    local rspec="$2"
    local filter="$3"

    local tmpvar="$(make_tmpvar)"

    mspec_temp_mount_rspec "$tmpvar" "$rspec" 'require-exisiting' || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    local mspec="${!tmpvar}"
    local directory="$(mspec_path "$mspec")"

    pick_entry_from_directory "$tmpvar" 'index of file to inspect? ' "$directory" "$filter" || {
        defer_forward_error "$1" \
            "${!tmpvar}" \
            mspec_release "$mspec"

        return 1
    }

    local fsa_file_path="${!tmpvar}"

    if [[ -n "$fsa_file_path" ]]; then
        fsarchiver_archinfo "$tmpvar" "$fsa_file_path" || {
            defer_forward_error "$1" \
                "${!tmpvar}" \
                mspec_release "$mspec"

            return 1
        }
    else
        printf_stderr 'No fsa file selected.\n'
    fi

    mspec_release "$tmpvar" "$mspec" || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    return 0
}

#
# inspect_fsa_directory_unfiltered <error-trace out> <rspec>
#
inspect_fsa_directory_unfiltered() {
    local rspec="$2"

    local tmpvar="$(make_tmpvar)"

    inspect_fsa_directory_with_filter "$tmpvar" "$rspec" is_fsa_file || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    return 0
}

#
# archive_file_system <fsa-file_rspec | error-trace out> <file-system> <top-level-rspec>
#
archive_file_system() {
    local file_system="$2"
    local top_level_rspec="$3"

    local sentinel="fsa-archive"
    local rspec="$(rspec_extend_path "$top_level_rspec" "$sentinel")"
    local tmpvar="$(make_tmpvar)"

    create_fsa_file "$tmpvar" "$file_system" "$rspec" || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    copy_out_result "$1" "${!tmpvar}"
    return 0
}
