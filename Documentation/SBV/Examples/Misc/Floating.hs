-----------------------------------------------------------------------------
-- |
-- Module    : Documentation.SBV.Examples.Misc.Floating
-- Copyright : (c) Levent Erkok
-- License   : BSD3
-- Maintainer: erkokl@gmail.com
-- Stability : experimental
--
-- Several examples involving IEEE-754 floating point numbers, i.e., single
-- precision 'Float' ('SFloat') and double precision 'Double' ('SDouble') types.
--
-- Note that arithmetic with floating point is full of surprises; due to precision
-- issues associativity of arithmetic operations typically do not hold. Also,
-- the presence of @NaN@ is always something to look out for.
-----------------------------------------------------------------------------

{-# LANGUAGE ScopedTypeVariables #-}

module Documentation.SBV.Examples.Misc.Floating where

import Data.SBV

-----------------------------------------------------------------------------
-- * FP addition is not associative
-----------------------------------------------------------------------------

-- | Prove that floating point addition is not associative. For illustration purposes,
-- we will require one of the inputs to be a @NaN@. We have:
--
-- >>> prove $ assocPlus (0/0)
-- Falsifiable. Counter-example:
--   s0 = 0.0 :: Float
--   s1 = 0.0 :: Float
--
-- Indeed:
--
-- >>> let i = 0/0 :: Float
-- >>> i + (0.0 + 0.0)
-- NaN
-- >>> ((i + 0.0) + 0.0)
-- NaN
--
-- But keep in mind that @NaN@ does not equal itself in the floating point world! We have:
--
-- >>> let nan = 0/0 :: Float in nan == nan
-- False
assocPlus :: SFloat -> SFloat -> SFloat -> SBool
assocPlus x y z = x + (y + z) .== (x + y) + z

-- | Prove that addition is not associative, even if we ignore @NaN@/@Infinity@ values.
-- To do this, we use the predicate 'fpIsPoint', which is true of a floating point
-- number ('SFloat' or 'SDouble') if it is neither @NaN@ nor @Infinity@. (That is, it's a
-- representable point in the real-number line.)
--
-- We have:
--
-- >>> assocPlusRegular
-- Falsifiable. Counter-example:
--   x =  131071.26 :: Float
--   y =  1.4853516 :: Float
--   z = -126976.29 :: Float
--
-- Indeed, we have:
--
-- >>> let x =  131071.26 :: Float
-- >>> let y =  1.4853516 :: Float
-- >>> let z = -126976.29 :: Float
-- >>> x + (y + z)
-- 4096.453
-- >>> (x + y) + z
-- 4096.461
--
-- Note the significant difference between two additions!
assocPlusRegular :: IO ThmResult
assocPlusRegular = prove $ do [x, y, z] <- sFloats ["x", "y", "z"]
                              let lhs = x+(y+z)
                                  rhs = (x+y)+z
                              -- make sure we do not overflow at the intermediate points
                              constrain $ fpIsPoint lhs
                              constrain $ fpIsPoint rhs
                              return $ lhs .== rhs

-----------------------------------------------------------------------------
-- * FP addition by non-zero can result in no change
-----------------------------------------------------------------------------

-- | Demonstrate that @a+b = a@ does not necessarily mean @b@ is @0@ in the floating point world,
-- even when we disallow the obvious solution when @a@ and @b@ are @Infinity.@
-- We have:
--
-- >>> nonZeroAddition
-- Falsifiable. Counter-example:
--   a = 2.2922064e-37 :: Float
--   b =       1.1e-44 :: Float
--
-- Indeed, we have:
--
-- >>> let a = 2.2922064e-37 :: Float
-- >>> let b =       1.1e-44 :: Float
-- >>> a + b == a
-- True
-- >>> b == 0
-- False
--
nonZeroAddition :: IO ThmResult
nonZeroAddition = prove $ do [a, b] <- sFloats ["a", "b"]
                             constrain $ fpIsPoint a
                             constrain $ fpIsPoint b
                             constrain $ a + b .== a
                             return $ b .== 0

-----------------------------------------------------------------------------
-- * FP multiplicative inverses may not exist
-----------------------------------------------------------------------------

-- | This example illustrates that @a * (1/a)@ does not necessarily equal @1@. Again,
-- we protect against division by @0@ and @NaN@/@Infinity@.
--
-- We have:
--
-- >>> multInverse
-- Falsifiable. Counter-example:
--   a = 1.2896893825010637e308 :: Double
--
-- Indeed, we have:
--
-- >>> let a = 1.2896893825010637e308 :: Double
-- >>> a * (1/a)
-- 0.9999999999999998
multInverse :: IO ThmResult
multInverse = prove $ do a <- sDouble "a"
                         constrain $ fpIsPoint a
                         constrain $ fpIsPoint (1/a)
                         return $ a * (1/a) .== 1

-----------------------------------------------------------------------------
-- * Effect of rounding modes
-----------------------------------------------------------------------------

-- | One interesting aspect of floating-point is that the chosen rounding-mode
-- can effect the results of a computation if the exact result cannot be precisely
-- represented. SBV exports the functions 'fpAdd', 'fpSub', 'fpMul', 'fpDiv', 'fpFMA'
-- and 'fpSqrt' which allows users to specify the IEEE supported 'RoundingMode' for
-- the operation. This example illustrates how SBV can be used to find rounding-modes
-- where, for instance, addition can produce different results. We have:
--
-- >>> roundingAdd
-- Satisfiable. Model:
--   rm = RoundTowardNegative :: RoundingMode
--   x  =          0.21655247 :: Float
--   y  =          -1.0332974 :: Float
--
-- (Note that depending on your version of Z3, you might get a different result.)
-- Unfortunately we can't directly validate this result at the Haskell level, as Haskell only supports
-- 'RoundNearestTiesToEven'. We have:
--
-- >>> 0.21655247 + (-1.0332974) :: Float
-- -0.8167449
--
-- While we cannot directly see the result when the mode is 'RoundTowardNegative' in Haskell, we can use
-- SBV to provide us with that result thusly:
--
-- >>> sat $ \z -> z .== fpAdd sRoundTowardNegative 0.21655247 (-1.0332974 :: SFloat)
-- Satisfiable. Model:
--   s0 = -0.816745 :: Float
--
-- We can see why these two resuls are indeed different: The 'RoundTowardNegative'
-- (which rounds towards negative-infinity) produces a smaller result. Indeed, if we treat these numbers
-- as 'Double' values, we get:
--
-- >> 0.21655247 + (-1.0332974) :: Double
-- -0.8167449299999999
--
-- we see that the "more precise" result is smaller than what the 'Float' value is, justifying the
-- smaller value with 'RoundTowardNegative'. A more detailed study is beyond our current scope, so we'll
-- merely note that floating point representation and semantics is indeed a thorny
-- subject, and point to <http://ece.uwaterloo.ca/~dwharder/NumericalAnalysis/02Numerics/Double/paper.pdf> as
-- an excellent guide.
roundingAdd :: IO SatResult
roundingAdd = sat $ do m :: SRoundingMode <- free "rm"
                       constrain $ m ./= literal RoundNearestTiesToEven
                       x <- sFloat "x"
                       y <- sFloat "y"
                       let lhs = fpAdd m x y
                       let rhs = x + y
                       constrain $ fpIsPoint lhs
                       constrain $ fpIsPoint rhs
                       return $ lhs ./= rhs
