# Plan de benchmarks pour financer JuliaConstraints

Proposition du 2 octobre 2026, à exécuter par étapes, complétée par les états
d'avancement datés ci-dessous. Elle fixe la démarche et ne vaut pas accord de
financement.

Consigne courante du 4 octobre : poursuivre la campagne comparative multi-jours
sur le corpus officiel complet, avec un objectif réaliste par étapes et sans
limite globale de durée. Hexaly reste en attente de l'accès effectif à sa licence
d'essai. Avant chaque lot de calculs, vérifier qu'aucune autre tâche Codex n'est
active ; si une tâche démarre, reporter le lot. Les lectures et mises à jour
documentaires peuvent continuer pendant cette attente. Les budgets de chaque
essai restent figés pour préserver la comparaison reproductible.

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

L'ancienne consigne d'automatisation, qui prévoyait une pause après le premier
pilote, est remplacée par la demande ultérieure de campagne multi-jours. Avant
chaque lot, vérifier la liste actuelle des tâches, y compris les tâches épinglées,
en excluant ce chat, puis confirmer que les calculs et rendus antérieurs sont
terminés. Refaire ces contrôles entre les lots. Dès qu'un rapport ou des figures
sont prêts, les sauvegarder par commit et push sur GitLab avant d'élargir la
campagne.

## Objectif et résultat attendu

### Premier pilote officiel SINTEF — 5 octobre 2026

Le [rapport et ses figures](../LiLim/results/sintef-campaign-10s-1t-trio-bdc0c48-20261005/report.md)
présentent 90 essais sur LC101, LR101 et LRC101 : dix profils CBLS/ICN, hybrides
et HiGHS, trois graines, dix secondes par essai et un thread fixé sur un cœur P.
Les 90 solutions et leurs trajectoires ont passé le validateur original ; chaque
profil a utilisé en moyenne un CPU actif.

LC101 atteint la référence avec tous les profils à partir du départ commun. Sur
LR101, l'hybride ICN spécialisé et HiGHS natif l'atteignent chacun sur une graine
différente. L'hybride bridgé ne l'atteint pas dans ce lot. Aucun profil n'atteint
la référence LRC101 en dix secondes. Les variantes ICN fusionnées ne montrent
pas de gain de qualité mesurable ici. Ce résultat reste un diagnostic court sur
trois instances ; il ne permet pas de conclure sur les 354 instances, les autres
largeurs de thread ni les budgets plus longs.

La suite immédiate est de répéter les mêmes instances, graines, profils et
budgets à 2, 4, 8 et 16 threads pour isoler l'effet de la largeur. Après cette
comparaison, étendre les profils retenus au corpus officiel complet et allonger
les budgets selon les paliers fixés dans le protocole.

### État du 4 octobre 2026 après qualification ICN et diagnostic GC

Le [bilan des 369 essais](../LiLim/results/icn-threads-20261004.md) et les figures
de réussite/anytime conservent leurs sources et budgets. Le
[diagnostic PerfChecker/SnoopCompile](../LiLim/results/icn-performance-20261004.md)
conduit à des buffers privés par worker et une correction d'itération du noyau.
Sur le contrôle LC101 à seize threads, l'occupation atteint 15,97 CPU actifs et
les allocations passent de 36,09 Go à 256 Mo sur cinq secondes. Ce résultat
qualifie le débit ; il n'est pas une preuve de supériorité sur la qualité.
Une capture séparée de la boucle chaude atteint 15,986 CPU actifs et ne mesure
aucun temps de GC pendant les trois recherches de cinq secondes ; la collecte
forcée avant leur départ reste comptée dans le coût de l'appel complet.

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

Le [premier bilan Timefold](../LiLim/results/competitors-20261004.md) comprend
90 essais natifs Community et 45 contrôles CBLS/ICN actuels, à cinq secondes,
sur 1/2/4/8/16 workers. CBLS gagne les 60 paires LR101/LRC101 contre les deux
profils testés et égale les 30 paires LC101. Aucun BKS LR101/LRC101 n'est atteint.
Les modèles, scores, budgets et sorties sont qualifiés, mais le corpus exposé,
trois graines et les réglages non optimisés limitent cette conclusion au pilote.
Hexaly dispose du modèle et du contrat d'échange ; sa qualification native et
sa campagne attendent un exécutable disponible. Ne pas compter cette préparation
comme un résultat comparatif ni comme le démarrage de la licence d'essai.
Le [bilan élargi des variantes](../LiLim/results/all-variants-20261004.md)
ajoute HiGHS, CBLS naïf/ICN/natif, les hybridations et deux allocations
MetaStrategist aux cinq largeurs ; il distingue médianes et meilleurs essais.

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

### Vérification d'intégrité du corpus complet, 4 octobre 2026

Un audit SHA-256 en lecture seule a confirmé les 354 fichiers d'instances SINTEF
extraits par rapport à `LiLim/config/sintef-pdptw-bks-20261004.toml`, avec le
nombre attendu dans chaque groupe de tailles. Les six archives sources
correspondent aussi aux empreintes enregistrées. Aucun fichier ne manque et
aucune empreinte ne diffère. Ce contrôle établit la provenance binaire et
l'inventaire du corpus officiel ; il ne qualifie pas à lui seul l'import des
instances, la qualité des solutions ou le validateur indépendant. Le lanceur du
corpus complet répète ces vérifications avant chaque campagne.

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
Ce pilote est une étape de qualification ; il ne clôt pas la campagne demandée
ensuite.

## Campagne complète SINTEF préparée le 4 octobre 2026

La demande ultérieure élargit l'étape de confirmation aux 354 instances Li-Lim
officielles. Les six archives sont conservées sous `LiLim/data/raw/sintef-archives`;
leurs SHA-256 correspondent à la table SINTEF figée le 4 octobre. Les 354 fichiers
extraits sont recensés par empreinte dans
[`sintef-pdptw-bks-20261004.toml`](../LiLim/config/sintef-pdptw-bks-20261004.toml).
Les données brutes restent locales et ne sont pas nécessaires dans les commits.

Le protocole initial fixe les largeurs 1/2/4/8/12/16/20 sur les 20 CPU logiques
disponibles, en commençant par un cœur P distinct par voie, puis les cœurs E et
les frères SMT. Il prévoit des paliers de 10/30/60/120/300/600 secondes. Les
résultats conservent chaque graine, le meilleur résultat observé, la moyenne, la
médiane réelle d'une exécution, l'écart-type, l'étendue, la faisabilité, les
atteintes de référence SINTEF et les temps pour les atteindre. Les distances
restent secondaires à la flotte et sont comparées au BKS lorsque la flotte
correspond. Les absences de résultats ne sont pas comptées comme des échecs de
faisabilité.

La page officielle indique que les objectifs sont hiérarchiques et que les
distances de référence sont publiées à deux décimales
([table SINTEF](https://www.sintef.no/projectweb/top/pdptw/li-lim-benchmark/),
[cas 100](https://www.sintef.no/projectweb/top/pdptw/100-customers/)). Le taux
d'atteinte compare donc la flotte exactement, puis arrondit le résultat candidat
à deux décimales avant de le comparer à la valeur affichée. Les classements,
moyennes et écarts conservent les distances brutes en double précision. La
tolérance `1e-6` reste réservée à l'égalité de distances entre essais appariés;
elle ne sert pas à comparer un résultat brut au BKS arrondi.

Les programmes
[`full_corpus_campaign.jl`](../LiLim/scripts/full_corpus_campaign.jl),
[`full_corpus_report.jl`](../LiLim/scripts/full_corpus_report.jl) et
[`full_corpus_plots.jl`](../LiLim/scripts/full_corpus_plots.jl) apportent le
lanceur reprenable, le rapport anglais et les figures exactes ou XKCD. Chaque
essai est écrit atomiquement dans son propre fichier et scellé par SHA-256 ; une
reprise contrôle le protocole, les sources, la cohorte, l'environnement, la
solution et tous les points de trajectoire dans le problème original. La
commande exige une affinité CPU explicitement conforme à la topologie figée.
Avant lancement, commencer par un lot diagnostique à 10 secondes sur LC101,
LR101 et LRC101, puis vérifier les nouveaux chemins ICN fusionnés. Les résultats
ci-dessus ne sont pas des résultats de cette campagne complète.

Le rapporteur et le générateur de figures acceptent aussi une campagne
incomplète : ils revalident chaque essai présent, publient le nombre planifié et
terminé, et séparent le taux de complétion du taux de faisabilité. À la fin de
chaque lot cohérent, produire le rapport anglais, le CSV par instance et les
figures exactes et XKCD à partir du résumé disponible, puis pousser ces livrables
avant de commencer le palier suivant. Une absence reste un essai manquant, jamais
un échec du solveur.

Le contrôleur de campagne actuelle évalue CBLS naïf, score direct, ICN récupérés,
hybrides spécialisé et bridgé, HiGHS natif, portefeuilles HiGHS et allocations
MetaStrategist. Les profils Timefold et Hexaly attendent leurs adaptateurs
qualifiés sur le corpus complet. Hexaly Optimizer reste soumis à l'examen de la
licence d'essai ; aucun résultat commercial ne sera ajouté avant l'accès effectif.

### Coordination courante de la campagne — 4 octobre 2026

L'utilisateur a demandé de tenir compte du travail PerfChecker et du chat
`01a0df72-50d8-72b3-9424-f67bb7a2aa19` avant de consommer les ressources locales.
Au dernier contrôle, seul le chat PerfChecker restait actif ; son travail attendait
des runners GitHub et ne lançait pas de calcul Julia local. Plusieurs serveurs MCP
Julia observés sur la machine étaient inactifs (0 % CPU) et ne correspondaient pas
à des lots de solveur. Aucun calcul de cette campagne ne commence tant qu'une
autre tâche Codex reste active. Le contrôle des tâches et des processus est refait
juste avant chaque lot ; toute nouvelle tâche reporte le lot. Tout nouveau jeu de
figures est commité et poussé dès qu'il est prêt.

## Comparaison à 2 threads — 5 octobre 2026

Le lot diagnostique à deux threads a terminé les **90/90 essais** sur lc101,
lr101 et lrc101, avec les mêmes trois graines et dix secondes par essai que le
lot à un thread. Toutes les solutions et trajectoires ont été revérifiées par le
validateur Li-Lim original. Le [rapport détaillé](../LiLim/results/sintef-campaign-10s-2t-trio-bdc0c48-20261005/report.md)
publie les valeurs par instance, moyenne, écart-type, médiane réelle, temps
d'atteinte SINTEF et les quatre figures exactes et XKCD en anglais.

Le nombre de réussites BKS reste à 3/9 pour CBLS naïf, appris ICN, direct, ICN
fusionné et mix de stratégies. L'hybride ICN spécialisé atteint 4/9, le bridge
3/9, HiGHS natif 4/9 et son portefeuille série 5/9. Comparé au lot à un thread,
le portefeuille HiGHS passe de 4 à 5 réussites ; son écart moyen de flotte
descend de 2,111 à 1,889 véhicule et l'écart de la vraie exécution médiane de
2,333 à 1,667. Les variantes CBLS gardent les mêmes taux sur ce trio et les
hybrides spécialisés restent à 4/9. C'est un signal exploratoire, limité aux
trois instances déjà exposées ; aucune sélection de stratégie n'a été faite
après lecture des résultats.

L'occupation CPU moyenne confirme environ 2,00 processeurs actifs pour CBLS,
1,98 pour l'hybride bridgé, 1,85 pour le portefeuille HiGHS et 1,03 pour HiGHS
natif à deux threads alloués. Les deux voies CBLS/hybrides saturent donc les
cœurs qui leur sont réservés ; le HiGHS natif n'emploie pas en continu son
budget de deux cœurs sur ces essais. Le palier à deux threads n'inclut pas encore
les deux plans MetaStrategist, réservés aux largeurs d'au moins quatre threads.

La suite immédiate est le même trio à 4 threads, où les deux allocations
MetaStrategist deviennent disponibles, puis à 8 et 16 threads. Conserver les
instances, graines, objectifs et budget pour isoler la largeur avant d'étendre
les profils retenus au corpus des 354 instances et aux budgets supérieurs.

## Comparaison à 4 threads — 5 octobre 2026

Le lot à quatre threads a terminé les **108/108 essais** sur le même trio,
avec les mêmes graines et budgets ; les deux allocations fixes MetaStrategist
sont incluses. Les 108 solutions et toutes les trajectoires ont été revalidées
sur les instances Li-Lim originales. Le [rapport et les figures exactes et
XKCDMakie en anglais](../LiLim/results/sintef-campaign-10s-4t-trio-bdc0c48-20261005/report.md)
incluent les temps vers les cibles SINTEF, le meilleur, la moyenne, la médiane
réelle et l'occupation CPU.

Sur les neuf essais par profil, les variantes CBLS seule (naïve, ICN appris,
score direct, ICN fusionné et mix de stratégies) font chacune 3/9 réussites
BKS. L'hybride spécialisé, l'hybride bridgé et les deux allocations
MetaStrategist font 4/9 ; HiGHS natif fait 4/9, et le portefeuille HiGHS 5/9.
Les meilleures exécutions de l'hybride spécialisé réduisent l'écart moyen de
flotte à 0,333 véhicule par instance ; le portefeuille HiGHS a le plus de
réussites BKS. Aucun profil n'atteint la référence LRC101 dans cette fenêtre de
dix secondes. Les taux restent des mesures exploratoires sur trois instances
et trois graines, pas un classement général ni une comparaison Hexaly.

Les variantes CBLS et hybrides spécialisées utilisent en moyenne 3,84 à 4,00
CPU actifs sur quatre ; le HiGHS natif n'en utilise que 1,03. Le portefeuille
HiGHS atteint 3,76 CPU actifs. MetaStrategist en utilise 3,58 à 3,59 : les
allocations mixtes parallélisent effectivement le travail, mais ne saturent pas
encore leurs quatre cœurs autant que les profils de recherche locale seuls.
Les temps CPU incluent l'initialisation et la validation dans le budget.

La comparaison confirme le débit des variantes CBLS sur quatre workers, mais
la qualité BKS n'augmente pas pour CBLS seule entre 1, 2 et 4 threads sur ce
trio. Le résultat à 8 threads suit.

## Comparaison à 8 threads — 5 octobre 2026

Le lot à huit threads a terminé les **108/108 essais** sur lc101, lr101 et
lrc101. Les mêmes douze profils, graines, budget, empreintes et validateurs
originaux sont conservés. Le [rapport complet et ses figures précises et
XKCDMakie en anglais](../LiLim/results/sintef-campaign-10s-8t-trio-bdc0c48-20261005/report.md)
publie les distributions et l'usage CPU.

CBLS seul garde 3/9 réussites BKS, contre 4/9 pour les deux hybrides et HiGHS
natif. Le portefeuille HiGHS et MetaStrategist équilibré atteignent chacun 6/9 ;
MetaStrategist recherche-intensive atteint 4/9. Sur LRC101, MetaStrategist
équilibré trouve 15 véhicules pour la graine 43 et l'hybride ICN spécialisé
trouve la même flotte sur cette graine ; les deux restent hors de la référence
SINTEF. Sur LR101, le portefeuille HiGHS et MetaStrategist équilibré atteignent
la référence sur les trois graines, tandis que l'hybride spécialisé l'atteint
sur une. Ces nombres suggèrent un intérêt du portfolio mixte, mais trois
instances et trois graines ne suffisent pas à départager les profils de façon
fiable.

CBLS seul utilise 7,98 à 7,99 CPU actifs sur huit. Les deux hybrides sont à
7,50–7,81, HiGHS natif à 1,04, le portefeuille HiGHS à 7,18, et MetaStrategist
à 7,05–7,51. CBLS sature donc huit workers dans ce cas ; l'allocation mixte
équilibrée reste sous son budget de huit processeurs, tout en augmentant de
6,03 à 7,05 CPU actifs par rapport au palier quatre threads. Le pool HiGHS
natif ne tire toujours pas parti de tous les threads pour ces instances.

La machine est un Intel Core i7-12700 : 12 cœurs physiques, dont huit cœurs P
avec deux processeurs logiques chacun et quatre cœurs E à un processeur logique
chacun. Le lot 8 threads utilise un processeur logique par cœur P. Selon l'ordre
d'affinité figé, le lot à 16 threads combinera huit cœurs P, quatre cœurs E et
quatre processeurs logiques SMT supplémentaires sur les cœurs P. Cette largeur
mesure donc l'allocation hybride de 16 workers, pas l'effet pur de SMT. Une
expérience P-only distincte pourra isoler SMT plus tard si ce point est
important. Puis les budgets augmenteront par puissances de deux sur les profils
retenus avant d'élargir le corpus officiel au-delà du trio pilote.

## Comparaison à 16 threads — 5 octobre 2026

Le lot à seize workers a également terminé les **108/108 essais** et revérifié
chaque solution et chaque point de trajectoire avec le validateur Li-Lim
original. Le [rapport, les données reproductibles et les figures exactes et
XKCDMakie en anglais](../LiLim/results/sintef-campaign-10s-16t-trio-bdc0c48-20261005/report.md)
consignent l'affinité réellement employée : huit cœurs P, quatre cœurs E et
quatre fils SMT des cœurs P.

Les taux BKS sont 3/9 pour CBLS seul, 4/9 pour chacun des deux hybrides, 4/9
pour HiGHS natif, et 6/9 pour HiGHS portfolio et MetaStrategist équilibré.
MetaStrategist recherche-intensive reste à 4/9. Face au palier 8 threads, ces
taux restent stables. Les écarts moyens de flotte s'améliorent cependant pour
CBLS naïf/ICN/direct (1,111 à 0,889), hybride spécialisé (0,778 à 0,556) et
bridgé (1,000 à 0,667) ; ils sont stables pour les deux meilleurs portfolios.
Personne n'atteint le BKS LRC101 en dix secondes. Ces écarts proviennent d'une
campagne courte et ne suffisent pas à déclarer un avantage reproductible.

Les variantes CBLS atteignent 14,72–15,98 CPU actifs en moyenne ; les hybrides
15,35 (spécialisé) et 14,37 (bridgé). MetaStrategist atteint 14,07 pour
l'allocation équilibrée et 15,10 pour l'allocation recherche-intensive. Ainsi,
le mélange matériel à 16 workers reste très occupé. CBLS mobilise environ deux
fois plus de CPU actifs qu'à huit threads, sans améliorer son taux BKS sur ce
trio. Ces compteurs ne mesurent pas le nombre de mouvements évalués par seconde ;
un test de débit dédié devra établir si le débit utile double aussi. Le
portefeuille HiGHS utilise 14,22 CPU actifs, alors que HiGHS natif demeure à
1,07.

Les quatre largeurs demandées sont maintenant couvertes à 1/2/4/8/16, à budget
constant de dix secondes. Avant d'augmenter les durées, comparer le débit par
cœur et les résultats moyens aux meilleurs ; garder en tête que le palier 16
ajoute des cœurs E et n'est pas un pur test SMT. La prochaine série conserve le
même petit corpus pour 30, 60 et 120 secondes, puis 300 et 600 secondes, avec
les profils retenus uniquement si leur classement reste cohérent.

## Premier palier long — 30 secondes à 1 thread

Le premier lot de trente secondes a terminé les **90/90 essais** à un thread.
Le [rapport détaillé et ses figures précises et XKCDMakie en anglais](../LiLim/results/sintef-campaign-30s-1t-trio-bdc0c48-20261005/report.md)
confirment que toutes les sorties restent validées sur le problème original et
que chaque méthode consomme en moyenne un CPU actif.

CBLS naïf, ICN appris, direct et ses deux ablations fusionnées restent à 3/9
réussites BKS. L'hybride spécialisé atteint 4/9, l'hybride bridgé 4/9, HiGHS
natif et son portefeuille série 4/9. Par rapport au diagnostic à dix secondes,
le seul gain de taux BKS est l'hybride bridgé (3/9 à 4/9) ; les écarts moyens
de flotte restent inchangés et aucun profil n'atteint LRC101. Un budget plus
long à un seul worker ne suffit donc pas à améliorer nettement CBLS sur ce trio.

Le prochain lot garde trente secondes et passe à deux threads. Les mesures
suivantes conserveront budget, instances et graines pour séparer l'effet de la
largeur de thread de celui du temps de recherche avant le palier 60 secondes.

## Budget de 30 secondes à 2 threads

Le lot à deux threads a également terminé les **90/90 essais** et passé toutes
les sorties au validateur original. Son [rapport et ses figures en anglais,
exactes et XKCDMakie](../LiLim/results/sintef-campaign-30s-2t-trio-bdc0c48-20261005/report.md)
indiquent deux CPU actifs pour CBLS seul, environ 1,98–1,99 pour les hybrides,
1,19 pour HiGHS natif et 1,80 pour son portfolio.

Les résultats BKS sont 3/9 pour CBLS seul, 4/9 pour chacun des deux hybrides,
4/9 pour HiGHS natif et 5/9 pour le portfolio HiGHS. Entre les lots 10 et 30
secondes à deux threads, CBLS et le portfolio gardent les mêmes taux et les
mêmes écarts moyens ; le bridge passe de 3/9 à 4/9. Sur LR101, le portfolio
atteint le BKS aux graines 42 et 43, HiGHS natif à la graine 43 et chaque
hybride à la graine 41. Aucun profil n'atteint LRC101. L'augmentation du budget
seul ne montre donc pas encore de gain stable pour CBLS.

La prochaine largeur à trente secondes est 4 threads, qui ajoute les profils
MetaStrategist ; poursuivre ensuite à 8 et 16 threads avant de passer au palier
60 secondes.

## Budget de 30 secondes à 4 threads

Le lot à quatre threads a terminé et qualifié les **108/108 essais** : douze
profils, trois graines et trois instances officielles. Le [rapport détaillé,
les données agrégées et les figures exactes et XKCDMakie en anglais](../LiLim/results/sintef-campaign-30s-4t-trio-bdc0c48-20261005/report.md)
revalident chaque solution et chaque point de trajectoire contre le validateur
Li-Lim original.

L'hybride ICN spécialisé et le portfolio HiGHS atteignent chacun le BKS sur
5/9 essais. L'hybride XCSP3Bridges, HiGHS natif et les deux allocations
MetaStrategist en atteignent 4/9. Chacun des profils CBLS seuls — résidu naïf,
ICN appris, erreur directe, deux ablations ICN fusionnées et mix de stratégies
— en atteint 3/9. Les écarts moyens de flotte favorisent l'hybride spécialisé
sur ce trio, mais les essais restent trop peu nombreux pour conclure à une
supériorité générale.

CBLS mobilise 3,99 à 4,00 CPU actifs en moyenne ; les hybrides 3,88 à 3,95.
HiGHS natif en utilise 1,47, son portfolio 3,67 et MetaStrategist 3,55–3,57.
Sur LRC101, aucun profil ne rejoint le BKS en 30 secondes ; l'hybride
spécialisé et MetaStrategist recherche-intensive trouvent toutefois une flotte
de 15 véhicules, au plus près des essais de ce lot. Le prochain palier garde
30 secondes et passe à 8 threads, puis 16, avant de commencer la série à
60 secondes.
