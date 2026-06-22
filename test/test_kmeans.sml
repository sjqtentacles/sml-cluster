(* test_kmeans.sml -- k-means with k-means++ seeding.

   Reference dataset: two well-separated 2-D blobs of five points each.

     Blob A (around the origin):  (0,0) (1,0) (0,1) (1,1) (0.5,0.5)
     Blob B (around (10,10)):     (10,10) (11,10) (10,11) (11,11) (10.5,10.5)

   With k = 2, k-means++ must place one centre per blob (the blobs are far
   apart, so the squared-distance seeding always splits them), and Lloyd's
   algorithm converges to the blob means:

     mean A = (0.5, 0.5),  mean B = (10.5, 10.5)

   Each blob contributes inertia 2.0 (four corner points at squared distance
   0.5 from the mean, the centre point at 0), so total inertia = 4.0 exactly.
   The centre/assignment labels are arbitrary up to permutation, so the
   partition is checked permutation-invariantly, and the seeding is checked for
   exact run-to-run reproducibility. *)

structure KMeansTests =
struct
  open Support
  structure C = Cluster

  val blobA = [[0.0,0.0],[1.0,0.0],[0.0,1.0],[1.0,1.0],[0.5,0.5]]
  val blobB = [[10.0,10.0],[11.0,10.0],[10.0,11.0],[11.0,11.0],[10.5,10.5]]
  val data = blobA @ blobB

  val meanA = [0.5, 0.5]
  val meanB = [10.5, 10.5]

  (* the expected partition: first five together, last five together *)
  val truthLabels = [0,0,0,0,0, 1,1,1,1,1]

  (* does the centroid set {c0,c1} match {meanA,meanB} in either order? *)
  fun centroidsMatch [c0, c1] =
        (pointApprox (c0, meanA) andalso pointApprox (c1, meanB))
        orelse
        (pointApprox (c0, meanB) andalso pointApprox (c1, meanA))
    | centroidsMatch _ = false

  fun run () =
    let
      val () = Harness.section "k-means on two well-separated blobs"

      val ({ centroids, assignments, inertia, iterations }, _) =
        C.kmeans { k = 2, maxIter = 100, data = data } (seeded 0w20260621)

      val () = Harness.checkInt "returns two centroids"
                 (2, List.length centroids)
      val () = Harness.checkInt "one assignment per point"
                 (10, List.length assignments)
      val () = checkPartition "assignments recover the two blobs"
                 (truthLabels, assignments)
      val () = Harness.check "centroids are the two blob means"
                 (centroidsMatch centroids)
      val () = checkApprox "inertia = 4.0" (4.0, inertia)
      val () = Harness.check "converged within the iteration budget"
                 (iterations < 100)

      val () = Harness.section "k-means++ is reproducible (fixed seed)"

      val ({ centroids = c1, assignments = a1, inertia = i1, ... }, _) =
        C.kmeans { k = 2, maxIter = 100, data = data } (seeded 0w12345)
      val ({ centroids = c2, assignments = a2, inertia = i2, ... }, _) =
        C.kmeans { k = 2, maxIter = 100, data = data } (seeded 0w12345)

      val () = Harness.checkIntList "same seed -> identical assignments"
                 (a1, a2)
      val () = checkApprox "same seed -> identical inertia" (i1, i2)
      val () = Harness.check "same seed -> identical centroids"
                 (ListPair.allEq pointApprox (c1, c2))

      val () = Harness.section "k-means parameter validation"
      val () = Harness.checkRaises "k <= 0 raises"
                 (fn () => C.kmeans { k = 0, maxIter = 10, data = data }
                              (seeded 0w1))
      val () = Harness.checkRaises "k > |data| raises"
                 (fn () => C.kmeans { k = 11, maxIter = 10, data = data }
                              (seeded 0w1))
      val () = Harness.checkRaises "empty data raises"
                 (fn () => C.kmeans { k = 2, maxIter = 10, data = [] }
                              (seeded 0w1))

      val () = Harness.section "k = 1 collapses to the global mean"
      val (r1, _) =
        C.kmeans { k = 1, maxIter = 50, data = data } (seeded 0w7)
      val g = hd (#centroids r1)
      val gi = #inertia r1
      (* global mean of all ten points = (5.5, 5.5) *)
      val () = checkPoint "centroid is the global mean" ([5.5, 5.5], g)
      val () = Harness.check "single-cluster inertia is positive" (gi > 0.0)
    in
      ()
    end
end
