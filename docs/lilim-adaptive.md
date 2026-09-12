# Li–Lim : échelons et threads

Cette campagne succède au diagnostic à 15 configurations. Les anciennes mesures
conservent leur révision, leurs modèles et leur allocation ; elles ne sont pas
fusionnées avec cette campagne à 1, 2 et 4 threads.

## Règle validée avec l'utilisateur

- Les échelons 30, 60 et 120 secondes sont exécutés sur les 354 instances,
  toutes les configurations disponibles et les trois répétitions.
- L'échelon 240 est obligatoire sauf si **toutes** les observations à 120 secondes
  sont réalisables, toutes instances, configurations et répétitions confondues.
- Après 240, chaque instance sans aucune solution réalisable observée reçoit
  480, puis 960 secondes, puis les doublements suivants.
- Un échelon commencé est terminé pour toutes les configurations et répétitions
de l'instance, même si une première solution apparaît avant sa fin.
- Une erreur d'exécution ou une censure de ressources exige un diagnostic ;
  elle ne déclenche pas automatiquement un doublement de budget.

Chaque échelon est une nouvelle résolution ; la trajectoire de 960 secondes
n'est pas réutilisée pour fabriquer les expériences de plus petits budgets.
Les solutions trouvées après le budget sont conservées et signalées mais ne
satisfont pas le critère d'arrêt. Une solution suffit après 240 ; cela ne prouve
ni robustesse sur trois graines, ni bonne qualité, ni optimalité.

## Parallélisme réellement demandé

| Moteur | Configurations | Signification |
|---|---|---|
| LSS natif et CBLS/JuMP | 1, 2, 4 | Travailleurs de recherche configurés dans `process_threads_map` |
| JuLS natif | 1, 2, 4 | Threads Julia pour l'évaluation parallèle des mouvements |
| GHOST C++ natif | 1, 2, 4 | Recherches parallèles natives ; voie séquentielle à 1 |
| HiGHS contrôle | 1, 2, 4 | Limite de threads native ; utilisation effective selon l'algorithme |
| Timefold Community | 1 | Recherche native séquentielle |

Timefold Community ne fournit pas le multithreading natif d'une résolution.
Les cases 2 et 4 sont conservées comme indisponibles dans `availability.toml`,
jamais simulées par des résolutions indépendantes :
[documentation commerciale](https://docs.timefold.ai/timefold-solver/latest/commercial-editions/commercial-editions).
Hexaly reste exclu jusqu'à activation de la licence.

Les 15 profils/interfaces initiaux donnent **41 configurations disponibles**.
La grille complète 30–240 représente 174 168 résolutions et 226,78 jours de
budgets de recherche séquentiels, avant échauffements/démarrages et hors
terminaisons anticipées. L'escalade peut ajouter du temps ; ce n'est pas une
estimation de fin calendaire ni une raison pour réduire silencieusement le plan.

Le contrôleur ne lance qu'un solveur à la fois. Le processus enfant hérite
avant son démarrage d'une affinité sur 1, 2 ou 4 CPU parmi 4–7. L'affinité est
vérifiée après lancement ; celle du contrôleur est restaurée. GC et bibliothèques
restent limités à un thread auxiliaire dans cette même allocation. Le plafond
global reste quatre CPU, les autres HPO conservent 0–3.

## Validation, lancement et preuves

`scripts/lilim_schedule_checks.jl` vérifie les règles d'arrêt, les cas manquants,
les doublons et la séparation des erreurs/censures. `scripts/lilim_thread_qualify.jl`
exécute les 41 configurations, trois fois chacune, sur la petite instance
multi-véhicules : solutions vérifiées indépendamment, threads déclarés et affinité.
Le sceau `SolverSmoke/THREAD_QUALIFICATION.toml` doit correspondre exactement
aux sources et exécutables avant tout lancement avec `scripts/lilim_adaptive.jl`.

La reprise reçoit le dossier de campagne en argument. Les solveurs, validateurs,
la politique d'échelons et la liste des cas sont figés. Les nouveaux commits de
rapport ou de contrôleur sont autorisés après publication GitLab privée, mais
la révision mesurée reste celle du lancement. Les tentatives interrompues ne
sont pas écrasées : il faut diagnostiquer un éventuel processus orphelin et
archiver la tentative avant une nouvelle exécution. `STOP` arrête entre deux
résolutions. Les rapports datés séparent explicitement les threads et les tailles
réelles des instances.

Les fichiers d'évidence sont stockés par Git sans conversion de fins de ligne.
`scripts/lilim_evidence_bytes.jl` compare les empreintes annoncées aux octets
locaux et à ceux de l'index Git, y compris les traces natives écrites en CRLF.
