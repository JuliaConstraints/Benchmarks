# Li-Lim : erreurs ICN, threads et portefeuilles

369 essais audités, 166700484120 appels réels aux décodeurs ICN. Trois instances exposées, trois graines, budget mural de 10 secondes par essai. Les résultats sont diagnostiques.

Les erreurs ICN et directes qualifiées sont numériquement identiques ici. Ce test mesure leur coût et le parallélisme, sans démontrer un bénéfice d'apprentissage. Les travailleurs de recherche locale sont des trajectoires indépendantes ; les plans MetaStrategist sont statiques et réellement exécutés.

Les profils CBLS emploient l'API native LocalSearchSolvers, son moteur de recherche ; le coût de traduction de la façade JuMP/MOI n'est pas inclus. Dans les portefeuilles mixtes, les graines restent attachées aux positions globales des voies : une famille ne reçoit pas automatiquement la graine de la première voie. Cette allocation est fixée avant la campagne, et peut être défavorable à un profil.

Source mesurée : `43852f287d5246df77a2db599aca218ea70817d0`. Banque ICN : `61225eadc114677498e781befe67afbbcab98b480f81c5b7b0f2e0009297ecaf`. Dépassement mural maximal : 0.1682 s ; les solutions améliorées sont toutes validées et datées dans le budget. La fusion et son audit sont chronométrés séparément.

La campagne a été interrompue à la demande de l'utilisateur après 358 essais terminés. Les 11 essais manquants ont été repris avec les mêmes sources de solveur, banque, instances et budgets. Les empreintes du contrôleur de reprise, les temps de préparation des deux segments et l'attribution de chaque essai sont conservés. Cette séparation temporelle doit rester présente dans l'interprétation des résultats.

## lc101

Médiane lexicographique parmi les trois répétitions (flotte, distance), puis médiane du nombre moyen de CPU actifs.

| Profil | Threads | Véhicules | Distance | CPU actifs | Réinsertions/s |
|---|---:|---:|---:|---:|---:|
| cbls_naive | 1 | 10 | 828.937 | 1.00 | 1066937 |
| cbls_naive | 2 | 10 | 828.937 | 1.68 | 1721361 |
| cbls_naive | 4 | 10 | 828.937 | 2.63 | 2425367 |
| cbls_naive | 8 | 10 | 828.937 | 4.07 | 2493975 |
| cbls_naive | 16 | 10 | 828.937 | 6.61 | 2513490 |
| cbls_icn | 1 | 10 | 828.937 | 1.00 | 778763 |
| cbls_icn | 2 | 10 | 828.937 | 1.63 | 1235020 |
| cbls_icn | 4 | 10 | 828.937 | 2.52 | 1622941 |
| cbls_icn | 8 | 10 | 828.937 | 3.95 | 1731854 |
| cbls_icn | 16 | 10 | 828.937 | 6.51 | 1713271 |
| cbls_direct | 1 | 10 | 828.937 | 1.00 | 1078224 |
| cbls_direct | 2 | 10 | 828.937 | 1.68 | 1743238 |
| cbls_direct | 4 | 10 | 828.937 | 2.63 | 2441378 |
| cbls_direct | 8 | 10 | 828.937 | 4.07 | 2469814 |
| cbls_direct | 16 | 10 | 828.937 | 6.58 | 2525746 |
| hybrid_specialized_icn | 1 | 10 | 828.937 | 1.00 | 495398 |
| hybrid_specialized_icn | 2 | 10 | 828.937 | 1.76 | 821804 |
| hybrid_specialized_icn | 4 | 10 | 828.937 | 2.90 | 1097774 |
| hybrid_specialized_icn | 8 | 10 | 828.937 | 4.58 | 1336368 |
| hybrid_specialized_icn | 16 | 10 | 828.937 | 7.59 | 1390225 |
| hybrid_bridged_icn | 1 | 10 | 828.937 | 1.00 | 510802 |
| hybrid_bridged_icn | 2 | 10 | 828.937 | 1.73 | 791638 |
| hybrid_bridged_icn | 4 | 10 | 828.937 | 2.86 | 1032978 |
| hybrid_bridged_icn | 8 | 10 | 828.937 | 4.61 | 1178413 |
| hybrid_bridged_icn | 16 | 10 | 828.937 | 7.69 | 1147293 |
| highs_native | 1 | 10 | 828.937 | 1.00 | 0 |
| highs_native | 2 | 10 | 828.937 | 1.01 | 0 |
| highs_native | 4 | 10 | 828.937 | 1.03 | 0 |
| highs_native | 8 | 10 | 828.937 | 1.06 | 0 |
| highs_native | 16 | 10 | 828.937 | 1.12 | 0 |
| highs_portfolio | 1 | 10 | 828.937 | 1.00 | 0 |
| highs_portfolio | 2 | 10 | 828.937 | 1.99 | 0 |
| highs_portfolio | 4 | 10 | 828.937 | 3.83 | 0 |
| highs_portfolio | 8 | 10 | 828.937 | 7.04 | 0 |
| highs_portfolio | 16 | 10 | 828.937 | 12.75 | 0 |
| mixed_balanced | 4 | 10 | 828.937 | 2.36 | 1157758 |
| mixed_balanced | 8 | 10 | 828.937 | 3.75 | 1347991 |
| mixed_balanced | 16 | 10 | 828.937 | 6.10 | 1343216 |
| mixed_ls_heavy | 4 | 10 | 828.937 | 2.30 | 1327413 |
| mixed_ls_heavy | 8 | 10 | 828.937 | 3.91 | 1515948 |
| mixed_ls_heavy | 16 | 10 | 828.937 | 6.58 | 1507262 |

## lr101

Médiane lexicographique parmi les trois répétitions (flotte, distance), puis médiane du nombre moyen de CPU actifs.

| Profil | Threads | Véhicules | Distance | CPU actifs | Réinsertions/s |
|---|---:|---:|---:|---:|---:|
| cbls_naive | 1 | 20 | 1695.138 | 1.00 | 699976 |
| cbls_naive | 2 | 20 | 1695.138 | 1.69 | 1143081 |
| cbls_naive | 4 | 20 | 1695.138 | 2.62 | 1609587 |
| cbls_naive | 8 | 20 | 1695.138 | 4.14 | 1725217 |
| cbls_naive | 16 | 19 | 1685.959 | 6.75 | 1785538 |
| cbls_icn | 1 | 20 | 1695.138 | 1.00 | 477026 |
| cbls_icn | 2 | 20 | 1695.138 | 1.64 | 782091 |
| cbls_icn | 4 | 20 | 1695.138 | 2.54 | 974940 |
| cbls_icn | 8 | 20 | 1695.138 | 3.98 | 1092824 |
| cbls_icn | 16 | 19 | 1685.959 | 6.62 | 1093216 |
| cbls_direct | 1 | 20 | 1695.138 | 1.00 | 711224 |
| cbls_direct | 2 | 20 | 1695.138 | 1.69 | 1163445 |
| cbls_direct | 4 | 20 | 1695.138 | 2.61 | 1589998 |
| cbls_direct | 8 | 20 | 1695.138 | 4.14 | 1725900 |
| cbls_direct | 16 | 19 | 1685.959 | 6.72 | 1759483 |
| hybrid_specialized_icn | 1 | 20 | 1703.037 | 1.00 | 296957 |
| hybrid_specialized_icn | 2 | 20 | 1693.081 | 1.76 | 521044 |
| hybrid_specialized_icn | 4 | 19 | 1671.576 | 2.85 | 742213 |
| hybrid_specialized_icn | 8 | 19 | 1671.576 | 4.44 | 930913 |
| hybrid_specialized_icn | 16 | 19 | 1654.132 | 7.34 | 957190 |
| hybrid_bridged_icn | 1 | 20 | 1738.197 | 1.00 | 302672 |
| hybrid_bridged_icn | 2 | 20 | 1693.081 | 1.75 | 509465 |
| hybrid_bridged_icn | 4 | 19 | 1681.796 | 2.87 | 650931 |
| hybrid_bridged_icn | 8 | 19 | 1681.796 | 4.54 | 809599 |
| hybrid_bridged_icn | 16 | 19 | 1681.796 | 7.58 | 842163 |
| highs_native | 1 | 21 | 1900.408 | 1.00 | 0 |
| highs_native | 2 | 21 | 1900.408 | 1.06 | 0 |
| highs_native | 4 | 21 | 1900.408 | 1.06 | 0 |
| highs_native | 8 | 21 | 1900.408 | 1.07 | 0 |
| highs_native | 16 | 21 | 1900.408 | 1.09 | 0 |
| highs_portfolio | 1 | 21 | 1900.408 | 1.00 | 0 |
| highs_portfolio | 2 | 19 | 1650.799 | 1.51 | 0 |
| highs_portfolio | 4 | 19 | 1650.799 | 3.51 | 0 |
| highs_portfolio | 8 | 19 | 1650.799 | 6.09 | 0 |
| highs_portfolio | 16 | 19 | 1650.799 | 14.43 | 0 |
| mixed_balanced | 4 | 19 | 1685.959 | 3.19 | 700777 |
| mixed_balanced | 8 | 19 | 1650.799 | 4.86 | 837917 |
| mixed_balanced | 16 | 19 | 1650.799 | 8.69 | 788998 |
| mixed_ls_heavy | 4 | 19 | 1685.959 | 3.11 | 812802 |
| mixed_ls_heavy | 8 | 19 | 1685.959 | 4.60 | 936592 |
| mixed_ls_heavy | 16 | 19 | 1654.132 | 7.14 | 937071 |

## lrc101

Médiane lexicographique parmi les trois répétitions (flotte, distance), puis médiane du nombre moyen de CPU actifs.

| Profil | Threads | Véhicules | Distance | CPU actifs | Réinsertions/s |
|---|---:|---:|---:|---:|---:|
| cbls_naive | 1 | 17 | 1797.545 | 1.00 | 810506 |
| cbls_naive | 2 | 17 | 1797.545 | 1.71 | 1339762 |
| cbls_naive | 4 | 17 | 1797.545 | 2.61 | 1746005 |
| cbls_naive | 8 | 17 | 1797.545 | 4.18 | 1952307 |
| cbls_naive | 16 | 17 | 1793.425 | 6.71 | 1970002 |
| cbls_icn | 1 | 17 | 1797.545 | 1.00 | 557994 |
| cbls_icn | 2 | 17 | 1797.545 | 1.66 | 910994 |
| cbls_icn | 4 | 17 | 1797.545 | 2.51 | 1133989 |
| cbls_icn | 8 | 17 | 1797.545 | 3.99 | 1253764 |
| cbls_icn | 16 | 17 | 1793.425 | 6.52 | 1268326 |
| cbls_direct | 1 | 17 | 1797.545 | 1.00 | 824320 |
| cbls_direct | 2 | 17 | 1797.545 | 1.71 | 1350662 |
| cbls_direct | 4 | 17 | 1797.545 | 2.63 | 1751700 |
| cbls_direct | 8 | 17 | 1797.545 | 4.17 | 1967438 |
| cbls_direct | 16 | 17 | 1793.425 | 6.63 | 1947601 |
| hybrid_specialized_icn | 1 | 17 | 1795.539 | 1.00 | 354149 |
| hybrid_specialized_icn | 2 | 17 | 1797.545 | 1.77 | 607336 |
| hybrid_specialized_icn | 4 | 16 | 1766.246 | 2.92 | 826169 |
| hybrid_specialized_icn | 8 | 16 | 1766.246 | 4.69 | 1008770 |
| hybrid_specialized_icn | 16 | 16 | 1766.246 | 7.70 | 1030397 |
| hybrid_bridged_icn | 1 | 17 | 1797.545 | 1.00 | 360579 |
| hybrid_bridged_icn | 2 | 17 | 1797.545 | 1.76 | 601315 |
| hybrid_bridged_icn | 4 | 17 | 1790.627 | 2.94 | 781533 |
| hybrid_bridged_icn | 8 | 17 | 1792.201 | 4.79 | 908059 |
| hybrid_bridged_icn | 16 | 16 | 1790.489 | 7.82 | 1028974 |
| highs_native | 1 | 19 | 2143.503 | 1.00 | 0 |
| highs_native | 2 | 19 | 2143.503 | 1.02 | 0 |
| highs_native | 4 | 19 | 2143.503 | 1.02 | 0 |
| highs_native | 8 | 19 | 2143.503 | 1.03 | 0 |
| highs_native | 16 | 19 | 2143.503 | 1.03 | 0 |
| highs_portfolio | 1 | 19 | 2143.503 | 1.00 | 0 |
| highs_portfolio | 2 | 19 | 2143.503 | 2.00 | 0 |
| highs_portfolio | 4 | 19 | 2143.503 | 4.00 | 0 |
| highs_portfolio | 8 | 19 | 2143.503 | 7.97 | 0 |
| highs_portfolio | 16 | 19 | 2143.503 | 15.26 | 0 |
| mixed_balanced | 4 | 17 | 1792.201 | 3.21 | 783197 |
| mixed_balanced | 8 | 16 | 1766.246 | 5.37 | 916296 |
| mixed_balanced | 16 | 16 | 1790.489 | 9.02 | 869164 |
| mixed_ls_heavy | 4 | 17 | 1792.201 | 3.13 | 897303 |
| mixed_ls_heavy | 8 | 17 | 1797.545 | 4.63 | 1037484 |
| mixed_ls_heavy | 16 | 17 | 1793.425 | 7.11 | 1058534 |

## Comparaisons appariées

Gain / égalité / recul par rapport au profil de référence, pour la même instance, largeur et graine. À flotte égale, tolérance d'égalité de distance : 1e-6. Les cellules partagent trois instances et ne sont pas des observations indépendantes.

| Profil | Référence | Gain | Égalité | Recul |
|---|---|---:|---:|---:|
| cbls_icn | cbls_direct | 0 | 45 | 0 |
| cbls_icn | cbls_naive | 0 | 45 | 0 |
| hybrid_specialized_icn | cbls_icn | 23 | 18 | 4 |
| hybrid_bridged_icn | cbls_icn | 17 | 23 | 5 |
| hybrid_specialized_icn | highs_native | 25 | 15 | 5 |
| hybrid_specialized_icn | highs_portfolio | 19 | 17 | 9 |
| mixed_balanced | cbls_icn | 11 | 12 | 4 |
| mixed_balanced | highs_portfolio | 10 | 15 | 2 |
| mixed_ls_heavy | mixed_balanced | 4 | 17 | 6 |

## Limites et reproduction

Les CPU 1 à 8 sont des cœurs P distincts ; la largeur 16 ajoute quatre cœurs E et quatre frères SMT. Les compteurs CPU publient l'utilisation réelle ; une limite de threads ne signifie pas que toutes les phases utilisent cette largeur. HiGHS natif et N HiGHS série sont rapportés séparément. Aucune comparaison Timefold/Hexaly, aucune adaptation MetaStrategist ni confirmation sur de nouvelles instances n'est prétendue.

Les variantes bridgées exécutent XCSP3Bridges pour les égalités discrètes de route, avec des DAG manuels. La banque apprise/reconstruite de bridges n'est pas chargée dans ces fragments ; les ICN sont utilisées par le parent CBLS.

La référence HiGHS conserve le modèle compact et les deux phases de la première campagne : flotte d'abord, distance après preuve d'optimalité de la flotte. Cela peut limiter l'amélioration de distance dans les petits budgets. Elle n'est pas présentée comme le meilleur modèle ou réglage HiGHS possible ; une variante d'objectif scalaire lexicographique et un effort de réglage doivent être comparés avant toute affirmation industrielle.

Protocole : [ICN_THREADS.md](../ICN_THREADS.md). Configuration : [icn-threads.toml](../config/icn-threads.toml). Les sources mesurées et les empreintes des traces sont conservées dans le TOML associé. Chaque solution et chaque événement ont été revérifiés dans le problème original.

