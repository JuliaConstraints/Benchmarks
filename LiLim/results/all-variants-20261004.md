# Reassessment of All Solver Variants — 4 October 2026

The pilot contains 504 validated trials: 414 CBLS/HiGHS and 90 Timefold
Community trials, each with a five-second budget. It covers three instances,
three seeds and 1/2/4/8/16 workers. Mixed MetaStrategist allocations start at
four workers.

The objective is lexicographic: fleet size, then distance. Each median is an
actual observed run ranked by that pair; route sets from different runs are
never combined. SINTEF target attainment is descriptive, and LC101 starts at
its reference. SINTEF does not provide a uniform runtime table. Solver
representations and neighborhoods differ, and these exposed instances do not
prove commercial superiority.

## Quality at 16 workers

| Profile | LC101 | LR101 | LRC101 |
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
| MetaStrategist search-heavy | 10 / 828.937 | 19 / 1681.796 | 16 / 1790.489 |
| Timefold LA 400 | 10 / 828.937 | 21 / 1813.936 | 19 / 2143.503 |
| Timefold LA 1,000 | 10 / 828.937 | 21 / 1813.936 | 19 / 2143.503 |

## BKS attainment and improvement at 16 workers

| Profile | LR101 BKS | LRC101 BKS | LR101 improved | LRC101 improved | Mean CPU (3 cases) | Median search GC |
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
| MetaStrategist search-heavy | 0/3 | 0/3 | 3/3 | 3/3 | 14.15 | 0.4430 s |
| Timefold LA 400 | 0/3 | 0/3 | 3/3 | 0/3 | 14.05 | — |
| Timefold LA 1,000 | 0/3 | 0/3 | 3/3 | 0/3 | 13.98 | — |

## Best observed trials

These results are the best selected across all pilot profiles and worker counts;
they are neither medians nor guaranteed probabilities for a five-second run.
The `quality-best` figure also shows the best of three trials in each cell.

- LC101: 10 / 828.936867, CBLS naive, 1 worker, seed/repetition 41.
- LR101: 19 / 1650.799240, Specialized ICN hybrid, 1 worker, seed/repetition 41.
- LRC101: 15 / 1735.605247, Specialized ICN hybrid, 4 workers, seed/repetition 43.

## Buffers and preparation

Naive, direct and ICN scores, route decoding and reinsertions use lane-private
workspaces. Repair groups are reusable, bridge programs are cached per domain
inside each resolver, and MetaStrategist plans are prepared in advance.
Snapshots retain ownership. JuMP/HiGHS models are rebuilt for each fragment and
do not share handles; their construction remains inside the RO budget. The new
CBLS mix combines best/first improvement, 10/100/75% plateau rejection, and
reinsertion every 1/4 steps. With one worker it reproduces the standard ICN
profile.

CBLS CPU accounting includes all preparation in the common clock. External
engine CPU refers to their native process, including model construction; the
short shared Julia prefix counts against the budget but its CPU is not merged
into theirs. Warmups and final audits are separate. Sixteen workers use eight
P-cores, four E-cores and four P-core SMT siblings; these are not sixteen
identical physical cores.

In the balanced four-worker LC101 allocation, seed 41, the HiGHS lane finishes
at about 0.93 seconds and proves the fleet and distance optimal. The other three
lanes continue to five seconds. The resulting mean of about 3.15 CPUs partly
reflects that completed lane; it does not measure a CBLS throughput ceiling.
Redistribution or stopping on a certificate would require a different
coordination variant. The current results retain the announced independent
final merge.

Hexaly's model and launcher are prepared, but its executable is absent and no
Hexaly measurement has been added. No GHOST/JuLS capture exists for these
instances and budgets. Sources, fingerprints, versions and complete traces are
listed in the capture files below.

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
