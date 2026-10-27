#!/bin/zsh
# Crée build/OutilScan-<version>.dmg : l'app, un raccourci vers Applications et un mode d'emploi.
# Usage : ./make-dmg.sh
set -euo pipefail
cd "$(dirname "$0")"

./build-app.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" build/OutilScan.app/Contents/Info.plist)
DMG="build/OutilScan-${VERSION}.dmg"
STAGING="$(mktemp -d)/OutilScan"
mkdir -p "$STAGING"

cp -R build/OutilScan.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/À LIRE - Installation.txt" <<'TXT'
OutilScan — numérisation pour Fujitsu ScanSnap S1500 et S1300
==============================================================

1. INSTALLER L'APPLICATION
   Glissez OutilScan sur le dossier Applications.

2. PREMIER LANCEMENT
   L'application n'est pas signée par un développeur Apple identifié.
   Sur un autre Mac que celui où elle a été créée, macOS peut refuser de l'ouvrir :
   - clic droit (ou Ctrl-clic) sur OutilScan dans Applications > Ouvrir > Ouvrir ;
   - ou Réglages Système > Confidentialité et sécurité > « Ouvrir quand même ».

3. INSTALLER LE PILOTE DE SCANNER (SANE), une seule fois
   Dans le Terminal (Homebrew requis, voir https://brew.sh) :
       brew install sane-backends

4. SCANSNAP S1300 UNIQUEMENT
   Le S1300 a besoin du fichier firmware Fujitsu 1300_0C26.nal (non fourni).
   Au premier branchement, OutilScan propose « Importer le firmware… » :
   choisissez ce fichier, l'application l'installe et en garde une copie.

5. UTILISATION
   Branchez le scanner, ouvrez son capot, lancez OutilScan.
   ⌘N : numériser   ⌘S : enregistrer le PDF (nom proposé automatiquement)

Configuration requise : Mac Apple Silicon, macOS 14 ou plus récent.
Nommage par Apple Intelligence : macOS 26 ou plus récent avec Apple Intelligence activé
(sinon, des règles simples prennent le relais).
TXT

rm -f "$DMG"
hdiutil create -volname "OutilScan ${VERSION}" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$(dirname "$STAGING")"
echo "✔ Image disque créée : $PWD/$DMG"
