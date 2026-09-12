# Contrôle sur le même extrait historique Li–Lim

Six visites, trois requêtes, un véhicule. Les octets de l'ancien fichier et la provenance sont identiques. Les nouvelles formulations reçoivent ces mêmes données dans leur format multi-véhicules. Budget : deux secondes, trois répétitions, quatre cœurs. Oracle : 47.04315376485624 ; une seule permutation réalisable parmi 720.

Ancien pilote : CBLS, Timefold, GHOST et JuLS avaient chacun 3/3 solutions réalisables. Les colonnes ci-dessous concernent uniquement les nouvelles formulations. Les temps de découverte n'étaient pas enregistrés dans l'ancien pilote : aucune comparaison temporelle directe n'est possible.

| Solveur / profil | Réalisables dans 2 s | Temps de première solution, répétitions 1–3 (s) |
|---|---:|---|
| lss_native / default | 3/3 | 0.0006568, 0.0007234, 0.0007316 |
| lss_native / assignment | 3/3 | 0.0003556, 0.0007979, 0.0006859 |
| lss_native / juls_greedy_like | 3/3 | 0.0014141, 0.0004468, 0.0068638 |
| lss_native / ghost_assignment_like | 3/3 | 0.004258, 0.0004214, 0.0006603 |
| lss_native / timefold_late_acceptance_like | 3/3 | 0.0006989, 0.0009779, 0.0008633 |
| cbls_jump / default | 3/3 | 0.0004875, 0.0011524, 0.0008424 |
| cbls_jump / assignment | 3/3 | 0.00044, 0.0010061, 0.0042557 |
| cbls_jump / juls_greedy_like | 3/3 | 0.001563, 0.0004709, 0.007624 |
| cbls_jump / ghost_assignment_like | 3/3 | 0.0005719, 0.0007114, 0.0007561 |
| cbls_jump / timefold_late_acceptance_like | 3/3 | 0.0007702, 0.0010663, 0.0009611 |
| timefold_native / default | 3/3 | 0.003, 0.003, 0.001 |
| timefold_native / late_acceptance_400 | 3/3 | 0.004, 0.002, 0.002 |
| ghost_native_cpp / default_permutation | 3/3 | 0.00096, 0.001127, 0.000982 |
| juls_native / greedy_swap | 3/3 | 0.0243597, 0.0246432, 0.0288092 |
| highs_control / compact_mip | 3/3 | 0.0004751, 0.0004738, 0.0006055 |

Ce contrôle isole le changement de formulation sur un cas identique. Il ne démontre pas la performance sur lc101 complet, ni l'absence de régressions sur d'autres cas. GHOST conserve des répétitions non appariées par graine. Les observations et le code de contrôle sont archivés.
