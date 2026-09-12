# Rapports intermédiaires Li–Lim

`scripts/lilim_progress.jl CAMPAIGN_DIR` produit un rapport Markdown et ses
observations TOML dans `CAMPAIGN_DIR/reports/DATE_UTC/`. Chaque rapport conserve
les empreintes des fichiers lus, la révision de campagne et son propre source.
Il ne modifie aucun résultat ni l'instantané exécuté par les solveurs.

Le script utilise seulement les bibliothèques standard Julia. Le lancer avec
`--startup-file=no --compiled-modules=existing --threads=1,0 --gcthreads=1`,
`SOLVER_COMPARISON_CPUS=4,5,6,7` et `SOLVER_COMPARISON_CPU_LIMIT=4`.
Le contrôle de ressources commun applique l'affinité et la priorité réduite.
La production d'un rapport partage donc les quatre cœurs avec la campagne ;
elle peut introduire une petite perturbation, comme toute observation locale.

`scripts/lilim_progress.jl --self-test` vérifie notamment le filtrage des
solutions hors budget, la distinction des censures, l'absence de faux temps
pour les échecs et l'exclusion des travaux encore en écriture.

Les tableaux séparent budget et taille nominale. Les détails identifient
instance, solveur, profil et répétition. Les médianes conditionnelles aux succès
ne constituent pas un classement. La cible commune, propre à chaque rapport,
est la meilleure qualité observée dans le budget, tous solveurs et budgets
confondus ; elle n'est pas une preuve d'optimalité. Garder les rapports datés.

Un suivi horaire dans la tâche actualise ces rapports et présente les changements
utiles. Le contrôleur de campagne reste indépendant de ce suivi ; l'absence de
notification ne prouve pas son arrêt. Vérifier son processus réel avant toute
reprise, sans jamais lancer un doublon.
