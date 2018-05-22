{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE ViewPatterns      #-}

module System.MQ.Jobcontrol
  ( runJobcontrol
  ) where

import           Control.Concurrent           (forkIO, threadDelay)
import           Control.Concurrent.MVar      (MVar, modifyMVar_, newMVar, readMVar,
                                               tryReadMVar)
import           Control.Monad                (when)
import           Control.Monad.Except         (throwError)
import           Control.Monad.IO.Class       (liftIO)
import qualified Data.ByteString              as BS (readFile)
import qualified Data.ByteString.Char8        as BSC8 (unpack)
import           Data.Map.Strict              (Map)
import qualified Data.Map.Strict              as M (fromList, keys, (!))
import           Data.String                  (fromString)
import           System.Directory             (doesFileExist)
import           System.MQ.Component          (Env (..), TwoChannels (..),
                                               load2Channels, loadTechChannels,
                                               push, sub)
import           System.MQ.Error              (MQError (..), errorComponent)
import           System.MQ.Monad              (MQMonad, foreverSafe, runMQMonad)
import           System.MQ.Protocol           (Encoding, Hash, Message (..),
                                               MessageType, Spec, createMessage,
                                               createMessageBS, emptyHash,
                                               messagePid, messageSpec, msgId,
                                               notExpires)
import           System.MQ.Protocol.Technical (KillConfig (..))
import           Text.Read                    (readMaybe)

-- | Run Jobcontrol in command prompt.
--
runJobcontrol :: Env -> MQMonad ()
runJobcontrol env@Env{..} = do
    printHelp

    -- MVar to store ids of messages that we want to receive responses for
    idsMVar <- liftIO $ newMVar []
    lastAction <- liftIO $ newMVar printHelp

    _ <- liftIO $ forkIO $ receiveMessages idsMVar

    commChannels <- load2Channels
    techChannels <- loadTechChannels

    foreverSafe name $ do
        command <- liftIO $ getLine
        let action = case words command of
              ["run", spec', readMaybe -> mtype', encoding', path] -> processRun idsMVar commChannels spec' mtype' encoding' path
              ["kill", fromString -> jobId]                        -> processKill techChannels jobId
              ["help", "run"]                                      -> printHelpRun
              ["help", "kill"]                                     -> printHelpKill
              ["help", "rep"]                                      -> printHelpRep
              ["help"]                                             -> printHelp
              ["rep"]                                              -> performAction lastAction
              _                                                    -> printError
        when (words command /= ["rep"]) $ liftIO $ modifyMVar_ lastAction (pure . const action)
        action
  where
    performAction :: MVar (MQMonad ()) -> MQMonad ()
    performAction actionVar = do
        action <- liftIO $ readMVar actionVar
        action

    processRun :: MVar [(Hash, Spec)] -> TwoChannels -> Spec -> Maybe MessageType -> Encoding -> FilePath -> MQMonad ()
    processRun _ _ _ Nothing _ _ = throwError (MQError errorComponent "unknown type of message")
    processRun idsMVar TwoChannels{..} spec' (Just mtype') encoding' path = do
        -- Throw error if path to file is invalid
        checkPath path
        -- If check of path hasn't failed, then we are able to read file
        dataBS <- liftIO $ BS.readFile path

        -- Wait to make sure that id of message will be differet from its parent's id
        liftIO $ threadDelay oneSecond
        -- Create message with data that is already encoded in bytestring
        msg@Message{..} <- createMessageBS emptyHash creator notExpires spec' encoding' mtype' dataBS

        -- Put id and spec of created message to MVar so thread that receives messages knew which messages to receive
        modifyIds idsMVar (msgId, msgSpec)

        -- Send message to queue
        push toScheduler env msg
        liftIO $ putStrLn $ "Sent message to Monique. Its id: " ++ BSC8.unpack msgId

    processKill :: TwoChannels -> Hash -> MQMonad ()
    processKill TwoChannels{..} jId = createMessage "" creator notExpires (KillConfig jId) >>= push toScheduler env

    modifyIds :: MVar [(Hash, Spec)] -> (Hash, Spec) -> MQMonad ()
    modifyIds idsMVar = liftIO . modifyMVar_ idsMVar . fmap pure . (:)

    receiveMessages :: MVar [(Hash, Spec)] -> IO ()
    receiveMessages idsMVar = runMQMonad $ do
        TwoChannels{..} <- load2Channels
        foreverSafe name $ do
            -- Receive message from queue
            (tag, response@Message{..}) <- sub fromScheduler env
            let pId = messagePid tag

            -- Map that maps messages that we want to receive responses for to their specs
            idsM <- maybeToMap <$> (liftIO $ tryReadMVar idsMVar)

            -- If received message is response to message that we want to receive response for then proceed
            when (pId `elem` M.keys idsM) $ do
              -- If spec of received message doesn't match spec of message that begot it, we save id of that
              -- message cause it is definetly a foreign call of other component. If specs match, we don't need to
              -- save id of received message, because it is not a foreign call
              if messageSpec tag /= (idsM M.! pId)
                then modifyIds idsMVar (msgId, msgSpec) >> (liftIO $ print response)
                else liftIO $ print response

    checkPath :: FilePath -> MQMonad ()
    checkPath = ((\ex -> if ex then return () else throwError existanceEr) =<<) . liftIO . doesFileExist

    existanceEr = MQError errorComponent "given file doesn't exist"

    printHelp :: MQMonad ()
    printHelp = liftIO $ do
        putStrLn "run <spec> <data_type> <encoding> <path/to/file> — run job"
        putStrLn "kill <job_msg_id> — kill job"
        putStrLn "rep – repeat last command"
        putStrLn "help <command> — info about given command"
        putStrLn "help — this info"

    printHelpRun :: MQMonad ()
    printHelpRun = liftIO $ do
        putStrLn "Sends message of given spec containing given data to Monique"
        putStrLn "<spec>         — spec of message as it is documented in API"
        putStrLn "<data_type>    — one of following types of messages: config, result, data, error"
        putStrLn "<encoding>     — encoding of data in message that matches encoding for that type of data in API"
        putStrLn "<path/to/file> - path to file containing data, that will be sent in message, as bytestring"

    printHelpKill :: MQMonad ()
    printHelpKill = liftIO $ do
        putStrLn "Kills job that was started by message with given id"
        putStrLn "<job_msg_id> — id of message that started the job"

    printHelpRep :: MQMonad ()
    printHelpRep = liftIO $ putStrLn "Repeats the last command, even incorrect one."

    printError :: MQMonad ()
    printError = liftIO $ putStrLn "Incorrect command"

    oneSecond :: Int
    oneSecond = 10^(6 :: Int)

    maybeToMap :: Maybe [(Hash, Spec)] -> Map Hash Spec
    maybeToMap = maybe mempty M.fromList
