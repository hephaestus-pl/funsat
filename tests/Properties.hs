{-# OPTIONS_GHC -fglasgow-exts #-}
module Properties where

{-
    This file is part of DPLLSat.

    DPLLSat is free software: you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    DPLLSat is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Lesser General Public License for more details.

    You should have received a copy of the GNU Lesser General Public License
    along with DPLLSat.  If not, see <http://www.gnu.org/licenses/>.

    Copyright 2008 Denis Bueno
-}

import DPLLSat hiding ( (==>) )

import Control.Monad (replicateM, liftM)
import Data.Array.Unboxed
import Data.BitSet (hash)
import Data.Bits
import Data.Foldable hiding (sequence_)
import Data.List (nub, splitAt, unfoldr, delete, sort)
import Data.Maybe
import Debug.Trace
import Prelude hiding ( or, and, all, any, elem, minimum, foldr, splitAt, concatMap
                      , sum, concat )
import System.Random
import Test.QuickCheck hiding (defaultConfig)
import qualified Data.Foldable as Foldable
import qualified Data.List as List
import qualified Data.Set as Set
import qualified Data.Heap.Finger as H
import qualified Test.QuickCheck as QC

main :: IO ()
main = do
--   let s = solve1 prob1
--   case s of
--     Unsat -> return ()
--     Sat m -> if not (verify m prob1)
--              then putStrLn (show (find (`isFalseUnder` m) prob1))
--              else return ()

      --setStdGen (mkStdGen 42)
      check config prop_heap_member_out
      check config prop_heap_member
      check config prop_heap_extract_max
      check config prop_randAssign
      check config prop_allIsTrueUnderA
      check config prop_noneIsFalseUnderA
      check config prop_noneIsUndefUnderA
      check config prop_negIsFalseUnder
      check config prop_negNotUndefUnder
      check config prop_outsideUndefUnder
      check config prop_clauseStatusUnderA
      check config prop_negDefNotUndefUnder
      check config prop_undefUnderImpliesNegUndef
      check config prop_litHash
      check config prop_varHash

      -- Add more tests above here.  Setting the rng keeps the SAT instances
      -- the same even if more tests are added above.  Reproducible results
      -- are important.
      setStdGen (mkStdGen 42)
      check solveConfig prop_solveCorrect

config = QC.defaultConfig { configMaxTest = 1000 }

-- Special configuration for the "solve this random instance" tests.
solveConfig = QC.defaultConfig { configMaxTest = 2000 }

myConfigEvery testnum args = show testnum ++ ": " ++ show args ++ "\n\n"

-- * Tests
prop_solveCorrect (cnf :: CNF) =
    label "prop_solveCorrect" $
    trivial (numClauses cnf < 2 || numVars cnf < 2) $
    classify (numClauses cnf > 15 || numVars cnf > 10) "c>15, v>10" $
    classify (numClauses cnf > 30 || numVars cnf > 20) "c>30, v>20" $
    classify (numVars cnf > 20) "c>30, v>30" $
    case solve (defaultConfig cnf) (mkStdGen 1) cnf of
      Sat m -> label "SAT" $ verify m cnf
      Unsat -> label "UNSAT-unverified" $ True


prop_allIsTrueUnderA (m :: IAssignment) =
    label "prop_allIsTrueUnderA"$
    allA (\i -> if i /= 0 then L i `isTrueUnder` m else True) m

prop_noneIsFalseUnderA (m :: IAssignment) =
    label "prop_noneIsFalseUnderA"$
    not $ anyA (\i -> if i /= 0 then L i `isFalseUnder` m else False) m

prop_noneIsUndefUnderA (m :: IAssignment) =
    label "prop_noneIsUndefUnderA"$
    not $ anyA (\i -> if i /= 0 then L i `isUndefUnder` m else False) m

prop_negIsFalseUnder (m :: IAssignment) =
    label "prop_negIsFalseUnder"$
    allA (\l -> if l /= 0 then negate (L l) `isFalseUnder` m else True) m

prop_negNotUndefUnder (m :: IAssignment) =
    label "prop_negNotUndefUnder"$
    allA (\l -> if l /= 0 then not (negate (L l) `isUndefUnder` m) else True) m

prop_outsideUndefUnder (l :: Lit) (m :: IAssignment) =
    label "prop_outsideUndefUnder"$
    trivial ((unVar . var) l > rangeSize (bounds m)) $
    inRange (bounds m) (var l) ==>
    trivial (m `contains` l || m `contains` negate l) $
    not (m `contains` l) && not (m `contains` (negate l)) ==>
    l `isUndefUnder` m

prop_negDefNotUndefUnder (l :: Lit) (m :: IAssignment) =
    label "prop_negDefNotUndefUnder" $
    inRange (bounds m) (var l) ==>
    m `contains` l || m `contains` (negate l) ==>
    l `isTrueUnder` m || negate l `isTrueUnder` m

prop_undefUnderImpliesNegUndef (l :: Lit) (m :: IAssignment) =
    label "prop_undefUnderImpliesNegUndef" $
    inRange (bounds m) (var l) ==>
    trivial (m `contains` l) $
    l `isUndefUnder` m ==> negate l `isUndefUnder` m
    

prop_clauseStatusUnderA (c :: Clause) (m :: IAssignment) =
    label "prop_clauseStatusUnderA" $
    classify expectTrueTest "expectTrue"$
    classify expectFalseTest "expectFalseTest"$
    classify expectUndefTest "expectUndefTest"$
    if expectTrueTest then c `isTrueUnder` m
    else if expectFalseTest then c `isFalseUnder` m
    else c `isUndefUnder` m
        where
          expectTrueTest = not . null $ c `List.intersect` (map L $ elems m)
          expectFalseTest = all (`isFalseUnder` m) c
          expectUndefTest = not expectTrueTest && not expectFalseTest

-- Verify assignments generated are sane, i.e. no assignment contains an
-- element and its negation.
prop_randAssign (a :: IAssignment) =
    label "randAssign"$
    not $ anyA (\l -> if l /= 0 then a `contains` (negate $ L l) else False) a

-- unitPropFar should stop only if it can't propagate anymore.
-- prop_unitPropFarthest (m :: Assignment) (cnf :: CNF) =
--     label "prop_unitPropFarthest"$
--     case unitPropFar m cnf of
--       Nothing -> label "no propagation" True
--       Just m' -> label "propagated" $ not (anyUnit m' cnf)

-- Unit propagation may only add to the given assignment.
-- prop_unitPropOnlyAdds (m :: Assignment) (cnf :: CNF) =
--     label "prop_unitPropOnlyAdds"$
--     case unitPropFar m cnf of
--       Nothing -> label "no propagation" True
--       Just m' -> label "propagated" $ all (\l -> elem l m') m

-- Make sure the bit set will work.

prop_litHash (k :: Lit) (l :: Lit) =
    label "prop_litHash" $
    hash k == hash l <==> k == l

prop_varHash (k :: Var) l =
    label "prop_varHash" $
    hash k == hash l <==> k == l


(<==>) = iff
infixl 3 <==>

-- ** Max heap

newtype Nat = Nat { unNat :: Int }
    deriving (Eq, Show, Ord)
instance Num Nat where
    (Nat x) + (Nat y) = Nat (x + y)
    (Nat x) - (Nat y) | x >= y = Nat (x - y)
                      | x < y  = error "Nat: subtraction out of range"
    (Nat x) * (Nat y) = Nat (x * y)
    abs = id
    signum (Nat n) | n == 0 = 0
                   | n > 0  = 1
                   | n < 0  = error "Nat: signum of negative number"
    fromInteger n | n >= 0 = Nat (fromInteger n)
                  | n < 0  = error "Negative natural literal found"

instance Arbitrary Nat where
    arbitrary = sized $ \n -> do i <- choose (0, n)
                                 return (fromIntegral i)

newtype TestHeap = HT { theHeap :: H.Heap Nat Nat }
    deriving Show

emptyNatHeap :: TestHeap
emptyNatHeap = HT H.empty

-- sanity checking for Arbitrary Nat instance.
prop_nat (xs :: [Nat]) = trivial (null xs) $ sum xs >= 0
prop_nat1 (xs :: [Nat]) = trivial (null xs) $ unNat (sum xs) == sum (map unNat xs)

instance Arbitrary (H.Info Nat Nat) where
    arbitrary = do n <- arbitrary
                   return (H.Info { H.key = n, H.datum = n })

instance Arbitrary TestHeap where
    arbitrary = sized $ \n ->
                do xs <- vector n
                   return $ HT (foldl' (flip H.insert) H.empty xs)

prop_heap_member_out x (xsIn :: [H.Info Nat Nat]) =
    label "prop_heap_member_out" $
    (x `H.member` heap) `iff` (x `elem` xs)
  where heap = H.fromList xs
        xs = nub xsIn 

prop_heap_member (xsIn :: [H.Info Nat Nat]) =
    label "prop_heap_member" $
    all (\y -> y `H.member` heap) xs
  where heap = H.fromList xs
        xs   = nub xsIn

prop_heap_extract_max (xsIn :: [H.Info Nat Nat]) =
    label "prop_heap_extract_max" $
    trivial (null xs) $
    sort xs == maxs
  where (maxs, _) =
            foldl' (\ (xs, h) _ -> let (x, h') = H.extractMax h
                                   in (x : xs, h'))
            ([], heap) xs
        heap = H.fromList xs
        xs = nub xsIn

-- * Helpers



allA :: (IArray a e, Ix i) => (e -> Bool) -> a i e -> Bool
allA p a = all (p . (a !)) (range . bounds $ a)

anyA :: (IArray a e, Ix i) => (e -> Bool) -> a i e -> Bool
anyA p a = any (p . (a !)) (range . bounds $ a)

_findA :: (IArray a e, Ix i) => (e -> Bool) -> a i e -> Maybe e
_findA p a = (a !) `fmap` find (p . (a !)) (range . bounds $ a)


-- Generate exactly n distinct, random things from given enum, starting at
-- element given.  Obviously only really works for infinite enumerations.
_uniqElts :: (Enum a) => Int -> a -> Gen [a]
_uniqElts n x =
    do is <- return [x..]
       choices <-
           sequence $ map
                      (\i -> do {b <- oneof [return True, return False];
                                 return $ if b then Just i else Nothing})
                      is
       return $ take n $ catMaybes choices

-- Send this as a patch for quickcheck, maybe.
iff :: Bool -> Bool -> Property
first `iff` second =
    classify first "first" $
    classify (not first) "not first" $
    classify second "second" $
    classify (not second) "not second" $
    if first then second
    else not second
    && if second then first
       else not first


fromRight (Right x) = x
fromRight (Left _) = error "fromRight: Left"


_intAssignment :: Int -> Integer -> [Lit]
_intAssignment n i = map nthBitLit [0..n-1]
    -- nth bit of i as a literal
    where nthBitLit n = toLit (n + 1) $ i `testBit` n
          toLit n True  = L n
          toLit n False = negate $ L n
                         


_powerset       :: [a] -> [[a]]
_powerset []     = [[]]
_powerset (x:xs) = xss /\/ map (x:) xss
    where
      xss = _powerset xs

      (/\/)        :: [a] -> [a] -> [a]
      []     /\/ ys = ys
      (x:xs) /\/ ys = x : (ys /\/ xs)


-- * Generators

instance Arbitrary Var where
    arbitrary = sized $ \n -> V `fmap` choose (1, n)
instance Arbitrary Lit where
    arbitrary = sized $ sizedLit

-- Generates assignment that never has a subset {l, -l}.
instance Arbitrary IAssignment where
    arbitrary = sized $ assign'
        where 
          assign' n = do lits :: [Lit] <- vector n
                         return $ array (V 1, V n) $ map (\i -> (var i, unLit i))
                                                     (nub lits)

instance Arbitrary CNF where
    arbitrary = sized genRandom3SAT

sizedLit n = do
  v <- choose (1, n)
  t <- oneof [return id, return negate]
  return $ L (t v)

genRandom3SAT :: Int -> Gen CNF
genRandom3SAT n =
    do let clausesPerVar = 3.0
           nClauses = ceiling (fromIntegral nVars * clausesPerVar)
       clauseList <- replicateM nClauses arbClause
       return $ CNF { numVars    = nVars
                    , numClauses = nClauses
                    , clauses    = Set.fromList clauseList }
  where 
    nVars = n `div` 3
    arbClause :: Gen Clause
    arbClause = do
      a <- sizedLit nVars
      b <- sizedLit nVars
      c <- sizedLit nVars
      return [a,b,c]


genCNF2 n = gen (fromIntegral n)
      where
        gen n =
            let _g = n `div` 4
                lits :: [Lit] = map L [1..n]
                genClause1 [a,b,c,d] =
                    map (map negate) [[a,b,c], [a,b,d], [a,c,d], [b,c,d]]
                genClause1 _ = error "genClause1: bad arg"
                genClause2 [a,b,c,d] = [[a,b,c], [a,b,d], [a,c,d], [b,c,c]]
                genClause2 _ = error "genClause2: bad arg"
                _genUnsat [a,b,c,d,e] =
                    map (map negate)
                    [[a,b,c,d]
                    ,[a,b,c,e]
                    ,[a,b,d,e]
                    ,[a,c,d, negate e]
                    ,[b,c,d, negate e]]
                _genUnsat _ = error "genUnsat: bad arg"
            in do groups1 <- return $ concatMap genClause1 $ windows 4 lits
                  lits'   <- permute lits
                  groups2 <- return $ concatMap genClause2 $ windows 4 lits'
                  return $
                    CNF {numVars = n
                        ,numClauses = length groups1 + length groups1
                        ,clauses = Set.fromList $ groups1 ++ groups2}

windows :: Int -> [a] -> [[a]]
windows n xs = if length xs < n
               then []
               else take n xs : windows n (drop n xs)

permute :: [a] -> Gen [a]
permute [] = return []
permute xs = choose (0, length xs - 1) >>= \idx ->
             case splitAt idx xs of
               (pfx, x:xs') -> do perm <- permute $ pfx ++ xs'
                                  return $ x : perm
               _            -> error "permute: bug"


-- ** Simplification

class WellFoundedSimplifier a where
    -- | If the argument can be made simpler, a list of one-step simpler
    -- objects.  Only in cases where there are multiple "dimensions" to
    -- simplify should the returned list have length more than 1.  Otherwise
    -- returns the empty list.
    simplify :: a -> [a]

instance WellFoundedSimplifier a => WellFoundedSimplifier [a] where
    simplify []     = []
    simplify (x:xs) = case simplify x of
                        [] -> [xs]
                        x's-> map (:xs) x's

instance WellFoundedSimplifier () where
    simplify () = []

instance WellFoundedSimplifier Bool where
    simplify True = [False]
    simplify False = []

instance WellFoundedSimplifier Int where
  simplify i | i == 0 = []
             | i > 0  = [i-1]
             | i < 0  = [i+1]

-- Assign the highest variable and reduce the number of variables.
instance WellFoundedSimplifier CNF where
    simplify f
        | numVars f <= 1 = []
        | numVars f > 1 = [ f{ numVars    = numVars f - 1
                             , clauses    = clauses'
                             , numClauses = Set.size clauses' }
--                           , f{ clauses    = Set.deleteMax (clauses f)
--                              , numClauses = numClauses f - 1 }
                          ]
      where
        clauses' = foldl' assignVar Set.empty (clauses f)
        pos = L (numVars f)
        neg = negate pos
        assignVar outClauses clause =
            let clause' = neg `delete` clause
            in if pos `elem` clause || null clause' then outClauses
               else clause' `Set.insert` outClauses


simplifications :: WellFoundedSimplifier a => a -> [a]
simplifications a = concat $ unfoldr (\ xs -> let r = concatMap simplify xs
                                              in if null r then Nothing
                                                 else Just (r, r))
                                     [a]

-- Returns smallest CNF simplification that also gives erroneous output.
minimalError :: CNF -> CNF
minimalError f = lastST f satAndWrong (simplifications f)
    where satAndWrong f_inner =
              trace (show (numVars f_inner) ++ "/" ++ show (numClauses f_inner)) $
              case solve1 f_inner of
                Unsat          -> False
                Sat assignment -> not (verify assignment f_inner)

-- last (takeWhile p xs) in the common case.
-- mnemonic: "last Such That"
lastST def _ []     = def
lastST def p (x:xs) = if p x then lastST x p xs else def

prop_lastST (x :: Int) =
    if not (null xs) && xa > 3 then
        classify True "nontrivial" $
        last (takeWhile p xs) == lastST undefined p xs
    else True `trivial` True
  where p  = (> xa `div` 2)
        xs = simplifications xa
        xa = abs x


getCNF :: Int -> IO CNF
getCNF maxVars = do g <- newStdGen
                    return (generate (maxVars * 3) g arbitrary)

