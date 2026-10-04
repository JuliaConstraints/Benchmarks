# Timefold, Hexaly et temps d'atteinte d'une référence

Le protocole exécutable est [competitors.toml](config/competitors.toml). Le corpus
LC101/LR101/LRC101 est déjà exposé : ces essais servent à qualifier des adaptateurs
et des pistes de recherche, pas à déclarer une supériorité industrielle.

Le [bilan du 4 octobre](results/competitors-20261004.md) livre 135 essais
comparatifs à cinq secondes, sur 1/2/4/8/16 workers, et leurs figures de
qualité, de réussite et de progression en versions exactes et XKCD.
Le [comparatif étendu](results/all-variants-20261004.md) réunit 504 essais de
CBLS/HiGHS, deux mélanges MetaStrategist et Timefold avec les autres variantes
CBLS. Il détaille les captures présentes et les limites du pilote.

## Quelle référence de temps ?

La [table SINTEF des 100 tâches](https://www.sintef.no/projectweb/top/pdptw/100-customers/)
donne les véhicules, la distance, la provenance et une date. Elle précise que
le temps de calcul et la plateforme peuvent manquer pour les meilleures solutions.
La date n'est pas une durée de résolution. Pour nos trois cas, nous conservons
les BKS 10/828,94, 19/1650,80 et 14/1708,80 comme cibles de qualité, avec leur
arrondi de publication. Nous mesurons le temps pour atteindre ces cibles sur
la même machine, au même plafond CPU, à partir du chrono déclaré.

Le [benchmark de l'éditeur Hexaly](https://www.hexaly.com/benchmarks/hexaly-vs-google-or-tools-pickup-and-delivery-problem-with-time-windows-pdptw)
utilise des budgets de 60 et 600 secondes, Hexaly 15.0 et un Ryzen 7 7700 à
huit cœurs. Ce sont des budgets d'une campagne différente, pas les temps historiques
des BKS ni une référence directement transposable à notre i7-12700. Le modèle
publié dans cet article optimise retard puis distance arrondie ; notre modèle
comparatif garde la faisabilité originale, flotte puis distance non arrondie.

## Timefold prêt à exécuter

Le nouveau modèle est [Pdptw.java](native/timefold/src/main/java/bench/Pdptw.java),
Timefold **2.6.0 Community**, Java 21, dépendances Maven épinglées dans
[pom.xml](native/timefold/pom.xml). Cette version conserve celle de SolverSmoke ;
une mise à jour éventuelle devra requalifier le modèle. Les anciens lanceurs
Windows et leur EasyScoreCalculator global restent des traces historiques.

Les variables sont des listes natives de visites par véhicule. Chaque lane
dispose de son modèle et de son scoreur. L'IncrementalScoreCalculator conserve
une contribution par route et ne recalcule que les routes modifiées, y compris
lors des annulations de mouvements à plages imbriquées. Les doubles des distances
et temps ne sont pas discrétisés. Le score lexicographique contient violation,
flotte et distance, avec des contributions BigDecimal pour éviter la dérive
d'une accumulation flottante lors des annulations. Ce score est incrémental à
l'échelle de la route ; les préfixes temporels de la route modifiée sont recalculés.

Qualification : 480 partitions exhaustives de deux requêtes, deux capacités
et deux ensembles de fenêtres, oracle de faisabilité distinct ; quatre recherches
natives FULL_ASSERT ; changements/annulations aléatoires sur chaque instance
réelle. Les incumbents sont contrôlés par un score complet natif, puis toutes
les sorties et trajectoires admises sont auditées par le validateur Julia du
problème original. Les échanges mal formés, les distances/fausses flottes et
les solutions infaisables sont refusés. Les observations tardives sont censurées.

Community utilise un fil de recherche par solveur. À plusieurs workers, le
pilote exécute explicitement plusieurs solveurs indépendants dans une JVM et
fusionne les meilleurs incumbents après jonction. Ce n'est pas le parallélisme
interne des mouvements, qui appartient à
[Timefold Enterprise](https://docs.timefold.ai/timefold-solver/latest/running-timefold-solver/multithreaded-solving).
L'affinité est le même préfixe de CPU que pour CBLS ; `ActiveProcessorCount=N`,
SerialGC et un heap de 2 Go sont publiés. Le nombre de workers ne remplace pas
les mesures CPU. Le défaut natif se résout en acceptation tardive de taille 400
et un candidat accepté par étape dans Timefold 2.6.0. Le profil explicite
`late_acceptance_400` est donc un contrôle de la même politique, pas une nouvelle
stratégie. Le second profil distinct utilise une taille de 1 000. Les versions
instrumentées publient aussi les calculs de score et recalculs de routes exécutés.

Le [lanceur Linux](scripts/timefold_pilot.jl) accepte `workers seconds profil sortie.toml`.
Il utilise trois graines 41/42/43 sur les trois instances, refuse une sortie
existante, conserve sources/JARs/instances hachés, budget, warmup, CPU et trajectoires.
Le script [competitor_cbls.jl](scripts/competitor_cbls.jl) fournit les contrôles
CBLS/ICN actuels sur les mêmes graines, instances et budgets.

Le chargement du runtime et deux warmups sont rapportés séparément. Dans la
version actuelle du lanceur, la préparation commune est débitée du budget de
chaque essai avant l'entrée dans le solveur natif. Le chrono natif inclut lecture
de l'échange, distances, modèle/factory, recherche et contrôles natifs des incumbents.
L'audit original Julia a son temps publié. Les premières captures `timefold-default-*`
sont des diagnostics antérieurs à ce raccordement des deux horloges : leur budget
natif est cinq secondes, avec préparation commune séparée. Elles ne doivent pas
être présentées comme une comparaison strictement égale en temps total.

## Hexaly préparé, qualification native encore requise

Le [modèle natif](native/hexaly/pdptw.hxm) est un draft à qualifier avec Hexaly 15.0.
Il lit le même échange et le même point initial que Timefold, utilise des listes
et une partition, la même route pour les deux membres de chaque requête et une
précédence stricte. Il contraint les charges de tous les préfixes, les heures de
début de service et le retour au dépôt ; depot opening/service et routes vides
sont explicitement traités. Les deux objectifs sont flotte puis distance brute.
L'initialisation des listes est placée dans `param`, conformément à la
[documentation](https://www.hexaly.com/docs/last/features/initialsolution.html).

Le contrat Julia de lancement et d'audit est dans [Adapters.jl](competitors/Adapters.jl).
Le lancement passe `inFileName`, `solFileName`, `trajectoryFileName`, `hxTimeLimit`,
`hxNbThreads`, `hxSeed` et `hxTimeBetweenDisplays` explicitement, avec affinité imposée : le paramètre
[hxNbThreads](https://www.hexaly.com/docs/last/modelerreference/standardlibrary/builtinfunctions.html)
est indicatif. Le contrat de lancement accepte aussi `hxNbThreads=0` pour mesurer
le réglage automatique sous un masque CPU explicite ; un essai fixe à 8 fils peut
ainsi utiliser exactement le même masque de huit cœurs. L'audit accepte uniquement
les routes revalidées avec les objectifs recalculés dans le problème original.
Aucun benchmark Hexaly ni résultat de performance n'est encore produit ;
l'exécutable n'est pas présent sur cette machine.

Le modèle utilise sa fonction HXM classique `display()` pour ajouter chaque
amélioration lexicographique à un TOML de trajectoire. L'intervalle initial est
de 1 seconde, minimum accepté par l'API entière ; seules les améliorations écrivent leurs routes. Le validateur
Julia applique à chaque temps le décalage mesuré de préparation commune, place
le point de départ à cet instant, revérifie les snapshots dans l'instance
originale et censure les observations tardives. Le coût de cette surveillance
reste à mesurer pendant la qualification native.

Le temps est réparti entre les deux objectifs lexicographiques. La valeur simple
`hxTimeLimit=60` signifierait zéro seconde pour la flotte puis 60 secondes pour
la distance. L'adaptateur impose donc une phase explicite 5:1 : 50/10 secondes
pour un budget de 60 secondes, 500/100 pour 600 secondes. Si la flotte est
prouvée optimale tôt, Hexaly transfère le temps restant à la distance. Cette
répartition constitue le profil initial ; tout autre partage devra être une
ablation annoncée, avec les deux durées et les trajectoires consignées.

Avant une campagne : compiler, injecter des solutions valides et invalides
à temps nul, vérifier les routes vides et les fenêtres/charges, contrôler le
point initial après presolve, qualifier le chrono construction/recherche commun
et les snapshots anytime. Le CLI avec un budget de recherche seul ne suffit pas
au classement. La préparation n'active pas de licence et ne démarre pas l'essai.

## Variante par processus

LocalSearchSolvers, moteur de CBLS, possède `Distributed` et `process_threads_map`.
Le pilote MetaStrategist actuel est une phase à threads ; son ordonnanceur
distribué devra être ajouté explicitement. Préparer des workers persistants et
charger banque/packages une fois par processus. Comparer ensuite threads,
processus et combinaisons avec le même plafond CPU, en distinguant GC privés,
mémoire totale, sérialisation, coût froid et réutilisation chaude. Cette ablation
suit la correction multithread ; elle ne sert pas à masquer les allocations.

## GHOST et JuLS Linux

Les sources publiques sont figées dans leurs emplacements de développement :
[GHOST](https://github.com/richoux/GHOST) au commit
`37bbfdf612af229cf9fbb9688995cae268c53a64`, sous `~/Gits/GHOST`, et
[JuLS](https://github.com/amazon-science/JuLS) au commit
`5033406449e48b7aae1cf5ac45ac12cf8a26ff02`, sous `~/.julia/dev/JuLS`.
Les packages ne sont pas modifiés. JuLS 0.1.0 se charge sous Julia 1.11.9 ;
son binding `eval` empêche le chargement sous Julia 1.12.7. Son environnement
séparé avec Manifest conserve cette compatibilité sans changer CBLS.

Les adaptateurs utilisent une permutation de tous les clients et des séparateurs
distincts pour la flotte complète. Même insertion, charge de chaque préfixe,
précédences dans une même route, temps continus avec tolérance originale 1e-8,
retour au dépôt, flotte puis distance brute. `test/native_routes.jl` qualifie
2 880 permutations dans quatre petits problèmes ; le score natif C++ est comparé
au score Julia et à la validation originale (11 716 assertions).

GHOST utilise ses recherches parallèles natives, son point initial personnalisé
et ses options par défaut. Ses observations proviennent de candidats faisables
évalués par l'objectif, qui peuvent précéder l'acceptation du candidat. Le compteur
d'évaluations distingue le point initial d'un appel réel au moteur. Son API
d'options ne fournit pas de seed : les trois répétitions ne sont pas des seeds
appariées avec CBLS. Construction reproductible avec GCC 13.3/C++20 :

```sh
cmake -S "$HOME/Gits/GHOST" -B "$HOME/.cache/juliaconstraints/ghost-build" -DCMAKE_BUILD_TYPE=Release
cmake --build "$HOME/.cache/juliaconstraints/ghost-build" --target ghost_static -j 8
g++ -O3 -std=c++20 -pthread -I"$HOME/Gits/GHOST" -I"$HOME/Gits/GHOST/include" LiLim/native/ghost/pdptw.cpp "$HOME/.cache/juliaconstraints/ghost-build/libghost_static.a" -o "$HOME/.cache/juliaconstraints/ghost-pdptw"
```

JuLS utilise ses sélections greedy et simulated annealing, avec un batch de
64 propositions swap natives dans l'adaptateur, évalué par le pool natif.
Un swap natif isolé ne fournirait qu'une proposition et ne profiterait pas des
threads. Le garde de sélection exclut les mouvements arrêtés comme infaisables
avant de déléguer à la sélection native ; ils ne peuvent pas être committés
par JuLS. CP désactivé. L'erreur agrégée est entière, `ceil(violation)`, afin de
préserver le zéro exact dans les deltas ; pénalité 10 000. Cent deltas par instance
et lancement vérifient faisabilité et coût, puis chaque incumbent est revalidé
dans le problème original. Ces profils explicitement adaptés ne sont pas un HPO
complet des concurrents.

`scripts/local_search_pilot.jl` applique l'affinité 1/2/4/8/16, trois répétitions
et un budget total de cinq secondes raccordé au préfixe de préparation commune.
Deux warmups de même forme d'une seconde, chargement du runtime et audit final
sont séparés. Les captures conservent les sources, commits, environnements,
trajectoires, CPU et compteurs natifs. Hexaly reste en attente de son exécutable.
