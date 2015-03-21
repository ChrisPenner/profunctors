{-# LANGUAGE CPP #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE MultiParamTypeClasses #-}
#if __GLASGOW_HASKELL__ >= 702 && __GLASGOW_HASKELL__ <= 708
{-# LANGUAGE Trustworthy #-}
#endif
-----------------------------------------------------------------------------
-- |
-- Module      :  Data.Profunctor.Composition
-- Copyright   :  (C) 2014 Edward Kmett
-- License     :  BSD-style (see the file LICENSE)
--
-- Maintainer  :  Edward Kmett <ekmett@gmail.com>
-- Stability   :  experimental
-- Portability :  GADTs, TFs, MPTCs, RankN
--
----------------------------------------------------------------------------
module Data.Profunctor.Composition
  (
  -- * Profunctor Composition
    Procompose(..)
  , procomposed
  -- * Unitors and Associator
  , idl
  , idr
  , assoc
  -- * Generalized Composition
  , downs, kleislis
  , ups, cokleislis
  -- * Right Kan Lift
  , Rift(..)
  , decomposeRift
  ) where

import Control.Arrow
import Control.Category
import Control.Comonad
import Control.Monad (liftM)
import Data.Functor.Compose
import Data.Profunctor
import Data.Profunctor.Adjunction
import Data.Profunctor.Closed
import Data.Profunctor.Monad
import Data.Profunctor.Rep
import Data.Profunctor.Unsafe
import Prelude hiding ((.),id)

type Iso s t a b = forall p f. (Profunctor p, Functor f) => p a (f b) -> p s (f t)

-- * Profunctor Composition

-- | @'Procompose' p q@ is the 'Profunctor' composition of the
-- 'Profunctor's @p@ and @q@.
--
-- For a good explanation of 'Profunctor' composition in Haskell
-- see Dan Piponi's article:
--
-- <http://blog.sigfpe.com/2011/07/profunctors-in-haskell.html>
data Procompose p q d c where
  Procompose :: p x c -> q d x -> Procompose p q d c

instance ProfunctorFunctor (Procompose p) where
  promap f (Procompose p q) = Procompose p (f q)

instance Category p => ProfunctorMonad (Procompose p) where
  proreturn = Procompose id
  projoin (Procompose p (Procompose q r)) = Procompose (p . q) r

procomposed :: Category p => Procompose p p a b -> p a b
procomposed (Procompose pxc pdx) = pxc . pdx
{-# INLINE procomposed #-}

instance (Profunctor p, Profunctor q) => Profunctor (Procompose p q) where
  dimap l r (Procompose f g) = Procompose (rmap r f) (lmap l g)
  {-# INLINE dimap #-}
  lmap k (Procompose f g) = Procompose f (lmap k g)
  {-# INLINE rmap #-}
  rmap k (Procompose f g) = Procompose (rmap k f) g
  {-# INLINE lmap #-}
  k #. Procompose f g     = Procompose (k #. f) g
  {-# INLINE ( #. ) #-}
  Procompose f g .# k     = Procompose f (g .# k)
  {-# INLINE ( .# ) #-}

instance Profunctor p => Functor (Procompose p q a) where
  fmap k (Procompose f g) = Procompose (rmap k f) g
  {-# INLINE fmap #-}

-- | The composition of two 'Representable' 'Profunctor's is 'Representable' by
-- the composition of their representations.
instance (Representable p, Representable q) => Representable (Procompose p q) where
  type Rep (Procompose p q) = Compose (Rep q) (Rep p)
  tabulate f = Procompose (tabulate id) (tabulate (getCompose . f))
  {-# INLINE tabulate #-}
  rep (Procompose g f) d = Compose $ rep g <$> rep f d
  {-# INLINE rep #-}

instance (Corepresentable p, Corepresentable q) => Corepresentable (Procompose p q) where
  type Corep (Procompose p q) = Compose (Corep p) (Corep q)
  cotabulate f = Procompose (cotabulate (f . Compose)) (cotabulate id)
  {-# INLINE cotabulate #-}
  corep (Procompose g f) (Compose d) = corep g $ corep f <$> d
  {-# INLINE corep #-}

instance (Strong p, Strong q) => Strong (Procompose p q) where
  first' (Procompose x y) = Procompose (first' x) (first' y)
  {-# INLINE first' #-}
  second' (Procompose x y) = Procompose (second' x) (second' y)
  {-# INLINE second' #-}

instance (Choice p, Choice q) => Choice (Procompose p q) where
  left' (Procompose x y) = Procompose (left' x) (left' y)
  {-# INLINE left' #-}
  right' (Procompose x y) = Procompose (right' x) (right' y)
  {-# INLINE right' #-}

instance (Closed p, Closed q) => Closed (Procompose p q) where
  closed (Procompose x y) = Procompose (closed x) (closed y)
  {-# INLINE closed #-}

-- * Lax identity

-- | @(->)@ functions as a lax identity for 'Profunctor' composition.
--
-- This provides an 'Iso' for the @lens@ package that witnesses the
-- isomorphism between @'Procompose' (->) q d c@ and @q d c@, which
-- is the left identity law.
--
-- @
-- 'idl' :: 'Profunctor' q => Iso' ('Procompose' (->) q d c) (q d c)
-- @
idl :: Profunctor q => Iso (Procompose (->) q d c) (Procompose (->) r d' c') (q d c) (r d' c')
idl = dimap (\(Procompose g f) -> rmap g f) (fmap (Procompose id))

-- | @(->)@ functions as a lax identity for 'Profunctor' composition.
--
-- This provides an 'Iso' for the @lens@ package that witnesses the
-- isomorphism between @'Procompose' q (->) d c@ and @q d c@, which
-- is the right identity law.
--
-- @
-- 'idr' :: 'Profunctor' q => Iso' ('Procompose' q (->) d c) (q d c)
-- @
idr :: Profunctor q => Iso (Procompose q (->) d c) (Procompose r (->) d' c') (q d c) (r d' c')
idr = dimap (\(Procompose g f) -> lmap f g) (fmap (`Procompose` id))


-- | The associator for 'Profunctor' composition.
--
-- This provides an 'Iso' for the @lens@ package that witnesses the
-- isomorphism between @'Procompose' p ('Procompose' q r) a b@ and
-- @'Procompose' ('Procompose' p q) r a b@, which arises because
-- @Prof@ is only a bicategory, rather than a strict 2-category.
assoc :: Iso (Procompose p (Procompose q r) a b) (Procompose x (Procompose y z) a b)
             (Procompose (Procompose p q) r a b) (Procompose (Procompose x y) z a b)
assoc = dimap (\(Procompose f (Procompose g h)) -> Procompose (Procompose f g) h)
              (fmap (\(Procompose (Procompose f g) h) -> Procompose f (Procompose g h)))

-- | 'Profunctor' composition generalizes 'Functor' composition in two ways.
--
-- This is the first, which shows that @exists b. (a -> f b, b -> g c)@ is
-- isomorphic to @a -> f (g c)@.
--
-- @'downs' :: 'Functor' f => Iso' ('Procompose' ('Down' f) ('Down' g) d c) ('Down' ('Compose' f g) d c)@
downs :: Functor g
        => Iso (Procompose (Down f ) (Down g ) d  c )
               (Procompose (Down f') (Down g') d' c')
               (Down (Compose g  f ) d  c )
               (Down (Compose g' f') d' c')
downs = dimap hither (fmap yon) where
  hither (Procompose (Down xgc) (Down dfx)) = Down (Compose . fmap xgc . dfx)
  yon (Down dfgc) = Procompose (Down id) (Down (getCompose . dfgc))

-- | 'Profunctor' composition generalizes 'Functor' composition in two ways.
--
-- This is the second, which shows that @exists b. (f a -> b, g b -> c)@ is
-- isomorphic to @g (f a) -> c@.
--
-- @'ups' :: 'Functor' f => Iso' ('Procompose' ('Up' f) ('Up' g) d c) ('Up' ('Compose' g f) d c)@
ups :: Functor f
          => Iso (Procompose (Up f ) (Up g ) d  c )
                 (Procompose (Up f') (Up g') d' c')
                 (Up (Compose f  g ) d  c )
                 (Up (Compose f' g') d' c')
ups = dimap hither (fmap yon) where
  hither (Procompose (Up gxc) (Up fdx)) = Up (gxc . fmap fdx . getCompose)
  yon (Up dgfc) = Procompose (Up (dgfc . Compose)) (Up id)

-- | This is a variant on 'downs' that uses 'Kleisli' instead of 'Down'.
--
-- @'kleislis' :: 'Monad' f => Iso' ('Procompose' ('Kleisli' f) ('Kleisli' g) d c) ('Kleisli' ('Compose' f g) d c)@
kleislis :: Monad g
        => Iso (Procompose (Kleisli f ) (Kleisli g ) d  c )
               (Procompose (Kleisli f') (Kleisli g') d' c')
               (Kleisli (Compose g  f ) d  c )
               (Kleisli (Compose g' f') d' c')
kleislis = dimap hither (fmap yon) where
  hither (Procompose (Kleisli xgc) (Kleisli dfx)) = Kleisli (Compose . liftM xgc . dfx)
  yon (Kleisli dfgc) = Procompose (Kleisli id) (Kleisli (getCompose . dfgc))

-- | This is a variant on 'ups' that uses 'Cokleisli' instead
-- of 'Up'.
--
-- @'cokleislis' :: 'Functor' f => Iso' ('Procompose' ('Cokleisli' f) ('Cokleisli' g) d c) ('Cokleisli' ('Compose' g f) d c)@
cokleislis :: Functor f
          => Iso (Procompose (Cokleisli f ) (Cokleisli g ) d  c )
                 (Procompose (Cokleisli f') (Cokleisli g') d' c')
                 (Cokleisli (Compose f  g ) d  c )
                 (Cokleisli (Compose f' g') d' c')
cokleislis = dimap hither (fmap yon) where
  hither (Procompose (Cokleisli gxc) (Cokleisli fdx)) = Cokleisli (gxc . fmap fdx . getCompose)
  yon (Cokleisli dgfc) = Procompose (Cokleisli (dgfc . Compose)) (Cokleisli id)

----------------------------------------------------------------------------
-- * Rift
----------------------------------------------------------------------------
-- | This represents the right Kan lift of a 'Profunctor' @q@ along a 'Profunctor' @p@ in a limited version of the 2-category of Profunctors where the only object is the category Hask, 1-morphisms are profunctors composed and compose with Profunctor composition, and 2-morphisms are just natural transformations.
newtype Rift p q a b = Rift { runRift :: forall x. p b x -> q a x }

instance ProfunctorFunctor (Rift p) where
  promap f (Rift g) = Rift (f . g)

instance Category p => ProfunctorComonad (Rift p) where
  proextract (Rift f) = f id
  produplicate (Rift f) = Rift $ \p -> Rift $ \q -> f (q . p)

instance (Profunctor p, Profunctor q) => Profunctor (Rift p q) where
  dimap ca bd f = Rift (lmap ca . runRift f . lmap bd)
  {-# INLINE dimap #-}
  lmap ca f = Rift (lmap ca . runRift f)
  {-# INLINE lmap #-}
  rmap bd f = Rift (runRift f . lmap bd)
  {-# INLINE rmap #-}
  bd #. f = Rift (\p -> runRift f (p .# bd))
  {-# INLINE ( #. ) #-}
  f .# ca = Rift (\p -> runRift f p .# ca)
  {-# INLINE (.#) #-}

instance Profunctor p => Functor (Rift p q a) where
  fmap bd f = Rift (runRift f . lmap bd)
  {-# INLINE fmap #-}

-- | @'Rift' p p@ forms a 'Monad' in the 'Profunctor' 2-category, which is isomorphic to a Haskell 'Category' instance.
instance p ~ q => Category (Rift p q) where
  id = Rift id
  {-# INLINE id #-}
  Rift f . Rift g = Rift (g . f)
  {-# INLINE (.) #-}

-- | The 2-morphism that defines a left Kan lift.
--
-- Note: When @p@ is right adjoint to @'Rift' p (->)@ then 'decomposeRift' is the 'counit' of the adjunction.
decomposeRift :: Procompose p (Rift p q) :-> q
decomposeRift (Procompose p (Rift pq)) = pq p
{-# INLINE decomposeRift #-}

instance ProfunctorAdjunction (Procompose p) (Rift p) where
  counit (Procompose p (Rift pq)) = pq p
  unit q = Rift $ \p -> Procompose p q

--instance (ProfunctorAdjunction f g, ProfunctorAdjunction f' g') => ProfunctorAdjunction (ProfunctorCompose f' f) (ProfunctorCompose g g') where
