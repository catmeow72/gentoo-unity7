#!/bin/bash

color_blink=$(tput blink)
color_blue=$(tput bold; tput setaf 4)
color_cyan=$(tput setaf 6)
color_green=$(tput bold; tput setaf 2)
color_norm=$(tput sgr0)
color_red=$(tput bold; tput setaf 1)
color_yellow=$(tput bold; tput setaf 3)

einfo() {
	echo " ${color_green}*${color_norm} $*"
}

ewarn() {
	echo " ${color_yellow}*${color_norm} $*"
}

eerror() {
	echo " ${color_red}*${color_norm} $*"
}

get_subdirs() {
	local prev_shopt=$(shopt -p nullglob)
	shopt -s nullglob
	local -a result=( "$1"profiles/ehooks/$2 )
	${prev_shopt}

	echo "${result[@]}"
}

get_repo_root() {
	echo $(/usr/bin/portageq get_repo_path / gentoo-unity7)
}

get_ehooks_subdirs() {
	local \
		repo_root=$(get_repo_root) \
		wildcard="*/*/"

	local -a \
		helper=( "n" ) \
		result

	while [[ -n ${helper[@]} ]]; do
		helper=( $(get_subdirs "${repo_root}/" "${wildcard}") )
		result+=( "${helper[@]}" )
		wildcard+="*/"
	done
	echo "${result[@]}"
}

get_installed_packages() {
	local \
		prev_shopt=$(shopt -p nullglob) \
		sys_db="/var/db/pkg"

	local -a result

	shopt -s nullglob ## don't use extglob
	[[ -d ${sys_db}/$1 ]] && result=( "${sys_db}/$1" ) || result=( "${sys_db}/$1"{-[0-9],.[0-9],-r[0-9]}*/ )
	${prev_shopt}
	echo "${result[@]}"
}

get_slot() {
	[[ $1 == *":"+([0-9.]) ]] && echo "${1##*:}" || echo ""
}

find_flag_changes() {
	local \
		reset="$1" \
		sys_db="/var/db/pkg/" \
		ts_file="/etc/ehooks/timestamps" \
		flag line n sys_date ts x

	local -a result

	while read -r line; do
		[[ ${line} == "##"* ]] && continue
		x="${line%%|*}"
		flag=$(echo "${line}" | cut -d "|" -f 2)
		portageq has_version / unity-extra/ehooks["${flag}"] \
			&& ts=$(echo "${line}" | cut -d "|" -f 3) \
			|| ts=$(echo "${line}" | cut -d "|" -f 4)
		slot=$(get_slot "${x}")

		pkg=( $(get_installed_packages "${x%:*}") )
		for n in "${pkg[@]}"; do
			## Try another package if slots differ.
			[[ -z ${slot} ]] || grep -Fqsx "${slot}" "${n}/SLOT" || continue

			## Try another package if modification time is newer or equal to ehooks USE flag change time.
			sys_date=$(date -r "${n}" "+%s")
			[[ ${sys_date} -ge ${ts} ]] && continue

			## Set USE flag change time equal to package's time when --reset option given.
			if [[ -n ${reset} ]]; then
				if portageq has_version / unity-extra/ehooks["${flag}"]; then
					sed -i -e "/${x/\//\\/}|${flag}/{s/|[0-9]\{10\}|/|${sys_date}|/}" "${ts_file}" 2>/dev/null && reset="applied" && continue
				else
					sed -i -e "/${x/\//\\/}|${flag}/{s/|[0-9]\{10\}$/|${sys_date}/}" "${ts_file}" 2>/dev/null && reset="applied" && continue
				fi
			fi
			## Get ownership of file when 'touch: cannot touch "${x}": Permission denied' and quit.
			[[ -n ${reset} ]] && reset=$(stat -c "%U:%G" "${ts_file}") && break 2

			## Get =${CATEGORY}/${PF} from package's ${sys_db} path.
			n="${n%/}"
			n="${n#${sys_db}}"
			result+=( "=${n}" )
		done
	done < "${ts_file}"
	[[ -n ${reset} ]] && echo "${reset}" || echo "${result[@]}"
}

find_tree_changes() {
	local \
		reset="$1" \
		sys_db="/var/db/pkg/" \
		f m n x

	local -a \
		subdirs=( $(get_ehooks_subdirs) ) \
		flags result

	for x in "${subdirs[@]}"; do
		## Get ${CATEGORY}/{${P}-${PR},${P},${P%.*},${P%.*.*},${PN}} from ehooks' path.
		m=${x%%/files/*}
		m=${m%/}
		m=${m#*/ehooks/}
		slot=$(get_slot "${m}")
		m="${m%:*}"

		pkg=( $(get_installed_packages "${m}") )
		for n in "${pkg[@]}"; do
			## Try another package if slots differ.
			[[ -z ${slot} ]] || grep -Fqsx "${slot}" "${n}/SLOT" || continue

			## Try another package if modification time is newer or equal to ehooks (sub)directory time.
			sys_date=$(date -r "${n}" "+%s")
			[[ ${sys_date} -ge $(date -r "${x}" "+%s") ]] && continue

			## Try another package if ehooks_{require,use} flag is not declared.
			flags=( $(grep -Ehos "ehooks_(require|use)\s[A-Za-z0-9+_@-]+" "${x%%/files/*}/"*.ehooks) )
			if [[ -n ${flags[@]} ]]; then
				flags=( ${flags[@]/ehooks_require} ); flags=( ${flags[@]/ehooks_use} )
				for f in "${flags[@]}"; do
					portageq has_version / unity-extra/ehooks["${f}"] && break
					[[ ${f} == ${flags[-1]} ]] && continue 2
				done
			fi

			## Set ehooks' modification time equal to package's time when --reset option given.
			[[ -n ${reset} ]] && touch -m -t $(date -d @"${sys_date}" +%Y%m%d%H%M.%S) "${x}" 2>/dev/null && reset="applied" && continue
			## Get ownership of file when 'touch: cannot touch "${x}": Permission denied' and quit.
			[[ -n ${reset} ]] && reset=$(stat -c "%U:%G" "${x}") && break 2

			## Get =${CATEGORY}/${PF} from package's ${sys_db} path.
			n="${n%/}"
			n="${n#${sys_db}}"
			result+=( "=${n}" )
		done
	done
	[[ -n ${reset} ]] && echo "${reset}" || echo "${result[@]}"
}

ehooks_changes() {
	if [[ -n $1 ]] && ( [[ ! -w $(get_repo_root)/profiles/ehooks ]] || [[ ! -w /etc/ehooks/timestamps ]] ); then
		echo
		eerror "Permission denied to apply 'reset'!"
		echo
		exit 1
	fi

	printf "%s" "Looking for ehooks changes${color_blink}...${color_norm}"

	local -a changes=( $(find_tree_changes "$1") $(find_flag_changes "$1") )
	# Remove duplicates.
	changes=( $(printf "%s\n" "${changes[@]}" | sort -u) )

	printf "\b\b\b%s\n\n" "... done!"

	if [[ -z ${changes[@]} ]]; then
		einfo "No rebuild needed"
	elif [[ ${changes[0]} == "="* ]] && ( [[ -z ${changes[1]} ]] || [[ ${changes[1]} == "="* ]] ); then
		ewarn "Rebuild the packages affected by ehooks changes:"
		echo
		ewarn "emerge -av1 ${changes[@]}"
	else
		case ${changes[@]} in
			applied|"applied reset"|"reset applied")
				einfo "Reset applied"
				;;
			reset)
				einfo "Reset not needed"
				;;
			*)
				${changes[@]/applied}; ${changes[@]/reset}
				eerror "Permission denied to apply reset (ownership ${changes[@]})"
				;;
		esac
	fi
	echo
}

find_portage_updates() {
	local \
		pmask="$1/profiles/unity-portage.pmask" \
		tmp_file=ehooks-unmask.tmp \
		line start_reading update x

	local -a result

	## Temporarily Unmask packages maintained via ehooks.
	install -m 666 /dev/null /tmp/"${tmp_file}" || exit 1
	ln -fs /tmp/"${tmp_file}" /etc/portage/package.unmask/0000_"${tmp_file}" || exit 1

	for x in "${pmask[@]}"; do
		while read -r line; do
			[[ -z ${start_reading} ]] && [[ ${line} == *"maintained via ehooks"* ]] && start_reading=yes && continue
			[[ -z ${start_reading} ]] && continue
			[[ -n ${start_reading} ]] && [[ -z ${line} ]] && continue
			[[ -n ${start_reading} ]] && [[ ${line} == "#"* ]] && break
			echo "${line}" > /tmp/"${tmp_file}"
			update=$(equery -q l -p -F '$cpv|$mask2' "${line}" | grep "\[32;01m" | tail -1 | sed "s/|.*$//")
			[[ -n ${update} ]] && result+=( "${line}|${update}" )
		done < "${x}"
		start_reading=""
	done

	## Remove temporary unmask file.
	rm /etc/portage/package.unmask/0000_"${tmp_file}"

	[[ -z ${pmask[@]} ]] && echo "no pmask" || echo "${result[@]}"
}

update_firefox_dep() {
	local old_pkg new_pkg x

	for x in dev-libs/nspr dev-libs/nss; do
		old_pkg="$(grep -F ${x} $1)"; old_pkg="${old_pkg#\~}"; old_pkg="${old_pkg%::gentoo}"
		new_pkg="$(grep -F ${x} $2)"; new_pkg="${new_pkg#*>=}"
		[[ ${old_pkg} != ${new_pkg} ]] && sed -i -e "s:${old_pkg}:${new_pkg}:" "$1" && echo " * ${x}: '${1##*/}' entry... [${color_green}updated${color_norm}]"
	done
}

portage_updates() {
	[[ $(type -P equery) != "/usr/bin/equery" ]] && echo && eerror "'equery' tool from 'app-portage/gentoolkit' package not found!" && echo && exit 1
	[[ ! -w /etc/portage/package.unmask ]] && echo && eerror "Permission denied to perform 'update'!" && echo && exit 1
	[[ -z $1 ]] && [[ ${PWD} == $(get_repo_root) ]] && echo && eerror "Don't run 'update' inside installed repo!" && echo && exit 1
	[[ -z $1 ]] && ! grep -Fq "gentoo-unity7" "${PWD}"/profiles/repo_name 2>/dev/null && echo && eerror "Run 'update' inside dev repo or set path!" && echo && exit 1
	[[ -n $1 ]] && ! grep -Fq "gentoo-unity7" "$1"/profiles/repo_name 2>/dev/null && echo && eerror "$1 is not dev repo path!" && echo && exit 1

	printf "%s" "Looking for gentoo main portage updates${color_blink}...${color_norm}"

	local \
		main_repo="$(/usr/bin/portageq get_repo_path / gentoo)" \
		new_pkg old_pkg release x

	[[ -z $1 ]] && x="${PWD}" || x="$1"
	local -a updates=( $(find_portage_updates "${x}") )

	printf "\b\b\b%s\n\n" "... done!"

	if [[ ${updates[@]} == "no pmask" ]]; then
		eerror "'unity-portage.pmask' file not found"
		echo
	elif [[ -z ${updates[@]} ]]; then
		einfo "No updates found"
		echo
	else
		local pmask="${x}/profiles/unity-portage.pmask"

		# Remove duplicates.
		updates=( $(printf "%s\n" "${updates[@]}" | sort -u) )

		echo " * Updates available:"
		echo
		for x in "${updates[@]}"; do
			## Format: ">old_pkg:slot|new_pkg".
			old_pkg="${x%|*}"; old_pkg="${old_pkg#>}"; old_pkg="${old_pkg%:*}"
			new_pkg="${x#*|}"
			echo " * Update from ${color_bold}${old_pkg}${color_norm} to ${color_yellow}${new_pkg}${color_norm}"
			printf "%s" " * Test command 'EHOOKS_PATH=${pmask%/*}/ehooks ebuild \$(portageq get_repo_path / gentoo)/${new_pkg%-[0-9]*}/${new_pkg#*/}.ebuild clean prepare'${color_blink}...${color_norm}"
			if EHOOKS_PATH="${pmask%/*}/ehooks" ebuild "${main_repo}/${new_pkg%-[0-9]*}/${new_pkg#*/}".ebuild clean prepare 1>/dev/null && sed -i -e "s:${old_pkg}:${new_pkg}:" "${pmask}" 2>/dev/null; then
				printf "\b\b\b%s\n" "... [${color_green}passed${color_norm}]"
				echo " * ${new_pkg%-[0-9]*}: '${pmask##*/}' entry... [${color_green}updated${color_norm}]"
			else
				printf "\b\b\b%s\n" "... [${color_red}failed${color_norm}]"
				echo " * ${new_pkg%-[0-9]*}: '${pmask##*/}' entry... [${color_red}not updated${color_norm}]"
			fi
			[[ ${new_pkg} == "www-client/firefox"* ]] && update_firefox_dep "${pmask/pmask/paccept_keywords}" "${main_repo}/${new_pkg/firefox/firefox\/firefox}.ebuild"
			echo
		done
	fi
}

get_uvers() {
	local ver x y

	local -a result subdirs

	if [[ -n $@ ]]; then
		grep -Fq "gentoo-unity7" "$1"/profiles/repo_name 2>/dev/null && y="$1/" && shift
		for x in "$@"; do
			subdirs+=( $(get_subdirs "${y}" "${x}/*src_unpack.ehooks") )
		done
	fi

	[[ -z $@ ]] && subdirs=( $(get_subdirs "${y}" "*/*/*src_unpack.ehooks") )

	for x in "${subdirs[@]}"; do
		ver=$(grep -o -m 1 "uver=.*" "${x}")
		[[ -n ${ver} ]] && result+=( "${x}|${ver#uver=}" );
	done
	echo "${result[@]}"
}

get_debian_archive() {
	local x

	local -a filenames=( $1.debian.tar.xz $1.debian.tar.gz )

	for x in "${filenames[@]}"; do
		[[ -z $2 ]] && [[ -r /tmp/ehooks-${USER}-${x} ]] && return
		wget -q -T 60 "https://launchpad.net/ubuntu/+archive/primary/+files/${x}" -O "/tmp/${2:-ehooks-${USER}-${x}}" && return
	done

	return 1
}

debian_changes() {
	local x=$1 && shift

	[[ $(type -P equery) != "/usr/bin/equery" ]] && echo && eerror "'equery' tool from 'app-portage/gentoolkit' package not found!" && echo && exit 1
	[[ -z $1 ]] && [[ ${PWD} == $(get_repo_root) ]] && echo && eerror "Don't run 'check' inside installed repo!" && echo && exit 1
	[[ -z $1 ]] && ! grep -Fq "gentoo-unity7" "${PWD}"/profiles/repo_name 2>/dev/null && echo && eerror "Run 'check' inside dev repo or set path!" && echo && exit 1
	[[ -n $1 ]] && ! grep -Fq "gentoo-unity7" "${PWD}"/profiles/repo_name 2>/dev/null && ! grep -Fq "gentoo-unity7" "$1"/profiles/repo_name 2>/dev/null && echo && eerror "Dev repo path not found!" && echo && exit 1

	local -a uvers=( $(get_uvers "$@") )

	if [[ -z ${uvers[@]} ]]; then
		[[ -n $@ ]] && eerror "No package found! Package name must be in format: \${CATEGORY}/\${PN}." || eerror "No package found."
		echo
		exit 1
	fi

	local -a result

	case ${x} in
		-b|--blake)
			printf "%s" "Looking for BLAKE2 checksum changes${color_blink}...${color_norm}"

			local pre_sed pn sum

			for x in "${uvers[@]}"; do
				## Format: "file|uver".
				pn="${x#*ehooks/}"; pn="${pn%/*}"
				if get_debian_archive "${x#*|}" "ehooks-${USER}-debian.tmp"; then
					sum=$(b2sum "/tmp/ehooks-${USER}-debian.tmp" | cut -d ' ' -f 1)
					pre_sed=$(b2sum "${x%|*}")
					sed -i -e "s/blake=[[:alnum:]]*/blake=${sum}/" "${x%|*}"
					[[ ${pre_sed} != $(b2sum "${x%|*}") ]] && result+=( " ${color_green}*${color_norm} ${pn}... ${color_green}checksum updated!${color_norm}" )
				else
					result+=( " ${color_red}*${color_norm} ${pn}... ${color_red}debian file not found!${color_norm}" )
				fi
			done
			;;
		-c|--changes)
			printf "%s" "Looking for available version changes${color_blink}...${color_norm}"

			local \
				releases="impish jammy" \
				sources="main universe" \
				rls frls src

			for rls in ${releases}; do
				for frls in "${rls}" "${rls}"-security "${rls}"-updates; do
					for src in ${sources}; do
						wget -q -T 60 http://archive.ubuntu.com/ubuntu/dists/${frls}/${src}/source/Sources.gz -O /tmp/ehooks-${USER}-sources-${src}-${frls}.gz || exit 1
						gunzip -qf /tmp/ehooks-${USER}-sources-${src}-${frls}.gz || exit 1
					done
				done
			done

			local pn un utd uv

			local -a an auvers result

			for x in "${uvers[@]}"; do
				auvers=()
				un="${x#*|}"
				utd="${color_yellow}${un}${color_norm}"
				for rls in ${releases}; do
					for frls in "${rls}" "${rls}"-security "${rls}"-updates; do
						for src in ${sources}; do
							uv=$(grep -A6 "Package: ${un%_*}$" /tmp/ehooks-${USER}-sources-${src}-${frls} | sed -n 's/^Version: \(.*\)/\1/p' | sed 's/[0-9]://g')
							[[ -n ${uv} ]] && [[ ${uv} != ${pn} ]] && [[ ${uv} != ${un#*_} ]] && auvers+=( "'${uv}'" ) && pn="${uv}"
							[[ ${uv} == ${un#*_} ]] && utd="${color_green}${un}${color_norm}" || an[1]="${color_yellow}[ local package is outdated ]${color_norm}"
						done
					done
				done

				pn="${x#*ehooks/}"; pn="${pn%/*}"
				if [[ -n ${auvers[@]} ]]; then
					result+=( " * $(equery -q l -p -F '$cpv|$mask2' "${pn}" | grep "\[32;01m" | tail -1 | sed "s/|.*$//")... local: ${utd} available: ${auvers[*]}" )
					get_debian_archive "${un}"
					tar --overwrite -xf "/tmp/ehooks-${USER}-${un}.debian.tar.xz" -C /tmp debian/patches/series --strip-components 2 --transform "s/series/ehooks-${USER}-series/"
					auvers=( "${auvers[@]//\'}" )
					for uv in "${auvers[@]}"; do
						get_debian_archive "${un%_*}_${uv}"
						tar --overwrite -xf "/tmp/ehooks-${USER}-${un%_*}_${uv}.debian.tar.xz" -C /tmp debian/patches/series --strip-components 2 --transform "s/series/ehooks-${USER}-aseries/"
						if [[ -n $(diff /tmp/ehooks-${USER}-series /tmp/ehooks-${USER}-aseries) ]]; then
							result[${#result[@]}-1]="${result[${#result[@]}-1]/${uv}/${color_red}${uv}${color_norm}}"
							an[2]="${color_red}[ debian/patches/series file differs from local ]${color_norm}"
						fi
					done
				fi
			done
			;;
	esac
	printf "\b\b\b%s\n\n" "... done!"

	if [[ -n "${result[@]}" ]]; then
		for x in "${result[@]}"; do
			printf "%s\n\n" "${x}"
		done
		for x in "${an[@]}"; do
			printf "%s\n" "${x}"
		done
		[[ -n ${an[@]} ]] && echo
	else
		einfo "No changes found"
		echo
	fi
}

case $1 in
	-g|--generate)
		ehooks_changes
		;;
	-r|--reset)
		ehooks_changes "reset"
		;;
	-u|--update)
		portage_updates "$2"
		;;
	-b|--blake|-c|--changes)
		debian_changes "$@"
		;;
	*)
		echo "${color_blue}NAME${color_norm}"
		echo "	ehooks_version_control.sh"
		echo
		echo "${color_blue}SYNOPSIS${color_norm}"
		echo "	${color_blue}ehooks${color_norm} [${color_cyan}OPTION${color_norm}]"
		echo
		echo "${color_blue}DESCRIPTION${color_norm}"
		echo "	ehooks version control tool."
		echo
		echo "	/usr/bin/${color_blue}ehooks${color_norm} is a symlink to gentoo-unity7/ehooks_version_control.sh script."
		echo
		echo "${color_blue}OPTIONS${color_norm}"
		echo "	${color_blue}-g${color_norm}, ${color_blue}--generate${color_norm}"
		echo "		It looks for ehooks changes and generates emerge command needed to apply the changes."
		echo
		echo "	${color_blue}-r${color_norm}, ${color_blue}--reset${color_norm}"
		echo "		It looks for ehooks changes and set them as applied (it resets modification time)."
		echo
		echo "	${color_blue}-u${color_norm}, ${color_blue}--update${color_norm} [${color_cyan}$(tput smul)repo path$(tput rmul)${color_norm}]"
		echo "		It looks for Gentoo tree updates and refreshes unity-portage.pmask version entries (it needs temporary access to /etc/portage/package.unmask)."
		echo
		echo "	${color_blue}-b${color_norm}, ${color_blue}--blake${color_norm} [${color_cyan}$(tput smul)repo path$(tput rmul)${color_norm}] [${color_cyan}$(tput smul)packages$(tput rmul)${color_norm}]"
		echo "		It updates BLAKE2 checksum of debian archive file in {pre,post}_src_unpack.ehooks."
		echo
		echo "	${color_blue}-c${color_norm}, ${color_blue}--changes${color_norm} [${color_cyan}$(tput smul)repo path$(tput rmul)${color_norm}] [${color_cyan}$(tput smul)packages$(tput rmul)${color_norm}]"
		echo "		It looks for available version changes of debian archive file."
		echo
		exit 1
esac
