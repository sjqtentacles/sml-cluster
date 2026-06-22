(* test_hierarchical.sml -- agglomerative clustering and its dendrogram.

   Reference dataset: four colinear points
     p0 = (0,0)  p1 = (1,0)  p2 = (4,0)  p3 = (5,0)
   so the pairwise distances are
     d01 = 1  d23 = 1  d12 = 3  d02 = 4  d13 = 4  d03 = 5.

   Singletons carry ids 0..3; each merge yields the next id (4, 5, ...).
   The two unit-distance pairs (0,1) and (2,3) merge first; ties break toward
   the lowest (left,right) id pair, so (0,1) -> id 4 precedes (2,3) -> id 5.
   The final merge joins 4 and 5; its distance depends on the linkage:

     single   : min cross distance d12 = 3
     complete : max cross distance d03 = 5
     average  : mean of {d02,d03,d12,d13} = (4+5+3+4)/4 = 4 *)

structure HierarchicalTests =
struct
  open Support
  structure C = Cluster

  val data = [[0.0,0.0],[1.0,0.0],[4.0,0.0],[5.0,0.0]]

  fun checkMerge name (exp : C.merge, act : C.merge) =
    Harness.check name
      (#left exp = #left act
       andalso #right exp = #right act
       andalso #size exp = #size act
       andalso approx (#dist exp, #dist act))

  fun run () =
    let
      val () = Harness.section "single linkage dendrogram"
      val s = C.hierarchical { linkage = C.Single, data = data }
      val () = Harness.checkInt "produces n-1 = 3 merges" (3, List.length s)
      val () = checkMerge "merge 1: (0,1) at d = 1"
                 ({left=0,right=1,dist=1.0,size=2}, List.nth (s, 0))
      val () = checkMerge "merge 2: (2,3) at d = 1"
                 ({left=2,right=3,dist=1.0,size=2}, List.nth (s, 1))
      val () = checkMerge "merge 3: (4,5) at single d = 3"
                 ({left=4,right=5,dist=3.0,size=4}, List.nth (s, 2))

      val () = Harness.section "complete linkage dendrogram"
      val c = C.hierarchical { linkage = C.Complete, data = data }
      val () = checkMerge "merge 1: (0,1) at d = 1"
                 ({left=0,right=1,dist=1.0,size=2}, List.nth (c, 0))
      val () = checkMerge "merge 2: (2,3) at d = 1"
                 ({left=2,right=3,dist=1.0,size=2}, List.nth (c, 1))
      val () = checkMerge "merge 3: (4,5) at complete d = 5"
                 ({left=4,right=5,dist=5.0,size=4}, List.nth (c, 2))

      val () = Harness.section "average linkage dendrogram"
      val a = C.hierarchical { linkage = C.Average, data = data }
      val () = checkMerge "merge 1: (0,1) at d = 1"
                 ({left=0,right=1,dist=1.0,size=2}, List.nth (a, 0))
      val () = checkMerge "merge 2: (2,3) at d = 1"
                 ({left=2,right=3,dist=1.0,size=2}, List.nth (a, 1))
      val () = checkMerge "merge 3: (4,5) at average d = 4"
                 ({left=4,right=5,dist=4.0,size=4}, List.nth (a, 2))

      val () = Harness.section "hierarchical edge cases"
      val () = Harness.checkRaises "empty data raises"
                 (fn () => C.hierarchical { linkage = C.Single, data = [] })
      val () = Harness.checkInt "singleton set yields no merges"
                 (0, List.length
                       (C.hierarchical { linkage = C.Single,
                                         data = [[1.0,2.0]] }))
    in
      ()
    end
end
