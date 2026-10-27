# OutilScan

Application macOS (Apple Silicon) pour numériser avec des **Fujitsu ScanSnap S1500 et S1300**, en recto ou en recto verso, vers un PDF multipage avec OCR.

ScanSnap Home ne prend pas en charge ces modèles : l'app les pilote via le pilote libre **SANE** (backend `fujitsu` pour le S1500, `epjitsu` pour le S1300). Elle lit les capacités de chaque scanner (résolutions, modes, redressement) et n'affiche que les réglages qu'il accepte. Si plusieurs scanners sont branchés, un menu permet de choisir.

## Pilotes

| Scanner | Pilote SANE | Fichier supplémentaire |
|---|---|---|
| ScanSnap S1500 / S1500M | `fujitsu` | aucun |
| ScanSnap S1300 | `epjitsu` | firmware `1300_0C26.nal` |

Le pilote SANE s'installe avec Homebrew (voir *Installation*).

### Firmware du S1300

Le S1300 doit recevoir un firmware Fujitsu, `1300_0C26.nal`, à chaque mise sous tension. **Ce fichier appartient à Fujitsu/PFU : il n'est pas fourni avec SANE ni dans ce dépôt, et ne peut pas y être ajouté.** PFU a cessé de distribuer ScanSnap Manager le 7 novembre 2024 et les anciens liens de téléchargement ne fonctionnent plus.

Où le trouver :
- sur le **CD-ROM** livré avec le scanner (fichier contenu dans l'installateur ScanSnap Manager) ;
- sur un **PC Windows** où ScanSnap Manager est installé : `C:\Windows\twain_32\ScanSnap\1300_0C26.nal` (ou chercher `*.nal`) ;
- dans un ancien installateur **ScanSnap Manager pour S1300** (`WinS1300ManagerV55L10WW.exe` ou version voisine) que vous auriez conservé ; le fichier s'extrait sans exécuter l'installateur, par exemple avec `unshield` (`brew install unshield`).

Quand OutilScan détecte un S1300 sans firmware, le bouton **Importer le firmware…** copie le fichier au bon endroit et en garde une sauvegarde : après un `brew upgrade`, l'app le réinstalle toute seule.

## Installation

```bash
brew install sane-backends
./build-app.sh --install
```

Le script compile avec les seuls Command Line Tools (Xcode n'est pas nécessaire) et copie `OutilScan.app` dans `/Applications`.

Pour installer sur un autre Mac, `./make-dmg.sh` crée `build/OutilScan-<version>.dmg` (l'app, un raccourci vers Applications et un mode d'emploi). L'app n'a qu'une signature ad hoc : sur un autre Mac, il faut l'ouvrir la première fois par clic droit > Ouvrir.

## Utilisation

1. Brancher le scanner en USB et ouvrir le capot (il s'allume).
2. Choisir recto / recto verso, couleur, résolution, format ; redressement, nettoyage du fond et pages blanches se règlent dans la barre latérale.
3. **Numériser** (⌘N) — un nouveau passage ajoute les pages à la suite. Chaque page est redressée et nettoyée (ombres du pli, transparence du verso) dès qu'elle arrive.
4. Réorganiser par glisser-déposer, pivoter ou supprimer (survol ou clic droit) ; double-clic pour agrandir et parcourir les pages avec ← →.
5. **Enregistrer le PDF** (⌘S) : le nom `AAMMJJ-EMETTEUR-Intitule` (par ex. `261012-CHULILLE-Facture-Soins`) est proposé d'après le contenu du document, par Apple Intelligence sur le Mac (macOS 26+) ou par des règles simples. Les corrections sont mémorisées. Le PDF contient le texte reconnu (OCR français, néerlandais, anglais, allemand).

Si le scanner n'est pas trouvé : quitter ScanSnap Home et VueScan (un seul logiciel peut l'utiliser à la fois), puis cliquer sur Actualiser. En ligne de commande : `scanimage -L`.

## Développement

- `swift build` — compiler
- `swift run OutilScan` — lancer l'app sans paquet
- `swift run OutilScanSelfTest` — tests (XCTest et Swift Testing exigent Xcode, d'où cet exécutable)
- `swift run OutilScanSelfTest --analyze fichier.pdf` — rejoue la proposition de nom sur un PDF
- `./make-dmg.sh` — crée l'image disque d'installation

Avec le SDK macOS 27, `@State` est une macro dont le plugin n'est livré qu'avec Xcode : les vues utilisent l'alias `@ViewState` (voir `Sources/OutilScan/ViewState.swift`).

## Licence

Code publié sous licence [MIT](LICENSE). SANE, Homebrew et le firmware Fujitsu restent soumis à leurs propres licences.
