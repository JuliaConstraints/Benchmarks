# CBLS, ICN et MetaStrategist : allocations et préparation

Diagnostic du 4 octobre 2026 sur l'i7-12700, Julia 1.13.1. Le problème de GC
était réel. Les buffers privés et une correction du noyau rendent désormais
presque tout le temps CPU disponible aux 16 trajectoires sur LC101. Les trois
décodeurs ICN récupérés sont conservés ; leurs fonctions et poids n'ont pas changé.

## Résultat à 16 threads

Trois graines, cinq secondes par essai, même instance, mêmes mouvements et ICN,
Julia `-O1`, GC/BLAS/OMP à un thread, affinité fixe. Médianes :

| Étape | CPU actifs / 16 | Candidats de réinsertion par seconde | Octets alloués par appel | Temps GC de l'appel |
|---|---:|---:|---:|---:|
| Avant | 6,41 | 2,00 millions | 36,09 Go | 3,328 s |
| Buffers ICN et déplacements | 14,74 | 23,07 millions | 3,66 Go | 0,490 s |
| Noyau typé et buffers de routes | 15,97 | 26,59 millions | 0,256 Go | 0,171 s |

Le débit est multiplié par 13,3 ; les allocations sont divisées par environ 141.
Le temps GC publié inclut une collecte complète forcée dans `run_case`, avant
son chrono de recherche. Il ne représente donc pas uniquement les pauses de la
boucle chaude. L'occupation utilise les horloges CPU des workers et du processus,
et non le pourcentage « utilization » du profileur Julia, qui peut inclure des
attentes de GC. On observe 97,4 à 100 % par worker à 16 threads.

La capture supplémentaire `throughput-hot-gc-16t-20261004.toml`, aux mêmes
solveurs avec instrumentation des limites du chrono, mesure séparément le
compteur GC global avant et après la recherche. Sur les trois graines :
**0 seconde de GC pendant la recherche**, 15,985 à 15,986 CPU actifs, 254 à
256 Mo alloués et 26,35 à 26,59 millions de candidats/s. Les 0,165 à 0,167 seconde
de GC de l'appel complet se trouvent hors de cet intervalle. Cela décrit ces
essais de cinq secondes ; les allocations restantes peuvent provoquer des
collectes dans des essais plus longs. Cette instrumentation est sauvegardée au
commit `80fd298` et ne modifie ni le score, ni les mouvements, ni l'acceptation.

LC101 est un contrôle de débit : le point d'insertion est déjà à la meilleure
qualité connue. Ce gain ne prouve pas une amélioration des solutions ni une
victoire contre un autre solveur.

## Passage à l'échelle

| Threads | CPU actifs, premier lot | Candidats/s | Allocations, premier lot |
|---|---:|---:|---:|
| 1 | 1,00 | 2,60 millions | 49 Mo |
| 2 | 1,99 | 4,83 millions | 68 Mo |
| 4 | 3,91 | 9,85 millions | 1,61 Go |
| 8 | 7,99 | 19,87 millions | 197 Mo |
| 16 | 15,97 | 26,59 millions | 256 Mo |

À quatre threads, un second lot aux mêmes sources retrouve 3,997 CPU actifs et
113 à 116 Mo alloués. Les deux lots sont conservés et figurent dans le graphique.
Le pic du premier lot n'est pas reproduit dans la capture suivante ; sa cause
reste indéterminée. Le chargement de ConstraintModels passe de 4,4 à 1,6 secondes
entre ces sessions, signe que l'état des caches de compilation disponibles a
changé. Cela ne permet pas d'attribuer ce pic au cache sans autre mesure.

Les huit premières voies utilisent huit cœurs P distincts. À seize, quatre
cœurs E et quatre voies SMT s'ajoutent : une occupation de 100 % ne garantit
pas un débit proportionnel au nombre de voies logiques.

## Ce qui a été corrigé

- Les tableaux de successeurs, positions, routes et arguments des ICN appartiennent
  à chaque worker. Ils sont réutilisés, sans partage mutable entre trajectoires.
- Les candidats de réinsertion utilisent des buffers ; seule une amélioration
  conservée reçoit une copie indépendante.
- Le décodage des routes courantes utilise un workspace. Les snapshots confiés
  aux méta-variables et les solutions conservées possèdent toujours leurs données.
- Le noyau LocalSearchSolvers sépare l'itérateur concret du choix entre déplacements
  et échanges. Les résultats d'itération n'étaient auparavant pas correctement
  typés dans la boucle commune et produisaient des allocations par candidat.
- Un voisin structurellement invalide produit son score d'infaisabilité sans
  construire une exception et sa trace.

La première correction du noyau, seule, n'a pas suffi à réduire le GC global à
seize threads. Les mesures intermédiaires `throughput-iterators-*` documentent
ce résultat ; c'est le décodage réutilisable des routes qui lève le coût suivant.

## PerfChecker et SnoopCompile réellement exécutés

PerfChecker 1.0.0-rc1, commit `1cc09a98db569b382f91dc10f6a569c1c728b6aa`,
collecte les profils CPU, muraux et d'allocations dans des workers isolés. Les
trois captures complètes sont conservées : baseline, premiers buffers et finale.
Les allocations importantes des positions, petits arguments ICN et copies de
routes disparaissent des profils. La dernière capture détecte encore une petite
allocation dans l'itération du planning des profondeurs ; les résultats sont
échantillonnés et ne constituent pas un inventaire exhaustif des octets.
Le checkout de développement PerfChecker déjà modifié par l'utilisateur reste
intact. Le contrôleur utilise une source épinglée séparée et n'altère pas
l'environnement du solveur.

SnoopCompile 3.2.9 / SnoopCompileCore 3.1.3 a instrumenté une session à seize
threads. Le décodage de la banque induit environ 4 067 instances de méthodes ;
la première préparation CBLS naïve environ 14 406, puis ICN 739 et bridges 3 218.
Au second passage, ICN, les deux hybrides, HiGHS et les portefeuilles n'induisent
plus de nouvelles instances ; le naïf en induit encore 80. Les durées de
compilation de plusieurs threads s'additionnent : elles ne sont pas un temps mural.
Les sommes Snoop publiées utilisent les durées exclusives par méthode ; additionner
récursivement les durées inclusives compterait plusieurs fois l'inférence imbriquée.

Après échauffement, préparer un parent prend environ 0,5 ms, un plan MetaStrategist
0,2 ms, et réutiliser son kernel avec un nouveau contexte environ 0,2 ms. Sur le
petit fragment qualifié, les réparations chaudes coûtent environ 17 ms spécialisées
et 60 ms bridgées, sans nouvelle inférence. Les modules ne sont pas rechargés à
chaque réparation. La construction d'un modèle JuMP/HiGHS neuf reste un coût réel,
à mesurer et éventuellement réutiliser selon la forme du fragment.

Les échauffements de deux secondes contiennent aussi deux secondes de recherche :
ils ne doivent pas être présentés comme deux secondes de compilation. Une partie
du très premier chargement dépend de caches de packages déjà présents ; aucun
gain à froid n'est attribué aux buffers sur cette seule observation.

La préparation à conserver est : charger les packages et décoder la banque une
fois, préparer les variantes réellement utilisées, garder des workers durables,
réutiliser les plans immuables avec des contextes privés et les buffers par lane.
Aucun sysimage ni précompilation AOT du modèle dynamique n'a encore été installé.

## Qualification, processus et prochaine comparaison

Les scores ICN et les distances sont comparés exhaustivement au validateur et
au score direct. Les tests vérifient aussi zéro allocation pour le score et le
décodage chauds, l'isolation des seize workspaces, les snapshots conservés, les
réinsertions et les portefeuilles. LocalSearchSolvers passe 10 432 contrats de
stratégies et 782 contrats de performance après la correction du noyau.

CBLS/LocalSearchSolvers dispose aussi de workers `Distributed` et de
`process_threads_map`, avec GC distincts. Le pilote actuel est une phase
MetaStrategist à threads ; il n'implémente pas encore une phase distribuée.
Le contrôle par processus viendra après cette correction, avec pool chaud,
plafond CPU identique et coûts de lancement, sérialisation, mémoire et GC publiés.

Le [protocole concurrents](../config/competitors.toml) ajoute Timefold Community
avec score incrémental par route et prépare Hexaly avec contraintes originales,
flotte puis distance non arrondie. La table [SINTEF](https://www.sintef.no/projectweb/top/pdptw/100-customers/)
ne garantit pas de temps de référence par instance : le temps d'atteinte de la
qualité publiée doit être mesuré localement. Les scores BKS arrondis restent des
cibles de qualité, et non des certificats de temps ou d'optimalité.

Sources mesurées : Benchmarks `972fa7859dfa1c89c8874275168f9e3dad21e63d`,
LocalSearchSolvers `8d0b3291420f49950cfda4e890899f384b8b7239`. Le reste de la
cohorte et les empreintes du solveur figurent dans chaque capture. La campagne
initiale de 369 essais conserve sa cohorte et son [bilan qualité](icn-threads-20261004.md).

Captures essentielles : `throughput-final-*`, `throughput-final-repeat-4t-*`,
`throughput-hot-gc-16t-*`, `perfchecker-final-*` et
`snoop-startup-exclusive-16t-*` dans ce répertoire.
Les graphiques exact et XKCD sont produits par `icn_performance_plots.jl` ; les
graphiques de réussite, anytime et temps d'atteinte des BKS restent dans
`figures-20261004`, distincts du diagnostic de débit.
