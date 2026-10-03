# Protocole du premier pilote CBLS–HiGHS — 4 octobre 2026

Ce pilote diagnostique le prototype reconstruit. Il ne confirme pas une
supériorité générale de CBLS, ni un résultat contre Timefold ou Hexaly.
Les trois instances ont déjà été utilisées : aucune n'est un cas réservé
à la confirmation. Un examen préalable de trois secondes a servi à vérifier
le fonctionnement et à fixer la politique ; ses valeurs ne sont pas agrégées
avec les mesures ci-dessous.

## Matrice figée avant mesures

Le fichier `config/current-pilot.toml` fixe 72 exécutions : lc101, lr101 et
lrc101 ; budgets de 10 et 30 secondes ; graines 41, 42 et 43 ; quatre méthodes.
La campagne représente 24 minutes de budgets cumulés, hors chargement,
échauffement, archivage et éventuels dépassements coopératifs. Un processus
enfant travaille à la fois sur le CPU logique 8 du i7-12700. Julia, GC, BLAS,
OMP et HiGHS sont limités à un thread. L'autorisation de toutes les ressources
permet cette exécution ; le plafond commun d'un CPU rend le diagnostic lisible.
L'ordre des quatre méthodes est décalé de façon prédéfinie entre les blocs.

| Méthode | Recherche | Score / contraintes |
|---|---|---|
| CBLS | Pas natifs LSS et meilleure réinsertion admissible d'une paire choisie au hasard | Score direct des routes ; aucune ICN |
| Hybride spécialisé | Même CBLS, plus réparations RO de routes entières | Égalités de labels MILP spécialisées |
| Hybride bridgé | Même politique et même périmètre de fragments | Égalités discrètes par DAG XCSP3Bridges ; temps et charges RO explicites |
| HiGHS complet | Modèle compact sur toutes les visites avec MIP start commun | Flotte puis distance après preuve de flotte optimale |

Les DAG d'égalité sont des poids structurels manuels sauvegardés, pas des poids
appris ni des optima récupérés. Les fragments contiennent au plus 20 visites,
soit dix requêtes, et libèrent l'union de deux routes complètes quand elle tient
dans ce plafond, sinon une route admissible. Budget maximal par appel : 0,5 s ;
part cumulée des réparations : 35 % du budget global ; déclenchement tous les
20 pas. Cette politique est fixe, sans sélection adaptative MetaStrategist.
Les égalités spécialisées et bridgées ont la même sémantique, mais la trajectoire
globale peut diverger. Le coût des bridges se diagnostique aussi dans les traces
de construction et de résolution, sans prétendre que des fragments différents
constituent une comparaison strictement appariée des formulations.

## Temps, objectifs et preuve

Chaque exécution relit le fichier et construit le même point de départ avec
cinq ordres d'insertion, graine 41. Ce coût compte dans son budget. Les graines
41–43 règlent ensuite la recherche. L'objectif compare d'abord la faisabilité,
puis la flotte, puis la distance euclidienne non arrondie. Le score CBLS est
un scalaire avec borne de distance garantissant cette priorité de flotte.

Le budget principal couvre lecture, insertion, préparation du parent ou du
MILP, traduction, recherches, réparations et validation originale des
incumbents. Les horloges du wrapper et de CBLS partagent la même origine.
Seuls les incumbents déjà validés avant l'échéance sont admissibles.
Les snapshots de routes sont possédés ; une amélioration tardive ne supprime
pas une solution antérieure admissible. HiGHS est observé par son callback de
solution avec correspondance des colonnes qualifiée. Les validations finales
d'audit et la sérialisation sont postérieures à la recherche et leur coût se
retrouve dans le temps mural ; elles ne rendent aucune solution tardive admissible.

Le chargement et l'échauffement synthétique du wrapper réel sont mesurés
séparément dans chaque processus. La matrice principale porte sur une exécution
échauffée. Ce pilote ne compare pas les démarrages à froid des moteurs complets.
Un dépassement coopératif est publié, jamais assimilé à une amélioration dans
le budget. Le superviseur surveille la mémoire RSS et les temps : 8 Gio,
120 secondes par job, 900 secondes par enfant. Un dépassement arrête l'enfant
et la campagne, conserve les sorties et demande un diagnostic.

Les chemins historiques restent inchangés. Le nouveau lecteur et le validateur
sont `ConstraintModels.Benchmarks`, sémantique `pdptw-semantics-rebuild/1`, dans
l'environnement sauvegardé `ConstraintModels/perf/pdptw`. La configuration
empreinte Project, Manifest, les fichiers d'instances et douze dépendances de
développement. La campagne vérifie les versions et l'absence de modifications
suivies dans ces dépendances. Les changements antérieurs de SolverSmoke sont
exclus du chemin mesuré. Chaque résultat contient les routes originales,
trajectoires, traces des réparations, identités des programmes et empreintes.

## Qualification et exploitation

Les contrôles couvrent le lecteur/validateur, toutes les partitions de petits
problèmes confrontées au MILP, le résolveur RO, le score CBLS, les réinsertions
accessibles confrontées à une énumération indépendante, les callbacks HiGHS,
les échéances et l'aller-retour TOML. Ils doivent passer avant la campagne.

Qualification du 4 octobre : 2 051 assertions passent (25 sémantique,
592 modèle RO, 38 résolveur, 1 354 contrôleur et déplacements, 42 observation
et archivage). Le callback a nécessité une synchronisation explicite du cache
JuMP avant résolution ; son accès aux colonnes est couvert par les contrôles.

Depuis la racine Benchmarks, lancer `LiLim/scripts/current_pilot.jl campaign`
avec Julia 1.13.1, `--startup-file=no --compiled-modules=existing -O1`,
`--threads=1 --gcthreads=1`, et le projet
`$HOME/.julia/dev/ConstraintModels/perf/pdptw`, sur le CPU 8 avec BLAS/OMP/MKL
à un thread. Le lanceur ne télécharge rien et refuse de remplacer une campagne.
Les données complètes restent dans `LiLim/data/pilots/<uuid>` ; le bilan et
les preuves essentielles seront sauvegardés dans ce dépôt privé.

Rapporter la qualité et sa dispersion par instance et budget, les taux
d'admissibilité, le nombre de réparations utiles, les coûts de construction et
résolution, les dépassements et les échecs. Trois graines ne permettent pas
de conclure à une parité statistique. Une absence d'amélioration sur lc101,
dont le point de départ atteint déjà l'ancien optimum validé, n'est pas un
échec du prototype. Les conclusions désignent cette formulation HiGHS et
ce profil CBLS précis. Le prochain effort est choisi d'après les obstacles
mesurés, avant toute extension au corpus réservé ou aux solveurs commerciaux.

Campagne terminée et auditée :
[bilan et décision](results/pilot-20261004.md),
[preuves et traces essentielles](results/pilot-20261004.toml).
La référence mesurée est `fb609d3012d2cfc1e38974df6e1b85dbf7277e4d` ;
72/72 résultats sont admissibles. Le lecteur de bilan est
`scripts/current_report.jl <campagne> <base-de-sortie>` et refuse une destination
existante. Son audit a aussi rejeté une empreinte volontairement altérée.
