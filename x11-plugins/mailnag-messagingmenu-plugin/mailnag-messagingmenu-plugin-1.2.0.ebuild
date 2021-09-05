# Copyright 1999-2021 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

EAPI=7

PYTHON_COMPAT=( python{3_8,3_9} )

inherit distutils-r1 xdg

COMMIT="69f8e5f123643d7fdae28b77afec458ed976b086"
SRC_URI="https://github.com/pulb/mailnag-messagingmenu-plugin/archive/${COMMIT}.tar.gz -> ${P}.tar.gz"
KEYWORDS="~amd64"

DESCRIPTION="Plugin that integrates Mailnag in the MessagingMenu indicator"
HOMEPAGE="https://github.com/pulb/mailnag-messagingmenu-plugin"

LICENSE="GPL-2"
SLOT="0"
IUSE=""
RESTRICT="mirror"

BDEPEND=">=net-mail/mailnag-2.0.0
	unity-indicators/indicator-messages"

RDEPEND="${BDEPEND}"

S="${WORKDIR}/${PN}-${COMMIT}"
