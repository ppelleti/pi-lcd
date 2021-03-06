{-# LANGUAGE OverloadedStrings #-}

-- a demo of buttons and backlight colors

-- This example is dedicated to the public domain (cc0) by Patrick Pelletier

import Control.Exception
import Control.Monad
import Data.Bits
import Data.Char
import Data.Monoid
import qualified Data.Text as T
import Data.Word
import Text.Printf

import System.Hardware.PiLcd

printChanges :: PiLcd -> Int -> IO ()
printChanges lcd color = do
  b <- getButtonEvent lcd
  color' <- case b of
              Nothing -> return color
              (Just btn@(ButtonEvent but dir)) -> do
                let nc = case dir of
                           Press -> 7 .&. (color + 1)
                           Release -> color
                    nc' = toEnum nc
                setBacklightColor lcd nc'
                let msg = ["“" ++ (drop 6 $ show but) ++ "” " ++ (show dir), (show nc')]
                updateDisplay lcd $ map T.pack msg
                return nc
  printChanges lcd color'

main =
  bracket (openPiLcd defaultLcdAddress $ defaultLcdOptions) turnOffAndClosePiLcd
  $ \lcd -> do
    putStrLn "Press Control-C to exit"
    updateDisplay lcd ["Press buttons...", ""]
    printChanges lcd 0
