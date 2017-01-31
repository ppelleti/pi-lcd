module PiLcd
  ( PiLcd
  , Color(..)
  , mkPiLcd
  , getButtons
  , buttonSelect
  , buttonRight
  , buttonDown
  , buttonUp
  , buttonLeft
  , setBacklightColor
  ) where

import Control.Applicative
import Data.Bits
import Data.Word

import I2C
import Mcp23017

data PiLcd =
  PiLcd
  { plExpander :: PortExpander
  }

lcdAddr :: Int
lcdAddr = 0x20

data Color = Off | Red | Green | Blue | Cyan | Magenta | Yellow | White
  deriving (Eq, Ord, Show, Read, Bounded, Enum)

off, red, green, blue, cyan, magenta, yellow, white :: Word16

off     = 0
red     = bit 14
green   = bit 15
blue    = bit 0
cyan    = green + blue
magenta = red + blue
yellow  = red + green
white   = red + green + blue

colorValue :: Color -> Word16
colorValue Off     = off
colorValue Red     = red
colorValue Green   = green
colorValue Blue    = blue
colorValue Cyan    = cyan
colorValue Magenta = magenta
colorValue Yellow  = yellow
colorValue White   = white

buttonMaskA :: Word8
buttonMaskA = 0x1f

buttonMask :: Word16
buttonMask = fromIntegral buttonMaskA `shiftL` 8

bitSelect, bitRight, bitDown, bitUp, bitLeft :: Int
bitSelect = 0
bitRight  = 1
bitDown   = 2
bitUp     = 3
bitLeft   = 4

buttonSelect, buttonRight, buttonDown, buttonUp, buttonLeft :: Word8
buttonSelect = bit bitSelect
buttonRight  = bit bitRight
buttonDown   = bit bitDown
buttonUp     = bit bitUp
buttonLeft   = bit bitLeft

allBits :: Word16
allBits = 0xffff

mkPiLcd :: I2cHandle -> IO PiLcd
mkPiLcd h = do
  pe <- mkPortExpander (i2cReadReg h lcdAddr) (i2cWriteReg h lcdAddr)
  writeIoDir pe buttonMask allBits
  writeIPol  pe 0 allBits
  writeGpPu  pe buttonMask allBits
  return $ PiLcd pe

getButtons :: PiLcd -> IO Word8
getButtons lcd = do
  x <- readGpioA (plExpander lcd)
  return $ (x .&. buttonMaskA) `xor` buttonMaskA

setBacklightColor :: PiLcd -> Color -> IO ()
setBacklightColor lcd c =
  writeGpio (plExpander lcd) (colorValue c `xor` white) white
