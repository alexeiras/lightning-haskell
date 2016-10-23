{-# LANGUAGE GADTs                      #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings          #-}

{-|
Module      : Web.Lightning.Types.Lightning
Description : Main Lightning Types
Copyright   : (c) Connor Moreside, 2016
License     : BSD-3
Maintainer  : connor@moresi.de
Stability   : experimental
Portability : POSIX
-}

module Web.Lightning.Types.Lightning
  (
    -- * Lightning Types
    Lightning
  , LightningF(..)
  , LightningT(..)
  , ValidatablePlot(..)
    -- * Lightning Actions
  , runRoute
  , sendPlot
  , streamPlot
  , sendJSON
  , receiveRoute
  , withBaseURL
  , failWith
  , liftLightningF
  )
  where

--------------------------------------------------------------------------------
import           Control.Monad.IO.Class
import           Control.Monad.Reader
import           Control.Monad.Trans.Free

import           Data.Aeson
import qualified Data.Text                         as T

import           Network.API.Builder               hiding (runRoute)

import           Web.Lightning.Routes              (stream)
import           Web.Lightning.Types.Error
import           Web.Lightning.Types.Visualization
import           Web.Lightning.Utilities
--------------------------------------------------------------------------------

-- | Allows plot fields to be validated.
class ValidatablePlot a where
  validatePlot :: a -> Either LightningError a

-- | Represents an IO Lightning transformer action.
type Lightning a = LightningT IO a

-- | Represents a URL.
type BaseUrl = T.Text

-- | Defines the available actions
data LightningF m a where
  FailWith     :: APIError LightningError -> LightningF m a
  ReceiveRoute :: Receivable b => Route -> (b -> a) -> LightningF m a
  RunRoute     :: FromJSON b => Route -> (b -> a) -> LightningF m a
  SendJSON     :: (Receivable b) => Value -> Route -> (b -> a) -> LightningF m a
  WithBaseURL  :: T.Text -> LightningT m b -> (b -> a) -> LightningF m a

instance Functor (LightningF m) where
  fmap _ (FailWith x)        = FailWith x
  fmap f (ReceiveRoute r x)  = ReceiveRoute r (fmap f x)
  fmap f (RunRoute r x)      = RunRoute r (fmap f x)
  fmap f (SendJSON js r x)   = SendJSON js r (fmap f x)
  fmap f (WithBaseURL u a x) = WithBaseURL u a (fmap f x)

-- | Defines free monad transformer
newtype LightningT m a = LightningT (ReaderT BaseUrl (FreeT (LightningF m) m) a)
  deriving (Functor, Applicative, Monad, MonadReader T.Text)

instance MonadIO m => MonadIO (LightningT m) where
  liftIO = LightningT . liftIO

instance MonadTrans LightningT where
  lift = LightningT . lift . lift

-- | Lifts a 'LightningF' free monad into the ReaderT context.
liftLightningF :: (Monad m) => FreeT (LightningF m) m a
               -> ReaderT T.Text (FreeT (LightningF m) m) a
liftLightningF = lift

-- | Runs a route action within the free monadic transformer context.
runRoute :: (FromJSON a, Monad m) => Route
                                     -- ^ Route to run
                                  -> LightningT m a
                                     -- ^ Monad transformer stack with result.
runRoute r = LightningT $ liftF $ RunRoute r id

-- | Sends a request to the lightning-viz server to create a visualization.
sendPlot :: (ToJSON p, ValidatablePlot p, Receivable a, Monad m) => T.Text
                                                 -- ^ The plot type
                                              -> p
                                                 -- ^ The plot creation request
                                              -> Route
                                                 -- ^ The plot route.
                                              -> LightningT m a
                                                 -- ^ Monad transformer stack with result.
sendPlot t p r =
  case validatePlot p of
    Left err -> failWith (APIError err)
    Right p' -> sendJSON (createPayLoad t $ toJSON p') r

-- | Sends a request to either create a brand new streaming plot or
-- to append data to an existing streaming plot.
streamPlot :: (ToJSON p,
               ValidatablePlot p,
               Receivable a,
               Monad m) => Maybe Visualization
                           -- ^ Visualization to update. If nothing, create
                           -- a new plot.
                        -> T.Text
                           -- ^ Plot type
                        -> p
                           -- ^ Plot payload
                        -> Route
                           -- ^ Route to send plot to.
                        -> LightningT m a
                           -- ^ Monad transformer stack with result.
streamPlot viz t p r =
  case validatePlot p of
    Left err -> failWith (APIError err)
    Right _  -> streamOrCreate viz
  where
    streamOrCreate (Just viz') = sendJSON (createDataPayLoad $ toJSON p) (stream viz')
    streamOrCreate Nothing = sendJSON (createPayLoad t $ toJSON p) r

-- | Sends a request containing JSON to the specified route.
sendJSON :: (Receivable a, Monad m) => Value
                                       -- ^ The JSON payload
                                    -> Route
                                       -- ^ Route to send request to
                                    -> LightningT m a
                                       -- ^ Monad transformer stack with result.
sendJSON j r = LightningT $ liftF $ SendJSON j r id

-- | Send and receives a GET request to the specified route.
receiveRoute :: (Receivable a, Monad m) => Route
                                           -- ^ The route to retrieve data from.
                                        -> LightningT m a
                                           -- ^ Monad transformer stack with result.
receiveRoute r = LightningT $ liftF $ ReceiveRoute r id

-- | Replaces the base URL in the stack and run the supplied action afterwards.
withBaseURL :: Monad m => T.Text
                          -- ^ The new base URL.
                       -> LightningT m a
                          -- ^ Next action to run.
                       -> LightningT m a
                          -- ^ Monad transformer stack with result.
withBaseURL u f = LightningT $ liftF $ WithBaseURL u f id

-- | Returns an error message.
failWith :: Monad m => APIError LightningError
                       -- ^ The error message to return.
                    -> LightningT m a
                       -- ^ Monad transformer stack with error.
failWith = LightningT . liftF . FailWith
