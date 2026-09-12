# Qualification du socle — 12 septembre 2026

Ce rapport concerne l'infrastructure et l'oracle ILP, **aucun solveur externe**.

## Qualification initiale avant DrWatson

| Exécution | Environnement | Résultat | Archive locale |
|---|---|---|---|
| Un thread Julia | Julia 1.13.0, Windows, CPU 4, masque 0x10 | 51/51 contrôles réussis | `data/checks/050aec0f-1aef-40cd-9787-8d1ca537fe9c` |
| Deux threads Julia | Julia 1.13.0, Windows, CPU 4–5, masque 0x30 | 51/51 contrôles réussis | `data/checks/7b4ac318-f6c9-4fbd-a03c-a513aa5b4564` |
| Préparation du plan | Deux threads, même masque | 228 combinaisons préparées, zéro résolution | `data/plans/d1b89329-3ee1-4313-b905-66d507ee66ad` |

Contrôles : six références ILP recalculées par énumération exacte, domaines/égalités/sens
et offsets, rejet des témoins invalides et objectifs incohérents, refus d'une énumération
hors budget, identités des 19 chemins sans doublons, conservation de deux tentatives
distinctes et empreinte du résultat terminé. Les deux threads Julia sont exercés dans
un test d'infrastructure ; cela ne prouve aucun parallélisme propre à un solveur.

Les archives indiquent PID, heures UTC, allocation, empreintes du manifeste et des cas.
La campagne HPO voisine continue sur CPU 0–3 ; ses fichiers et son processus n'ont pas
été modifiés. Aucun paquet installé, environnement partagé modifié, instance téléchargée,
benchmark de performance, HPO supplémentaire, commit ou push effectué.

La compatibilité déclarée Julia 1.10 du socle reste à tester sur cette version.
Les adaptateurs, la conformité MOI, les modèles natifs optimisés, le rejeu d'une campagne
interrompue et les comparaisons de performance restent aux lots suivants.

## Requalification après intégration DrWatson

Julia 1.13.0 / DrWatson 2.19.1, même allocation CPU coordonnée : **61/61 contrôles**
sur un thread (archive `data/checks/90e17d1f-5864-4252-ba46-56afc56c4d46`) et deux
threads (archive `data/checks/7f773600-b639-48d9-b82b-b4b1bf7705a2`). Les nouveaux
contrôles couvrent l'activation DrWatson, les empreintes des environnements/sources,
le marquage Git et la copie des sources d'une tentative. Le plan relancé depuis le
lanceur racine conserve ses 228 combinaisons, sans résoudre de modèle :
`data/plans/3b944b99-f97c-475c-aafe-a3f7ea475cbe`.

Les environnements propres à Benchmarks ont été résolus hors ligne à partir du cache
existant, avec précompilation automatique désactivée. Ils conservent chacun leur
Manifest. Aucun environnement ni fichier du HPO n'a été modifié. Les nouveaux résultats
incluent une copie des sources et fichiers Project/Manifest, même non commités.
