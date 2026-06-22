(* demo.sml

   A deterministic tour of `sml-cluster`: k-means++ on three well-separated
   2-D blobs, the same data run through DBSCAN, and an agglomerative merge
   summary -- followed by an ASCII scatter coloured by k-means cluster id.

   Every number comes from a fixed dataset and a fixed SplitMix64 seed, so the
   output is byte-identical under MLton and Poly/ML. Build and run with
   `make example`. *)

structure C = Cluster

(* Real formatting that is byte-identical across compilers (fixed decimals;
   always a decimal point), with a leading "-" rather than SML's "~". *)
fun fmt k x = Real.fmt (StringCvt.FIX (SOME k)) x
fun fmtD k x =
  let val s = fmt k x
  in if String.isPrefix "~" s then "-" ^ String.extract (s, 1, NONE) else s end
fun line s = print (s ^ "\n")

(* ---- fixed dataset: three blobs of six points each ---- *)
val blob1 = [[7.0,4.0],[9.0,4.0],[7.0,6.0],[9.0,6.0],[8.0,5.0],[8.0,4.0]]
val blob2 = [[29.0,5.0],[31.0,5.0],[29.0,7.0],[31.0,7.0],[30.0,6.0],[30.0,5.0]]
val blob3 = [[17.0,15.0],[19.0,15.0],[17.0,17.0],[19.0,17.0],[18.0,16.0],[18.0,15.0]]
val data = blob1 @ blob2 @ blob3
val n = List.length data

val seed = 0w20260621 : Word64.word

val () = line "=== sml-cluster demo ========================================="
val () = line ""
val () = line ("Dataset: " ^ Int.toString n
               ^ " points in R^2, three blobs of six.")
val () = line ("Seed:    SplitMix64 0x20260621 (deterministic k-means++).")
val () = line ""

(* ---- k-means (k = 3) ---- *)
val ({ centroids, assignments, inertia, iterations }, _) =
  C.kmeans { k = 3, maxIter = 100, data = data } (SplitMix64.seed seed)

fun ptStr p = "(" ^ String.concatWith ", " (List.map (fmtD 2) p) ^ ")"

val sizes =
  List.tabulate
    (List.length centroids,
     fn c => List.length (List.filter (fn a => a = c) assignments))

val () = line "k-means (k = 3, k-means++ seeding, Lloyd to convergence)"
val () = line ("  iterations = " ^ Int.toString iterations)
val () = line ("  inertia    = " ^ fmtD 4 inertia)
val () =
  List.app
    (fn c =>
       line ("  cluster " ^ Int.toString c ^ ": centroid "
             ^ ptStr (List.nth (centroids, c))
             ^ "  size " ^ Int.toString (List.nth (sizes, c))))
    (List.tabulate (List.length centroids, fn c => c))
val () = line ""

(* ---- DBSCAN on the same data ---- *)
val { labels, nClusters } =
  C.dbscan { eps = 3.0, minPts = 2, data = data }
val noiseCount = List.length (List.filter (fn l => l = C.noise) labels)
val () = line "DBSCAN (eps = 3.0, minPts = 2)"
val () = line ("  clusters found = " ^ Int.toString nClusters
               ^ "   noise points = " ^ Int.toString noiseCount)
val () = line ""

(* ---- hierarchical (single linkage) ---- *)
val merges = C.hierarchical { linkage = C.Single, data = data }
val lastMerge = List.last merges
val () = line "Hierarchical agglomerative (single linkage)"
val () = line ("  merges       = " ^ Int.toString (List.length merges))
val () = line ("  final merge  : clusters " ^ Int.toString (#left lastMerge)
               ^ " + " ^ Int.toString (#right lastMerge)
               ^ " at distance " ^ fmtD 4 (#dist lastMerge)
               ^ " (size " ^ Int.toString (#size lastMerge) ^ ")")
val () = line ""

(* ---- ASCII scatter, coloured by k-means cluster id ---- *)
val gw = 52 and gh = 19
val xs = List.map (fn p => List.nth (p, 0)) data
val ys = List.map (fn p => List.nth (p, 1)) data
val minX = List.foldl Real.min (hd xs) xs
val maxX = List.foldl Real.max (hd xs) xs
val minY = List.foldl Real.min (hd ys) ys
val maxY = List.foldl Real.max (hd ys) ys

fun col x = Real.round ((x - minX) / (maxX - minX) * real (gw - 1))
fun row y = Real.round ((maxY - y) / (maxY - minY) * real (gh - 1))

val grid = Array.array (gh * gw, #".")
val () =
  ListPair.appEq
    (fn (p, a) =>
       let
         val x = List.nth (p, 0)
         val y = List.nth (p, 1)
         val r = row y and cc = col x
         val ch = Char.chr (Char.ord #"0" + a)
       in
         if r >= 0 andalso r < gh andalso cc >= 0 andalso cc < gw
         then Array.update (grid, r * gw + cc, ch) else ()
       end)
    (data, assignments)

val () = line "ASCII scatter (digit = k-means cluster id)"
val () = line ("  x in [" ^ fmtD 1 minX ^ ", " ^ fmtD 1 maxX
               ^ "],  y in [" ^ fmtD 1 minY ^ ", " ^ fmtD 1 maxY ^ "]")
val () = line ""
fun emitRow r =
  let val s = CharVector.tabulate (gw, fn c => Array.sub (grid, r * gw + c))
  in line ("  " ^ s) end
val () = List.app emitRow (List.tabulate (gh, fn r => r))
val () = line ""
val () = line "============================================================="
