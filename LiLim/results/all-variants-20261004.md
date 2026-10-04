# Réévaluation de toutes les variantes — 4 octobre 2026

504 essais validés : 414 essais CBLS/HiGHS et 90 essais Timefold Community à cinq secondes. Trois instances, trois graines, 1/2/4/8/16 workers. Les allocations MetaStrategist mixtes commencent à quatre workers.

Optimisation lexicographique : flotte puis distance. La médiane est la deuxième solution observée dans cet ordre, sans assembler deux routes différentes. Le taux d'atteinte compare la flotte, puis la distance arrondie aux deux décimales publiées par SINTEF ; les scores bruts restent conservés. Il est descriptif ; LC101 commence déjà à la référence. La table SINTEF n'offre pas de temps homogène. Les représentations et mouvements diffèrent entre solveurs, et ces cas exposés ne prouvent pas une supériorité commerciale.

## Qualité à seize workers

| Profil | LC101 | LR101 | LRC101 |
|---|---:|---:|---:|
| CBLS naive | 10 / 828.937 | 19 / 1685.959 | 17 / 1793.425 |
| CBLS ICN | 10 / 828.937 | 19 / 1685.959 | 17 / 1793.425 |
| CBLS native, direct score | 10 / 828.937 | 19 / 1685.959 | 17 / 1793.425 |
| CBLS mixed strategies | 10 / 828.937 | 19 / 1685.959 | 16 / 1790.489 |
| Specialized ICN hybrid | 10 / 828.937 | 19 / 1654.132 | 16 / 1766.246 |
| Bridged ICN hybrid | 10 / 828.937 | 19 / 1685.128 | 16 / 1790.489 |
| Native HiGHS | 10 / 828.937 | 21 / 1900.408 | 19 / 2143.503 |
| HiGHS multistart | 10 / 828.937 | 19 / 1773.670 | 19 / 2143.503 |
| MetaStrategist balanced | 10 / 828.937 | 19 / 1685.128 | 16 / 1790.489 |
| MetaStrategist CBLS-heavy | 10 / 828.937 | 19 / 1681.796 | 16 / 1790.489 |
| Timefold LA 400 | 10 / 828.937 | 21 / 1813.936 | 19 / 2143.503 |
| Timefold LA 1,000 | 10 / 828.937 | 21 / 1813.936 | 19 / 2143.503 |

## Réussite et progrès à seize workers

| Profil | LR101 BKS | LRC101 BKS | LR101 amélioré | LRC101 amélioré | CPU moyen (3 cas) | GC recherche médian |
|---|---:|---:|---:|---:|---:|---:|
| CBLS naive | 0/3 | 0/3 | 3/3 | 3/3 | 15.81 | 0.0000 s |
| CBLS ICN | 0/3 | 0/3 | 3/3 | 3/3 | 14.65 | 0.3391 s |
| CBLS native, direct score | 0/3 | 0/3 | 3/3 | 3/3 | 15.46 | 0.0000 s |
| CBLS mixed strategies | 0/3 | 0/3 | 3/3 | 3/3 | 14.08 | 0.3558 s |
| Specialized ICN hybrid | 1/3 | 0/3 | 3/3 | 3/3 | 14.40 | 0.4257 s |
| Bridged ICN hybrid | 1/3 | 0/3 | 3/3 | 3/3 | 13.23 | 0.7088 s |
| Native HiGHS | 1/3 | 0/3 | 1/3 | 0/3 | 1.08 | 0.0000 s |
| HiGHS multistart | 0/3 | 0/3 | 2/3 | 0/3 | 14.16 | 0.1493 s |
| MetaStrategist balanced | 0/3 | 0/3 | 3/3 | 3/3 | 13.30 | 0.4606 s |
| MetaStrategist CBLS-heavy | 0/3 | 0/3 | 3/3 | 3/3 | 14.15 | 0.4430 s |
| Timefold LA 400 | 0/3 | 0/3 | 3/3 | 0/3 | 14.05 | — |
| Timefold LA 1,000 | 0/3 | 0/3 | 3/3 | 0/3 | 13.98 | — |

## Meilleurs essais observés

Ces résultats sont sélectionnés parmi tous les profils et largeurs du pilote ; ils ne représentent pas une médiane ni une probabilité garantie en cinq secondes. La figure `quality-best` montre également le meilleur des trois essais dans chaque cellule.

- LC101 : 10 / 828.936867, CBLS naive, 1 workers, seed/répétition 41.
- LR101 : 19 / 1650.799240, Specialized ICN hybrid, 1 workers, seed/répétition 41.
- LRC101 : 15 / 1735.605247, Specialized ICN hybrid, 4 workers, seed/répétition 43.

## Buffers et préparation

Scores naïf/direct/ICN, décodage de routes et réinsertions : workspaces privés par voie. Groupes de réparation réutilisables, programmes de bridge mis en cache par domaine dans chaque resolver, plans MetaStrategist préchargés. Les snapshots restent possédés. Les modèles JuMP/HiGHS sont reconstruits pour chaque fragment et ne partagent pas de handles ; leur coût reste dans le budget RO. Le nouveau mix CBLS combine meilleure/première amélioration, rejets de plateau 10/100/75 %, et réinsertion toutes les 1/4 étapes. À un worker il reproduit le profil ICN standard.

Le CPU CBLS inclut toute la préparation dans le chrono commun. Le CPU des moteurs externes concerne leur processus natif, construction incluse ; le court préfixe Julia commun est chargé au budget mais son CPU n'est pas fusionné. Les warmups et audits finaux sont séparés. Seize workers comprennent 8 cœurs P, 4 E et 4 frères SMT : pas seize cœurs identiques.

Dans le mix équilibré LC101 à quatre workers, seed 41, la voie HiGHS termine vers 0,93 seconde et prouve la flotte et la distance optimales. Les trois autres voies vont jusqu'à cinq secondes. Une moyenne d'environ 3,15 CPU découle donc aussi d'une voie terminée dans cette allocation statique, et ne mesure pas un plafond du débit CBLS. Une redistribution ou un arrêt sur certificat exigerait une nouvelle variante de coordination ; les résultats présents conservent la fusion finale indépendante annoncée.

Hexaly : modèle et lancement préparés, exécutable absent, aucune mesure ajoutée. Aucune capture GHOST/JuLS sur ces instances et budgets n'est présente. Sources, empreintes, versions et trajets complets dans les captures listées ci-dessous.

## Captures

- [all-variants-core-1t-20261004.toml](all-variants-core-1t-20261004.toml) — SHA-256 `e2b6c16db81a64b125c8c95d289eab6aa14d198dbe69555b486ff7dc960ab706`
- [timefold-late-1t-20261004.toml](timefold-late-1t-20261004.toml) — SHA-256 `2caf3d5ef0516ea568d1f456506141369d08925f102987edc59dfeed98893c57`
- [timefold-late1000-1t-20261004.toml](timefold-late1000-1t-20261004.toml) — SHA-256 `4cb7690d7c8439fdd3ca7ecf8bffdfa6c9526e16cae97aaea1012d08799e29ee`
- [all-variants-core-2t-20261004.toml](all-variants-core-2t-20261004.toml) — SHA-256 `8e1427748c36c78121ad2ffefa447b0bc29594e1f4c035498a4c9299a432417b`
- [timefold-late-2t-20261004.toml](timefold-late-2t-20261004.toml) — SHA-256 `a576d6e853028ec51566d363cf3721f8af4df00a6b63c7d2ef940f3a5d21ef95`
- [timefold-late1000-2t-20261004.toml](timefold-late1000-2t-20261004.toml) — SHA-256 `f6a328e816b6f89e75179ed63c75a1538cdad2fc35145cedba60fe32e78f4582`
- [all-variants-core-4t-20261004.toml](all-variants-core-4t-20261004.toml) — SHA-256 `0a4df46793f05ca73c4eedf165b9313089459cded78d857fee7ec23c14f7aa50`
- [timefold-late-4t-20261004.toml](timefold-late-4t-20261004.toml) — SHA-256 `af9cb6d247f3521937f2796394f62e0b8e9633a5b5b4af388c5c383078a70c6c`
- [timefold-late1000-4t-20261004.toml](timefold-late1000-4t-20261004.toml) — SHA-256 `e4866d055e8676d82748691bae48a5c54e57b8fa9013734bd09ba851c26f0ec7`
- [all-variants-core-8t-20261004.toml](all-variants-core-8t-20261004.toml) — SHA-256 `20305146b11a93654cb26ad35e6e8be6d2422534b2e8592c5b00d0377813483e`
- [timefold-late-8t-20261004.toml](timefold-late-8t-20261004.toml) — SHA-256 `0a9e7cb40c53505f213288507b85fd035a271caa82bc4106a0e91c7a3890abea`
- [timefold-late1000-8t-20261004.toml](timefold-late1000-8t-20261004.toml) — SHA-256 `093e7c43dd847926c6b9f390f04556e8683734655c528f1850da2fc9527e2b80`
- [all-variants-current-16t-20261004.toml](all-variants-current-16t-20261004.toml) — SHA-256 `c3bd968cac1a9ab7b15048f6a597d2f8f0c3a9aa95f5309383753dee703a6b1c`
- [timefold-late-16t-20261004.toml](timefold-late-16t-20261004.toml) — SHA-256 `1e97b39283cb0907e92400afb928326d5098dbc00bcb354892d976eec9dc574c`
- [timefold-late1000-16t-20261004.toml](timefold-late1000-16t-20261004.toml) — SHA-256 `eb19112f0d6d98331ff42de3cb3a6dd9d86413afe7eaa33542f2b5c5f11b3c86`
