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

# mount_spec fields:
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
# _encode_mount_spec <path> <mount-point> <cleanup-action>
#
_encode_mount_spec() {
    printf '%q %q %q' "$1" "$2" "$3"
}

_split_mount_spec() {
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
# _make_mount_spec <mount-spec out> <path> <mount-point> <cleanup-action>
#
_make_mount_spec() {
    printf -v "$1" '%s' "$(_encode_mount_spec "$2" "$3" "$4")"
}

#
# mount_spec_path <mount-spec>
#
mount_spec_path() {
    local path
    local mount_point
    local cleanup_action

    _split_mount_spec "$1" path mount_point cleanup_action

    printf '%s\n' "$path"
}

#
# _mount_spec_mount_point <mount-spec>
#
_mount_spec_mount_point() {
    local path
    local mount_point
    local cleanup_action

    _split_mount_spec "$1" path mount_point cleanup_action

    printf '%s\n' "$mount_point"
}

#
# _mount_spec_cleanup_action <mount-spec>
#
_mount_spec_cleanup_action() {
    local path
    local mount_point
    local cleanup_action

    _split_mount_spec "$1" path mount_point cleanup_action

    printf '%s\n' "$cleanup_action"
}

#
# format_mount_spec_for_display <mount-spec>
#
format_mount_spec_for_display() {
    mount_spec_path "$1"
}

#
# mount_spec_working_directory <mount-spec>
#
mount_spec_working_directory() {
    mount_spec_path "$1"
}

#
# mount_spec_file_path <mount-spec> <leaf-name>
#
mount_spec_file_path() {
    printf '%s/%s\n' \
        "$(mount_spec_path "$1")" \
        "$2"
}

#
# umount_wrapper <error-message out> <mount-point>
#
umount_wrapper() {
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
# release_mount_spec <error-message out> <mount-spec>
#
# Typical use: release_mount_spec "$1" "$mount_spec" || return "$?"
#
release_mount_spec() {
    local path
    local mount_point
    local cleanup_action
    local tmpvar="$(make_tmpvar)"

    _split_mount_spec "$2" path mount_point cleanup_action

    case "$cleanup_action" in
    none)
        return 0
        ;;

    umount)
        umount_wrapper "$tmpvar" "$mount_point" || {
            forward_error "$1" "${!tmpvar}"
            return 1
        }
        return 0
        ;;

    umount-rmdir)
        umount_wrapper "$tmpvar" "$mount_point" || {
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
            'Unknown mount_spec cleanup action "%s".' \
            "$cleanup_action"
        return 1
        ;;
    esac
}

#
# _get_device_for_resource_spec <device | error-message out> <resource-spec>
#
_get_device_for_resource_spec() {
    local resource_spec="$2"
    local type="$(resource_spec_type "$resource_spec")"

    case "$type" in
    label)
        local tmpvar="$(make_tmpvar)"

        get_device_for_label "$tmpvar" \
            "$(resource_spec_label "$resource_spec")" || {
            forward_error "$1" "${!tmpvar}"
            return 1
        }

        copy_out_result "$1" "${!tmpvar}"
        return 0
        ;;

    nfs)
        local host="$(resource_spec_host "$resource_spec")"
        local share="$(resource_spec_share "$resource_spec")"

        # Current NFS locator policy: shares are exported under /nfs.
        copy_out_result "$1" "$host:/nfs/$share"
        return 0
        ;;

    *)
        originate_error "$1" \
            'There is no mount device for resource "%s" of type "%s".' \
            "$(format_resource_spec_for_display "$resource_spec")" \
            "$type"
        return 1
        ;;

    esac
}

#
# mount_wrapper <error-message out> <source> <target> [<mount-options>]
#
mount_wrapper() {
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
# _mount_resource_spec <mount-spec | error-message out> <cleanup-action> <resource-spec> <mount-point> [<mount-options>]
#
_mount_resource_spec() {
    local cleanup_action="$2"
    local resource_spec="$3"
    local mount_point="$4"
    local tmpvar="$(make_tmpvar)"

    if [[ "$(resource_spec_type "$resource_spec")" == local ]]; then
        _make_mount_spec "$tmpvar" \
            "$(resource_spec_root "$resource_spec")" \
            '' \
            none

        copy_out_result "$1" "${!tmpvar}"
        return 0
    fi

    local device

    _get_device_for_resource_spec "$tmpvar" "$resource_spec" || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    device="${!tmpvar}"

    mount_wrapper "$tmpvar" "$device" "$mount_point" "${5:-}" || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    local required_directory="$mount_point$(resource_spec_root "$resource_spec")"

    [[ -d "$required_directory" ]] || {
        local error_message

        printf -v error_message \
            'Required directory for resource "%s" does not exist.' \
            "$(format_resource_spec_for_display "$resource_spec")"

        umount_wrapper "$tmpvar" "$mount_point" || {
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

    _make_mount_spec "$tmpvar" \
        "$required_directory" \
        "$mount_point" \
        "$cleanup_action"

    copy_out_result "$1" "${!tmpvar}"
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
# mount_resource_spec <mount-spec | error-message out> <resource-spec> <mount-point> [<mount-options>]
#
mount_resource_spec() {
    local resource_spec="$2"
    local mount_point="$3"
    local tmpvar="$(make_tmpvar)"

    _mount_resource_spec "$tmpvar" umount "$resource_spec" "$mount_point" "${4:-}" || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    copy_out_result "$1" "${!tmpvar}"
    return 0
}

#
# temp_mount_resource_spec <mount-spec | error-message out> <resource-spec> [<mount-options>]
#
temp_mount_resource_spec() {
    local resource_spec="$2"
    local tmpvar="$(make_tmpvar)"

    if [[ "$(resource_spec_type "$resource_spec")" == local ]]; then
        _mount_resource_spec "$tmpvar" none "$resource_spec" '' "${3:-}" || {
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

    _mount_resource_spec "$tmpvar" umount-rmdir "$resource_spec" "$tmpdir" "${3:-}" || {
        forward_error "$1" "${!tmpvar}"
        rmdir "$tmpdir"
        return 1
    }

    copy_out_result "$1" "${!tmpvar}"
    return 0
}
