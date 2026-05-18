# shellcheck shell=bash
# shellcheck disable=SC2155
# shellcheck disable=SC2181

# execution guard
[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
    echo "$(basename "${BASH_SOURCE[0]}") must be sourced." >&2
    exit 1
}

# re-source guard
[[ ${_MOUNT_SPEC_LIB_INCLUDED:-} ]] && return
readonly _MOUNT_SPEC_LIB_INCLUDED=1

if [[ -z ${BASH_LIBS_DIR:-} ]]; then
    readonly BASH_LIBS_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
fi

# shellcheck source=./result_type_lib.bash
source "$BASH_LIBS_DIR/result_type_lib.bash"
(($? == 0)) || return 1

# shellcheck source=./resource_spec_lib.bash
source "$BASH_LIBS_DIR/resource_spec_lib.bash"
(($? == 0)) || return 1

# shellcheck source=./file_system_lib.bash
source "$BASH_LIBS_DIR/file_system_lib.bash"
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
    printf '%s/%s\n' \
        "$(mspec_path "$1")" \
        "$2"
}

#
# _mspec_umount_wrapper <error-message out> <mount-point>
#
_mspec_umount_wrapper() {
    local mount_point="$2"
    local tmpvar="$(make_tmpvar)"

    capture_output "$tmpvar" umount "$mount_point" || {
        sleep 1

        capture_output "$tmpvar" umount "$mount_point" || {
            originate_error "$1" \
                'Failed to unmount mount point "%s": %s' \
                "$mount_point" \
                "${!tmpvar}"
            return 1
        }
    }

    return 0
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
        _mspec_umount_wrapper "$tmpvar" "$mount_point" || {
            forward_error "$1" "${!tmpvar}"
            return 1
        }
        return 0
        ;;

    umount-rmdir)
        _mspec_umount_wrapper "$tmpvar" "$mount_point" || {
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
# _mspec_get_device_for_rspec <device | error-message out> <rspec>
#
_mspec_get_device_for_rspec() {
    local rspec="$2"
    local type="$(rspec_type "$rspec")"

    case "$type" in
    label)
        local tmpvar="$(make_tmpvar)"

        get_device_for_label "$tmpvar" \
            "$(rspec_label "$rspec")" || {
            forward_error "$1" "${!tmpvar}"
            return 1
        }

        copy_out_result "$1" "${!tmpvar}"
        return 0
        ;;

    nfs)
        local host="$(rspec_host "$rspec")"
        local share="$(rspec_share "$rspec")"

        # Current NFS locator policy: shares are exported under /nfs.
        copy_out_result "$1" "$host:/nfs/$share"
        return 0
        ;;

    *)
        originate_error "$1" \
            'There is no mount device for resource "%s" of type "%s".' \
            "$(rspec_format "$rspec")" \
            "$type"
        return 1
        ;;

    esac
}

#
# _mspec_mount_wrapper <error-message out> <source> <target> [<mount-options>]
#
_mspec_mount_wrapper() {
    local mount_output
    local mount_cmd=(mount)

    if [[ -n ${4:-} ]]; then
        mount_cmd+=(--options "$4")
    fi

    mount_cmd+=("$2" "$3")

    capture_output mount_output "${mount_cmd[@]}" || {
        originate_error "$1" \
            'Failed to mount source "%s" at target "%s": %s' \
            "$2" \
            "$3" \
            "$mount_output"
        return 1
    }

    return 0
}

#
# _mspec_mount_rspec <mspec | error-message out> <cleanup-action> <rspec> <mount-point> [<mount-options>]
#
_mspec_mount_rspec() {
    local cleanup_action="$2"
    local rspec="$3"
    local mount_point="$4"
    local tmpvar="$(make_tmpvar)"

    if [[ "$(rspec_type "$rspec")" == local ]]; then
        _mspec_make "$tmpvar" \
            "$(rspec_path "$rspec")" \
            '' \
            none

        copy_out_result "$1" "${!tmpvar}"
        return 0
    fi

    local device

    _mspec_get_device_for_rspec "$tmpvar" "$rspec" || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    device="${!tmpvar}"

    _mspec_mount_wrapper "$tmpvar" "$device" "$mount_point" "${5:-}" || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    local required_directory="$mount_point$(rspec_path "$rspec")"

    [[ -d "$required_directory" ]] || {
        local error_message

        printf -v error_message \
            'Required directory for resource "%s" does not exist.' \
            "$(rspec_format "$rspec")"

        _mspec_umount_wrapper "$tmpvar" "$mount_point" || {
            originate_error "$1" \
                '%s Also failed to unmount mount point "%s": %s' \
                "$error_message" \
                "$mount_point" \
                "${!tmpvar}"

            return 1
        }

        originate_error "$1" '%s' "$error_message"
        return 1
    }

    _mspec_make "$tmpvar" \
        "$required_directory" \
        "$mount_point" \
        "$cleanup_action"

    copy_out_result "$1" "${!tmpvar}"
    return 0
}

#
# mspec_mount_rspec <mspec | error-message out> <rspec> <mount-point> [<mount-options>]
#
mspec_mount_rspec() {
    local rspec="$2"
    local mount_point="$3"
    local tmpvar="$(make_tmpvar)"

    _mspec_mount_rspec "$tmpvar" umount "$rspec" "$mount_point" "${4:-}" || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    copy_out_result "$1" "${!tmpvar}"
    return 0
}

#
# mspec_temp_mount_rspec <mspec | error-message out> <rspec> [<mount-options>]
#
mspec_temp_mount_rspec() {
    local rspec="$2"
    local tmpvar="$(make_tmpvar)"

    if [[ "$(rspec_type "$rspec")" == local ]]; then
        _mspec_mount_rspec "$tmpvar" none "$rspec" '' "${3:-}" || {
            forward_error "$1" "${!tmpvar}"
            return 1
        }

        copy_out_result "$1" "${!tmpvar}"
        return 0
    fi

    make_tmpdir "$tmpvar" || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    local tmpdir="${!tmpvar}"

    _mspec_mount_rspec "$tmpvar" umount-rmdir "$rspec" "$tmpdir" "${3:-}" || {
        forward_error "$1" "${!tmpvar}"
        rmdir "$tmpdir"
        return 1
    }

    copy_out_result "$1" "${!tmpvar}"
    return 0
}
