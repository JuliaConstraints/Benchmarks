# Fonctions ICN, threads et portefeuilles MetaStrategist

Protocole fixé le 4 octobre 2026 avant observation des résultats. Cette campagne
corrige l'absence d'ICN du pilote précédent, puis examine la qualité à budget
mural égal et le parallélisme effectif. Corpus diagnostic déjà exposé : lc101,
lr101 et lrc101, 106 visites et 53 requêtes chacun. Aucun concurrent commercial
ni corpus de confirmation n'est inclus.

## Fonctions d'erreur réellement exécutées

La banque privée ConstraintLearningBenchmarks contient 145 témoins construits
dans une grammaire apprenable. Ce pilote ne prétend pas qu'ils proviennent tous
d'une campagne d'apprentissage automatique. Les témoins 4 (sum, condition
scalaire), 2 (allEqual) et 52 (ordered strict) sont reconstruits par les
constructeurs normaux CompositionalNetworks, leurs schémas et poids sont
contrôlés, puis leurs décodeurs sont appelés pendant la recherche.

Les temps et charges cumulées sont des vues dérivées des routes. Les ICN évaluent
les contraintes de flotte, de fenêtres temporelles continues, de charges aux
préfixes et au retour, d'appartenance des paires à une même route et de précédence
stricte. Les temps ne sont pas discrétisés. Le décodeur de successeurs garde
le contrôle structurel d'unicité de service et de cycles déconnectés ; ce bloc
est explicite, sans revendication d'apprentissage. Le validateur du problème
original reste indépendant.

Les trois erreurs sont : un indicateur global d'infaisabilité naïf ; les fonctions
ICN récupérées ; le score direct de la première campagne. Sur les vues qualifiées,
ICN et direct ont la même valeur numérique. Cette ablation mesure leur exécution
et son coût, pas un paysage appris différent. Le contrôleur reste principalement
dans les solutions faisables avec des réinsertions de requêtes complètes ; la
diversification guidée à travers l'infaisabilité n'est pas ajoutée implicitement.
Les décodeurs sont préparés avant l'échauffement ; les modèles, états et
compteurs sont propres à chaque trajectoire. Aucun compteur ICN fictif n'est
attribué aux variantes directes ou à HiGHS.

## Ressources et budgets

Budget par essai : 10 secondes, trois graines 41/42/43, mêmes instances et même
initialisation par cinq insertions (graine 41). Lecture, insertion, construction
des modèles, préparation du plan et validation des améliorations comptent dans
ce budget. Chargement des packages, décodage des poids fixes et échauffement sont
rapportés séparément. La validation finale et la fusion ont leur temps publié.
Les observations des trajectoires sont datées après validation et censurées
au budget ; la fusion reconstitue le meilleur disponible, sans prétendre à un
échange d'incumbents en ligne.

L'i7-12700 possède 8 cœurs P avec SMT et 4 cœurs E, soit 20 CPU logiques. L'ordre
des CPU est [8,10,0,2,4,6,12,14,16,17,18,19,9,11,1,3]. Les allocations 1/2/4/8
utilisent des cœurs P distincts ; 16 ajoute les 4 cœurs E et 4 frères SMT. Cela
interdit d'interpréter une mauvaise efficacité à 16 comme un pur problème du
solveur. L'affinité est contrôlée. Un processus par largeur, campagnes séquentielles,
Julia exactement N threads de calcul, aucun thread interactif, GC et BLAS/OMP
à un thread. Plafond mémoire : 12 GiB, garde par essai : 120 secondes.

CBLS et les hybrides exécutent N trajectoires série indépendantes, chacun avec
son état, son RNG et son budget mural commun ; HiGHS dans les fragments reste
à un thread. Il s'agit de recherche parallèle par diversification et fusion du
meilleur incumbent, pas d'évaluation parallèle d'un seul voisinage. Les graines
des voies sont seed + 10000*(voie-1). HiGHS natif reçoit threads=N et parallel=on.
Le benchmark utilise l'API native LocalSearchSolvers, moteur de CBLS ; le coût
de traduction de la façade JuMP/MOI de CBLS n'est pas mesuré dans ces profils.
Une référence supplémentaire exécute N modèles HiGHS série indépendants, pour
distinguer ce mode de son parallélisme natif. Le scheduler global HiGHS est remis
à zéro seulement après la jonction complète des travailleurs du précédent essai.

La mesure publie les identifiants des threads Julia et OS, le temps CPU par
travailleur, le temps CPU total du processus et son rapport au temps mural.
Les threads alloués ne sont jamais assimilés à une utilisation constante. Les
logs natifs HiGHS sont conservés. Le parallélisme HiGHS dépend du modèle et des
phases exécutées, comme le précise sa
[documentation v1.15.1](https://github.com/ERGO-Code/HiGHS/blob/v1.15.1/docs/src/parallel.md).

## Plans MetaStrategist exécutés

Le plan est résolu par PhaseCatalog/StrategyProfile/resolve_strategy, préparé par
prepare_strategy(mode=:typed), puis réellement exécuté par execute!. Son empreinte
est publiée. L'adaptateur de benchmark fournit la phase parallèle et l'agrégation
indépendante ; le package ne reçoit pas une orchestration adaptative fictive.

| Plan | 4 threads | 8 threads | 16 threads |
|---|---|---|---|
| Équilibré | 1/1/1/1 | 2/2/2/2 | 4/4/4/4 |
| Priorité recherche locale | 2/1/0/1 | 4/2/1/1 | 8/4/3/1 |

Ordre des colonnes dans chaque allocation : CBLS ICN, hybride spécialisé ICN,
hybride bridgé ICN, HiGHS série. Allocation statique, sans échange d'incumbents
ni réallocation adaptative dans cette première passe. Le plan priorisant la
recherche locale est choisi avant la campagne, sans sélection après résultats.

Sept profils homogènes × cinq largeurs × trois instances × trois graines = 315
essais. Deux plans mixtes × trois largeurs × trois instances × trois graines =
54 essais. Total : 369, environ 61,5 minutes de budget mural, plus préparation.
Ordre cyclique des méthodes fixé par instance et répétition.
Les comparaisons appariées classent d'abord la flotte ; à flotte égale, une
différence absolue de distance inférieure ou égale à 1e-6 est une égalité, pour
éviter d'attribuer des gains aux seuls arrondis flottants.

## Reproduire et sauvegarder

L'environnement solveur qualifié reste ConstraintModels/perf/pdptw ; la version
exacte des packages, ses deux empreintes et les empreintes des sources, instances
et de la banque sont contrôlées. Le lanceur refuse les modifications non commises
du périmètre mesuré. Utiliser `OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1` et Julia
`--startup-file=no --compiled-modules=existing -O1 --threads=1,0 --gcthreads=1`,
avec ce projet et le lanceur `scripts/icn_threads.jl campaign`.

Après une interruption, `check-resume <répertoire>` vérifie les empreintes du
protocole, des sources de solveur et de chaque résultat scellé. `resume
<répertoire>` reprend uniquement les essais sans résultat, dans l'ordre initial.
Les anciens résultats, marqueurs et temps de préparation restent intacts ; les
nouveaux temps de préparation, logs et empreintes du contrôleur de reprise sont
conservés dans `resumptions/<identifiant>`. Chaque nouveau résultat est rattaché
à ce segment. Les sources de solveur doivent rester identiques à la campagne
initiale ; seul le contrôleur de reprise peut évoluer. Une reprise temporelle
reste déclarée dans le bilan, même lorsque le protocole est inchangé.

Les traces complètes sont dans data/thread-pilots. Le bilan conserve les résultats,
routes et trajectoires essentiels avec les empreintes des traces. Les sources,
protocole, décisions, résultats essentiels et graphiques sont commis et poussés
sur GitLab privé. Les graphiques Julia utilisent un environnement indépendant
plotting/Project.toml et son Manifest, sans changer les versions des solveurs.
La sortie XKCD est une illustration secondaire ; les figures sobres conservent
des coordonnées exactes pour une utilisation scientifique.

Après livraison des essais et figures, mesurer les coûts de chargement, JIT,
préparation des plans et construction des sous-modèles séparément. Étudier la
réutilisation d'un workspace par travailleur pour CBLS, MetaStrategist et les
réparations HiGHS ; vérifier l'isolation des états et l'identité des résultats
avant d'en déduire une réduction de temps de préparation.

## Résultats du 4 octobre 2026

Les 369 essais ont été terminés et leurs routes et événements revérifiés dans
le problème original. Le bilan déclare la reprise de 11 essais après une pause,
les 166 700 484 120 appels ICN, les attributions de threads et les limites du
modèle HiGHS de référence. Les sources de solveur sont celles du commit
`43852f287d5246df77a2db599aca218ea70817d0` ; le contrôleur de reprise est séparé.

- [Bilan détaillé](results/icn-threads-20261004.md) et
  [résultats essentiels reproductibles](results/icn-threads-20261004.toml).
- [Qualité](results/figures-20261004/icn-threads-quality.png),
  [utilisation CPU](results/figures-20261004/icn-threads-cpu.png),
  [débit](results/figures-20261004/icn-threads-throughput.png) et
  [illustration XKCD](results/figures-20261004/icn-threads-xkcd.png).
- Les quatre figures sont aussi fournies en PDF dans le même répertoire.

L'hybride spécialisé améliore CBLS ICN dans 23/45 comparaisons appariées, fait
égalité dans 18 et recule dans 4. Sur lrc101, sa flotte médiane passe de 17 à 16
véhicules dès quatre threads, contre 19 pour cette référence HiGHS. Sur lr101,
HiGHS multi-départ atteint 19/1650,799 dès deux threads et demeure compétitif.
CBLS ICN/direct/naïf produisent les mêmes qualités dans leurs 45 cellules
appariées. Ces observations sur trois instances exposées ne constituent pas
une comparaison commerciale ni une mesure de généralisation.

Les figures de réussite ajoutées ensuite emploient des cibles descriptives
[SINTEF](https://www.sintef.no/projectweb/top/pdptw/100-customers/), vérifiées le
4 octobre, et conservées dans [diagnostic-targets.toml](config/diagnostic-targets.toml).
La distance de référence est publiée arrondie ; les distances mesurées restent
en double précision. Le léger écart visuel sur LC101 est celui de cet arrondi.
Ces cibles ne deviennent pas rétroactivement un test de confirmation annoncé.

- [Réussite](results/figures-20261004/icn-threads-success.png) et
  [version XKCD](results/figures-20261004/icn-threads-success-xkcd.png).
- [Progression à 8 threads](results/figures-20261004/icn-threads-anytime.png) et
  [version XKCD avec références](results/figures-20261004/icn-threads-anytime-xkcd.png).
- [Temps pour atteindre la cible](results/figures-20261004/icn-threads-time-to-target.png)
  et [version XKCD](results/figures-20261004/icn-threads-time-to-target-xkcd.png).

La réussite à dix secondes classe la flotte avant la distance ; le second rang
de la figure montre l'amélioration du départ commun. Les courbes temporelles
reconstituent les découvertes privées validées des voies, avec une fusion finale.
Elles ne prétendent pas que le portefeuille partage les incumbents en ligne.
Trois graines donnent 0/33/67/100 %, sans intervalle statistique inventé. Les
figures XKCD déforment volontairement les tracés ; les versions sobres portent
les coordonnées exactes. Toutes sont fournies aussi en PDF.

## Diagnostic de chauffe et du plafonnement

Le lanceur [icn_performance.jl](scripts/icn_performance.jl) sépare les processus
froids, les deux passes du même échauffement, les préparations de parents et de
plans, la réutilisation contrôlée d'un kernel MetaStrategist et les réparations
RO répétées. Il publie temps mural, allocations, temps GC, compilation et
recompilation Julia. La durée d'échauffement inclut des recherches synthétiques
de deux secondes par profil ; elle ne doit pas être appelée entièrement JIT.

Le mode `throughput` mesure trois essais CBLS ICN de cinq secondes sur LC101,
après échauffement. Les expériences à 1/4/16 threads gardent le même algorithme,
avec contrôle séparé du nombre de threads GC. Le processus 16 threads/GC 1
enregistre aussi un profil CPU et un échantillon d'allocations. Ces expériences
instrumentées servent au diagnostic et ne remplacent pas les 369 essais de
qualité gelés. Toute optimisation ultérieure doit être mesurée séparément.

PerfChecker 1.0.0-rc1 est figé au commit
`1cc09a98db569b382f91dc10f6a569c1c728b6aa` dans l'environnement contrôleur
[perfcheck](perfcheck/Project.toml), distinct de l'environnement solveur.
[icn_perfcheck.jl](scripts/icn_perfcheck.jl) collecte les profils CPU, temps
mural et allocations dans trois workers isolés, chacun préchauffé. Le RC copie
les chemins de développement relatifs sans les réancrer : le setup réactive
l'environnement solveur original, en lecture, sans le modifier. Les métriques
par site sont échantillonnées et redimensionnées par PerfChecker ; elles ne
sont pas des compteurs exacts par ligne. Les piles de tâches en attente du
profil mural ne constituent pas une mesure de consommation CPU.

Les mesures initiales à 16 workers montrent environ 36 Go alloués en cinq
secondes, 3,3 secondes de GC et 6,4 CPU actifs en moyenne. Avec quatre threads
de GC, le débit ne progresse que d'environ 9 %. La référence PerfChecker et
les trois mesures de diagnostic sont conservées avant toute modification du
scoreur et des voisinages. Le scoreur du pilote recrée ses entrées ICN et ses
routes ; le moteur LocalSearchSolvers possède déjà des espaces de travail pour
les entrées de contraintes et les mouvements. Cette distinction empêche
d'attribuer au moteur un défaut qui appartient à l'adaptateur du benchmark.
