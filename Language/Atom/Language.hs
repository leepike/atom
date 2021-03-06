-- | The Atom language.
module Language.Atom.Language
  (
    module Language.Atom.Expressions
  -- * Primary Language Containers
  , Atom
  -- * Hierarchical Rule Declarations
  , atom
  , period
  , getPeriod
  , phase
  , exactPhase
  , getPhase
  -- * Action Directives
  , cond
  , Assign (..)
  , incr
  , decr
  -- * Variable Declarations
  , var
  , var'
  , array
  , array'
  , bool
  , bool'
  , int8
  , int8'
  , int16
  , int16'
  , int32
  , int32'
  , int64
  , int64'
  , word8
  , word8'
  , word16
  , word16'
  , word32
  , word32'
  , word64
  , word64'
  , float
  , float'
  , double
  , double'
  -- * Custom Actions
  , action
  , call
  -- * Probing
  , probe
  , probes
  -- * Assertions and Functional Coverage
  , assert
  , cover
  , assertImply
  -- * Utilities
  , Name
  , liftIO
  , path
  , clock
  -- * Code Coverage
  , nextCoverage
  ) where

import Control.Monad
import Control.Monad.Trans
import Data.Int
import Data.Word

import Language.Atom.Elaboration hiding (Atom)
import qualified Language.Atom.Elaboration as E
import Language.Atom.Expressions

infixr 1 <==

-- | The Atom monad captures variable and transition rule declarations.
type Atom = E.Atom

-- | Creates a hierarchical node, where each node could be a atomic rule.
atom :: Name -> Atom a -> Atom a
atom name design = do
  name' <- addName name
  (g1, parent) <- get
  (a, (g2, child)) <- liftIO $ buildAtom g1 { gState = [] } name' design
  put (g2 { gState = gState g1 ++ [StateHierarchy name $ gState g2] }, parent { atomSubs = atomSubs parent ++ [child] })
  return a

-- | Defines the period of execution of sub rules as a factor of the base rate of the system.
--   Rule period is bound by the closest period assertion.  For example:
--
--   > period 10 $ period 2 a   -- Rules in 'a' have a period of 2, not 10.
period :: Int -> Atom a -> Atom a
period n _ | n <= 0 = error "ERROR: Execution period must be greater than 0."
period n atom = do
  (g, a) <- get
  put (g { gPeriod = n }, a)
  r <- atom
  (g', a) <- get
  put (g' { gPeriod = gPeriod g }, a)
  return r

-- | Returns the execution period of the current scope.
getPeriod :: Atom Int
getPeriod = do
  (g, _) <- get
  return $ gPeriod g

phase' :: (Int -> Phase) -> Int -> Atom a -> Atom a
phase' _ n _ | n < 0 = error $ "ERROR: phase " ++ show n ++ " must be at least 0."
phase' phType n atom = do
  (g, a) <- get
  if (n >= gPeriod g) 
    then error $ "ERROR: phase " ++ show n ++ " must be less than the current period "
               ++ show (gPeriod g) ++ "."
    else do put (g { gPhase = phType n }, a)
            r <- atom
            (g', a) <- get
            put (g' { gPhase = gPhase g }, a)
            return r
    -- XXX
    -- else do put (g { gPhase = n }, a)
    --         r <- atom
    --         (g', a) <- get
    --         put (g' { gPhase = gPhase g }, a)
    --         return r

-- | Defines the earliest phase within the period at which the rule should
-- execute; the scheduler attempt to find an optimal phase from 0 <= @n@ <
-- period (thus, the 'phase' must be at least zero and less than the current
-- 'period'.).
phase :: Int -> Atom a -> Atom a
phase n a = phase' MinPhase n a

-- | Ensures an atom is scheduled only at phase @n@.
exactPhase :: Int -> Atom a -> Atom a
exactPhase n a = phase' ExactPhase n a

-- | Returns the phase of the current scope.
getPhase :: Atom Int
getPhase = do
  (g, _) <- get
  return $ case gPhase g of
             MinPhase ph   -> ph
             ExactPhase ph -> ph

-- | Returns the current atom hierarchical path.
path :: Atom String
path = do
  (_, atom) <- get
  return $ atomName atom

-- | Local boolean variable declaration.
bool :: Name -> Bool -> Atom (V Bool)
bool = var

-- | External boolean variable declaration.
bool' :: Name -> V Bool
bool' name = var' name Bool

-- | Local int8 variable declaration.
int8 :: Name -> Int8 -> Atom (V Int8)
int8 = var

-- | External int8 variable declaration.
int8' :: Name -> V Int8
int8' name = var' name Int8

-- | Local int16 variable declaration.
int16 :: Name -> Int16 -> Atom (V Int16)
int16 = var

-- | External int16 variable declaration.
int16' :: Name -> V Int16
int16' name = var' name Int16

-- | Local int32 variable declaration.
int32 :: Name -> Int32 -> Atom (V Int32)
int32 = var

-- | External int32 variable declaration.
int32' :: Name -> V Int32
int32' name = var' name Int32

-- | Local int64 variable declaration.
int64 :: Name -> Int64 -> Atom (V Int64)
int64 = var

-- | External int64 variable declaration.
int64' :: Name -> V Int64
int64' name = var' name Int64

-- | Local word8 variable declaration.
word8 :: Name -> Word8 -> Atom (V Word8)
word8 = var

-- | External word8 variable declaration.
word8' :: Name -> V Word8
word8' name = var' name Word8

-- | Local word16 variable declaration.
word16 :: Name -> Word16 -> Atom (V Word16)
word16 = var

-- | External word16 variable declaration.
word16' :: Name -> V Word16
word16' name = var' name Word16

-- | Local word32 variable declaration.
word32 :: Name -> Word32 -> Atom (V Word32)
word32 = var

-- | External word32 variable declaration.
word32' :: Name -> V Word32
word32' name = var' name Word32

-- | Local word64 variable declaration.
word64 :: Name -> Word64 -> Atom (V Word64)
word64 = var

-- | External word64 variable declaration.
word64' :: Name -> V Word64
word64' name = var' name Word64

-- | Local float variable declaration.
float :: Name -> Float -> Atom (V Float)
float = var

-- | External float variable declaration.
float' :: Name -> V Float
float' name = var' name Float

-- | Local double variable declaration.
double :: Name -> Double -> Atom (V Double)
double = var

-- | External double variable declaration.
double' :: Name -> V Double
double' name = var' name Double

-- | Declares an action.
action :: ([String] -> String) -> [UE] -> Atom ()
action f ues = do
  (g, a) <- get
  put (g, a { atomActions = atomActions a ++ [(f, ues)] })

-- | Calls an external C function of type 'void f(void)'.
call :: Name -> Atom ()
call n = action (\ _ -> n ++ "()") []

-- | Declares a probe.
probe :: Expr a => Name -> E a -> Atom ()
probe name a = do
  (g, atom) <- get
  if any (\ (n, _) -> name == n) $ gProbes g
    then error $ "ERROR: Duplicated probe name: " ++ name
    else put (g { gProbes = (name, ue a) : gProbes g }, atom)


-- | Fetches all declared probes to current design point.
probes :: Atom [(String, UE)]
probes = do
  (g, _) <- get
  return $ gProbes g


-- | Increments a NumE 'V'.
incr :: (Assign a, NumE a) => V a -> Atom ()
incr a = a <== value a + 1

-- | Decrements a NumE 'V'.
decr :: (Assign a, NumE a) => V a -> Atom ()
decr a = a <== value a - 1


class Expr a => Assign a where
  -- | Assign an 'E' to a 'V'.
  (<==) :: V a -> E a -> Atom ()
  v <== e = do
    (g, atom) <- get
    put (g, atom { atomAssigns = (uv v, ue e) : atomAssigns atom })

instance Assign Bool
instance Assign Int8
instance Assign Int16
instance Assign Int32
instance Assign Int64
instance Assign Word8
instance Assign Word16
instance Assign Word32
instance Assign Word64
instance Assign Float
instance Assign Double

-- | Adds an enabling condition to an atom subtree of rules.
--   This condition must be true before any rules in hierarchy
--   are allowed to execute.
cond :: E Bool -> Atom ()
cond c = do
  (g, atom) <- get
  put (g, atom { atomEnable = uand (atomEnable atom) (ue c) })

-- | Reference to the 64-bit free running clock.
clock :: E Word64
clock = value $ word64' "__global_clock"

-- | Rule coverage information.  (current coverage index, coverage data)
nextCoverage :: Atom (E Word32, E Word32)
nextCoverage = do
  action (const "__coverage_index = (__coverage_index + 1) % __coverage_len") []
  return (value $ word32' "__coverage_index", value $ word32' "__coverage[__coverage_index]")


-- | An assertions checks that an E Bool is true.  Assertions are checked between the execution of every rule.
--   Parent enabling conditions can disable assertions, but period and phase constraints do not.
--   Assertion names should be globally unique.
assert :: Name -> E Bool -> Atom ()
assert name check = do
  (g, atom) <- get
  let names = fst $ unzip $ atomAsserts atom
  when (elem name names) (liftIO $ putStrLn $ "WARNING: Assertion name already used: " ++ name)
  put (g, atom { atomAsserts = (name, ue check) : atomAsserts atom })

-- | Implication assertions.  Creates an implicit coverage point for the precondition.
assertImply :: Name -> E Bool -> E Bool -> Atom ()
assertImply name a b = do
  assert name $ imply a b
  cover (name ++ "Precondition") a

-- | A functional coverage point tracks if an event has occured (true).
--   Coverage points are checked at the same time as assertions.
--   Coverage names should be globally unique.
cover :: Name -> E Bool -> Atom ()
cover name check = do
  (g, atom) <- get
  let names = fst $ unzip $ atomCovers atom
  when (elem name names) (liftIO $ putStrLn $ "WARNING: Coverage name already used: " ++ name)
  put (g, atom { atomCovers = (name, ue check) : atomCovers atom })

