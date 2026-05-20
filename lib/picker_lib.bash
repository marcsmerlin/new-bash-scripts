# shellcheck shell=bash
# shellcheck disable=SC2155 # Declare and assign separately to avoid masking return values.
# shellcheck disable=SC2181 # Check exit code directly with e.g. `if mycmd;`, not indirectly with `$?`.

# re-source guard
[[ ${_picker_lib_included:-} ]] &&
    readonly _picker_lib_included=1

[[ -z ${BASH_LIBS_DIR:-} ]] &&
    readonly BASH_LIBS_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

# shellcheck source=./result_type_lib.bash
source "$BASH_LIBS_DIR/result_type_lib.bash"
(($? == 0)) || return 1

# shellcheck source=./system_lib.bash
source "$BASH_LIBS_DIR/system_lib.bash"
(($? == 0)) || return 1

#
# _collect_entries_from_directory <error-message out> <directory> <predicate> <collection>
#
_collect_entries_from_directory() {
    local directory="$2"
    local predicate="$3"

    [[ -d "$directory" ]] || {
        originate_error "$1" 'Directory "%s" does not exist.' "$directory"
        return 1
    }

    local -n selection_out="$4"
    selection_out=()

    shopt -s nullglob

    for entry in "$directory"/*; do
        "$predicate" "$entry" || continue
        selection_out+=("$entry")
    done

    shopt -u nullglob

    return 0
}

#
# _pick_entry_from_collection <collection>
#
_pick_entry_from_collection() {
    local prompt="$1"
    local tmpvar="$(make_tmpvar)"
    local -n "$tmpvar"="$2"
    local -i number_of_entries

    eval "number_of_entries=\"\${#${tmpvar}[@]}\""

    ((number_of_entries == 0)) && {
        printf ''
        return
    }

    local -i index
    local entry

    for ((index = 0; index < number_of_entries; index++)); do
        eval "entry=\"\${${tmpvar}[$index]}\""
        printf_stderr '%d) %s\n' "$index" "$(basename "$entry")"
    done

    read_integer_input index "$prompt" 0 "$((number_of_entries - 1))" && {
        eval "entry=\"\${${tmpvar}[$index]}\""
        printf '%s\n' "$entry"
        return
    }

    printf ''
    return
}

#
# pick_entry_from_directory <picked_entry | error-message out> <prompt> <directory> <predicate>
#
# shellcheck disable=SC2034
pick_entry_from_directory() {
    local prompt="$2"
    local directory="$3"
    local predicate="$4"
    local tmpvar="$(make_tmpvar)"
    local -a collection

    _collect_entries_from_directory "$tmpvar" "$directory" "$predicate" collection || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    local picked_entry="$(_pick_entry_from_collection "$prompt" collection)"
    copy_out_result "$1" "$picked_entry"
    return 0
}
