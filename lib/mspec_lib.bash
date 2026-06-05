# shellcheck shell=bash
# shellcheck disable=SC2155
# shellcheck disable=SC2181

# re-source guard
[[ ${_mspec_lib_included:-} ]] && return 0

if [[ -z ${BASH_LIBS_DIR:-} ]]; then
    readonly BASH_LIBS_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
fi

# shellcheck source=./system_lib.bash
source "$BASH_LIBS_DIR/system_lib.bash" || return 1

readonly _mspec_lib_deps=(mount.cifs)
verify_script_dependencies "${_mspec_lib_deps[@]}" || return 1
readonly _mspec_lib_included=1

# shellcheck source=./result_type_lib.bash
source "$BASH_LIBS_DIR/result_type_lib.bash"
(($? == 0)) || return 1

# shellcheck source=./rspec_lib.bash
source "$BASH_LIBS_DIR/rspec_lib.bash"
(($? == 0)) || return 1

# shellcheck source=./file_system_lib.bash
source "$BASH_LIBS_DIR/file_system_lib.bash"
(($? == 0)) || return 1

# shellcheck source=./sudo_lib.bash
source "$BASH_LIBS_DIR/sudo_lib.bash"
(($? == 0)) || return 1

# mspec fields:
#
#   path
#   mount-point
#   cleanup-action
#
# cleanup-action values:
#
#   none
#   umount
#   umount-rmdir
#

#
# _mspec_encode <path> <mount-point> <cleanup-action>
#
_mspec_encode() {
    printf '%q %q %q' "$1" "$2" "$3"
}

_mspec_split() {
    local encoded="$1"

    local path_out="$2"
    local mount_point_out="$3"
    local cleanup_action_out="$4"

    eval "set -- $encoded"

    printf -v "$path_out" '%s' "$1"
    printf -v "$mount_point_out" '%s' "$2"
    printf -v "$cleanup_action_out" '%s' "$3"
}

#
# _mspec_make <mspec out> <path> <mount-point> <cleanup-action>
#
_mspec_make() {
    printf -v "$1" '%s' "$(_mspec_encode "$2" "$3" "$4")"
}

#
# mspec_path <mspec>
#
mspec_path() {
    local path
    local mount_point
    local cleanup_action

    _mspec_split "$1" path mount_point cleanup_action

    printf '%s\n' "$path"
}

#
# _mspec_mount_point <mspec>
#
_mspec_mount_point() {
    local path
    local mount_point
    local cleanup_action

    _mspec_split "$1" path mount_point cleanup_action

    printf '%s\n' "$mount_point"
}

#
# _mspec_cleanup_action <mspec>
#
_mspec_cleanup_action() {
    local path
    local mount_point
    local cleanup_action

    _mspec_split "$1" path mount_point cleanup_action

    printf '%s\n' "$cleanup_action"
}

#
# mspec_format <mspec>
#
mspec_format() {
    mspec_path "$1"
}

#
# mspec_file_path <mspec> <leaf-name>
#
mspec_file_path() {
    local leaf_name="${2#/}"

    printf '%s/%s\n' \
        "$(mspec_path "$1")" \
        "$leaf_name"
}

#
# mspec_release <error-message out> <mspec>
#
# Typical use: mspec_release "$1" "$mspec" || return "$?"
#
mspec_release() {
    local path
    local mount_point
    local cleanup_action
    local tmpvar="$(make_tmpvar)"

    _mspec_split "$2" path mount_point cleanup_action

    case "$cleanup_action" in
    none)
        return 0
        ;;

    umount)
        sudo_unmount "$tmpvar" "$mount_point" || {
            forward_error "$1" "${!tmpvar}"
            return 1
        }
        return 0
        ;;

    umount-rmdir)
        sudo_unmount "$tmpvar" "$mount_point" || {
            forward_error "$1" "${!tmpvar}"
            return 1
        }

        rmdir "$mount_point" || {
            originate_error "$1" \
                'Failed to remove temporary mount point directory "%s".' \
                "$mount_point"
            return 1
        }

        return 0
        ;;

    *)
        originate_error "$1" \
            'Unknown mspec cleanup action "%s".' \
            "$cleanup_action"
        return 1
        ;;
    esac
}

#
# _mspec_mount_local <mspec> <rspec> <directory-policy>
#
_mspec_mount_local() {
    local rspec="$2"
    local directory_policy

    local path="$(rspec_path "$rspec")"
    local tmpvar="$(make_tmpvar)"

    if [[ ! -d "$path" ]]; then
        request_confirmation "Create directory ${path}? " || {
            originate_error "$1" \
            'Aborting: directory "%s" is required to proceed.' \
            "$path"

            return 1
        }

        sudo_make_directory "$tmpvar" "$path" || {
            forward_error "$1" "${!tmpvar}"
            return 1
        }
    fi

    _mspec_make "$tmpvar" \
        "$path" \
        '' \
        none

    copy_out_result "$1" "${!tmpvar}"
    return 0
}

#
# _mspec_require_directory <error-trace out> <rspec> <directory-policy> <mount_point>
#
_mspec_require_directory() {
    local rspec="$2"
    local directory_policy="$3"
    local mount_point="$4"

    local path="$(rspec_path "$rspec")"
    local required_directory="$mount_point$path"

    [[ -d "$required_directory" ]] && return 0

    local formatted_rspec="$(rspec_format "$rspec")"

    case "$directory_policy" in
    require-existing)
        originate_error "$1" \
            'Directory "%s" is required to proceed.' \
            "$formatted_rspec"
        return 1
        ;;

    create-if-missing)
        request_confirmation "Create directory ${formatted_rspec}? " || {
            originate_error "$1" \
                'Aborting: directory "%s" is required to proceed.' \
                "$formatted_rspec"
            return 1
        }

        local tmpvar="$(make_tmpvar)"

        sudo_make_directory "$tmpvar" "$required_directory" || {
            forward_error "$1" "${!tmpvar}"
            return 1
        }

        return 0
        ;;

    *)
        originate_error "$1" \
            'Unknown directory policy "%s".' \
            "$directory_policy"
        return 1
        ;;
    esac
}

#
# _mspec_mount_label <mspec | error-trace out> <rspec> <directoy-policy> <mount-point> <cleanup-action>
#
_mspec_mount_label() {
    local rspec="$2"
    local directory_policy="$3"
    local mount_point="$4"
    local cleanup_action="$5"

    local label="$(rspec_label "$rspec")"
    local tmpvar="$(make_tmpvar)"

    sudo_mount_label "$tmpvar" "$label" "$mount_point" || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    _mspec_require_directory "$tmpvar" "$rspec" "$directory_policy" "$mount_point" || {
        defer_forward_error "$1" \
            "${!tmpvar}" \
            sudo_unmount "$mount_point"
        return 1
    }

    local path="$(rspec_path "$rspec")"

    _mspec_make "$tmpvar" \
        "$mount_point$path" \
        "$mount_point" \
        "$cleanup_action"

    copy_out_result "$1" "${!tmpvar}"

    return 0
}

#
# _mspec_mount_cifs <mspec | error-trace out> <rspec> <directory_policy> <mount-point> <cleanup-action>
#
_mspec_mount_cifs() {
    local rspec="$2"
    local directory_policy="$3"
    local mount_point="$4"
    local cleanup_action="$5"

    local sudo_user="$(get_sudo_user)"
    local tmpvar="$(make_tmpvar)"

    get_user_home "$tmpvar" "$sudo_user" || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    local host="$(rspec_host "$rspec")"
    local credentials_file="${!tmpvar}/.config/smb/credentials-$host"

    [[ -f "$credentials_file" && -r "$credentials_file" ]] || {
        originate_error "$1" \
            'No readable CIFS credentials file found for user "%s": "%s"' \
            "$sudo_user" \
            "$credentials_file"
        return 1
    }

    local service="//"$host/"$(rspec_share "$rspec")"
    local uid="$(get_sudo_uid)"
    local gid="$(get_sudo_gid)"
    local credentials="$credentials_file,uid=$uid,gid=$gid"

    sudo_mount_cifs "$tmpvar" "$service" "$mount_point" "$credentials" || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    _mspec_require_directory "$tmpvar" "$rspec" "$directory_policy" "$mount_point" || {
        defer_forward_error "$1" \
            "${!tmpvar}" \
            sudo_unmount "$mount_point"
        return 1
    }

    local path="$(rspec_path "$rspec")"

    _mspec_make "$tmpvar" \
        "$mount_point$path" \
        "$mount_point" \
        "$cleanup_action"

    copy_out_result "$1" "${!tmpvar}"

    return 0
}

#
# _mspec_mount_rspec <mspec | error-trace out> <rspec> <directory-policy> <mount-point> <cleanup-action>
#
_mspec_mount_rspec() {
    local rspec="$2"
    local directory_policy="$3"
    local mount_point="$4"
    local cleanup_action="$5"

    local type="$(rspec_type "$rspec")"
    local tmpvar="$(make_tmpvar)"

    case "$type" in
    local)
        _mspec_mount_local "$tmpvar" "$rspec" "$directory_policy" || {
            forward_error "$1" "${!tmpvar}"
            return 1
        }
        ;;

    label)
        _mspec_mount_label "$tmpvar" "$rspec" "$directory_policy" "$mount_point" "$cleanup_action" || {
            forward_error "$1" "${!tmpvar}"
            return 1
        }
        ;;

    cifs)
        _mspec_mount_cifs "$tmpvar" "$rspec" "$directory_policy" "$mount_point" "$cleanup_action" || {
            forward_error "$1" "${!tmpvar}"
            return 1
        }
        ;;

    *)
        originate_error "$1" \
            'Unknown rspec type "%s".' \
            "$type"
        return 1
        ;;
    esac

    copy_out_result "$1" "${!tmpvar}"
    return 0
}

#
# mspec_mount_rspec <mspec | error-trace out> <rspec> <directory-policy ><mount-point>
#
mspec_mount_rspec() {
    local rspec="$2"
    local directory_policy="$3"
    local mount_point="$4"

    local tmpvar="$(make_tmpvar)"

    _mspec_mount_rspec "$tmpvar" "$rspec" "$directory_policy" "$mount_point" 'umount' || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    copy_out_result "$1" "${!tmpvar}"
    return 0
}

#
# mspec_temp_mount_rspec <mspec | error-trace out> <rspec> <directory-policy>
#
mspec_temp_mount_rspec() {
    local rspec="$2"
    local directory_policy="$3"

    local type="$(rspec_type "$rspec")"
    local tmpvar="$(make_tmpvar)"

    if [[ "$type" == local ]]; then
        _mspec_mount_local "$tmpvar" "$rspec" "$directory_policy" || {
            forward_error "$1" "${!tmpvar}"
            return 1
        }
    else
        make_tmpdir "$tmpvar" || {
            forward_error "$1" "${!tmpvar}"
            return 1
        }

        local tmpdir="${!tmpvar}"

        _mspec_mount_rspec "$tmpvar" "$rspec" "$directory_policy" "$tmpdir" umount-rmdir || {
            defer_forward_error "$1" \
                "${!tmpvar}" \
                rmdir_wrapper "$tmpdir"
            return 1
        }
    fi

    copy_out_result "$1" "${!tmpvar}"
    return 0
}
