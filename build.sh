#!/usr/bin/env bash
# Usage: ./build.sh            build dist/DKRadio-<version>.zip and dist/repo.xml
#        ./build.sh --release  also publish GitHub release plugin-v<version> and update ./repo.xml
set -euo pipefail
cd "$(dirname "$0")"

GH_REPO="macsatcom/lyrion-dansk-radio"
VERSION=$(sed -n 's:.*<version>\(.*\)</version>.*:\1:p' Plugins/DKRadio/install.xml)
ZIP="DKRadio-${VERSION}.zip"
TAG="plugin-v${VERSION}"

prove -I. t/

rm -rf dist && mkdir dist
(cd Plugins/DKRadio && zip -qr "../../dist/${ZIP}" . -x '*.swp')
SHA=$(sha1sum "dist/${ZIP}" | cut -d' ' -f1)

cat > dist/repo.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<extensions>
	<details>
		<title lang="EN">DK Radio repository</title>
	</details>
	<plugins>
		<plugin name="DKRadio" version="${VERSION}" minTarget="8.0" maxTarget="*" category="radio">
			<title lang="EN">DK Radio</title>
			<title lang="DA">DK Radio</title>
			<desc lang="EN">All Danish radio stations from radio.dk</desc>
			<desc lang="DA">Alle danske radiostationer fra radio.dk</desc>
			<link>https://github.com/macsatcom/lyrion-dansk-radio</link>
			<creator>Kasper S Nielsen</creator>
			<creatorEmail>kasper@smsweb.dk</creatorEmail>
			<url>https://github.com/${GH_REPO}/releases/download/${TAG}/${ZIP}</url>
			<sha>${SHA}</sha>
		</plugin>
	</plugins>
</extensions>
EOF

echo "Built dist/${ZIP} (sha1 ${SHA}) and dist/repo.xml"

if [[ "${1:-}" == "--release" ]]; then
	if gh release view "$TAG" -R "$GH_REPO" >/dev/null 2>&1; then
		echo "Release $TAG already exists - bump <version> in install.xml first" >&2
		exit 1
	fi
	gh release create "$TAG" "dist/${ZIP}" -R "$GH_REPO" --title "DK Radio ${VERSION}" --notes "DK Radio plugin ${VERSION}"
	cp dist/repo.xml repo.xml
	echo "Released $TAG. Commit and push repo.xml to publish it to Lyrion."
fi
