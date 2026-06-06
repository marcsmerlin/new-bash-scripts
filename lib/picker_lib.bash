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
    local -n selection_out="$4"


    [[ -d "$directory" ]] || {
        originate_error "$1" 'Directory "%s" does not exist.' "$directory"
        return 1
    }

    selection_out=()

    shopt -s nullglob

    for entry in "$directory"/*; do
        "$predicate" "$entry" || continue
        selection_out+=("$entry")
    done

    shopt -u nullglob

    (( "${#selection_out[@]}" > 0 )) || {
        originate_error "$1" 'Directory "%s" contains no matching files.' "$directory"
        return 1
    }

    return 0
}

#
# _pick_index_from_collection <index> <prompt> <collection>
#
_pick_index_from_collection() {
    local prompt="$2"
    local -n _namref_pick_index_from_collection="$3"

    local number_of_entries="${#_namref_pick_index_from_collection[@]}"

    ((number_of_entries > 0)) || {
        return 1
    }

    local index
    local entry

    for ((index = 0; index < number_of_entries; index++)); do
        entry="${_namref_pick_index_from_collection[$index]}"
        printf_stderr '%d) %s\n' "$index" "$(basename "$entry")"
    done
    
    local tmpvar="$(make_tmpvar)"

    read_integer_input "$tmpvar" "$prompt" 0 "$((number_of_entries - 1))" || {
        return 1
    }

    copy_out_result "$1" "${!tmpvar}"
    return 0
}

#
# _pick_entry_from_collection <prompt> <collection>
#
_pick_entry_from_collection() {
    local prompt="$1"
    local -n _namref_pick_entry_from_collection="$2"

    local tmpvar="$(make_tmpvar)"

    _pick_index_from_collection "$tmpvar" "$prompt" _namref_pick_entry_from_collection || {
        printf ''
        return
    }

    local index="${!tmpvar}"
    local entry

    entry=${_namref_pick_entry_from_collection[$index]}
    printf '%s\n' "$entry"
    return
}

#
# pick_entry_from_directory <entry | error-trace out> <prompt> <directory> <predicate>
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

    local entry="$(_pick_entry_from_collection "$prompt" collection)"
    copy_out_result "$1" "$entry"
    return 0
}
