# CMake implementation of AutoGen
# Copyright (C) 2017 Anonymous Maarten <anonymous.maarten@gmail.com>

set(WS " \t\r\n")

function(cutoff_first_occurrence TEXT OCCURRENCE RESULT)
    string(FIND "${TEXT}" "${OCCURRENCE}" OCCURRENCE_INDEX)
    if (OCCURRENCE_INDEX EQUAL -1)
        set(${TEXT} "" PARENT_SCOPE)
        return()
    endif()

    string(LENGTH "${OCCURRENCE}" OCCURRENCE_LENGTH)
    math(EXPR CUTOFF_INDEX "${OCCURRENCE_INDEX}+${OCCURRENCE_LENGTH}")
    string(SUBSTRING "${TEXT}" ${CUTOFF_INDEX} -1 TEXT_REMAINDER)
    set(${RESULT} "${TEXT_REMAINDER}" PARENT_SCOPE)

    endfunction()

function(read_definition DEFINITION_FILENAME TEMPLATE_FILENAME DATA)
    file(READ "${DEFINITION_FILENAME}" DEFINITION_CONTENTS)

    string(REGEX MATCH "autogen definitions ([a-zA-Z\\._-]+);[${WS}]*" TEMPLATE_MATCH "${DEFINITION_CONTENTS}")
    if (NOT TEMPLATE_MATCH)
        message(FATAL_ERROR "${DEFINITION_FILENAME} does not contain an AutoGen definition.")
    endif()

    get_filename_component(DEFINITION_DIR "${DEFINITION_FILENAME}" PATH)
    set(${TEMPLATE_FILENAME} "${DEFINITION_DIR}/${CMAKE_MATCH_1}" PARENT_SCOPE)
    if (DEBUG)
        message("found: TEMPLATE_FILENAME=${CMAKE_MATCH_1}")
    endif()

    cutoff_first_occurrence("${DEFINITION_CONTENTS}" "${TEMPLATE_MATCH}" DEFINITION_CONTENTS)

    set(DEFINITION "")

    while (1)
        string(REGEX MATCH "([a-zA-Z_][a-zA-Z0-9_]*)[${WS}]*=[${WS}]*{[${WS}]*" GROUPSTART_MATCH "${DEFINITION_CONTENTS}")
        if (NOT GROUPSTART_MATCH)
            break()
        endif()
        set(GROUPNAME "${CMAKE_MATCH_1}")
        cutoff_first_occurrence("${DEFINITION_CONTENTS}" "${GROUPSTART_MATCH}" DEFINITION_CONTENTS)
        if (DEBUG)
            message("found: GROUPNAME=${GROUPNAME}")
        endif()
        set(NBKEYS 0)
        set(GROUP_KEY_VALUES "")
        while (1)
            string(REGEX MATCH "^([a-zA-Z_][a-zA-Z0-9_]*)[${WS}]*=[${WS}]*(([\"']([${WS}a-zA-Z0-9_%\\\"<>\(\)\\.*+/?:,\\-]+)[\"'])|([a-zA-Z0-9_%\\]+))[${WS}]*;[${WS}]*" KEY_VALUE_MATCH "${DEFINITION_CONTENTS}")
            if (NOT KEY_VALUE_MATCH)
                break()
            endif()
            set(KEY "${CMAKE_MATCH_1}")
            if ("${CMAKE_MATCH_4}" STREQUAL "")
                set(VALUE "${CMAKE_MATCH_5}")
            else()
                string(REPLACE "\\\"" "\"" VALUE "${CMAKE_MATCH_4}")
                #set(VALUE "${CMAKE_MATCH_4}")
            endif()

            if (DEBUG)
                message("found: KEY=${KEY}, VALUE=${VALUE}")
            endif()
            math(EXPR NBKEYS "${NBKEYS}+1")
            list(APPEND GROUP_KEY_VALUES "${KEY}" "${VALUE}")
            cutoff_first_occurrence("${DEFINITION_CONTENTS}" "${KEY_VALUE_MATCH}" DEFINITION_CONTENTS)
        endwhile()
        string(REGEX MATCH "^[${WS}]*}[${WS}]*;[${WS}]*" GROUPEND_MATCH "${DEFINITION_CONTENTS}")
        if (NOT GROUPEND_MATCH)
            message(FATAL_ERROR "Group ${GROUPNAME} did not finish.")
        endif()
        cutoff_first_occurrence("${DEFINITION_CONTENTS}" "${GROUPEND_MATCH}" DEFINITION_CONTENTS)
        list(APPEND DEFINITION "${GROUPNAME}" ${NBKEYS} ${GROUP_KEY_VALUES})
    endwhile()
    set(${DATA} "${DEFINITION}" PARENT_SCOPE)
endfunction()

function(match_autogen_group TEXT START POS0 POS1 MATCH FOUND)
    string(SUBSTRING "${TEXT}" "${START}" -1 TEXT)
    string(REGEX MATCH "\\[\\+[${WS}]*([ a-zA-Z0-9=_$%\\(\\)\"\\+\\-]+)[${WS}]*\\+\\]" MATCH_GROUP "${TEXT}")
    if ("${MATCH_GROUP}" STREQUAL "")
        set(${FOUND} 0 PARENT_SCOPE)
        return()
    endif()
    string(FIND "${TEXT}" "${MATCH_GROUP}" START_TEXT)
    math(EXPR POS0_var "${START}+${START_TEXT}")
    string(LENGTH "${MATCH_GROUP}" MATCH_LENGTH)
    math(EXPR POS1_var "${POS0_var}+${MATCH_LENGTH}")
    set(${POS0} "${POS0_var}" PARENT_SCOPE)
    set(${POS1} "${POS1_var}" PARENT_SCOPE)
    set(${FOUND} 1 PARENT_SCOPE)
    string(STRIP "${CMAKE_MATCH_1}" CONTENT)
    set("${MATCH}" "${CONTENT}" PARENT_SCOPE)
endfunction()

function(append_output SUFFICES_FILENAMES TEXT POS0 POS1 FILTER)
    math(EXPR POS_LENGTH "${POS1}-${POS0}")
    string(LENGTH "${TEXT}" TEXT_LENGTH)
    string(SUBSTRING "${TEXT}" "${POS0}" "${POS_LENGTH}" TEXT_APPEND)
    if (DEBUG)
        message("appending ${POS0}:${POS1}, length=${POS_LENGTH}")
    endif()
    append_output_text("${SUFFICES_FILENAMES}" "${TEXT_APPEND}" "${FILTER}")
endfunction()

function(append_output_text SUFFICES_FILENAMES TEXT_APPEND FILTER)
    string(LENGTH "${TEXT_APPEND}" TEXT_LENGTH)
    list(LENGTH SUFFICES_FILENAMES NB)
    math(EXPR NB_END "${NB}-1")
    foreach(INDEX RANGE 0 ${NB_END} 3)
        math(EXPR INDEX_1 "${INDEX}+1")
        math(EXPR INDEX_2 "${INDEX}+2")
        list(GET SUFFICES_FILENAMES ${INDEX} SUFFIX)
        list(GET SUFFICES_FILENAMES ${INDEX_1} FILENAME)
        list(GET SUFFICES_FILENAMES ${INDEX_2} TEMPFILENAME)
        set(WRITE_OK 1)
        if (FILTER)
            if (NOT "${SUFFIX}" STREQUAL "${FILTER}")
                set(WRITE_OK 0)
            endif()
        endif()
        if (WRITE_OK)
            if (DEBUG)
                message("Write: ${TEXT_LENGTH} characters to ${FILENAME}")
            endif()
            file(APPEND "${TEMPFILENAME}" "${TEXT_APPEND}")
        endif()
    endforeach()
endfunction()

function(output_finish SUFFICES_FILENAMES)
    list(LENGTH SUFFICES_FILENAMES NB)
    math(EXPR NB_END "${NB}-1")
    foreach(INDEX RANGE 0 ${NB_END} 3)
        math(EXPR INDEX_1 "${INDEX}+1")
        math(EXPR INDEX_2 "${INDEX}+2")
        list(GET SUFFICES_FILENAMES ${INDEX_1} FILENAME)
        list(GET SUFFICES_FILENAMES ${INDEX_2} TEMPFILENAME)
        file(RENAME "${TEMPFILENAME}" "${FILENAME}")
    endforeach()
endfunction()

function(stack_push STACK_ARG)
    set(STACK_LIST "${${STACK_ARG}}")
    string(REPLACE ";" " " NEWITEM "${ARGN}")
    if (DEBUG)
        list(LENGTH STACK_LIST STACK_LENGTH)
        message("Pushing \"${NEWITEM}\" onto stack (length=${STACK_LENGTH})")
    endif()
    list(APPEND STACK_LIST "${NEWITEM}")
    set(${STACK_ARG} "${STACK_LIST}" PARENT_SCOPE)
endfunction()

function(stack_pop STACK_ARG ITEM)
    set(STACK_LIST "${${STACK_ARG}}")
    list(LENGTH STACK_LIST STACK_LENGTH)
    if (STACK_LENGTH EQUAL 0)
        message(FATAL_ERROR "ENDFOR: stack is empty")
    endif()
    math(EXPR LAST_ITEM_INDEX "${STACK_LENGTH}-1")
    list(GET STACK_LIST "${LAST_ITEM_INDEX}" LAST_ITEM)
    list(REMOVE_AT STACK_LIST "${LAST_ITEM_INDEX}")
    string(REPLACE " " ";" LAST_ITEM_LIST "${LAST_ITEM}")
    if (DEBUG)
        message("Popping \"${LAST_ITEM}\" from stack (length=${STACK_LENGTH})")
    endif()
    set(${ITEM} "${LAST_ITEM_LIST}" PARENT_SCOPE)
    set(${STACK_ARG} "${STACK_LIST}" PARENT_SCOPE)
endfunction()

function(stack_top STACK_ARG ITEM)
    set(STACK_LIST "${${STACK_ARG}}")
    list(LENGTH STACK_LIST STACK_LENGTH)
    if (STACK_LENGTH EQUAL 0)
        message(FATAL_ERROR "ENDFOR: stack is empty")
    endif()
    math(EXPR LAST_ITEM_INDEX "${STACK_LENGTH}-1")
    list(GET STACK_LIST "${LAST_ITEM_INDEX}" LAST_ITEM)
    string(REPLACE " " ";" LAST_ITEM_LIST "${LAST_ITEM}")
    if (DEBUG)
        message("Top of stack: \"${LAST_ITEM}\" from stack (length=${STACK_LENGTH})")
    endif()
    set(${ITEM} "${LAST_ITEM_LIST}" PARENT_SCOPE)
endfunction()

function(stack_find_key STACK_LIST TEMPLATE_PARAMETERS KEY VALUE)
    list(REVERSE STACK_LIST)
    foreach(STACK_ITEM ${STACK_LIST})
        string(REPLACE " " ";" STACK_ITEM_LIST "${STACK_ITEM}")
        list(GET STACK_ITEM_LIST 3 TP_INDEX)
        math(EXPR TP_SIZE_INDEX "${TP_INDEX}+1")
        list(GET TEMPLATE_PARAMETERS ${TP_SIZE_INDEX} TP_SIZE)
        math(EXPR TP_KV_INDEX_START "${TP_INDEX}+2")
        math(EXPR TP_KV_INDEX_END "${TP_KV_INDEX_START}+2*${TP_SIZE}-1")
        foreach(TP_KV_INDEX RANGE ${TP_KV_INDEX_START} ${TP_KV_INDEX_END} 2)
            list(GET TEMPLATE_PARAMETERS ${TP_KV_INDEX} TP_KEY)
            if("${TP_KEY}" STREQUAL "${KEY}")
                math(EXPR TP_VALUE_INDEX "${TP_KV_INDEX}+1")
                list(GET TEMPLATE_PARAMETERS ${TP_VALUE_INDEX} TP_VALUE)
                set(${VALUE} "${TP_VALUE}" PARENT_SCOPE)
                return()
            endif()
        endforeach()
    endforeach()
    message(FATAL_ERROR "Unknown KEY=${KEY}")
endfunction()

function(template_parameters_find_next_groupname_index TEMPLATE_PARAMETERS GROUPNAME INDEX_LAST INDEX_NEXT)
    if (${INDEX_LAST} LESS 0)
        set(INDEX 0)
    else ()
        math(EXPR INDEX_1 "1+(${INDEX_LAST})")
        list(GET TEMPLATE_PARAMETERS ${INDEX_1} GROUPNAME_INDEX_SIZE)
        math(EXPR INDEX "${INDEX_LAST}+1+2*${GROUPNAME_INDEX_SIZE}+1")
    endif()
    list(LENGTH TEMPLATE_PARAMETERS PARAMETERS_LENGTH)
    while (${INDEX} LESS ${PARAMETERS_LENGTH})
        list(GET TEMPLATE_PARAMETERS ${INDEX} GROUPNAME_AT_INDEX)
        if ("${GROUPNAME}" STREQUAL "${GROUPNAME_AT_INDEX}")
            set("${INDEX_NEXT}" ${INDEX} PARENT_SCOPE)
            return()
        endif()
        math(EXPR INDEX_1 "${INDEX}+1")
        list(GET TEMPLATE_PARAMETERS ${INDEX_1} GROUPNAME_INDEX_SIZE)
        math(EXPR INDEX "${INDEX}+1+2*${GROUPNAME_INDEX_SIZE}+1")
    endwhile()
    set("${INDEX_NEXT}" -1 PARENT_SCOPE)
endfunction()

function(calculate_line_number TEXT POSITION LINENUMBER_ARG)
    #math(EXPR INDEX_MAX "${POSITION}-1")
    string(SUBSTRING "${TEXT}" 0 ${POSITION} SUBTEXT)
    string(REGEX MATCHALL "\n" MATCH_NEWLINES "${SUBTEXT}")
    list(LENGTH MATCH_NEWLINES NBLINES)
    math(EXPR NBLINES "${NBLINES}+1")
    set(${LINENUMBER_ARG} ${NBLINES} PARENT_SCOPE)
endfunction()

function(parse_template TEMPLATE_FILENAME OUTPUT_DIR TEMPLATE_PARAMETERS)
    file(READ ${TEMPLATE_FILENAME} TEMPLATE_CONTENTS)
    set(POSITION 0)
    match_autogen_group("${TEMPLATE_CONTENTS}" "${POSITION}" POS0 POS1 AUTOGEN FOUND)
    if (NOT FOUND)
        message(FATAL_ERROR "Header of template not found")
    endif()
    string(REGEX MATCH "AutoGen5 template ([ a-zA-Z0-9]*)" SUFFICES_MATCH "${AUTOGEN}")
    if (NOT SUFFICES_MATCH)
        message(FATAL_ERROR "No output suffices found")
    endif()
    string(STRIP "${CMAKE_MATCH_1}" SUFFICES)
    string(REPLACE " " ";" SUFFICES "${SUFFICES}")
    set(SUFFICES_FILENAMES "")
    get_filename_component(TEMPLATE_NAME_WE "${TEMPLATE_FILENAME}" NAME_WE)
    foreach(SUFFIX ${SUFFICES})
        if ("${OUTPUT_DIR}" STREQUAL "")
            set(DIR_PREFIX "")
        else()
            set(DIR_PREFIX "${OUTPUT_DIR}/")
        endif()
        string(RANDOM LENGTH 64 RANDOMSTRING)
        set(FILENAME "${DIR_PREFIX}${TEMPLATE_NAME_WE}.${SUFFIX}")
        set(TEMPFILENAME "${DIR_PREFIX}${TEMPLATE_NAME_WE}${RANDOMSTRING}.${SUFFIX}")
        list(APPEND SUFFICES_FILENAMES "${SUFFIX}" "${FILENAME}" "${TEMPFILENAME}")
        file(WRITE "${FILENAME}" "")
    endforeach()
    if (DEBUG)
        message("Output files: ${SUFFICES_FILENAMES}")
    endif()
    set(WRITE_FILTER "")
    append_output("${SUFFICES_FILENAMES}" "${TEMPLATE_CONTENTS}" 0 "${POS0}" "${WRITE_FILTER}")
    math(EXPR POS1 "${POS1}+1")
    set(POSITION "${POS1}")
    if (DEBUG)
        message("Output: ${SUFFICES_FILENAMES}")
    endif()

    set(STACK "")
    while (1)
        match_autogen_group("${TEMPLATE_CONTENTS}" "${POSITION}" POS0 POS1 GROUP_MATCH FOUND)
        if (NOT FOUND)
            if (DEBUG)
                message("No group found. Dumping rest of file.")
            endif()
            if (NOT "${STACK}" STREQUAL "")
                message(FATAL_ERROR "Stack not empty at end of file")
            endif()
            string(LENGTH "${TEMPLATE_CONTENTS}" TEXT_LENGTH)
            append_output("${SUFFICES_FILENAMES}" "${TEMPLATE_CONTENTS}" ${POSITION} ${TEXT_LENGTH} "${WRITE_FILTER}")
            break()
        endif()
        append_output("${SUFFICES_FILENAMES}" "${TEMPLATE_CONTENTS}" ${POSITION} ${POS0} "${WRITE_FILTER}")
        set(POSITION "${POS1}")

        if (GROUP_MATCH MATCHES "^FOR")
            string(REPLACE " " ";" GROUP_MATCH_LIST "${GROUP_MATCH}")
            list(GET GROUP_MATCH_LIST 1 FOR_KEY)
            template_parameters_find_next_groupname_index("${TEMPLATE_PARAMETERS}" "${FOR_KEY}" -1 FOR_INDEX)
            if (DEBUG)
                message("FOR_KEY: ${FOR_KEY}")
                message("FOR_INDEX: ${FOR_INDEX}")
            endif()
            if (${FOR_KEY} LESS 0)
                message(FATAL_ERROR "FOR has key with empty list. Not implemented yet..")
            endif()
            stack_push(STACK FOR ${POSITION} ${FOR_KEY} ${FOR_INDEX})
        elseif (GROUP_MATCH MATCHES "^ENDFOR")
            string(REPLACE " " ";" GROUP_MATCH_LIST "${GROUP_MATCH}")
            list(GET GROUP_MATCH_LIST 1 ENDFOR_KEY)
            stack_pop(STACK FOR_ITEM)
            list(GET FOR_ITEM 0 FOR_FOR)
            if (NOT "${FOR_FOR}" STREQUAL "FOR")
                message(FATAL_ERROR "ENDFOR does not match last item: ${FOR_FOR}")
            endif()
            list(GET FOR_ITEM 1 FOR_POSITION)
            list(GET FOR_ITEM 2 FOR_KEY)
            if (NOT "${FOR_KEY}" STREQUAL "${ENDFOR_KEY}")
                calculate_line_number("${TEMPLATE_CONTENTS}" "${POSITION}" LINENUMBER)
                message("FOR and ENDFOR do not match. (line number ${LINENUMBER}) (FOR:${FOR_KEY}, ENDFOR:${ENDFOR_KEY})")
            endif()
            list(GET FOR_ITEM 3 FOR_INDEX_PREV)
            template_parameters_find_next_groupname_index("${TEMPLATE_PARAMETERS}" "${FOR_KEY}" ${FOR_INDEX_PREV} FOR_INDEX)
            if (DEBUG)
                message("FOR_INDEX was ${FOR_INDEX_PREV}, is now ${FOR_INDEX}")
            endif()
            if (${FOR_INDEX} LESS 0)
                if (DEBUG)
                    message("ENDFOR: FOR_INDEX < 0 (no more key) ==> Continue")
                endif()
            else()
                set(POSITION ${FOR_POSITION})
                stack_push(STACK FOR ${FOR_POSITION} ${FOR_KEY} ${FOR_INDEX})
                if (DEBUG)
                    message("ENDFOR: FOR_INDEX >= 0 (more keys available) ==> Back to position=${FOR_POSITION}")
                endif()
            endif()
        elseif (GROUP_MATCH MATCHES "^CASE")
            string(REGEX MATCH "^CASE[${WS}]+\\(([a-zA-Z]+)\\)" CASE_MATCH "${GROUP_MATCH}")
            if ("${CASE_MATCH}" STREQUAL "")
                message(FATAL_ERROR "Wrong CASE syntax")
            endif()
            set(CASE_KEY "${CMAKE_MATCH_1}")
            if (DEBUG)
                message("CASE: KEY=${CASE_KEY}")
            endif()
            stack_push(STACK CASE "${CASE_KEY}" ${POSITION})
        elseif (GROUP_MATCH MATCHES "^==")
            math(EXPR POSITION "${POSITION}+1")
            string(REGEX MATCH "^==[${WS}]+([a-zA-Z_][a-zA-Z0-9_]*)" CASE_MATCH "${GROUP_MATCH}")
            if ("${CASE_MATCH}" STREQUAL "")
                message(FATAL_ERROR "Wrong == syntax")
            endif()
            stack_top(STACK CASE_ITEM)
            list(GET CASE_ITEM 0 CASE_CASE)
            if(NOT "${CASE_CASE}" STREQUAL "CASE")
                message(FATAL_ERROR "== block must be in CASE. Top of stack=${CASE_CASE}")
            endif()
            set(CASE_VALUE "${CMAKE_MATCH_1}")
            if (DEBUG)
                message("case: == VALUE=${CASE_VALUE}")
            endif()
            list(GET CASE_ITEM 1 CASE_KEY)
            if ("${CASE_KEY}" STREQUAL "suffix")
                if (DEBUG)
                    message("Setting write filter to ${CASE_VALUE}")
                endif()
                set(WRITE_FILTER "${CASE_VALUE}")
            else()
                message(FATAL_ERROR "CASE: unsupported argument ${CASE_KEY}")
            endif()
        elseif (GROUP_MATCH MATCHES "^ESAC")
            stack_pop(STACK CASE_ITEM)
            if (DEBUG)
                message("ESAC")
            endif()
            list(GET CASE_ITEM 0 CASE_CASE)
            if (NOT "${CASE_CASE}" STREQUAL "CASE")
                message(FATAL_ERROR "ESAC does not match last item: ${CASE_CASE}")
            endif()
            if ("${CASE_KEY}" STREQUAL "suffix")
                if (DEBUG)
                    message("Removing write filter")
                endif()
                set(WRITE_FILTER "")
            else()
                message(FATAL_ERROR "CASE: unsupported argument ${CASE_KEY}")
            endif()
        else()
            string(REGEX MATCH "\\(([a-zA-Z0-9_$%\"${WS}\\+\\-]+)\\)" PARENTHESE_MATCH "${GROUP_MATCH}")
            if (NOT "${PARENTHESE_MATCH}" STREQUAL "")
                set(PARENTHESE_CONTENT "${CMAKE_MATCH_1}")
                string(REPLACE " " ";" PARENTHESE_LIST "${PARENTHESE_CONTENT}")
                list(GET PARENTHESE_LIST 0 PARENTHESE_COMMAND)
                if ("${PARENTHESE_COMMAND}" STREQUAL "get")
                    list(GET PARENTHESE_LIST 1 KEY_QUOTED)
                    string(REGEX MATCH "\\\"([a-zA-Z_${WS}]+)\\\"" KEY_MATCH "${KEY_QUOTED}")
                    if ("${KEY_MATCH}" STREQUAL "")
                        message(FATAL_ERROR "get: empty key")
                    endif()
                    set(KEY "${CMAKE_MATCH_1}")
                    if (DEBUG)
                        message("Get: key=${KEY}")
                    endif()
                    stack_find_key("${STACK}" "${TEMPLATE_PARAMETERS}" "${KEY}" VALUE)
                    if (DEBUG)
                        message("Get key=${KEY} ==> value=${VALUE}")
                    endif()
                    append_output_text("${SUFFICES_FILENAMES}" "${VALUE}" "${WRITE_FILTER}")
                elseif("${PARENTHESE_COMMAND}" STREQUAL "tpl-file-line")
                    list(GET PARENTHESE_LIST 1 FORMAT_LINE)
                    calculate_line_number("${TEMPLATE_CONTENTS}" "${POSITION}" LINENUMBER)
                    append_output_text("${SUFFICES_FILENAMES}" "${LINENUMBER}" "${WRITE_FILTER}")
                else()
                    message(FATAL_ERROR "Unknown parenthese command: ${PARENTHESE_COMMAND}")
                endif()
            else()
                message(FATAL_ERROR "Unknown command: ${GROUP_MATCH}")
            endif()
        endif()

    endwhile()
    if (NOT "${STACK}" STREQUAL "")
        message(FATAL_ERROR "STACK was not empty at EOF")
    endif()
    output_finish("${SUFFICES_FILENAMES}")
endfunction()

if ("${DEFINITION}" STREQUAL "")
    message(FATAL_ERROR "Need definition file")
endif()
if (NOT EXISTS "${DEFINITION}")
    message(FATAL_ERROR "Definition file does not exist (${DEFINITION})")
endif()

read_definition("${DEFINITION}" TEMPLATE_FILENAME DATA)
if (DEBUG)
    message("${TEMPLATE_FILENAME}")
    message("${DATA}")
endif()

parse_template("${TEMPLATE_FILENAME}" "${OUTPUTDIR}" "${DATA}")
