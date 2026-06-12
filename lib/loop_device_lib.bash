# shellcheck shell=bash
# shellcheck disable=SC2155

# execution guard
[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
    echo "$(basename "${BASH_SOURCE[0]}") must be sourced." >&2
    exit 1
}

# re-source guard
[[ ${_loop_device_lib_included:-} ]] && return
readonly _loop_device_lib_included=1

if [[ -z ${BASH_LIBS_DIR:-} ]]; then
    readonly BASH_LIBS_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
fi

# shellcheck source=./result_type_lib.bash
source "$BASH_LIBS_DIR/result_type_lib.bash"

#
# detach_loop_device <loopdev>
#
detach_loop_device() {
    losetup --detach "$1"
    return 0
}

#
# attach_loop_device <loop-device | error-trace out> <file-name>
#
attach_loop_device() {
    local file_name="$2"
    local loopdev

    loopdev="$(losetup --find --show "$file_name")" || {
        originate_error "$1" \
            'Unable to attach loop device to "%s".\n' \
            "$file_name"
        return 1
    }

    copy_out_result "$1" "$loopdev"
    return 0
}

#
# create_loop_image_file <loop-device | error-trace out-device> <file-name> <file-size>
#
create_loop_image_file() {
    local file_name="$2"
    local file_size="$3"

    rm -f "$file_name"
    truncate -s "$file_size" "$file_name" || {
        originate_error "$1" \
            'Unable to create image file "%s".\n' \
            "$file_name" \
            "$file_size"
        return 1
    }

    local tmpvar="$(make_tmpvar)"

    attach_loop_device "$tmpvar" "$file_name" || {
        forward_error "$1" "${!tmpvar}"
        rm -f "$file_name"
        return 1
    } 

    copy_out_result "$1" "${!tmpvar}"
    return 0
}
