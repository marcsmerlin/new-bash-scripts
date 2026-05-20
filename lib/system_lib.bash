# shellcheck shell=bash
# shellcheck disable=SC2155 # Declare and assign separately to avoid masking return values.

# execution guard
[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
    echo "$(basename "${BASH_SOURCE[0]}") must be sourced." >&2
    exit 1
}

# re-source guard
[[ ${_SYSTEM_LIB_INCLUDED:-} ]] && return 0
readonly _SYSTEM_LIB_INCLUDED=1

#
# trim_string <string>
#
trim_string() {
    local value="$1"

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    printf '%s\n' "$value"
}

#
# printf_stderr
#
# shellcheck disable=SC2059 # Don't use variables in the `printf` format string.
printf_stderr() {
    printf "$@" >&2
}

#
# send_notification <title> <message>
#
send_notification() {
    local title="$1"
    local message="$2"

    if ((EUID == 0)) && [[ -n "$SUDO_USER" ]]; then
        sudo -u "$SUDO_USER" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u "$SUDO_USER")/bus" \
            notify-send "$title" "$message"
    else
        notify-send "$title" "$message"
    fi
}

#
# has_command <command_name>
#
has_command() {
    command -v "$1" >/dev/null 2>&1
}

#
# verify_script_dependencies <command>...
#
verify_script_dependencies() {
    local command

    for command in "$@"; do
        if ! has_command "$command"; then
            printf_stderr \
                'The command "%s" is missing and must be installed in order to proceed.\n' \
                "$command"
            return 1
        fi
    done

    return 0
}

#
# verify_integer_input <input> <minimum> <maximum>
#
verify_integer_input() {
    local input="$1"
    local minimum="$2"
    local maximum="$3"

    [[ "$input" =~ ^[0-9]+$ ]] && ((input >= minimum)) && ((input <= maximum))
}

#
# read_integer_input <integer out> <prompt> <miniumum> <maximum>
#
read_integer_input() {
    local prompt="$2"
    local minimum="$3"
    local maximum="$4"

    local input
    read -rp "$prompt" input

    if ! verify_integer_input "$input" "$minimum" "$maximum"; then
        rc=1
    else
        printf -v "$1" '%d' "$input"
        rc=0
    fi

    return "$rc"
}

#
# request_confirmation <prompt>
#
request_confirmation() {
    local prompt="$1"

    local response

    read -rp "$prompt" response

    # normalize to lowercase
    response=${response,,}

    [[ "$response" == "y" || "$response" == "yes" ]]
}

