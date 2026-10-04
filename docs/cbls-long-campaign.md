# Campagne longue de comparaison CBLS / MetaStrategist

## Objectif

Établir, sur plusieurs familles classiques et avec des budgets croissants, où
CBLS et MetaStrategist sont compétitifs, où ils ne le sont pas, et quelles
améliorations de la roadmap changent effectivement le résultat. Les mesures
commerciales sous licence d'essai — Hexaly et autres — restent réservées à la
reprise de l'utilisateur. D'ici là, comparer les moteurs libres et les
implémentations disponibles, sans présenter les petites instances de diagnostic
comme une preuve de supériorité générale.

Le présent document est le journal de suivi du dépôt privé GitLab : chaque étape
terminée ajoutera son protocole, son bilan, ses figures (tous les libellés des
figures sont en anglais) et le commit mesuré. Les données brutes volumineuses
peuvent rester sur la machine ; les résultats résumés, empreintes, versions,
validations et plots destinés à la consultation à distance seront poussés ici.

## Résultats déjà accessibles

Le premier comparatif toutes variantes contient 504 essais revalidés sur LC101,
LR101 et LRC101, avec cinq secondes par essai et 1/2/4/8/16 workers. Il couvre
CBLS naïf, ICN, score direct et mixte, les deux hybrides HiGHS, HiGHS natif et
multi-départ, deux allocations MetaStrategist et deux profils Timefold
Community. Ces cas servent de diagnostic, pas de confirmation industrielle.

- [Bilan et tableau des résultats](../LiLim/results/all-variants-20261004.md)
- [Médianes de toutes les variantes](../LiLim/results/figures-20261004/all-variants-quality.png)
- [Taux de réussite et améliorations](../LiLim/results/figures-20261004/all-variants-success-matrix.png)
- [Trajectoires à 8 et 16 workers](../LiLim/results/figures-20261004/all-variants-anytime-8t.png),
  [8 workers XKCD](../LiLim/results/figures-20261004/all-variants-anytime-8t-xkcd.png),
  [16 workers XKCD](../LiLim/results/figures-20261004/all-variants-anytime-16t-xkcd.png)
- [Utilisation CPU](../LiLim/results/figures-20261004/all-variants-cpu.png)
- [CBLS contre Timefold](../LiLim/results/figures-20261004/competitors-quality.png)
- [Débit, allocations et GC](../LiLim/results/figures-20261004/icn-performance.png)

Le nouveau point 16 workers a été capturé séparément du fragment partiel déjà
présent dans le dossier de résultats. Il est complet et son empreinte figure
dans le résumé agrégé. GHOST et JuLS n'ont pas de captures comparables dans ce
lot ; Hexaly n'est pas exécuté. La capture Timefold représente des recherches
Community indépendantes et séquentielles, pas le parallélisme natif d'une
résolution.

## Hexaly : estimation et comparabilité pour Li-Lim

Le [benchmark PDPTW publié par Hexaly le 27 mars 2026](https://www.hexaly.com/benchmarks/hexaly-vs-google-or-tools-pickup-and-delivery-problem-with-time-windows-pdptw)
rapporte, après une minute, un écart moyen à la meilleure valeur connue de 0 %
pour la taille 100 et de 0,1 % pour la taille 200. L'article utilise Hexaly
15.0, OR-Tools 9.14 avec ses paramètres par défaut et une machine Ryzen 7 7700
à 8 cœurs, 3,8 GHz et 32 Go. Ce résultat suggère que Hexaly sera un concurrent
très fort, et probablement devant le prototype CBLS actuel sur la qualité à
court budget pour les petites Li-Lim. Il s'agit d'une estimation, pas d'un
résultat comparatif reproduit chez nous.

La page de benchmark dit que la littérature minimise d'abord le nombre de
véhicules puis la distance, mais son modèle affiché minimise le retard total
puis la distance arrondie au centième, sans objectif flotte; son tableau ne
rapporte que l'écart de distance à la meilleure valeur connue. Le
[template PDPTW officiel](https://www.hexaly.com/templates/pickup-and-delivery-problem-with-time-windows-pdptw)
est différent : il minimise aussi le nombre de camions lorsque `nbMaxTrucks`
n'est pas défini. Il faut donc figer le modèle et ce paramètre effectivement
utilisés par le benchmark publié avant de prétendre le reproduire.

L'article annonce les paramètres par défaut mais ne donne pas le nombre de
threads utilisé. La documentation Hexaly 15.0 indique que `nbThreads = 0`
adapte automatiquement les threads au modèle et à la machine. Mesurer ensuite
les threads réellement consommés. À l'essai, faire deux passages sur le même
plafond de huit cœurs physiques : défaut automatique, puis huit threads
explicitement fixés. Pour l'objectif Li-Lim officiel, comparer flotte puis
distance en double précision et appliquer le validateur officiel; rapporter
aussi l'écart à la meilleure distance connue, le temps de première solution
faisable, la flotte, les fils et le temps mural end-to-end. Garder une ligne
distincte reproduisant l'objectif du code de benchmark Hexaly si la version
exacte peut être récupérée. Jusqu'à cette étape, ne pas annoncer Hexaly comme
battu ou égalé.

Les six archives officielles sont maintenant présentes sous
`LiLim/data/raw/sintef-archives/`, et leurs 354 fichiers d'instances sont
extraits dans `LiLim/data/raw/sintef-pdptw/`. Les effectifs vérifiés sont
56/60/60/60/60/58 pour les tailles 100/200/400/600/800/1000. Les 354 clés de
la table des meilleures valeurs connues publiée par SINTEF correspondent
exactement aux 354 fichiers locaux. La référence figée et les empreintes des
pages et archives sont dans
[`LiLim/config/sintef-pdptw-bks-20261004.toml`](../LiLim/config/sintef-pdptw-bks-20261004.toml).

Le premier passage de comparaison reproduira le budget fournisseur de 60 s sur
toutes les 354 instances, avec un profil CBLS/ICN et un profil MetaStrategist
gelés, puis Hexaly quand l'installation sera autorisée. Le second budget
fournisseur de 600 s sera appliqué aux meilleurs finalistes, puis étendu si les
gains de qualité continuent. Une reproduction intégrale 60+600 s coûte au plus
64,9 heures par profil avant répétitions. Le benchmark publié ne donne ni
graine ni nombre de fils effectif. La comparaison locale enregistrera donc le
défaut automatique de Hexaly et le nombre de fils observé, puis ajoutera un
passage à 8 fils explicites. Le Ryzen publié a 8 cœurs et notre machine est
différente : limiter à 8 cœurs P, et consigner séparément l'essai 16 fils SMT,
permettra de comparer des budgets proches sans prétendre à une égalité de
matériel.

## Couverture à construire

Les candidats ci-dessous viennent des sources et manifests retrouvés dans les
dépôts. La présence dans un catalogue ne signifie pas encore que notre modèle,
score, validateur et lancement sont qualifiés.

| Famille | Disponibilité et candidats | Comparaisons à qualifier |
|---|---|---|
| PDPTW / Li-Lim | Corpus officiel SINTEF complet présent localement : 354 fichiers sur les tailles 100/200/400/600/800/1000, avec références de meilleure valeur connues figées | CBLS/ICN, CBLS direct et stratégies mixtes, méta-variables + HiGHS, HiGHS complet, Timefold, GHOST, JuLS ; OR-Tools Routing à évaluer |
| Vehicle routing classique | Corpus Solomon/CVRPTW et autres cas à inventorier et empreinter avant sélection | Timefold, OR-Tools Routing, GHOST/JuLS et CBLS avec budgets muraux égaux ; HiGHS comme contrôle adapté au modèle |
| Car sequencing | Le plan industriel a inventorié 30 cas CSPLib stratifiés sur 200/300/400 voitures et 109 XML XCSP3 | CBLS/MetaStrategist, solveur de programmation par contraintes libre et OR-Tools CP-SAT si son modèle est sémantiquement identique ; Hexaly après le retour |
| Graph partitioning | Douze candidats modérés répertoriés dans le plan ; onze matrices SuiteSparse à acquérir/empreinter, plus deux graphes KaHIP | CBLS, MetaStrategist, KaHIP et METIS comme solveurs spécialisés ; HiGHS sur voisinages ou régions réduites |
| XCSP3 Core réel | `COPInstances` référence onze problèmes officiels de compétition et un exemple de spécification ; seul ce dernier est déjà stocké localement | Pilote de faisabilité CBLS/ICN et de MetaStrategist sur un sous-ensemble résolu par plusieurs moteurs disponibles |
| Instances de réglage classiques | Les scripts de tuning existants utilisent permutation, Golomb ruler et N-Queens | Recherche des bons profils et stratégies ; les garder séparées des confirmations de routage et des autres familles |

Les références, licences, archives, versions et empreintes seront revérifiées
avant téléchargement ou inclusion. Pour chaque famille, conserver l'objectif et
les contraintes officiels, distinguer faisabilité et qualité, puis réserver des
instances de confirmation qui ne servent pas au réglage. Ne pas agréger des
distances en ignorant la flotte, ni confondre XCSP3 Core et les archives entières
de compétition.

## Ressources et protocole de mise à l'échelle

La topologie locale constatée par `lscpu` est de **20 CPU logiques et 12 cœurs
physiques** : 8 cœurs P à deux fils logiques chacun et 4 cœurs E à un fil chacun.
La grille doit donc inclure **1, 2, 4, 8, 12, 16 et 20 workers** : 8 correspond
aux cœurs P principaux ; 12 utilise un worker par cœur physique ; 16 ajoute
quatre frères SMT ; 20 utilise les vingt fils logiques. Les résultats à 8 et 16
ne suffisent pas à attribuer l'effet aux cœurs E et au SMT.

La liste `taskset` limite les CPU éligibles mais ne fixe pas un worker Julia à
un cœur précis. Le protocole de mise à l'échelle enregistrera l'affinité permise,
les CPU réellement occupés, les cœurs P/E sollicités si la mesure système le
permet, la fréquence si disponible, le CPU/wall, le débit, les allocations et le
GC. Chaque solveur est plafonné au même nombre de CPU logiques disponibles ;
les pools imbriqués HiGHS/Julia ne doivent pas sur-abonner la machine.

Échelle de budget de recherche, en secondes : **8, 16, 32, 64, 128, 256, 512,
1 024, 2 048, 4 096, ...**. Les premiers échelons couvrent le criblage rapide,
puis les durées se rapprochent de 10 s, 30 s, 1 min, 2 min, 4 min, 8 min et
17 min. Les résultats antérieurs à cinq secondes restent une ligne de base
distincte. Chaque échelon commencé est terminé pour ses cellules annoncées ; les
configurations et instances éliminées après une étape le sont selon une règle
écrite avant de consulter l'étape suivante. Réserver un budget global, prévoir
les mesures hors solveur et élargir les échelons sans fabriquer d'estimation de
fin calendaire.

Les phases servent des objectifs différents :

1. **Qualification et ligne de base** : sources figées, tests de correction,
   fonctions d'erreur ICN identifiées, coût de démarrage séparé du temps total,
   `PerfChecker` sur un appel CBLS et un portefeuille MetaStrategist représentatif.
2. **Échelle des cœurs** : 1/2/4/8/12/16/20 sur Li-Lim difficile, plus les
   configurations historiques pour relier les courbes. Répéter les graines et
   équilibrer l'ordre des solveurs.
3. **Criblage des variantes** : toutes les variantes applicables et instances de
   réglage à 8/16/32 s ; `PerfChecker` avant/après toute modification de noyau ou
   stratégie. Le profiling n'est pas inclus dans un chrono comparatif, car il
   perturbe la recherche.
4. **Montée des durées** : faire avancer les finalistes par doublements,
   jusqu'à 1 024 s puis au-delà si la qualité ou le temps d'atteinte continue à
   évoluer. Ajouter une stratégie de roadmap seulement quand les profils et
   traces désignent une limite qu'elle peut traiter ; mesurer son ablation.
5. **Confirmation** : configurations gelées sur des instances réservées,
   répétitions indépendantes et comparaison avec les solveurs libres appropriés
   à chaque famille. Les campagnes commerciales reprendront après le retour de
   l'utilisateur.

Les mesures principales utilisent le même budget mural total, graines ou
répétitions appariées lorsque l'API le permet, et validateurs indépendants.
Publier qualité à budgets fixés, faisabilité, réussite aux meilleures valeurs
connues, temps d'atteinte, distributions entre graines et courbes anytime.
Rapporter séparément l'initialisation, le chargement/compilation, le warm-up,
la recherche, la collecte GC et l'audit final. Le meilleur résultat d'un lot ne
remplace pas sa médiane.

## Objectifs prioritaires sur plusieurs jours

L'ordre ci-dessous évite de dépenser des journées de calcul sur une fonction
d'erreur mal identifiée ou un score dont le coût domine déjà la recherche.
Chaque phase produit une décision documentée ; une absence de gain mesuré est
un résultat exploitable et arrête les branches qui en dépendent.

### 1. Statistiques fiables sur les recherches heuristiques

Pour chaque instance, budget, variante et allocation de ressources, conserver
chaque graine et chaque solution validée. Publier au minimum le meilleur résultat
avec le nombre de répétitions explicite, la moyenne arithmétique, la médiane,
l'écart-type, l'intervalle interquartile, le taux de faisabilité et le temps
d'atteinte des seuils BKS. Pour l'objectif lexicographique Li-Lim, rapporter
séparément la flotte et la distance conditionnelle aux solutions faisables ; ne
pas fabriquer une moyenne qui mélange des flottes différentes. Ajouter un
intervalle de confiance sur les agrégats des instances de confirmation et
montrer les distributions, pas seulement un meilleur run.

Le criblage commence avec cinq graines appariées ; les profils finalistes
reçoivent au moins vingt graines sur les instances de confirmation. Si l'écart
entre profils reste du même ordre que l'incertitude, augmenter les répétitions
avant de déclarer un vainqueur. Figer les graines et l'ordre des cellules avant
chaque passe. Un profil qui a fini plus tôt reste compté avec son temps réel et
son motif d'arrêt.

### 2. Refaire et étendre les fonctions d'erreur Li-Lim

La banque actuellement chargée par CBLS ne contient pas encore des fonctions
apprises sur les distributions de contraintes Li-Lim : trois témoins ICN
récupérés représentent les familles scalaire, égalité de liste et ordre strict.
Ils alimentent les contraintes de flotte, temps, capacité, route et précédence.
Construire une expérience explicite, contrainte par contrainte, pour les bornes
de flotte, fenêtres temporelles, bornes de charge, même-route pickup/delivery et
précédence. Inclure la distance comme signal d'objectif de recherche, distinct
des erreurs de faisabilité.

Pour chaque contrainte, comparer une recette ICN apprise, la recette manuelle
existante et une recette manuelle retravaillée à partir des domaines et de la
structure des routes. Séparer les états utilisés pour apprendre, choisir les
poids et confirmer. Vérifier sur des cas synthétiques de bord et sur des états
Li-Lim que l'erreur est finie et non négative, vaut zéro exactement sur les
contraintes satisfaites, et distingue les violations utiles à la recherche.
Sauvegarder la grammaire, les poids, leur empreinte, le générateur d'états,
l'échantillon de confirmation et le coût d'apprentissage. Une recette n'entre
dans un solveur de campagne qu'après vérification dans le modèle original.

### 3. Expliquer puis réduire le surcoût ICN

Le diagnostic disponible répond déjà partiellement au souvenir de l'écart de
30 %. Dans le [comparatif ICN](../LiLim/results/icn-threads-20261004.md), les
scores direct et ICN sont numériquement identiques sur les états qualifiés, mais
sur LC101 le débit ICN est inférieur d'environ 28 à 33 % aux largeurs 1/2/4/8/16
(environ 0,78 contre 1,08 million de réinsertions/s à un thread). Le lot
contient trois graines et mesure un chemin de recherche précis ; ce n'est pas
une estimation universelle du coût d'ICN, et cela ne mesure pas une qualité
différente des solutions. La capture de performance complète est dans
[`icn-performance-20261004.md`](../LiLim/results/icn-performance-20261004.md).
Le bilan de 369 essais comptabilise 166,7 milliards d'appels aux décodeurs
ICN. Le score actuel appelle le décodeur scalaire séparément pour chaque résidu
de temps/charge et appelle deux autres décodeurs pour chaque paire. Une piste
précise à tester est de regrouper, dans des buffers privés, les résidus de même
sémantique puis d'évaluer un ICN vectoriel une fois par groupe — par exemple
une somme de parties positives pour les violations de fenêtres temporelles.
Ne pas mélanger dans le même groupe des inégalités de sens ou d'échelle
différents, ni des paires pickup-delivery indépendantes en une seule contrainte
`all_equal` globale. La sortie agrégée devra rester égale à la somme actuelle
sur un rejeu déterministe complet.

La fusion de plusieurs évaluations de contraintes n'a pas encore été testée dans
le chemin Li-Lim. Le commit CompositionalNetworks mesuré (`ac70b743`) compile les
réseaux simples à quatre couches en code spécialisé en place, et le compilateur
fusionne déjà certaines paires transformation/agrégation. Cela peut optimiser
des opérations à l'intérieur d'un décodeur ; les alias fusionnés ne sont pas
tous des choix de poids apprenables, et cela ne regroupe pas les millions de
décodages séparés effectués par le score. L'empreinte actuelle prouve les appels
ICN, pas quelle branche du compilateur a été sélectionnée pour chacun des trois
témoins. Il faut donc extraire les IR des témoins et vérifier cette branche sur
l'environnement figé avant d'attribuer le surcoût à une opération.
Avant toute modification, faire une comparaison PerfChecker sur une séquence
figée d'états et de candidats, puis profiler l'évaluation de bout en bout.
Repérer les compositions récurrentes — résidu scalaire, ordre, égalité,
agrégation et décodage de route — et tester le plus petit noyau composé qui
élimine du dispatch ou des buffers sans changer le résultat. Si le chemin
spécialisé actuel ne couvre pas la composition utile, comparer l'interpréteur
ICN existant, le noyau composé et le score manuel sur les mêmes entrées, y
compris les domaines limites, les vecteurs vides ou singleton lorsque permis,
les entiers grands, les égalités et les violations.

Le noyau fusionné n'est recevable que si les sorties et les zéros satisfont les
mêmes contrats, les poids restent applicables/valides pour la banque ICN, et
chaque voie possède son workspace mutable. Garder un test différentiel exact
contre l'évaluateur ICN de référence. Mesurer allocations, GC dans la boucle,
temps par score, débit de candidats et qualité finale à graine/budget égaux.
N'accepter l'optimisation que si le gain apparaît aussi dans le solveur complet
sans dégrader faisabilité, qualité moyenne ou temps d'atteinte. Le coût à froid,
la compilation et le coût chaud seront publiés séparément. Cette passe attend
que le travail concurrent sur PerfChecker ait terminé ses changements afin de
ne pas profiler un outil en cours de modification.
Le contrôleur [`icn_perfcheck.jl`](../LiLim/scripts/icn_perfcheck.jl) peut choisir
ICN, direct ou naïf ; il vérifie séparément l'environnement initial du solveur,
la cohorte post-optimisation `workspace-cohort.toml`, l'instance LC101 et la
banque ICN. Cette séparation évite de comparer par erreur la nouvelle campagne
aux commits plus anciens du premier pilote.

### 4. Allocations MetaStrategist et mise à l'échelle

Après validation des scores, comparer CBLS ICN, score manuel, hybride spécialisé,
hybride bridgé et HiGHS en portefeuilles explicites MetaStrategist. Tester les
allocations équilibrées et orientées, par exemple 4/4/4/4 voies sur une machine
à seize voies, ainsi que l'arrêt ou la redistribution de voies terminées si le
mécanisme peut le garantir sans partager d'état mutable. Mesurer la qualité de
la meilleure voie et la distribution de toutes les voies ; l'incumbent fusionné
ne remplace pas les résultats individuels.

Pour la grille 1/2/4/8/12/16/20, distinguer huit cœurs P primaires, les douze
cœurs physiques, l'ajout de SMT sur huit P et les vingt fils logiques. D'abord
corriger et mesurer le GC des threads. Une campagne en processus vient ensuite,
avec workers préchauffés, GC distinct, mémoire, lancement et sérialisation dans
le coût annoncé. Pour chaque cellule, enregistrer les cœurs réellement utilisés,
les CPU-seconds, le temps mural, les allocations et les pauses GC ; le nombre
de threads demandé seul n'est pas une mesure de débit.

### 5. Campagne croissante et décision de poursuite

Sur les 354 instances SINTEF, commencer par les budgets diagnostiques de 8, 16,
32 et 64 secondes avec les fonctions d'erreur et profils figés. Publier ensuite
les passages de 128, 256, 512 et 1 024 secondes sur tous les profils encore
compétitifs ou en amélioration, puis doubler vers 2 048 secondes et au-delà
seulement si les courbes de qualité ou le temps d'atteinte continuent d'évoluer.
Les étapes fournisseur de 60 et 600 secondes restent des lignes dédiées, faciles
à comparer à Hexaly quand l'installation sera disponible. Alterner l'ordre des
solveurs et répartir les graines pour éviter qu'une dérive de fréquence ou de
température favorise un profil.

Après chaque phase, verser le protocole, les versions et empreintes, les
résultats complets légers, les validations, un résumé en anglais et les figures
avec axes/légendes/titres en anglais sur GitLab. Laisser les archives volumineuses
locales. Continuer une branche de stratégie seulement si une mesure identifie
un goulot et si une ablation contrôlée peut tester son effet.

## Moteurs à recenser

Disponibles ou déjà préparés localement : CBLS natif/ICN, MetaStrategist,
HiGHS/JuMP, Timefold Community, GHOST et JuLS. Vérifier les builds et les
versions figées avant d'inclure GHOST/JuLS. Ajouter par domaine les moteurs
libres établis — notamment OR-Tools Routing/CP-SAT, KaHIP/METIS et un moteur CP
tel que Gecode via MiniZinc — seulement après qualification du modèle et du
validateur. Une disponibilité logicielle seule ne suffit pas à qualifier un
comparatif.

## Journal des étapes

| État | Étape | Résultat consultable | Révision mesurée | Révision GitLab |
|---|---|---|---|---|
| Livré | Réévaluation, 12 profils, 1/2/4/8/16, budget 5 s | [Rapport](../LiLim/results/all-variants-20261004.md) et figures ci-dessus | Capture originale : vérifier dans TOML | `613c293` |
| Livré | Journal GitLab publié ; estimation Hexaly et comparaison des deux formulations | [Commit du journal](https://gitlab.naze.baffier.fr/others/Benchmarks/-/commit/9d2afd37897e46d964ff22124d4e465cc75a902c) | Benchmark fournisseur du 27 mars 2026 ; pas encore reproduit | `9d2afd3` |
| Livré | Corpus SINTEF 354 instances et valeurs de référence figées ; noms et effectifs concordent | [`BKS et empreintes`](../LiLim/config/sintef-pdptw-bks-20261004.toml) | Six archives et six pages SINTEF ; validation complète | En préparation |
| En préparation | Statistiques multi-graines, fonctions d'erreur Li-Lim apprises et manuelles, profilage ICN et essai de fusion sémantiquement équivalente | Objectifs détaillés ci-dessus ; première mesure du surcoût ICN déjà consignée | Les anciens essais ICN/direct ont trois graines ; fusion non essayée | — |
| En préparation | Hexaly bloqué par la revue d'installation ; qualification des profils CBLS/MetaStrategist sur 8 cœurs | Comparatif à 60 s sur toutes les instances, puis finalistes à 600 s | Hexaly indisponible ; pas de nouveau lot lancé | — |

À chaque nouvelle ligne de résultat, pousser avec le même commit les mises à jour
du présent journal, le résumé de résultats, les plots anglais PNG/PDF et le
protocole exact. Ne pas remplacer les captures anciennes ; chaque passe reçoit
un identifiant et un nouveau fichier de résultats.
