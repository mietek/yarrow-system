-- File: GoMonSt
-- Description: This module defines error and state monads, for use in
--              Gofer

module GoMonSt where

infixr 5 >>

-------------------
-- G E N E R A L --
-------------------

-- for an introduction to monads, see Philip Wadler's papers

return :: Monad m => a -> m a
return = result

-- skip will usually be bound to something
skip :: Monad m => m ()
skip = return ()

maplComs :: Monad m => (a -> m ()) -> [a] -> m ()
maplComs p l = map (const ()) (mapl p l)

mapL :: Monad m => (a -> m b) -> ([a] -> m [b])
mapL = mapl

-- the >> corresponds to the ; in many imperative languages
(>>) :: Monad m => m  () -> m c -> m c
c >> d = c `bind` (const d)

(>>=) :: Monad a => a b -> (b -> a c) -> a c
(>>=) = bind

-- Only used for testing
primitive trace "primTrace" :: String -> a -> a

----------------------------
-- E R R O R  M O N A D S --
----------------------------

-- We would like to have parametrized over the type Error, and could
-- have done so in Gofer, but this is not admitted in Haskell.

class Monad m => PreErrorMonad m where -- a class of monads for describing
    err :: Error -> m a               -- computations that might go wrong


class PreErrorMonad m => ErrorMonad m where
    handle :: m a -> (Error -> b) -> (a -> b) -> b
-- handle allows you to return to a normal datatype

class PreErrorMonad m => ErrorSMonad m where
    handleS :: m a -> (Error -> m b) -> (a -> m b) -> m b
-- handleS stays in the monad (e.g. for state monads)

{-
instance ErrorMonad m => ErrorSMonad m where
    handleS = handle
-}

data E a = Suc a | Err Error


instance Functor E where
       map f (Suc a) = Suc (f a)
       map f (Err e) = Err e

instance Monad E where
       result a = Suc a
       (Suc a) `bind` f = f a
       (Err e) `bind` f = Err e

instance PreErrorMonad E where
     err = Err

instance ErrorMonad E where
     handle (Err e) f g = f e
     handle (Suc a) f g = g a


noErr :: ErrorMonad m => (Error -> String) -> m a -> a
noErr mkErr x = handle x
                (error . mkErr) -- Gofer runtime error.
                id

-- doFirstOk p handle xs  performs p on all elements of xs, and returns
--                        the corresponding result for the first element
--                        that succeeds. If all fail, handle is invoked with
--                        as argument all error messages with the input of p
doFirstOk :: ErrorSMonad m =>
             (a -> m b) -> ([(Error,a)] -> m b) -> [a] -> m b
doFirstOk p = doFirstOk' p []

doFirstOk' p errs handle [] = handle (reverse errs)
doFirstOk' p errs handle (x:xs) =
    handleS (p x)
    (\er -> doFirstOk' p ((er,x):errs) handle xs)
    return


-----------------------------------------
-- S T A T E - E R R O R   M O N A D S --
-----------------------------------------

data State s a = ST (s -> (s,E a))

instance Functor (State s) where
     map f (ST st) = ST (\s -> doSnd (map f) (st s))

instance Monad (State s) where
     result x = ST (\s -> (s,Suc x))
     (ST x) `bind` f = ST (\s -> let (s',ea) = x s in
                                  case ea of
                                  Err e -> (s',Err e)
                                  Suc a -> let (ST f') = f a in
                                           f' s')

instance PreErrorMonad (State s) where
     err e = ST (\s -> (s,Err e))

instance ErrorSMonad (State s) where
    handleS (ST x) hand f = ST (\s -> let (s',ea) = x s in
                                  case ea of
                                  Err e -> let (ST hand') = hand e in
                                           hand' s'
                                  Suc a -> let (ST f') = f a in
                                           f' s')

class StateMonad m where
     fetch :: m s s
     update :: (s->s) -> m s s
     update' :: (s->s) -> m s ()
     set :: s -> m s ()


instance StateMonad State where
     fetch = ST (\s -> (s,Suc s))
     update f = ST (\s -> (f s, Suc s))
     update' f = ST (\s -> (f s, Suc ())) -- map (const ()) (update f)
     set s = ST (\old -> (s,Suc ()))


perform :: PreErrorMonad (State b) => s -> State s a -> State b (a,s)
perform st (ST p) = let (st',ea) = p st in
                      case ea of
                      Err e -> err e
                      Suc a -> return (a,st')


runState :: s -> State s b -> (s,E b)
runState init (ST prog) = prog init
