{-# LANGUAGE OverloadedStrings #-}

module Main where

import           System.MQ.Component  (runApp)
import           System.MQ.Jobcontrol (runJobcontrol)

-- | Name of jobcontrol
--
jobcontrolName :: String
jobcontrolName = "mq_jobcontrol"

main :: IO ()
main = runApp jobcontrolName runJobcontrol
