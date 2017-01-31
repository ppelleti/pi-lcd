import Control.Monad
import Data.Bits
import Data.Word
import Text.Printf

import I2C
import PiLcd

printChanges :: PiLcd -> Int -> Int -> IO ()
printChanges lcd addr color = do
  b <- getButtonEvent lcd
  color' <- case b of
              Nothing -> return color
              (Just btn) -> do
                let nc = 7 .&. (color + 1)
                    nc' = toEnum nc
                setBacklightColor lcd nc'
                putStrLn $ (show btn) ++ " " ++ (show nc')
                return nc
  printChanges lcd addr color'

main = do
  h <- i2cOpen 1
  lcd <- mkPiLcd h
  printChanges lcd 0x20 0
  i2cClose h
