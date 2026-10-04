# Timefold, Hexaly et temps d'atteinte d'une référence

Le protocole exécutable est [competitors.toml](config/competitors.toml). Le corpus
LC101/LR101/LRC101 est déjà exposé : ces essais servent à qualifier des adaptateurs
et des pistes de recherche, pas à déclarer une supériorité industrielle.

Le [bilan du 4 octobre](results/competitors-20261004.md) livre 54 essais
comparatifs à cinq secondes, sur un et seize workers, et leurs figures de
qualité, de réussite et de progression en versions exactes et XKCD.

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
Le lancement passe `inFileName`, `solFileName`, `hxTimeLimit`, `hxNbThreads` et
`hxSeed` explicitement, avec affinité imposée : le paramètre
[hxNbThreads](https://www.hexaly.com/docs/last/modelerreference/standardlibrary/builtinfunctions.html)
est indicatif. L'audit accepte uniquement les routes revalidées avec les objectifs
recalculés dans le problème original. Aucun benchmark Hexaly ni résultat de
performance n'est encore produit ; l'exécutable n'est pas présent sur cette machine.

Avant une campagne : compiler, injecter des solutions valides et invalides
à temps nul, vérifier les routes vides et les fenêtres/charges, contrôler le
point initial après presolve, ajouter le chrono construction/recherche commun
et des callbacks anytime. Le CLI avec un budget de recherche seul ne suffit pas
au classement. La préparation n'active pas de licence et ne démarre pas l'essai.

## Variante par processus

LocalSearchSolvers, moteur de CBLS, possède `Distributed` et `process_threads_map`.
Le pilote MetaStrategist actuel est une phase à threads ; son ordonnanceur
distribué devra être ajouté explicitement. Préparer des workers persistants et
charger banque/packages une fois par processus. Comparer ensuite threads,
processus et combinaisons avec le même plafond CPU, en distinguant GC privés,
mémoire totale, sérialisation, coût froid et réutilisation chaude. Cette ablation
suit la correction multithread ; elle ne sert pas à masquer les allocations.
