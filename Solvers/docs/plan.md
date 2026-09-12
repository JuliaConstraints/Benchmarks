# Plan de réalisation — comparaisons de solveurs

Décision du 12 septembre 2026 : utiliser le dépôt existant `JuliaConstraints/Benchmarks`,
avec le sous-projet `Solvers`, séparé du dépôt d'apprentissage. Le premier périmètre est
la programmation linéaire en nombres entiers (ILP), à domaines bornés. Les petits cas
de conformité ne prétendent pas représenter la difficulté d'une campagne industrielle.

## Architecture et responsabilité des données

* COPInstances : téléchargement à la demande, octets bruts, provenance et droits d'usage.
* ConstraintModels : lecteurs sémantiques, formulations réutilisables, décodage/validation.
* XCSP3 et ses bridges : transformations facultatives, identifiées dans les essais.
* Benchmarks/Solvers : matrice de configurations, adaptateurs d'expériences, contrôles,
  orchestration et archives de comparaison. Une formulation native réutilisable pourra
  être extraite vers ConstraintModels ; son intégration expérimentale reste ici.
* LocalSearchSolvers : générateur de solveurs ; CBLS : accès JuMP à ce générateur.
* ConstraintLearningBenchmarks : HPO/apprentissage en cours, sources et archives intactes.
  Les configurations apprises sont importées par identité et provenance, pas par lecture
  opportuniste d'un répertoire de résultats encore en écriture.

## Lots et critères de sortie

| Lot | Travail | Critère de sortie |
|---|---|---|
| 0 — socle | Registre natif/JuMP, cas ILP, oracle et résultat explicite | Cas et identités vérifiés, aucune indisponibilité présentée comme réussite |
| 1 — raccords locaux | HiGHS/JuMP comme contrôle ; LocalSearchSolvers direct, CBLS/JuMP, GHOST natif/JuMP | Chaque chemin construit/résout/décode, solution revalidée ; arrêts et erreurs correctement classés |
| 2 — autres moteurs | JuLS natif puis JuMP ; Timefold natif puis JuMP ; Hexaly natif/JuMP si accessible | Sous-ensembles et versions qualifiés dans des environnements séparés |
| 3 — profils appariés | Intégrer GHOST-like, puis JuLS-like et Timefold-like selon mécanismes disponibles | Stratégies/paramètres transmis, écarts déclarés, comparaison des décisions sur petits cas |
| 4 — protocole performance | Modèles adaptés, budgets, réglages équitables, HPO et séparation des corpus | Protocole figé avant résultats ; représentativité et coûts de l'interface séparés |
| 5 — campagnes durables | Archives, reprise, matrice de versions et détection de régressions | Rejeu depuis une archive figée et nouvelle tentative sans écraser l'historique |

**Livraison actuelle : lot 0 préparé et testé.** Le plan génère 228 combinaisons
(19 chemins × 6 cas × 2 profils de threads), sans les exécuter. Tous les raccords du lot 1
restent à intégrer dans ce nouveau sous-projet. Les tests de profils réalisés auparavant
dans ConstraintModels ne valent pas qualification de cette matrice.

## Cas ILP et fonctionnement attendu

Six cas : couverture binaire, entiers bornés, sac à dos en maximisation, égalité et domaine
négatif, parité infaisable, variable fixée. Coefficients et objectifs entiers, offsets et
sens explicites. L'oracle énumère au plus 4096 affectations, en arithmétique entière exacte.
Pas de Big-M arbitraire ni de conversion silencieuse. Pour les futurs solveurs numériques,
définir et enregistrer la politique de tolérance et conserver les valeurs brutes.

Sur cas faisable, exiger un témoin admissible et un objectif cohérent ; ne pas imposer à
une heuristique une preuve d'optimalité. Sur cas infaisable, l'oracle sert de référence,
mais le solveur peut retourner une limite sans témoin. Une exception d'interface ou une
solution invalide n'est ni un timeout normal ni une infaisabilité démontrée.

Vérifier aussi constructions répétées, mutations/reconstruction, absence de résultat,
paramètres non supportés et stratégies effectivement sélectionnées. Les paramètres par
défaut dépendant de la taille du modèle doivent être résolus après sa construction.

## Comparaison honnête et modèles natifs

Conserver pour chaque moteur un chemin natif adapté et un chemin JuMP lorsque réalisable.
Le petit ILP matriciel est un cas de conformité, pas une exigence universelle de modélisation.
Pour les campagnes, employer les primitives, évaluations incrémentales et voisinages
appropriés à chacun ; comparer aussi des formulations plus spécialisées lorsque pertinentes.
« Aussi optimaux que possible » signifie ici examinés, documentés, réglés et validés ;
ne pas prétendre démontrer que la formulation choisie est la meilleure possible.

Identifier distinctement formulation, moteur, interface, bridges, configuration de
stratégies et paramètres. Mesurer le coût propre de l'interface à représentation et
configuration identiques lorsque possible ; sinon attribuer le résultat au chemin complet.
Le coût négligeable de JuMP est une hypothèse à tester, jamais un présupposé.

Les profils GHOST-like/JuLS-like/etc. sont des solveurs générés par LocalSearchSolvers,
pas d'autres noms pour les moteurs originaux. Archiver les correspondances de stratégies,
unités (propositions/mouvements/temps), défauts résolus, scores et différences connues.
Ne pas brider le moteur concurrent pour rendre l'appariement plus facile. Conserver ses
résultats représentatifs même si certaines stratégies sont inconnues ou non reproductibles.

## HPO, diagnostic et futures campagnes

Deux axes complémentaires : qualité du code et sélection/réglage des stratégies du
générateur. Étudier ensuite les fonctions d'erreur en isolant leurs effets ; ajouter des
stratégies ou meta-strategist si le diagnostic le justifie. Conserver les configurations
de référence et attribuer un nouvel identifiant à chaque amélioration.

Séparer instances/seeds de réglage, validation et test final. Définir budget HPO,
budget de résolution et métrique de sélection ; documenter l'effort de réglage des
concurrents et toute asymétrie. Pas de sélection rétrospective du meilleur profil par
instance présentée comme un solveur utilisable. Définir une politique de sélection
si plusieurs solveurs spécialisés sont déployés et comptabiliser son coût.

Réutiliser les contrats d'identité/archive/reprise éprouvés dans les campagnes existantes
après extraction ou dépendance propre ; éviter de recopier leur moteur HPO dans ce pilote.
Employer PerfChecker pour les mesures de coût, en conservant les unités et périmètres de
mémoire propres à Julia/JVM/C++. À terme : time-to-feasible, qualité à temps fixé, courbes
de progression, temps total et coût de construction, dispersion et taux d'échec.

La campagne durable sera déclenchée explicitement au début. Une exécution périodique ne
sera configurée qu'après définition des budgets, du stockage et des déclencheurs. Li-Lim,
SAT, coloration, TSP et ordonnancement restent les extensions après le pilote ILP.
