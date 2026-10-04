# Plan de benchmarks pour financer JuliaConstraints

Proposition du 2 octobre 2026, à exécuter par étapes. Ce document fixe la démarche ;
il ne rapporte pas une campagne nouvelle ni un accord de financement.

Consigne du 4 octobre : l'utilisateur autorise explicitement la reprise, sans
limite globale, avec toutes les ressources de la machine disponibles. L'objectif
actif est un premier pilote Li-Lim qualifié et sauvegardé. Les budgets des essais
restent fixés pour permettre une comparaison reproductible ; cette autorisation
remplace l'attente stricte des autres chats. L'ancienne automation reste en pause
pendant cette reprise directe.

Consigne d'exécution historique du 2 octobre : reprendre les calculs et les
travaux de solveur lorsque les trois tâches ci-dessous ont terminé leurs
exécutions et qu'aucune autre tâche Codex n'est active, en excluant ce chat du
contrôle. Une nouvelle tâche concurrente reporte également les calculs.

Consigne complémentaire du 4 octobre : corriger le pilote qui utilisait un score
direct sans les fonctions ICN récupérées. Comparer les erreurs naïves booléennes,
les décodeurs ICN effectivement exécutés et le score direct existant, ainsi que
les hybrides, à 1, 2, 4, 8 et 16 threads. Distinguer parallélisme natif HiGHS et
portefeuilles de trajectoires indépendantes. Utiliser réellement MetaStrategist
pour exécuter des allocations mixtes, notamment 4 CBLS, 4 hybrides spécialisés,
4 hybrides bridgés et 4 HiGHS série à 16 threads. Livrer les mesures d'utilisation
CPU et des graphiques Julia, dont une sortie XKCDMakie. Le protocole est dans
[ICN et threads](../LiLim/ICN_THREADS.md). L'ancienne campagne conserve son
statut de diagnostic du score direct ; elle ne constitue pas une preuve sur ICN.

| Tâche attendue | Identifiant du chat |
|---|---|
| Cloner le repo business-plan | `01a0fb66-d842-7193-801e-e2973852e777` |
| Définir l’objectif du RTS spatial (2) | `01a0f635-0f91-7a52-a0a6-c0b8caaa066a` |
| Faire le point sur Catalyst | `01a0f430-cccd-7312-8f0d-fed8e319c1a8` |

La reprise automatique « Reprise JuliaConstraints après les tâches en cours »
est attachée à ce chat avec une vérification toutes les cinq minutes. Elle
confirme aussi la fin des processus de rendu ou de solveur encore présents avant
un lot de calculs. Elle reste silencieuse pendant une attente inchangée, poursuit
le premier pilote qualifié selon ce plan lorsque les ressources sont libres et
se met en pause à la livraison de son bilan sauvegardé. Les lectures de sources
et les mises à jour documentaires peuvent continuer pendant l'attente.

## Objectif et résultat attendu

### État du 4 octobre 2026 après qualification ICN et diagnostic GC

Le [bilan des 369 essais](../LiLim/results/icn-threads-20261004.md) et les figures
de réussite/anytime conservent leurs sources et budgets. Le
[diagnostic PerfChecker/SnoopCompile](../LiLim/results/icn-performance-20261004.md)
conduit à des buffers privés par worker et une correction d'itération du noyau.
Sur le contrôle LC101 à seize threads, l'occupation atteint 15,97 CPU actifs et
les allocations passent de 36,09 Go à 256 Mo sur cinq secondes. Ce résultat
qualifie le débit ; il n'est pas une preuve de supériorité sur la qualité.

La priorité reste la réduction du GC en multithread. Les versions par processus
seront contrôlées ensuite avec un pool déjà chargé, GC privés, coûts de lancement
et sérialisation déclarés. Le pilote MetaStrategist actuel exécute des threads ;
sa phase distribuée n'est pas supposée exister.

Le [protocole concurrents](../LiLim/config/competitors.toml) ajoute un adaptateur
Timefold Community à score incrémental par route et prépare un modèle Hexaly
de même sémantique : contraintes originales, flotte puis distance non arrondie.
Qualifier les sorties avec le validateur original et comparer à budget et
ressources égaux. La fenêtre d'essai Hexaly n'est pas démarrée par cette préparation.
Les BKS SINTEF donnent des cibles de qualité ; aucun temps de référence homogène
ne doit être inventé. La mesure utile est notre temps local d'atteinte de ces cibles.

Obtenir assez de preuves de compétitivité pour proposer à une entreprise de
financer JuliaConstraints avec une partie du budget consacré à ses licences de
solveurs commerciaux de recherche locale. Le cœur logiciel resterait open source.
Les données des campagnes et les configurations ajustées seraient réservées aux
deux entreprises partenaires, selon un accord à établir.

Deux hypothèses guident les premiers essais :

1. CBLS, avec quelques stratégies bien choisies, peut égaler ou dépasser Timefold
   et Hexaly sur des familles classiques favorables à la recherche locale.
2. CBLS peut gagner sur Li-Lim en traitant des méta-variables par des sous-problèmes
   de recherche opérationnelle confiés à HiGHS, plutôt qu'en résolvant constamment
   le problème complet.

La première cible est un résultat convaincant sur un corpus annoncé à l'avance.
Une parité robuste peut suffire à soutenir la proposition économique. Une
supériorité universelle et la réalisation de toute la roadmap ne sont pas des
conditions préalables au financement. Les essais peuvent aussi invalider ces
hypothèses : leur protocole doit permettre de le constater.

## Ce qui existe et ce qui manque

L'inspection porte sur Benchmarks au commit
`7994aeca55164264d48969adec53ba8936fa6406` et LocalSearchSolvers au commit
`9010ff2a0147257a2991680981f579e8c20db733`. Les modifications locales en cours ne
constituent pas automatiquement une nouvelle référence reproductible.

| Élément | État utile pour ce plan | Limite à lever |
|---|---|---|
| SolverSmoke | Adaptateurs et traces de qualification CBLS/LSS, GHOST, JuLS, Timefold et HiGHS | Petits cas, lanceurs historiques Windows, recalcul complet des routes ; les profils de routing ne démontrent pas l'emploi de fonctions ICN apprises |
| Comparaison GHOST et CBLS | Traces encourageantes sur quatre petits cas synthétiques, dix répétitions par cellule | Pas une preuve contre Timefold ou Hexaly sur des problèmes classiques de taille représentative |
| LiLim | Modèle MILP compact, initialisation par insertion et traces de validation indépendante | L'insertion est une référence autonome, pas CBLS ; la copie locale de l'ancien lecteur/validateur est absente et doit être reconstruite et requalifiée |
| Méta-variables LSS | Groupes de variables, mouvements atomiques et interface de résolution avec budget | L'adaptateur de sous-problème HiGHS reste à réaliser et qualifier |
| MetaStrategist | Grammaire, plans et infrastructure d'exécution exploitables | Une orchestration adaptative complète ne doit pas être supposée disponible |
| XCSP3Bridges | Module reconstruit, compilation de réseaux entiers finis via les bridges CPE et raccordement à des variables MOI existantes ; première version sauvegardée sur GitLab privé | Pas de traduction complète déjà qualifiée de Li-Lim ; les anciens rangs ne sont pas restaurés |

Les qualifications historiques sont décrites dans
[SolverSmoke](../SolverSmoke/THREAD_QUALIFICATION.md),
[les mesures anytime](../SolverSmoke/ANYTIME.md) et
[le pilote Li-Lim](../LiLim/QUALIFICATION.md). La comparaison synthétique est dans
[la branche GHOST et CBLS de ConstraintLearningBenchmarks](https://gitlab.naze.baffier.fr/others/ConstraintLearningBenchmarks.jl/-/blob/c27b20854cb805d8077a7827aafd7fbf96bbdf4e/docs/ghost_cbls_four_cores.md).

Sur lc101, le pilote HiGHS a prouvé son optimum pour la flotte et la distance :
une meilleure qualité sur exactement ce modèle est impossible. Sur lr101 et
lrc101, le temps imparti a expiré sans preuve d'optimalité et sans amélioration
de l'initialisation. Ces résultats ouvrent une question expérimentale, pas une
conclusion sur les performances de CBLS.

Hexaly est une cible exigeante : son étude du 27 mars 2026 annonce un écart moyen
de 0,8 % aux meilleures distances connues en une minute sur Li-Lim. C'est une
mesure de l'éditeur. Le modèle publié minimise le retard puis une distance
arrondie et n'affiche pas la minimisation de la flotte dans ses objectifs : ces
chiffres ne sont pas directement comparables à notre objectif flotte puis
distance non arrondie. [Source et modèle Hexaly](https://www.hexaly.com/benchmarks/hexaly-vs-google-or-tools-pickup-and-delivery-problem-with-time-windows-pdptw).

## Axe 1 Quelques stratégies et deux familles classiques

Les candidats prioritaires sont le partitionnement équilibré de graphes, déjà
prioritaire dans le carnet de travail, et le car sequencing. Un problème
d'emploi du temps peut remplacer l'un des deux si ses modèles et validateurs
sont nettement plus prêts. Le choix dépendra de cette disponibilité et de
l'intérêt des familles, avant d'observer les résultats comparatifs.

Pour chaque famille, préciser la variante, les contraintes dures, l'objectif,
la représentation et plusieurs tailles d'instances. Fixer un corpus de réglage
et un corpus de confirmation séparés. Une famille difficile pour CBLS reste
dans le bilan ; un changement de corpus demande une nouvelle version du protocole.

Le premier effort de développement est borné :

- Mesurer les coûts dominants et introduire une évaluation incrémentale là où
  elle change réellement le débit de recherche, avec vérification du score complet.
- Fournir des mouvements qui respectent la structure : échanges conservant
  l'équilibre pour les graphes, échanges et déplacements de séquences pour les voitures.
- Comparer au plus trois profils initiaux d'acceptation et de diversification,
  choisis parmi ce qui fonctionne déjà ; ajouter une stratégie seulement si
  les diagnostics en expliquent le besoin.
- Introduire MetaStrategist sous une forme légère : un plan fixe ou un petit
  choix de profils selon la stagnation. Régler ces quelques paramètres hors
  ligne, puis figer la politique pour la confirmation.

Identifier pour chaque contrainte la fonction d'erreur réellement exécutée et
sa provenance : ICN, QUBO, réseau de bridge ou fonction écrite directement.
Conserver l'empreinte du modèle, des poids et de la représentation. L'existence
d'un témoin satisfaisant sur une variante ne prouve ni l'optimalité de ses poids
ni sa validité sur tous les domaines. Qualifier le domaine effectivement utilisé
et vérifier que le chemin mesuré exécute bien cette fonction.

Les concurrents doivent disposer de modèles adaptés à leurs moteurs. Pour
Timefold, qualifier un score incrémental ou Constraint Streams avant d'en faire
une référence de performance ; l'ancien EasyScoreCalculator est insuffisant
pour conclure sur le passage à l'échelle. La documentation distingue explicitement
ces mécanismes. [Documentation Timefold](https://docs.timefold.ai/timefold-solver/latest/constraints-and-score/overview).
Pour Hexaly, partir de ses représentations natives pertinentes, puis assurer
l'identité de la sémantique et des objectifs. Déclarer versions, éditions et
effort de réglage des concurrents. Préparer modèles et protocole avant de démarrer
la fenêtre d'essai commercial.

## Axe 2 Méta-variables et sous-problèmes HiGHS sur Li-Lim

Le prototype suit l'interface de méta-variables existante dans LocalSearchSolvers :

1. CBLS sélectionne un groupe de décisions, par exemple quelques paires
   pickup-delivery complètes sur des routes liées ou une tentative de suppression
   d'une route. La portée peut recouvrir d'autres méta-variables.
2. Une requête capture l'état, les variables libres, les décisions extérieures
   fixées, les conditions aux frontières et le budget disponible.
3. Le résolveur construit un sous-problème RO et le confie à HiGHS. Le budget
   couvre construction, résolution et validation, avec une part totale des
   appels HiGHS plafonnée dans le budget du solveur hybride.
4. Une solution admissible est transformée en `MetaMove`, validée dans le
   problème original et appliquée atomiquement selon la politique d'acceptation.
   Le meilleur incumbent valide est conservé. Un timeout sans solution, un refus
   de ressources ou une solution invalide produit un statut explicite et aucun mouvement.

Les frontières doivent tenir compte des contraintes traversant le groupe :
unicité de service, appartenance à une même route, précédence, charge, fenêtres
temporelles et retour au dépôt. Fixer l'extérieur ne signifie pas supprimer ses
interactions. Un optimum du fragment n'est pas un optimum du problème complet.

Commencer par deux types de fragments et quelques tailles modestes calibrées
sur le corpus de réglage. HiGHS peut recevoir l'affectation courante comme point
de départ lorsqu'elle satisfait le fragment. MetaStrategist peut choisir le
type de groupe ou déclencher une réparation après stagnation ; une politique
simple suffit au premier prototype, sans apprentissage par renforcement.

### Contraintes communes et XCSP3Bridges

Utiliser effectivement XCSP3Bridges pour les contraintes discrètes prises en
charge du fragment. L'API `add_program!` peut les raccorder aux variables du
modèle RO. Conserver l'identité et l'empreinte des programmes source, ainsi que
les contraintes restant formulées directement. Une contrainte déjà garantie
par la représentation doit être déclarée comme telle, sans encodage redondant
ajouté uniquement pour faire apparaître un bridge.

La reconstruction actuelle traduit des graphes sur domaines entiers finis en
relations locales, avec des coefficients entiers exactement représentables par
son backend Float64. Li-Lim utilise des temps continus et des distances
euclidiennes. Ne pas les arrondir ou discrétiser implicitement pour contourner
cette limite. Le premier modèle peut combiner des blocs discrets bridgés et des
contraintes RO continues explicites ; il doit être présenté avec cette portée.
Une traduction plus complète nécessite des bridges supplémentaires qualifiés.

Les tables locales peuvent multiplier les sélecteurs et produire des relaxations
peu efficaces. Mesurer les variables auxiliaires, les lignes, la mémoire, le
temps de traduction, le presolve et la résolution. L'impact dépend de la
formulation et du fragment ; une perte systématique n'est pas établie.

Comparer sur les mêmes fragments une traduction par bridges et une formulation
MILP spécialisée de même sémantique. Ce contrôle sépare le coût de traduction du
gain de décomposition. Il ne remplace pas discrètement la variante bridgée dans
les résultats. Chercher ensuite des bridges spécialisés, des bornes plus serrées
ou une réutilisation de structure, en conservant la validation originale.

## Comparaisons qui permettent d'attribuer les gains

Les ablations sont des diagnostics courts avant de retenir les finalistes :

| Variante | Question mesurée |
|---|---|
| CBLS avec mouvements simples | Référence du moteur actuel |
| CBLS avec mouvements de groupe sans HiGHS | Gain de structure des méta-variables |
| HiGHS sur le modèle complet | Référence RO, incluant construction et initialisation |
| CBLS et HiGHS sur fragments bridgés | Gain de l'hybridation avec les contraintes communes |
| CBLS et HiGHS sur les mêmes fragments spécialisés | Coût et effet de la formulation des bridges |
| Meilleur hybride avec MetaStrategist léger | Gain du choix de fragments ou de leur déclenchement |

Ne pas croiser toutes les variantes avec toutes les tailles, budgets et stratégies.
Retenir les variantes utiles après les diagnostics, puis comparer les finalistes
sur le corpus de confirmation. Sur Li-Lim, la première cible est un gain robuste
de l'hybride sur CBLS seul et HiGHS complet ; la confrontation aux solveurs de
recherche locale reste nécessaire avant d'étendre cette conclusion à la concurrence.

## Protocole et campagne bornée

Le [protocole existant](method.md) reste applicable. Avant les mesures, figer :
instances et empreintes, séparation réglage/confirmation, sources et dépendances,
configurations, répétitions, limites CPU et mémoire, budgets et critères d'arrêt.

La mesure principale couvre le temps jusqu'à la solution utilisable :
initialisation, construction, traduction, appels solveur et validation finale.
Publier séparément les coûts de chargement et de compilation, les résultats à
froid et après échauffement, et le temps de recherche proprement dit. Aucun coût
de l'hybride ne doit être soustrait seulement pour lui. Isoler les campagnes des
autres charges de la machine et fixer le même plafond de ressources.

Valider les solutions indépendamment de chaque score interne. Sur Li-Lim,
comparer d'abord la faisabilité, puis le nombre de véhicules, puis la distance
euclidienne non arrondie. Les pénalités peuvent guider une trajectoire infaisable,
mais seul un résultat revalidé entre dans le classement. Un diagnostic à point
de départ commun complète les essais avec initialisations natives lorsque les
adaptateurs l'acceptent ; le coût de production de ce point est déclaré.

Rapporter taux de faisabilité, qualité à budget fixé, temps pour atteindre une
cible, distributions entre répétitions et courbes anytime. Un échec, une
incompatibilité de modèle et un arrêt de ressources gardent des statuts distincts.
La parité demande une marge pratique de non-infériorité fixée par famille et une
incertitude suffisamment faible ; une différence non significative ne la prouve
pas. Les gains de distance ne s'agrègent pas en ignorant une flotte plus grande.

Proposition initiale pour l'axe classique : deux familles, douze instances chacune,
six pour le réglage et six pour la confirmation, dix répétitions et trois budgets
de 1, 10 et 60 secondes. Avec quatre finalistes, la confirmation représenterait
1 440 exécutions et environ 9,5 heures de budgets cumulés, hors préparation et
échauffement. Ce n'est pas une estimation du délai réel. Calibrer d'abord les
budgets sur quelques cas, puis figer la matrice avant la confirmation.

Pour Li-Lim, commencer par lc101, lr101 et lrc101 comme cas de diagnostic, puis
constituer un petit corpus séparé couvrant les trois distributions et plusieurs
tailles. Ne pas reprendre immédiatement la matrice historique de 354 instances
et 41 configurations. Plafonner chaque pilote et établir son coût avant de
décider d'une extension.

## Recherche des instances du 2 octobre 2026

Les listes suivantes sont des propositions de sélection avant exécution.
La lecture des archives confirme des fichiers et des formats, pas leur résolution
par nos adaptateurs. Les petites archives consultées ont été supprimées après
inspection ; leurs sources et empreintes restent ci-dessous.

### Premier corpus Car Sequencing

[CSPLib 001](https://www.csplib.org/Problems/prob001/) définit les demandes par
classe et les capacités d'options sur fenêtres. Son
[index de données](https://www.csplib.org/Problems/prob001/data/) distingue les
instances classiques des variantes ROADEF, avec contraintes supplémentaires.

L'[archive de Caroline Gagne](https://www.csplib.org/Problems/prob001/data/ProblemDataSet200to400.zip)
a été téléchargée et inventoriée : trente fichiers, dix pour chacune des tailles
200, 300 et 400 voitures, avec cinq options. Les en-têtes ont été lus ; aucune
solution ni classification de satisfaisabilité n'a été vérifiée dans cette passe.

Proposition de douze instances, stratifiée par taille :

| Taille | Réglage | Confirmation |
|---|---|---|
| 200 | `pb_200_01.txt`, `pb_200_02.txt` | `pb_200_06.txt`, `pb_200_07.txt` |
| 300 | `pb_300_01.txt`, `pb_300_02.txt` | `pb_300_06.txt`, `pb_300_07.txt` |
| 400 | `pb_400_01.txt`, `pb_400_02.txt` | `pb_400_06.txt`, `pb_400_07.txt` |

Pour la qualification, garder aussi le petit exemple de dix voitures de la
spécification et quelques cas historiques avec statuts annoncés. Les
[résultats CSPLib](https://www.csplib.org/Problems/prob001/results/result1.md.html)
indiquent notamment `4/72` satisfaisable et `6/76` infaisable. Ils mentionnent
`26/82`, absent du fichier historique lu : ne pas construire un manifeste à partir
de la seule liste de résultats. Le
[fichier de données source](https://raw.githubusercontent.com/csplib/csplib/master/Problems/prob001/data/data.txt)
consulté contient huit cas historiques et soixante-dix cas de 200 voitures,
répartis en sept niveaux d'utilisation.

Deux contrats doivent rester distincts : atteindre une séquence sans violation,
ou minimiser un dépassement explicitement défini. Le
[modèle Hexaly publié](https://www.hexaly.com/docs/last/exampletour/carsequencing.html)
minimise la somme des excès positifs de capacité sur toutes les options et
fenêtres. Ce score n'est pas simplement le nombre de fenêtres violées. Une
fonction ICN peut guider CBLS, mais le résultat comparatif doit être réévalué
avec le même objectif officiel pour tous les solveurs. Une valeur publiée de
« violations » n'est comparable qu'après vérification de sa définition.

L'[index XCSP3](https://xcsp.org/instances/) fournit aussi une
[archive CarSequencing](https://www.cril.univ-artois.fr/~lecoutre/seriesSiteXCSP/CarSequencing.tgz),
inventoriée à 109 fichiers XML compressés. Un exemple lu, `CarSequencing-90-02`,
est de type CSP avec cardinalités et sommes. C'est une voie de qualification
XCSP3, pas une preuve que notre importeur accepte déjà tout le corpus.
Le [modèle source PyCSP3](https://raw.githubusercontent.com/xcsp3team/pycsp3-models/main/realistic/CarSequencing/CarSequencing.py)
propose des encodages logique et table, et ajoute des contraintes redondantes
déduites des capacités dures. Ne pas garder automatiquement ces dernières en
transformant le problème en minimisation de dépassements : leur justification
suppose le respect des capacités. Regrouper les encodages d'une même instance
dans le même lot pour éviter les doublons entre réglage et confirmation.

### Sources accessibles pour Graph Partitioning

L'[archive Walshaw](https://chriswalshaw.co.uk/partition/) reste la référence du
carnet. Son accès complet passe par une demande de lien ; aucune demande n'est
envoyée dans cette passe. Ses tableaux donnent des qualités, sans temps comparables.
La convention d'équilibre utilise la borne supérieure
`ceil(n/k) * (1 + epsilon)` sur la taille des blocs. Ne pas ajouter des bornes
inférieures ou une exigence de connexité absentes de la variante référencée.

La [collection DIMACS10 de SuiteSparse](https://sparse.tamu.edu/DIMACS10)
répertorie les correspondances avec Walshaw. Elle permet une acquisition par
notices individuelles, puis une conversion déclarée des matrices en graphes.
Le téléchargement Matrix Market de
[3elt](https://sparse.tamu.edu/AG-Monien/3elt) a été vérifié : 4 720 sommets et
13 722 entrées triangulaires d'une matrice de motif symétrique. Le miroir indiqué
par la notice est joignable en HTTP ; l'essai HTTPS a expiré.

Douze candidats de tailles modérées sont proposés pour la qualification :

| Graphe | Sommets | Collection ou notice correspondante |
|---|---:|---|
| add20 | 2 395 | `Hamm/add20` |
| data | 2 851 | `DIMACS10/data` |
| 3elt | 4 720 | `AG-Monien/3elt` |
| uk | 4 824 | `DIMACS10/uk` |
| add32 | 4 960 | `Hamm/add32` |
| bcsstk33 | 8 738 | `HB/bcsstk33` |
| whitaker3 | 9 800 | `AG-Monien/whitaker3` |
| crack | 10 240 | `AG-Monien/crack` |
| wing_nodal | 10 937 | `DIMACS10/wing_nodal` |
| fe_4elt2 | 11 143 | `DIMACS10/fe_4elt2` |
| 4elt | 15 606 | `Pothen/barth5` |
| memplus | 17 758 | `Hamm/memplus` |

Les tailles viennent du tableau Walshaw ; les correspondances sont celles de
SuiteSparse/DIMACS10. Les octets des onze autres graphes restent à qualifier.
Pour les matrices numériques, vérifier la conversion en motif non orienté,
l'élimination de la diagonale et le dédoublonnage des arêtes ; ne pas utiliser
leurs coefficients comme poids sans changer explicitement de variante.

Proposition initiale : quatre blocs, équilibre à 0 % selon la convention de
l'archive, coupe en nombre d'arêtes. Une tolérance de 3 % serait une ablation
séparée. Réserver six graphes entiers à la confirmation avant les réglages ;
changer `k` sur un graphe ne crée pas une instance indépendante pour ce partage.

En complément, le
[dépôt KaHIP](https://github.com/KaHIP/KaHIP/tree/34e1d0a00afeae2ae2ebfe625826e9c8f8f40ac4/examples)
contient deux fichiers METIS directement accessibles, dont les en-têtes ont été
lus : `delaunay_n15.graph` et `rgg_n_2_15_s0.graph`, chacun à 32 768 sommets.
Ils peuvent diversifier les structures après qualification du petit pilote.
Le [travail sur la recherche locale par ILP pour le partitionnement](https://arxiv.org/abs/1802.07144),
déjà référencé dans le carnet, étaye la piste de régions réduites résolues par
un moteur RO ; il ne mesure pas notre futur adaptateur HiGHS.

### Pilote Li-Lim de 100 vers 200 tâches

[SINTEF](https://www.sintef.no/projectweb/top/pdptw/li-lim-benchmark/)
fournit six tailles nominales, environ 100 à 1 000 tâches. Une tâche est une
visite pickup ou delivery, pas une paire de requêtes. Les archives de tailles
100 et 200 ont été inventoriées : respectivement 56 et 60 fichiers texte.

Une proposition bornée réutilise six cas à 100 tâches pour le réglage :
`lc101`, `lr101`, `lrc101`, `lc201`, `lr201`, `lrc201`. Les trois premiers ont
déjà servi au pilote historique et ne doivent pas devenir des cas de confirmation.
Réserver six cas nominalement à 200 tâches : `LC1_2_1`, `LR1_2_1`, `LRC1_2_1`,
`LC2_2_1`, `LR2_2_1`, `LRC2_2_1`. Ces noms exacts existent dans l'archive 200,
sans sous-répertoire, avec extension `.txt`. Les cas 100 sont en minuscules sous
`pdp_100/`. Cette proposition teste le transfert de taille ; elle ne suffit pas
à conclure sur les tailles 400 à 1 000.

Les [références 100](https://www.sintef.no/projectweb/top/pdptw/100-customers/) et
[références 200](https://www.sintef.no/projectweb/top/pdptw/200-customers/)
serviront de cibles de qualité. Elles ne fournissent pas des temps comparables
et mêlent meilleures valeurs connues et valeurs signalées optimales. Lire les
annotations par cas. Ne pas injecter leurs solutions dans l'initialisation du
benchmark ; leur lecture sert au contrôle et à la comparaison a posteriori.
Conserver les identifiants originaux et suivre la
[documentation du format](https://www.sintef.no/projectweb/top/pdptw/documentation/).

### Empreintes des sources inspectées

Ces SHA-256 portent sur les archives ou le fichier historique, avant conversion.
L'import futur devra aussi empreinter les données normalisées et les modèles.

| Source | SHA-256 |
|---|---|
| CSPLib `ProblemDataSet200to400.zip` | `85479b9bf0d29c547aa21945bf69e3f458502cdfe9ff530d435c51d395d87645` |
| CSPLib `data.txt` | `e64da35182ae455559642d185afbe7e0f97527d0c0c087dce05a96852913bf6c` |
| XCSP3 `CarSequencing.tgz` | `94e3ad768d3b69c415a020683a3294336339079ea31d00f717d9f16814cbde55` |
| SuiteSparse `3elt.tar.gz` | `86f80a8679f9d1ec7386c4f117e3158fbe5322345057cafe2d83e7aa4494afdd` |
| SINTEF `pdp_100.zip` | `d106694e9e18cebc32b63c322e1000620238392c1b9d98d92de82ef7e4b43cd9` |
| SINTEF `pdp_200.zip` | `0d83737d8ede85b83ac4ec2d162479794d091e915cc921c0912ee9739e5de4d9` |

## Ordre de réalisation et décisions de poursuite

### Reprise et références sauvegardées le 2 octobre 2026

Les trois tâches attendues ont terminé leurs exécutions. Les autres tâches Codex
ont été vérifiées, y compris les chats non chargés : leurs derniers tours sont
terminés ou interrompus. Les processus Julia persistants sont des serveurs MCP
au repos ; aucun rendu ou solveur orphelin n'a été détecté. Chaque lot suivant
reste soumis au contrôle d'absence de concurrence.

- [XCSP3Bridges.jl](https://gitlab.naze.baffier.fr/others/XCSP3Bridges.jl) : dépôt
  **privé**, branche `rebuild/learnable-networks`, commit
  `fe5bceaddc5081fedd200571b480e44ca9de1947`, présent sur le remote.
- [ConstraintLearningBenchmarks.jl](https://gitlab.naze.baffier.fr/others/ConstraintLearningBenchmarks.jl) :
  branche `feat/core-witness-recovery`, banque et intégration sauvegardées au
  commit `429175f35687c766a87db3db78c39b6baf025ec0` ; rejeu complet sauvegardé au
  commit `b340e83a72ed19acd1f1647edaafb9e363738f0f`.
- 533 assertions du package, 30 d'intégration MetaStrategist et 21 165 du rejeu
  complet passent sur la machine actuelle, avec un CPU logique et un thread de
  solveur. Le rejeu couvre les 637 témoins et 6 886 affectations, conserve les
  empreintes MILP et désactive les recettes Core pendant la reconstruction.
- Le rejeu en `--compile=min -O0` a atteint son plafond de dix minutes après
  400 témoins. Le contrôle complet en `--compiled-modules=existing -O1` passe en
  17,9 secondes après chargement. Ce temps qualifie une méthode de contrôle,
  sans établir un classement de performances des solveurs.

Les dépôts privés ConstraintModels et COPInstances ont été retrouvés et clonés
sous `~/.julia/dev`. Leurs références disponibles sont respectivement
`8cea440a807d1e01b33bda7ef26f79100ea5e17b` et
`dfc7344c8948550d0895968f6ad29a98449d643e`.
Ils ne contiennent pas les sources de `ConstraintModels/src/benchmarks` ni
l'ancienne API `COPInstances.download_dataset` référencées par les lanceurs
LiLim. Les inventaires SHA de Benchmarks conservent les empreintes de ces
fichiers perdus, mais pas leur contenu. Les lanceurs historiques ne sont donc
pas encore reproductibles sur cette machine. La reprise reconstruit un lecteur
et un validateur PDPTW versionnés et les contrôle contre des cas exhaustifs,
sans déclarer une identité avec les sources perdues ni modifier les anciens
inventaires pour leur faire accepter les nouveaux fichiers.

| Étape | Livraison | Condition pour poursuivre |
|---|---|---|
| 0 Références | Plan sauvegardé, inventaire des versions et des adaptateurs ; commits et remotes des dépendances à figer | Aucun module ou poids essentiel uniquement dans un checkout non sauvegardé avant campagne |
| 1 Qualification | Deux familles choisies, modèles et validateurs cohérents ; diagnostic des coûts CBLS | Résultats corrects et budget pilote maîtrisé |
| 2 CBLS minimal | Évaluation utile, mouvements structurés et quelques profils ; réglage borné | Gain mesuré ou parité plausible justifiant la comparaison externe |
| 3 Références externes | Timefold et Hexaly qualifiés avec objectifs identiques | Absence de désavantage artificiel dû au modèle ou au score |
| 4 Hybride | Résolveur de méta-variables, fragments et bridges qualifiés | Amélioration utile sous budget total, sans invalidité globale |
| 5 Confirmation | Configurations figées, corpus réservé et rapport comparatif | Conclusion limitée aux familles, tailles et ressources effectivement testées |

Chaque étape se termine par une décision : poursuivre, corriger un obstacle
précis, ou arrêter cette piste. Si le coût du bridge domine, mesurer et améliorer
ce coût avant d'élargir les campagnes. Si le minimum de stratégies ne suffit
pas, présenter la limite et chiffrer le prochain développement au lieu d'engager
toute la roadmap pour obtenir à tout prix une victoire.

Le rapport destiné au partenaire doit relier les résultats à sa proposition
économique : quelles tâches peuvent être couvertes, quelles limites demeurent,
et ce que son financement permettrait d'étendre. L'automatisation avancée,
les nombreuses stratégies restantes, la synthèse de stratégies et les campagnes
massives restent des étapes financées possibles, pas des prérequis du pilote.

## Conservation des plans et de la provenance

Conserver roadmaps, plans d'implémentation, protocoles, décisions et configurations
de référence dans les dépôts privés appropriés. Pendant un travail actif,
commiter et pousser après chaque étape cohérente et au plus tard après environ
trente minutes de modifications significatives. Vérifier que le commit est bien
présent sur le remote ; un commit local seul ne protège pas d'une perte de machine.

Les dossiers de données volumineuses ne deviennent pas une sauvegarde exhaustive
obligatoire. Préserver dans les documents les identifiants de campagne, empreintes
de sources et de modèles, critères et références nécessaires pour reconstruire
la démarche. Ne pas embarquer les changements sans rapport avec l'étape livrée.
Avant d'utiliser la reconstruction XCSP3Bridges en campagne, lui attribuer une
révision sauvegardée sur son dépôt privé et figer les témoins utilisés.

## Point de reprise — pause explicite du 2 octobre 2026

Travail suspendu à la demande de l'utilisateur pour libérer les ressources.
L'automatisation de reprise est en pause ; attendre une instruction explicite
avant de reprendre les calculs ou le développement.

Les sources reconstruites de ConstraintModels sont sauvegardées à la révision
`4ddd8f65417ac8a8d6bb12add6faf0c0c84801c3` : lecteur Li-Lim et validateur
PDPTW contrôlés par 25 assertions. Le résolveur de méta-variables est sauvegardé
dans Benchmarks à `c091547442845eb0d7f67060e65aa39a27ad054a` ; ses 38 assertions
et les 592 assertions de comparaison exhaustive du modèle RO passent.

`LiLim/src/Hybrid.jl` et `LiLim/test/hybrid.jl` sont sauvegardés comme travaux
en cours. Le contrôleur assemble les pas CBLS et les réparations HiGHS sous
budget, avec validation des solutions originales. Ses tests n'ont pas été
lancés : une tâche concurrente a été détectée avant leur lancement, puis
l'utilisateur a demandé la pause. Le score actuel est calculé directement,
sans ICN. La prochaine étape, après autorisation de reprise, est de qualifier
ce contrôleur avant tout pilote comparatif. Aucun résultat comparatif de
performance n'est encore établi par cette reprise.

## Premier pilote livré le 4 octobre 2026

La reprise explicite a livré le [pilote qualifié](../LiLim/CURRENT_PILOT.md) et
son [bilan audité](../LiLim/results/pilot-20261004.md). La configuration et les
sources mesurées sont figées à
`fb609d3012d2cfc1e38974df6e1b85dbf7277e4d`. Les 2 051 contrôles passent et les
72 exécutions ont des solutions originales admissibles avec preuves scellées.
Les versions des dépendances et les poids manuels des programmes de bridge
sont conservés dans les preuves. Le score CBLS est direct, sans ICN.

L'hybride spécialisé gagne 9 comparaisons appariées contre CBLS seul, en égale
7 et en perd 2 ; contre la formulation HiGHS mesurée, les deux hybrides
gagnent 10 comparaisons, en égalent 6 et en perdent 2. Ces 18 paires mélangent
trois instances déjà exposées et deux budgets ; elles ne sont pas 18 instances
indépendantes. La cible lr101 n'est atteinte que pour une graine sur trois,
et lrc101 reste à 17 véhicules contre 14 dans la meilleure valeur publiée.
Le constat est un gain de prototype avec une limite claire de robustesse,
sans conclusion contre Timefold ou Hexaly.

Priorités avant extension : mouvements permettant de vider une route,
fragments de trois routes bornés, capture des états pour un rejeu apparié des
bridges, puis déclenchement guidé par stagnation/rendement sous MetaStrategist
léger. Un petit contrôle des graines HiGHS et du modèle RO évite de confondre
un avantage sur une référence particulière avec un avantage général.
Les profils seront réglés sur le corpus exposé et figés avant confirmation.
L'ancienne automation reste en pause après livraison du pilote.
