# sml-cluster

[![CI](https://github.com/sjqtentacles/sml-cluster/actions/workflows/ci.yml/badge.svg)](https://github.com/sjqtentacles/sml-cluster/actions/workflows/ci.yml)

Clustering in pure Standard ML — **k-means** with k-means++ seeding,
**DBSCAN** (density-based), and **hierarchical agglomerative** clustering
(single / complete / average linkage) — built on
[`sml-prng`](https://github.com/sjqtentacles/sml-prng) for deterministic,
seedable k-means++ initialization. No FFI, no ambient randomness, no external
dependencies, and **deterministic, byte-identical** under both
[MLton](http://mlton.org/) and [Poly/ML](https://www.polyml.org/).

## Status

- 36 assertions, green on MLton and Poly/ML (byte-identical output).
- Basis-library + vendored `sml-prng` only; deterministic across compilers.
- Vendors `sml-prng` (Layout B), so the repo builds standalone.

## Install

With [`smlpkg`](https://github.com/diku-dk/smlpkg):

```
smlpkg add github.com/sjqtentacles/sml-cluster
smlpkg sync
```

Include the MLB from your own (it pulls in the vendored `sml-prng`):

```
local
  $(SML_LIB)/basis/basis.mlb
  lib/github.com/sjqtentacles/sml-cluster/... (via smlpkg)
in
  ...
end
```

This brings `structure Cluster` (and the vendored generators) into scope.

## Quick start

```sml
(* points are real vectors as `real list`; all distances are Euclidean *)
val data =
  [ [0.0,0.0], [1.0,0.0], [0.0,1.0], [1.0,1.0]       (* blob near origin   *)
  , [10.0,10.0], [11.0,10.0], [10.0,11.0], [11.0,11.0] ] (* blob near (10,10) *)

(* k-means: inject a seeded sml-prng generator for k-means++, thread state *)
val (result, _) =
  Cluster.kmeans { k = 2, maxIter = 100, data = data } (SplitMix64.seed 0w42)
val { centroids, assignments, inertia, iterations } = result
(* assignments : int list (cluster id per point); inertia : real *)

(* DBSCAN: eps-neighbourhoods, minPts core threshold; ~1 = noise *)
val { labels, nClusters } =
  Cluster.dbscan { eps = 1.5, minPts = 3, data = data }

(* hierarchical agglomerative clustering -> the merge sequence (dendrogram) *)
val merges =
  Cluster.hierarchical { linkage = Cluster.Single, data = data }
(* each merge: { left : int, right : int, dist : real, size : int } *)
```

## API (`signature CLUSTER`)

```sml
type rng                      (* underlying sml-prng generator state *)
type point = real list

exception Empty
exception Dim of string

val euclideanSq : point * point -> real
val euclidean   : point * point -> real

(* ---- k-means (k-means++ seeding + Lloyd iterations) ---- *)
type kmeansResult =
  { centroids   : point list   (* k centroids, in cluster-id order       *)
  , assignments : int list     (* cluster id (0..k-1) per input point     *)
  , inertia     : real         (* sum of squared point-to-centroid dists  *)
  , iterations  : int }
val kmeans :
  { k : int, maxIter : int, data : point list } -> rng -> kmeansResult * rng

(* ---- DBSCAN ---- *)
val noise : int                          (* the noise label, = ~1 *)
type dbscanResult = { labels : int list, nClusters : int }
val dbscan : { eps : real, minPts : int, data : point list } -> dbscanResult

(* ---- hierarchical agglomerative clustering ---- *)
datatype linkage = Single | Complete | Average
type merge = { left : int, right : int, dist : real, size : int }
val hierarchical : { linkage : linkage, data : point list } -> merge list
```

The library is a functor
`ClusterFn (R : RANDOM) :> CLUSTER where type rng = R.state` over a
[`sml-prng`](https://github.com/sjqtentacles/sml-prng) generator. The default
`structure Cluster = ClusterFn (SplitMix64)`, so its `rng` is
`SplitMix64.state`; instantiate `ClusterFn` yourself to seed k-means++ from
`Xoshiro256ss` or `Pcg32` instead.

### Conventions

- **Points** are `real list`; every point in one call must share the same
  dimension, otherwise `Dim` is raised. Distances are Euclidean (`euclidean`
  for the metric, `euclideanSq` when only comparisons matter).
- **k-means** uses k-means++ seeding drawn from the injected generator: the
  first centre is uniform, each subsequent centre is sampled with probability
  proportional to the squared distance to the nearest chosen centre. Lloyd's
  algorithm then iterates to convergence or `maxIter`. Assignment ties break
  toward the lowest cluster id; an empty cluster keeps its previous centroid.
  `kmeans` is **pure and seedable** — same seed yields the same clustering on
  every run, machine, and compiler.
- **`inertia`** is the within-cluster sum of squared distances
  `Σ ‖x − c(x)‖²` (the k-means objective).
- **DBSCAN** marks a point *core* when at least `minPts` points (including
  itself) lie within distance `eps`; it visits points and expands
  neighbourhoods in increasing input-index order, so the labelling is
  deterministic. `labels` are cluster ids in `[0, nClusters)` or `noise`
  (= `~1`). Border points are absorbed into the first cluster that reaches
  them.
- **Hierarchical** clustering starts with every point its own cluster and
  repeatedly merges the two closest clusters under the chosen linkage
  (`Single` = min, `Complete` = max, `Average` = mean of cross-pair
  distances). Singletons carry ids `0..n-1`; each merge yields the next id.
  Ties break toward the lowest `(left, right)` id pair, so the dendrogram is
  deterministic.

## Build & test

```
make test        # MLton
make test-poly   # Poly/ML
make all-tests   # both
make example     # build + run examples/demo.sml
make clean
```

Both compilers run the same strict-TDD suite, seeded with closed-form vectors:
two well-separated blobs that k-means and DBSCAN must recover (checked
permutation-invariantly, with inertia pinned to `4.0` and centroids to the
blob means); a fixed-seed reproducibility check on k-means++; a DBSCAN
reference with hand-derived core/border/noise labels; and a four-point
colinear dendrogram whose single/complete/average merge distances
(`3 / 5 / 4`) are computed by hand.

## Example

`make example` clusters three fixed 2-D blobs (18 points) with k-means++
(`k = 3`, SplitMix64 seed `0x20260621`), runs the same data through DBSCAN and
single-linkage agglomeration, and prints a report plus an ASCII scatter
coloured by cluster id. The output is byte-identical under MLton and Poly/ML
and is committed verbatim at [`assets/report.txt`](assets/report.txt):

```
=== sml-cluster demo =========================================

Dataset: 18 points in R^2, three blobs of six.
Seed:    SplitMix64 0x20260621 (deterministic k-means++).

k-means (k = 3, k-means++ seeding, Lloyd to convergence)
  iterations = 1
  inertia    = 26.5000
  cluster 0: centroid (8.00, 4.83)  size 6
  cluster 1: centroid (18.00, 15.83)  size 6
  cluster 2: centroid (30.00, 5.83)  size 6

DBSCAN (eps = 3.0, minPts = 2)
  clusters found = 3   noise points = 0

Hierarchical agglomerative (single linkage)
  merges       = 17
  final merge  : clusters 30 + 33 at distance 12.8062 (size 18)

ASCII scatter (digit = k-means cluster id)
  x in [7.0, 31.0],  y in [4.0, 17.0]

  .....................1....1.........................
  .......................1............................
  ....................................................
  .....................1.1..1.........................
  ....................................................
  ....................................................
  ....................................................
  ....................................................
  ....................................................
  ....................................................
  ....................................................
  ....................................................
  ....................................................
  ....................................................
  ...............................................2...2
  0...0............................................2..
  ....................................................
  ..0............................................2.2.2
  0.0.0...............................................

=============================================================
```

### Poly/ML note

This repository is shipped as **CI Variant B**: it vendors `sml-prng` and is
real-arithmetic-heavy (Euclidean distances, centroid means, linkage
distances). CI builds Poly/ML 5.9.1 from source rather than using the Ubuntu
package (Poly/ML 5.7.1), whose X86 code generator crashes (`asGenReg raised
while compiling`) on heavy real-arithmetic code. See
`.github/workflows/ci.yml`.

## License

MIT — see [LICENSE](LICENSE).
