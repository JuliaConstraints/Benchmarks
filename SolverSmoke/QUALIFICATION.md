# Validation des solveurs — petit pilote

Tentative : `ddfa1aa5-c08e-4d3e-a88d-3f358549e471`. Quatre CPU logiques (4–7), exécutions séquentielles. Trois répétitions, deux secondes demandées par résolution, après un échauffement distinct. HPO actif sur CPU 0–3 ; mémoire, cache et fréquence restent partagés.

## ILP : sac à dos à 12 variables binaires

Capacité 40. Optimum **83**, vérifié par les 4096 affectations. Maximisation ; les colonnes donnent les résultats des trois répétitions.

| Moteur / interface | Objectifs | Valides | Temps résolution médian (s) | Construction médiane (s) |
|---|---|---:|---:|---:|
| cbls_jump | 83, 83, 83 | 3/3 | 2.00459 | 0.001235 |
| lss_native | 83, 83, 83 | 3/3 | 2.0009 | 0.000248 |
| ghost_jump | 82, 80, 81 | 3/3 | 2.02151 | 0.00088 |
| ghost_native_c | 79, 82, 80 | 3/3 | 2.01875 | 3.1e-5 |
| timefold_native | 83, 83, 83 | 3/3 | 2.00513 | 0.012366 |
| juls_native | 82, 82, 82 | 3/3 | 2.00064 | 0.000353 |
| highs_control | 83, 83, 83 | 3/3 | 0.00526 | 0.001222 |

## Li–Lim : lc101 réduit à trois requêtes, un véhicule

Six clients, paires complètes, distances et fenêtres originales en Float64, sans arrondi des distances. 720 permutations vérifiées indépendamment ; **1 tournée faisable**, distance **47.04315376485624**. Ce cas teste surtout l'obtention d'une tournée valide. Ce n'est pas lc101 complet.

| Moteur / interface | Valides | Distances obtenues | Temps résolution médian (s) |
|---|---:|---|---:|
| cbls_jump | 3/3 | 47.043154, 47.043154, 47.043154 | 2.00384 |
| timefold_native | 3/3 | 47.043154, 47.043154, 47.043154 | 2.00596 |
| ghost_native_cpp | 3/3 | 47.043154, 47.043154, 47.043154 | 2.00055 |
| juls_native | 3/3 | 47.043154, 47.043154, 47.043154 | 2.00037 |

## Portée et limites

- CBLS est la façade JuMP du générateur LocalSearchSolvers. Profil par défaut ici, sans HPO ; quatre travailleurs locaux. LSS natif et CBLS/JuMP sont tous deux testés sur l'ILP.
- GHOST : JuMP et C ABI natif sur l'ILP (même bibliothèque JLL), C++ natif avec permutation sur Li–Lim. Quatre travailleurs. La graine native n'est pas exposée : les numéros sont des répétitions, pas des graines appariées. Le binaire C++ est recompilé avec le compilateur portable consigné ; il ne sert pas à mesurer le surcoût de JuMP.
- Timefold 2.6.0 Community, Java 21 portable, formulations natives. Un fil de recherche (défaut Community), plafond processus de quatre CPU. Score non incrémental écrit pour cette validation ; ce modèle n'est pas encore qualifié pour une campagne de performance. Pas d'interface JuMP validée.
- JuLS natif à la révision enregistrée, sous Julia 1.11.9 : chargement amont incompatible avec Julia 1.13 (`eval`). ILP : initialisation gloutonne, voisinage exhaustif de deux variables, choix glouton et filtrage CP, tous par défaut amont. Routage : invariant de tournée, échanges de deux visites, choix glouton, pénalité 10000, filtrage CP désactivé faute de traduction de cet invariant ; pas d'interface JuMP validée. L'erreur du routage est encodée en unités entières (plafond de violation × 10^6), avant pénalité, pour respecter le test de zéro exact de JuLS. Aucune distance n'est arrondie. Les 10800 transitions par échange ont vérifié la cohérence arithmétique de cette pénalité.
- HiGHS est seulement le contrôle ILP. Hexaly est exclu à ta demande, licence non activée.
- Les temps sont ceux de l'appel de résolution après échauffement ; chargement, compilation et lancement des processus sont séparés dans les journaux. Une résolution arrêtée à deux secondes ne mesure pas le temps pour atteindre l'optimum. Ces trois répétitions ne démontrent aucun classement, ni un surcoût négligeable de JuMP.
- Toutes les solutions retenues sont relues depuis les fichiers, puis validées indépendamment. Une absence de solution reste un résultat, jamais une preuve d'infaisabilité. Les contrôles d'oracle, sources et environnements sont conservés dans cette tentative.
