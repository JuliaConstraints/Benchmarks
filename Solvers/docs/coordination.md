# Coordination et publication

## Séparation des dépôts

`JuliaConstraints/Benchmarks` existe déjà et est public. Son clone local était propre à
l'inspection, branche `main`, commit `fa4bb4b` (21 avril 2025). Le travail de comparaison
se fait sur la branche locale `feat/solver-comparison-ilp`, dans `Solvers`.
Il n'a pas été nécessaire de créer un nouveau dépôt Git.

À la demande suivante, le périmètre inclut également l'organisation DrWatson de la
racine, les diagnostics de bibliothèques et l'archivage des anciens dossiers dans
`archive/legacy`. La limite d'écriture reste strictement le dépôt Benchmarks.

La préparation doit être publiée d'abord sur le GitLab privé de l'équipe. Aucun push vers
GitHub n'est autorisé par cette préparation. Le remote public existant sert de provenance
amont ; son existence ne vaut pas autorisation de publication. Aucune création de projet
distant ni publication n'a été réalisée à ce stade. La décision d'ouverture publique
interviendra après la préparation ; vérifier droits de redistribution des données,
licences des moteurs et contenu des archives avant cette publication effective.

La tentative de lecture SSH de `git@nohost.d-vision.fr:julia/Benchmarks.git` a renvoyé
`Internal API unreachable`. Elle ne permet de confirmer ni l'existence ni la visibilité
de ce projet GitLab. Aucun remote GitLab n'a été ajouté sur cette hypothèse et aucun push
n'a été tenté. Vérifier/créer la destination privée lorsque le service sera accessible.

## Coordination avec le HPO en cours

Accord reçu le 12 septembre 2026 de la tâche **Planifier campagnes ConstraintBench**,
id `01a07b4f-4b7f-76f1-b484-dc3057202f88` : son Julia PID 16236 utilise l'affinité `0xF`,
CPU logiques Windows 0–3. Archive HPO `data/he/89d0684b/core_4`, supervision
`data/core-variants/20260910/v2e/`, dans ConstraintLearningBenchmarks.

Pour nos petits essais : CPU 4 (`0x10`) puis CPU 4–5 (`0x30`), un processus actif à la
fois, au plus deux CPU pour toute la tâche, BLAS/GC/précompilation à un thread.
Vérification locale : 20 CPU logiques visibles, seul processus Julia existant observé
avant nos tests : PID 16236, masque 15. Ce constat ne réserve pas les CPU aux dépens
d'autres applications. L'affinité est relue dans chaque processus de test.

Ne modifier ni branche/index, ni scripts, données, Project/Manifest ou dépendances de la
cohorte HPO. Aucun fichier n'a été ajouté à ConstraintLearningBenchmarks par cette tâche.
Ses sources gelées peuvent être inspectées, mais ses campagnes ne sont pas relancées.

Archiver PID et heures UTC de nos tests ; conserver la période de concurrence. Même avec
des CPU distincts, cache/mémoire/fréquence sont partagés : ces tests ne produisent pas de
mesures de performance isolées. Cette allocation est propre à la session et doit être
revérifiée avant une autre campagne ; ne pas conserver un PID comme vérité permanente.

## Destination confirmée par l'utilisateur — 12 septembre 2026

L'utilisateur autorise le commit et le push directement dans le groupe GitLab `julia`,
en privé, sans inscription à Oasis. Les remotes actuels de ConstraintCommons.jl,
ConstraintModels.jl et LocalSearchSolvers.jl utilisent tous
`git@nohost.d-vision.fr:julia/<nom>.git`. La destination retenue pour ce dépôt est
`git@nohost.d-vision.fr:julia/Benchmarks.git`, remote `gitlab` et destination de push
par défaut. Le remote GitHub `origin` reste la provenance amont historique.

À 11:19 UTC, le 12 septembre 2026, les lectures SSH du dépôt existant
ConstraintCommons.jl et de Benchmarks échouent toutes deux avec `Internal API
unreachable`. L'accès HTTPS à `/gitlab/users/sign_in` et à l'API GitLab répond
`502 Bad Gateway`. Le problème dépasse donc le seul chemin de Benchmarks.
L'existence et la visibilité privée de la destination doivent être confirmées une fois
le service rétabli, avant de transférer les commits. Aucun passage par Oasis n'est prévu.

Après qualification des campagnes, le contenu approprié pourra être publié sur le
GitHub public de Mirage Interactive. Cette destination future ne déclenche aucune
publication publique pendant la préparation actuelle.
# 2026-09-12: service recovery and actual solver pilot

GitLab service recovery was confirmed by a successful signed branch push. The
server explicitly confirmed creation of **private** project `julia/Benchmarks` at
`https://nohost.d-vision.fr/gitlab/julia/Benchmarks`. The initial shallow clone had
to retrieve its missing upstream history before GitLab accepted the push. No
public push or Oasis registration was performed.

`SolverSmoke` is the dedicated DrWatson functional study. It uses CPUs 4–7, at
most four logical CPUs globally for its workers, while the coordinated HPO task
keeps CPUs 0–3. All local Julia dependency sources are copied; the shared HPO
checkouts and environment are not modified. Actual solver workers now exist for
CBLS/JuMP, LSS native, GHOST/JuMP and native, Timefold Java and JuLS. Hexaly is
excluded by the user's explicit instruction, license not activated.
