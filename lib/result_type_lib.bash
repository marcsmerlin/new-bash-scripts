# shellcheck shell=bash

# execution guard
[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
    echo "$(basename "${BASH_SOURCE[0]}") must be sourced." >&2
    exit 1
}

# re-source guard
[[ ${_RESULT_TYPE_LIB_INCLUDED:-} ]] && return 0
readonly _RESULT_TYPE_LIB_INCLUDED=1

#
# make_tmpvar (invoked via shell substitution)
#
make_tmpvar() {
    printf 'tmpvar_%s' "${FUNCNAME[1]}"
}

#
# clear_var <var-name>
#
clear_var() {
    printf -v "$1" ''
}

#
# copy_out_result <result> <value>
#
copy_out_result() {
    printf -v "$1" '%s' "$2"
}

#
# originate_error <error-trace-var> <format-string> [args...]
#
# Create a new originating error message in <error-trace-var>, formatted as:
#
#   <caller-function>: <formatted-message>
#
originate_error() {
    local current

    # shellcheck disable=SC2059
    printf -v current "${@:2}"
    printf -v "$1" '%s: %s' "${FUNCNAME[1]}" "$current"
}

#
# forward_error <error-trace-var> <child-error-trace>
#
# Forward an existing child error trace into <error-trace-var>, appending only
# the caller's function name as a new trace frame:
#
#   <child-error-trace>
#   <caller-function>:
#
# If <child-error-trace> is empty, create a single frame containing only the
# caller's function name.
#
forward_error() {
    if [[ -n $2 ]]; then
        printf -v "$1" '%s\n%s:' "$2" "${FUNCNAME[1]}"
    else
        printf -v "$1" '%s:' "${FUNCNAME[1]}"
    fi
}

#
# capture_output <output> <command-to-execute>
#
capture_output() {
    local output
    local rc

    output="$("${@:2}" 2>&1)"
    rc="$?"

    printf -v "$1" '%s' "$output"
    return "$rc"
}

#
# print_error_trace <error-trace>
#
print_error_trace() {
    printf '%s\n' "$1" >&2
}
