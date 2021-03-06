#!/usr/bin/env bash

#   mp3art.sh
#   Author: William Woodruff
#   ------------------------
#   Adds album artwork to MP3 files in bulk.
#   Requires ffmpeg or avconv and GNU bash 4.0.
#   ------------------------
#   This code is licensed by William Woodruff under the MIT License.
#   http://opensource.org/licenses/MIT

function usage() {
	printf "Usage: $(basename ${0}) [-svh] [-f artfile] [-j jobs] [directory]\n"
	printf "\t-f <file> - Use <file> as artwork instead of looking for common artwork files\n"
	printf "\t-s - convert files sequentially instead of spawning processes\n"
	printf "\t-v - be verbose\n"
	printf "\t-h - print this usage information\n"
	printf "\t-j X - Number of jobs to use\n"
	exit 1
}

function verbose() {
	[[ "${verbose}" ]] && printf "${@}\n"
}

function error() {
	>&2 printf "Fatal: ${@}. Exiting.\n"
	exit 2
}

function installed() {
	local cmd=$(command -v "${1}")

	[[ -n  "${cmd}" ]] && [[ -f "${cmd}" ]]
	return ${?}
}

function find_artfile() {
	local common_files=(cover.{jp{e,}g,png} folder.{jp{e,}g,png})

	for file in "${common_files[@]}"; do
		[[ -f "${dir}/${file}" ]] && { printf "${dir}/${file}" ; return ; }
	done
}

function mp3art() {
	local mp3_file="${1}"

	verbose "Beginning '${mp3_file}."

	"${conv}" -i "${mp3_file}" -i "${artfile}" -map 0:0 -map 1:0 -c copy \
		-id3v2_version 3 -metadata:s:v title="Album cover" -metadata:s:v \
		comment="Cover (Front)" "${mp3_file}.out.mp3" &>/dev/null
	mv -f "${mp3_file}.out.mp3" "${mp3_file}"

	verbose "Completed '${mp3_file}'."
}

[[ "${BASH_VERSINFO[0]}" -lt 4 ]] && error "GNU bash 4.0 or later is required"

shopt -s nullglob
shopt -s globstar

if installed ffmpeg; then
	conv=ffmpeg
elif installed avconv; then
	conv=avconv
else
	error "Could not find either ffmpeg or avconv to encode with"
fi

while getopts ":f:svhj:" opt; do
	case "${opt}" in
		f ) artfile=${OPTARG} ;;
		s ) sequential=1 ;;
		v ) verbose=1 ;;
		j ) njobs=${OPTARG} ;;
		* ) usage ;;
	esac
done

shift $((OPTIND - 1))

if [[ -n "${1}" ]]; then
	dir="${1}"
	[[ ! -d "${dir}" ]] && error "Not a directory: '${dir}'"
else
	dir="."
fi

if [[ -z "${artfile}" ]]; then
	common_files=(cover.{jp{e,}g,png} folder.{jp{e,}g,png})

	for file in "${common_files[@]}"; do
		[[ -f "${dir}/${file}" ]] && { artfile="${dir}/${file}" ; break ; }
	done

	if [[ -z "${artfile}" ]]; then
		error "Could not find an artwork file. Use the -f flag to specify one"
	fi
fi

mp3s=("${dir}"/**/*.mp3)

if [[ "${sequential}" ]]; then
	verbose "Encoding sequentially."

	for file in "${mp3s[@]}"; do
		mp3art "${file}"
	done
else
	verbose "Encoding in parallel."
	if installed "parallel"; then
		export -f mp3art verbose
		export conv
		export artfile
		if [[ -z "${njobs}" ]]; then
			printf '%s\n' "${mp3s[@]}" | parallel -j+0 -q mp3art
		else
			printf '%s\n' "${mp3s[@]}" | parallel -j"${njobs}" -q mp3art
		fi
	else
		verbose "'parallel' is not installed, falling back to forking. Job control will NOT work in this mode."
		for file in "${mp3s[@]}"; do
			mp3art "${file}" &
		done
		wait
	fi
fi

verbose "All done. ${#mp3s[@]} files encoded with artwork."
