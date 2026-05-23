# shellcheck shell=bash
# shellcheck disable=SC2155 # Declare and assign separately to avoid masking return values.
# shellcheck disable=SC2181 # Check exit code directly with e.g. `if mycmd;`, not indirectly with `$?`.

# re-source guard
[[ ${_sync_lib_included:-} ]] && return 0

if [[ -z ${BASH_LIBS_DIR:-} ]]; then
    readonly BASH_LIBS_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
fi

# shellcheck source=./system_lib.bash
source "$BASH_LIBS_DIR/system_lib.bash" || return 1

readonly _sync_lib_deps=(rsync)
verify_script_dependencies "${_sync_lib_deps[@]}" || return 1
readonly _sync_lib_included=1

# shellcheck source=./result_type_lib.bash
source "$BASH_LIBS_DIR/result_type_lib.bash"
(($? == 0)) || return 1

# shellcheck source=../lib/result_type_lib.bash
source "$BASH_LIBS_DIR/result_type_lib.bash"

# shellcheck source=./rspec_lib.bash
source "$BASH_LIBS_DIR/rspec_lib.bash"
(($? == 0)) || return 1

# shellcheck source=./mspec_lib.bash
source "$BASH_LIBS_DIR/mspec_lib.bash"
(($? == 0)) || return 1

# shellcheck source=./file_system_lib.bash
source "$BASH_LIBS_DIR/file_system_lib.bash"
(($? == 0)) || return 1

#
# _rsync_archive_wrapper <error-trace out> <source-directory> <archive-directory> <is_dry_run>
#
_rsync_archive_wrapper() {
    local source="$2"
    local archive="$3"
    local is_dry_run="$4"

    local rsync_opts=(
        --archive
        --no-owner
        --no-group
        --human-readable
        --delete
        --info=progress2
        --info=STATS
        --delete-excluded
    )

    [[ -d "$source" && -r "$source" && -x "$source" ]] || {
        originate_error "$1" \
            '"%s" is either not a directory or is not readable.' \
            "$source"
        return 1
    }

    (( is_dry_run == 0 )) && rsync_opts+=(--dry-run)

    local rsync_exclude="$source/.rsync-exclude"

    [[ -f "$rsync_exclude" ]] && rsync_opts+=(--exclude-from="$rsync_exclude")

    rsync "${rsync_opts[@]}" "$source" "$archive" || {
        originate_error "$1" 'rsync failure from %s to %s' "$source" "$archive"
        return 1
    }

    return 0
}

#
# sync_source_directory_to_archive_directory <error-trace out> <source-directory> <archive-directory> <is-dry-run>
#
sync_source_directory_to_archive_directory() {
    local source="$2"
    local archive="$3"
    local is_dry_run="$4"

    _rsync_archive_wrapper "$1" "$source" "$archive" "$is_dry_run" || return 1

    return 0
}

#
# sync_source_directory_to_archive_rspec <error-trace out> <source-directory> <archive-rspec> <is-dry-run>#
sync_source_directory_to_archive_rspec() {
    local source="$2"
    local rspec="$3"
    local is_dry_run="$4"

    local tmpvar="$(make_tmpvar)"

    mspec_temp_mount_rspec "$tmpvar" "$rspec" || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    local mspec="${!tmpvar}"
    local archive="$(mspec_path "$mspec")"

    sync_source_directory_to_archive_directory "$tmpvar" "$source" "$archive" "$is_dry_run" || {
        defer_forward_error "$1" \
            "${!tmpvar}" \
            mspec_release "$mspec"

        return 1
    }

    mspec_release "$tmpvar" "$mspec" || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    return 0
}

#
# sync_user_directory_to_archive_rspec <error-trace out> <user> <directory> <rspec> <is_dry_run>
#
sync_user_directory_to_archive_rspec() {
    local user="$2"
    local directory="$3"
    local rspec="$4"
    local is_dry_run="$5"
    
    local tmpvar="$(make_tmpvar)"

    get_user_home "$tmpvar" "$user" || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    local home="${!tmpvar}"
    local source="$home/$directory"
    local archive_rspec="$(rspec_extend_path "$rspec" "$user")"
    
    sync_source_directory_to_archive_rspec "$tmpvar" "$source" "$archive_rspec" "$is_dry_run" || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    return 0
}
