# Contrat des adaptateurs d'expériences

Un adaptateur fournit `capabilities`, `build`, `solve`, `decode`, `close` dans son
environnement propre. C'est une cible de contrat ; aucun adaptateur externe n'est chargé
par le module du pilote. Ne pas détourner le registre des chemins en preuve de support.

Entrée : instance sémantique, formulation/version, profil et paramètres résolus, départ
facultatif, budget et allocation CPU, seed et mode de randomisation. Sortie : état brut,
statut normalisé, témoin éventuel, objectif déclaré, borne/certificat s'il existe, temps
et compteurs effectivement exposés. Une donnée inconnue reste absente.

Statuts distincts : `unavailable`, `unsupported`, `error`, `no_incumbent`,
`invalid_solution`, `feasible`, `proven_optimal`, `proven_infeasible`.
Valider hors adaptateur. L'absence de témoin n'est jamais une preuve d'infaisabilité.
Un objectif déclaré incohérent invalide l'observation même si le témoin est admissible.

Identité de configuration : moteur, version/binaire, frontend, formulation, bridges,
profil, fonctions d'erreur, paramètres demandés et résolus. Même configuration dans
LocalSearchSolvers direct et CBLS pour une comparaison du coût de l'interface. Vérifier
le transfert effectif des stratégies ; le constructeur CBLS actuel devra être qualifié
ou étendu avant de prétendre que tous les profils lui sont accessibles.

Sources locales examinées à réutiliser, sans exécuter leurs campagnes historiques :

* ConstraintLearningBenchmarks : `scripts/evolving/compare_plain_solvers.jl` pour les
  petits modèles directs ; `perf/proposal_ghost_comparison.jl` pour les compositions.
  Ce dernier choisit une initialisation GHOST d'un échantillon : variante explicite,
  pas défaut GHOST général de dix. Les anciennes limites CPU ne sont pas réutilisées.
* ConstraintModels : `scripts/solver_profiles.jl` pour le profil GHOST-like partiel et
  `docs/src/solver-strategy-profiles.md` pour les références publiques et écarts connus.
* GHOST.jl : `CAPI` et `Optimizer` ; vérifier quel binaire est effectivement chargé.

Éviter toute importation de script historique ayant des effets globaux, un environnement
implicite ou une allocation CPU incompatible. Porter uniquement les petits adaptateurs
nécessaires après qualification, en conservant leur provenance et leur licence.

La couche de campagnes lancera chaque moteur dans un processus avec son Project/Manifest
épinglé. Archiver hash des sources réelles (y compris modifications locales), binaire,
environnement, données, logs, allocation et périodes de concurrence. Les marqueurs
`started`/`completed` du pilote évitent de considérer un résultat partiel comme terminé ;
reprise sémantique, scheduler et compatibilité d'archives restent à implémenter.
