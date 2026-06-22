(* cluster.sml

   Implementation of CLUSTER as a functor over a `sml-prng` RANDOM generator.
   The randomness (k-means++ seeding) is fully injected: `kmeans` threads the
   generator state, so the same seed reproduces the same clustering on MLton and
   Poly/ML. DBSCAN and hierarchical clustering use no randomness at all. *)

functor ClusterFn (R : RANDOM) :> CLUSTER where type rng = R.state =
struct
  type rng = R.state
  type point = real list

  exception Empty
  exception Dim of string

  (* ---- distances ---- *)

  fun euclideanSq (a, b) =
    let
      fun loop ([], [], acc) = acc
        | loop (x :: xs, y :: ys, acc) =
            let val d = x - y in loop (xs, ys, acc + d * d) end
        | loop _ = raise Dim "euclideanSq: dimension mismatch"
    in
      loop (a, b, 0.0)
    end

  fun euclidean (a, b) = Math.sqrt (euclideanSq (a, b))

  (* Check that every point shares the head's dimension; return (vector, dim). *)
  fun checkData data =
    case data of
      [] => raise Empty
    | p0 :: _ =>
        let
          val d = List.length p0
          val () =
            List.app
              (fn p => if List.length p = d then ()
                       else raise Dim "points have differing dimensions")
              data
        in
          (Vector.fromList data, d)
        end

  (* ---- centroid helpers (work on real lists of equal length) ---- *)

  fun addInto (acc, p) =
    ListPair.mapEq (fn (a, x) => a + x) (acc, p)

  fun scaleVec (s, p) = List.map (fn x => x * s) p

  fun zeroVec d = List.tabulate (d, fn _ => 0.0)

  (* index of the nearest centroid to p (ties -> lowest index), with its
     squared distance. *)
  fun nearest (centroids, p) =
    let
      fun loop ([], _, bestI, bestD) = (bestI, bestD)
        | loop (c :: cs, i, bestI, bestD) =
            let val d = euclideanSq (p, c)
            in if d < bestD then loop (cs, i + 1, i, d)
               else loop (cs, i + 1, bestI, bestD)
            end
    in
      case centroids of
        [] => raise Dim "nearest: no centroids"
      | c0 :: cs => loop (cs, 1, 0, euclideanSq (p, c0))
    end

  (* ---- k-means ---- *)

  type kmeansResult =
    { centroids : point list
    , assignments : int list
    , inertia : real
    , iterations : int
    }

  (* k-means++ seeding: first centre uniform; each subsequent centre drawn with
     probability proportional to D(x)^2, the squared distance to the nearest
     centre chosen so far. Deterministic given the generator state. *)
  fun kmeansppInit (pts, k, s0) =
    let
      val n = Vector.length pts
      val (i0, s1) = R.intRange (0, n - 1) s0
      val c0 = Vector.sub (pts, i0)

      (* choose the remaining k-1 centres *)
      fun pickMore (chosen, count, s) =
        if count >= k then (List.rev chosen, s)
        else
          let
            (* D2 i = squared distance of point i to the nearest chosen centre *)
            fun d2 i =
              let
                fun best ([], acc) = acc
                  | best (c :: cs, acc) =
                      let val d = euclideanSq (Vector.sub (pts, i), c)
                      in best (cs, if d < acc then d else acc) end
              in
                case chosen of
                  [] => 0.0
                | c :: cs => best (cs, euclideanSq (Vector.sub (pts, i), c))
              end
            val weights = Vector.tabulate (n, d2)
            val total = Vector.foldl (op +) 0.0 weights
            val (u, s') = R.real01 s
          in
            if total <= 0.0 then
              (* All remaining points coincide with already-chosen centres
                 (D^2 = 0 everywhere): the data has fewer than k distinct
                 points. Repeat the lowest-index point deterministically; the
                 generator state is still advanced so callers see a stable
                 successor state. *)
              pickMore (Vector.sub (pts, 0) :: chosen, count + 1, s')
            else
              let
                val target = u * total
                (* walk the cumulative weights; pick the first index whose
                   cumulative sum exceeds target. *)
                fun walk (i, cum) =
                  if i >= n - 1 then n - 1
                  else
                    let val cum' = cum + Vector.sub (weights, i)
                    in if cum' > target then i else walk (i + 1, cum') end
                val idx = walk (0, 0.0)
              in
                pickMore (Vector.sub (pts, idx) :: chosen, count + 1, s')
              end
          end
    in
      pickMore ([c0], 1, s1)
    end

  (* assign every point to its nearest centroid; return (assignment array,
     inertia). *)
  fun assignAll (pts, centroids) =
    let
      val n = Vector.length pts
      val asg = Array.array (n, 0)
      fun loop (i, inertia) =
        if i >= n then inertia
        else
          let val (ci, d) = nearest (centroids, Vector.sub (pts, i))
          in Array.update (asg, i, ci); loop (i + 1, inertia + d) end
      val inertia = loop (0, 0.0)
    in
      (asg, inertia)
    end

  (* recompute centroids as the mean of assigned points; empty clusters keep
     their old centroid. *)
  fun recompute (pts, asg, oldCentroids, k, d) =
    let
      val n = Vector.length pts
      val sums = Array.array (k, zeroVec d)
      val counts = Array.array (k, 0)
      fun acc i =
        if i >= n then ()
        else
          let val c = Array.sub (asg, i)
          in Array.update (sums, c, addInto (Array.sub (sums, c), Vector.sub (pts, i)));
             Array.update (counts, c, Array.sub (counts, c) + 1);
             acc (i + 1)
          end
      val () = acc 0
      val oldVec = Vector.fromList oldCentroids
    in
      List.tabulate
        (k, fn c =>
              let val cnt = Array.sub (counts, c)
              in if cnt = 0 then Vector.sub (oldVec, c)
                 else scaleVec (1.0 / real cnt, Array.sub (sums, c))
              end)
    end

  fun arrayToList a = Array.foldr (op ::) [] a

  fun kmeans { k, maxIter, data } s0 =
    let
      val (pts, d) = checkData data
      val n = Vector.length pts
      val () = if k <= 0 then raise Dim "kmeans: k must be positive" else ()
      val () = if k > n then raise Dim "kmeans: k exceeds number of points" else ()
      val (init, s1) = kmeansppInit (pts, k, s0)

      fun iterate (centroids, prevAsg, iter) =
        let
          val (asg, inertia) = assignAll (pts, centroids)
          val asgList = arrayToList asg
          val changed =
            case prevAsg of
              NONE => true
            | SOME prev => prev <> asgList
        in
          if not changed orelse iter >= maxIter then
            { centroids = centroids
            , assignments = asgList
            , inertia = inertia
            , iterations = iter
            }
          else
            let val centroids' = recompute (pts, asg, centroids, k, d)
            in iterate (centroids', SOME asgList, iter + 1) end
        end

      val result = iterate (init, NONE, 0)
    in
      (result, s1)
    end

  (* ---- DBSCAN ---- *)

  val noise = ~1

  type dbscanResult = { labels : int list, nClusters : int }

  fun dbscan { eps, minPts, data } =
    let
      val (pts, _) = checkData data
      val n = Vector.length pts
      val () = if minPts < 1 then raise Dim "dbscan: minPts must be >= 1" else ()
      val () = if eps < 0.0 then raise Dim "dbscan: eps must be >= 0" else ()

      val UNVISITED = ~2
      val labels = Array.array (n, UNVISITED)

      (* indices within eps of point i, in increasing order (includes i). *)
      fun neighbours i =
        let
          val pi = Vector.sub (pts, i)
          fun loop (j, acc) =
            if j < 0 then acc
            else
              let val acc' = if euclidean (pi, Vector.sub (pts, j)) <= eps
                             then j :: acc else acc
              in loop (j - 1, acc') end
        in
          loop (n - 1, [])
        end

      (* deterministic FIFO seed set with membership guard *)
      val inSeed = Array.array (n, false)
      val buf = Array.array (n, 0)
      val head = ref 0
      val tail = ref 0
      fun resetSeed () =
        (head := 0; tail := 0; Array.modify (fn _ => false) inSeed)
      fun push i =
        if Array.sub (inSeed, i) then ()
        else (Array.update (inSeed, i, true);
              Array.update (buf, !tail, i);
              tail := !tail + 1)
      fun empty () = !head >= !tail
      fun pop () = let val i = Array.sub (buf, !head) in head := !head + 1; i end

      val nextId = ref 0

      fun expand cid =
        if empty () then ()
        else
          let val q = pop ()
              val lq = Array.sub (labels, q)
          in
            if lq = noise then (Array.update (labels, q, cid); expand cid)
            else if lq <> UNVISITED then expand cid
            else
              let
                val () = Array.update (labels, q, cid)
                val nb = neighbours q
              in
                if List.length nb >= minPts
                then List.app push nb
                else ();
                expand cid
              end
          end

      fun visit i =
        if Array.sub (labels, i) <> UNVISITED then ()
        else
          let val nb = neighbours i
          in
            if List.length nb < minPts then Array.update (labels, i, noise)
            else
              let val cid = !nextId
              in
                nextId := !nextId + 1;
                Array.update (labels, i, cid);
                resetSeed ();
                List.app (fn j => if j <> i then push j else ()) nb;
                expand cid
              end
          end

      fun loop i = if i >= n then () else (visit i; loop (i + 1))
      val () = loop 0
    in
      { labels = arrayToList labels, nClusters = !nextId }
    end

  (* ---- hierarchical agglomerative clustering ---- *)

  datatype linkage = Single | Complete | Average

  type merge = { left : int, right : int, dist : real, size : int }

  fun hierarchical { linkage, data } =
    let
      val (pts, _) = checkData data
      val n = Vector.length pts

      (* linkage distance between two clusters given their member index lists *)
      fun clusterDist (msA, msB) =
        let
          (* fold over all cross pairs *)
          fun pairs () =
            List.concat
              (List.map (fn a => List.map (fn b => euclidean
                          (Vector.sub (pts, a), Vector.sub (pts, b))) msB) msA)
        in
          case linkage of
            Single =>
              List.foldl Real.min Real.posInf (pairs ())
          | Complete =>
              List.foldl Real.max Real.negInf (pairs ())
          | Average =>
              let val ds = pairs ()
              in List.foldl (op +) 0.0 ds / real (List.length ds) end
        end

      (* active clusters: (id, members). singletons get ids 0..n-1. *)
      val initial = List.tabulate (n, fn i => (i, [i]))
      val nextId = ref n

      (* find the (lowest-id-pair) closest pair; returns (idA,msA,idB,msB,dist) *)
      fun closest clusters =
        let
          fun overPairs ([], best) = best
            | overPairs ((idA, msA) :: rest, best) =
                let
                  fun inner ([], best) = best
                    | inner ((idB, msB) :: more, best) =
                        let val d = clusterDist (msA, msB)
                            val better =
                              case best of
                                NONE => true
                              | SOME (_, _, _, _, bd) => d < bd
                        in inner (more, if better
                                        then SOME (idA, msA, idB, msB, d)
                                        else best)
                        end
                in overPairs (rest, inner (rest, best)) end
        in
          overPairs (clusters, NONE)
        end

      fun run (clusters, acc) =
        if List.length clusters <= 1 then List.rev acc
        else
          case closest clusters of
            NONE => List.rev acc
          | SOME (idA, msA, idB, msB, d) =>
              let
                val newId = !nextId
                val () = nextId := !nextId + 1
                val members = msA @ msB
                val left = Int.min (idA, idB)
                val right = Int.max (idA, idB)
                val m = { left = left, right = right, dist = d
                        , size = List.length members }
                val remaining =
                  List.filter (fn (id, _) => id <> idA andalso id <> idB)
                              clusters
              in
                run (remaining @ [(newId, members)], m :: acc)
              end
    in
      if n <= 1 then [] else run (initial, [])
    end
end

(* Default instantiation: SplitMix64-backed clustering. *)
structure Cluster = ClusterFn (SplitMix64)
