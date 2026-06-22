(* cluster.sig

   Pure Standard ML clustering: k-means with k-means++ seeding, DBSCAN, and
   hierarchical agglomerative clustering (single/complete/average linkage).

   Points are real vectors represented as `real list`; every point in a single
   call must share the same dimension (otherwise `Dim` is raised). All distances
   are Euclidean.

   Determinism is the central design constraint: every result is identical on
   MLton and Poly/ML for the same input. The only source of randomness is the
   injected `sml-prng` generator used by k-means++ seeding -- the library is a
   functor `ClusterFn (R : RANDOM)` over a generator, and the default `Cluster`
   structure is instantiated with `SplitMix64`, so `rng = SplitMix64.state`.
   `kmeans` threads the generator state exactly like `sml-prng`: it takes a state
   and returns the result together with the successor state. Same seed => same
   clustering, every run, machine and compiler.

   DBSCAN and hierarchical clustering are fully deterministic without any
   randomness: DBSCAN visits points and expands neighbourhoods in increasing
   input-index order, and agglomerative merges break ties by lowest cluster id. *)

signature CLUSTER =
sig
  (* Generator state of the underlying `sml-prng` instance. *)
  type rng

  (* A point in R^d. *)
  type point = real list

  (* Raised when a clustering routine is given no data. *)
  exception Empty

  (* Raised on a dimension mismatch or a nonsensical parameter (e.g. k <= 0,
     k > number of points). The string describes the problem. *)
  exception Dim of string

  (* ---- distances ---- *)

  (* Squared Euclidean distance; cheaper when only comparisons are needed. *)
  val euclideanSq : point * point -> real

  (* Euclidean distance. *)
  val euclidean : point * point -> real

  (* ---- k-means (k-means++ seeding + Lloyd iterations) ---- *)

  type kmeansResult =
    { centroids   : point list   (* k centroids, in cluster-id order        *)
    , assignments : int list     (* cluster id (0..k-1) per input point      *)
    , inertia     : real         (* sum of squared point-to-centroid dists   *)
    , iterations  : int          (* Lloyd iterations actually run            *)
    }

  (* `kmeans {k, maxIter, data} rng` seeds k centroids with k-means++ (drawing
     from `rng`), then runs Lloyd's algorithm until the assignments stop
     changing or `maxIter` iterations elapse. Returns the result and the
     successor generator state. Raises `Empty` on empty data, `Dim` if
     k <= 0, k > |data|, or the points are ragged. Assignment ties are broken
     toward the lowest cluster id; an empty cluster keeps its previous centroid
     (so the run stays deterministic). *)
  val kmeans :
    { k : int, maxIter : int, data : point list } -> rng -> kmeansResult * rng

  (* ---- DBSCAN ---- *)

  (* Cluster labels: a cluster id in [0, nClusters), or `noise` (= ~1). *)
  val noise : int

  type dbscanResult =
    { labels : int list, nClusters : int }

  (* Density-based clustering. A point is a core point if at least `minPts`
     points (including itself) lie within distance `eps`. Visits points in
     increasing input-index order, so the labelling is deterministic. Raises
     `Empty` on empty data, `Dim` on ragged points or minPts < 1 or eps < 0. *)
  val dbscan :
    { eps : real, minPts : int, data : point list } -> dbscanResult

  (* ---- hierarchical agglomerative clustering ---- *)

  datatype linkage = Single | Complete | Average

  (* One agglomeration step. Singleton clusters carry ids 0..n-1 (one per input
     point, in input order); each merge produces a new cluster whose id is the
     next integer (n, n+1, ...). `left` < `right` are the merged cluster ids,
     `dist` the linkage distance at which they merged, `size` the number of
     original points in the merged cluster. *)
  type merge =
    { left : int, right : int, dist : real, size : int }

  (* Agglomerative clustering: start with every point its own cluster and
     repeatedly merge the two closest clusters (by the chosen linkage) until one
     cluster remains, returning the n-1 merges in order. Ties are broken toward
     the lowest (left, right) cluster-id pair, so the dendrogram is
     deterministic. Raises `Empty` on empty data, `Dim` on ragged points. *)
  val hierarchical :
    { linkage : linkage, data : point list } -> merge list
end
