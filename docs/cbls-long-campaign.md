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

## Couverture à construire

Les candidats ci-dessous viennent des sources et manifests retrouvés dans les
dépôts. La présence dans un catalogue ne signifie pas encore que notre modèle,
score, validateur et lancement sont qualifiés.

| Famille | Disponibilité et candidats | Comparaisons à qualifier |
|---|---|---|
| PDPTW / Li-Lim | Trois instances 100 tâches présentes ; les sources officielles inventoriées dans le plan industriel comprennent 56 fichiers à 100 et 60 à 200 tâches | CBLS/ICN, CBLS direct et stratégies mixtes, méta-variables + HiGHS, HiGHS complet, Timefold, GHOST, JuLS ; OR-Tools Routing à évaluer |
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
| En préparation | Inventaire des familles et moteurs, PerfChecker baseline, contrôle 8/12/16/20 | À compléter ici avant le premier lot long | — | — |

À chaque nouvelle ligne de résultat, pousser avec le même commit les mises à jour
du présent journal, le résumé de résultats, les plots anglais PNG/PDF et le
protocole exact. Ne pas remplacer les captures anciennes ; chaque passe reçoit
un identifiant et un nouveau fichier de résultats.
