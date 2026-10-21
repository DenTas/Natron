# Profiler l'interface et le viewer de Natron (Windows)

Ce dossier sert à mesurer **où Natron perd son temps** quand l'interface et le
viewer sont lents, avant de changer quoi que ce soit dans le code.

- `build-msys2.sh` : compile Natron (Qt5) et les plug-ins openfx-misc et
  openfx-io sous MSYS2, dans l'environnement **UCRT64**, en `RelWithDebInfo`.
  Avec `--tracy`, Natron est instrumenté pour
  [Tracy](https://github.com/wolfpld/tracy).
- `patches/` : correctifs de compilation des plug-ins. `openfx-io.patch` et
  `openfx-misc.patch` sont repris de
  [Niik-l/Natron](https://github.com/Niik-l/Natron) (`tools/win-build/patches`) ;
  `openfx-io-ffmpeg9.patch` adapte l'écriture vidéo à FFmpeg 9, qui a supprimé
  `AVCodec::pix_fmts`.

Pourquoi UCRT64 et pas MINGW64 (utilisé par la CI Windows) : MSYS2 ne fabrique
plus `pyside2`, `pyside6`, `python-qtpy`, `breakpad`, `openimageio` ni
`opencolorio` pour MINGW64, donc les dépendances de la CI ne s'installent plus.
- `run-msys2.sh` : lance la version compilée avec les bonnes variables
  d'environnement (plug-ins, OCIO, Python).

L'instrumentation est désactivée par défaut (`NATRON_TRACY=OFF`) : sans l'option,
les macros de `Global/Profiling.h` ne génèrent aucun code.

## Test A : sans compiler (Natron 2.5 officiel)

1. Ouvrir un projet lourd (séquence EXR 2K/4K + quelques nœuds).
2. Faire varier le **gain**, le **gamma** et l'**espace couleur** du viewer ;
   noter la réactivité (fluide / saccadé / bloqué N secondes).
3. Lire la séquence et noter les **fps** affichés dans le viewer.
4. *Préférences → Viewer → Viewer textures bit depth* : passer en
   **32 bits flottant**, redémarrer Natron, refaire 2 et 3.

À quoi s'attendre d'après le code :
- en 8 bits (défaut), chaque changement de gain/gamma/espace couleur relance une
  conversion complète de l'image sur le CPU (`ViewerInstance::onGainChanged`…) ;
- en 32 bits, ces réglages sont appliqués par le shader GPU (simple redessin),
  mais chaque image envoyée au GPU pèse 4 fois plus lourd.

## Test B : profilage avec Tracy

### 1. Compiler
Installer [MSYS2](https://www.msys2.org/), ouvrir le shell **MSYS2 UCRT64**
(menu Démarrer ; l'invite doit afficher `UCRT64`), puis :

```bash
git clone https://github.com/DenTas/Natron.git
cd Natron
git checkout claude/gallant-clarke-5rxuav
tools/profiling/build-msys2.sh --tracy
```

La première compilation est longue (téléchargement des dépendances puis plusieurs centaines de fichiers C++).

### 2. Installer l'interface de Tracy
Télécharger l'archive **Windows** de la release
[Tracy v0.11.1](https://github.com/wolfpld/tracy/releases/tag/v0.11.1).
La version doit être **exactement** la même que celle compilée dans Natron
(v0.11.1, fixée dans `CMakeLists.txt`), sinon la connexion est refusée.

### 3. Enregistrer une session
1. Lancer `tracy-profiler.exe` **en administrateur** : c'est nécessaire sous
   Windows pour l'échantillonnage des piles d'appels et des changements de
   contexte, qui couvrent aussi le code non instrumenté.
2. Lancer Natron : `tools/profiling/run-msys2.sh`.
3. Dans Tracy, cliquer sur **Connect** (Natron apparaît dans la liste).
4. Refaire les gestes du test A, en **8 bits puis en 32 bits**, et ajouter ce
   qui te paraît lent dans l'interface (déplacer des nœuds dans le graphe,
   ouvrir un panneau de paramètres, scrubber la timeline…).
5. Arrêter, puis *File → Save trace* (fichier `.tracy`).

### Zones instrumentées

| Zone | Thread | Ce qu'elle mesure |
|---|---|---|
| `ViewerGL::paintGL` (+ marqueur de frame) | principal | un redessin du viewer |
| `ViewerInstance::updateViewer (upload to GPU)` | principal | envoi de l'image rendue au GPU |
| `ViewerGL::transferBufferFromRAMtoGPU` / `memcpy to PBO` | principal | copie de chaque tuile vers le GPU |
| `ViewerGL::endTransferBufferFromRAMToGPU` | principal | fin d'envoi, mise à jour des textures |
| `ViewerInstance::onGainChanged` / `onGammaChanged` / `onColorSpaceChanged` | principal | réaction aux réglages du viewer |
| `ViewerInstance::renderViewer_internal` | rendu | rendu complet d'une image pour le viewer |
| `Viewer tile conversion (scaleToTexture)` | workers | conversion CPU des tuiles (LUT, gain, tramage) |
| `EffectInstance::renderRoI` | rendu | rendu d'un nœud (récursif vers l'amont) |
| `OFX plug-in render` (+ ID du plug-in) | rendu | temps passé dans un plug-in OpenFX |

Tout ce qui bloque le **thread principal** se traduit directement par une
interface qui ne répond plus.

## Quoi me renvoyer
- Les fichiers `.tracy` (un en 8 bits, un en 32 bits si possible).
- Les notes du test A (réactivité, fps).
- La résolution et le format des images du projet, et l'emplacement des
  fichiers : **disque dur ou SSD** (Gestionnaire des tâches → Performance →
  Disque l'indique).

## Limites connues
- Je n'ai pas pu tester `build-msys2.sh` sous Windows : il reproduit les étapes
  de la CI Windows, mais si une étape échoue, envoie-moi la sortie.
- La compilation de Tracy avec MinGW n'a pas été vérifiée sous Windows (seulement
  sous Linux).
