{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ViewPatterns    #-}

module System.MQ.Jobcontrol
  ( runJobcontrol
  ) where

import           Control.Concurrent            (threadDelay)
import           Control.Monad.Except          (throwError)
import           Control.Monad.IO.Class        (liftIO)
import qualified Data.ByteString               as BS (readFile)
import qualified Data.ByteString.Char8         as BSC8 (unpack)
import           Data.Function                 (fix)
import           System.Directory              (doesFileExist)
import           System.MQ.Component           (Env (..), TwoChannels (..),
                                                load2Channels)
import           System.MQ.Component.Transport (push, sub)
import           System.MQ.Monad               (MQError (..), MQMonad,
                                                foreverSafe)
import           System.MQ.Protocol            (Condition (..), Encoding,
                                                MessageType, Spec,
                                                createMessageBS, matches,
                                                messagePid, mkId, notExpires)
import           Text.Read                     (readMaybe)

-- | Run Jobcontrol in command prompt.
--
runJobcontrol :: Env -> MQMonad ()
runJobcontrol env@Env{..} = do
    channels <- load2Channels
    printHelp

    foreverSafe name $ do
        command <- liftIO $ getLine
        case words command of
          ["run", spec', readMaybe -> mtype', encoding', path] -> processRun channels spec' mtype' encoding' path
          ["help", "run"]                                      -> printHelpRun
          ["help"]                                             -> printHelp
          _                                                    -> printError
  where
    processRun :: TwoChannels -> Spec -> Maybe MessageType -> Encoding -> FilePath -> MQMonad ()
    processRun _ _ Nothing _ _ = throwError (MQComponentError "Unknown type of message")
    processRun TwoChannels{..} spec' (Just mtype') encoding' path = do
        -- Throw error if path to file is invalid
        checkPath path
        -- If check of path hasn't failed, then we are able to read file
        dataBS <- liftIO $ BS.readFile path

        -- Generate parent id for message that will be sent to queue. We need parent id to get response to message
        pId <- fst <$> mkId creator spec'
        -- Wait to make sure that id of message will be differet from its parent's id
        liftIO $ threadDelay oneSecond
        -- Create message with data that is already encoded in bytestring
        msg <- createMessageBS pId creator notExpires spec' encoding' mtype' dataBS

        -- Sent message to queue
        push toScheduler env msg
        liftIO $ putStrLn $ "Sent message to Monique. Its id: " ++ BSC8.unpack pId

        fix $ \action -> do
            -- Receive message from queue
            (tag, response) <- sub fromScheduler env

            -- If received message is answer to message that was sent, print received message.
            -- Otherwise continue receiving messages from queue
            if tag `matches` (messagePid :== pId)
              then liftIO $ print response
              else action

    checkPath :: FilePath -> MQMonad ()
    checkPath = ((\ex -> if ex then return () else throwError existanceEr) =<<) . liftIO . doesFileExist

    existanceEr = MQComponentError "Given file doesn't exist"

    printHelp :: MQMonad ()
    printHelp = liftIO $ do
        putStrLn "run <spec> <data_type> <encoding> <path/to/file> — run job"
        putStrLn "help run — info about parameters of 'run'"
        putStrLn "help — this info"

    printHelpRun :: MQMonad ()
    printHelpRun = liftIO $ do
        putStrLn "Sends message of given spec containing given data to Monique"
        putStrLn "<spec>         — spec of message as it is documented in API"
        putStrLn "<data_type>    — one of following types of messages: config, response, data, error"
        putStrLn "<encoding>     — encoding of data in message that matches encoding for that type of data in API"
        putStrLn "<path/to/file> - path to file containing data, that will be sent in message, as bytestring"

    printError :: MQMonad ()
    printError = liftIO $ putStrLn "Incorrect command"

    oneSecond :: Int
    oneSecond = 10^(6 :: Int)
