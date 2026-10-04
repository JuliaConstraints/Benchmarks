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

Les traces complètes sont dans data/thread-pilots. Le bilan conserve les résultats,
routes et trajectoires essentiels avec les empreintes des traces. Les sources,
protocole, décisions, résultats essentiels et graphiques sont commis et poussés
sur GitLab privé. Les graphiques Julia utilisent un environnement indépendant
plotting/Project.toml et son Manifest, sans changer les versions des solveurs.
La sortie XKCD est une illustration secondaire ; les figures sobres conservent
des coordonnées exactes pour une utilisation scientifique.
