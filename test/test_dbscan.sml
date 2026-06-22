(* test_dbscan.sml -- density-based clustering.

   Reference dataset (eps = 1.5, minPts = 3):

     cluster 0:  (0,0) (0,1) (1,0) (1,1)      -- a dense 2x2 square
     cluster 1:  (10,10) (10,11) (11,10)      -- a dense triangle far away
     noise:      (5,5)                        -- isolated, no neighbours

   Every square point has >= 3 neighbours within 1.5 (the diagonal is
   sqrt 2 ~ 1.414), so the square is one core cluster. Each triangle point has
   exactly 3 neighbours (itself + the two at distance 1), so it forms a second
   cluster. (5,5) has only itself within 1.5, so it is noise. Cluster ids are
   assigned in visit order, so the labelling is exact and deterministic. *)

structure DBSCANTests =
struct
  open Support
  structure C = Cluster

  val data =
    [ [0.0,0.0],[0.0,1.0],[1.0,0.0],[1.0,1.0]      (* square  *)
    , [10.0,10.0],[10.0,11.0],[11.0,10.0]          (* triangle *)
    , [5.0,5.0] ]                                  (* noise   *)

  fun run () =
    let
      val () = Harness.section "DBSCAN on two dense groups + one outlier"

      val { labels, nClusters } =
        C.dbscan { eps = 1.5, minPts = 3, data = data }

      val () = Harness.checkInt "found two clusters" (2, nClusters)
      val () = Harness.checkIntList "labels match the known partition"
                 ([0,0,0,0, 1,1,1, C.noise], labels)
      val () = Harness.checkInt "noise sentinel is ~1" (~1, C.noise)

      val () = Harness.section "DBSCAN: large eps merges everything"
      val { labels = l2, nClusters = nc2 } =
        C.dbscan { eps = 100.0, minPts = 1, data = data }
      val () = Harness.checkInt "single cluster with eps = 100" (1, nc2)
      val () = Harness.checkIntList "every point in cluster 0"
                 ([0,0,0,0,0,0,0,0], l2)

      val () = Harness.section "DBSCAN: tiny eps makes all points noise"
      val { labels = l3, nClusters = nc3 } =
        C.dbscan { eps = 0.1, minPts = 3, data = data }
      val () = Harness.checkInt "no clusters" (0, nc3)
      val () = Harness.checkIntList "all noise"
                 ([~1,~1,~1,~1,~1,~1,~1,~1], l3)

      val () = Harness.section "DBSCAN parameter validation"
      val () = Harness.checkRaises "empty data raises"
                 (fn () => C.dbscan { eps = 1.0, minPts = 1, data = [] })
      val () = Harness.checkRaises "minPts < 1 raises"
                 (fn () => C.dbscan { eps = 1.0, minPts = 0, data = data })
      val () = Harness.checkRaises "negative eps raises"
                 (fn () => C.dbscan { eps = ~1.0, minPts = 1, data = data })
    in
      ()
    end
end
