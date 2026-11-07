#!/usr/bin/env bash
# Usage: BASE_URL=https://example.org/dkradio ./build.sh
# Produces dist/DKRadio-<version>.zip and dist/repo.xml pointing at BASE_URL.
set -euo pipefail
cd "$(dirname "$0")"

: "${BASE_URL:?Set BASE_URL to where the zip will be hosted}"
VERSION=$(sed -n 's:.*<version>\(.*\)</version>.*:\1:p' Plugins/DKRadio/install.xml)
ZIP="DKRadio-${VERSION}.zip"

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
			<url>${BASE_URL}/${ZIP}</url>
			<sha>${SHA}</sha>
		</plugin>
	</plugins>
</extensions>
EOF

echo "Built dist/${ZIP} (sha1 ${SHA}) and dist/repo.xml"
