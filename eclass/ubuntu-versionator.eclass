# Copyright 1999-2022 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

# @ECLASS: ubuntu-versionator.eclass
# @MAINTAINER: c4pp4
# @AUTHOR: c4pp4
# @SUPPORTED_EAPIS: 6 7
# @BLURB: Provides phases for Ubuntu based packages.
# @DESCRIPTION:
# Exports portage base functions used by ebuilds written for packages using
# the gentoo-unity7 framework.

# @ECLASS-VARIABLE: UBUNTU_EAUTORECONF
# @DEFAULT_UNSET
# @DESCRIPTION:
# Run eautoreconf
UBUNTU_EAUTORECONF=${UBUNTU_EAUTORECONF:-""}

[[ ${UBUNTU_EAUTORECONF} == "yes" ]] && inherit autotools

case "${EAPI:-0}" in
	6|7) EXPORT_FUNCTIONS pkg_setup src_prepare pkg_postinst ;;
	*) die "EAPI=${EAPI:-0} is not supported" ;;
esac

# Used by unity-base/unity-control-center, unity-base/unity-language-pack,
# unity-extra/unity-greeter
URELEASE="21.10 Impish"

# Set base sane vala version for all packages requiring vala, override
# in ebuild if or when specific higher/lower versions are needed
VALA_MIN_API_VERSION=${VALA_MIN_API_VERSION:-0.52}
VALA_MAX_API_VERSION=${VALA_MAX_API_VERSION:-0.52}

# Ubuntu delete superceded release tarballs from their mirrors if the release
# is not Long Term Supported (LTS). Download tarballs from the always available
# Launchpad archive
UURL="https://launchpad.net/ubuntu/+archive/primary/+files/${PN}_${PV}${UVER}"

# Default variables
SRC_URI="${UURL}.orig.tar.gz"
RESTRICT="mirror"

# @FUNCTION: einstalldocs
# @DESCRIPTION:
# Based on eutils.eclass' function. Install documentation using DOCS
# including COPYING* files. Inherit values if DOCS is declared.
einstalldocs() {
	debug-print-function ${FUNCNAME} "${@}"

	local x
	local -aI DOCS
	for x in README* ChangeLog AUTHORS NEWS TODO CHANGES \
		THANKS BUGS FAQ CREDITS CHANGELOG COPYING*; do
		if [[ -s ${x} ]] ; then
			DOCS+=( "${x}" )
		fi
	done

	if [[ -n ${DOCS[@]} ]]; then
		dodoc -r "${DOCS[@]}" || die
	fi

	return 0
}

# @FUNCTION: ubuntu-versionator_pkg_setup
# @DESCRIPTION:
# Check we have a valid profile set
# and apply python-single-r1_pkg_setup if declared.
ubuntu-versionator_pkg_setup() {
	debug-print-function ${FUNCNAME} "$@"

	[[ -n ${CURRENT_PROFILE} ]] && [[ ${CURRENT_PROFILE} == *"${REPO_ROOT}"* ]] \
		|| die "Invalid profile detected, please select gentoo-unity7 profile shown in 'eselect profile list'."

	declare -F python-single-r1_pkg_setup 1>/dev/null && python-single-r1_pkg_setup
}

# @FUNCTION: ubuntu-versionator_src_prepare
# @DESCRIPTION:
# Apply common src_prepare tasks such as patching and vala setting.
# Apply {xdg,gnome2,distutils-r1,cmake-utils}_src_prepare functions
# if declared or only apply default.
ubuntu-versionator_src_prepare() {
	debug-print-function ${FUNCNAME} "$@"

	local \
		color_bold=$(tput bold) \
		color_norm=$(tput sgr0) \
		x

	# Apply Ubuntu diff file if present #
	local diff_file="${WORKDIR}/${PN}_${PV}${UVER}-${UREV}.diff"
	if [[ -f ${diff_file} ]]; then
		echo "${color_bold}>>> Processing Ubuntu diff file${color_norm} ..."
		eapply "${diff_file}"
		echo "${color_bold}>>> Done.${color_norm}"
	fi

	# Apply Ubuntu patchset if one is present #
	local upatch_dir
	local -a upatches
	[[ -f ${WORKDIR}/debian/patches/series ]] && upatch_dir="${WORKDIR}/debian/patches"
	[[ -f debian/patches/series ]] && upatch_dir="debian/patches"
	if [[ -d ${upatch_dir} ]]; then
		for x in $(grep -v \# "${upatch_dir}/series"); do
			upatches+=( "${upatch_dir}/${x}" )
		done
	fi
	if [[ -n ${upatches[@]} ]]; then
		echo "${color_bold}>>> Processing Ubuntu patchset${color_norm} ..."
		eapply "${upatches[@]}"
		echo "${color_bold}>>> Done.${color_norm}"
	fi

	if declare -F vala_src_prepare 1>/dev/null; then
		vala_src_prepare
		export VALA_API_GEN="${VAPIGEN}"
	fi

	unset x
	if declare -F gnome2_src_prepare 1>/dev/null; then
		gnome2_src_prepare
		x="1"
	elif declare -F xdg_src_prepare 1>/dev/null; then
		xdg_src_prepare
		x="1"
	fi
	if declare -F distutils-r1_src_prepare 1>/dev/null; then
		distutils-r1_src_prepare
		x="1"
	fi
	if declare -F cmake-utils_src_prepare 1>/dev/null; then
		cmake-utils_src_prepare
		x="1"
	fi
	[[ -z ${x} ]] && default

	[[ ${UBUNTU_EAUTORECONF} == 'yes' ]] && eautoreconf
}

# @FUNCTION: ubuntu-versionator_pkg_postinst
# @DESCRIPTION:
# Apply {gnome2,xdg}_pkg_postinst function if declared and re-create
# bamf-2.index file of every package to capture all *.desktop files.
ubuntu-versionator_pkg_postinst() {
	debug-print-function ${FUNCNAME} "$@"

	if declare -F gnome2_pkg_postinst 1>/dev/null; then
		gnome2_pkg_postinst
	elif declare -F xdg_pkg_postinst 1>/dev/null; then
		xdg_pkg_postinst
	fi

	if [[ -x /usr/bin/bamf-index-create ]]; then
		einfo "Checking bamf-2.index"
		/usr/bin/bamf-index-create triggered
	fi
}
