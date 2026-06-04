# shellcheck shell=bash
# shellcheck disable=SC2155 # Declare and assign separately to avoid masking return values.
# shellcheck disable=SC2181 # Check exit code directly with e.g. `if mycmd;`, not indirectly with `$?`.

[[ ${_sudo_lib_included:-} ]] && return 0
readonly _sudo_lib_include=1

if [[ -z ${BASH_LIBS_DIR:-} ]]; then
    readonly BASH_LIBS_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
fi

# shellcheck source=./result_type_lib.bash
source "$BASH_LIBS_DIR/result_type_lib.bash"
(($? == 0)) || return 1

#
# get_sudo_user
#
get_sudo_user() {
    printf '%s\n' "${SUDO_USER:-$USER}"
}

#
# get_sudo_uid
#
get_sudo_uid() {
    printf '%s\n' "${SUDO_UID:-$(id -u)}"
}

#
# get_sudo_gid
#
get_sudo_gid() {
    printf '%s\n' "${SUDO_GID:-$(id -g)}"
}

sudo_context_capture() {
    local output
    local rc

    output="$(sudo -v 2>&1)"
    rc="$?"

    ((rc == 0)) || {
        printf -v "$1" '%s' "$output"
        return "$rc"
    }

    output="$(sudo -n "${@:2}" 2>&1)"
    rc="$?"

    printf -v "$1" '%s' "$output"
    return "$rc"
}

#
# sudo_unmount <error-trace out> <mount-point>
#
sudo_unmount() {
    local mount_point="$2"

    local tmpvar="$(make_tmpvar)"
    local rc

    sudo_context_capture "$tmpvar" \
        umount "$mount_point"

    rc="$?"

    ((rc == 0)) || {
        originate_error "$1" \
            'Failed to unmount mount point "%s": %s' \
            "$mount_point" \
            "${!tmpvar}"
        return 1
    }

    return 0
}

#
# sudo_mount_label <error-trace out> <label> <mount-point>
#
sudo_mount_label() {
    local label="$2"
    local mount_point="$3"

    local tmpvar="$(make_tmpvar)"

    get_device_for_label "$tmpvar" "$label" || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    local device="${!tmpvar}"
    local rc

    sudo_context_capture "$tmpvar" \
        mount "$device" "$mount_point"

    rc="$?"

    ((rc == 0)) || {
        originate_error "$1" \
            'Failed to mount label ("%s") on mount point "%s": %s' \
            "$label" \
            "$mount_point" \
            "${!tmpvar}"
        return 1
    }

    return 0
}

#
# sudo_mount_cifs <error-trace out> <service> <mount-point> <credentials>
#
sudo_mount_cifs() {
    local service="$2"
    local mount_point="$3"
    local credentials="$4"

    local tmpvar="$(make_tmpvar)"
    local rc

    sudo_context_capture "$tmpvar" \
        mount.cifs "$service" "$mount_point" -o "credentials=$credentials"

    rc="$?"

    ((rc == 0)) || {
        originate_error "$1" \
            'Failed to mount service "%s" on mount point "%s" using credentials "%s": %s' \
            "$service" \
            "$mount_point" \
            "$credentials" \
            "${!tmpvar}"
        return 1
    }

    return 0
}

#
# sudo_make_directory <error-trace out> <path>
#
sudo_make_directory() {
    local path="$2"

    local tmpvar="$(make_tmpvar)"
    local rc

    sudo_context_capture "$tmpvar" \
        install -d "$path" -o "$(get_sudo_uid)" -g "$(get_sudo_gid)"

    rc="$?"

    ((rc == 0)) || {
        originate_error "$1" \
            'Failed to create path "%s": %s' \
            "$path" \
            "${!tmpvar}"
        return 1
    }

    return 0
}

#
# sudo_chown <error-trace out> <file>
#
sudo_chown() {
    local file="$2"

    local tmpvar="$(make_tmpvar)"
    local rc

    sudo_context_capture "$tmpvar" \
        chown "$(get_sudo_uid):$(get_sudo_gid)" "$file"

    rc="$?"

    ((rc == 0)) || {
        originate_error "$1" \
            'Failed to change ownership "%s": %s' \
            "$path" \
            "${!tmpvar}"
        return 1
    }

    return 0
}
