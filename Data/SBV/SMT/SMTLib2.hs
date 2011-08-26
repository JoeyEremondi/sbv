-----------------------------------------------------------------------------
-- |
-- Module      :  Data.SBV.SMT.SMTLib2
-- Copyright   :  (c) Levent Erkok
-- License     :  BSD3
-- Maintainer  :  erkokl@gmail.com
-- Stability   :  experimental
-- Portability :  portable
--
-- Conversion of symbolic programs to SMTLib format, Using v2 of the standard
-----------------------------------------------------------------------------
{-# LANGUAGE PatternGuards #-}

module Data.SBV.SMT.SMTLib2(cvt, addNonEqConstraints) where

import Data.List (intercalate)

import Data.SBV.BitVectors.Data

addNonEqConstraints :: [[(String, CW)]] -> SMTLibPgm -> String
addNonEqConstraints nonEqConstraints (SMTLibPgm _ (aliasTable, pre, post)) = intercalate "\n" $
     pre
  ++ [ "; --- refuted-models ---" ]
  ++ concatMap nonEqs (map (map intName) nonEqConstraints)
  ++ post
 where intName (s, c)
          | Just sw <- s `lookup` aliasTable = (show sw, c)
          | True                             = (s, c)

nonEqs :: [(String, CW)] -> [String]
nonEqs []     =  []
nonEqs [sc]   =  ["(assert " ++ nonEq sc ++ ")"]
nonEqs (sc:r) =  ["(assert (or " ++ nonEq sc]
              ++ map (("           " ++) . nonEq) r
              ++ ["        ))"]

nonEq :: (String, CW) -> String
nonEq (s, c) = "(not (= " ++ s ++ " " ++ cvtCW c ++ "))"

-- TODO: fix this
cvtCW :: CW -> String
cvtCW = show

cvt :: Bool                                        -- ^ is this a sat problem?
    -> [String]                                    -- ^ extra comments to place on top
    -> [(Quantifier, NamedSymVar)]                 -- ^ inputs and aliasing names
    -> [(SW, CW)]                                  -- ^ constants
    -> [((Int, (Bool, Int), (Bool, Int)), [SW])]   -- ^ auto-generated tables
    -> [(Int, ArrayInfo)]                          -- ^ user specified arrays
    -> [(String, SBVType)]                         -- ^ uninterpreted functions/constants
    -> [(String, [String])]                        -- ^ user given axioms
    -> Pgm                                         -- ^ assignments
    -> SW                                          -- ^ output variable
    -> ([String], [String])
cvt _isSat comments qinps _consts _tbls _arrs _uis _axs _asgnsSeq _out
  | not (needsExistentials (map fst qinps))
  = error "SBV: No existential variables present. Use prove/sat instead."
  | True
  = (pre, post ++ extractModel)
  where pre  = [ "; Automatically generated by SBV. Do not edit."
               , "(set-option :produce-models true)"
               ]
               ++ map ("; " ++) comments
               ++ topDecls
        post = [ "(assert (forall ((s2 (_ BitVec 16))) (bvuge (bvadd s2 s1) s0)))"
               ]
        topExists = takeWhile (\(q, _) -> q == EX) qinps
        topDecls  = ["(declare-fun " ++ show s ++ " () " ++ smtType s ++ ")" | (_, (s, _)) <- topExists]
        modelVals = [show s | (_, (s, _)) <- topExists]
        extractModel = "(check-sat)" : ["(get-value (" ++ v ++ "))" | v <- modelVals]

smtType :: SW -> String
smtType s = "(_ BitVec " ++ show (sizeOf s) ++ ")"
