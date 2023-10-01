#!/usr/bin/env bash

set -e

function usage() {
    echo "

Merge multiple VBOX vbo files into a new vbo and mp4 file collection.  By default,
    media files are concatenated into one large mp4.  The vbo files have to have been
    generated using the same VBOX configuration, otherwise the resulting output vbo
    file will be corrupt.

Usage: vbox_merge [OPTIONS] <OUTPUT> <INPUT> [ INPUT ... ]

Where: OUTPUT is the base file name (including \".vbo\" extension) and each
    INPUT is the full path to the vbo file.

Options:

   -M <FLAG> : specifies disposition of media files, where <FLAG> is one of
        c      : copy each mp4 file (the default)
        C      : concatenate the mp4 files
        s      : use a symbolic link to original mp4
        l      : use a hard link to original mp4
   -h        : prints this message

"
}

function error() {
    exitval=$1
    shift
    echo "error: ""$@"
    exit ${exitval}
}

function strip_leading_zeros() {
    for i in "$@"; do
        while [[ ${i::1} == 0 ]]; do
            i=${i:1}
        done
        echo "$i"
    done
}

function add_leading_zeros() {
    length=$1
    shift
    zeros=$(printf "%0${length}d" 0)
    for i in "$@"; do
        i=${zeros}${i}
        echo ${i:0-length:length}
    done
}

function vbo_merge()
{
    mp4_disposition=C

    OPTIND=1
    while getopts ":hM:" opt; do
        case "${opt}" in
            M) if [[ ${#OPTARG} != 1 || ${OPTARG} != [cCsl] ]]; then
                   error 1 "unknown media disposition \"${OPTARG}\""
               fi
               mp4_disposition=${OPTARG};;

            h) usage; return 0;;

            [?]) error 1 "unknown option \"${OPTARG}\"";;
        esac
    done
    ((OPTIND--))
    shift "${OPTIND}"

    (( ${#@} < 2 )) && error 1 "please specify OUTPUT and INPUT"

    dest=$1
    shift

    if [[ ${dest%.vbo} == ${dest} ]]; then
        dest=${dest.vbo}
    fi

    [[ ${dest} != ${dest%/*} ]] && error 1 "output must be in current working directory"

    dest_base=${dest%.vbo}

    if [[ -e ${dest} ]]; then
        while true; do

            read -p "${dest} exists, overwrite? [Y/n] " || exit $?

            if [[ -z ${REPLY}  || ${REPLY} == [Yy] ]]; then
                echo rm -rf "${dest}"
                break
            elif [[ ${REPLY} == [Nn] ]]; then
                echo "ok, aborting"
                return 1
            else
                echo "please answer y or n"
            fi
        done

    fi
    rm -f "${dest}"
    rm -f "${dest_base}_0001.mp4"
    rm -f "${dest}.txt"

    srcs=( "$@" )
    mp4_list=( )

    for src in "${srcs[@]}"
    do
        echo processing "${src}"
        [[ -f ${src} ]] || error 1 "input file \"${src}\" not found"

        src_dir=${src%/*}
        src_dir=${src_dir:-.}
        src_base=${src##*/}
        src_base=${src_base%.vbo}

        mp4_list+=( "${src_dir}/${src_base}_"*.mp4 )

        # if no dest yet, means first src
        if [[ ! -f ${dest} ]]; then
            # copy srcs[0] into dest, change the mp4 file base name
            sed 's/'"${src_base}"'/'"${dest_base}"'/' < "${src}" > "${dest}"
        else
            # concatenate data section from other src files
            exec {srcfd}< "${src}"
            while read -u "${srcfd}" line; do
                line=${line/$'\r'/} # cleanup
                if [[ ${line} == "[column names]" ]]; then
                    read -u "${srcfd}" -a colnames
                    i=0
                    for colname in "${colnames[@]}"; do
                        colname=${colname/$'\r'/} # cleanup
                        if [[ ${colname} == "avifileindex" ]]; then
                            avifileindex_idx=$i
                        elif [[ ${colname} == "time" ]]; then
                            time_idx=$i
                        elif [[ ${colname} == "avitime" ]]; then
                            avitime_idx=$i
                        fi
                        ((i++))
                    done
                elif [[ ${line} == "[data]" ]]; then
                    break
                fi
            done

            lastline=( $(tail -1 "${dest}") )
            echo ${lastline[*]}

            avitime_base=$(strip_leading_zeros "${lastline[avitime_idx]}")

            time_base=${lastline[time_idx]}
            time_base=${timebase/./} # strip decimal point

            while read -u "${srcfd}" -a data; do
                data[avifileindex_idx]=0001
                # leading zeros
                avitime=$(strip_leading_zeros "${data[avitime_idx]}")

                ((avitime+=avitime_base))
                avitime=$(add_leading_zeros 9 "${avitime}")

                data[avitime_idx]=$(add_leading_zeros 9 "${avitime}")

                time=${data[time_idx]/.}
                ((time+=time_base))
                split=-3 # 3 decimal places
                data[time_idx]=${time:0:split}.${time:split}

                printf "%s\n" "${data[*]}" >> "${dest}"
            done
        fi
    done

    printf "file '%s'\n" "${mp4_list[@]}" >> "${dest}.txt"

    ffmpeg -f concat -safe 0 -i "${dest}.txt" -c copy "${dest_base}_0001.mp4"
}

if [[ ${0} =~ .*bash$ ]]
then
    return
fi

if [[ -z ${vbo_merge_DOTEST} ]]
then
    vbo_merge "${@}"
    exit $?
fi
