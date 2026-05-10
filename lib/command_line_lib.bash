# shellcheck shell=bash
# shellcheck disable=SC2155 # Declare and assign separately to avoid masking return values.

# execution guard
[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
    echo "$(basename "${BASH_SOURCE[0]}") must be sourced." >&2
    exit 1
}

# re-source guard
[[ ${_COMMAND_LIB_INCLUDED:-} ]] && return 0

if [[ -z ${BASH_LIBS_DIR:-} ]]; then
    readonly BASH_LIBS_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
fi

# shellcheck source=./system_lib.bash
source "$BASH_LIBS_DIR/system_lib.bash" || return 1

readonly _COMMAND_LIB_DEPS=(getopt)
verify_script_dependencies "${_COMMAND_LIB_DEPS[@]}" || return 1
readonly _COMMAND_LIB_INCLUDED=1

# shellcheck source=./result_type_lib.bash
source "$BASH_LIBS_DIR/result_type_lib.bash" || return 1

declare -a command_line_args
declare -A command_line_opts

#
# get_command_line_arg <arg-position> <arg-outvar>
#
# shellcheck disable=SC2034 # foo appears unused. Verify it or export it.
get_command_line_arg() {
    # shift arg-position position to args array index
    local -i args_index=$1-1
    local -n _arg_outvar="$2"

    if [[ -v command_line_args[args_index] ]]; then
        _arg_outvar="${command_line_args[args_index]}"
    else
        unset _arg
    fi
}

#
# get_command_line_arg_count <arg-count-outvar>
#
get_command_line_arg_count() {
    local -n _arg_count_outvar="$1"

    _arg_count_outvar="${#command_line_args[@]}"
}

#
# has_command_line_opt <opt-name>
#
has_command_line_opt() {
    [[ -v command_line_opts[$1] ]]
}

#
# get_command_line_opt_value <opt-name> <value-outvar>
#
# shellcheck disable=SC2034 # foo appears unused. Verify it or export it.
get_command_line_opt_value() {
    # shellcheck disable=SC2034
    local -n _value_outvar="$2"

    if [[ -v command_line_opts[$1] ]]; then
        _value_outvar="${command_line_opts[$1]}"
    else
        unset _value_outvar
    fi
}

#
# create_schema_from_getopt_spec <getopt_spec> <schema-dictionary-name>
#
# shellcheck disable=SC2034 # foo appears unused. Verify it or export it.
create_schema_from_getopt_spec() {
    local getopt_spec="$2"
    local -n dict="$3"
    local _maxcolons=0

    local -a schema_list
    local opt key colons colon_count

    local IFS=','
    read -r -a schema_list <<< "$getopt_spec"

    for opt in "${schema_list[@]}"; do
        # key preceeds first colon, if any
        key="${opt%%:*}"
        # only colons remain after key
        colons="${opt#"$key"}"
        # remove leading -- from key
        key="${key#--}"
        colon_count="${#colons}"
        (( colon_count > _maxcolons )) && _maxcolons=$colon_count
        dict["$key"]="$colon_count"
    done

    copy_out_result "$1" "$_maxcolons"
}

#
# unpack_getopt_output <getopt-output> <opts-schema-outvar>
#
unpack_getopt_output() {
    local getopt_output="$1"
    local -n opts_schema_outvar="$2"

    eval set -- "$getopt_output"

    # unpack options and values (if present) into command_line_opts dictionary
    while [[ $1 != -- ]]; do
        local opt="$1"
        local key="${opt#--}"

        if (( opts_schema_outvar["$key"] == 0 )); then
            command_line_opts["$key"]=""
        else
            shift
            command_line_opts["$key"]="$1"
        fi

        shift
    done

    # skip the -- options sentinel
    shift 

    # unpack arguments into command_line_args array
    local index=0

    while (( $# > 0 )); do
        command_line_args[index]="$1"
        ((index++))
        shift
    done

    readonly -a command_line_args
    readonly -A command_line_opts
}

#
# register_command_line <error-outvar> <opts-spec> <command-line>
#
register_command_line() {

   local getopt_spec="$2"
   local tmpvar="$(make_tmpvar)"

    if ! capture_output "$tmpvar" getopt -o "" --long "$getopt_spec" -- "${@:3}"; then
        forward_error "$1" "${!tmpvar}"
        return 1
    fi

    local maxcolons

    # shellcheck disable=SC2034 # foo appears unused. Verify it or export it.
    local -A opts_schema
    create_schema_from_getopt_spec maxcolons "$getopt_spec" opts_schema

    if (( maxcolons >= 2 )); then
        originate_error "$1" 'optional command line arguments are not supported'
        return 1
    fi

    local getopt_output="${!tmpvar}"
    unpack_getopt_output "$getopt_output" opts_schema
    return 0
}
