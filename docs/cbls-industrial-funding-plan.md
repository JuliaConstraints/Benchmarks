# Plan de benchmarks pour financer JuliaConstraints

Proposition du 2 octobre 2026, à exécuter par étapes. Ce document fixe la démarche ;
il ne rapporte pas une campagne nouvelle ni un accord de financement.

## Objectif et résultat attendu

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
| LiLim | Modèle MILP compact, initialisation par insertion et validation indépendante | L'insertion est une référence autonome, pas CBLS ; le pilote ne mesure pas l'hybridation |
| Méta-variables LSS | Groupes de variables, mouvements atomiques et interface de résolution avec budget | L'adaptateur de sous-problème HiGHS reste à réaliser et qualifier |
| MetaStrategist | Grammaire, plans et infrastructure d'exécution exploitables | Une orchestration adaptative complète ne doit pas être supposée disponible |
| XCSP3Bridges | Module reconstruit, compilation de réseaux entiers finis via les bridges CPE et raccordement à des variables MOI existantes | Pas de traduction complète déjà qualifiée de Li-Lim ; le checkout reconstruit n'a encore ni commit ni remote |

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

## Ordre de réalisation et décisions de poursuite

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
