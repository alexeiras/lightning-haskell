{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE LambdaCase #-}

module Web.Lightning.Routes where

import Data.Aeson
import qualified Data.Text as T

import Web.Lightning.Types.Lightning

import Network.API.Builder hiding (runRoute)

data Session =
  Session { sessionID :: T.Text
          , sessionName :: T.Text
          , updatedAt :: T.Text
          , createdAt :: T.Text
          }
  deriving (Show, Read, Eq, Ord)

instance FromJSON Session where
  parseJSON (Object o) =
    Session <$>
      o .: "id" <*>
      o .: "name" <*>
      o .: "updatedAt" <*>
      o .: "createdAt"
  parseJSON _ = mempty

instance Receivable Session where
  receive = useFromJSON

createSessionRoute :: Route
createSessionRoute = Route ["sessions"] [] "POST"

createSession :: Monad m => LightningT m Session
createSession = receiveRoute createSessionRoute
