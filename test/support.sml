(* support.sml -- shared helpers for the sml-cluster tests.

   Clustering mixes integer labels (compared exactly) with real centroids and
   distances (compared through an explicit epsilon, never `=` or
   `Real.toString`, which differ between MLton and Poly/ML). A tight `eps`
   (1e-9) pins centroid coordinates, inertias and linkage distances. *)

structure Support =
struct
  open Cluster

  val eps = 1E~9

  fun approx (a, b) = Real.abs (a - b) <= eps
  fun approxTol tol (a, b) = Real.abs (a - b) <= tol

  fun checkApprox name (expected, actual) =
    Harness.check name (approx (expected, actual))

  fun checkApproxTol tol name (expected, actual) =
    Harness.check name (approxTol tol (expected, actual))

  (* Compare two points coordinate-wise within eps. *)
  fun pointApprox (a, b) =
    List.length a = List.length b
    andalso ListPair.all approx (a, b)

  fun checkPoint name (expected, actual) =
    Harness.check name (pointApprox (expected, actual))

  fun checkPointTol tol name (expected, actual) =
    Harness.check name
      (List.length expected = List.length actual
       andalso ListPair.all (approxTol tol) (expected, actual))

  (* Permutation-invariant comparison of two label vectors: two labellings are
     equivalent iff they induce the same partition of point indices, regardless
     of the actual id values. *)
  fun samePartition (a, b) =
    length a = length b
    andalso
    let
      (* For every pair of indices, "same cluster in a" must match "same cluster
         in b". O(n^2) but the test sets are tiny. *)
      val av = Vector.fromList a
      val bv = Vector.fromList b
      val n = Vector.length av
      fun loopI i =
        if i >= n then true
        else
          let
            fun loopJ j =
              if j >= n then true
              else
                let
                  val sameA = Vector.sub (av, i) = Vector.sub (av, j)
                  val sameB = Vector.sub (bv, i) = Vector.sub (bv, j)
                in
                  (sameA = sameB) andalso loopJ (j + 1)
                end
          in
            loopJ (i + 1) andalso loopI (i + 1)
          end
    in
      loopI 0
    end

  fun checkPartition name (expected, actual) =
    Harness.check name (samePartition (expected, actual))

  val seeded = SplitMix64.seed
end
