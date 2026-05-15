# shellcheck shell=bash
# shellcheck disable=SC2155
# shellcheck disable=SC2181

# execution guard
[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
    echo "$(basename "${BASH_SOURCE[0]}") must be sourced." >&2
    exit 1
}

# re-source guard
[[ ${_MOUNT_LIB_INCLUDED:-} ]] && return
readonly _MOUNT_LIB_INCLUDED=1

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
#   mount-point
#   root
#   temporary-flag
#   resource-spec
#
# temporary-flag values:
#
#   ''
#   temporary
#

# _encode_mount_spec <mount-point> <root> <temporary-flag> <resource-spec>
#
_encode_mount_spec() {
    printf '%q %q %q %q' "$1" "$2" "$3" "$4"
}

# _build_mount_spec <mount-spec | error-message out> <mount-point> <resource-spec> <temporary-flag>
#
_build_mount_spec() {
    local mount_point="$2"
    local resource_spec="$3"
    local temporary_flag="$4"
    local resource_type
    local resource_root
    local root

    resource_type="$(get_resource_spec_type "$resource_spec")"

    [[ "$resource_type" != local ]] || {
        originate_error "$1" \
            'Cannot build mount_spec from local resource "%s".' \
            "$(format_resource_spec_for_display "$resource_spec")"
        return 1
    }

    resource_root="$(get_resource_spec_root "$resource_spec")"

    case "$resource_root" in
    /)
        root="$mount_point"
        ;;
    /*)
        root="$mount_point$resource_root"
        ;;
    *)
        root="$mount_point/$resource_root"
        ;;
    esac

    copy_out_result "$1" \
        "$(_encode_mount_spec "$mount_point" "$root" "$temporary_flag" "$resource_spec")"

    return 0
}

# build_mount_spec <mount-spec | error-message out> <mount-point> <resource-spec>
#
build_mount_spec() {
    _build_mount_spec "$1" "$2" "$3" '' || {
        forward_error "$1" "$1"
        return 1
    }

    return 0
}

# build_temp_mount_spec <mount-spec | error-message out> <mount-point> <resource-spec>
#
build_temp_mount_spec() {
    _build_mount_spec "$1" "$2" "$3" temporary || {
        forward_error "$1" "$1"
        return 1
    }

    return 0
}

#
# _split_mount_spec <mount-spec> <mount-point out> <root out>
#
_split_mount_spec() {
    local tmpvar="$(make_tmpvar)"
    local mp
    local root

    printf -v "$tmpvar" '%s %s' "$2" "$3"

    eval "set -- $1"

    mp="$1"
    root="$2"

    eval "set -- ${!tmpvar}"

    printf -v "$1" '%s' "$mp"
    printf -v "$2" '%s' "$root"
}

# get_mount_spec_mount_point <mount-spec>
#
get_mount_spec_mount_point() {
    eval "set -- $1"

    printf '%s\n' "$1"
}

# get_mount_spec_root <mount-spec>
#
get_mount_spec_root() {
    eval "set -- $1"

    printf '%s\n' "$2"
}

# is_temp_mount_spec <mount-spec>
#
is_temp_mount_spec() {
    eval "set -- $1"

    [[ "$3" == temporary ]]
}

#
# format_mount_spec_for_display <mount-spec>
#
format_mount_spec_for_display() {
    format_resource_spec_for_display \
        "$(_get_mount_spec_resource_spec "$1")"
}

#
# _get_mount_spec_resource_spec <mount-spec>
#
_get_mount_spec_resource_spec() {
    eval "set -- $1"

    printf '%s\n' "$4"
}

#
# get_mount_spec_working_root <mount-spec>
#
get_mount_spec_working_root() {
    eval "set -- $1"

    printf '%s\n' "$2"
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
    local mount_point="$(get_mount_spec_mount_point "$2")"
    local tmpvar="$(make_tmpvar)"

    umount_wrapper "$tmpvar" "$mount_point" || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    if is_temp_mount_spec "$2"; then
        rmdir "$mount_point" || {
            originate_error "$1" \
                'Failed to remove temporary mount point directory "%s".' \
                "$mount_point"
            return 1
        }
    fi

    return 0
}

#
# get_device_for_resource_spec <device | error-message out> <resource-spec>
#
get_device_for_resource_spec() {
    local resource_spec="$2"
    local type="$(get_resource_spec_type "$resource_spec")"

    case "$type" in
    label)
        local tmpvar="$(make_tmpvar)"

        if ! get_device_for_label "$tmpvar" \
            "$(get_resource_spec_label "$resource_spec")"; then
            forward_error "$1" "${!tmpvar}"
            return 1
        fi

        copy_out_result "$1" "${!tmpvar}"
        return 0
        ;;

    nfs)
        local host="$(get_resource_spec_host "$resource_spec")"
        local share="$(get_resource_spec_share "$resource_spec")"

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
# mount_resource_spec <mount-spec | error-message out> <resource-spec> <mount-point> [<mount-options>]
#
mount_resource_spec() {
    local resource_spec="$2"
    local mount_point="$3"
    local tmpvar="$(make_tmpvar)"
    local device

    get_device_for_resource_spec "$tmpvar" "$resource_spec" || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    device="${!tmpvar}"

    mount_wrapper "$tmpvar" "$device" "$mount_point" "${4:-}" || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    local required_directory="$mount_point$(get_resource_spec_root "$resource_spec")"

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

    build_mount_spec "$tmpvar" "$mount_point" "$resource_spec" || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    copy_out_result "$1" "${!tmpvar}"
    return 0
}
