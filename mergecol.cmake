
if(REPO)
    set(repo ${REPO})
else()
    set(repo /Users/okuoku/stage/lkl-wasm)
endif()

# Run `git ls-files -u` to collect unmerged paths

execute_process(
    COMMAND git ls-files -u
    OUTPUT_VARIABLE out
    RESULT_VARIABLE rr
    WORKING_DIRECTORY ${repo})

if(rr)
    message(FATAL_ERROR "Failed to collect unmerged paths: ${rr}")
endif()

set(paths)

while(out)
    # FIXME: Handle renames(take filenames only on stage 1)
    if("${out}" MATCHES "([^\n]*)\n(.*)")
        set(line "${CMAKE_MATCH_1}")
        set(out "${CMAKE_MATCH_2}")
        if("${line}" MATCHES "[^\t]*\t(.*)")
            set(p ${CMAKE_MATCH_1})
            if(NOT path_${p})
                set(path_${p} ON)
                list(APPEND paths "${p}")
            endif()
        else()
            message(FATAL_ERROR "Invalid line format: [${line}]")
        endif()
    endif()
endwhile()

# Pass1: Collect conflicted lines and commits information
foreach(e ${paths})
    message(STATUS "blame: ${e}")

    # Collect blame output
    # FIXME: How to handle line removal..?
    execute_process(
        COMMAND git blame -p ${e}
        OUTPUT_VARIABLE out
        RESULT_VARIABLE rr
        WORKING_DIRECTORY ${repo})
    if(rr)
        message(FATAL_ERROR "Failed to blame: ${rr}")
    endif()

    set(lines)
    set(state merged)
    set(curcommit OFF)
    while(out)
        if("${out}" MATCHES "([^\n]*)\n(.*)")
            set(line "${CMAKE_MATCH_1}")
            set(out "${CMAKE_MATCH_2}")
            if("${line}" MATCHES "([0-9a-f]+) ([0-9]+) ([0-9]+) ([0-9]+)")
                set(commit "${CMAKE_MATCH_1}")
                #message(STATUS "Commit(Zone): ${commit}")
                set(curcommit "${commit}")
                list(APPEND lines "${line}")
                if("${state}" STREQUAL "A")
                    list(APPEND patha_${e} ${commit})
                elseif("${state}" STREQUAL "B")
                    list(APPEND pathb_${e} ${commit})
                endif()
            elseif("${line}" MATCHES "([0-9a-f]+) ([0-9]+) ([0-9]+)")
                set(commit "${CMAKE_MATCH_1}")
                #message(STATUS "Commit: ${commit}")
                set(curcommit OFF)
                list(APPEND lines "${line}")
                if("${state}" STREQUAL "A")
                    list(APPEND patha_${e} ${commit})
                elseif("${state}" STREQUAL "B")
                    list(APPEND pathb_${e} ${commit})
                endif()
            elseif("${line}" MATCHES "author (.*)")
                set(author "${CMAKE_MATCH_1}")
                message(STATUS "Author: ${author}")
                if(curcommit)
                    set(author_${commit} "${CMAKE_MATCH_1}")
                else()
                    message(FATAL_ERROR "No curcommit: ${line}")
                endif()
            elseif("${line}" MATCHES "author-mail (.*)")
                set(mail "${CMAKE_MATCH_1}")
                message(STATUS "Mail: ${mail}")
                if(curcommit)
                    set(mail_${commit} "${mail}")
                else()
                    message(FATAL_ERROR "No curcommit: ${line}")
                endif()
            elseif("${line}" MATCHES "summary (.*)")
                set(summary "${CMAKE_MATCH_1}")
                message(STATUS "Summary: ${summary}")
                if(curcommit)
                    set(summary_${commit} "${summary}")
                else()
                    message(FATAL_ERROR "No curcommit: ${line}")
                endif()
            elseif("${line}" MATCHES "\t(.*)")
                set(curcommit OFF)
                set(src "${CMAKE_MATCH_1}")
                if("${src}" MATCHES "^<<<<<<<")
                    message(STATUS "BEGIN")
                    set(state "A")
                elseif("${src}" MATCHES "^=======")
                    message(STATUS "CHANGE")
                    set(state "B")
                elseif("${src}" MATCHES "^>>>>>>>")
                    set(state "merged")
                    message(STATUS "END")
                else()
                    # Skip source line
                endif()
            else()
                # Do nothing, drop line
            endif()
        endif()
    endwhile()
endforeach()

# Pass2: Generate summary
foreach(e ${paths})
    list(REMOVE_DUPLICATES patha_${e})
    list(REMOVE_DUPLICATES pathb_${e})
    list(REMOVE_ITEM patha_${e} 0000000000000000000000000000000000000000)
    list(REMOVE_ITEM pathb_${e} 0000000000000000000000000000000000000000)
    message(STATUS "${e}:")

    # Pass2.1: Filter out duplicates
    foreach(c ${patha_${e}})
        set(seen_${e}_${c} ON)
    endforeach()
    foreach(c ${pathb_${e}})
        if(seen_${e}_${c})
            list(REMOVE_ITEM patha_${e} ${c})
            list(REMOVE_ITEM pathb_${e} ${c})
        endif()
    endforeach()
    
    # Pass2.2: Output
    foreach(c ${patha_${e}})
        message(STATUS "\tA ${c} ${author_${c}} ${mail_${c}}\t${summary_${c}}")
    endforeach()
    foreach(c ${pathb_${e}})
        message(STATUS "\tB ${c} ${author_${c}} ${mail_${c}}\t${summary_${c}}")
    endforeach()
endforeach()

