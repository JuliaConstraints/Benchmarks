# Premier raccordement Timefold et préparation Hexaly

Le 4 octobre 2026, Timefold 2.6.0 Community est ajouté à Li-Lim avec un modèle
natif de listes et un score incrémental par route. Hexaly dispose d'un modèle
préparé et d'un contrat de lancement/audit ; aucun résultat Hexaly n'est annoncé.
Le [protocole et les limites](../COMPETITORS.md) sont sauvegardés avec les sources.

## Résultats courts à point initial commun

90 essais Timefold à horloges raccordées : trois instances, trois graines,
1/2/4/8/16 workers, acceptation tardive de taille 400 ou 1 000. Les 45 contrôles
CBLS/ICN sont relancés avec le noyau et les workspaces actuels, au même budget
total de cinq secondes. Les préparations communes et les coûts de modèle
sont inclus dans le budget déclaré ; le chargement et les warmups sont séparés.
Chaque résultat et chaque incumbent admis est revalidé dans le problème original.

Médianes lexicographiques sur les trois graines :

| Instance | BKS publié | CBLS ICN, 1/2/4/8 workers | CBLS ICN, 16 workers | Timefold, 1/2/4/8/16 workers, LA 400 ou 1 000 |
|---|---|---|---|---|
| LC101 | 10 / 828,94 | 10 / 828,937 | 10 / 828,937 | 10 / 828,937 |
| LR101 | 19 / 1650,80 | 20 / 1695,138 | 19 / 1685,959 | 21 / 1813,936 |
| LRC101 | 14 / 1708,80 | 17 / 1797,545 | 17 / 1793,425 | 19 / 2143,503 |

Le meilleur CBLS de ce lot sur LRC101 atteint 16 véhicules / 1790,489.
À tolérance de distance 1e-6, CBLS gagne les 60 comparaisons appariées LR101/LRC101
contre les deux profils Timefold et fait égalité dans les 30 cellules LC101.
LC101 est déjà à sa référence dans le point commun : ce succès n'est pas dû à
une découverte des solveurs. Aucun essai ne rejoint les BKS LR101 ou LRC101.
Les différences de quelques unités d'arrondi flottant sur LR101 côté Timefold
ne constituent pas une amélioration utile de l'insertion.

## Ce que cela permet de dire

Le contrôleur CBLS avec réinsertions de requêtes complètes améliore l'insertion
sur les deux cas difficiles. Le modèle Timefold testé, malgré son score
incrémental et ses solveurs effectivement actifs, progresse peu avec ses mouvements
natifs et ces budgets courts. L'ajustement de l'acceptation 400 → 1 000 ne suffit
pas ici. Ce résultat désigne les mouvements et la diversification comme prochain
levier à examiner ; il ne prouve pas une supériorité sur toutes les formulations
Timefold, l'édition Enterprise, ou un corpus industriel de confirmation.

Le défaut Timefold 2.6.0 se résout déjà en acceptation tardive 400 et un candidat
accepté par étape. Le profil explicite 400 n'est donc pas compté comme une
stratégie différente. Les premières captures `timefold-default-*` sont des
qualifications antérieures au raccordement du coût commun ; elles ne sont pas
utilisées dans cette table ou dans les figures comparatives à cinq secondes.

À seize workers, Timefold reçoit la même affinité et exécute seize solveurs
série indépendants dans une JVM, avec GC série et heap maximal déclaré de 2 Go.
Ce n'est pas son parallélisme interne Enterprise. Le processus utilise environ
13,6 à 14,3 CPU en médiane selon le cas/profil. Dans les 81 essais instrumentés,
tous les workers entrent réellement en recherche ; ils totalisent 813 115 001
calculs de score. Les compteurs natifs sont conservés pour permettre de
vérifier cette activité sans la déduire du seul nombre de threads demandé.
Les métriques Micrometer globales émettent un avertissement de nom partagé
entre solveurs ; les compteurs de travail retenus sont propres aux threads.

Occupation médiane du processus Timefold, plages selon les trois cas et les
deux profils : 0,999–1,000 CPU à un worker, 1,934–1,971 à deux,
3,717–3,808 à quatre, 7,156–7,369 à huit et 13,597–14,298 à seize.
Ces horloges couvrent l'appel natif complet ; elles ne doivent pas être
interprétées comme le seul temps de recherche par thread.

Les recherches CBLS et Timefold n'ont pas le même voisinage ni la même erreur
de guidage des états infaisables, mais visent le même ensemble de solutions
originales et le même ordre de qualité. La comparaison porte sur ces solveurs
et formulations complets. Les modèles Timefold, le heap et les hyperparamètres
ne sont pas encore optimisés par HPO. Le corpus est déjà exposé, les méthodes
ne sont pas exécutées en ordre contrebalancé et il n'y a que trois graines :
ce bilan sert de pilote, pas de preuve commerciale finale.

## Hexaly et référence de temps

Le modèle [pdptw.hxm](../native/hexaly/pdptw.hxm) lit le même échange, impose les
contraintes originales et optimise flotte puis distance sans arrondir. Les
tests du contrat Julia refusent les routes invalides, les scores incohérents
et des allocations CPU ambiguës. L'exécutable est absent : compilation native,
injection à temps nul, gestion des routes vides, chrono de construction/résolution
et callbacks anytime restent à qualifier. La licence d'essai n'est pas activée.

La [table SINTEF](https://www.sintef.no/projectweb/top/pdptw/100-customers/) fournit
une qualité, une provenance et une date ; elle ne garantit pas des durées de
calcul et des plateformes comparables. Les figures affichent cette qualité,
et notre temps local d'atteinte. Les budgets de 60/600 secondes du benchmark
de l'éditeur Hexaly ne sont pas des temps historiques des BKS.

## Sources et sauvegarde

Les captures conservent les sources, instances et JARs hachés, les budgets,
préparations, warmups, CPU, graines et trajectoires. Les versions exactes des
adaptateurs mesurés sont conservées dans l'historique Git : `9285fa8`, `12b8013`,
`511e6aa` puis `1314994`. L'extension à 2/4/8 workers utilise `b066616`.
Le contrôleur CBLS conserve la cohorte du noyau
`8d0b329` et l'empreinte inchangée des fonctions ICN récupérées. Aucune donnée
de la campagne précédente de 369 essais n'est remplacée.

Qualification : 480 partitions exhaustives avec un oracle distinct, quatre
recherches Timefold FULL_ASSERT réellement démarrées, contrôles de changement/
annulation sur les trois instances, onze tests Julia d'échange/audit et nouvelle
qualification à seize threads des scores, workspaces et portefeuilles CBLS.

Captures comparatives : `competitor-cbls-{1,2,4,8,16}t-*`,
`timefold-late-{1,2,4,8,16}t-*` et `timefold-late1000-{1,2,4,8,16}t-*`.
Figures exactes et XKCD en PNG/PDF :
`figures-20261004/competitors-quality*` et `competitors-anytime*`. Les figures
incluent flotte, distance, taux d'atteinte de la référence et progression des
trois graines ; les taux 0/33/67/100 % ne sont pas une extrapolation statistique.
